using ObjectiveC
using Test

@testset "version" begin
    @test ObjectiveC.darwin_version() isa VersionNumber
    @test ObjectiveC.macos_version() isa VersionNumber
    @test ObjectiveC.is_macos(ObjectiveC.macos_version())
end

# Availability
@objcwrapper availability = macos(v"1000") TestWrapperNoIntro1 <: Object
@objcwrapper availability = macos(introduced = v"1000") TestWrapperNoIntro2 <: Object
@objcwrapper availability = macos(deprecated = v"1", obsoleted = v"2.3.4") TestWrapperObsolete <: Object
@objcwrapper availability = macos(introduced = v"1000", unavailable = true) TestWrapperUnavailable <: Object
@objcwrapper availability = macos(v"0") TestPropAvail <: Object
@objcproperties TestPropAvail begin
    @autoproperty length::Culong
    @autoproperty UTF8String::Ptr{Cchar} availability = macos(v"0")
    @autoproperty NoIntro1Property::Cint availability = macos(v"1000")
    @autoproperty NoIntro2Property::Cint availability = macos(introduced = v"1000")
    @autoproperty ObsoleteProperty::Cint availability = macos(deprecated = v"1", obsoleted = v"2.3")
    @autoproperty UnavailableProperty::Cint availability = macos(introduced = v"1000", unavailable = true)
end
@objcwrapper availability = [macos(v"1000")] TestVectUnavail <: Object
@objcwrapper availability = [macos(v"1000"), darwin(v"0")] TestVectMultiple1 <: Object
@objcwrapper availability = [macos(v"0"), darwin(v"1000")] TestVectMultiple2 <: Object
@objcwrapper availability = [macos(v"0"), darwin(v"0")] TestVectMultiple3 <: Object
@objcwrapper availability = [macos(v"0")] TestVectAvail <: Object
@objcproperties TestVectAvail begin
    @autoproperty length::Culong
    @autoproperty UTF8String::Ptr{Cchar} availability = [macos(v"0")]
    @autoproperty VectUnavailableProperty::Cint availability = [macos(introduced = v"1000")]
