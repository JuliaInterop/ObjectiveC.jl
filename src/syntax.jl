export @objc, @objcwrapper, @objcproperties, @objcblock


# Method Calling

callerror(msg) = error("""ObjectiveC call: $msg
                          Use [obj method]::typ or [obj method :param::typ ...]::typ""")

# convert a vcat to a hcat so that we can split the @objc expressions into multiple lines
function flatvcat(ex::Expr)
  any(ex->Meta.isexpr(ex, :row), ex.args) || return ex
  flat = Expr(:hcat)
  for row in ex.args
    Meta.isexpr(row, :row) ?
      push!(flat.args, row.args...) :
      push!(flat.args, row)
  end
  return flat
end

function objcm(ex)
    # handle a single call, [dst method: param::typ]::typ

    # parse the call return type
    Meta.isexpr(ex, :(::)) || callerror("missing return type")
    call, rettyp = ex.args

    # parse the call
    if Meta.isexpr(call, :vcat)
      call = flatvcat(call)
    end
    Meta.isexpr(call, :hcat) || return esc(call)
    obj, method, args... = call.args

    # argument should be typed expressions
    argnames, argvals, argtyps = [], [], []
    function parse_argument(arg; named=true)
        # name before the parameter (name:value::type) is optional
        if Meta.isexpr(arg, :call) && arg.args[1] == :(:)
          # form: name:value::typ
          name = String(arg.args[2])
          arg = arg.args[3]
        else
          name = nothing
        end
        push!(argnames, name)

        Meta.isexpr(arg, :(::)) || callerror("missing argument type")
        value, typ = arg.args
        if value isa QuoteNode
            # nameless params are parsed as a symbol
            # (there's an edge case when using e.g. `:length(x)::typ`, causing the `length`
            #  to be parsed as a symbol, but you should just use a param name in that case)
            value = value.value
        end
        push!(argvals, value)
        push!(argtyps, typ)
    end

    # the method may be a plain symbol, or already contain the first arg
    if method isa Symbol
        argnames, argvals, argtyps = [], [], []
    elseif Meta.isexpr(method, :call) && method.args[1] == :(:)
        _, method, arg = method.args
        isa(method, Symbol) || callerror("method name must be a literal symbol")
        parse_argument(arg)
    else
        callerror("method name must be a literal")
    end

    # deconstruct the remaining arguments
    for arg in args
        # first arg should always be part of the method
        isempty(argnames) && callerror("first argument should be part of the method (i.e., don't use a space between the method and :param)")

        parse_argument(arg)
    end

    # with the method and all args known, we can determine the selector
    sel = String(method) * join(map(name->something(name,"")*":", argnames))

    # the object should be a class (single symbol) or an instance (var + typeassert)
    ex = if obj isa Symbol
        # class
        class_message(obj, sel, rettyp, argtyps, argvals)
    elseif Meta.isexpr(obj, :(::))
        # instance
        value, typ = obj.args
        if value isa Expr
            # possibly dealing with a nested expression, so recurse
            quote
                obj = $(objcm(obj))
                $(instance_message(:obj, esc(typ), sel, rettyp, argtyps, argvals))
            end
        else
            instance_message(esc(value), esc(typ), sel, rettyp, argtyps, argvals)
        end
    else
        callerror("object must be a class or typed instance")
    end

    return ex
end

# argument renderers, for tracing functionality
render(io, obj) = Core.print(io, repr(obj))
function render(io, ptr::id{T}) where T
  Core.print(io, "(id<", String(T.name.name), ">)0x", string(UInt(ptr), base=16, pad = Sys.WORD_SIZE>>2))
end
function render(io, ptr::Ptr{T}) where T
  Core.print(io, "(", String(T.name.name), "*)0x", string(UInt(ptr), base=16, pad = Sys.WORD_SIZE>>2))
end
## mimic ccall's conversion
function render_c_arg(io, obj, typ)
  GC.@preserve obj begin
    ptr = Base.unsafe_convert(typ, Base.cconvert(typ, obj))
    render(io, ptr)
  end
end

