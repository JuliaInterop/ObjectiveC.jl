# `@public foo, bar` -> `public foo, bar` on Julia >= 1.11, nothing on older.
# `public` is only parseable at module top-level on all Julia versions, so a
# bare `@static if ...; public foo; end` would fail at parse time. Taking the
# names through a macro sidesteps that: `foo, bar` parses as a plain tuple,
# and we splice its members into an `Expr(:public, ...)` the lowerer accepts.
macro public(names)
    @static if VERSION >= v"1.11"
        syms = names isa Symbol ? (names,) :
               Meta.isexpr(names, :tuple) ? names.args :
               error("@public expects a symbol or a comma-separated list of symbols")
        return esc(Expr(:public, syms...))
    else
        return nothing
    end
end
