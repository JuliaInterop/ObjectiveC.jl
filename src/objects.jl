immutable Object{T}
  ptr::Ptr{Void}
end

convert(::Type{Ptr{Void}}, obj::Object) = obj.ptr

Object(p::Ptr{Void}) = Object{name(class(p))}(p)

objc_msgsend(obj, sel) = ccall(:objc_msgSend, Ptr{Void}, (Ptr{Void}, Ptr{Void}),
                               obj, sel)

message(obj, sel) = objc_msgsend(obj, sel)
