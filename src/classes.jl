export @class

function allocclass(name, super)
  ptr = ccall(:objc_allocateClassPair, Ptr{Void}, (Ptr{Void}, Ptr{Cchar}, Csize_t),
              super, name, 0)
  ptr == C_NULL && error("Couldn't allocate class $name")
  return Class(ptr)
end

function register(class::Class)
  ccall(:objc_registerClassPair, Void, (Ptr{Void},),
        class)
  return class
end

createclass(name, super) = allocclass(name, super) |> register

getmethod(class::Class, sel::Selector) =
  ccall(:class_getInstanceMethod, Ptr{Void}, (Ptr{Void}, Ptr{Void}),
        class, sel)

methodtypeenc(method::Ptr) =
  ccall(:method_getTypeEncoding, Ptr{Cchar}, (Ptr{Void},),
        method) |> bytestring

methodtypeenc(class::Class, sel::Selector) = methodtypeenc(getmethod(class, sel))

methodtype(args...) = methodtypeenc(args...) |> parseencoding

replacemethod(class::Class, sel::Selector, imp::Ptr{Void}, types::String) =
  ccall(:class_replaceMethod, Bool, (Ptr{Void}, Ptr{Void}, Ptr{Void}, Ptr{Cchar}),
        class, sel, imp, types)

function setmethod(class::Class, sel::Selector, imp::Ptr{Void}, types::String)
  meth = getmethod(class, sel)
  meth ≠ C_NULL && methodtype(meth) != parseencoding(types) &&
    error("New method $(name(sel)) of $class must match $(methodtype(meth))")
  replacemethod(class, sel, imp, types)
end

# Syntax

function createdef(f, args, Ts, body, ret)
  def = :(function $f($(map((x,T)->:($x::$(ctype(T))), args, Ts)...)) end)
  for (arg, T) in zip(args, Ts)
    T in (Object, Selector) && push!(def.args[2].args, :($arg = $T($arg)))
  end
  push!(def.args[2].args, ret == Void ? # Ugly workaround for 0.3
                            :($body; nothing) :
                            :(convert($(ctype(ret)), $body)))
  return def
end

function createmethod(class, ex)
  instance = ex.args[1] == symbol("@-")
  ret = eval(current_module(), ex.args[2])
  params = ex.args[3:end-1]
  sel = @_ params map(x->x.args[1], _) join(_, ":") string(_, ":") Selector
  Ts = @>> params map(x->x.args[2]) map(x->isa(x, Symbol) ? Object : x.args[2]) map(T->eval(current_module(), T))
  args = @>> params map(x->x.args[2]) map(x->isa(x, Symbol) ? x : x.args[3])
  body = ex.args[end]

  Ts = [Object, Selector, Ts...]
  args = [:self, :_cmd, args...]
  typ = encodetype(ret, Ts...)

  f = "$(class)_$(name(sel))" |> symbol
  return quote
    $(esc(createdef(f, args, Ts, body, ret)))
    setmethod($(instance ? esc(class) : :(class($(esc(class))))), $sel,
              cfunction($(esc(f)), $(ctype(ret)), $(Expr(:tuple, map(ctype, Ts)...))),
              $typ)
  end
end

macro class (def)
  name = namify(def.args[2])
  sym = Expr(:quote, name)
  super = isexpr(def.args[2], :(<:)) ? def.args[2].args[2] : :NSObject
  expr = quote
    classexists($sym) || createclass($sym, Class($(Expr(:quote, super))))
    isdefined($sym) || (const $(esc(name)) = Class($sym))
  end
  for ex in def.args[3].args
    if isexpr(ex, :macrocall) && ex.args[1] in (symbol("@+"), symbol("@-"))
      ex = createmethod(name, ex)
    end
    push!(expr.args, ex)
  end
  :(@objc $expr; $(esc(name)))
end

# quote
#   @class type Foo
#     @- (Cdouble) multiply:(Cdouble)x by:(Cdouble)y begin
#       x*y
#     end
#   end
# end |> macroexpand

# @class type Foo
#   @- (Cdouble) multiply:(Cdouble)x by:(Cdouble)y begin
#     x*y
#   end
# end

# @objc begin
#   foo = [Foo new]
#   x = [foo multiply:28 by:26]
#   [foo release]
#   x
# end
