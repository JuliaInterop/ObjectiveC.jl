module ObjectiveC

using CEnum

using Preferences

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

# Types & Reflection
include("primitives.jl")
include("methods.jl")

# Calls & Properties
include("abi.jl")
include("availability.jl")
include("syntax.jl")
include("tracing.jl")

# API wrappers
include("version.jl")
include("foundation.jl")
include("core_foundation.jl")
include("dispatch.jl")
include("os.jl")
export Foundation, CoreFoundation, Dispatch, OS

# High-level functionality
include("classes.jl")
include("blocks.jl")

end
