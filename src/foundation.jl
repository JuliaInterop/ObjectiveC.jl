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

NSString() = @objc [NSString string]::NSString
NSString(data::String) = @objc [NSString stringWithUTF8String :data::Ptr{UInt8}]::NSString
Base.length(s::NSString) = Int(@objc [s::NSString length]::NSUInteger)

export NSHost, hostname

struct NSHost <: Object
    ptr::id
end
Base.unsafe_convert(::Type{id}, host::NSHost) = host.ptr

hostname() =
  unsafe_string(@objc [[[NSHost currentHost]::NSHost localizedName]::NSString UTF8String]::Ptr{UInt8})

end
