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
@objcwrapper availability = test(introduced = v"1000") TestIgnore <: Object
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
@objcwrapper availability = [macos(v"0"), test(v"1000")] TestVectMultiple4 <: Object
@objcwrapper availability = [macos(v"0")] TestVectAvail <: Object
@objcproperties TestVectAvail begin
    @autoproperty length::Culong
    @autoproperty UTF8String::Ptr{Cchar} availability = [macos(v"0")]
    @autoproperty VectUnavailableProperty::Cint availability = [darwin(introduced = v"1000")]
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
    let # Not-applicable platform ignored
        fakeidwrap = id{TestIgnore}(1)
        @test TestIgnore(fakeidwrap) isa TestIgnore
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
    let # Not-applicable platform ignored
        fakeidwrap = id{TestVectMultiple4}(1)
        @test TestVectMultiple4(fakeidwrap) isa TestVectMultiple4
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
    @test_throws "UnavailableError: `TestVectAvail.VectUnavailableProperty` was introduced on Darwin v1000.0.0"  vectprop.VectUnavailableProperty

    @test_throws "`:templeos` is not a supported platform for `PlatformAvailability`" macroexpand(@__MODULE__, :(@objcwrapper availability = templeos(v"1000") TestBadAvail2 <: Object))
    @test_throws "`:templeos` is not a supported platform for `PlatformAvailability`" macroexpand(@__MODULE__, :(@objcwrapper availability = [templeos(v"1000")] TestBadAvail3 <: Object))
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

    @test_throws "Couldn't find class ObjectiveCClassCacheRetry" (@objc [ObjectiveCClassCacheRetry new]::id{Object})
    ObjectiveC.createclass(:ObjectiveCClassCacheRetry, Class(:NSObject))
    retry_obj = @objc [ObjectiveCClassCacheRetry new]::id{Object}
    @test retry_obj != nil
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

# `@objcwrapper Foo` (no explicit parent) must work from a module that hasn't
# brought `Object` into scope; the default super has to be fully qualified.
module NoObjectImport
    import ..ObjectiveC
    import ..ObjectiveC: @objcwrapper
    @objcwrapper NoImportWrapper
end
@testset "@objcwrapper default super qualified" begin
    # `Object` is parametric on Kind, so the immediate supertype is a
    # parameterized `Object{NoImportWrapperKind}`. Subtyping into the
    # unparameterized umbrella still holds.
    @test NoObjectImport.NoImportWrapper <: ObjectiveC.Object
    @test ObjectiveC.objc_parent(NoObjectImport.NoImportWrapper) === ObjectiveC.Object
    @test ObjectiveC.is_managed_wrapper(NoObjectImport.NoImportWrapper)
    @test Base.ismutabletype(NoObjectImport.NoImportWrapper)
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
# bare subclass: no `@objcproperties` of its own, used to verify that
# `propertynames` inherits the parent's property list.
@objcwrapper TestNSStringBareSub <: TestNSString
@testset "@objcproperties" begin
    # object with only read properties
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

    # subclass without its own @objcproperties block still surfaces the
    # parent's properties via propertynames.
    bare = TestNSStringBareSub(@objc [NSString stringWithUTF8String:str1::Ptr{UInt8}]::id{TestNSStringBareSub})
    @test :length in propertynames(bare)
    @test :UTF8String in propertynames(bare)
    @test bare.length == length(str1)

    # Const-prop on literal property access: `obj.length` must infer the
    # exact return type, not the Union of every property in the ancestor
    # chain. Regression guard for the `@inline objc_getproperty` cascade.
    get_len(s) = s.length
    @test Base.return_types(get_len, (TestNSString,))[1] === Culong
    @test Base.return_types(get_len, (TestNSStringBareSub,))[1] === Culong
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

# Polymorphic methods declared at top level: they should dispatch on
# subclasses declared later, even from outside the current testset.
open_len_kind(s::TestNSStringLike)::Int =
    Int(@objc [s::id{TestNSString} length]::Culong)
