export YES, NO, nil, hostname

for c in :[NSObject
           NSBundle
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

function loadbundle(path)
  @objc begin
    bundle = [NSBundle bundleWithPath:path]
    bundle.ptr |> int |> bool || error("Bundle $path not found")
    [bundle load] |> bool || error("Couldn't load bundle $path")
    return
  end
end

framework(name) = loadbundle("/System/Library/Frameworks/$name.framework")