function class_message(class_name, msg, rettyp, argtyps, argvals)
    quote
        class = Class($(String(class_name)))
        sel = Selector($(String(msg)))
        @static if $tracing
            io = Core.stderr
            Core.print(io, "+ [", $(String(class_name)), " ", $(String(msg)))
            for (arg, typ) in zip([$(map(esc, argvals)...)], [$(map(esc, argtyps)...)])
                Core.print(io, " ")
                render_c_arg(io, arg, typ)
            end
            Core.println(io, "]")
        end
        ret = ccall(:objc_msgSend, $(esc(rettyp)),
                    (Ptr{Cvoid}, Ptr{Cvoid}, $(map(esc, argtyps)...)),
                    class, sel, $(map(esc, argvals)...))
        @static if $tracing
            if $(esc(rettyp)) !== Nothing
              Core.print(io, "  ")
              render(io, ret)
              Core.println(io)
            end
        end
        ret
    end
end

function instance_message(instance, typ, msg, rettyp, argtyps, argvals)
    # TODO: use the instance type `typ` to verify when in validation mode?
    quote
        sel = Selector($(String(msg)))
        @static if $tracing
            io = Core.stderr
            Core.print(io, "- [")
            render_c_arg(io, $instance, $typ)
            Core.print(io, " ", $(String(msg)))
            for (arg, typ) in zip([$(map(esc, argvals)...)], [$(map(esc, argtyps)...)])
                Core.print(io, " ")
                render_c_arg(io, arg, typ)
            end
            Core.println(io, "]")
        end
        ret = ccall(:objc_msgSend, $(esc(rettyp)),
                    (id{Object}, Ptr{Cvoid}, $(map(esc, argtyps)...)),
                    $instance, sel, $(map(esc, argvals)...))
        @static if $tracing
            if $(esc(rettyp)) !== Nothing
              Core.print(io, "  ")
              render(io, ret)
              Core.println(io)
            end
        end
        ret
    end
end

macro objc(ex)
  objcm(ex)
end


# Wrapper Classes

wrappererror(msg) = error("""ObjectiveC wrapper: $msg
                             Use `@objcwrapper Class` or `Class <: SuperType`; see `?@objcwrapper` for more details.""")

"""
    @objcwrapper [kwargs] name [<: super]

Helper macro to define a set of Julia classes for wrapping Objective-C pointers.

Because Objective-C supports multilevel inheritance, we cannot directly translate its
class model to Julia's. Instead, we define an abstract class `name` that implements the
requested hierarchy (extending `super`, which defaults to `Object`), along with an instance
class `$(name)Instance` that wraps an Objective-C pointer.

The split into two classes should not be visible to the end user. Methods should only ever
use the `name` class, both for dispatch purposes and when constructing objects.

In addition to this boilerplate, `@objcwrapper`'s code generation can be customized through
keyword arguments:

  * `immutable`: if `true` (default), define the instance class as an immutable. Should be
    disabled when you want to use finalizers.
  * `comparison`: if `true` (default `false`), define `==` and `hash` methods for the
    wrapper class. This should not be necessary when using an immutable struct, in which
    case the default `==` and `hash` methods are sufficient.
"""
macro objcwrapper(ex...)
  def = ex[end]
  kwargs = ex[1:end-1]

  # parse kwargs
  comparison = nothing
  immutable = nothing
  for kw in kwargs
    if kw isa Expr && kw.head == :(=)
      kw, value = kw.args
      if kw == :comparison
        value isa Bool || wrappererror("comparison keyword argument must be a literal boolean")
        comparison = value
      elseif kw == :immutable
        value isa Bool || wrappererror("immutable keyword argument must be a literal boolean")
        immutable = value
      else
        wrappererror("unrecognized keyword argument: $kw")
      end
    else
      wrappererror("invalid keyword argument: $kw")
    end
  end
  immutable = something(immutable, true)
  comparison = something(comparison, !immutable)

  # parse class definition
  if Meta.isexpr(def, :(<:))
    name, super = def.args
  elseif def isa Symbol
    name = def
    super = Object
  else
    wrappererror()
  end

  # generate type hierarchy
  ex = quote
    abstract type $name <: $super end
  end

  # generate the instance class
  instance = Symbol(name, "Instance")
  ex = if immutable
    quote
      $(ex.args...)
      struct $instance <: $name
        ptr::id{$name}
      end
    end
  else
    quote
      $(ex.args...)
      mutable struct $instance <: $name
        ptr::id{$name}
      end
    end
  end

  # add essential methods
  ex = quote
    $(ex.args...)

    Base.unsafe_convert(T::Type{<:id}, dev::$instance) = convert(T, dev.ptr)

    # add a pseudo constructor to the abstract type that also checks for nil pointers.
    function $name(ptr::id)
      ptr == nil && throw(UndefRefError())
      $instance(ptr)
    end
  end

  # add optional methods
  if comparison
    ex = quote
      $(ex.args...)

      Base.:(==)(a::$instance, b::$instance) = a.ptr == b.ptr
      Base.hash(dev::$instance, h::UInt) = hash(dev.ptr, h)
    end
  end

  esc(ex)
