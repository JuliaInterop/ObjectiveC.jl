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
