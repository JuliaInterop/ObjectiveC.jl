function allocclass(name, super)
  ptr = ccall(:objc_allocateClassPair, Ptr{Void}, (Ptr{Void}, Ptr{Cchar}, Csize_t),
              super, name, 0)
end

ctype(Object)

# Syntax

param(ex) =
  isexpr(ex, :(::)) ? ex.args[1] : ex

params(ex) =
  map(param, ex.args[2:end])

typehint(ex) =
  isexpr(ex, :(::)) ? ex.args[2] : :Any

typehints(ex) =
  map(typehint, ex.args[2:end])

macro ocimp (func)
  params(func.args[1]), typehints(func.args[1])
end

@ocimp function foo(x, y::Int)
  x+y
end
