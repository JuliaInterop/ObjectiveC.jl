# varargs_ccall

# variant of ccall that supports varargs

@generated function varargs_ccall(f::Ptr, _rettyp, _types, vals...)
    ex = quote end

    rettyp = _rettyp.parameters[1]
    types = _types.parameters[1].parameters
    args = [:(vals[$i]) for i in 1:length(vals)]

    # cconvert
    cconverted = [Symbol("cconverted_$i") for i in 1:length(vals)]
    for (dst, typ, src) in zip(cconverted, types, args)
      append!(ex.args, (quote
         $dst = Base.cconvert($typ, $src)
      end).args)
    end

    # unsafe_convert
    unsafe_converted = [Symbol("unsafe_converted_$i") for i in 1:length(vals)]
    for (dst, typ, src) in zip(unsafe_converted, types, cconverted)
      append!(ex.args, (quote
         $dst = Base.unsafe_convert($typ, $src)
      end).args)
    end

    call = Expr(:foreigncall, :f, rettyp, Core.svec(types...), 0, QuoteNode(:ccall), unsafe_converted..., cconverted...)
    push!(ex.args, call)

    return ex
end


# Calls

toobject(o::Object) = o
toobject(c::Class) = c
toobject(p::Ptr) = p

ctype(x) = x
ctype(o::Type{Object}) = Ptr{Cvoid}
ctype(s::Type{Selector}) = Ptr{Cvoid}
ctype(a::AbstractArray) = map(ctype, a)

const cmsgsend = cglobal(:objc_msgSend)

function message(obj, sel, args...)
  # FIXME: can we do these look-ups at compile time so that we can use `@ccall`?
  obj = toobject(obj)
  clarse = class(obj)
  m = method(clarse, sel)
  m == C_NULL && error("$clarse does not respond to $sel")
  types = signature(m)
  ctypes = ctype(types)

  args = Any[args...]
  for i = 1:length(args)
    types[i+3] == Object && (args[i] = toobject(args[i]))
  end

  result = varargs_ccall(cmsgsend, ctypes[1], Tuple{ctypes[2:end]...},
                         obj, sel, args...)
  types[1] in (Object, Selector) && return types[1](result)
  return result
end
