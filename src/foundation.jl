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

@objcwrapper NSObject <: Object

# forward declaration
@objcwrapper NSString <: NSObject

@objcproperties NSObject begin
    @autoproperty hash::NSUInteger
    @autoproperty description::id{NSString}
    @autoproperty debugDescription::id{NSString}

    @autoproperty retainCount::NSUInteger
end

function Base.show(io::IO, ::MIME"text/plain", obj::NSObject)
    if get(io, :compact, false)
        print(io, String(obj.description))
    else
        print(io, String(obj.debugDescription))
    end
end

release(obj::NSObject) = @objc [obj::id{NSObject} release]::Cvoid

autorelease(obj::NSObject) = @objc [obj::id{NSObject} autorelease]::Cvoid

retain(obj::NSObject) = @objc [obj::id{NSObject} retain]::Cvoid

ObjectiveC.class(obj::NSObject) = @objc [obj::id{NSObject} class]::Class

function is_kind_of(obj::NSObject, class::Class)
    @objc [obj::id{NSObject} isKindOfClass:class::Class]::Bool
end

function Base.:(==)(obj1::NSObject, obj2::NSObject)
    @objc [obj1::id{NSObject} isEqual:obj2::id{NSObject}]::Bool
end


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

@objcwrapper NSValue <: NSObject

Base.:(==)(v1::NSValue, v2::NSValue) =
    @objc [v1::id{NSValue} isEqualToValue:v2::id{NSValue}]::Bool

@objcproperties NSValue begin
    @autoproperty objCType::Ptr{Cchar}
    @autoproperty pointerValue::Ptr{Cvoid}
    @autoproperty rangeValue::NSRange
    # ...
end

NSValue(x::Ptr) = NSValue(@objc [NSValue valueWithPointer:x::Ptr{Cvoid}]::id{NSValue})
NSValue(x::Union{NSRange,UnitRange}) =
    NSValue(@objc [NSValue valueWithRange:x::NSRange]::id{NSValue})
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

@objcwrapper NSNumber <: NSObject

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
        @eval NSNumber(x::$T) = NSNumber(@objc [NSNumber $method:x::$T]::id{NSNumber})
        @eval Base.convert(::Type{NSNumber}, x::$T) = NSNumber(x)
    end
end


export NSDecimalNumber, NaNDecimalNumber

@objcwrapper NSDecimalNumber <: NSNumber
@objcproperties NSDecimalNumber begin
    #@autoproperty defaultBehavior::NSDecimalNumberBehaviors
    @autoproperty decimalValue::NSDecimal
    @autoproperty doubleValue::Float64
end

# constructors
NSDecimalNumber(dec::NSDecimal) =
    NSDecimalNumber(@objc [NSDecimalNumber decimalNumberWithDecimal:dec::NSDecimal]::id{NSDecimalNumber})
NSDecimalNumber(str::Union{String,NSString}) =
    NSDecimalNumber(@objc [NSDecimalNumber decimalNumberWithString:str::id{NSString}]::id{NSDecimalNumber})
NSDecimalNumber(; mantissa, exponent, negative) =
    NSDecimalNumber(@objc [NSDecimalNumber decimalNumberWithMantissa:mantissa::Culonglong
                                                            exponent:exponent::Cshort
                                                          isNegative:negative::Bool]::id{NSDecimalNumber})

# conversions
Core.Float64(dec::NSDecimal) = NSDecimalNumber(dec).doubleValue
NSDecimal(dec::NSDecimalNumber) = dec.decimalValue

# fixed values
Base.zero(::Type{NSDecimalNumber}) =
    NSDecimalNumber(@objc [NSDecimalNumber zero]::id{NSDecimalNumber})
Base.one(::Type{NSDecimalNumber}) =
    NSDecimalNumber(@objc [NSDecimalNumber one]::id{NSDecimalNumber})
Base.typemin(::Type{NSDecimalNumber}) =
    NSDecimalNumber(@objc [NSDecimalNumber minimumDecimalNumber]::id{NSDecimalNumber})
Base.typemax(::Type{NSDecimalNumber}) =
    NSDecimalNumber(@objc [NSDecimalNumber maximumDecimalNumber]::id{NSDecimalNumber})
NaNDecimalNumber() =
    NSDecimalNumber(@objc [NSDecimalNumber notANumber]::id{NSDecimalNumber})

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

@objcwrapper immutable = false NSCopying <: NSObject

export NSData

@objcwrapper immutable = false NSData <: NSObject

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

NSString() = NSString(@objc [NSString string]::id{NSString})
NSString(data::String) =
    NSString(@objc [NSString stringWithUTF8String:data::Ptr{Cchar}]::id{NSString})
Base.length(s::NSString) = Int(s.length)
Base.String(s::NSString) = unsafe_string(@objc [s::id{NSString} UTF8String]::Ptr{Cchar})

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

@objcwrapper NSArray <: NSObject

@objcproperties NSArray begin
    @autoproperty count::NSUInteger
