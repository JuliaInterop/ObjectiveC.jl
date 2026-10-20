module Foundation

using ..ObjectiveC
using ..CEnum


export NSInteger, MSIntegerMin, NSIntegerMax, NSUInteger, NSUIntegerMax

if sizeof(Ptr{Cvoid}) == 8
    const NSInteger = Int64
    const NSUInteger = UInt64
else
    const NSInteger = Int32
    const NSUInteger = UInt32
end
const NSIntegerMin = typemin(NSInteger)
const NSIntegerMax = typemax(NSInteger)
const NSUIntegerMax = typemax(NSUInteger)


export NSObject, retain, release, autorelease, is_kind_of

ObjectiveC.@public checked_release, unsafe_release, adopt

@objcwrapper NSObject <: Object

# forward declaration
@objcwrapper comparison = false NSString <: NSObject

@objcproperties NSObject begin
    @autoproperty hash::NSUInteger
    @autoproperty description::id{NSString}
    @autoproperty debugDescription::id{NSString}

    @autoproperty retainCount::NSUInteger
end

function Base.show(io::IO, ::MIME"text/plain", obj::NSObjectLike)
    if get(io, :compact, false)
        print(io, String(obj.description))
    else
        print(io, String(obj.debugDescription))
    end
end

"""
    unsafe_release(obj)

Send a raw Objective-C `release` message. This is the primitive release
operation; package authors may extend it for wrapper families with nonstandard
release primitives, such as dispatch objects. Deallocation may autorelease objects, so
such extensions should release within an [`@unsafe_autoreleasepool`](@ref).
"""
unsafe_release(obj::Object) =
    @objc [obj::id{Object} release]::Cvoid

"""
    checked_release(obj)

Release the owned reference of a managed wrapper at most once. Package authors
who need to wrap release-time behavior should extend `release(obj::T)` and call
`checked_release(obj)` from that method.
"""
function checked_release(obj::Object)
    (@atomicswap :acquire_release obj.owned = false) || return nothing
    unsafe_release(obj)
    return nothing
end

"""
    release(obj)

Release an Objective-C object.

For managed wrappers, this eagerly releases the wrapper's owned reference and
is safe to call more than once or before the finalizer runs. For borrowed
managed wrappers created with the bare `T(ptr)` constructor, this is a no-op.
For unmanaged wrappers, this sends the raw Objective-C release message.
"""
release(obj::Object) =
    ObjectiveC.is_managed_wrapper(typeof(obj)) ? checked_release(obj) : unsafe_release(obj)

"""
    autorelease(obj)

Manually autorelease an Objective-C object. This is for unmanaged wrappers and raw
manual-ownership code, and only makes sense within an [`@unsafe_autoreleasepool`](@ref):
`@objc` calls run in their own pools, so they cannot be used to autorelease objects.
"""
autorelease(obj::Object) =
    ccall(:objc_autorelease, id{Object}, (id{Object},), obj)

"""
    retain(obj)

Manually retain an Objective-C object and return the raw Objective-C result.
Prefer `retain(T, ptr)` for borrowed pointers that should become managed
wrappers.
"""
retain(obj::Object) =
    ccall(:objc_retain, id{Object}, (id{Object},), obj)

is_kind_of(obj::NSObjectLike, class::Class) =
    @objc [obj::id{NSObject} isKindOfClass:class::Class]::Bool

function check_managed_type(::Type{T}) where {T<:Object}
    ObjectiveC.is_managed_wrapper(T) ||
        throw(ArgumentError("$T is not managed; declare it with `@objcwrapper managed=true`"))
    return nothing
end

function attach_managed_finalizer(obj::Object)
    @atomic obj.owned = true
    finalizer(release, obj)
    return obj
end

"""
    adopt(T, ptr)

Wrap a +1 Objective-C object pointer, such as a result from a `new`, `alloc`,
`copy`, or `mutableCopy` family method, and release it from a Julia finalizer.
This does not retain the object. The bare `T(ptr)` constructor is non-owning.
You may call `release` on the returned wrapper to release it before the
finalizer runs.
"""
function adopt(::Type{T}, ptr::id) where {T<:Object}
    check_managed_type(T)
    return attach_managed_finalizer(T(ptr))
