function allocclass(name, super)
  ptr = ccall(:objc_allocateClassPair, Ptr{Void}, (Ptr{Void}, Ptr{Cchar}, Csize_t),
              super, name, 0)
  ptr == C_NULL && error("Couldn't allocate class $name")
  return Class(ptr)
end

function register(class::Class)
  ccall(:objc_registerClassPair, Void, (Ptr{Void},),
        class)
end

function addmethod(class::Class, sel::Selector, imp::Ptr{Void}, types::String)
  result = ccall(:class_addMethod, Bool, (Ptr{Void}, Ptr{Void}, Ptr{Void}, Ptr{Cchar}),
                 class, sel, imp, types)
  result || error("Couldn't add method $sel to class $class")
end

# Syntax Utils

typehint(ex) =
  isexpr(ex, :(::)) ? ex.args[2] : :Any

typehints(ex) =
  map(typehint, ex.args[2:end])

# Syntax

macro ocfunc (func, ts)
  isexpr(ts, Tuple) && (ts = Expr(:tuple, ts...))
  ctypes = map(T->ctype(eval(current_module(), T)), ts.args)
end

end