end
@testset "availability" begin
    # wrapper
    let # not yet introduced arg version
        fakeidwrap = id{TestWrapperNoIntro1}(1)
        @test_throws "UnavailableError: `TestWrapperNoIntro1` was introduced on macOS v1000.0.0" TestWrapperNoIntro1(fakeidwrap)
    end
    let # not yet introduced kwarg version
        fakeidwrap = id{TestWrapperNoIntro2}(1)
        @test_throws "UnavailableError: `TestWrapperNoIntro2` was introduced on macOS v1000.0.0" TestWrapperNoIntro2(fakeidwrap)
    end
    let # obsolete
        fakeidwrap = id{TestWrapperObsolete}(1)
        @test_throws "UnavailableError: `TestWrapperObsolete` is obsolete since macOS v2.3.4" TestWrapperObsolete(fakeidwrap)
    end
    let # unavailable
        fakeidwrap = id{TestWrapperUnavailable}(1)
        @test_throws "UnavailableError: `TestWrapperUnavailable` is not available on macOS" TestWrapperUnavailable(fakeidwrap)
    end
    let # not yet introduced in vector
        fakeidwrap = id{TestVectUnavail}(1)
        @test_throws "UnavailableError: `TestVectUnavail` was introduced on macOS v1000.0.0" TestVectUnavail(fakeidwrap)
    end
    let # not yet introduced in vector for multiple
        fakeidwrap = id{TestVectMultiple1}(1)
        @test_throws "UnavailableError: `TestVectMultiple1` was introduced on macOS v1000.0.0" TestVectMultiple1(fakeidwrap)
    end
    let # not yet introduced in vector for multiple
        fakeidwrap = id{TestVectMultiple2}(1)
        @test_throws "UnavailableError: `TestVectMultiple2` was introduced on Darwin v1000.0.0" TestVectMultiple2(fakeidwrap)
    end
    let # Make sure it does not error
        fakeidwrap = id{TestVectMultiple3}(1)
        @test TestVectMultiple3(fakeidwrap) isa TestVectMultiple3
    end

    # property
    str1 = "foo"
    prop = TestPropAvail(@objc [NSString stringWithUTF8String:str1::Ptr{UInt8}]::id{TestPropAvail})

    @test :length in propertynames(prop)
    @test :UTF8String in propertynames(prop)
    @test :NoIntro1Property in propertynames(prop)
    @test :NoIntro2Property in propertynames(prop)
    @test :ObsoleteProperty in propertynames(prop)
    @test :UnavailableProperty in propertynames(prop)

    @test prop.length == length(str1)
    @test unsafe_string(prop.UTF8String) == str1
    @test_throws "UnavailableError: `TestPropAvail.NoIntro1Property` was introduced on macOS v1000.0.0"  prop.NoIntro1Property
    @test_throws "UnavailableError: `TestPropAvail.NoIntro2Property` was introduced on macOS v1000.0.0"  prop.NoIntro2Property
    @test_throws "UnavailableError: `TestPropAvail.ObsoleteProperty` is obsolete since macOS v2.3.0" prop.ObsoleteProperty
    @test_throws "UnavailableError: `TestPropAvail.UnavailableProperty` is not available on macOS" prop.UnavailableProperty

    vectprop = TestVectAvail(@objc [NSString stringWithUTF8String:str1::Ptr{UInt8}]::id{TestVectAvail})
    @test_throws "UnavailableError: `TestVectAvail.VectUnavailableProperty` was introduced on macOS v1000.0.0"  vectprop.VectUnavailableProperty

    @test_throws "UnavailableError: `TestVectAvail.VectUnavailableProperty` was introduced on macOS v1000.0.0"  vectprop.VectUnavailableProperty
    @test_throws "UnavailableError: `TestVectAvail.VectUnavailableProperty` was introduced on macOS v1000.0.0"  vectprop.VectUnavailableProperty

    @test_throws UndefVarError macroexpand(@__MODULE__, :(@objcwrapper availability = templeos(v"1000") TestBadAvail2 <: Object))
    @test_throws UndefVarError macroexpand(@__MODULE__, :(@objcwrapper availability = [templeos(v"1000")] TestBadAvail3 <: Object))
    @test_throws "`availability` keyword argument must be a valid `PlatformAvailability`" macroexpand(@__MODULE__, :(@objcwrapper availability = [6] TestBadAvail4 <: Object))
    @test_throws "`availability` keyword argument must be a valid `PlatformAvailability`" macroexpand(@__MODULE__, :(@objcwrapper availability = 6 TestBadAvail5 <: Object))
end

@testset "@objc macro" begin
    # class methods
    @objc [NSString new]::id{Object}
    data = "test"
    @objc [NSString stringWithUTF8String:data::Ptr{UInt8}]::id{Object}
    @objc [NSString stringWithUTF8String:"test"::Ptr{UInt8}]::id{Object}
    obj = @objc [NSString stringWithUTF8String:"test"::Ptr{UInt8}]::id{Object}

    # instance methods
    @objc [obj::id{Object} length]::UInt
    @objc [obj::id{Object} length]::UInt
    @test @objc [obj::id{Object} isEqualTo:obj::id{Object}]::Bool
    empty_str = @objc [NSString string]::id{Object}
    @objc [obj::id stringByReplacingOccurrencesOfString:empty_str::id{Object} withString:empty_str::id{Object}]::id{Object}

    # chained class + instance calls
    @objc [[NSString alloc]::id{Object} init]::id{Object}
end

@objcwrapper TestNSString <: Object
@testset "@objc calls" begin
    data = "test"
    ptr = @objc [NSString stringWithUTF8String:data::Ptr{UInt8}]::id{TestNSString}
    @test ptr isa id{TestNSString}
    @test class(ptr) isa Class
    @test "length" in methods(ptr)
    @test 4 == @objc [ptr::id length]::Culong

    obj = TestNSString(ptr)
    @test Base.unsafe_convert(id, obj) == ptr
    @test_throws UndefRefError TestNSString(nil)
