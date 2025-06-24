# version and support queries

@noinline function _syscall_version(name)
    size = Ref{Csize_t}()
    err = @ccall sysctlbyname(
        name::Cstring, C_NULL::Ptr{Cvoid}, size::Ptr{Csize_t},
        C_NULL::Ptr{Cvoid}, 0::Csize_t
    )::Cint
    Base.systemerror("sysctlbyname", err != 0)

    osrelease = Vector{UInt8}(undef, size[])
    err = @ccall sysctlbyname(
        name::Cstring, osrelease::Ptr{Cvoid}, size::Ptr{Csize_t},
        C_NULL::Ptr{Cvoid}, 0::Csize_t
    )::Cint
    Base.systemerror("sysctlbyname", err != 0)

    verstr = view(String(osrelease), 1:(size[] - 1))
    return parse(VersionNumber, verstr)
end

@static if isdefined(Base, :OncePerProcess) # VERSION >= v"1.12.0-DEV.1421"
    const darwin_version = OncePerProcess{VersionNumber}() do
        _syscall_version("kern.osrelease")
    end
    const _macos_version = OncePerProcess{VersionNumber}() do
        _syscall_version("kern.osproductversion")
    end
else
    const _darwin_version = Ref{VersionNumber}()
    function darwin_version()
        if !isassigned(_darwin_version)
            _darwin_version[] = _syscall_version("kern.osrelease")
        end
        _darwin_version[]
    end

    const __macos_version = Ref{VersionNumber}()
    function _macos_version()
        if !isassigned(__macos_version)
            __macos_version[] = _syscall_version("kern.osproductversion")
        end
        __macos_version[]
    end
end

function macos_version(normalize=true)
    ver = _macos_version()
    if normalize && ver.major == 16
        # on older SDKs, macOS Tahoe (26) is reported as v16.
        # normalize this to v26 regardless of the SDK to simplify use.
        return VersionNumber(26, ver.minor, ver.patch)
    end    
    return ver
end
@doc """
    ObjectiveC.darwin_version()::VersionNumber

Returns the host Darwin kernel version.

See also [`ObjectiveC.macos_version`](@ref).
""" darwin_version

@doc """
    ObjectiveC.macos_version()::VersionNumber

Returns the host macOS version.

See also [`ObjectiveC.darwin_version`](@ref).
""" macos_version

"""
    Metal.is_macos([ver::VersionNumber]) -> Bool

Returns whether the OS is macOS with version `ver` or newer.

See also [`Metal.macos_version`](@ref).
"""
function is_macos(ver = nothing)
    return if !Sys.isapple()
        false
    elseif ver === nothing
        true
    else
        macos_version() >= ver
    end
end
