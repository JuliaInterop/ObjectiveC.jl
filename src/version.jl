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
    const macos_version = OncePerProcess{VersionNumber}() do
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

    const _macos_version = Ref{VersionNumber}()
    function macos_version()
        if !isassigned(_macos_version)
            _macos_version[] = _syscall_version("kern.osproductversion")
        end
        _macos_version[]
    end
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
