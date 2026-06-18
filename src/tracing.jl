# Runtime, low-overhead Objective-C call tracing (à la CUPTI's callback API).
#
# This is distinct from the compile-time `tracing` preference (which just prints every call
# to stderr for debugging). Here a consumer registers a callback at runtime with `subscribe`,
# and it is invoked for every Objective-C message send with the class and selector — both
# known as compile-time constants at the `@objc` chokepoint — plus enter/exit timestamps.
#
# Cost model: the hook is compiled into every `@objc` site unconditionally, but when no
# subscriber is registered the cost is a single relaxed load of `_tracing_subscriber` plus a
# predicted-not-taken branch (and no clock read). Toggling needs neither a preference nor
# recompilation. This trades a tiny always-present cost for instant, invalidation-free
# toggling — see the message-send codegen in `syntax.jl`.

# The active subscriber, read once at every `@objc` call. `nothing` ⇒ tracing disabled.
const _tracing_subscriber = Ref{Any}(nothing)

# Monotonic clock for call timing. Returns raw `mach_absolute_time` ticks, which on Apple
# Silicon are NOT nanoseconds (see `tracing_timebase`); convert when reporting. This shares
# the clock domain of CoreAnimation / Metal GPU timestamps (unlike Julia's `time_ns`).
@inline _tracing_clock() = ccall(:mach_absolute_time, UInt64, ())

"""
    ObjectiveC.tracing_timebase() -> Float64

Nanoseconds per `mach_absolute_time` tick, for converting the raw timestamps handed to a
tracing callback (see [`subscribe`](@ref)) into nanoseconds.
"""
function tracing_timebase()
    tb = Ref{NTuple{2,UInt32}}((0, 0))
    ccall(:mach_timebase_info, Cint, (Ref{NTuple{2,UInt32}},), tb)
    numer, denom = tb[]
    return numer / denom
end

_maxthreadid() = isdefined(Threads, :maxthreadid) ? Threads.maxthreadid() : Threads.nthreads()

# Per-thread reentrancy guard: a subscriber callback may itself issue `@objc` calls (e.g. to
# inspect an object), which would otherwise recurse. Sized at `subscribe` time.
const _tracing_guard = Bool[]

# Invoked (only when a subscriber is registered) around each message send. Kept out of line so
# the inlined hot path is just the load + branch.
@noinline function _tracing_dispatch(@nospecialize(sub), class::Symbol, sel::Symbol,
                                     t0::UInt64, t1::UInt64)
    tid = Threads.threadid()
    @inbounds if tid <= length(_tracing_guard) && !_tracing_guard[tid]
        _tracing_guard[tid] = true
        try
            sub(class, sel, t0, t1)
        catch err
            # a faulty callback must never take down the traced program; disable and report
            _tracing_subscriber[] = nothing
            @error "ObjectiveC.jl tracing callback failed; tracing disabled" exception=(err, catch_backtrace())
        finally
            _tracing_guard[tid] = false
        end
    end
    return
end

"""
    ObjectiveC.subscribe(callback) -> callback

Register `callback` to be invoked for every Objective-C message send, as

    callback(class::Symbol, selector::Symbol, t_enter::UInt64, t_exit::UInt64)

where the timestamps are raw `mach_absolute_time` ticks (convert with
[`tracing_timebase`](@ref)). Only one subscriber may be active at a time; call
[`unsubscribe`](@ref) to remove it.

The callback runs synchronously on the calling thread around each call, behind a reentrancy
guard (so it may itself issue `@objc` calls — those are not traced). Keep it cheap:
accumulate into a preallocated structure and defer expensive processing until after
`unsubscribe`. A callback that throws is removed and the error reported.
"""
function subscribe(@nospecialize(callback))
    _tracing_subscriber[] === nothing ||
        error("ObjectiveC.jl already has a tracing subscriber; call `unsubscribe()` first.")
    resize!(_tracing_guard, _maxthreadid())
    fill!(_tracing_guard, false)
    _tracing_subscriber[] = callback
    return callback
end

"""
    ObjectiveC.unsubscribe()

Remove the active tracing subscriber registered with [`subscribe`](@ref).
"""
function unsubscribe()
    _tracing_subscriber[] = nothing
    return
end
