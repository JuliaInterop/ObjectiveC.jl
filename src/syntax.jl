export @objc, @classes

callerror() = error("ObjectiveC call: use [obj method]::typ or [obj method :param::typ ...]::typ")

ctype(T::Type) = T
ctype(T::Type{<:Object}) = id

# version of ccall that calls `ctype` on types to figure out if we need pass-by-reference,
# further relying on `Base.unsafe_convert` to get a hold of such a reference.
# it works around the limitation that ccall type tuples need to be literals.
# this is a bit of hack, as it relies on internals of ccall.
@inline @generated function byref_ccall(f::Ptr, _rettyp, _types, vals...)
    ex = quote end

    rettyp = _rettyp.parameters[1]
    types = _types.parameters[1].parameters
    args = [:(vals[$i]) for i in 1:length(vals)]

    # unwrap
    reference_rettyp = ctype(rettyp)
    reference_types = map(ctype, types)

    # cconvert
    cconverted = [Symbol("cconverted_$i") for i in 1:length(vals)]
    for (dst, typ, src) in zip(cconverted, reference_types, args)
      append!(ex.args, (quote
         $dst = Base.cconvert($typ, $src)
      end).args)
    end

    # unsafe_convert
    unsafe_converted = [Symbol("unsafe_converted_$i") for i in 1:length(vals)]
    for (dst, typ, src) in zip(unsafe_converted, reference_types, cconverted)
      append!(ex.args, (quote
         $dst = Base.unsafe_convert($typ, $src)
      end).args)
    end

    call = Expr(:foreigncall, :f, reference_rettyp, Core.svec(reference_types...), 0, QuoteNode(:ccall), unsafe_converted..., cconverted...)
    push!(ex.args, call)

    # re-wrap if necessary
    if rettyp != reference_rettyp
        ex = quote
            val = $(ex)
            $rettyp(val)
        end
    end

    return ex
end

function objcm(ex)
    # handle a single call, [dst method: param::typ]::typ

    # parse the call return type
    Meta.isexpr(ex, :(::)) || callerror()
    call, rettyp = ex.args

    # parse the call
    Meta.isexpr(call, :hcat) || callerror()
    obj, method, args... = call.args

    # the method should be a simple symbol. the resulting selector name includes : for args
    method isa Symbol || callerror()
    sel = String(method) * ":"^(length(args))

    # deconstruct the arguments, which should all be typed expressions
    argtyps, argvals = [], []
    for arg in args
        Meta.isexpr(arg, :(::)) || callerror()
        val, typ = arg.args
        if val isa QuoteNode
            # this comes from a prepended symbol indicating another arg
            val = val.value
        end
        push!(argvals, val)
        push!(argtyps, typ)
    end

    # the object should be a class (single symbol) or an instance (var + typeassert)
    ex = if obj isa Symbol
        # class
        class_message(obj, sel, rettyp, argtyps, argvals)
    elseif Meta.isexpr(obj, :(::))
        # instance
        val, typ = obj.args
        if val isa Expr
            # possibly dealing with a nested expression, so recurse
            quote
                obj = $(objcm(obj))
                $(instance_message(:obj, sel, rettyp, argtyps, argvals))
            end
        else
            instance_message(esc(val), sel, rettyp, argtyps, argvals)
        end
        # XXX: do something with the instance type?
    else
        callerror()
    end

    return ex
end

const msgSend = cglobal(:objc_msgSend)

function class_message(class_name, msg, rettyp, argtyps, argvals)
    quote
        class = Class($(String(class_name)))
        sel = Selector($(String(msg)))
        byref_ccall(msgSend, $(esc(rettyp)),
              Tuple{Ptr{Cvoid}, Ptr{Cvoid}, $(map(esc, argtyps)...)},
              class, sel, $(map(esc, argvals)...))
    end
end

function instance_message(instance, msg, rettyp, argtyps, argvals)
    quote
        sel = Selector($(String(msg)))
        byref_ccall(msgSend, $(esc(rettyp)),
              Tuple{id, Ptr{Cvoid}, $(map(esc, argtyps)...)},
              $instance, sel, $(map(esc, argvals)...))
    end
end

macro objc(ex)
  objcm(ex)
end


# Import Classes

macro classes(names)
  isexpr(names, Symbol) ? (names = [names]) : (names = names.args)
  Expr(:block, [:(const $(esc(name)) = Class($(Expr(:quote, name))))
                for name in names]..., nothing)
end
