export @objc, @objcwrapper, @objcproperties, @objcblock, @objcdispatch
export KindOf, inherits_from


# Class hierarchy as a runtime trait
#
# Each `@objcwrapper Foo <: Bar` declaration emits `objc_parent(::Type{Foo}) = Bar`.
# `inherits_from(T, S)` walks the chain; the recursion is `@inline` and folds to a
# compile-time constant whenever T and S are statically known.

objc_parent(::Type{Object}) = nothing
objc_parent(::Type{<:Object}) = nothing   # fallback for classes declared without a `<: parent` clause

inherits_from(::Type, ::Type) = false
@inline function inherits_from(::Type{T}, ::Type{S}) where {T<:Object, S<:Object}
    T === S && return true
    P = objc_parent(T)
    P === nothing && return false
    inherits_from(P, S)
end


# `KindOf{T}` is a *marker* type used exclusively in `@objcdispatch` argument
# slots — it has no values. The macro substitutes it at expansion time with
# `Union{T, descendants(T)...}`, where descendants are enumerated by walking
# the `objc_parent` method table. The result is a regular Julia method on a
# concrete Union; dispatch goes through native multiple-dispatch with no
# wrapper, no forwarder, and no runtime `inherits_from` check.
#
# Modeled on ObjC's `__kindof T *` type qualifier (covariant subclass pointer).
struct KindOf{T<:Object} end

# Walk the `objc_parent` method table to enumerate every type that
# `inherits_from(T, P)`, including P itself. Used by `@objcdispatch` to expand
# `KindOf{P}` into a Union at macro-expansion time.
function objc_subtree(P::Type)
    P <: Object || return Type[P]
    result = Type[P]
    queue = Type[P]
    seen = Set{Type}((P,))
    while !isempty(queue)
        current = popfirst!(queue)
        for m in methods(objc_parent)
            sig = m.sig
            sig isa DataType && length(sig.parameters) >= 2 || continue
            tp = sig.parameters[2]
            tp isa DataType && tp <: Type || continue
            length(tp.parameters) == 1 || continue
            Sub = tp.parameters[1]
            Sub isa Type && Sub <: Object || continue
            Sub === Object && continue  # the `Type{Object}` and `Type{<:Object}` fallbacks
            Sub === current && continue  # skip self (would re-enqueue)
            objc_parent(Sub) === current || continue
            if !(Sub in seen)
                push!(seen, Sub)
                push!(result, Sub)
                push!(queue, Sub)
            end
        end
    end
    return result
end

# Resolve `KindOf{P}` to its dispatch type — `P` alone if no subclasses are
# wrapped, or `Union{P, descendants...}` otherwise.
function objc_kindof_type(P::Type)
    sub = objc_subtree(P)
    length(sub) == 1 ? sub[1] : Union{sub...}
end


# Per-parent registry of `@objcdispatch` call sites. Populated as a side
# effect of each `@objcdispatch` expansion (the macro emits a top-level
# `register_objcdispatch_site!`). Consulted by `@objcwrapper Sub <: Parent`
# to warn when a subclass is declared after methods on its ancestor —
# such methods will not dispatch on `Sub`, because their Union was frozen
# at the time `@objcdispatch` was processed.
const objcdispatch_sites = IdDict{Type, Vector{NamedTuple{(:name, :file, :line), Tuple{Symbol, String, Int}}}}()

function register_objcdispatch_site!(P::Type, name::Symbol, file::AbstractString, line::Integer)
    sites = get!(() -> NamedTuple{(:name, :file, :line), Tuple{Symbol, String, Int}}[], objcdispatch_sites, P)
    entry = (name=name, file=String(file), line=Int(line))
    entry in sites || push!(sites, entry)
    return
end

function warn_late_subclass(child::Type, parent::Type)
    p = parent
    while p isa Type && p <: Object
        if haskey(objcdispatch_sites, p)
            for site in objcdispatch_sites[p]
                @warn """`@objcwrapper $child <: $parent` declared after `@objcdispatch \
                         $(site.name)(::KindOf{$p}, …)` at $(site.file):$(site.line). \
                         The existing method will not dispatch on $child; redeclare the \
                         `@objcdispatch` after the `@objcwrapper`, or move the wrapper \
                         above the methods."""
            end
        end
        p === Object && break
        p = objc_parent(p)
    end
    return
end


