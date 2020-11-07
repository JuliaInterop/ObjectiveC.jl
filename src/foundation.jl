using Libdl

Libdl.dlopen("/System/Library/Frameworks/Foundation.framework/Foundation")

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
  (@objc [[[NSHost currentHost] localizedName] UTF8String]) |> unsafe_string

release(obj) = @objc [obj release]

function GC.gc(obj::Object)
  finalizer(obj, release)
  obj
end

function loadbundle(path)
  bundle = @objc [NSBundle bundleWithPath:path]
  bundle.ptr |> Int |> int2bool || error("Bundle $path not found")
  loadedStuff = @objc [bundle load]
  loadedStuff |> int2bool || error("Couldn't load bundle $path")
  return
end

framework(name) = loadbundle("/System/Library/Frameworks/$name.framework")
