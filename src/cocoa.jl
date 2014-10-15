dlopen("/System/Library/Frameworks/AppKit.framework/Versions/C/Resources/BridgeSupport/AppKit")

for c in :[NSWindow NSAlert].args
  @eval const $c = Class($(Expr(:quote, c)))
end
