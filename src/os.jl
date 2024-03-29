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

export OSLog

struct os_log_s end
const os_log_t = Ptr{os_log_s}

struct OSLog
    handle::os_log_t
end

Base.unsafe_convert(::Type{os_log_t}, log::OSLog) = log.handle

OS_LOG_DISABLED() = OSLog(cglobal(:_os_log_disabled, os_log_t))
OS_LOG_DEFAULT() = OSLog(cglobal(:_os_log_default, os_log_t))

"""
    OSLog([subsystem::String], [category::String]; enabled=true)

Create a new `OSLog` object, which can be used to log messages to the system log.
Passing no options creates a default logger, but it is recommended to specify the
subsystem and category of the logger. By setting `enabled` to `false`, the logger
can be disabled, which is useful for conditional logging.

Construction of these objects is very cheap, and as such it is recommended to create
a new logger for each subsystem and category combination.

For logging messages, use the `log` object as a function, passing the message as a
string. The `type` keyword argument can be used to specify the log type, which can
be one of `LOG_TYPE_DEFAULT`, `LOG_TYPE_INFO`, `LOG_TYPE_DEBUG`, `LOG_TYPE_ERROR`,
or `LOG_TYPE_FAULT`. By default, the log type is `LOG_TYPE_DEFAULT`.
"""
function OSLog(subsystem::String, category::String; enabled=true)
    if enabled
        handle = @ccall os_log_create(subsystem::Cstring, category::Cstring)::os_log_t
        OSLog(handle)
    else
        OS_LOG_DISABLED()
    end
end
OSLog(; enabled::Bool=true) = enabled ? OS_LOG_DEFAULT() : OS_LOG_DISABLED()

@cenum os_log_type_t::UInt8 begin
    LOG_TYPE_DEFAULT = 0x00
    LOG_TYPE_INFO    = 0x01
    LOG_TYPE_DEBUG   = 0x02
    LOG_TYPE_ERROR   = 0x10
    LOG_TYPE_FAULT   = 0x11
end

is_log_enabled(log::OSLog, type::os_log_type_t) =
    Bool(@ccall os_log_type_enabled(log::os_log_t, type::os_log_type_t)::Cint)

function (log::OSLog)(msg::String; type::os_log_type_t=LOG_TYPE_DEFAULT)
    if is_log_enabled(log, type)
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

@inline function os_log_call(f, str::String)
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
        buf = (
            UInt8(HasNonScalarItems),
            UInt8(1),
            (StringKind << 4)%UInt8 | IsPublic,
            UInt8(8),
            #reinterpret(NTuple{8,UInt8}, UInt64(pointer(cstr)))...
            # XXX: the above reinterpret only works on 1.10
            ntuple(i -> (UInt64(pointer(cstr)) >> ((i-1)*8))%UInt8, 8)...
        )

        f(buf::NTuple{12, UInt8})
    end
end

@inline function os_log_with_type(log::OSLog, type::os_log_type_t, str::String)
    os_log_call(str) do buf
        @ccall _os_log_impl(libjulia_header[]::Ptr{Cvoid},
                            log::os_log_t, type::os_log_type_t,
                            "%{public}s"::Cstring, buf::Ref{UInt8}, sizeof(buf)::UInt32
                           )::Cvoid
    end
end


## signpost

export OSSignpost, @signpost_interval, @signpost_event

const os_signpost_id_t = UInt64
struct OSSignpost
    id::os_signpost_id_t
end

OSSignpostNull() = OSSignpost(0)
OSSignpostInvalid() = OSSignpost(-1%UInt64)
OSSignpostExclusive() = OSSignpost(0xEEEEB0B5B2B2EEEE)

function OSSignpost(log::OSLog)
    id = @ccall os_signpost_id_generate(log::os_log_t)::os_signpost_id_t
    OSSignpost(id)
end

Base.convert(::Type{os_signpost_id_t}, signpost::OSSignpost) = signpost.id

is_signpost_enabled(log::OSLog) = Bool(@ccall os_signpost_enabled(log::os_log_t)::Cint)

@cenum os_signpost_type_t::UInt8 begin
    SIGNPOST_EVENT          = 0
    SIGNPOST_INTERVAL_BEGIN = 1
    SIGNPOST_INTERVAL_END   = 2
end

