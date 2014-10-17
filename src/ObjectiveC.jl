module ObjectiveC

using Lazy

# Types & Reflection

import Base: show, convert, super, methods

include("selectors.jl")
include("classes.jl")
include("objects.jl")
include("methods.jl")

# Calling Machinery

export @objc, @classes

include("call.jl")
include("syntax.jl")

# API wrappers
include("foundation.jl")

end

include("cocoa.jl")