end

@objcproperties TestNSString begin
    @autoproperty length::Culong
    @static if true
        @autoproperty UTF8String::Ptr{Cchar}
    end
    @static if false
        @autoproperty NonExistingProperty::Cint
    end
end
@objcwrapper TestNSMutableString <: TestNSString
@objcproperties TestNSMutableString begin
    @setproperty! string function(obj, val)
        @objc [obj::id{TestNSMutableString} setString:val::id{TestNSString}]::Nothing
    end
end
@objcwrapper TestNSOperationQueue <: Object
@objcproperties TestNSOperationQueue begin
    @autoproperty name::id{TestNSString} setter=setName
end
@testset "@objcproperties" begin
    # immutable object with only read properties
    str1 = "foo"
    immut = TestNSString(@objc [NSString stringWithUTF8String:str1::Ptr{UInt8}]::id{TestNSString})

    @test :length in propertynames(immut)
    @test :UTF8String in propertynames(immut)
    @test :NonExistingProperty ∉ propertynames(immut)

    @test immut.length == length(str1)
    @test unsafe_string(immut.UTF8String) == str1

    # mutable object with a write property
    str2 = "barbar"
    mut = TestNSMutableString(@objc [NSMutableString stringWithUTF8String:str2::Ptr{UInt8}]::id{TestNSMutableString})

    @test :length in propertynames(mut)
    @test :UTF8String in propertynames(mut)
    @test :string in propertynames(mut)
    @test :NonExistingProperty ∉ propertynames(mut)

    @test mut.length == length(str2)
    @test unsafe_string(mut.UTF8String) == str2

    mut.string = immut
    @test mut.length == length(str1)
    @test unsafe_string(mut.UTF8String) == str1

    # mutable object using @autoproperty to generate a setter
    queue = TestNSOperationQueue(@objc [NSOperationQueue new]::id{TestNSOperationQueue})
    @test queue.name isa TestNSString
    @test unsafe_string(queue.name.UTF8String) != str1
    queue.name = immut
    @test unsafe_string(queue.name.UTF8String) == str1
end

@testset "@objc blocks" begin
    # create a dummy class we'll register our blocks with
    # (no need to use @objcwrapper as we're not constructing an id{BlockWrapper})
    wrapper_class = ObjectiveC.createclass(:BlockWrapper, Class(:NSObject))
    ptr = @objc [BlockWrapper alloc]::id{Object}

    # use the same type signature for both methods
    types = (Cint, Object, Selector, Cint)
    typestr = ObjectiveC.encodetype(types...)

    @testset "simple" begin
        function addone(self, x::T) where T
            return x + one(T)
        end
        @assert sizeof(addone) == 0
        block = Foundation.@objcblock(addone, Cint, (id{Object}, Cint,))

        imp = ccall(:imp_implementationWithBlock, Ptr{Cvoid}, (id{Foundation.NSBlock},), block)
        @assert ccall(:class_addMethod, Bool,
                    (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cchar}),
                    wrapper_class, sel"invoke_simple:", imp, typestr)

        # create a wrapper instance and call our block
        ret = @objc [ptr::id{Object} invoke_simple:41::Cint]::Cint
        @test ret == 42
    end

    @testset "closure" begin
        val = Cint(2)
        function addbox(self, x::T) where T
            return x + val
        end
        @assert sizeof(addbox) != 0
        block = @objcblock(addbox, Cint, (id{Object}, Cint,))

        imp = ccall(:imp_implementationWithBlock, Ptr{Cvoid}, (id{Foundation.NSBlock},), block)
        @assert ccall(:class_addMethod, Bool,
                        (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cchar}),
                        wrapper_class, sel"invoke_closure:", imp, typestr)

        ret = @objc [ptr::id{Object} invoke_closure:40::Cint]::Cint
        @test ret == 42
    end

    @testset "async" begin
        val = Ref(0)
        cond = Base.AsyncCondition() do async_cond
            val[] += 1
            close(async_cond)
        end
        block = @objcasyncblock(cond)

        types = (Nothing, Selector)
        typestr = ObjectiveC.encodetype(types...)

        imp = ccall(:imp_implementationWithBlock, Ptr{Cvoid}, (id{Foundation.NSBlock},), block)
        @assert ccall(:class_addMethod, Bool,
                      (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cchar}),
                       wrapper_class, sel"invoke_async_condition", imp, typestr)

        ret = @objc [ptr::id{Object} invoke_async_condition]::Nothing
        retry(; delays=[0, 0.1, 1]) do
            # XXX: is there another wait? `wait(cond)` doesn't seem to work on 1.6
            val[] == 1 || error("val[] = $(val[])")
        end()
    end
