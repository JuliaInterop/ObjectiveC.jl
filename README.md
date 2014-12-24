# ObjectiveC.jl

```julia
Pkg.clone("ObjectiveC")
```

ObjectiveC.jl is an Objective-C bridge for Julia. The library allows you to call Objective-C methods using native syntax:

```julia
using ObjectiveC

@objc [NSString new]
```

This makes it easy to wrap Objective-C APIs from Julia.

```julia
using ObjectiveC

@classes NSSound

function play(name::String)
  @objc begin
    sound = [NSSound soundNamed:name]
    if [sound isPlaying] |> bool
      [sound stop]
    end
    [sound play]
  end
end

play("Purr")
```

ObjectiveC.jl also supports defining classes, using a variant of Objective-C
syntax (which eschews the interface/implementation distinction):

```julia
@class type Foo
  @- (Cdouble) multiply:(Cdouble)x by:(Cdouble)y begin
    x*y # Note that this is Julia code
  end
end

@objc [[Foo new] multiply:5 by:3]
#> 15
```

You can leave out the type to default to `Object`. So long as you don't change
the type of the method, you're able to redefine it on the fly – even if you've
already created instances of the class and used them as delegates.

## using Cocoa

The library provides some basic wrappers for the Cocoa framework for creating
GUIs. Despite having generally nice APIs Objective-C is ridiculously verbose, so
it's handy to have Julia wrappers for most functionality.

```julia
using ObjectiveC, Cocoa
Cocoa.init()
win = window()
```

This will pop up a window with the title "Julia". Now let's try something more
interesting:

```julia
for α = linspace(0,π,50)
  @objc [win setAlphaValue:cos(α)^2]
  sleep(1/100)
end
```

You should see the window fade in and out again.

If you're using [Juno](http://junolab.org), I encourage you to try uncommenting
[this line](https://github.com/one-more-minute/ObjectiveC.jl/blob/65f8605657a9a5c7bf5eab6cea89c6c431ff332d/src/cocoa/cocoa.jl#L48)
and pressing `C-Enter` to evaluate the class definition (after opening a window
as above). You'll notice that the class is actually redefined on-the-fly, and
you'll hear a popping sound as the `tick` method is called (and you can do the
reverse to stop the sound, of course).

## Current Limitations

  * Julia's FFI doesn't have great support for structs yet, so neither does
    ObjectiveC.jl. Luckily structs aren't too common in Objective-C APIs, and
    where they are used it's not too difficult to add wrappers (see
    [cocoa.m](deps/cocoa.m))
  * Objective-C calls made from Julia are not as fast as they could be. This
    is fine for most GUI-related purposes, since most calls will be callbacks
    made by the Objective-C runtime, but may not be suitable for use with
    high-performance scientific computing libraries written in Objective-C.
  * Instance variables are not yet supported on classes.
  * Probably other things I haven't thought of; ObjectiveC.jl has not been used
    for any remotely large projects yet so proceed with caution.