open_pair(a::TestNSStringLike, b::TestNSOperationQueueLike) =
    (typeof(a), typeof(b))
# Subclass declared *after* the methods above — Kind-lattice dispatch
# means it just works, with no warning, no registry, and no Union to
# refreeze.
@objcwrapper TestLateSub <: TestNSString

@testset "inheritance / Like aliases" begin
    # The existing @objcproperties fixture gives us a two-level hierarchy:
    #   TestNSMutableString <: TestNSString <: Object
    # plus a sibling TestNSOperationQueue <: Object.

    # Native subtyping on `Object{K}` mirrors the ObjC parent chain — there's
    # no bespoke `inherits_from` anymore, just `<:`.
    @test TestNSMutableString <: TestNSStringLike
    @test TestNSMutableString <: Object{<:ObjectiveC.classkind(Object)}
    @test !(TestNSString <: Object{<:ObjectiveC.classkind(TestNSMutableString)})
    @test !(TestNSOperationQueue <: TestNSStringLike)

    # The same relation viewed at the Kind level.
    @test ObjectiveC.classkind(TestNSMutableString) <: ObjectiveC.classkind(TestNSString)
    @test ObjectiveC.classkind(TestNSString) <: ObjectiveC.classkind(Object)
    @test !(ObjectiveC.classkind(TestNSOperationQueue) <: ObjectiveC.classkind(TestNSString))

    # id{Sub} ↔ id{Parent} conversion follows the Kind lattice
    raw = @objc [NSMutableString stringWithUTF8String:"abcd"::Ptr{UInt8}]::id{TestNSMutableString}
    @test raw isa id{TestNSMutableString}
    @test convert(id{TestNSString}, raw) isa id{TestNSString}
    @test convert(id{Object}, raw) isa id{Object}
    @test_throws ArgumentError convert(id{TestNSOperationQueue}, raw)
    # downcast is allowed through reinterpret only
    parent_ptr = convert(id{TestNSString}, raw)
    @test_throws ArgumentError convert(id{TestNSMutableString}, parent_ptr)
    @test reinterpret(id{TestNSMutableString}, parent_ptr) isa id{TestNSMutableString}

    mut = TestNSMutableString(raw)
    str = TestNSString(@objc [NSString stringWithUTF8String:"xyz"::Ptr{UInt8}]::id{TestNSString})
    queue = TestNSOperationQueue(@objc [NSOperationQueue new]::id{TestNSOperationQueue})

    # A method typed on `TestNSStringLike` dispatches across the Kind
    # lattice — parent and every subclass route to the same body.
    @test open_len_kind(mut) == 4    # subclass
    @test open_len_kind(str) == 3    # exact type
    # …including subclasses declared *after* the method site.
    late = TestLateSub(@objc [NSString stringWithUTF8String:"xyz"::Ptr{UInt8}]::id{TestLateSub})
    @test open_len_kind(late) == 3

    # non-conforming class → clean MethodError.
    @test_throws MethodError open_len_kind(queue)

    # the body sees the concrete subclass.
    concretetype(s::TestNSStringLike) = typeof(s)
    @test concretetype(mut) === TestNSMutableString
    @test concretetype(str) === TestNSString

    # property access works natively — no wrapper involved
    @test mut.length == 4
    @test unsafe_string(mut.UTF8String) == "abcd"

    # multiple `Like` slots: dispatch picks each concrete type
    # independently.
    pair_same(a::TestNSStringLike, b::TestNSStringLike) =
        (typeof(a), typeof(b))
    @test pair_same(mut, str) === (TestNSMutableString, TestNSString)
    @test pair_same(str, mut) === (TestNSString, TestNSMutableString)

    # different parents in a single signature — also covers the
    # cross-hierarchy method created at top level above (open_pair).
    @test open_pair(mut, queue) === (TestNSMutableString, TestNSOperationQueue)
    @test_throws MethodError open_pair(queue, queue)
    @test_throws MethodError open_pair(mut, mut)

    # other positional args may be anonymous-typed (`::SomeType`).
    with_anon(s::TestNSStringLike, ::Type{T}) where {T<:Integer} =
        (typeof(s), T)
    @test with_anon(mut, Int32) === (TestNSMutableString, Int32)

    # `Object{<:ObjectKind}` matches any wrapper, and a subclass declared
    # afterwards also routes through it.
    anyobj(x::Object{<:ObjectiveC.ObjectKind}) = typeof(x)
    @test anyobj(mut) === TestNSMutableString
    @test anyobj(queue) === TestNSOperationQueue
    @test_nowarn @eval @objcwrapper TestNSAnyObjSub <: Object

    # Constructor overloads via Like aliases compose normally: each is just
    # a plain Julia method, no entry/body forwarder to dedup.
    @eval @objcwrapper TestCtorTarget <: Object
    @eval TestCtorTarget(x::TestNSStringLike) =
        TestCtorTarget(reinterpret($id{TestCtorTarget}, $pointer(x)))
    @test_nowarn @eval TestCtorTarget(x::TestNSOperationQueueLike) =
        TestCtorTarget(reinterpret($id{TestCtorTarget}, $pointer(x)))