end

using .Foundation
@testset "foundation" begin

@testset "NSAutoReleasePool" begin
    # a function that creates an `autorelease`d object (by calling `arrayWithObjects`)
    function trigger_autorelease()
        str1 = NSString("Hello")
        str2 = NSString("World")
        arr1 = [str1, str2]
        NSArray([str1, str2])
    end

    # low-level API
    let pool=NSAutoreleasePool()
        trigger_autorelease()
        drain(pool)
    end

    # high-level API
    @autoreleasepool begin
        trigger_autorelease()
    end
    @autoreleasepool function foo()
        trigger_autorelease()
    end
    foo()
end

# run the remainder of the tests in an autorelease pool to avoid leaking objects
@autoreleasepool begin

@testset "NSString" begin
    str = NSString()
    @test is_kind_of(str, Class("NSString"))
    @test class(str) isa Class
    @test length(str) == 0
    @test String(str) == ""

    str = NSString("test")
    @test length(str) == 4
    @test String(str) == "test"

    @test NSString() == NSString()
    @test "" == NSString()
    @test NSString() == ""

    @test NSString("foo") != NSString("bar")
    @test "foo" != NSString("bar")
    @test NSString("foo") != "bar"
end

@testset "NSHost" begin
    @test startswith(gethostname(), hostname())
end

@testset "NSBundle" begin
    load_framework("IOKit")
    @test_throws ErrorException load_framework("NonExistingFramework")
end

@testset "NSArray" begin
    str1 = NSString("Hello")
    str2 = NSString("World")
    arr1 = [str1, str2]
    arr2 = NSArray([str1, str2])
    @test length(arr2) == 2
    @test reinterpret(NSString, arr2[1]) == "Hello"
    @test reinterpret(NSString, arr2[2]) == "World"
    @test Vector{NSString}(arr2) == arr1

    @test_throws MethodError NSArray([NSUInteger(42)])
end

@testset "NSDictionary" begin
    str1 = NSString("Hello")
    str2 = NSString("World")
    dict1 = Dict(str1 => str2)
    dict2 = NSDictionary(dict1)
    @test length(dict2) == 1
    @test keys(dict2) == NSArray([str1])
    @test values(dict2) == NSArray([str2])
    @test reinterpret(NSString, dict2[str1]) == "World"
    @test_throws KeyError dict2[str2]
    @test Dict{NSString,NSString}(dict2) == dict1
end

@testset "NSError" begin
    err = NSError("NSPOSIXErrorDomain", 1)
    @test isempty(err.userInfo)
    @test contains(err.localizedFailureReason, "Operation not permitted")
end

@testset "NSValue" begin
    val1 = Ptr{Cvoid}(12345)
    val2 = NSValue(val1)
    @test val2.pointerValue == val1
    @test val2 == NSValue(val1)

    val3 = NSRange(1,2)
    val4 = NSValue(val3)
    @test val4.rangeValue == val3
    @test val4 != val2
end

@testset "NSRange" begin
    # test conversion from UnitRange
    val1 = UnitRange(2:20)
    val2 = NSValue(val1)
    @test first(val1) == first(val2.rangeValue)
    @test last(val1) == last(val2.rangeValue)
    @test length(val1) == length(val2.rangeValue)
end

