export YES, NO, @sel_str, Selector, Class, class, Protocol, Object, id, nil

const YES = true
const NO  = false


# Selectors

selname(s::Ptr{Cvoid}) =
    ccall(:sel_getName, Ptr{Cchar}, (Ptr{Cvoid},), s) |> unsafe_string

struct Selector
    ptr::Ptr{Cvoid}
    Selector(ptr::Ptr{Cvoid}) = new(ptr)
end

Base.unsafe_convert(::Type{Ptr{Cvoid}}, sel::Selector) = sel.ptr

function Selector(name)
    Selector(ccall(:sel_registerName, Ptr{Cvoid}, (Ptr{Cchar},), name))
end

macro sel_str(name)
    Selector(name)
end

name(sel::Selector) = selname(sel.ptr)

function Base.show(io::IO, sel::Selector)
    print(io, "sel")
    show(io, string(name(sel)))
end


# Classes

struct Class
    ptr::Ptr{Cvoid}
    Class(ptr::Ptr{Cvoid}) = new(ptr)
end

Base.unsafe_convert(::Type{Ptr{Cvoid}}, class::Class) = class.ptr

classptr(name) = ccall(:objc_getClass, Ptr{Cvoid}, (Ptr{Cchar},), name)

function Class(name)
    ptr = classptr(name)
    ptr == C_NULL && error("Couldn't find class $name")
    return Class(ptr)
end

classexists(name) = classptr(name) ≠ C_NULL

name(class::Class) =
    ccall(:class_getName, Ptr{Cchar}, (Ptr{Cvoid},),
              class) |> unsafe_string |> Symbol

ismeta(class::Class) = ccall(:class_isMetaClass, Bool, (Ptr{Cvoid},), class)

function Base.supertype(class::Class)
    ptr = ccall(:class_getSuperclass, Ptr{Cvoid}, (Ptr{Cvoid},),
                class.ptr)
    ptr == C_NULL && return nothing
    Class(ptr)
end

function Base.show(io::IO, class::Class)
    ismeta(class) && print(io, "^")
    print(io, name(class))
end

function Base.methods(class::Class)
    count = Cuint[0]
    meths = ccall(:class_copyMethodList, Ptr{Ptr{Cvoid}}, (Ptr{Cvoid}, Ptr{Cuint}),
                  class, count)
    meths′ = [unsafe_load(meths, i) for i = 1:count[1]]
    Libc.free(meths)
    meths = [ccall(:method_getName, Ptr{Cvoid}, (Ptr{Cvoid},), meth) for meth in meths′]
    return map(meth->selname(meth), meths)
end


# Protocols

struct Protocol
    ptr::Ptr{Cvoid}
    Protocol(ptr::Ptr{Cvoid}) = new(ptr)
end

Base.unsafe_convert(::Type{Ptr{Cvoid}}, proto::Protocol) = proto.ptr

protoptr(name) = ccall(:objc_getProtocol, Ptr{Cvoid}, (Ptr{Cchar},), name)

function Protocol(name)
    ptr = protoptr(name)
    ptr == C_NULL && error("Couldn't find proto $name")
    return Protocol(ptr)
end

protoexists(name) = protoptr(name) ≠ C_NULL

name(proto::Protocol) =
    ccall(:protocol_getName, Ptr{Cchar}, (Ptr{Cvoid},),
              proto) |> unsafe_string |> Symbol

function Base.show(io::IO, proto::Protocol)
    print(io, name(proto))
end


# Object Pointer

if sizeof(Ptr{Cvoid}) == 8
    primitive type id{T} 64 end
else
    primitive type id{T} 32 end
end

# constructor
id{T}(x::Union{Int,UInt,id}) where {T} = Base.bitcast(id{T}, x)

# getters
Base.eltype(::Type{<:id{T}}) where {T} = T

# comparison
Base.:(==)(x::id, y::id) = Base.bitcast(UInt, x) == Base.bitcast(UInt, y)
## refuse comparison with unrelated pointer types
Base.:(==)(x::id, y::Ptr) = throw(ArgumentError("Cannot compare id with Ptr"))
Base.:(==)(x::Ptr, y::id) = throw(ArgumentError("Cannot compare id with Ptr"))

# conversion between pointers: refuse to convert between unrelated types
function Base.convert(::Type{id{T}}, x::id{U}) where {T,U}
    # nil is an exception (we want to be able to use `nil` in `@objc` directly)
    x == nil && return Base.bitcast(id{T}, nil)
    # otherwise, types must match (i.e., only allow converting to a supertype)
    U <: T || throw(ArgumentError("Cannot convert id{$U} to id{$T}"))
    Base.bitcast(id{T}, x)
end

# conversion to integer
Base.Int(x::id)  = Base.bitcast(Int, x)
Base.UInt(x::id) = Base.bitcast(UInt, x)

# `reinterpret` can be used to force conversion, typically from untyped `id{Object}`
Base.reinterpret(::Type{id{T}}, x::id) where {T} = Base.bitcast(id{T}, x)

# defer conversions from objects to `unsafe_convert`
Base.cconvert(::Type{<:id}, x) = x

# fallback for `unsafe_convert`
Base.unsafe_convert(::Type{P}, x::id) where {P<:id} = convert(P, x)


# Objects

# Object is an abstract type, so that we can define subtypes with constructors.
# The expected interface is that any subtype of Object should be convertible to id.

abstract type Object end
# interface: subtypes of Object should be convertible to `id`s
#            (i.e., `Base.unsafe_convert(::Type{id}, ::MyObj)`)

const nil = id{Object}(0)

# for convenience, make `reinterpret` work on object output types as well
Base.reinterpret(::Type{T}, x::id) where {T<:Object} = T(Base.bitcast(id{T}, x))

class(obj::Union{Object,id}) =
    ccall(:object_getClass, Ptr{Cvoid}, (id{Object},), obj) |> Class

Base.methods(obj::Union{Object,id}) = methods(class(obj))

Base.show(io::IO, obj::T) where {T <: Object} = print(io, "$T (object of type ", class(obj), ")")

struct UnknownObject <: Object
    ptr::id
    UnknownObject(ptr::id) = new(ptr)
end
Base.unsafe_convert(T::Type{<:id}, obj::UnknownObject) = convert(T, obj.ptr)
Object(ptr::id) = UnknownObject(ptr)
