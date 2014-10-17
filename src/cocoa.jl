module Cocoa

using ObjectiveC

dlopen("/System/Library/Frameworks/AppKit.framework/Versions/C/Resources/BridgeSupport/AppKit")

for c in :[NSAlert
           NSWindow
           NSColor].args
  @eval $(Expr(:export, c))
  @eval const $c = ObjectiveC.Class($(Expr(:quote, c)))
end

export alert

function alert(header, body)
  @objc begin
    msg = [[NSAlert alloc] init]
    [msg setMessageText: header]
    [msg setInformativeText: body]
    [msg runModal]
    [msg release]
  end
end

end