end

NSArray() = NSArray(@objc [NSArray array]::id{NSArray})

function NSArray(elements::Vector{<:NSObject})
    arr = @objc [NSArray arrayWithObjects:elements::id{Object}
                                    count:length(elements)::NSUInteger]::id{NSArray}
    return NSArray(arr)
end

Base.length(arr::NSArray) = Int(arr.count)
function Base.getindex(arr::NSArray, i::Int)
    @boundscheck 1 <= i <= length(arr) || throw(BoundsError(arr, i))
    @objc [arr::id{NSArray} objectAtIndex:(i-1)::NSUInteger]::id{Object}
end

Base.iterate(arr::NSArray, i::Int=1) = i > length(arr) ? nothing : (arr[i], i+1)

Base.:(==)(a1::NSArray, a2::NSArray) =
    @objc [a1::id{NSArray} isEqualToArray:a2::id{NSArray}]::Bool

# conversion to typed Julia array
function Base.convert(::Type{Vector{T}}, arr::NSArray) where {T}
    [reinterpret(T, arr[i]) for i in 1:length(arr)]
end
Vector{T}(arr::NSArray) where {T} = convert(Vector{T}, arr)


export NSDictionary

@objcwrapper NSDictionary <: NSObject

@objcproperties NSDictionary begin
    @autoproperty count::NSUInteger
    @autoproperty allKeys::id{NSArray}
    @autoproperty allValues::id{NSArray}
end

NSDictionary() = NSDictionary(@objc [NSDictionary dictionary]::id{NSDictionary})

function NSDictionary(items::Dict{<:NSObject,<:NSObject})
    nskeys = NSArray(collect(keys(items)))
    nsvals = NSArray(collect(values(items)))
    dict = @objc [NSDictionary dictionaryWithObjects:nsvals::id{NSArray}
                               forKeys:nskeys::id{NSArray}]::id{NSDictionary}
    return NSDictionary(dict)
end

Base.length(dict::NSDictionary) = Int(dict.count)
Base.isempty(dict::NSDictionary) = length(dict) == 0

Base.keys(dict::NSDictionary) = dict.allKeys
Base.values(dict::NSDictionary) = dict.allValues

function Base.getindex(dict::NSDictionary, key::NSObject)
    ptr = @objc [dict::id{NSDictionary} objectForKey:key::id{NSObject}]::id{Object}
    ptr == nil && throw(KeyError(key))
    return ptr
end

# conversion to typed Julia dictionary
function Base.convert(::Type{Dict{K,V}}, dict::NSDictionary) where {K,V}
    Dict{K,V}(zip(map(Base.Fix1(reinterpret, K), keys(dict)),
                    map(Base.Fix1(reinterpret, V), values(dict))))
end
Dict{K,V}(dict::NSDictionary) where {K,V} = convert(Dict{K,V}, dict)


export NSError

@objcwrapper NSError <: NSObject

@objcproperties NSError begin
    @autoproperty code::NSInteger
    @autoproperty domain::id{NSString}
    @autoproperty userInfo::id{NSDictionary} type=Dict{NSString,Object}
    @autoproperty localizedDescription::id{NSString}
    @autoproperty localizedRecoveryOptions::id{NSString}
    @autoproperty localizedRecoverySuggestion::id{NSString}
    @autoproperty localizedFailureReason::id{NSString}
end
# TODO: userInfo

function NSError(domain, code)
    err = @objc [NSError errorWithDomain:domain::id{NSString}
                        code:code::NSInteger
                        userInfo:nil::id{NSDictionary}]::id{NSError}
    return NSError(err)
end

function NSError(domain, code, userInfo)
    err = @objc [NSError errorWithDomain:domain::id{NSString}
                        code:code::NSInteger
                        userInfo:userInfo::id{NSDictionary}]::id{NSError}
    return NSError(err)
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

current_host() = NSHost(@objc [NSHost currentHost]::id{NSHost})
hostname() = unsafe_string(current_host().localizedName.UTF8String)


export NSBundle, load_framework

@objcwrapper NSBundle <: NSObject

function NSBundle(path::Union{String,NSString})
    ptr = @objc [NSBundle bundleWithPath:path::id{NSString}]::id{NSBundle}
    ptr == nil && error("Couldn't find bundle '$path'")
    NSBundle(ptr)
end

function load(bundle::NSBundle)
    loaded = @objc [bundle::id{NSBundle} load]::Bool
    loaded || error("Couldn't load bundle")
end

load_framework(name) = load(NSBundle("/System/Library/Frameworks/$name.framework"))


export NSURL, NSFileURL

@objcwrapper NSURL <: NSObject

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
    NSURL(@objc [NSURL URLWithString:str::id{NSString}]::id{NSURL})
end

function NSFileURL(path::Union{String,NSString})
    NSURL(@objc [NSURL fileURLWithPath:path::id{NSString}]::id{NSURL})
end