@testset "NSNumber" begin
    @testset "bool" begin
        t = NSNumber(true)
        f = NSNumber(false)
        @test t == t
        @test t != f
        @test t.boolValue == true
        @test f.boolValue == false
        @test convert(NSNumber, true) == t
        @test convert(NSNumber, false) == f
    end

    @testset "int" begin
        i = NSNumber(123)
        j = NSNumber(456)
        @test i == i
        @test i != j
        @test i.intValue == 123
        @test j.intValue == 456
        @test convert(NSNumber, 123) == i
        @test convert(NSNumber, 456) == j
    end

    @testset "decimal" begin
        i = NSNumber(3.14)
        @test i.decimalValue == NSDecimal(NSDecimalNumber("3.14"))
    end
end

@testset "NSDecimal" begin
    @test zero(NSDecimalNumber) == zero(NSDecimalNumber)
    @test zero(NSDecimalNumber) != one(NSDecimalNumber)
    @test zero(NSDecimalNumber) < one(NSDecimalNumber)
    @test one(NSDecimalNumber) > zero(NSDecimalNumber)
    @test one(NSDecimalNumber) != NaNDecimalNumber()
    @test one(NSDecimalNumber) > typemin(NSDecimalNumber)
    @test one(NSDecimalNumber) < typemax(NSDecimalNumber)

    # –12.345, expressed as 12345x10^–3: mantissa 12345; exponent –3; isNegative YES
    num = NSDecimalNumber(mantissa=12345, exponent=-3, negative=true)
    @test num == NSDecimalNumber("-12.345")

    # conversion to raw NSDecimal
    dec = NSDecimal(num)
    @test dec.mantissa == 12345
    @test dec.exponent == -3
    @test dec.isNegative

    # conversion back to NSDecimalNumber
    @test NSDecimalNumber(dec) == num
end

@testset "NSURL" begin
    url = NSURL("https://julialang.org/downloads/")
    @test !url.isFileURL
    @test url.scheme == "https"
    @test url.host == "julialang.org"
    @test url.path == "/downloads"
    @test url == NSURL("https://julialang.org/downloads/")

    file = NSFileURL("/foo/bar/baz.qux")
    @test file.isFileURL
    @test file.path == "/foo/bar/baz.qux"
    @test file.lastPathComponent == "baz.qux"
    @test file.pathComponents == NSString["/", "foo", "bar", "baz.qux"]
    @test file != url
end

@testset "NSProcessInfo" begin
    info = NSProcessInfo()

    @test info.processIdentifier == ccall("getpid", Cint, ())

    @test info.operatingSystemVersion isa NSOperatingSystemVersion
end

end

end

@testset "dispatch" begin

using .Dispatch

@testset "dispatch_data" begin
    arr = [1]
    GC.@preserve arr begin
        data = dispatch_data(pointer(arr), sizeof(arr))

        retain(data)
        release(data)

        @test sizeof(data) == sizeof(arr)

        release(data)
    end
end

end

@testset "core foundation" begin

using .CoreFoundation

@testset "allocator" begin
    allocator = default_allocator()

    size = 100
    @test preferred_size(allocator, size) >= size
    mem = allocate!(allocator, size)
    mem = reallocate!(allocator, mem, size*2)
    deallocate!(allocator, mem)

    # other allocators aren't directly usable, but do test their constructors
    @test system_default_allocator() !== nothing
    @test malloc_allocator() !== nothing
    @test malloc_zone_allocator() !== nothing
    @test null_allocator() !== nothing
end

@testset "strings" begin
    str = CFString("foobar")
    @test str[1] == 'f'
    @test_throws BoundsError str[0]
    @test_throws BoundsError str[7]
    @test length(str) == 6
    @test String(str) == "foobar"
    @test string(str) == "foobar"
    @test sprint(show, str) == "CFString(\"foobar\")"
end

@testset "run loop" begin
    loop = current_loop()
    @test loop == main_loop()
    wake_loop(loop)
    stop_loop(loop)
    @test loop_waiting(loop) == false

    @test run_loop(0.1) == CoreFoundation.RunLoopRunTimedOut
end

