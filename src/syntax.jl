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

function objcm(mod, ex)
    # handle a single call, [dst method: param::typ]::typ

    # parse the call return type
    Meta.isexpr(ex, :(::)) || callerror("missing return type")
    call, rettyp = ex.args

    # we need the return type at macro definition time in order to determine the ABI
    rettyp = Base.eval(mod, rettyp)::Type

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
                obj = $(objcm(mod, obj))
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

# ensure that the GC can run during a ccall. this is only safe if callbacks
# into Julia transition back to GC-unsafe, which is the case on Julia 1.10+.
#
# doing so is tricky, because no GC operations are allowed after the transition,
# meaning we have to do our own argument conversion instead of relying on ccall.
#
# TODO: replace with JuliaLang/julia#49933 once merged
function make_gcsafe(ex)
    # decode the ccall
    if !Meta.isexpr(ex, :call) || ex.args[1] != :ccall
        error("Can only make ccall expressions GC-safe")
    end
    target = ex.args[2]
    rettyp = ex.args[3]
    argtypes = ex.args[4].args
    args = ex.args[5:end]

    code = quote
    end

    # assign argument values to variables
    vars = [Symbol("arg$i") for i in 1:length(args)]
    for (var, arg) in zip(vars, args)
        push!(code.args, :($var = $arg))
    end

    # convert the arguments
    converted = [Symbol("converted_arg$i") for i in 1:length(args)]
    for (converted, argtyp, var) in zip(converted, argtypes, vars)
        push!(code.args, :($converted = Base.unsafe_convert($argtyp, Base.cconvert($argtyp, $var))))
    end

    # emit a gcsafe ccall
    append!(code.args, (quote
        GC.@preserve $(vars...) begin
            gc_state = ccall(:jl_gc_safe_enter, Int8, ())
            ret = ccall($target, $rettyp, ($(argtypes...),), $(converted...))
            ccall(:jl_gc_safe_leave, Cvoid, (Int8,), gc_state)
            ret
        end
    end).args)

    return code
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
        ret = $(
            if ABI.use_stret(rettyp)
                # we follow Julia's ABI implementation,
                # so ccall will handle the sret box
                make_gcsafe(:(
                    ccall(:objc_msgSend_stret, $rettyp,
                          (Ptr{Cvoid}, Ptr{Cvoid}, $(map(esc, argtyps)...)),
                          class, sel, $(map(esc, argvals)...))
                ))
            else
                make_gcsafe(:(
                    ccall(:objc_msgSend, $rettyp,
                          (Ptr{Cvoid}, Ptr{Cvoid}, $(map(esc, argtyps)...)),
                          class, sel, $(map(esc, argvals)...))
                ))
            end
        )
        @static if $tracing
            if $rettyp !== Nothing
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
        ret = $(
            if ABI.use_stret(rettyp)
                # we follow Julia's ABI implementation,
                # so ccall will handle the sret box
                make_gcsafe(:(
                    ccall(:objc_msgSend_stret, $rettyp,
                          (id{Object}, Ptr{Cvoid}, $(map(esc, argtyps)...)),
                          $instance, sel, $(map(esc, argvals)...))
                ))
            else
                make_gcsafe(:(
                    ccall(:objc_msgSend, $rettyp,
                          (id{Object}, Ptr{Cvoid}, $(map(esc, argtyps)...)),
                          $instance, sel, $(map(esc, argvals)...))
                ))
            end
        )
        @static if $tracing
            if $rettyp !== Nothing
                Core.print(io, "  ")
                render(io, ret)
                Core.println(io)
            end
        end
        ret
    end
end

# TODO: support availability
macro objc(ex)
    objcm(__module__, ex)
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
  * `availability`: A `PlatformAvailability` object that represents the availability of the object.
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
    availability = nothing
    for kw in kwargs
        if kw isa Expr && kw.head == :(=)
            kw, value = kw.args
            if kw == :comparison
                value isa Bool || wrappererror("comparison keyword argument must be a literal boolean")
                comparison = value
            elseif kw == :immutable
                value isa Bool || wrappererror("immutable keyword argument must be a literal boolean")
                immutable = value
            elseif kw == :availability
                availability = get_avail_exprs(__module__, value)
            else
                wrappererror("unrecognized keyword argument: $kw")
            end
        else
            wrappererror("invalid keyword argument: $kw")
        end
    end
    immutable = something(immutable, true)
    comparison = something(comparison, !immutable)
    availability = something(availability, PlatformAvailability[])

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

        # add a pseudo constructor to the abstract type that also checks for nil pointers.
        function $name(ptr::id)
            @static if !ObjectiveC.is_available($availability)
                throw($UnavailableError(Symbol($name), $availability))
            end

            ptr == nil && throw(UndefRefError())
            $instance(ptr)
        end
    end

    # add optional methods
    if comparison
        ex = quote
            $(ex.args...)

            Base.:(==)(a::$instance, b::$instance) = pointer(a) == pointer(b)
            Base.hash(obj::$instance, h::UInt) = hash(pointer(obj), h)
        end
    end

    esc(ex)