function Base.:(==)(a::NSURL, b::NSURL)
    @objc [a::id{NSURL} isEqual:b::id{NSURL}]::Bool
end


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

@objcwrapper NSBlock <: NSObject

function Base.copy(block::NSBlock)
    @objc [block::id{NSBlock} copy]::id{NSBlock}
end


export NSAutoreleasePool, @autoreleasepool, drain

@objcwrapper NSAutoreleasePool <: NSObject

"""
    NSAutoreleasePool()

Create a new autorelease pool. This is a low-level wrapper around the Objective-C
`NSAutoreleasePool` class, and should be used with care. For example, it does not
automatically get released, or drain the pool on finalization.

For high-level usage, consider using the do-block syntax, or [`@autoreleasepool`](@ref)
instead.
"""
function NSAutoreleasePool()
    obj = NSAutoreleasePool(@objc [NSAutoreleasePool alloc]::id{NSAutoreleasePool})
    # XXX: this init call itself requires an autoreleasepool to be active...
    @objc [obj::id{NSAutoreleasePool} init]::id{NSAutoreleasePool}
    # NOTE: we don't register a finalizer, as it's better to drain the pool,
    #       and it's not allowed to both drain and release.
    obj
end

drain(pool::NSAutoreleasePool) = @objc [pool::id{NSAutoreleasePool} drain]::Cvoid

# high-level interface to wrap Julia code in an autorelease pool

"""
    NSAutoreleasePool() do
      # ...
    end

High-level interface to wrap Julia code in an autorelease pool. This is equivalent to
`@autoreleasepool` in Objective-C, and ensures that the pool is drained after the
enclosed code block has finished.

Note that due to technical limitations, this API prevents the current task from migrating
to another thread. In addition, only one autorelease do-block can be active at a time.
To disable these limitations, use the unsafe [`NSUnsafeAutoreleasePool`](@ref) instead.

See also: [`@autoreleasepool`](@ref)
"""
function NSAutoreleasePool(f::Base.Callable)
    # we cannot switch between multiple autorelease pools, so ensure only one is ever active.
    # XXX: support multiple pools, as long as they run on separate threads?
    Base.@lock NSAutoreleaseLock begin
        # autorelease pools are thread-bound, so ensure we don't migrate to another thread
        task = current_task()
        sticky = task.sticky
        task.sticky = true

        pool = NSAutoreleasePool()
        try
            f()
        finally
            drain(pool)
            #task.sticky = sticky
            # XXX: we cannot safely re-enable thread migration, as the called code might have
            #      disabled it too. instead, Julia should have a notion of "temporary pinning"
        end
    end
end
const NSAutoreleaseLock = ReentrantLock()

function NSUnsafeAutoreleasePool(f::Base.Callable)
    pool = NSAutoreleasePool()
    try
        f()
    finally
        drain(pool)
    end
end


"""
    @autoreleasepool [kwargs...] code...
    @autoreleasepool [kwargs...] function ... end

High-level interface to wrap Julia code in an autorelease pool. This macro can be used
within a function, or as a function decorator. In both cases, the macro ensures that the
contained code is wrapped in an autorelease pool, and that the pool is drained after the
enclosed code block has finished.

See also: [`NSAutoreleasePool`](@ref)
"""
macro autoreleasepool(ex...)
    code = ex[end]
    kwargs = ex[1:end-1]

    # extract keyword arguments that are handled by this macro
    unsafe = false
    for kwarg in kwargs
        if Meta.isexpr(kwarg, :(=))
            key, value = kwarg.args
            if key == :unsafe
                isa(value, Bool) || throw(ArgumentError("Invalid value for keyword argument `unsafe`: got `$value`, expected literal boolean value"))
                unsafe = value
            else
                error("Invalid keyword argument to @autoreleasepool: $kwarg")
            end
        else
            throw(ArgumentError("Invalid keyword argument to @autoreleasepool: $kwarg"))
        end
    end
    f = unsafe ? NSUnsafeAutoreleasePool : NSAutoreleasePool

    if Meta.isexpr(code, :(=)) &&
        (Meta.isexpr(code.args[1], :call) || Meta.isexpr(code.args[1], :where))
        # function definition, short form
        sig, body = code.args
        @assert Meta.isexpr(body, :block)
        managed_body = quote
            $f() do
                $body
            end
        end
        esc(Expr(:(=), sig, managed_body))
    elseif Meta.isexpr(code, :function)
        # function definition, long form
        sig = code.args[1]
        @assert Meta.isexpr(sig, :call) || Meta.isexpr(sig, :where)
        body = code.args[2]
        @assert Meta.isexpr(body, :block)
        managed_body = quote
            $f() do
                $body
            end
        end
        esc(Expr(:function, sig, managed_body))
    else
        # code block
        quote
            $f() do
                $(esc(code))
            end
        end
    end
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

NSProcessInfo() = NSProcessInfo(@objc [NSProcessInfo processInfo]::id{NSProcessInfo})

end
