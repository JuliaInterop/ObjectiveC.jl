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
    prev_tracing = @load_preference("tracing", false)::Bool
    @set_preferences!("tracing" => enabled)
    if prev_tracing == enabled
        @info("ObjectiveC.jl tracing setting was already `$enabled`; setting not changed.")
    else
        @info("ObjectiveC.jl tracing setting changed; restart your Julia session for this change to take effect!")
    end
    return
end
const tracing = @load_preference("tracing", false)::Bool

# Types & Reflection
include("primitives.jl")
include("methods.jl")

# Get macOS and Darwin version
include("version.jl")

# Calls & Properties
include("abi.jl")
include("availability.jl")
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
