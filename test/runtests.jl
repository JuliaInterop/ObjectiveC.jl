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

@test hostname() == gethostname()

end