end

using .Foundation

@objcwrapper TestManagedNSObject <: NSObject
@objcwrapper managed = false TestUnmanagedNSObject <: NSObject

function owned_object_ptr()
    @objc [NSObject new]::id{TestManagedNSObject}
end

function borrowed_object_ptr()
    ptr = owned_object_ptr()
    @objc [ptr::id{TestManagedNSObject} autorelease]::id{TestManagedNSObject}
end

function retain_with_hook_managed_test(ptr)
    obj = retain(TestManagedNSObject, ptr)
    finalize(obj)
    return nothing
end

@testset "managed wrappers" begin
    @test_throws "unrecognized keyword argument: immutable" macroexpand(
        @__MODULE__, :(@objcwrapper immutable = false TestOldKeyword <: NSObject))
    @test Base.ismutabletype(TestManagedNSObject)
    @test ObjectiveC.is_managed_wrapper(TestManagedNSObject)
    @test !Base.ismutabletype(TestUnmanagedNSObject)
    @test isbitstype(TestUnmanagedNSObject)
    @test !ObjectiveC.is_managed_wrapper(TestUnmanagedNSObject)

    @test ObjectiveC.method_family("newSynchronizedEvent") === :new
    @test ObjectiveC.method_family("newsletter") === nothing
    @test ObjectiveC.method_family("initWithString:") === :init
    @test ObjectiveC.method_family("copyItemAtURL:toURL:error:") === :copy
    @test ObjectiveC.method_family("mutableCopyWithZone:") === :mutableCopy

    @test_throws "owned-family selector `new` cannot return unmanaged wrapper" macroexpand(
        @__MODULE__, :(@objc [NSObject new]::TestUnmanagedNSObject))

    obj = @objc [NSObject new]::TestManagedNSObject
    @test obj isa TestManagedNSObject
    @test obj.retainCount == 1
    finalize(obj)

    obj = @objc [[NSObject alloc]::id{TestManagedNSObject} init]::TestManagedNSObject
    @test obj isa TestManagedNSObject
    @test obj.retainCount == 1
    finalize(obj)

    ptr = owned_object_ptr()
    @test (@objc [ptr::id{TestManagedNSObject} self]::id{TestManagedNSObject}) isa id{TestManagedNSObject}
    raw = TestManagedNSObject(ptr)
    count = raw.retainCount
    obj = @objc [ptr::id{TestManagedNSObject} self]::TestManagedNSObject
    @test obj isa TestManagedNSObject
    @test obj.retainCount == count + 1
    finalize(obj)
    @test raw.retainCount == count
    release(raw)

    str = @objc [NSString stringWithUTF8String:"managed"::Ptr{UInt8}]::TestNSString
    @test str isa TestNSString
    @test str.length == length("managed")

    ptr = owned_object_ptr()
    raw = TestManagedNSObject(ptr)
    count = raw.retainCount
    obj = adopt(TestManagedNSObject, ptr)
    @test obj.retainCount == count
    finalize(obj)

    ptr = owned_object_ptr()
    raw = TestManagedNSObject(ptr)
    try
        @test_throws ArgumentError adopt(TestUnmanagedNSObject, ptr)
        @test_throws ArgumentError retain(TestUnmanagedNSObject, ptr)
    finally
        release(raw)
    end

    ptr = borrowed_object_ptr()
    raw = TestManagedNSObject(ptr)
    count = raw.retainCount
    obj = retain(TestManagedNSObject, ptr)
    @test obj.retainCount == count + 1
    @test obj == raw
    @test hash(obj) == hash(raw)
    finalize(obj)
    @test raw.retainCount == count

    hook_calls = Ref(0)
    old_hook = set_managed_release!(obj -> begin
        hook_calls[] += 1
        release(obj)
    end)
    try
        ptr = borrowed_object_ptr()
        retain_with_hook_managed_test(ptr)
        @test hook_calls[] == 1
    finally
        set_managed_release!(old_hook)
    end