end

"""
    retain(T, ptr)

Retain a borrowed +0 Objective-C object pointer, wrap it as `T`, and release it
from a Julia finalizer. Use this for autoreleased objects that must escape their
autorelease pool.
You may call `release` on the returned wrapper to release it before the
finalizer runs.
"""
function retain(::Type{T}, ptr::id) where {T<:Object}
    check_managed_type(T)
    obj = T(ptr)
    retain(obj)
    return attach_managed_finalizer(obj)
end

export @unsafe_autoreleasepool

"""
    @unsafe_autoreleasepool expr

Evaluate `expr` within an Objective-C autorelease pool, releasing the objects it
autoreleased when it finishes.

This is not needed for `@objc` calls returning objects or values, as every such call
already runs in its own pool and takes ownership of what it returns. Use it for code that
works with raw pointers whose lifetime depends on an autorelease pool, e.g., the `+0`
`::id{T}` or `::Ptr{T}` results of `@objc` calls, until it has copied or retained what
it needs.

!!! warning

    `expr` must not yield to the scheduler. Autorelease pools are a per-thread stack,
    so a task switch could let another task push or pop a pool in between, which aborts
    the process or releases objects that are still in use.
"""
macro unsafe_autoreleasepool(ex)
    quote
        pool = ccall(:objc_autoreleasePoolPush, Ptr{Cvoid}, ())
        try
            $(esc(ex))
        finally
            ccall(:objc_autoreleasePoolPop, Cvoid, (Ptr{Cvoid},), pool)
        end
    end
end


# Default equality for ObjC objects via `isEqual:`. Specific classes can
# override this for a faster path (NSString, NSURL, etc. already do).
Base.:(==)(obj1::NSObjectLike, obj2::NSObjectLike) =
    @objc [obj1::id{NSObject} isEqual:obj2::id{NSObject}]::Bool


export NSRange

struct NSRange
    location::NSUInteger
    length::NSUInteger
end

Base.length(r::NSRange) = r.length
Base.first(r::NSRange) = r.location
Base.last(r::NSRange) = r.location + r.length - 1

Base.cconvert(::Type{NSRange}, r::UnitRange{<:Integer}) = NSRange(first(r), length(r))


export NSValue

@objcwrapper comparison = false NSValue <: NSObject

Base.:(==)(v1::NSValue, v2::NSValue) =
    @objc [v1::id{NSValue} isEqualToValue:v2::id{NSValue}]::Bool

@objcproperties NSValue begin
    @autoproperty objCType::Ptr{Cchar}
    @autoproperty pointerValue::Ptr{Cvoid}
    @autoproperty rangeValue::NSRange
    # ...
end

NSValue(x::Ptr) = @objc [NSValue valueWithPointer:x::Ptr{Cvoid}]::NSValue
NSValue(x::Union{NSRange,UnitRange}) =
    @objc [NSValue valueWithRange:x::NSRange]::NSValue
# ...


export NSDecimal

const NSDecimalMaxSize = 8
struct NSDecimal
    # an integer from –128 through 127
    exponent::Int8

    # unsigned int _length:4;
    #   length == 0 && isNegative -> NaN
    # unsigned int _isNegative:1;
    # unsigned int _isCompact:1;
    # unsigned int _reserved:18
    flags::UInt8
    _reserved1::UInt8
    _reserved2::UInt8

    # a decimal integer up to 38 digits long
    mantissa::NTuple{NSDecimalMaxSize, Cushort}
end

function Base.getproperty(obj::NSDecimal, sym::Symbol)
    if sym == :length
        obj.flags & 0xf
    elseif sym == :isNegative
        Bool(obj.flags >> 4 & 1)
    elseif sym == :isCompact
        obj.flags >> 5 & 1
    elseif sym == :mantissa
        bits = getfield(obj, :mantissa)
        result = UInt128(0)
        for i in 1:obj.length
            result |= UInt128(bits[i]) << (16*(i-1))
        end
        result
    else
        getfield(obj, sym)
    end
end