end

Base.pointer(obj::Object) = obj.ptr

# when passing a single object, we automatically convert it to an object pointer
Base.unsafe_convert(T::Type{<:id}, obj::Object) = convert(T, pointer(obj))

# when passing an array of objects, perform recursive conversion to object pointers
# this is similar to Base.RefArray, which is used for conversion to regular pointers.
struct idArray{T}
    ids::Vector{id{T}}
    roots::Vector{<:Object}
end
Base.cconvert(T::Type{<:id}, objs::Vector{<:Object}) =
    idArray{eltype(T)}([pointer(obj) for obj in objs], objs)
Base.unsafe_convert(T::Type{<:id}, arr::idArray) =
    reinterpret(T, pointer(arr.ids))


# Property Accesors

objc_propertynames(obj::Type{<:Object}) = Symbol[]

propertyerror(s::String) = error("""Objective-C property declaration: $s.
                                    Refer to the @objcproperties docstring for more details.""")

"""
    @objcproperties ObjCType begin
        @autoproperty myProperty::ObjCType [type=JuliaType] [setter=setMyProperty] [getter=getMyProperty] [availability::PlatformAvailability]

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
  - `getter`: specifies the name of the Objective-C getter method. Without this, the
    getter method is assumed to be identical to the property.
  - `availability`: A `PlatformAvailability` object that represents the availability of the property.
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

    # collect property declarations
    properties = []
    function process_property(ex)
        isa(ex, LineNumberNode) && return
        Meta.isexpr(ex, :macrocall) || propertyerror("invalid property declaration $ex")

        # split the contained macrocall into its parts
        cmd = ex.args[1]
        args = []
        kwargs = Dict()
        for arg in ex.args[2:end]
            isa(arg, LineNumberNode) && continue
            if isa(arg, Expr) && arg.head == :(=)
                kwargs[arg.args[1]] = arg.args[2]
            else
                push!(args, arg)
            end
        end

        # if we're dealing with `@static`, so recurse into the block
        # TODO: liberally support all unknown macros?
        if cmd == Symbol("@static")
            ex = macroexpand(__module__, ex; recursive=false)
            if ex !== nothing
                process_property.(ex.args)
            end
        else
            push!(properties, (; cmd, args, kwargs))
        end
    end
    process_property.(ex.args)

    for (cmd, args, kwargs) in properties
        # there should only be a single positional argument,
        # containing the property name (and optionally its type)
        length(args) >= 1 || propertyerror("$cmd requires a positional argument")
        property_arg = popfirst!(args)
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

            # for getproperty, we call the code generator directly to avoid the need to
            # escape the return type, breaking `@objc`s ability to look up the type in the
            # caller's module and decide on the appropriate ABI. that necessitates use of
            # :hygienic-scope to handle the mix of esc/hygienic code.

            availability = nothing
            if haskey(kwargs, :availability)
                availability = get_avail_exprs(__module__, kwargs[:availability])
            end
            availability = something(availability, PlatformAvailability[])

            getterproperty = if haskey(kwargs, :getter)
                kwargs[:getter]
            else
                property
            end
            getproperty_ex = objcm(__module__, :([object::id{$(esc(typ))} $getterproperty]::$srcTyp))
            getproperty_ex = quote
                @static if !ObjectiveC.is_available($availability)
                    throw($UnavailableError(Symbol($(esc(typ)), ".", field), $availability))
                end
                value = $(Expr(:var"hygienic-scope", getproperty_ex, @__MODULE__, __source__))
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
            function_arg = popfirst!(args)
            read_properties[property] = quote
                f = $(esc(function_arg))
                f(object)
            end
        elseif cmd == Symbol("@setproperty!")
            haskey(write_properties, property) && propertyerror("duplicate property $property")
            function_arg = popfirst!(args)
            write_properties[property] = quote
                f = $(esc(function_arg))
                f(object, value)
            end
        else
            propertyerror("unrecognized property declaration $cmd")
        end

        isempty(args) || propertyerror("too many positional arguments")
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
        final = :(@inline invoke(getproperty,
                                 Tuple{supertype($(esc(typ))), Symbol},
                                 object, field))
        push!(current.args, final)
        getproperties_ex = quote
            # XXX: force const-prop on field, without inlining everything?
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
        final = :(@inline invoke(setproperty!,
                                 Tuple{supertype($(esc(typ))), Symbol, Any},
                                 object, field, value))
        push!(current.args, final)
        setproperties_ex = quote
            # XXX: force const-prop on field, without inlining everything?
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