@testset "notifications" begin
    for (center, synchronous) in [(local_notify_center(), true),
                                  (darwin_notify_center(), false)]
        foo_calls = 0
        bar_calls = 0
        foobar_calls = 0
        foo_observer = CFNotificationObserver() do center, name, object, info
            foo_calls += 1
        end
        bar_observer = CFNotificationObserver() do center, name, object, info
            bar_calls += 1
        end
        foobar_observer = CFNotificationObserver() do center, name, object, info
            foobar_calls += 1
        end

        try
            add_observer!(center, foo_observer; name="foo")
            add_observer!(center, foobar_observer; name="foo")
            add_observer!(center, bar_observer; name="bar")
            add_observer!(center, foobar_observer; name="bar")

            post_notification!(center, "foo")
            if !synchronous
                run_loop(10; return_after_source_handled=true)
            end
            @test foo_calls == 1
            @test foobar_calls == 1

            post_notification!(center, "bar")
            if !synchronous
                run_loop(10; return_after_source_handled=true)
            end
            @test bar_calls == 1
            @test foobar_calls == 2

            # test unsubscribing from a specific notification
            remove_observer!(center, foobar_observer; name="foo")

            post_notification!(center, "foo")
            if !synchronous
                run_loop(10; return_after_source_handled=true)
            end
            @test foo_calls == 2
            @test foobar_calls == 2

            post_notification!(center, "bar")
            if !synchronous
                run_loop(10; return_after_source_handled=true)
            end
            @test bar_calls == 2
            @test foobar_calls == 3

            # test unsubscribing from all notifications
            remove_observer!(center, foobar_observer)

            post_notification!(center, "bar")
            if !synchronous
                run_loop(10; return_after_source_handled=true)
            end
            @test bar_calls == 3
            @test foobar_calls == 3
        finally
            remove_observer!(center, foo_observer)
            remove_observer!(center, bar_observer)
            remove_observer!(center, foobar_observer)
        end
    end
end

end

using .OS
@testset "os" begin

@testset "log" begin

let logger = OSLog()
    logger("test")
    logger("test", type=OS.LOG_TYPE_INFO)
end

let logger = OSLog(enabled=false)
    logger("test")
    logger("test", type=OS.LOG_TYPE_INFO)
end

let logger = OSLog("org.juliainterop.objectivec", "test suite")
    logger("test")
    logger("test", type=OS.LOG_TYPE_INFO)
end

end

@testset "signpost" begin

@testset "interval" begin
# basic usage
let
    @test @signpost_interval "test" begin
        true
    end
end

# scope handling
let
    foo = @signpost_interval "test" begin
        bar = 42
    end
    @test foo == 42
    @test bar == 42
end

# specifying a logger
let
    @signpost_interval log=OSLog() "test" begin end
end

# specifying begin and end messages
let
    foo = 41
    @signpost_interval start="begin $foo" stop="end $bar" "test" begin
        bar = 42
    end
end

# delayed evaluation of inputs
let
    @test @signpost_interval log=OSLog(enabled=false) start=error() stop=error() error() begin
        # the body should still be evaluated
        true
    end
end
end

@testset "event" begin

# basic usage
@signpost_event "test"
@signpost_event "test" "with details"

# specifying a logger
@signpost_event log=OSLog() "test" "with details"
end

# delayed evaluation
@signpost_event log=OSLog(enabled=false) error() error()

end

end

@testset "tracing" begin
    ObjectiveC.enable_tracing(true)
    cmd = ```$(Base.julia_cmd()) --project=$(Base.active_project())
                                 --eval "using ObjectiveC; using .Foundation; String(NSString())"```

    out = Pipe()
    err = Pipe()
    proc = run(pipeline(cmd, stdout=out, stderr=err), wait=false)
    close(out.in)
    close(err.in)
    wait(proc)
    out = read(out, String)
    err = read(err, String)

    @test success(proc)
    @test isempty(out)
    @test contains(err, "+ [NSString string]")
    @test contains(err, r"- \[.+ UTF8String\]")
end
