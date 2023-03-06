using ObjectiveC
using Test

using ObjectiveC

@testset "@objc" begin
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
end

# smoke test
@objcwrapper TestNSString <: Object
let data = "test"
    ptr = @objc [NSString stringWithUTF8String:data::Ptr{UInt8}]::id{TestNSString}
    @test ptr isa id{TestNSString}
    @test class(ptr) isa Class
    @test "length" in methods(ptr)
    @test 4 == @objc [ptr::id length]::Culong

    obj = TestNSString(ptr)
    @test Base.unsafe_convert(id, obj) == ptr
    @test_throws UndefRefError TestNSString(nil)
end

@testset "foundation" begin

using .Foundation

@testset "NSString" begin
    str = NSString()
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
    @test hostname() == gethostname()
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

@testset "NSNumber" begin
    @testset "bool" begin
        t = NSNumber(true)
        f = NSNumber(false)
        @test t == t
        @test t != f
        @test t.boolValue == true
        @test f.boolValue == false
    end

    @testset "int" begin
        i = NSNumber(123)
        j = NSNumber(456)
        @test i == i
        @test i != j
        @test i.intValue == 123
        @test j.intValue == 456
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