end

@testset "foundation" begin

@testset "managed defaults and opt-outs" begin
    @test ObjectiveC.is_managed_wrapper(NSObject)
    @test Base.ismutabletype(NSObject)

    for T in (NSString, NSNumber, NSValue, NSDecimalNumber, NSArray, NSDictionary, NSURL,
              NSBlock, NSAutoreleasePool)
        @test !ObjectiveC.is_managed_wrapper(T)
        @test !Base.ismutabletype(T)
        @test isbitstype(T)
    end

    for T in (NSError, NSData, NSCopying)
        @test ObjectiveC.is_managed_wrapper(T)
        @test Base.ismutabletype(T)
    end
end

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

@testset "dispatch managed opt-outs" begin
    for T in (dispatch_object, dispatch_queue, dispatch_data)
        @test !ObjectiveC.is_managed_wrapper(T)
        @test !Base.ismutabletype(T)
        @test isbitstype(T)
    end
end

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
    # Drain pending sources after an async post. `run_loop(t;
    # return_after_source_handled=true)` returns after handling *one* source,
    # but each observer fire is its own source, so a single spin can leave
    # additional observers queued.
    drain() = while run_loop(0.1; return_after_source_handled=true) ==
                    CoreFoundation.RunLoopRunHandledSource
              end

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
            synchronous || drain()
            @test foo_calls == 1
            @test foobar_calls == 1

            post_notification!(center, "bar")
            synchronous || drain()
            @test bar_calls == 1
            @test foobar_calls == 2

            # test unsubscribing from a specific notification
            remove_observer!(center, foobar_observer; name="foo")

            post_notification!(center, "foo")
            synchronous || drain()
            @test foo_calls == 2
            @test foobar_calls == 2

            post_notification!(center, "bar")
            synchronous || drain()
            @test bar_calls == 2
            @test foobar_calls == 3

            # test unsubscribing from all notifications
            remove_observer!(center, foobar_observer)

            post_notification!(center, "bar")
            synchronous || drain()
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

@testset "runtime tracing" begin
    ObjectiveC.tracing_unsubscribe()

    events = []
    callback = (class, selector, t0, t1) -> begin
        push!(events, (class, selector, t0, t1))
        return
    end

    @test ObjectiveC.tracing_subscribe(callback) === callback
    try
        String(NSString())
    finally
        ObjectiveC.tracing_unsubscribe()
    end

    @test any(event -> event[1] === :NSString && event[2] === :string, events)
    @test any(event -> event[2] === :UTF8String, events)
    @test all(event -> event[3] <= event[4], events)
    n_events = length(events)
    String(NSString())
    @test length(events) == n_events

    reentrant_events = []
    ObjectiveC.tracing_subscribe((class, selector, t0, t1) -> begin
        push!(reentrant_events, (class, selector))
        String(NSString())
        return
    end)
    try
        NSString()
    finally
        ObjectiveC.tracing_unsubscribe()
    end
    @test length(reentrant_events) == 1
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
