module ObjectiveC

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
#   while !((parent = super(class)) in (nothing, class))
#     print(io, " <: ")
#     show(io, parent)
#     class = parent
#   end
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

# Messages

selname(s::Ptr{Void}) =
  ccall(:sel_getName, Ptr{Cchar}, (Ptr{Void},),
        s) |> bytestring

immutable Selector{name}
  ptr::Ptr{Void}
  Selector(ptr::Ptr{Void}) = new(ptr)
end

Selector(name::Symbol, ptr::Ptr{Void}) = Selector{name}(ptr)
Selector(ptr::Ptr{Void}) = Selector(symbol(selname(ptr)), ptr)

convert(::Type{Ptr{Void}}, sel::Selector) = sel.ptr

function Selector(name)
  Selector(symbol(name),
           ccall(:sel_registerName, Ptr{Void}, (Ptr{Cchar},),
                 string(name)))
end

name{T}(sel::Selector{T}) = T

function show(io::IO, sel::Selector)
  print(io, "Selector $(name(sel))")
end

# Objects

immutable Object{T}
  ptr::Ptr{Void}
end

convert(::Type{Ptr{Void}}, obj::Object) = obj.ptr

Object(p::Ptr{Void}) = Object{name(class(p))}(p)

objc_msgsend(obj, sel) = ccall(:objc_msgSend, Ptr{Void}, (Ptr{Void}, Ptr{Void}),
                               obj, sel)

msg(obj, sel; ret = Object) =
  objc_msgsend(obj, Selector(sel)) |> ret

# Import some classes

for c in (:NSObject, :NSString, :NSArray)
  @eval const $c = Class($(Expr(:quote, c)))
end

# methods(NSString)

# methods(class(NSString))

# class(NSString)

# :[NSString initWithRed: 1 green: 2 blue: 4]

end