Base.isnan(dec::NSDecimal) = dec.length == 0 && dec.isNegative

function Base.show(io::IO, dec::NSDecimal)
    if isnan(dec)
        print(io, "NaN")
    else
        print(io, "NSDecimal(", dec.mantissa, "e", dec.exponent, ")")
    end
end


export NSNumber

@objcwrapper comparison = false NSNumber <: NSObject

@objcproperties NSNumber begin
    @autoproperty boolValue::Bool
    @autoproperty charValue::Cchar
    @autoproperty decimalValue::NSDecimal
    @autoproperty doubleValue::Cdouble
    @autoproperty floatValue::Cfloat
    @autoproperty intValue::Cint
    @autoproperty integerValue::NSInteger
    @autoproperty longValue::Clong
    @autoproperty longLongValue::Clonglong
    @autoproperty shortValue::Cshort
    @autoproperty unsignedCharValue::Cuchar
    @autoproperty unsignedIntValue::Cuint
    @autoproperty unsignedIntegerValue::NSUInteger
    @autoproperty unsignedLongValue::Culong
    @autoproperty unsignedLongLongValue::Culonglong
    @autoproperty unsignedShortValue::Cushort
end

const NSNumberTypes = [
    Bool => :numberWithBool,
    Cchar => :numberWithChar,
    Cdouble => :numberWithDouble,
    Cfloat => :numberWithFloat,
    Cint => :numberWithInt,
    NSInteger => :numberWithInteger,
    Clong => :numberWithLong,
    Clonglong => :numberWithLongLong,
    Cshort => :numberWithShort,
    Cuint => :numberWithUnsignedInt,
    NSUInteger => :numberWithUnsignedInteger,
    Culong => :numberWithUnsignedLong,
    Culonglong => :numberWithUnsignedLongLong,
    Cushort => :numberWithUnsignedShort,
]

let
    unique_number_types = Set{Type}(map(first, NSNumberTypes))
    for T in unique_number_types
        i = findfirst(x->x[1] == T, NSNumberTypes)
        method = NSNumberTypes[i][2]
        @eval NSNumber(x::$T) = @objc [NSNumber $method:x::$T]::NSNumber
        @eval Base.convert(::Type{NSNumber}, x::$T) = NSNumber(x)
    end
end


export NSDecimalNumber, NaNDecimalNumber

@objcwrapper comparison = false NSDecimalNumber <: NSNumber
@objcproperties NSDecimalNumber begin
    #@autoproperty defaultBehavior::NSDecimalNumberBehaviors
    @autoproperty decimalValue::NSDecimal
    @autoproperty doubleValue::Float64
end

# constructors
NSDecimalNumber(dec::NSDecimal) =
    @objc [NSDecimalNumber decimalNumberWithDecimal:dec::NSDecimal]::NSDecimalNumber
NSDecimalNumber(str::Union{String,NSString}) =
    @objc [NSDecimalNumber decimalNumberWithString:str::id{NSString}]::NSDecimalNumber
NSDecimalNumber(; mantissa, exponent, negative) =
    @objc [NSDecimalNumber decimalNumberWithMantissa:mantissa::Culonglong
                                            exponent:exponent::Cshort
                                          isNegative:negative::Bool]::NSDecimalNumber

# conversions
Core.Float64(dec::NSDecimal) = NSDecimalNumber(dec).doubleValue
NSDecimal(dec::NSDecimalNumber) = dec.decimalValue

# fixed values
Base.zero(::Type{NSDecimalNumber}) =
    @objc [NSDecimalNumber zero]::NSDecimalNumber
Base.one(::Type{NSDecimalNumber}) =
    @objc [NSDecimalNumber one]::NSDecimalNumber
Base.typemin(::Type{NSDecimalNumber}) =
    @objc [NSDecimalNumber minimumDecimalNumber]::NSDecimalNumber
Base.typemax(::Type{NSDecimalNumber}) =
    @objc [NSDecimalNumber maximumDecimalNumber]::NSDecimalNumber
NaNDecimalNumber() =
    @objc [NSDecimalNumber notANumber]::NSDecimalNumber

