# Runtime, low-overhead Objective-C call tracing, using a CUPTI-style callback API.
#
@public tracing_subscribe, tracing_unsubscribe, tracing_timebase

# This is distinct from the compile-time `tracing` preference (which just prints every call
# to stderr for debugging). Here a consumer registers a callback at runtime, and it is
# invoked for every Objective-C message send with the class and selector - both
# known as compile-time constants at the `@objc` chokepoint - plus enter/exit timestamps.
#
# Cost model: the hook is compiled into every `@objc` site unconditionally, but when no
# subscriber is registered the cost is one global read plus a predicted-not-taken branch
# (and no clock read). Toggling needs neither a preference nor
# recompilation. This trades a tiny always-present cost for instant, invalidation-free
# toggling. See the message-send codegen in `syntax.jl`.

# The active subscriber token, read once at every `@objc` call. `C_NULL` means tracing is
# disabled. We keep retired wrappers rooted for the session: a call site may have loaded a
# wrapper immediately before entering the GC-safe `objc_msgSend`, and another thread may
# unsubscribe while that call is in flight. Retaining only the tiny wrapper (with its callback
# cleared) avoids adding rooting overhead to every traced message send.
mutable struct TracingSubscriber
    callback::Any
    retired::Bool
end
TracingSubscriber(callback) = TracingSubscriber(callback, false)

const tracing_subscriber = Ref{Ptr{Cvoid}}(C_NULL)
const active_tracing_subscriber = Ref{Union{Nothing,TracingSubscriber}}(nothing)
const retired_tracing_subscribers = TracingSubscriber[]
const tracing_subscriber_lock = ReentrantLock()

# Monotonic clock for call timing. Returns raw `mach_absolute_time` ticks, which on Apple
# Silicon are NOT nanoseconds (see `tracing_timebase`); convert when reporting. This shares
# the clock domain of CoreAnimation / Metal GPU timestamps (unlike Julia's `time_ns`).
@inline tracing_clock() = ccall(:mach_absolute_time, UInt64, ())

"""
    ObjectiveC.tracing_timebase() -> Float64

Nanoseconds per `mach_absolute_time` tick, for converting the raw timestamps handed to a
tracing callback (see [`tracing_subscribe`](@ref)) into nanoseconds.
"""
function tracing_timebase()
    tb = Ref{NTuple{2,UInt32}}((0, 0))
    ccall(:mach_timebase_info, Cint, (Ref{NTuple{2,UInt32}},), tb)
    numer, denom = tb[]
    return numer / denom
end

max_thread_id() = isdefined(Threads, :maxthreadid) ? Threads.maxthreadid() : Threads.nthreads()

# Per-thread reentrancy guard: a subscriber callback may itself issue `@objc` calls (e.g. to
# inspect an object), which would otherwise recurse. Sized at `tracing_subscribe` time.
const tracing_guard = Bool[]

function ensure_tracing_guard()
    n = max_thread_id()
    old_n = length(tracing_guard)
    if old_n < n
        resize!(tracing_guard, n)
        tracing_guard[old_n+1:n] .= false
    end
    return
end

function retire_tracing_subscriber(sub::TracingSubscriber)
    sub.callback = nothing
    if !sub.retired
        push!(retired_tracing_subscribers, sub)
        sub.retired = true
    end
    return
end

# Invoked (only when a subscriber is registered) around each message send. Kept out of line so
# the inlined hot path is just the load + branch.
@noinline function tracing_dispatch(sub_ptr::Ptr{Cvoid}, class::Symbol, sel::Symbol,
                                    t0::UInt64, t1::UInt64)
    sub = Base.unsafe_pointer_to_objref(sub_ptr)::TracingSubscriber
    callback = sub.callback
    callback === nothing && return

    tid = Threads.threadid()
    @inbounds if tid <= length(tracing_guard) && !tracing_guard[tid]
        tracing_guard[tid] = true
        try
            callback(class, sel, t0, t1)
        catch err
            # a faulty callback must never take down the traced program; disable and report
            lock(tracing_subscriber_lock) do
                retire_tracing_subscriber(sub)
                if active_tracing_subscriber[] === sub
                    active_tracing_subscriber[] = nothing
                    tracing_subscriber[] = C_NULL
                end
            end
            @error "ObjectiveC.jl tracing callback failed; tracing disabled" exception=(err, catch_backtrace())
        finally
            tracing_guard[tid] = false
        end
    end
    return
end

"""
    ObjectiveC.tracing_subscribe(callback) -> callback

Register `callback` to be invoked for every Objective-C message send, as

    callback(class::Symbol, selector::Symbol, t_enter::UInt64, t_exit::UInt64)

where the timestamps are raw `mach_absolute_time` ticks (convert with
[`tracing_timebase`](@ref)). Only one tracing subscriber may be active at a time; call
[`tracing_unsubscribe`](@ref) to remove it.

The callback runs synchronously on the calling thread around each call, behind a reentrancy
guard (so it may itself issue `@objc` calls; those are not traced). Keep it cheap:
accumulate into a preallocated structure and defer expensive processing until after
`tracing_unsubscribe`. A callback that throws is removed and the error reported.
"""
function tracing_subscribe(@nospecialize(callback))
    lock(tracing_subscriber_lock) do
        active_tracing_subscriber[] === nothing ||
            error("ObjectiveC.jl already has a tracing subscriber; call `tracing_unsubscribe()` first.")
        ensure_tracing_guard()
        sub = TracingSubscriber(callback)
        active_tracing_subscriber[] = sub
        tracing_subscriber[] = Base.pointer_from_objref(sub)
    end
    return callback
end

"""
    ObjectiveC.tracing_unsubscribe()

Remove the active tracing subscriber registered with [`tracing_subscribe`](@ref).
"""
function tracing_unsubscribe()
    lock(tracing_subscriber_lock) do
        sub = active_tracing_subscriber[]
        if sub !== nothing
            retire_tracing_subscriber(sub)
            active_tracing_subscriber[] = nothing
            tracing_subscriber[] = C_NULL
        end
    end
    return
end
