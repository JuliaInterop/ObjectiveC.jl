# ObjectiveC.jl

*Objective-C bridge for Julia*

[![][github-img]][github-url] [![][codecov-img]][codecov-url]

[github-img]: https://github.com/JuliaInterop/ObjectiveC.jl/actions/workflows/ci.yml/badge.svg
[github-url]: https://github.com/JuliaInterop/ObjectiveC.jl/actions/workflows/ci.yml

[codecov-img]: https://codecov.io/gh/JuliaInterop/ObjectiveC.jl/branch/main/graph/badge.svg
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
NSValue (object of type NSConcreteValue)
```

Wrappers are managed by default. A typed Objective-C return such as
`@objc [NSObject new]::NSObject` creates a Julia wrapper that releases the
Objective-C object from a finalizer, using Objective-C selector-family rules to
distinguish owned (`new`/`alloc`/`copy`/`mutableCopy`/`init`) results from
borrowed results. The bare `T(ptr)` constructor is always non-owning.

Manual ownership helpers are available as public `ObjectiveC.Foundation`
bindings, but are not exported by default. `Foundation.release` is ownership
aware: on managed wrappers it eagerly releases the wrapper's owned reference at
most once, and on unmanaged wrappers it sends the raw Objective-C `release`.


## Type model

Objective-C lets a class be both *instantiated* and *subclassed with added state*. Julia's
type system doesn't allow concrete types to be extended that way, so ObjectiveC.jl splits
each ObjC class into separate Julia names for those two roles:

* the **concrete leaf** `Foo`: what you instantiate and store. Leaves are flat
  (`NSMutableString` is *not* Julia-`<:` `NSString`), which lets `Vector{NSString}` allocate
  inline and lets inference see a single fixed type through container access, even when the
  underlying Objective-C class varies at runtime.
* the **abstract kind** `FooKind <: BarKind`: a parallel lattice of abstract types
  mirroring the ObjC class hierarchy. The concrete struct's supertype embeds it directly
  via `Foo <: Object{FooKind}`, so subkind relationships are native Julia subtyping rather
  than a side table.
* the **polymorphic alias** `FooLike = Object{<:FooKind}`: what you dispatch on.
  `Object{<:FooKind}` matches `Foo` and every `@objcwrapper`ed subclass via ordinary `<:`,
  so a method written against `FooLike` keeps working when new subclasses land later,
  including in downstream packages.

In short, every `@objcwrapper Foo <: Bar` produces *one type for storage, one parameter
for the lattice, and one alias for dispatch*. The macro arranges the wiring; downstream
code uses the leaf for fields and containers, and the `Like` alias in method signatures:

```julia
julia> get_pointer(val::NSValueLike) =
           @objc [val::id{NSValue} pointerValue]::Ptr{Cvoid}

julia> get_pointer(obj)
Ptr{Nothing} @0x0000000000000000
```


## Lifetime management

Objective-C objects are reference counted: `retain` bumps an object's count, `release` drops
it, and the object is freed when the count hits zero. Whoever creates or holds an object has
to balance its retains with releases. ObjectiveC.jl can do that bookkeeping for you, using the
same rules the ARC compiler applies.

Each wrapper is either managed or not. You pick per class with the `managed` keyword of
`@objcwrapper`, and managed is the default:

* a managed wrapper is a mutable struct that owns a reference to its object. It attaches a
  finalizer that releases the object once the wrapper is collected. You can also call
  `release` to free the wrapper's owned reference before the garbage collector gets there.
* an unmanaged wrapper (`managed=false`) is an immutable, `isbits` borrowed reference. It
  never retains or releases anything, and it counts on the object's lifetime being guaranteed
  somewhere else. These are cheap to pass around.

### ARC-style returns

The return type you write on an `@objc` call decides how the result comes back:

```julia
@objc [obj someMethod]::id{Foo}              # raw pointer, you own the result
@objc [obj someMethod]::Foo                  # managed wrapper
@objc [obj someMethod]::Union{Nothing,Foo}   # managed wrapper, or nothing on nil
```

`::id{Foo}` gives you the bare pointer and gets out of the way. `::Foo` returns a managed
wrapper. `::Union{Nothing,Foo}` does the same but turns a `nil` result into `nothing` instead
of throwing.

To wrap the result, ObjectiveC.jl reads the selector and applies ARC's ownership rules.
Methods in the `alloc`, `new`, `copy`, `mutableCopy`, and `init` families already return
something you own, so the wrapper takes that reference as-is. Every other method returns a
borrowed object, so the wrapper retains it first. The finalizer issues the one matching
release either way.

```julia
# `new` is an owned-family selector, so the wrapper takes the result as-is.
obj = @objc [NSObject new]::NSObject

