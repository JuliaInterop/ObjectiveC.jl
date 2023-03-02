module Foundation

using ..ObjectiveC

export YES, NO, nil

const YES = true
const NO  = false
const nil = C_NULL


export NSUInteger

const NSUInteger = Culong


export NSString

struct NSString <: Object
    ptr::id
end
Base.unsafe_convert(::Type{id}, str::NSString) = str.ptr

Base.cconvert(::Type{id}, str::String) = NSString(str)

NSString() = NSString(@objc [NSString string]::id{NSString})
NSString(data::String) = NSString(@objc [NSString stringWithUTF8String :data::Ptr{UInt8}]::id{NSString})
Base.length(s::NSString) = Int(@objc [s::id{NSString} length]::NSUInteger)

export NSHost, hostname

struct NSHost <: Object
    ptr::id
end
Base.unsafe_convert(::Type{id}, host::NSHost) = host.ptr

hostname() =
  unsafe_string(@objc [[[NSHost currentHost]::id{NSHost} localizedName]::id{NSString} UTF8String]::Ptr{UInt8})


export NSBundle, load_framework

struct NSBundle <: Object
    ptr::id
end
Base.unsafe_convert(::Type{id}, bundle::NSBundle) = bundle.ptr

function NSBundle(path::Union{String,NSString})
  ptr = @objc [NSBundle bundleWithPath :path::id{NSString}]::id{NSBundle}
  ptr == nil && error("Couldn't find bundle '$path'")
  NSBundle(ptr)
end

function load(bundle::NSBundle)
  loaded = @objc [bundle::id{NSBundle} load]::Bool
  loaded || error("Couldn't load bundle")
end

load_framework(name) = load(NSBundle("/System/Library/Frameworks/$name.framework"))

end