# Tie `id{U}` → `id{T}` conversions to `inherits_from` whenever both are
# `<:Object`. Forward-declared in primitives.jl; the actual check lives here so
# it can use `inherits_from`.
compatible_id_types(::Type{T}, ::Type{U}) where {T<:Object, U<:Object} =
    inherits_from(U, T)


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

Define a Julia struct that wraps an Objective-C object pointer.

Each declaration generates a concrete `struct name <: Object` (or
`mutable struct` when `immutable=false`) holding a single `ptr::id{name}` field.
The Objective-C class hierarchy is recorded by emitting
`objc_parent(::Type{name}) = super` (defaulting to `Object`), which the
recursive `inherits_from` trait uses to model `<:`-style relationships at the
ObjC layer without forcing a Julia abstract type for each non-leaf class.

Methods can be written directly on the concrete struct (e.g.
`length(s::NSString) = ...`); polymorphic methods over an inheritance chain
should be expressed via [`@objcdispatch`](@ref).

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
        super = :Object
    else
        wrappererror()
    end

    # define the concrete struct. The constructor checks availability and rejects nil.
    structdef = if immutable
        quote
            struct $name <: $ObjectiveC.Object
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
            mutable struct $name <: $ObjectiveC.Object
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
        $(structdef.args...)

        # record the immediate ObjC parent for `inherits_from`.
        $ObjectiveC.objc_parent(::Type{$name}) = $super

        # default property forwarders. `@objcproperties` may override
        # `objc_getproperty`/`objc_setproperty!` per class to install
        # autoproperty branches; without that, the chain walks straight to the
        # parent via `objc_parent`, all the way up to `Object` where it falls
        # back to `getfield`/`setfield!`.
        Base.getproperty(object::$name, field::Symbol) =
            $ObjectiveC.objc_getproperty($name, object, field)
        Base.setproperty!(object::$name, field::Symbol, value::Any) =
            $ObjectiveC.objc_setproperty!($name, object, field, value)

        # Warn if any ancestor already has `@objcdispatch` methods — their
        # frozen Unions won't dispatch on us.
        $ObjectiveC.warn_late_subclass($name, $super)
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


