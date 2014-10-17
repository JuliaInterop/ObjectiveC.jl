import Base: show, convert, super, methods

# Classes

immutable Class
  ptr::Ptr{Void}
  Class(ptr::Ptr{Void}) = new(ptr)
end

convert(::Type{Ptr{Void}}, class::Class) = class.ptr

function Class(name)
  ptr = ccall(:objc_getClass, Ptr{Void}, (Ptr{Cchar},),
              string(name))
  ptr == C_NULL && error("Couldn't find class $name")
  return Class(ptr)
end

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

class(obj) =
  ccall(:object_getClass, Ptr{Void}, (Ptr{Void},),
        obj) |> Class

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
