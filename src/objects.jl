immutable Object{T}
  ptr::Ptr{Void}
end

convert(::Type{Ptr{Void}}, obj::Object) = obj.ptr

class(obj) =
  ccall(:object_getClass, Ptr{Void}, (Ptr{Void},),
        obj) |> Class

Object(p::Ptr{Void}) = Object{name(class(p))}(p)

show{T}(io::IO, obj::Object{T}) = print(io, T, " Object")
