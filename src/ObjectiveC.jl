module ObjectiveC

using Lazy, MacroTools, CEnum

# Types & Reflection
include("primitives.jl")
include("methods.jl")

# Calls & Properties
include("syntax.jl")

# API wrappers
include("foundation.jl")
include("dispatch.jl")
export Foundation, Dispatch

# High-level functionality
include("classes.jl")
include("blocks.jl")

end
