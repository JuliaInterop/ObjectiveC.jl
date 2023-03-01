using ObjectiveC
using Test

using ObjectiveC

# smoke test
let data = "test"
    ptr = @objc [NSString stringWithUTF8String :data::Ptr{UInt8}]::id
    @test ptr isa id
    @test class(ptr) isa Class
    @test "length" in methods(ptr)
    @test 4 == @objc [ptr::id length]::Culong
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

end
