module ObjectiveC

using Lazy, MacroTools, CEnum

# Types & Reflection
int2bool(x::Integer) = x != 0
include("primitives.jl")
include("methods.jl")

# Calling Machinery
include("syntax.jl")

# High-level functionality
include("classes.jl")

# API wrappers
include("foundation.jl")
include("dispatch.jl")
export Foundation, Dispatch

end