# output
Base.string(number::NSDecimalNumber) = number.description
Base.show(io::IO, number::NSDecimalNumber) = print(io, "NSDecimalNumber(", number.description, ")")

# comparisons
@cenum NSComparisonResult::NSInteger begin
    NSOrderedAscending = -1
    NSOrderedSame = 0
    NSOrderedDescending = 1
end
compare(a::NSDecimalNumber, b::NSDecimalNumber) =
    @objc [a::id{NSDecimalNumber} compare:b::id{NSDecimalNumber}]::NSComparisonResult
Base.isequal(a::NSDecimalNumber, b::NSDecimalNumber) = compare(a, b) == NSOrderedSame
Base.isless(a::NSDecimalNumber, b::NSDecimalNumber) = compare(a, b) == NSOrderedAscending

export NSCopying

@objcwrapper NSCopying <: NSObject

export NSData

@objcwrapper NSData <: NSObject

export NSString

#@objcwrapper NSString <: NSObject

@objcproperties NSString begin
    @autoproperty length::NSUInteger
    @autoproperty UTF8String::Ptr{Cchar}
end

# allow conversions from String
Base.cconvert(::Type{id{NSString}}, str::String) = NSString(str)
Base.convert(::Type{NSString}, str::String) = NSString(str)

Base.:(==)(s1::Union{String,NSString}, s2::Union{String,NSString}) =
    String(s1) == String(s2)
Base.:(==)(s1::NSString, s2::NSString) =
    @objc [s1::id{NSString} isEqualToString:s2::id{NSString}]::Bool

NSString() = @objc [NSString string]::NSString
NSString(data::String) =
    @objc [NSString stringWithUTF8String:data::Ptr{Cchar}]::NSString
Base.length(s::NSString) = Int(s.length)
# the UTF-8 buffer may only live as long as the string or the current autorelease pool
Base.String(s::NSString) = GC.@preserve s begin
    @unsafe_autoreleasepool unsafe_string(@objc [s::id{NSString} UTF8String]::Ptr{Cchar})
end

# avoid redundant quotes
Base.string(s::NSString) = String(s)
Base.print(io::IO, s::NSString) = print(io, String(s))

Base.show(io::IO, ::MIME"text/plain", s::NSString) =
    print(io, "NSString(", repr(String(s)), ")")
Base.show(io::IO, s::NSString) = show(io, String(s))

Base.contains(s::NSString, t::AbstractString) =
    @objc [s::id{NSString} containsString:t::id{NSString}]::Bool
Base.contains(s::AbstractString, t::NSString) =
    @objc [s::id{NSString} containsString:t::id{NSString}]::Bool


export NSArray

@objcwrapper comparison = false NSArray <: NSObject

@objcproperties NSArray begin
    @autoproperty count::NSUInteger
end

NSArray() = @objc [NSArray array]::NSArray

function NSArray(elements::Vector{<:Object})
    return @objc [NSArray arrayWithObjects:elements::id{Object}
                                     count:length(elements)::NSUInteger]::NSArray
end

Base.length(arr::NSArray) = Int(arr.count)
function Base.getindex(arr::NSArray, i::Int)
    @boundscheck 1 <= i <= length(arr) || throw(BoundsError(arr, i))
    # the element is kept alive by the array, not by the pool
    @unsafe_autoreleasepool @objc [arr::id{NSArray} objectAtIndex:(i-1)::NSUInteger]::id{Object}
end

Base.iterate(arr::NSArray, i::Int=1) = i > length(arr) ? nothing : (arr[i], i+1)

Base.:(==)(a1::NSArray, a2::NSArray) =
    @objc [a1::id{NSArray} isEqualToArray:a2::id{NSArray}]::Bool

# elements are only kept alive by their container, so take ownership of managed ones
container_element(::Type{T}, ptr::id) where {T} =
    ObjectiveC.is_managed_wrapper(T) ? retain(T, reinterpret(id{T}, ptr)) : reinterpret(T, ptr)

# conversion to typed Julia array
function Base.convert(::Type{Vector{T}}, arr::NSArray) where {T}
    GC.@preserve arr [container_element(T, arr[i]) for i in 1:length(arr)]
