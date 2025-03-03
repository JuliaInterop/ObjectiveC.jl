# ObjectiveC.jl

*Objective-C bridge for Julia*

[![][github-img]][github-url] [![][codecov-img]][codecov-url]

[github-img]: https://github.com/JuliaInterop/ObjectiveC.jl/actions/workflows/ci.yml/badge.svg
[github-url]: https://github.com/JuliaInterop/ObjectiveC.jl/actions/workflows/ci.yml

[codecov-img]: https://codecov.io/gh/JuliaInterop/ObjectiveC.jl/branch/master/graph/badge.svg
[codecov-url]: https://codecov.io/gh/JuliaInterop/ObjectiveC.jl


## Quick start

ObjectiveC.jl is a registered package, so you can install it using the package manager:

```julia
Pkg.add("ObjectiveC")
```

The library allows you to call Objective-C methods using almost-native syntax:

```julia
julia> using ObjectiveC

julia> @objc [NSString new]::id{Object}
id{Object}(0x00006000008a4760)
```

For performance reasons, ObjectiveC.jl requires you to specify the type of the call and
any arguments using Julia type-assertion syntax (`::id{Object}` in the example above).

Although it is possible to build Julia APIs around this functionality, manually keeping
track of `id` pointers, it is possible to have ObjectiveC.jl do this for you:

```julia
julia> @objcwrapper NSValue

julia> obj_ptr = @objc [NSValue valueWithPointer:C_NULL::Ptr{Cvoid}]::id{NSValue}
id{NSValue}(0x00006000023cfca0)

julia> obj = NSValue(obj_ptr)
NSValueInstance (object of type NSConcreteValue)
```

The generated `NSValue` class is an abstract type that implements the type hierarchy, while
the `NSValueInstance` object is a concrete structure that houses the `id` pointer. This
split makes it possible to implement multi-level inheritance and attach functionality at
each level of the hierarchy, and should be entirely transparent to the user (i.e., you
should never need to use the `*Instance` types in code or signatures).

The `@objcwrapper` macro also generates conversion routines and accessors that makes it
possible to use these objects directly with `@objc` calls that require `id` pointers:

```julia
julia> get_pointer(val::NSValue) = @objc [val::id{NSValue} pointerValue]::Ptr{Cvoid}

julia> get_pointer(obj)
Ptr{Nothing} @0x0000000000000000
```


## Properties

A common pattern in Objective-C is to use properties to acces instance variables. Although
it is possible to access these directly using `@objc`, ObjectiveC.jl provides a macro to
automatically generate the appropriate `getproperty`, `setproperty!` and `propertynames`
definitions:

```julia-repl
julia> @objcproperties NSValue begin
           @autoproperty pointerValue::Ptr{Cvoid}
       end

julia> obj.pointerValue
Ptr{Nothing} @0x0000000000000000
```

The behavior of `@objcproperties` can be customized by passing keyword arguments to the
property macros:

```julia
@objcproperties SomeObject begin
    # simplest definition: just generate a getter,
    # and convert the property value to `DstTyp`
    @autoproperty someProperty::DstTyp

    # also generate a setter
    @autoproperty someProperty::DstTyp setter=setSomeProperty

    # if the property is an ObjC object, use an object pointer type.
    # this will make sure to do a nil check and return nothing,
    # or convert the pointer to an instance of the specified type
    @autoproperty someProperty::id{DstTyp}

    # sometimes you may want to convert to a different type
    @autoproperty someStringProperty::id{NSString} type=String

    # and finally, if more control is needed, just do it yourself:
    @getproperty someComplexProperty function(obj)
        # do something with obj
        # return a value
    end
    @setproperty! someComplexProperty function(obj, val)
        # do something with obj and val
        # return nothing
    end
end
```


## Blocks

Julia callables can be converted to Objective-C blocks using the `@objcblock` macro:

```julia-repl
julia> function hello(x)
          println("Hello, $x!")
          x+1
       end
julia> block = @objcblock(hello, Cint, (Cint,))
```

This object can now be passed to Objective-C methods that take blocks as arguments. Note
that before Julia 1.9, blocks should only ever be called from Julia-managed threads, or else
your application will crash.

If you need to use blocks that may be called from unrelated threads on Julia 1.8 or earlier,
you can use the `@objasyncblock` macro instead. This variant takes an `AsyncCondition` that
will be executed on the libuv event loop after the block has been called. Note that there
may be some time between the block being called and the condition being executed, and libuv
may decide to coalesce multiple conditions into a single execution, so it is preferred to
use `@objcblock` whenever possible. It is also not possible to pass any arguments to the
condition, but you can use a closure to capture any state you need:

```julia-repl
julia> counter = 0
julia> cond = Base.AsyncCondition() do async_cond
           counter += 1
       end
julia> block = @objcasyncblock(cond)
```


## API wrappers

ObjectiveC.jl also provides ready-made wrappers for essential frameworks like Foundation:

```julia-repl
julia> using .Foundation


julia> str = NSString("test")
NSString("test")


julia> NSArray([str, str])
<__NSArrayI 0x12e69b9b0>(
test,
test
)


julia> d = NSDictionary(Dict(str=>str))
{
    test = test;
}

julia> d[str]
id{Object}(0x836f2afbc3a7b349)

julia> Dict{NSString,NSString}(d)
Dict{NSString, NSString} with 1 entry:
  "test" => "test"
```


## Debugging

To see what ObjectiveC.jl is doing under the hood, you can toggle the `tracing` preference,
which will make the package print out the Objective-C calls it makes:

```julia-repl
julia> using ObjectiveC
julia> ObjectiveC.enable_tracing(true)
[ Info: ObjectiveC.jl tracing setting changed; restart your Julia session for this change to take effect!

# restart Julia

julia> using ObjectiveC

julia> str = NSString("test");
+ [NSString stringWithUTF8String: (Int8*)0x000000010dc65428]
  (id<NSString>)0x983d4f92876ccd8c

julia> String(str)
- [(id<NSString>)0x983d4f92876ccd8c UTF8String]
  (Int8*)0x000060000376d6a8
"test"
```

This can be useful for submitting bug reports to upstream projects which may not be
familiar with Julia.


## Current status

ObjectiveC.jl has recently been revamped, and is still under heavy development. Do not
assume its APIs are stable until version 1.0 is released. That said, it is being used
as the main FFI for [Metal.jl](https://github.com/JuliaGPU/Metal.jl), so you can expect
the existing functionality to be fairly solid.

In the process of revamping the package, some functionality was lost, including the ability
to define Objective-C classes using native-like syntax. If you are interested, please take a
look at the repository [before the
revamp](https://github.com/JuliaInterop/ObjectiveC.jl/tree/22118319da1fb7601d2a3ecefb671ffbb5e57012)
and consider contributing a PR to bring it back.
