module ObjectiveC

using Lazy, MacroTools

# Types & Reflection

import Base: show, convert, unsafe_convert, super, methods
export @sel_str, signature

int2bool(x::Integer) = x != 0

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
