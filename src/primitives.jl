export YES, NO, @sel_str, Selector, Class, class, Object, id, nil

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

ismeta(class::Class) =
  ccall(:class_isMetaClass, Cint, (Ptr{Cvoid},),
        class) |> int2bool

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


# Objects

# Object is an abstract type, so that we can define subtypes with constructors.
# The expected interface is that any subtype of Object should be convertible to id.

abstract type OpaqueObject end
const id = Ptr{OpaqueObject}

const nil = id(C_NULL)

abstract type Object end
# interface: subtypes of Object should be convertible to `id`s
#            (i.e., `Base.unsafe_convert(::Type{id}, ::MyObj)`)

class(obj::Union{Object,id}) =
  ccall(:object_getClass, Ptr{Cvoid}, (id,), obj) |> Class

Base.methods(obj::Union{Object,id}) = methods(class(obj))

Base.show(io::IO, obj::T) where {T <: Object} = print(io, "$T (object of type ", class(obj), ")")

struct UnknownObject <: Object
  ptr::id
  UnknownObject(ptr::id) = new(ptr)
end
Base.unsafe_convert(::Type{id}, obj::UnknownObject) = obj.ptr
Object(ptr::id) = UnknownObject(ptr)
