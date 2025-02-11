export PlatformAvailability, UnavailableError

# Based off of Clang's `CXPlatformAvailability`
struct PlatformAvailability{Symbol}
    introduced::Union{Nothing, VersionNumber}
    deprecated::Union{Nothing, VersionNumber}
    obsoleted::Union{Nothing, VersionNumber}
    unavailable::Bool

    PlatformAvailability(platform, introduced, deprecated = nothing, obsoleted = nothing, unavailable = false) =
        new{platform}(introduced, deprecated, obsoleted, unavailable)
end
PlatformAvailability(platform; introduced = nothing, deprecated = nothing, obsoleted = nothing, unavailable = false) =
    PlatformAvailability(platform, introduced, deprecated, obsoleted, unavailable)

function is_unavailable(f::Function, avail::PlatformAvailability)
    return avail.unavailable ||
        (!isnothing(avail.obsoleted) && f() >= avail.obsoleted) ||
        (!isnothing(avail.introduced) && f() < avail.introduced)
end
is_unavailable(avails::Vector{<:PlatformAvailability}) = any(is_unavailable.(avails))

"""
    UnavailableError(symbol::Symbol, minver::VersionNumber)

Attempt to contruct an Objective-C object or property that is
not available in the current macOS version.
"""
struct UnavailableError <: Exception
    symbol::Symbol
    msg::String
end
function UnavailableError(f::Function, symbol::Symbol, platform::String, avail::PlatformAvailability)
    msg = if avail.unavailable
        "is not available on $platform"
    elseif !isnothing(avail.obsoleted) && f() >= avail.obsoleted
        "is obsolete since $platform v$(avail.obsoleted)"
    elseif !isnothing(avail.introduced) && f() < avail.introduced
        "was introduced on $platform v$(avail.introduced)"
    else
        "does not seem to be unavailable. Please file an issue at www.github.com/JuliaInterop/ObjectiveC.jl with the source of the offending Objective-C code."
    end
    return UnavailableError(symbol, msg)
end
function UnavailableError(symbol::Symbol, avails::Vector{<:PlatformAvailability})
    firsterror = findfirst(is_unavailable, avails)
    return UnavailableError(symbol, avails[firsterror])
end

function Base.showerror(io::IO, e::UnavailableError)
    print(io, "UnavailableError: `", e.symbol, "` ", e.msg)
    return
end

# Platform-specific definitions
for (name, pretty_name, version_function) in ((:macos, "macOS", :macos_version), (:darwin, "Darwin", :darwin_version))
    doc_str = """
        $name(introduced[, deprecated, obsoleted, unavailable])
        $name(; [introduced, deprecated, obsoleted, unavailable])

    Returns a `PlatformAvailability{:$name}` that represents a $pretty_name platform availability statement for Objective-C wrappers.
    """
    @eval begin
        export $name
        $name(args...; kwargs...) = PlatformAvailability(Symbol($name), args...; kwargs...)
        @doc $doc_str $name

        is_unavailable(avail::PlatformAvailability{Symbol($name)}) = is_unavailable($version_function, avail)
        UnavailableError(symbol::Symbol, avail::PlatformAvailability{Symbol($name)}) = UnavailableError($version_function, symbol, $pretty_name, avail)
    end
end

function _getavailability(mod, expr)
    avail = Base.eval(mod, expr)
    @assert avail isa PlatformAvailability || avail isa Vector{<:PlatformAvailability} "`availability` keyword argument must be a valid `PlatformAvailability` constructor or a vector thereof"

    return avail
end
