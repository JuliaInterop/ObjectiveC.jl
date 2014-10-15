module ObjectiveC

using Lazy

include("classes.jl")
include("selectors.jl")
include("objects.jl")
include("syntax.jl")
include("cocoa.jl")

# Import some classes
for c in :[NSObject NSString NSArray].args
  @eval const $c = Class($(Expr(:quote, c)))
end

# @objc [NSString new]

# calltransform(:[NSString foo:"foo" bar:2])

# methods(NSString)

# @objc [[NSWindow alloc] init]

# @objc begin
#   alert = [[NSAlert alloc] init]
#   [alert runModal]
#   [alert release]
# end

end
