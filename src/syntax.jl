export @objc, @classes

callerror() = error("ObjectiveC call: use [obj method]::typ or [obj method :param::typ ...]::typ")

function objcm(ex)
    # handle a single call, [dst method: param::typ]::typ

    # parse the call return type
    Meta.isexpr(ex, :(::)) || callerror()
    call, rettyp = ex.args
    if Meta.isexpr(rettyp, :curly) && rettyp.args[1] == :id
        # we're returning an object pointer, with additional type info.
        # currently that info isn't used, so just strip it
        rettyp = rettyp.args[1]
    end

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
        if Meta.isexpr(typ, :curly) && typ.args[1] == :id
            # we're passing an object pointer, with additional type info.
            # currently that info isn't used, so just strip it
            typ = typ.args[1]
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

function class_message(class_name, msg, rettyp, argtyps, argvals)
    quote
        class = Class($(String(class_name)))
        sel = Selector($(String(msg)))
        ccall(:objc_msgSend, $(esc(rettyp)),
              (Ptr{Cvoid}, Ptr{Cvoid}, $(map(esc, argtyps)...)),
              class, sel, $(map(esc, argvals)...))
    end
end

function instance_message(instance, msg, rettyp, argtyps, argvals)
    quote
        sel = Selector($(String(msg)))
        ccall(:objc_msgSend, $(esc(rettyp)),
              (id, Ptr{Cvoid}, $(map(esc, argtyps)...)),
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
