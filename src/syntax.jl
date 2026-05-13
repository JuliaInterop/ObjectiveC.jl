export @objc, @objcwrapper, @objcproperties, @objcblock


# `Object` is parameterized by its `Kind` (declared in primitives.jl). Each
# `@objcwrapper Foo <: Bar` emits an abstract `FooKind <: BarKind`, a concrete
# `struct Foo <: Object{FooKind}`, and a `const FooLike = Object{<:FooKind}`
# alias. Polymorphic methods are written `f(x::FooLike) = …` — ordinary Julia
# subtyping then matches `Foo` and every wrapped subclass.

# `objc_parent` walks the wrapper hierarchy for `@objcproperties`'s property
# chain (which inherits ancestors' getters/setters).
objc_parent(::Type{<:Object}) = nothing


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
# `Object` is a UnionAll (`Object{K}`), so `id{Object}` has `T === Object` as a
# UnionAll value without a `.name` slot. Strip to the underlying DataType where
# possible, otherwise fall back to `nameof`.
_type_short_name(T::DataType) = String(T.name.name)
_type_short_name(T::UnionAll) = _type_short_name(Base.unwrap_unionall(T))
_type_short_name(T) = string(nameof(T))
function render(io, ptr::id{T}) where T
    Core.print(io, "(id<", _type_short_name(T), ">)0x", string(UInt(ptr), base=16, pad = Sys.WORD_SIZE>>2))
end
function render(io, ptr::Ptr{T}) where T
    Core.print(io, "(", _type_short_name(T), "*)0x", string(UInt(ptr), base=16, pad = Sys.WORD_SIZE>>2))
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

Define a Julia struct that wraps an Objective-C object pointer.

Each declaration generates three names:

  * an abstract `nameKind <: superKind` in a parallel lattice mirroring the
    ObjC class hierarchy;
  * a concrete `struct name <: Object{nameKind}` (or `mutable struct` when
    `immutable=false`) holding a single `ptr::id{name}` field;
  * a `const nameLike = Object{<:nameKind}` alias for use in polymorphic
    method signatures (not exported — it's a tool for writing methods, not
    part of the user-facing API).

Methods on the concrete leaf are monomorphic: `f(x::name)` will *not* match a
later `@objcwrapper Sub <: name`. Write polymorphic methods against the
`Like` alias instead:

```julia
release(obj::NSObjectLike) = @objc [obj::id{NSObject} release]::Cvoid
```

Plain leaf methods are appropriate when the class has no wrapped subclasses,
or when you specifically want to refuse them.

Keyword arguments:

  * `immutable`: if `true` (default), define the wrapper as an immutable struct.
    Should be disabled when you want to attach finalizers (e.g., for objects
    that need explicit `release`).
  * `availability`: a `PlatformAvailability` describing the OS/version
    availability of the class.
  * `comparison`: if `true` (default `false`), define `==` and `hash` for the
    wrapper class. Mostly useful for `mutable struct` wrappers.
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
        # qualified so `@objcwrapper Foo` works even without `using ObjectiveC`
        super = :($ObjectiveC.Object)
    else
        wrappererror()
    end

    # The parallel `${name}Kind` lives *next to* the struct (rather than as a
    # separate trait function): the struct's supertype embeds it directly via
    # `Object{$kindname}`. The Kind type itself must be declared before the
    # struct because the supertype clause references it; the super's Kind has
    # to exist already (same ordering rule the old design imposed via
    # `<:Object`).
    kindname = Symbol(name, "Kind")
    likename = Symbol(name, "Like")

    # define the concrete struct. The constructor checks availability and rejects nil.
    structdef = if immutable
        quote
            struct $name <: $ObjectiveC.Object{$kindname}
                ptr::$ObjectiveC.id{$name}
                function $name(ptr::$ObjectiveC.id)
                    @static if !$ObjectiveC.is_available($availability)
                        throw($UnavailableError(Symbol($(QuoteNode(name))), $availability))
                    end
                    ptr == $ObjectiveC.nil && throw(UndefRefError())
                    new(ptr)
                end
            end
        end
    else
        quote
            mutable struct $name <: $ObjectiveC.Object{$kindname}
                ptr::$ObjectiveC.id{$name}
                function $name(ptr::$ObjectiveC.id)
                    @static if !$ObjectiveC.is_available($availability)
                        throw($UnavailableError(Symbol($(QuoteNode(name))), $availability))
                    end
                    ptr == $ObjectiveC.nil && throw(UndefRefError())
                    new(ptr)
                end
            end
        end
    end

    ex = quote
        # Kind has to come *before* the struct definition so the supertype
        # clause `Object{$kindname}` can resolve it.
        abstract type $kindname <: $ObjectiveC.classkind($super) end

        $(structdef.args...)

        # Polymorphic alias: `Object{<:$kindname}` matches the concrete leaf
        # and every wrapped subclass via native Julia subtyping. Not
        # exported — like `$kindname`, it's an implementation aid for
        # *writing* methods, not part of the user-facing API.
        const $likename = $ObjectiveC.Object{<:$kindname}

        # `classkind(::Type{$name})` falls through to the generic
        # `classkind(::Type{<:Object{K}})` method declared in syntax.jl; no
        # per-class definition needed.

        # record the immediate ObjC parent for the property-dispatch chain.
        $ObjectiveC.objc_parent(::Type{$name}) = $super

        # default property forwarders. `@objcproperties` may override
        # `objc_getproperty`/`objc_setproperty!` per class to install
        # autoproperty branches; without that, the chain walks straight to the
        # parent via `objc_parent`, all the way up to `Object` where it falls
        # back to `getfield`/`setfield!`. `propertynames` follows the same
        # chain via `objc_propertynames` so children without their own
        # `@objcproperties` block still surface their ancestors' properties.
        Base.getproperty(object::$name, field::Symbol) =
            $ObjectiveC.objc_getproperty($name, object, field)
        Base.setproperty!(object::$name, field::Symbol, value::Any) =
            $ObjectiveC.objc_setproperty!($name, object, field, value)
        Base.propertynames(::$name) = $ObjectiveC.objc_propertynames($name)
    end

    # add optional methods
    if comparison
        ex = quote
            $(ex.args...)

            Base.:(==)(a::$name, b::$name) = pointer(a) == pointer(b)
            Base.hash(obj::$name, h::UInt) = hash(pointer(obj), h)
        end
    end

    esc(ex)
