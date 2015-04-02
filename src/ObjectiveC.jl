module ObjectiveC

using Lazy

# Types & Reflection

import Base: show, convert, unsafe_convert, super, methods
export @sel_str, signature

include("primitives.jl")
include("methods.jl")

# Calling Machinery

export @objc, @classes

include("call.jl")
include("syntax.jl")

# Class Creation

include("classes.jl")

# API wrappers
include("foundation.jl")

end

# include("cocoa/cocoa.jl")
