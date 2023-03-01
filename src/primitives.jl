export @sel_str, Selector, Class, Object

# Selectors

selname(s::Ptr{Cvoid}) =
  ccall(:sel_getName, Ptr{Cchar}, (Ptr{Cvoid},),
        s) |> unsafe_string

struct Selector
  ptr::Ptr{Cvoid}
  Selector(ptr::Ptr{Cvoid}) = new(ptr)
end

Base.unsafe_convert(::Type{Ptr{Cvoid}}, sel::Selector) = sel.ptr

function Selector(name)
  Selector(ccall(:sel_registerName, Ptr{Cvoid}, (Ptr{Cchar},),
                 pointer(string(name))))
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

classptr(name) = ccall(:objc_getClass, Ptr{Cvoid}, (Ptr{Cchar},),
                       pointer(string(name)))

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

mutable struct Object
  ptr::Ptr{Cvoid}
end

Base.unsafe_convert(::Type{Ptr{Cvoid}}, obj::Object) = obj.ptr

class(obj) =
  ccall(:object_getClass, Ptr{Cvoid}, (Ptr{Cvoid},),
        obj) |> Class

Base.methods(obj::Object) = methods(class(obj))

Base.show(io::IO, obj::Object) = print(io, "Object{", class(obj), "}")