end
Vector{T}(arr::NSArray) where {T} = convert(Vector{T}, arr)


export NSDictionary

@objcwrapper comparison = false NSDictionary <: NSObject

@objcproperties NSDictionary begin
    @autoproperty count::NSUInteger
    @autoproperty allKeys::id{NSArray}
    @autoproperty allValues::id{NSArray}
end

NSDictionary() = @objc [NSDictionary dictionary]::NSDictionary

function NSDictionary(items::Dict{<:Object,<:Object})
    nskeys = NSArray(collect(keys(items)))
    nsvals = NSArray(collect(values(items)))
    return @objc [NSDictionary dictionaryWithObjects:nsvals::id{NSArray}
                                      forKeys:nskeys::id{NSArray}]::NSDictionary
end

Base.length(dict::NSDictionary) = Int(dict.count)
Base.isempty(dict::NSDictionary) = length(dict) == 0

Base.keys(dict::NSDictionary) = dict.allKeys
Base.values(dict::NSDictionary) = dict.allValues

function Base.getindex(dict::NSDictionary, key::Object)
    # the value is kept alive by the dictionary, not by the pool
    ptr = @unsafe_autoreleasepool @objc [dict::id{NSDictionary} objectForKey:key::id{NSObject}]::id{Object}
    ptr == nil && throw(KeyError(key))
    return ptr
end

# conversion to typed Julia dictionary
function Base.convert(::Type{Dict{K,V}}, dict::NSDictionary) where {K,V}
    Dict{K,V}(zip(Vector{K}(keys(dict)), Vector{V}(values(dict))))
end
Dict{K,V}(dict::NSDictionary) where {K,V} = convert(Dict{K,V}, dict)


export NSError

@objcwrapper NSError <: NSObject

@objcproperties NSError begin
    @autoproperty code::NSInteger
    @autoproperty domain::id{NSString}
    @autoproperty userInfo::id{NSDictionary} type=Dict{NSString,NSObject}
    @autoproperty localizedDescription::id{NSString}
    @autoproperty localizedRecoveryOptions::id{NSString}
    @autoproperty localizedRecoverySuggestion::id{NSString}
    @autoproperty localizedFailureReason::id{NSString}
end

function NSError(domain, code)
    return @objc [NSError errorWithDomain:domain::id{NSString}
                         code:code::NSInteger
                         userInfo:nil::id{NSDictionary}]::NSError
end

function NSError(domain, code, userInfo)
    return @objc [NSError errorWithDomain:domain::id{NSString}
                         code:code::NSInteger
                         userInfo:userInfo::id{NSDictionary}]::NSError
end

function Base.showerror(io::IO, err::NSError)
    print(io, "NSError: $(err.localizedDescription) ($(err.domain), code $(err.code))")

    if err.localizedFailureReason !== nothing
        print(io, "\nFailure reason: $(err.localizedFailureReason)")
    end

    recovery_options = err.localizedRecoveryOptions
    if recovery_options !== nothing
        print(io, "\nRecovery Options:")
        for option in recovery_options
            print(io, "\n - $(option)")
        end
    end
end


export NSHost, current_host, hostname

@objcwrapper NSHost <: NSObject

@objcproperties NSHost begin
    @autoproperty address::id{NSString}
    @autoproperty name::id{NSString}
    @autoproperty names::id{NSArray}
    @autoproperty localizedName::id{NSString}
end

current_host() = @objc [NSHost currentHost]::NSHost
hostname() = String(current_host().localizedName)


export NSBundle, load_framework

@objcwrapper NSBundle <: NSObject

function NSBundle(path::Union{String,NSString})
    bundle = @objc [NSBundle bundleWithPath:path::id{NSString}]::Union{Nothing,NSBundle}
    bundle === nothing && error("Couldn't find bundle '$path'")
    return bundle
end

function load(bundle::NSBundle)
    loaded = @objc [bundle::id{NSBundle} load]::Bool
    loaded || error("Couldn't load bundle")
end

load_framework(name) = load(NSBundle("/System/Library/Frameworks/$name.framework"))


export NSURL, NSFileURL

