# ccal
# This is basically a horrible hack around not being able to call C
# varargs functions. Emulates `ccall` but as a function taking a function
# pointer + types, args etc.

Base.eltype{T}(::Type{Type{T}}) = T

stagedfunction ccal(f::Ptr, t, ts, vals...)
  R = eltype(t)
  AS = Expr(:tuple, eltype(ts)...)
  args = map(x->gensym(), vals)
  quote
    let
      $(Expr(:tuple, args...)) = vals
      ccall(f, $R, $AS, $(args...))
    end
  end
end

# Calls

ctype(x) = x
ctype(o::Type{Object}) = Ptr{Void}
ctype(s::Type{Selector}) = Ptr{Void}
ctype(a::AbstractArray) = map(ctype, a)

const cmsgsend = cglobal(:objc_msgSend)

function message(obj, sel, args...)
  clarse = class(obj)
  m = method(clarse, sel)
  m == C_NULL && error("$(clarse) does not respond to $sel")
  types = signature(m)
  ctypes = ctype(types)
  result = ccal(cmsgsend, ctypes[1], tuple(ctypes[2:end]...),
                obj, sel, args...)
  types[1] in (Object, Selector) && return types[1](result)
  return result
end
