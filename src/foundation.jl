module Foundation

using ..ObjectiveC

export YES, NO, nil, retain, release, hostname

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

release(obj) = @objc [obj release]

retain(obj) = @objc [obj retain]

hostname() =
  unsafe_string(@objc [[[NSHost currentHost] localizedName] UTF8String])

function loadbundle(path)
  bundle = @objc [NSBundle bundleWithPath:path]
  bundle.ptr |> Int |> int2bool || error("Bundle $path not found")
  loadedStuff = @objc [bundle load]
  loadedStuff |> int2bool || error("Couldn't load bundle $path")
  return
end

framework(name) = loadbundle("/System/Library/Frameworks/$name.framework")

end