# `self` is not, so the result is borrowed and the wrapper retains it.
same = @objc [obj self]::NSObject
```

When you have a pointer from somewhere other than `@objc`, e.g. from a `::id{T}` call,
there are several ways to wrap it yourself:

* `T(ptr)` wraps a pointer, without retaining or installing a finalizer to release it.
* `adopt(T, ptr)` wraps a pointer without retaining it, but installs a finalizer.
* `retain(T, ptr)` retains a borrowed pointer, wraps the result, and installs a finalizer.

### Release timing

The ownership decisions match ARC, but the timing doesn't. ARC releases an object the moment
its last strong reference leaves scope. Here the release runs from a finalizer, whenever the
garbage collector gets around to the wrapper. If you know a managed wrapper is done, you can
manually call `release(obj)` to release its owned reference immediately. This is safe to
call repeatedly and safe if the finalizer later runs.

### Unmanaged objects

It's possible to opt out of reference counting entirely by using `managed=false` on the
wrapper. This is unsafe, and only makes sense in a handful of cases:

* value-like objects such as strings, numbers, collections, and URLs;
* control objects that run their own lifetime, like autorelease pools, blocks, and dispatch
  objects;
* objects something else already keeps alive: singletons, pooled objects, or resources whose
  release is coordinated elsewhere.

Beware that this also opts out of the idempotency of `release`. If you call `release` on an
unmanaged wrapper, it sends the raw `release` message to the object, which may crash if the
object is already freed. It is thus advised not to opt out of automatic memory management
when the lifetime of an object is non-trivial.


## Properties

A common pattern in Objective-C is to use properties to access instance variables. Although
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

This object can now be passed to Objective-C methods that take blocks as arguments. The
callable runs synchronously on the thread that invokes the block. Since Julia 1.9 a foreign
thread is adopted into the runtime when it enters Julia, so the block may be invoked from any
thread; before Julia 1.9 it could only be called from Julia-managed threads, or else the
application would crash. Even with adoption, the callable still runs synchronously on the
invoking thread, so it must not task-switch (yield, wait, do I/O) when another thread may be
blocked waiting for the block to return — doing so can deadlock.

For fire-and-forget callbacks where no synchronous result is required, use the
`@objcasyncblock` macro instead. Rather than running Julia code on the invoking thread, it
signals an `AsyncCondition` on the libuv event loop and returns immediately, so the handler
runs asynchronously on a Julia-managed thread and the invoking (possibly foreign) thread is
never blocked. Note that there may be some time between the block being called and the
condition being executed, and libuv may coalesce multiple signals into a single execution.
It is also not possible to pass any arguments to the condition, but you can use a closure to
capture any state you need:

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

For programmatic profiling or integration with external tooling, ObjectiveC.jl also
provides a runtime tracer. It can be enabled and disabled without restarting Julia:

```julia-repl
julia> events = Tuple{Symbol,Symbol,UInt64,UInt64}[]

julia> ObjectiveC.tracing_subscribe() do class, selector, t_enter, t_exit
           push!(events, (class, selector, t_enter, t_exit))
       end

julia> str = NSString("test");

julia> ObjectiveC.tracing_unsubscribe()

julia> ns_per_tick = ObjectiveC.tracing_timebase();
```

The callback receives the static wrapper class label, selector, and enter/exit timestamps
from `mach_absolute_time`. Multiply timestamp differences by `tracing_timebase()` to get
nanoseconds. Only one tracing subscriber can be active at a time. The callback runs
synchronously on the thread making the Objective-C call, and ObjectiveC.jl suppresses
recursive tracing if the callback itself makes Objective-C calls.


## Current status

ObjectiveC.jl is still under active development, so breaking releases are to be expected.
That said, the package is used as the main FFI for [Metal.jl](https://github.com/JuliaGPU/Metal.jl), so you can expect
the existing functionality to be fairly solid.

In the process of revamping the package, some functionality was lost, including the ability
to define Objective-C classes using native-like syntax. If you are interested, please take a
look at the repository [before the
revamp](https://github.com/JuliaInterop/ObjectiveC.jl/tree/22118319da1fb7601d2a3ecefb671ffbb5e57012)
and consider contributing a PR to bring it back.
