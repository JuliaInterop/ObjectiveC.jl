module Foundation

using ..ObjectiveC


export NSInteger, MSIntegerMin, NSIntegerMax, NSUInteger, NSUIntegerMax

if sizeof(Ptr{Cvoid}) == 8
  const NSInteger = Int64
  const NSUInteger = UInt64
else
  const NSInteger = Int32
  const NSUInteger = UInt32
end
const MSIntegerMin = typemin(NSInteger)
const NSIntegerMax = typemax(NSInteger)
const NSUIntegerMax = typemax(NSUInteger)


export NSObject, retain, release, is_kind_of

@objcwrapper NSObject <: Object

# forward declaration
@objcwrapper NSString <: NSObject

@objcproperties NSObject begin
    @autoproperty hash::NSUInteger
    @autoproperty description::id{NSString}
end

function Base.show(io::IO, ::MIME"text/plain", obj::NSObject)
  print(io, String(obj.description))
end

release(obj::NSObject) = @objc [obj::id{NSObject} release]::Cvoid

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

Base.cconvert(::Type{NSRange}, r::UnitRange{Int}) = NSRange(first(r), length(r))

Base.first(r::NSRange) = r.location
Base.last(r::NSRange) = r.location + r.length - 1
Base.length(r::NSRange) = r.length


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
NSValue(x::Union{NSRange,UnitRange}) = NSValue(@objc [NSValue valueWithRange:x::NSRange]::id{NSValue})
# ...


export NSNumber

@objcwrapper NSNumber <: NSObject

@objcproperties NSNumber begin
    @autoproperty boolValue::Bool
    @autoproperty charValue::Cchar
    #@autoproperty decimalValue::id{NSDecimalNumber}
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
  end
end


export NSString

#@objcwrapper NSString <: NSObject

@objcproperties NSString begin
    @autoproperty length::NSUInteger
    @autoproperty UTF8String::Ptr{Cchar}
end

# allow conversions from String
Base.cconvert(::Type{id{NSString}}, str::String) = NSString(str)
Base.convert(::Type{NSString}, str::String) = NSString(str)

Base.:(==)(s1::Union{String,NSString}, s2::Union{String,NSString}) = String(s1) == String(s2)
Base.:(==)(s1::NSString, s2::NSString) = @objc [s1::id{NSString} isEqualToString:s2::id{NSString}]::Bool

NSString() = NSString(@objc [NSString string]::id{NSString})
NSString(data::String) = NSString(@objc [NSString stringWithUTF8String:data::Ptr{Cchar}]::id{NSString})
Base.length(s::NSString) = Int(s.length)
Base.String(s::NSString) = unsafe_string(@objc [s::id{NSString} UTF8String]::Ptr{Cchar})

# avoid redundant quotes
Base.string(s::NSString) = String(s)
Base.print(io::IO, s::NSString) = print(io, String(s))

Base.show(io::IO, ::MIME"text/plain", s::NSString) = print(io, "NSString(", repr(String(s)), ")")
Base.show(io::IO, s::NSString) = show(io, String(s))

Base.contains(s::NSString, t::AbstractString) = @objc [s::id{NSString} containsString:t::id{NSString}]::Bool
Base.contains(s::AbstractString, t::NSString) = @objc [s::id{NSString} containsString:t::id{NSString}]::Bool


export NSArray

@objcwrapper NSArray <: NSObject

@objcproperties NSArray begin
    @autoproperty count::NSUInteger
end

NSArray() = NSArray(@objc [NSArray array]::id{NSArray})

function NSArray(elements::Vector)
    arr = @objc [NSArray arrayWithObjects:elements::Ptr{id}
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

# @cenum Block_flags::Cint begin
#     BLOCK_DEALLOCATING      = 0x0001
#     BLOCK_REFCOUNT_MASK     = 0xfffe

#     BLOCK_IS_NOESCAPE       = 1 << 23
#     BLOCK_NEEDS_FREE        = 1 << 24
#     BLOCK_HAS_COPY_DISPOSE  = 1 << 25
#     BLOCK_HAS_CTOR          = 1 << 26
#     BLOCK_IS_GLOBAL         = 1 << 28
#     BLOCK_HAS_STRET         = 1 << 29
#     BLOCK_HAS_SIGNATURE     = 1 << 30
# end

const _NSConcreteGlobalBlock = cglobal(:_NSConcreteGlobalBlock)
const _NSConcreteStackBlock  = cglobal(:_NSConcreteStackBlock)

@objcwrapper NSBlock <: NSObject

function Base.copy(block::NSBlock)
    @objc [block::id{NSBlock} copy]::id{NSBlock}
end


export @objcblock

struct JuliaBlockDescriptor
    reserved::Culong
    size::Culong
    copy_helper::Ptr{Cvoid}
    dispose_helper::Ptr{Cvoid}
end

struct JuliaBlock
    isa::Ptr{Cvoid}
    flags::Cint
    reserved::Cint
    invoke::Ptr{Cvoid}
    descriptor::Ptr{JuliaBlockDescriptor}

    # custom fields
    lambda::Function
end

# JuliaBlock is the concrete version of NSBlock, so make it possible to derive a regular
# Objective-C object by temporarily boxing the structure and copying it to the heap.
function NSBlock(block::JuliaBlock)
    block_box = Ref(block)
    GC.@preserve block_box begin
        block_ptr = Base.unsafe_convert(Ptr{Cvoid}, block_box)
        nsblock_ptr = reinterpret(id{NSBlock}, block_ptr)
        copy(NSBlock(nsblock_ptr))
    end
end

# static descriptor for a simple Julia-based block
const julia_block_descriptor = Ref(JuliaBlockDescriptor(0, sizeof(JuliaBlock), 0, C_NULL))

function julia_block_trampoline(_block, _self, args...)
    block = unsafe_load(_block)
    nsblock = NSBlock(reinterpret(id{NSBlock}, _block))

    # call the user lambda
    block.lambda(args...)
end

macro objcblock(callable, rettyp, argtyps)
    quote
        cb = @cfunction($julia_block_trampoline, $(esc(rettyp)),
                        (Ptr{JuliaBlock}, id{Object}, $(esc(argtyps))...))
        GC.@preserve cb begin
            if sizeof($(esc(callable))) > 0
                error("@objcblock: closures are not yet supported")
                # closures actually work, however they need to be kept alive. currently,
                # after deriving a NSBlock pointer, the GC is free to collect the JuliaBlock.
                # one solution is to return both from this macro (or somehow tieing them
                # together), however that is cumbersome as it user would then need to keep
                # the object alive until after the block is called. a better solution is
                # probably possible by refcounting the block by setting copy/dispose
                # helpers in the descriptor.
            end

            # set-up the block data structures
            trampoline_ptr = Base.unsafe_convert(Ptr{Cvoid}, cb)
            desc_ptr = Base.unsafe_convert(Ptr{Cvoid}, $julia_block_descriptor)
            block = JuliaBlock(_NSConcreteStackBlock, 0, 0, trampoline_ptr, desc_ptr, $(esc(callable)))

            # copy the block to the heap and have Objective-C use that object.
            # our original block was a plain Julia struct so doesn't need to be released.
            # we also don't need to worry about the lifetime of the block object, as the
            # only references to Julia data it contains are the descriptor, which is
            # statically allocated, and the lambda (Julia code currently isn't GC'd).
            #
            # XXX: does nobody need to release the NSBlock copy we created?
            NSBlock(block)
        end
    end
end


end
