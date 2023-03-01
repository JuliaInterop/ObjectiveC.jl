using ObjectiveC
using Test

using ObjectiveC

@testset "foundation" begin

using .Foundation

# smoke test
let str = @objc [NSString new]
    @test str isa Object
    release(str)
end

@test "UTF8String" in methods(NSString)

@test hostname() == gethostname()

end
