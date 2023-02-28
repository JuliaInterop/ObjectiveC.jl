module ObjectiveC

using Lazy, MacroTools

# Types & Reflection
int2bool(x::Integer) = x != 0
include("primitives.jl")
include("methods.jl")

# Calling Machinery
include("call.jl")
include("syntax.jl")

# Class Creation
include("classes.jl")

# API wrappers
include("foundation.jl")
export Foundation

end
