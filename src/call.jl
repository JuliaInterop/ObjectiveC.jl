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
