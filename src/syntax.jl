callerror() = error("ObjectiveC call: use [obj method] or [obj method:param ...]")

function calltransform(ex::Expr)
  obj = objcm(ex.args[1])
  args = ex.args[2:end]
  isempty(args) && callerror()
  if isexpr(args[1], Symbol)
    length(args) > 1 && callerror()
    return :(message($obj, $(Selector(args[1]))))
  end
  all(arg->isexpr(arg, :(:)) && isexpr(arg.args[1], Symbol), args) || callerror()
  msg = join(vcat([arg.args[1] for arg in args], ""), ":") |> Selector
  args = [objcm(arg.args[2]) for arg in args]
  :(message($obj, $msg, $(args...)))
end

objcm(ex::Expr) =
  isexpr(ex, :hcat) ? calltransform(ex) :
    Expr(ex.head, map(objcm, ex.args)...)

objcm(ex) = esc(ex)

macro objc(ex)
  objcm(ex)
end