"""
    @objcdispatch f(arg::KindOf{T}, more...)::ret begin
        # body — `arg` is typed as `Union{T, descendants(T)...}`
    end

Define a polymorphic Objective-C method on the class `T` and every currently
wrapped subclass of `T`. The macro substitutes `KindOf{T}` at expansion time
with `Union{T, descendants...}`, where descendants come from walking the
`objc_parent` method table. The result is a regular Julia method on a concrete
Union, dispatched natively — `typeof(arg)` inside the body is the concrete
subclass.

The substitution is frozen at macro expansion. **Wrappers must be declared
before any `@objcdispatch` method that should dispatch on them.** Declaring a
subclass via `@objcwrapper Sub <: Parent` *after* an `@objcdispatch` on
`KindOf{Parent}` will fire a warning; `Sub` won't flow through the existing
method until you redeclare it.

Modeled on Objective-C's `__kindof T *` type qualifier.
"""
macro objcdispatch(ex)
    # Accept `@objcdispatch @inline function ... end` style by unwrapping
    # leading macro decorators (e.g. `@inline`, `@noinline`).
    decorators = Any[]
    while Meta.isexpr(ex, :macrocall)
        # Drop the LineNumberNode in macrocalls (args[2])
        push!(decorators, ex.args[1])
        ex = ex.args[end]
    end

    Meta.isexpr(ex, :function) || Meta.isexpr(ex, :(=)) ||
        wrappererror("@objcdispatch expects a function definition")

    sig = ex.args[1]
    body = ex.args[2]

    # Peel off `f(...)::ret`
    rettype = nothing
    if Meta.isexpr(sig, :(::))
        rettype = sig.args[2]
        sig = sig.args[1]
    end

    # Peel off `where {T...}`
    whereparams = Any[]
    while Meta.isexpr(sig, :where)
        append!(whereparams, sig.args[2:end])
        sig = sig.args[1]
    end

    Meta.isexpr(sig, :call) || wrappererror("@objcdispatch expects a function-call signature")

    fname = sig.args[1]
    rawargs = sig.args[2:end]

    # Separate kwargs (Expr(:parameters, ...)) from positional args.
    kwparams = nothing
    args = Any[]
    for a in rawargs
        if Meta.isexpr(a, :parameters)
            kwparams = a
        else
            push!(args, a)
        end
    end
    isempty(args) && wrappererror("@objcdispatch needs at least one positional argument typed `KindOf{T}`")

    # Recognize `KindOf{T}` and any qualified form ending in `KindOf{T}`
    # (e.g. `ObjectiveC.KindOf{T}`, `OC.KindOf{T}`).
    function is_kindof_type(e)
        Meta.isexpr(e, :curly) || return false
        head = e.args[1]
        head === :KindOf && return true
        Meta.isexpr(head, :.) && head.args[2] === QuoteNode(:KindOf) && return true
        return false
    end

    # Locate the `KindOf{T}` argument; remember the type parameter T.
    iface_idx = nothing
    iface_T = nothing
    for (i, a) in enumerate(args)
        if Meta.isexpr(a, :(::)) && is_kindof_type(a.args[2])
            iface_idx = i
            iface_T = a.args[2].args[2]
            break
        end
    end
    iface_idx === nothing &&
        wrappererror("@objcdispatch needs one argument typed `KindOf{T}`")

    # Resolve T (the `KindOf{T}` parameter) in the user's module so we can
    # compute the dispatch Union at macroexpand time.
    P = try
        Core.eval(__module__, iface_T)
    catch err
        wrappererror("@objcdispatch could not resolve `$iface_T` (must be a wrapped class declared earlier): $err")
    end
    P isa Type && P <: Object ||
        wrappererror("@objcdispatch type parameter `$iface_T` must resolve to a subtype of `Object`, got $P")

    union_type = objc_kindof_type(P)

    # Substitute `KindOf{P}` with the Union at the matched arg slot.
    new_args = copy(args)
    iface_a = args[iface_idx]
    iface_arg_name = if Meta.isexpr(iface_a, :(::)) && length(iface_a.args) == 2
        iface_a.args[1]
    else
        gensym(:_)
    end
    new_args[iface_idx] = :( $iface_arg_name::$union_type )

    # Reconstruct the signature (with kwargs, where, ret).
    new_sig = Expr(:call, fname, new_args...)
    if kwparams !== nothing
        insert!(new_sig.args, 2, kwparams)
    end
    for tp in whereparams
        new_sig = Expr(:where, new_sig, tp)
    end
    if rettype !== nothing
        new_sig = Expr(:(::), new_sig, rettype)
    end

    method_def = Expr(:function, new_sig, body)
    for dec in reverse(decorators)
        method_def = Expr(:macrocall, dec, LineNumberNode(0), method_def)
    end

    # Register this call site so a later `@objcwrapper Sub <: P` can warn that
    # the Union is now stale.
    src_file = String(__source__.file)
    src_line = Int(__source__.line)
    fname_q = QuoteNode(fname isa Symbol ? fname : Symbol(fname))
    register_call = :( $ObjectiveC.register_objcdispatch_site!($P, $fname_q, $src_file, $src_line) )

    esc(quote
        Core.@__doc__ $method_def
        $register_call
    end)
end


# Property Accesors

objc_propertynames(::Type{<:Object}) = Symbol[]
objc_propertynames(::Nothing) = Symbol[]

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

    # generate Base.propertynames definition
    propertynames_ex = quote
        function $ObjectiveC.objc_propertynames(::Type{$(esc(typ))})
            properties = [$(map(QuoteNode, collect(propertynames))...)]
            parent = $ObjectiveC.objc_parent($(esc(typ)))
            if parent !== nothing
                properties = union(properties, $ObjectiveC.objc_propertynames(parent))
            end
            return properties
        end
        function Base.propertynames(::$(esc(typ)))
            $ObjectiveC.objc_propertynames($(esc(typ)))
        end
    end

    # generate `Base.getproperty` / `objc_getproperty` definitions.
    # We define `objc_getproperty(::Type{T}, obj, field)` rather than
    # `Base.getproperty` directly, so the ObjC parent chain can be walked at
    # runtime via `objc_parent` (replacing the old `invoke(getproperty,
    # supertype(T), ...)` chain). The wrapper `Base.getproperty(obj::T, field) =
    # objc_getproperty(T, obj, field)` is the user-facing entry. Julia
    # specializes `objc_getproperty` per concrete `obj` type at the call site
    # so type-stability is preserved through the chain.
    #
    # `obj` is intentionally left untyped — the same method must also serve
    # `KindOf{T}` wrappers, which are not `<:Object`.
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
            function $ObjectiveC.objc_getproperty(::Type{$(esc(typ))}, object, field::Symbol)
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
            function $ObjectiveC.objc_setproperty!(::Type{$(esc(typ))}, object,
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
