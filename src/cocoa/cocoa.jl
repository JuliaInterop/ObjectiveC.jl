module Cocoa

export init, window

using ObjectiveC

ObjectiveC.framework("AppKit")
dlopen(Pkg.dir("ObjectiveC", "c", "cocoa"))
include("constants.jl")

@classes NSWindow, NSApplication, NSSound, NSTimer

# Struct creation

nsrect(x, y, w, h) =
  ccall(:nsmakerect, Ptr{Void}, (Cfloat, Cfloat, Cfloat, Cfloat),
        x, y, w, h)

NSApp() = cglobal(:NSApp, Ptr{Void}) |> unsafe_load |> ObjectiveC.Object

function initapp()
  @objc begin
    [NSApplication sharedApplication]
#     [NSApp() setActivationPolicy:NSApplicationActivationPolicyRegular]
    [NSApp() setActivationPolicy:NSApplicationActivationPolicyAccessory]
  end
end

function window(title = "Julia", width = 600, height = 400)
  @objc begin
    win = [[NSWindow alloc] initWithContentRectRef:nsrect(0, 0, width, height)
                                            styleMask:(NSTitledWindowMask |
                                                       NSClosableWindowMask |
                                                       NSMiniaturizableWindowMask |
                                                       NSResizableWindowMask |
                                                       NSUnifiedTitleAndToolbarWindowMask)
                                              backing:NSBackingStoreBuffered
                                                defer:NO]
    [win setTitle:title]
    [win center]
    [win makeKeyAndOrderFront:nil]
    return win
  end
end

@class type Yielder
  @+ (Void) tick:timer begin
#     pop()
    yield()
  end
end

function eventloop()
  @async @objc begin
    try
      [NSTimer scheduledTimerWithTimeInterval:1/1000
                                      target:Yielder
                                    selector:sel"tick:"
                                    userInfo:nil
                                     repeats:YES]
      [NSApp() run]
    catch e
      showerror(STDERR, e)
      rethrow()
    end
  end
end

function init()
  initapp()
  eventloop()
end

# Sound

export play, pop

function play(name::String)
  @objc begin
    sound = [NSSound soundNamed:name]
    if [sound isPlaying] |> bool
      [sound stop]
    end
    [sound play]
  end
end

pop() = play("Pop")

# Alert window

@classes NSAlert

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
