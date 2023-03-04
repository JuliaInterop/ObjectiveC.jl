export @objc, @objcwrapper

callerror(msg) = error("""ObjectiveC call: $msg
                          Use [obj method]::typ or [obj method :param::typ ...]::typ""")

# convert a vcat to a hcat so that we can split the @objc expressions into multiple lines
function flatvcat(ex::Expr)
  any(ex->isexpr(ex, :row), ex.args) || return ex
  flat = Expr(:hcat)
  for row in ex.args
    isexpr(row, :row) ?
      push!(flat.args, row.args...) :
      push!(flat.args, row)
  end
  return flat
end

function objcm(ex)
    # handle a single call, [dst method: param::typ]::typ

    # parse the call return type
    Meta.isexpr(ex, :(::)) || callerror("missing return type")
    call, rettyp = ex.args
    if Meta.isexpr(rettyp, :curly) && rettyp.args[1] == :id
        # we're returning an object pointer, with additional type info.
        # currently that info isn't used, so just strip it
        rettyp = rettyp.args[1]
    end

    # parse the call
    if Meta.isexpr(call, :vcat)
      call = flatvcat(call)
    end
    Meta.isexpr(call, :hcat) || return esc(call)
    obj, method, args... = call.args

    # argument should be typed expressions
    argnames, argvals, argtyps = [], [], []
    function parse_argument(arg; named=true)
        # name before the parameter (name:value::type) is optional
        if Meta.isexpr(arg, :call) && arg.args[1] == :(:)
          # form: name:value::typ
          name = String(arg.args[2])
          arg = arg.args[3]
        else
          name = nothing
        end
        push!(argnames, name)

        Meta.isexpr(arg, :(::)) || callerror("missing argument type")
        val, typ = arg.args
        if val isa QuoteNode
            # nameless params are parsed as a symbol
            # (there's an edge case when using e.g. `:length(x)::typ`, causing the `length`
            #  to be parsed as a symbol, but you should just use a param name in that case)
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

    # the method may be a plain symbol, or already contain the first arg
    if method isa Symbol
        argnames, argvals, argtyps = [], [], []
    elseif Meta.isexpr(method, :call) && method.args[1] == :(:)
        _, method, arg = method.args
        isa(method, Symbol) || callerror("method name must be a literal symbol")
        parse_argument(arg)
    else
        callerror("method name must be a literal")
    end

    # deconstruct the remaining arguments
    for arg in args
        # first arg should always be part of the method
        isempty(argnames) && callerror("first argument should be part of the method (i.e., don't use a space between the method and :param)")

        parse_argument(arg)
    end

    # with the method and all args known, we can determine the selector
    sel = String(method) * join(map(name->something(name,"")*":", argnames))

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
        callerror("object must be a class or typed instance")
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


# Wrapper Classes

wrappererror(msg) = error("""ObjectiveC wrapper: $msg
                             Use `@objcwrapper Class` or `Class <: SuperType`; see `?@objcwrapper` for more details.""")

"""
    @objcwrapper [kwargs] name [<: super]

Helper macro to define a set of Julia classes for wrapping Objective-C pointers.

Because Objective-C supports multilevel inheritance, we cannot directly translate its
class model to Julia's. Instead, we define an abstract class `name` that implements the
requested hierarchy (extending `super`, which defaults to `Object`), along with an instance
class `$(name)Instance` that wraps an Objective-C pointer.

The split into two classes should not be visible to the end user. Methods should only ever
use the `name` class, both for dispatch purposes and when constructing objects.

In addition to this boilerplate, `@objcwrapper`'s code generation can be customized through
keyword arguments:

  * `immutable`: if `true` (default), define the instance class as an immutable. Should be
    disabled when you want to use finalizers.
  * `comparison`: if `true` (default `false`), define `==` and `hash` methods for the
    wrapper class. This should not be necessary when using an immutable struct, in which
    case the default `==` and `hash` methods are sufficient.
"""
macro objcwrapper(ex...)
  def = ex[end]
  kwargs = ex[1:end-1]

  # parse kwargs
  comparison = false
  immutable = true
  for kw in kwargs
    if kw isa Expr && kw.head == :(=)
      kw, val = kw.args
      if kw == :comparison
        val isa Bool || wrappererror("comparison keyword argument must be a literal boolean")
        comparison = val
      elseif kw == :immutable
        val isa Bool || wrappererror("immutable keyword argument must be a literal boolean")
        immutable = val
      else
        wrappererror("unrecognized keyword argument: $kw")
      end
    else
      wrappererror("invalid keyword argument: $kw")
    end
  end

  # parse class definition
  if Meta.isexpr(def, :(<:))
    name, super = def.args
  elseif def isa Symbol
    name = def
    super = Object
  else
    wrappererror()
  end

  # generate type hierarchy
  ex = quote
    abstract type $name <: $super end
  end

  # generate the instance class
  instance = Symbol(name, "Instance")
  ex = if immutable
    quote
      $(ex.args...)
      struct $instance <: $name
        ptr::id
      end
    end
  else
    quote
      $(ex.args...)
      mutable struct $instance <: $name
        ptr::id
      end
    end
  end

  # add essential methods
  ex = quote
    $(ex.args...)

    Base.unsafe_convert(::Type{id}, dev::$instance) = dev.ptr

    # add a pseudo constructor to theh abstract type that also checks for nil pointers.
    function $name(ptr::id)
      ptr == nil && throw(UndefRefError())
      $instance(ptr)
    end
  end

  # add optional methods
  if comparison
    ex = quote
      $(ex.args...)

      Base.:(==)(a::$instance, b::$instance) = a.ptr == b.ptr
      Base.hash(dev::$instance, h::UInt) = hash(dev.ptr, h)
    end
  end

  esc(ex)
end
