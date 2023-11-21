module CoreFoundation

using ..ObjectiveC
using ..CEnum


# CFBase

export CFIndex, CFRange

const Boolean = Cchar
const UniChar = Cushort

if sizeof(Int) == 8
    const CFIndex = Clonglong
else
    const CFIndex = Clong
end

struct CFRange
    location::CFIndex
    length::CFIndex
end


# CFString

export CFString

# TODO: toll-free bridging with NSString

struct __CFString end
const CFStringRef = Ptr{__CFString}

struct CFString
    ref::CFStringRef
end
Base.unsafe_convert(::Type{CFStringRef}, str::CFString) = str.ref

Base.length(str::CFString) = ccall(:CFStringGetLength, CFIndex, (CFStringRef,), str)

function Base.getindex(str::CFString, i::Int)
    @boundscheck if i < 1 || i > length(str)
        throw(BoundsError(str, i))
    end
    Char(ccall(:CFStringGetCharacterAtIndex, UniChar, (CFStringRef, CFIndex), str, i-1))
end

function Base.String(str::CFString)
    len = length(str)
    buf = Vector{UInt16}(undef, len)
    ccall(:CFStringGetCharacters, Nothing, (CFStringRef, CFRange, Ptr{UniChar}), str, CFRange(0, len), buf)
    String(Char.(buf))
end
Base.string(str::CFString) = String(str)

function Base.show(io::IO, str::CFString)
    print(io, "CFString(\"", String(str), "\")")
end


# CFDate

export CFTimeInterval

const CFTimeInterval = Cdouble


# CFRunLoop

export CFRunLoop, current_loop, main_loop, run_loop, wake_loop, stop_loop, loop_waiting

const CFRunLoopMode = CFStringRef

default_loop_mode() = CFString(unsafe_load(cglobal(:kCFRunLoopDefaultMode, CFStringRef)))
common_loop_modes() = CFString(unsafe_load(cglobal(:kCFRunLoopCommonModes, CFStringRef)))

@cenum CFRunLoopRunResult::Int32 begin
    RunLoopRunFinished = 1
    RunLoopRunStopped = 2
    RunLoopRunTimedOut = 3
    RunLoopRunHandledSource = 4
end

struct __CFRunLoopSourceContext end
const CFRunLoopRef = Ptr{__CFRunLoopSourceContext}

struct CFRunLoop
    ref::CFRunLoopRef
end
Base.unsafe_convert(::Type{CFRunLoopRef}, loop::CFRunLoop) = loop.ref

current_loop() = CFRunLoop(ccall(:CFRunLoopGetCurrent, CFRunLoopRef, ()))
main_loop() = CFRunLoop(ccall(:CFRunLoopGetMain, CFRunLoopRef, ()))

run_loop() = ccall(:CFRunLoopRun, Nothing, ())

function run_loop(seconds; mode=default_loop_mode(), return_after_source_handled=false)
    ccall(:CFRunLoopRunInMode, CFRunLoopRunResult, (CFRunLoopMode, CFTimeInterval, Boolean), mode, seconds, return_after_source_handled)
end

wake_loop(loop::CFRunLoop) = ccall(:CFRunLoopWakeUp, Nothing, (CFRunLoopRef,), loop)
stop_loop(loop::CFRunLoop) = ccall(:CFRunLoopStop, Nothing, (CFRunLoopRef,), loop)
loop_waiting(loop::CFRunLoop) = ccall(:CFRunLoopIsWaiting, Boolean, (CFRunLoopRef,), loop) != 0

end
