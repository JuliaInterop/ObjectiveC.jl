# Wrappers for the OS framework

module OS

using ..CEnum

# These aren't really ObjectiveC, but they're really only relevant on macOS.
# TODO: Move to Metal.jl, or to a separate macOS.jl package?


## static strings

# Unified logging does not copy the name and format strings of a message into the log.
# It records their offsets relative to the Mach-O image passed as `dso`, together with
# that image's UUID, and the strings are read from the image's on-disk __TEXT segment when
# the log is decoded (by `log show`, Instruments, ...). Messages whose `dso` is not a
# loaded image are dropped, and strings outside of the image decode as
# `<compose failure [UUID]>`.
#
# Julia string literals live on the heap or in a data section, so we materialize the
# strings as private LLVM constants using `llvmcall`. When the (non-inlined)
# specialization of `static_strings` is compiled into a package image, these constants
# end up in that image's __TEXT,__cstring section, and the weak `__dso_handle` reference
# resolves to the image's Mach-O header. JIT-compiled specializations are not part of an
# image; their `__dso_handle` is NULL, and callers fall back to `fallback_strings()`.

struct StaticStrings
    dso::Ptr{Cvoid}
    name::Ptr{UInt8}
    format::Ptr{UInt8}
end

const NO_STRINGS = StaticStrings(C_NULL, C_NULL, C_NULL)

function llvm_cstring(str::String)
    bytes = codeunits(str)
    0x00 in bytes && throw(ArgumentError("Static strings cannot contain NUL characters"))
    init = sprint() do io
        print(io, "c\"")
        for b in bytes
            if 0x20 <= b <= 0x7e && b != UInt8('"') && b != UInt8('\\')
                write(io, b)
            else
                print(io, '\\', string(b, base=16, pad=2))
            end
        end
        print(io, "\\00\"")
    end
    return "[$(length(bytes)+1) x i8]", init
end

# IR for a function returning the address of a global
function address_ir(name::String, def::String, typ::String)
    ptr = VERSION >= v"1.11-" ? "ptr" : "$typ*"
    """
    @$name = $def
    define i64 @entry() #0 {
        ret i64 ptrtoint ($ptr @$name to i64)
    }
    attributes #0 = { alwaysinline }
    """
end
# the linker defines `__dso_handle` as the Mach-O header of the image being linked
dso_ir() = address_ir("__dso_handle", "extern_weak hidden global i8", "i8")
function cstring_ir(str::String)
    typ, init = llvm_cstring(str)
    # Julia 1.10 confuses identically-named private globals of different `llvmcall`s
    name = "julia_static_string_" * string(hash(str), base=16)
    # `unnamed_addr` lets the string go into __cstring instead of __const, which the log
    # decoder does not read (Apple uses __oslogstring, but pkgimages drop that section)
    address_ir(name, "private unnamed_addr constant $typ $init, align 1", typ)
end

@generated function _static_strings(::Val{name}, ::Val{format}) where {name, format}
    # a GlobalRef makes Julia compile this code also when it would otherwise interpret it
    # (e.g. with `--compile=min`), which does not support `llvmcall`
    llvmcall = GlobalRef(Core.Intrinsics, :llvmcall)
    quote
        Base.@_inline_meta
        StaticStrings(
            reinterpret(Ptr{Cvoid},
                        $llvmcall(($(dso_ir()), "entry"), UInt64, Tuple{})),
            reinterpret(Ptr{UInt8},
                        $llvmcall(($(cstring_ir(String(name))), "entry"), UInt64, Tuple{})),
            reinterpret(Ptr{UInt8},
                        $llvmcall(($(cstring_ir(String(format))), "entry"), UInt64, Tuple{})))
    end
end

"""
    static_strings(Val(name::Symbol), Val(format::Symbol))

Return the image handle and addresses of the C strings `name` and `format`, as stored in
the package image that contains the native code of this specialization. The `dso` field
is `C_NULL` if the specialization was JIT-compiled.

This function must not be inlined: the native code containing the strings has to stay in
the image it was compiled into, also when called from JIT-compiled code. The result holds
addresses, so it must not be stored in a global while precompiling.
"""
@noinline static_strings(name::Val, format::Val) = _static_strings(name, format)

const PUBLIC_STRING = Val(Symbol("%{public}s"))

# Strings to use when no static strings are available, i.e., for dynamic names or call
# sites that were not precompiled. The name is then prepended to the message. These
# contain addresses, so they are determined anew in every session, by `__init__`.
const fallback = Ref(NO_STRINGS)
fallback_strings() = fallback[]
function find_fallback_strings()
    strings = static_strings(Val(:Julia), PUBLIC_STRING)
    if strings.dso == C_NULL
        # ObjectiveC.jl itself was not precompiled into a package image
        strings = shared_cache_strings()
    end
    return strings
end

# Borrow a "%s" string from libobjc, which is part of the dyld shared cache and thus
# always has its strings available to the log decoder. Signposts then show as named "%s".
function shared_cache_strings()
    header = C_NULL
    for i in 0:(@ccall _dyld_image_count()::UInt32)-1
        name = @ccall _dyld_get_image_name(i::UInt32)::Cstring
        if name != C_NULL && unsafe_string(name) == "/usr/lib/libobjc.A.dylib"
            header = @ccall _dyld_get_image_header(i::UInt32)::Ptr{Cvoid}
            break
        end
    end
    header == C_NULL && return NO_STRINGS
    size = Ref{Culong}(0)
    data = @ccall getsectiondata(header::Ptr{Cvoid}, "__TEXT"::Cstring, "__cstring"::Cstring,
                                 size::Ptr{Culong})::Ptr{UInt8}
    data == C_NULL && return NO_STRINGS
    bytes = unsafe_wrap(Vector{UInt8}, data, size[])
    # any NUL-terminated string ending in %s will do
    idx = findfirst(UInt8['%', 's', 0x00], bytes)
    idx === nothing && return NO_STRINGS
    str = data + first(idx) - 1
    return StaticStrings(header, str, str)
