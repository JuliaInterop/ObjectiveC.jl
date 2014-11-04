export Selector, Class, Object

# Selectors

selname(s::Ptr{Void}) =
  ccall(:sel_getName, Ptr{Cchar}, (Ptr{Void},),
        s) |> bytestring

immutable Selector
  ptr::Ptr{Void}
  Selector(ptr::Ptr{Void}) = new(ptr)
end

convert(::Type{Ptr{Void}}, sel::Selector) = sel.ptr

function Selector(name)
  Selector(ccall(:sel_registerName, Ptr{Void}, (Ptr{Cchar},),
                 string(name)))
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

immutable Class
  ptr::Ptr{Void}
  Class(ptr::Ptr{Void}) = new(ptr)
end

convert(::Type{Ptr{Void}}, class::Class) = class.ptr

classptr(name) = ccall(:objc_getClass, Ptr{Void}, (Ptr{Cchar},),
                       string(name))

function Class(name)
  ptr = classptr(name)
  ptr == C_NULL && error("Couldn't find class $name")
  return Class(ptr)
end

classexists(name) = classptr(name) ≠ C_NULL

name(class::Class) =
  ccall(:class_getName, Ptr{Cchar}, (Ptr{Void},),
            class) |> bytestring |> symbol

ismeta(class::Class) =
  ccall(:class_isMetaClass, Cint, (Ptr{Void},),
        class) |> bool

function super(class::Class)
  ptr = ccall(:class_getSuperclass, Ptr{Void}, (Ptr{Void},),
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
  meths = ccall(:class_copyMethodList, Ptr{Ptr{Void}}, (Ptr{Void}, Ptr{Cuint}),
                class, count)
  meths′ = [unsafe_load(meths, i) for i = 1:count[1]]
  c_free(meths)
  meths = [ccall(:method_getName, Ptr{Void}, (Ptr{Void},), meth) for meth in meths′]
  return map(meth->selname(meth), meths)
end

# Objects

type Object
  ptr::Ptr{Void}
end

convert(::Type{Ptr{Void}}, obj::Object) = obj.ptr

class(obj) =
  ccall(:object_getClass, Ptr{Void}, (Ptr{Void},),
        obj) |> Class

methods(obj::Object) = methods(class(obj))

show(io::IO, obj::Object) = print(io, class(obj), " Object")

release(obj) = @objc [obj release]

function Base.gc(obj::Object)
  finalizer(obj, release)
  obj
end