@objcwrapper comparison = false NSURL <: NSObject

@objcproperties NSURL begin
    # Querying an NSURL
    @autoproperty isFileURL::Bool
    @autoproperty isFileReferenceURL::Bool

    # Accessing the Parts of the URL
    @autoproperty absoluteString::id{NSString}
    @autoproperty absoluteURL::id{NSURL}
    @autoproperty baseURL::id{NSURL}
    @autoproperty fileSystemRepresentation::id{NSString}
    @autoproperty fragment::id{NSString}
    @autoproperty host::id{NSString}
    @autoproperty lastPathComponent::id{NSString}
    @autoproperty parameterString::id{NSString}
    @autoproperty password::id{NSString}
    @autoproperty path::id{NSString}
    @autoproperty pathComponents::id{NSArray} type=Vector{NSString}
    @autoproperty pathExtension::id{NSString}
    @autoproperty port::id{NSNumber}
    @autoproperty query::id{NSString}
    @autoproperty relativePath::id{NSString}
    @autoproperty relativeString::id{NSString}
    @autoproperty resourceSpecifier::id{NSString}
    @autoproperty scheme::id{NSString}
    @autoproperty standardizedURL::id{NSURL}
    @autoproperty user::id{NSString}

    # Modifying and Converting a File URL
    @autoproperty filePathURL::id{NSURL}
    @autoproperty fileReferenceURL::id{NSURL}
end

function NSURL(str::Union{String,NSString})
    @objc [NSURL URLWithString:str::id{NSString}]::NSURL
end

function NSFileURL(path::Union{String,NSString})
    @objc [NSURL fileURLWithPath:path::id{NSString}]::NSURL
end

function Base.:(==)(a::NSURL, b::NSURL)
    @objc [a::id{NSURL} isEqual:b::id{NSURL}]::Bool
end


# value objects compare by `isEqual:`, so hash accordingly
Base.hash(obj::Union{NSStringLike,NSValueLike,NSNumberLike,NSArrayLike,NSDictionaryLike,NSURLLike},
          h::UInt) = hash(obj.hash, h)

export NSBlock

@cenum Block_flags::Cint begin
    BLOCK_DEALLOCATING      = 0x0001
    BLOCK_REFCOUNT_MASK     = 0xfffe

    BLOCK_IS_NOESCAPE       = 1 << 23
    BLOCK_NEEDS_FREE        = 1 << 24
    BLOCK_HAS_COPY_DISPOSE  = 1 << 25
    BLOCK_HAS_CTOR          = 1 << 26
    BLOCK_IS_GLOBAL         = 1 << 28
    BLOCK_HAS_STRET         = 1 << 29
    BLOCK_HAS_SIGNATURE     = 1 << 30
end

NSConcreteGlobalBlock() = cglobal(:_NSConcreteGlobalBlock)
NSConcreteStackBlock()  = cglobal(:_NSConcreteStackBlock)

@objcwrapper managed = false NSBlock <: NSObject

function Base.copy(block::NSBlock)
    @objc [block::id{NSBlock} copy]::id{NSBlock}
end


export NSProcessInfo, NSOperatingSystemVersion

struct NSOperatingSystemVersion
    majorVersion::NSInteger
    minorVersion::NSInteger
    patchVersion::NSInteger
end

@objcwrapper NSProcessInfo <: NSObject

@objcproperties NSProcessInfo begin
    # process information
    @autoproperty arguments::id{NSArray}
    @autoproperty environment::id{NSDictionary}
    @autoproperty globallyUniqueString::id{NSString}
    @autoproperty macCatalystApp::Bool
    @autoproperty iosAppOnMac::Bool
    @autoproperty processIdentifier::Cint
    @autoproperty processName::id{NSString}

    # user information
    @autoproperty userName::id{NSString}
    @autoproperty fullUserName::id{NSString}

    # host information
    @autoproperty hostName::id{NSString}
    @autoproperty operatingSystemVersionString::id{NSString}
    @autoproperty operatingSystemVersion::NSOperatingSystemVersion
end

NSProcessInfo() = @objc [NSProcessInfo processInfo]::NSProcessInfo

end
