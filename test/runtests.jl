using ObjectiveC
using Test

using ObjectiveC

# basic @objc test
let data = "test"
    ptr = @objc [NSString stringWithUTF8String :data::Ptr{UInt8}]::id
    @test ptr isa id
    @test class(ptr) isa Class
    @test "length" in methods(ptr)
    @test 4 == @objc [ptr::id length]::Culong
end

# test re-wrapping of Objective-C objects (which are passed by-reference)
struct TestNSString <: Object
    canary::Int
    ptr::id
    TestNSString(ptr::id) = new(42, ptr)
end
let str = @objc [NSString string]::TestNSString
    @assert str isa TestNSString
    @assert str.canary == 42
end

@testset "foundation" begin

using .Foundation

@testset "NSString" begin
    str = NSString()
    @test length(str) == 0

    str = NSString("test")
    @test length(str) == 4
end

@testset "NSHost" begin
    @test hostname() == gethostname()
end

@testset "NSBundle" begin
    load_framework("IOKit")
    @test_throws ErrorException load_framework("NonExistingFramework")
end

end