end


# Property Accesors

objc_propertynames(obj::Type{<:Object}) = Symbol[]

propertyerror(s::String) = error("""Objective-C property declaration: $s.
                                    Refer to the @objcproperties docstring for more details.""")

"""
    @objcproperties ObjCType begin
        @autoproperty myProperty::ObjCType [type=JuliaType] [setter=setMyProperty]

        @getproperty myProperty function(obj)
            ...
        end
        @setproperty! myProperty function(obj, value)
            ...
        end
    end

Helper macro for automatically generating definitions for the `propertynames`,
`getproperty`, and `setproperty!` methods for an Objective-C type. The first argument
`ObjCType` is the Julia type corresponding to the Objective-C type, and following block
contains a series of property declarations:

- `@autoproperty myProperty::ObjCType`: automatically generate a definition for accessing
  property `myProperty` that has Objective-C type `ObjCType` (typically a pointer type like
  `id{AnotherObjCType}`). Several keyword arguments are supported:
  - `type`: specifies the Julia type that the property value should be converted to by
    calling `convert(type, value)`. Note that this is not needed for `id{ObjCType}`
    properties, which are automatically converted to `ObjCType` objects (after a `nil`
    check, returning `nothing` if the check fails).
  - `setter`: specifies the name of the Objective-C setter method. Without this, no
    `setproperty!` definition will be generated.
- `@getproperty myProperty function(obj) ... end`: define a custom getter for the property.
  The function should take a single argument `obj`, which is the object that the property is
  being accessed on. The function should return the property value.
- `@setproperty! myProperty function(obj, value) ... end`: define a custom setter for the
  property. The function should take two arguments, `obj` and `value`, which are the object
  that the property is being set on, and the value that the property is being set to,
  respectively.
"""
macro objcproperties(typ, ex)
    isa(typ, Symbol) || propertyerror("expected a type name")
    Meta.isexpr(ex, :block) || propertyerror("expected a block of property declarations")

    propertynames = Set{Symbol}()
    read_properties = Dict{Symbol,Expr}()
    write_properties = Dict{Symbol,Expr}()

    for arg in ex.args
        isa(arg, LineNumberNode) && continue
        Meta.isexpr(arg, :macrocall) || propertyerror("invalid property declaration $arg")

        # split the contained macrocall into its parts
        cmd = arg.args[1]
        kwargs = Dict()
        positionals = []
        for arg in arg.args[2:end]
            isa(arg, LineNumberNode) && continue
            if isa(arg, Expr) && arg.head == :(=)
                kwargs[arg.args[1]] = arg.args[2]
            else
                push!(positionals, arg)
            end
        end

        # there should only be a single positional argument,
        # containing the property name (and optionally its type)
        length(positionals) >= 1 || propertyerror("$cmd requires a positional argument")
        property_arg = popfirst!(positionals)
        if property_arg isa Symbol
            property = property_arg
            srcTyp = nothing
        elseif Meta.isexpr(property_arg, :(::))
            property = property_arg.args[1]
            srcTyp = property_arg.args[2]
        else
            propertyerror("invalid property specification $(property_arg)")
        end
        push!(propertynames, property)

        # handle the various property declarations. this assumes :object and :value symbol
        # names for the arguments to `getproperty` and `setproperty!`, as generated below.
        if cmd == Symbol("@autoproperty")
            srcTyp === nothing && propertyerror("missing type for property $property")
            dstTyp = get(kwargs, :type, nothing)

            getproperty_ex = quote
                value = @objc [object::id{$(esc(typ))} $property]::$(esc(srcTyp))
            end

            # if we're dealing with a typed object pointer, do a nil check and create an object
            if Meta.isexpr(srcTyp, :curly) && srcTyp.args[1] == :id
                objTyp = srcTyp.args[2]
                append!(getproperty_ex.args, (quote
                    value == nil && return nothing
                    value = $(esc(objTyp))(value)
                end).args)
            end

            # convert the value, if necessary
            if dstTyp !== nothing
                append!(getproperty_ex.args, (quote
                    value = convert($(esc(dstTyp)), value)
                end).args)
            end

            push!(getproperty_ex.args, :(return value))

            haskey(read_properties, property) && propertyerror("duplicate property $property")
            read_properties[property] = getproperty_ex

            if haskey(kwargs, :setter)
                setproperty_ex = quote
                    @objc [object::id{$(esc(typ))} $(kwargs[:setter]):value::$(esc(srcTyp))]::Nothing
                end

                haskey(write_properties, property) && propertyerror("duplicate property $property")
                write_properties[property] = setproperty_ex
            end
        elseif cmd == Symbol("@getproperty")
            haskey(read_properties, property) && propertyerror("duplicate property $property")
            function_arg = popfirst!(positionals)
            read_properties[property] = quote
                f = $(esc(function_arg))
                f(object)
            end
        elseif cmd == Symbol("@setproperty!")
            haskey(write_properties, property) && propertyerror("duplicate property $property")
            function_arg = popfirst!(positionals)
            write_properties[property] = quote
                f = $(esc(function_arg))
                f(object, value)
            end
        else
            propertyerror("unrecognized property declaration $cmd")
        end

        isempty(positionals) || propertyerror("too many positional arguments")
    end

    # generate Base.propertynames definition
    propertynames_ex = quote
        function $ObjectiveC.objc_propertynames(::Type{$(esc(typ))})
            properties = [$(map(QuoteNode, collect(propertynames))...)]
            if supertype($(esc(typ))) != Any
                properties = union(properties, $ObjectiveC.objc_propertynames(supertype($(esc(typ)))))
            end
            return properties
        end
        function Base.propertynames(::$(esc(typ)))
          $ObjectiveC.objc_propertynames($(esc(typ)))
        end
    end

    # generate `Base.getproperty` definition, if needed
    getproperties_ex = quote end
    if !isempty(read_properties)
      current = nothing
      for (property, body) in read_properties
          test = :(field === $(QuoteNode(property)))
          if current === nothing
              current = Expr(:if, test, body)
              getproperties_ex = current
          else
              new = Expr(:elseif, test, body)
              push!(current.args, new)
              current = new
          end
      end

      # finally, call our parent's `getproperty`
      final = :(invoke(getproperty, Tuple{supertype($(esc(typ))), Symbol}, object, field))
      if VERSION >= v"1.8"
        push!(current.args, :(@inline $final))
      else
        push!(current.args, :($final))
      end
      getproperties_ex = quote
          function Base.getproperty(object::$(esc(typ)), field::Symbol)
            $getproperties_ex
          end
      end
    end

    # generate `Base.setproperty!` definition, if needed
    setproperties_ex = quote end
    if !isempty(write_properties)
      current = nothing
      for (property, body) in write_properties
          test = :(field === $(QuoteNode(property)))
          if current === nothing
              current = Expr(:if, test, body)
              setproperties_ex = current
          else
              new = Expr(:elseif, test, body)
              push!(current.args, new)
              current = new
          end
      end

      # finally, call our parent's `setproperty!`
      final = :(invoke(setproperty!,
                       Tuple{supertype($(esc(typ))), Symbol, Any},
                       object, field, value))
      if VERSION >= v"1.8"
        push!(current.args, :(@inline $final))
      else
        push!(current.args, :($final))
      end
      setproperties_ex = quote
          function Base.setproperty!(object::$(esc(typ)), field::Symbol, value::Any)
            $setproperties_ex
          end
      end
    end

    return quote
        $(propertynames_ex.args...)
        $(getproperties_ex.args...)
        $(setproperties_ex.args...)
    end
end
