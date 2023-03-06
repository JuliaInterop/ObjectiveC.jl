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


export NSObject, retain, release, description

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


export NSString

#@objcwrapper NSString <: NSObject

@objcproperties NSString begin
    @autoproperty length::NSUInteger
    @autoproperty UTF8String::Ptr{Cchar}
end

Base.cconvert(::Type{id{NSString}}, str::String) = NSString(str)
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


export NSRange

struct NSRange
    location::NSUInteger
    length::NSUInteger
end


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

end
