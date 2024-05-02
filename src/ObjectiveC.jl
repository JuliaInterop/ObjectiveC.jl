module ObjectiveC

using CEnum

using Preferences

"""
    ObjectiveC.enable_tracing(enabled::Bool)

Enable or disable ObjectiveC.jl tracing, which outputs every Objective-C call made by Julia.
This is useful for debugging, or to collect traces for submitting bug reports.

The setting is saved in a preference, so is persistent, and requires a restart of Julia to
take effect.
"""
function enable_tracing(enabled::Bool)
    @set_preferences!("tracing" => enabled)
    @info("ObjectiveC.jl tracing setting changed; restart your Julia session for this change to take effect!")
end
const tracing = @load_preference("tracing", false)::Bool

# Types & Reflection
include("primitives.jl")
include("methods.jl")

# Calls & Properties
include("abi.jl")
include("syntax.jl")

# API wrappers
include("foundation.jl")
include("core_foundation.jl")
include("dispatch.jl")
include("os.jl")
export Foundation, CoreFoundation, Dispatch, OS

# High-level functionality
include("classes.jl")
include("blocks.jl")

end
