export Selector, Class, Object

# Selectors

selname(s::Ptr{Nothing}) =
  ccall(:sel_getName, Ptr{Cchar}, (Ptr{Nothing},),
        s) |> unsafe_string

struct Selector
  ptr::Ptr{Nothing}
  Selector(ptr::Ptr{Nothing}) = new(ptr)
end

unsafe_convert(::Type{Ptr{Nothing}}, sel::Selector) = sel.ptr

function Selector(name)
  Selector(ccall(:sel_registerName, Ptr{Nothing}, (Ptr{Cchar},),
                 pointer(string(name))))
end

macro sel_str(name)
  Selector(name)
end

name(sel::Selector) = selname(sel.ptr)

function show(io::IO, sel::Selector)
  print(io, "sel")
  show(io, string(name(sel)))
end

# Classes

struct Class
  ptr::Ptr{Nothing}
  Class(ptr::Ptr{Nothing}) = new(ptr)
end

unsafe_convert(::Type{Ptr{Nothing}}, class::Class) = class.ptr

classptr(name) = ccall(:objc_getClass, Ptr{Nothing}, (Ptr{Cchar},),
                       pointer(string(name)))

function Class(name)
  ptr = classptr(name)
  ptr == C_NULL && error("Couldn't find class $name")
  return Class(ptr)
end

classexists(name) = classptr(name) ≠ C_NULL

name(class::Class) =
  ccall(:class_getName, Ptr{Cchar}, (Ptr{Nothing},),
            class) |> unsafe_string |> Symbol

ismeta(class::Class) =
  ccall(:class_isMetaClass, Cint, (Ptr{Nothing},),
        class) |> int2bool

function super(class::Class)
  ptr = ccall(:class_getSuperclass, Ptr{Nothing}, (Ptr{Nothing},),
              class.ptr)
  ptr == C_NULL && return nothing
  Class(ptr)
end

function show(io::IO, class::Class)
  ismeta(class) && print(io, "^")
  print(io, name(class))
end

function methods(class::Class)
  count = Cuint[0]
  meths = ccall(:class_copyMethodList, Ptr{Ptr{Nothing}}, (Ptr{Nothing}, Ptr{Cuint}),
                class, count)
  meths′ = [unsafe_load(meths, i) for i = 1:count[1]]
  c_free(meths)
  meths = [ccall(:method_getName, Ptr{Nothing}, (Ptr{Nothing},), meth) for meth in meths′]
  return map(meth->selname(meth), meths)
end

# Objects

mutable struct Object
  ptr::Ptr{Nothing}
end

unsafe_convert(::Type{Ptr{Nothing}}, obj::Object) = obj.ptr

class(obj) =
  ccall(:object_getClass, Ptr{Nothing}, (Ptr{Nothing},),
        obj) |> Class

methods(obj::Object) = methods(class(obj))

show(io::IO, obj::Object) = print(io, class(obj), " Object")