function os_signpost_emit_with_type(log::OSLog, signpost::OSSignpost, type::os_signpost_type_t,
                                    name::String, msg::String)
    # NOTE: contrary to Apple's implementation, we do not check if signposts are enabled
    #       but assume that the user has already done so. by checking earlier, it's
    #       possible to also avoid the string formatting and further reduce overhead.
    os_log_call(msg) do buf
        @ccall _os_signpost_emit_with_name_impl(libjulia_header[]::Ptr{Cvoid},
                                                log::os_log_t, type::os_signpost_type_t,
                                                signpost::os_signpost_id_t, name::Cstring,
                                                "%s"::Cstring, buf::Ref{UInt8},
                                                sizeof(buf)::UInt32)::Cvoid
    end
end

interval_begin(log::OSLog, signpost::OSSignpost, name::String, msg::String="") =
    os_signpost_emit_with_type(log, signpost, SIGNPOST_INTERVAL_BEGIN, name, msg)

interval_end(log::OSLog, signpost::OSSignpost, name::String, msg::String="") =
    os_signpost_emit_with_type(log, signpost, SIGNPOST_INTERVAL_END, name, msg)

# Like a try-finally block, except without introducing the try scope
# NOTE: This is deprecated and should not be used from user logic. A proper solution to
# this problem will be introduced in https://github.com/JuliaLang/julia/pull/39217
macro __tryfinally(ex, fin)
    Expr(:tryfinally,
       :($(esc(ex))),
       :($(esc(fin)))
       )
end

# TODO: make signpost_event a macro and prevent rendering the messages if the log is disabled
#       also ensures it works this way for intervals

"""
    @signpost_interval [kwargs...] name ex

Run `ex` within a signposted interval called `name`.

The following keyword arguments are supported:

    - `log`: the `OSLog` object to use for logging. By default, the default logger is used.
    - `start`: the message to log at the start of the interval. By default, "start".
    - `stop`: the message to log at the end of the interval. By default, "end", or "error"
      if an error occured during evaluation of `ex`. May refer to variables defined in `ex`.
"""
macro signpost_interval(ex...)
    ex = [ex...]

    # destructure the expression
    kwargs = []
    while !isempty(ex) && Meta.isexpr(ex[1], :(=))
        push!(kwargs, popfirst!(ex))
    end
    if length(ex) != 2
        throw(ArgumentError("Invalid usage of @signpost_interval: expected 2 arguments"))
    end
    name, code = ex

    # parse the keyword arguments
    log_ex = :($OSLog())
    start_ex = "start"
    stop_ex = "stop"
    for kwarg in kwargs
        key, value = kwarg.args
        if key == :log
            log_ex = value
        elseif key == :start
            start_ex = value
        elseif key == :stop
            stop_ex = value
        else
            throw(ArgumentError("Invalid keyword argument to @signpost_interval: $kwarg"))
        end
    end

    quote
        log = $(esc(log_ex))
        if is_signpost_enabled(log)
            local signpost = OSSignpost(log)
            local name = $(esc(name))
            local start_msg = $(esc(start_ex))
            interval_begin(log, signpost, name, start_msg)
            local stop_msg = "error"
            @__tryfinally(begin
                ret = $(esc(code))
                stop_msg = $(esc(stop_ex))
                ret
            end, begin
                interval_end(log, signpost, name, stop_msg)
            end)
        else
            $(esc(code))
        end
    end
end

"""
    @signpost_event [kwargs...] name [message]

Emit a signposted event with the given `name` and optional `message`.

The following keyword arguments are supported:

    - `log`: the `OSLog` object to use for logging. By default, the default logger is used.
"""
macro signpost_event(ex...)
    ex = [ex...]

    # destructure the expression
    kwargs = []
    while !isempty(ex) && Meta.isexpr(ex[1], :(=))
        push!(kwargs, popfirst!(ex))
    end
    if length(ex) < 1
        throw(ArgumentError("Invalid usage of @signpost_event: expected at least 1 positional argument"))
    end
    name = popfirst!(ex)
    msg = isempty(ex) ? "" : popfirst!(ex)

    # parse the keyword arguments
    log_ex = :($OSLog())
    for kwarg in kwargs
        key, value = kwarg.args
        if key == :log
            log_ex = value
        else
            throw(ArgumentError("Invalid keyword argument to @signpost_event: $kwarg"))
        end
    end

    quote
        log = $(esc(log_ex))
        if is_signpost_enabled(log)
            os_signpost_emit_with_type(log, OSSignpostNull(), SIGNPOST_EVENT, $(esc(name)), $(esc(msg)))
        end
    end
end

end
