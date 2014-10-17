for c in :[NSObject
           NSString
           NSArray
           NSHost].args
  @eval $(Expr(:export, c))
  @eval const $c = Class($(Expr(:quote, c)))
end

toobject(s::String) = @objc [[NSString alloc] initWithUTF8String:s]

hostname() =
  @objc [[[NSHost currentHost] localizedName] UTF8String] |> bytestring
