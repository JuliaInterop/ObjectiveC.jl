module ObjectiveC

using Lazy, MacroTools

# Types & Reflection
int2bool(x::Integer) = x != 0
include("primitives.jl")
include("methods.jl")

# Calling Machinery
include("syntax.jl")

# High-level functionality
include("classes.jl")
include("memory.jl")

# API wrappers
include("foundation.jl")
export Foundation

end
