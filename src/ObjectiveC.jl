module ObjectiveC

using Lazy

# Types & Reflection

import Base: show, convert, super, methods
export @sel_str, signature

include("primitives.jl")
include("methods.jl")

# Calling Machinery

export @objc, @classes

include("call.jl")
include("syntax.jl")

# API wrappers
include("foundation.jl")

end

include("cocoa.jl")