end

# Use `getfield` to bypass any user-defined `getproperty` (e.g., from
# `@objcproperties`) when accessing the pointer slot.
Base.pointer(obj::Object) = getfield(obj, :ptr)

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

# Default `objc_propertynames` walks the ObjC parent chain. `@objcproperties`
# emits a more specific method per class that merges the class's own list
# with the parent's; without that method, this fallback ensures a child
# wrapper still surfaces its ancestor's properties.
@inline objc_propertynames(::Type{T}) where {T<:Object} =
    objc_propertynames(objc_parent(T))
@inline objc_propertynames(::Nothing) = Symbol[]

# Generic property accessors used by `@objcproperties`-generated dispatch.
# When a class has no override, walk the Objective-C parent chain. The chain
# bottoms out at `nothing` (the sentinel returned by `objc_parent(::Type{Object})`),
# at which point we fall back to the default `getfield`/`setfield!`.
@inline objc_getproperty(::Nothing, obj, field::Symbol) = getfield(obj, field)
@inline objc_getproperty(::Type{T}, obj, field::Symbol) where {T<:Object} =
    objc_getproperty(objc_parent(T), obj, field)
@inline objc_setproperty!(::Nothing, obj, field::Symbol, value) =
    setfield!(obj, field, value)
@inline objc_setproperty!(::Type{T}, obj, field::Symbol, value) where {T<:Object} =
    objc_setproperty!(objc_parent(T), obj, field, value)

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

    # Generate the per-class `objc_propertynames`. `Base.propertynames` is
    # already emitted by `@objcwrapper` and routes through this method.
    propertynames_ex = quote
        function $ObjectiveC.objc_propertynames(::Type{$(esc(typ))})
            properties = [$(map(QuoteNode, collect(propertynames))...)]
            parent = $ObjectiveC.objc_parent($(esc(typ)))
            if parent !== nothing
                properties = union(properties, $ObjectiveC.objc_propertynames(parent))
            end
            return properties
        end
    end

    # generate `Base.getproperty` / `objc_getproperty` definitions. We define
    # `objc_getproperty(::Type{T}, obj, field)` rather than `Base.getproperty` directly, so
    # the ObjC parent chain can be walked at runtime via `objc_parent`. The wrapper
    # `Base.getproperty(obj::T, field) = objc_getproperty(T, obj, field)` is the user-facing
    # entry. The per-class method is `@inline`d so a literal `obj.length` propagates the
    # field symbol through both forwarders, letting Julia fold the `if field === :length`
    # cascade and infer the precise return type (without it, the body's return type degrades
    # to the Union of every property type in the ancestor chain).
    #
    # `object` is intentionally left untyped. The parent-chain walk forwards a subclass
    # instance to the parent's `objc_getproperty(::Type{Parent}, object, field)`, but the
    # concrete wrappers are flat leaves, so the subclass is *not* `<:Parent` — typing the
    # slot on `Parent` would fail to dispatch.
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

        # fall through to the ObjC parent chain
        final = :(return $ObjectiveC.objc_getproperty(
                    $ObjectiveC.objc_parent($(esc(typ))), object, field))
        push!(current.args, final)
        getproperties_ex = quote
            @inline function $ObjectiveC.objc_getproperty(::Type{$(esc(typ))}, object, field::Symbol)
                $getproperties_ex
            end
        end
    end

    # generate `Base.setproperty!` / `objc_setproperty!` definitions
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

        # fall through to the ObjC parent chain
        final = :(return $ObjectiveC.objc_setproperty!(
                    $ObjectiveC.objc_parent($(esc(typ))), object, field, value))
        push!(current.args, final)
        setproperties_ex = quote
            @inline function $ObjectiveC.objc_setproperty!(::Type{$(esc(typ))}, object,
                                                            field::Symbol, value::Any)
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
