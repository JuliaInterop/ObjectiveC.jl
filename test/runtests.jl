using ObjectiveC
using Test

using ObjectiveC

# smoke test
str = @objc [NSString new]
@test str isa Object
