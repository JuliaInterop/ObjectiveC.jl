using ObjectiveC
using Test

@test startswith(read(`hostname`, String), hostname())
