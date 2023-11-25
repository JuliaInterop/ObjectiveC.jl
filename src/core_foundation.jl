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

if sizeof(Int) == 8
    const CFOptionFlags = Culonglong
else
    const CFOptionFlags = Culong
end


# CFAllocator

export CFAllocator, default_allocator, system_default_allocator,
       malloc_allocator, malloc_zone_allocator,
       allocate!, reallocate!, deallocate!, preferred_size

struct __CFAllocator end
const CFAllocatorRef = Ptr{__CFAllocator}

struct CFAllocator
    ref::CFAllocatorRef
end
Base.unsafe_convert(::Type{CFAllocatorRef}, alloc::CFAllocator) = alloc.ref

default_allocator() = CFAllocator(C_NULL)
system_default_allocator() = CFAllocator(unsafe_load(cglobal(:kCFAllocatorSystemDefault, CFAllocatorRef)))
malloc_allocator() = CFAllocator(unsafe_load(cglobal(:kCFAllocatorMalloc, CFAllocatorRef)))
malloc_zone_allocator() = CFAllocator(unsafe_load(cglobal(:kCFAllocatorMallocZone, CFAllocatorRef)))
null_allocator() = CFAllocator(unsafe_load(cglobal(:kCFAllocatorNull, CFAllocatorRef)))

function allocate!(allocator::CFAllocator, size, hint=0)
    @ccall CFAllocatorAllocate(
        allocator::CFAllocatorRef,
        size::CFIndex,
        hint::CFOptionFlags
    )::Ptr{Cvoid}
end

function reallocate!(allocator::CFAllocator, ptr, size, hint=0)
    @ccall CFAllocatorReallocate(
        allocator::CFAllocatorRef,
        ptr::Ptr{Cvoid},
        size::CFIndex,
        hint::CFOptionFlags
    )::Ptr{Cvoid}
end

function deallocate!(allocator::CFAllocator, ptr)
    @ccall CFAllocatorDeallocate(
        allocator::CFAllocatorRef,
        ptr::Ptr{Cvoid}
    )::Cvoid
end

function preferred_size(allocator::CFAllocator, size, hint=0)
    @ccall CFAllocatorPreferredSizeForSize(
        allocator::CFAllocatorRef,
        size::CFIndex,
        hint::CFOptionFlags
    )::CFIndex
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

# encodings
@cenum CFStringEncoding::UInt32 begin
    EncodingMacRoman = 0
    EncodingWindowsLatin1 = 0x0500
    EncodingISOLatin1 = 0x0201
    EncodingNextStepLatin = 0x0B01
    EncodingASCII = 0x0600
    EncodingUnicode = 0x0100
    EncodingUTF8 = 0x08000100
    EncodingNonLossyASCII = 0x0BFF
    EncodingUTF16 = 0x0100
    EncodingUTF16BE = 0x10000100
    EncodingUTF16LE = 0x14000100
    EncodingUTF32 = 0x0c000100
    EncodingUTF32BE = 0x18000100
    EncodingUTF32LE = 0x1c000100
end

# conversion to Julia string
function Base.String(str::CFString)
    len = length(str)
    buf = Vector{UInt16}(undef, len)
    ccall(:CFStringGetCharacters, Nothing, (CFStringRef, CFRange, Ptr{UniChar}), str, CFRange(0, len), buf)
    String(Char.(buf))
end
Base.string(str::CFString) = String(str)

# conversion from ASCII Julia string
function CFString(str::String)
    ref = @ccall CFStringCreateWithCString(
        default_allocator()::CFAllocatorRef,
        str::Cstring,
        EncodingUTF8::CFStringEncoding
    )::CFStringRef
    CFString(ref)
end
Base.cconvert(::Type{CFStringRef}, str::String) = CFString(str)

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


# CFDictionary

export CFDictionary

struct __CFDictionary end
const CFDictionaryRef = Ptr{__CFDictionary}

struct CFDictionary
    ref::CFDictionaryRef
end
Base.unsafe_convert(::Type{CFDictionaryRef}, dict::CFDictionary) = dict.ref


# CFNotificationCenter

export CFNotificationCenter, local_notify_center, darwin_notify_center,
       CFNotificationObserver, add_observer!, remove_observer!, remove_every_observer!,
       post_notification!

const CFNotificationName = CFStringRef

struct __CFNotificationCenter end
const CFNotificationCenterRef = Ptr{__CFNotificationCenter}

struct CFNotificationCenter
    ref::CFNotificationCenterRef
end
Base.unsafe_convert(::Type{CFNotificationCenterRef}, center::CFNotificationCenter) = center.ref

local_notify_center() = CFNotificationCenter(ccall(:CFNotificationCenterGetLocalCenter, CFNotificationCenterRef, ()))

darwin_notify_center() =
    CFNotificationCenter(ccall(:CFNotificationCenterGetDarwinNotifyCenter, CFNotificationCenterRef, ()))

const CFNotificationCallback = Ptr{Cvoid}   # @cfunction is untyped

@cenum CFNotificationSuspensionBehavior::CFIndex begin
    SuspensionBehaviorDrop = 1
    SuspensionBehaviorCoalesce = 2
    SuspensionBehaviorHold = 3
    SuspensionBehaviorDeliverImmediately = 4
end

mutable struct CFNotificationObserver
    callback::Base.Callable
end

function observer_callback(center, observer_ptr, name, object, user_info)
    observer = Base.unsafe_pointer_to_objref(observer_ptr)
    observer.callback(CFNotificationCenter(center), CFString(name), object,
                      CFDictionary(user_info))
    return
end

function add_observer!(center::CFNotificationCenter, observer::CFNotificationObserver;
                       name=nothing, object=nothing,
                       suspension_behavior=SuspensionBehaviorDeliverImmediately)
    callback_ptr = @cfunction(observer_callback, Nothing, (CFNotificationCenterRef, Ptr{Cvoid},
                              CFNotificationName, Ptr{Cvoid}, CFDictionaryRef))
    @ccall CFNotificationCenterAddObserver(
        center::CFNotificationCenterRef,
        Base.pointer_from_objref(observer)::Ptr{Cvoid},
        callback_ptr::CFNotificationCallback,
        something(name, C_NULL)::CFNotificationName,
        something(object, C_NULL)::Ptr{Cvoid},
        suspension_behavior::CFNotificationSuspensionBehavior
    )::Cvoid

    return
end

function remove_observer!(center::CFNotificationCenter, observer::CFNotificationObserver;
                          name=nothing, object=nothing)
    if name === nothing && object === nothing
        @ccall CFNotificationCenterRemoveEveryObserver(
            center::CFNotificationCenterRef,
            Base.pointer_from_objref(observer)::Ptr{Cvoid}
        )::Cvoid
    else
        @ccall CFNotificationCenterRemoveObserver(
            center::CFNotificationCenterRef,
            Base.pointer_from_objref(observer)::Ptr{Cvoid},
            something(name, C_NULL)::CFNotificationName,
            something(object, C_NULL)::Ptr{Cvoid}
        )::Cvoid
    end
end

@cenum NotificationFlags::CFOptionFlags begin
    DeliverImmediately = 1
    PostToAllSessions = 2
end

function post_notification!(center::CFNotificationCenter, name;
                            object=nothing, user_info=nothing, options=0)
    @ccall CFNotificationCenterPostNotificationWithOptions(
        center::CFNotificationCenterRef,
        name::CFNotificationName,
        something(object, C_NULL)::Ptr{Cvoid},
        something(user_info, C_NULL)::CFDictionaryRef,
        options::CFOptionFlags
    )::Cvoid
end

end
