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

    # id pointers should be allowed to carry type info
    @objc [NSString stringWithUTF8String :data::Ptr{UInt8}]::id{NSString}
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
