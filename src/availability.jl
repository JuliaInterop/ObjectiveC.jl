export PlatformAvailability, UnavailableError

# Each platform tuple has a symbol representing the constructor, a pretty_name name for errors,
# a symbol of the function used to check the version for that platform, and the function that
# returns whether that statement applies for this device
const SUPPORTED_PLATFORMS = Dict(
    :macos => (pretty_name = "macOS", ver_func = :macos_version, plat_func = Sys.isapple),
    :darwin => (pretty_name = "Darwin", ver_func = :darwin_version, plat_func = Sys.isapple),
    :test => (pretty_name = "Never applicable", ver_func = :error, plat_func = () -> false)
)

# Based off of Clang's `CXPlatformAvailability`
"""
    PlatformAvailability(platform::Symbol, introduced[, deprecated, obsoleted, unavailable])
    PlatformAvailability(platform::Symbol, ; [introduced, deprecated, obsoleted, unavailable])

Creates a `PlatformAvailability{platform}` object representing an availability statement for Objective-C wrappers.

The currently supported values for `platform` are:
- `:macos`:  for macOS version availability
- `:darwin`: for Darwin kernel availability
"""
struct PlatformAvailability{P}
    introduced::Union{Nothing, VersionNumber}
    deprecated::Union{Nothing, VersionNumber}
    obsoleted::Union{Nothing, VersionNumber}
    unavailable::Bool

    function PlatformAvailability(p::Symbol, introduced, deprecated = nothing, obsoleted = nothing, unavailable = false)
        haskey(SUPPORTED_PLATFORMS, p) || throw(ArgumentError(lazy"`:$p` is not a supported platform for `PlatformAvailability`, see `?PlatformAvailability` for more information."))
        return new{p}(introduced, deprecated, obsoleted, unavailable)
    end
end
PlatformAvailability(platform; introduced = nothing, deprecated = nothing, obsoleted = nothing, unavailable = false) =
    PlatformAvailability(platform, introduced, deprecated, obsoleted, unavailable)

function is_available(f::Function, avail::PlatformAvailability)
    return !avail.unavailable &&
        (isnothing(avail.obsoleted) || f() < avail.obsoleted) &&
        (isnothing(avail.introduced) || f() >= avail.introduced)
end
is_available(avails::Vector{<:PlatformAvailability}) = all(is_available.(avails))

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
    firsterror = findfirst(!is_available, avails)
    return UnavailableError(symbol, avails[firsterror])
end

function Base.showerror(io::IO, e::UnavailableError)
    print(io, "UnavailableError: `", e.symbol, "` ", e.msg)
    return
end

# Platform-specific definitions
for (name, (pretty_name, ver_func, plat_func)) in SUPPORTED_PLATFORMS
    quotname = Meta.quot(name)
    @eval begin
        is_available(avail::PlatformAvailability{$quotname}) = !$plat_func() || is_available($ver_func, avail)
        UnavailableError(symbol::Symbol, avail::PlatformAvailability{$quotname}) = UnavailableError($ver_func, symbol, $pretty_name, avail)
    end
end

function get_avail_exprs(mod, expr)
    transform_avail_exprs!(expr)
    avail = Base.eval(mod, expr)

    return avail
end

function transform_avail_exprs!(expr)
    if Meta.isexpr(expr, :vect)
        for availexpr in expr.args
            transform_avail_expr!(availexpr)
        end
    else
        transform_avail_expr!(expr)
    end
    return expr
end
function transform_avail_expr!(expr)
    @assert Meta.isexpr(expr, :call) "`availability` keyword argument must be a valid `PlatformAvailability` constructor or vector."
    expr.args[1] = Meta.quot(expr.args[1])
    insert!(expr.args, 1, :PlatformAvailability)
    return expr
end

