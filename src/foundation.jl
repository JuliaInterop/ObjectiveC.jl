export YES, NO, nil, hostname

for c in :[NSObject
           NSString
           NSArray
           NSHost].args
  @eval $(Expr(:export, c))
  @eval const $c = Class($(Expr(:quote, c)))
end

const YES = true
const NO  = false
const nil = C_NULL

toobject(s::String) = @objc [[NSString alloc] initWithUTF8String:s]

hostname() =
  @objc [[[NSHost currentHost] localizedName] UTF8String] |> bytestring

release(obj) = @objc [obj release]

function Base.gc(obj::Object)
  finalizer(obj, release)
  obj
end