end

# select the strings and message to use for a given name
@inline function resolve_strings(strings::StaticStrings, name, msg)
    msg = string(msg)::String
    if strings.dso == C_NULL
        strings = fallback_strings()
        msg = isempty(msg) ? string(name)::String : string(name, ": ", msg)
    end
    return strings, msg
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

log_strings() = static_strings(Val(Symbol("")), PUBLIC_STRING)

@inline function os_log_with_type(log::OSLog, type::os_log_type_t, str::String)
    image_strings = log_strings()
    strings = image_strings.dso == C_NULL ? fallback_strings() : image_strings
    strings.dso == C_NULL && return
    os_log_call(str) do buf
        @ccall _os_log_impl(strings.dso::Ptr{Cvoid}, log::os_log_t, type::os_log_type_t,
                            strings.format::Ptr{UInt8}, buf::Ref{UInt8},
                            sizeof(buf)::UInt32)::Cvoid
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

# NOTE: contrary to Apple's implementation, we do not check if signposts are enabled
#       but assume that the user has already done so. by checking earlier, it's
#       possible to also avoid the string formatting and further reduce overhead.
function os_signpost_emit_with_type(log::OSLog, signpost::OSSignpost,
                                    type::os_signpost_type_t, strings::StaticStrings,
                                    name, msg)
    strings, msg = resolve_strings(strings, name, msg)
    strings.dso == C_NULL && return
    os_log_call(msg) do buf
        @ccall _os_signpost_emit_with_name_impl(strings.dso::Ptr{Cvoid},
                                                log::os_log_t, type::os_signpost_type_t,
                                                signpost::os_signpost_id_t,
                                                strings.name::Ptr{UInt8},
                                                strings.format::Ptr{UInt8},
                                                buf::Ref{UInt8},
                                                sizeof(buf)::UInt32)::Cvoid
    end
end
os_signpost_emit_with_type(log::OSLog, signpost::OSSignpost, type::os_signpost_type_t,
                           name, msg) =
    os_signpost_emit_with_type(log, signpost, type, NO_STRINGS, name, msg)

interval_begin(log::OSLog, signpost::OSSignpost, name, msg="") =
    os_signpost_emit_with_type(log, signpost, SIGNPOST_INTERVAL_BEGIN, name, msg)
interval_begin(log::OSLog, signpost::OSSignpost, strings::StaticStrings, name, msg="") =
    os_signpost_emit_with_type(log, signpost, SIGNPOST_INTERVAL_BEGIN, strings, name, msg)

interval_end(log::OSLog, signpost::OSSignpost, name, msg="") =
    os_signpost_emit_with_type(log, signpost, SIGNPOST_INTERVAL_END, name, msg)
interval_end(log::OSLog, signpost::OSSignpost, strings::StaticStrings, name, msg="") =
    os_signpost_emit_with_type(log, signpost, SIGNPOST_INTERVAL_END, strings, name, msg)

# Like a try-finally block, except without introducing the try scope
# NOTE: This is deprecated and should not be used from user logic. A proper solution to
# this problem will be introduced in https://github.com/JuliaLang/julia/pull/39217
macro __tryfinally(ex, fin)
    Expr(:tryfinally,
       :($(esc(ex))),
       :($(esc(fin)))
       )
end

# Signpost names must be static strings; see `static_strings`. String literals are
# materialized in the image of the caller, other names use the fallback strings.
function signpost_strings(name)
    name isa String || return NO_STRINGS
    name_val = Val(Symbol(name))
    if ccall(:jl_generating_output, Cint, ()) == 1
        # make sure the strings end up in the image that is being generated, even if the
        # code containing the signpost is not compiled during precompilation
        precompile(static_strings, (typeof(name_val), typeof(PUBLIC_STRING)))
    end
    :($static_strings($name_val, $PUBLIC_STRING))
end

"""
    @signpost_interval [kwargs...] name ex

Run `ex` within a signposted interval called `name`.

For the name to show up in Instruments, it has to be a string literal, and the code has
to be part of a package image. Otherwise, the interval is called "Julia" and the name is
prepended to the messages.

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
            local strings = $(signpost_strings(name))
            local name = $(esc(name))
            local start_msg = $(esc(start_ex))
            interval_begin(log, signpost, strings, name, start_msg)
            local stop_msg = "error"
            @__tryfinally(begin
                ret = $(esc(code))
                stop_msg = $(esc(stop_ex))
                ret
            end, begin
                interval_end(log, signpost, strings, name, stop_msg)
            end)
        else
            $(esc(code))
        end
    end
end

"""
    @signpost_event [kwargs...] name [message]

Emit a signposted event with the given `name` and optional `message`.

The same restrictions on `name` apply as for [`@signpost_interval`](@ref).

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
            os_signpost_emit_with_type(log, OSSignpostNull(), SIGNPOST_EVENT,
                                       $(signpost_strings(name)), $(esc(name)), $(esc(msg)))
        end
    end
end


## initialization

function __init__()
    # the package can be loaded on other platforms, e.g., by packages that depend on it
    Sys.isapple() && (fallback[] = find_fallback_strings())
end


## precompilation

precompile(find_fallback_strings, ())
precompile(static_strings, (Val{:Julia}, typeof(PUBLIC_STRING)))
precompile(log_strings, ())
precompile(static_strings, (Val{Symbol("")}, typeof(PUBLIC_STRING)))

end
