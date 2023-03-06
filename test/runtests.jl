using ObjectiveC
using Test

using ObjectiveC

@testset "@objc" begin
    # class methods
    @objc [NSString new]::id
    data = "test"
    @objc [NSString stringWithUTF8String:data::Ptr{UInt8}]::id
    @objc [NSString stringWithUTF8String:"test"::Ptr{UInt8}]::id
    obj = @objc [NSString stringWithUTF8String:"test"::Ptr{UInt8}]::id{NSString}

    # instance methods
    @objc [obj::id length]::UInt
    @objc [obj::id{NSString} length]::UInt
    @test @objc [obj::id{NSString} isEqualTo:obj::id]::Bool
    empty_str = @objc [NSString string]::id{NSString}
    @objc [obj::id stringByReplacingOccurrencesOfString:empty_str::id withString:empty_str::id]::id
end

# smoke test
@objcwrapper TestNSString <: Object
let data = "test"
    ptr = @objc [NSString stringWithUTF8String:data::Ptr{UInt8}]::id
    @test ptr isa id
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
    arr = NSArray([str1, str2])
    @test length(arr) == 2
    @test NSString(arr[1]) == "Hello"
    @test NSString(arr[2]) == "World"
end

@testset "NSDictionary" begin
    str1 = NSString("Hello")
    str2 = NSString("World")
    dict = NSDictionary(Dict(str1 => str2))
    @test length(dict) == 1
    @test keys(dict) == NSArray([str1])
    @test values(dict) == NSArray([str2])
    @test NSString(dict[str1]) == "World"
    @test_throws KeyError dict[str2]
end

@testset "NSError" begin
    err = NSError("NSPOSIXErrorDomain", 1)
    @test isempty(err.userInfo)
    @test contains(err.localizedFailureReason, "Operation not permitted")
end


end
