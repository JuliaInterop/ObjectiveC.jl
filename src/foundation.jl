module Foundation

using ..ObjectiveC

export YES, NO, nil

const YES = true
const NO  = false
const nil = C_NULL

export NSObject, retain, release

abstract type NSObject <: Object end

description(obj::NSObject) = NSString(@objc [obj::id{NSObject} description]::id{NSString})

function Base.show(io::IO, ::MIME"text/plain", obj::NSObject)
  print(io, String(description(obj)))
end

release(obj::NSObject) = @objc [obj::id{NSObject} release]::Cvoid

retain(obj::NSObject) = @objc [obj::id{NSObject} retain]::Cvoid


export NSUInteger

const NSUInteger = Culong


export NSString

struct NSString <: NSObject
    ptr::id
end
Base.unsafe_convert(::Type{id}, str::NSString) = str.ptr

Base.cconvert(::Type{id}, str::String) = NSString(str)

NSString() = NSString(@objc [NSString string]::id{NSString})
NSString(data::String) = NSString(@objc [NSString stringWithUTF8String :data::Ptr{Cchar}]::id{NSString})
Base.length(s::NSString) = Int(@objc [s::id{NSString} length]::NSUInteger)
String(s::NSString) = unsafe_string(@objc [s::id{NSString} UTF8String]::Ptr{Cchar})
Base.show(io::IO, ::MIME"text/plain", s::NSString) = print(io, "NSString(", repr(String(s)), ")")
Base.show(io::IO, s::NSString) = show(io, String(s))

export NSHost, current_host, hostname

struct NSHost <: NSObject
    ptr::id
end
Base.unsafe_convert(::Type{id}, host::NSHost) = host.ptr

current_host() = NSHost(@objc [NSHost currentHost]::id{NSHost})
function hostname()
  host = current_host()
  unsafe_string(@objc [[host::id{NSHost} localizedName]::id{NSString} UTF8String]::Ptr{UInt8})
end


export NSBundle, load_framework

struct NSBundle <: NSObject
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
