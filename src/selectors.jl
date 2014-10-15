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

macro sel_str(name)
  Selector(name)
end

name{T}(sel::Selector{T}) = T

function show(io::IO, sel::Selector)
  print(io, "sel")
  show(io, string(name(sel)))
end
