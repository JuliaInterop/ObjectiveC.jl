# Wrappers for the OS framework

module OS

using ..CEnum
using Libdl

# These aren't really ObjectiveC, but they're really only relevant on macOS.
# TODO: Move to Metal.jl, or to a separate macOS.jl package?

const libjulia_header = Ref{Vector{UInt8}}()

function __init__()
    # os_log APIs require a __dso_handle. we don't have a way to query that, but it
    # essentially points to the start of the DSO, so read the start of libjulia
    libjulia_handle =
        @ccall jl_load_dynamic_library(C_NULL::Ptr{Cvoid}, #=flags=#0::Cuint,
                                       #=throw=#1::Cint)::Ptr{Cvoid}
    libjulia_path = Libdl.dlpath(libjulia_handle)
    libjulia_header[] = read(libjulia_path)
end


## log

export OSLog, is_enabled

struct os_log_s end
const os_log_t = Ptr{os_log_s}

struct OSLog
    handle::os_log_t
end

Base.unsafe_convert(::Type{os_log_t}, log::OSLog) = log.handle

OS_LOG_DISABLED() = OSLog(cglobal(:_os_log_disabled, os_log_t))
OS_LOG_DEFAULT() = OSLog(cglobal(:_os_log_default, os_log_t))

"""
    OSLog([subsystem::String], [category::String]; disabled=false)

Create a new `OSLog` object, which can be used to log messages to the system log.
Passing no options creates a default logger, but it is recommended to specify the
subsystem and category of the logger. By setting `disabled` to `true`, the logger
can be disabled, which is useful for conditional logging.

Construction of these objects is very cheap, and as such it is recommended to create
a new logger for each subsystem and category combination.

For logging messages, use the `log` object as a function, passing the message as a
string. The `type` keyword argument can be used to specify the log type, which can
be one of `LOG_TYPE_DEFAULT`, `LOG_TYPE_INFO`, `LOG_TYPE_DEBUG`, `LOG_TYPE_ERROR`,
or `LOG_TYPE_FAULT`. By default, the log type is `LOG_TYPE_DEFAULT`.
"""
function OSLog(subsystem::String, category::String; disabled=false)
    if disabled
        OS_LOG_DISABLED()
    else
        handle = @ccall os_log_create(subsystem::Cstring, category::Cstring)::os_log_t
        OSLog(handle)
    end
end
OSLog(; disabled::Bool=false) = disabled ? OS_LOG_DISABLED() : OS_LOG_DEFAULT()

@cenum os_log_type_t::UInt8 begin
    LOG_TYPE_DEFAULT = 0x00
    LOG_TYPE_INFO    = 0x01
    LOG_TYPE_DEBUG   = 0x02
    LOG_TYPE_ERROR   = 0x10
    LOG_TYPE_FAULT   = 0x11
end

is_enabled(log::OSLog, type::os_log_type_t) =
    Bool(@ccall os_log_type_enabled(log::os_log_t, type::os_log_type_t)::Cint)

function (log::OSLog)(msg::String; type::os_log_type_t=LOG_TYPE_DEFAULT)
    if is_enabled(log, type)
        os_log_with_type(log, type, msg)
    end
end

@cenum os_log_buffer_kind::UInt8 begin
    ScalarKind = 0  # simple scalar (int, float, raw_pointer, etc)
    CountKind       # describes the length of the following item.
    StringKind      # pointer to a null-terminated C string. may be preceded by CountKind
    PointerKind     # pointer to a block of raw data. must be preceded by CountKind
    ObjCObjKind     # pointer to an Objective-C object.
    WideStringKind  # pointer to a wide-char string. may be preceded by CountKind
    ErrnoKind       # no value; runtime should load errno
end

@cenum os_log_buffer_visibility::UInt8 begin
    IsPrivate = 1
    IsPublic  = 2
end

@cenum os_log_buffer_flags::UInt8 begin
    HasPrivateItems   = 1
    HasNonScalarItems = 2
end

@inline function os_log_with_type(log::OSLog, type::os_log_type_t, str::String)
    # we do not support arbitrary formatting, but only string arguments which are passed
    # using a hard-coded '%{public}s' format. for arbitrary formatting, look at Clang's
    # `__builtin_os_log_format_buffer_size` and `__builtin_os_log_format` implementations.
    GC.@preserve str begin
        cstr = Base.unsafe_convert(Cstring, str)

        # build the buffer dynamically
        #buf = let io=IOBuffer()
        #    # summary flags
        #    write(io, HasNonScalarItems)
        #
        #    # number of arguments
        #    write(io, UInt8(1))
        #
        #    # arg 1
        #    write(io, (StringKind << 4)%UInt8 | IsPublic)   # descriptor
        #    write(io, UInt8(8))                             # length
        #    write(io, UInt64(pointer(cstr)))                # data
        #
        #    take!(io)
        #end

        # normally the buffer would be built statically by looking at the formatting string.
        # since we only support a single string argument, we can hard-code it here instead.
        buf = Ref{NTuple{12, UInt8}}((
            HasNonScalarItems,
            UInt8(1),
            (StringKind << 4)%UInt8 | IsPublic,
            UInt8(8),
            reinterpret(NTuple{8,UInt8}, UInt64(pointer(cstr)))...
        ))

        @ccall _os_log_impl(libjulia_header[]::Ptr{Cvoid},
                            log::os_log_t, type::os_log_type_t,
                            "%{public}s"::Cstring, buf::Ptr{UInt8}, sizeof(buf)::UInt32
                           )::Cvoid
    end
end

end
