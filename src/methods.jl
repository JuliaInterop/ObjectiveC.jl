method(class::Class, sel::Selector) =
  ccall(:class_getInstanceMethod, Ptr{Void}, (Ptr{Void}, Ptr{Void}),
        class, sel)

method(obj::Object, sel::Selector) =
  method(class(obj), sel)

types(m::Ptr) =
  ccall(:method_getTypeEncoding, Ptr{Cchar}, (Ptr{Void},), m) |> bytestring

implementation(m::Ptr) =
  ccall(:method_getImplementation, Ptr{Void}, (Ptr{Void},),
        m)

# From https://developer.apple.com/library/mac/documentation/Cocoa/Conceptual/ObjCRuntimeGuide/Articles/ocrtTypeEncodings.html
typeencodings = Dict('c' => Cchar,
                     'i' => Cint,
                     's' => Cshort,
                     'l' => Clong,
                     'q' => Clonglong,
                     'C' => Cuchar,
                     'I' => Cuint,
                     'S' => Cushort,
                     'L' => Culong,
                     'Q' => Culonglong,
                     'f' => Cfloat,
                     'd' => Cdouble,
                     'B' => Bool,
                     'v' => Void,
                     '*' => Ptr{Cchar},
                     '@' => Object,
                     '#' => Class,
                     ':' => Selector,
                     '^' => Ptr)

# Other modifiers
# r const
# n in
# N inout
# o out
# O bycopy
# R byref
# V oneway
# Numbers a stack size + offset, now obsolete
const skip = Set(['r',
                  '0', '1', '2', '3', '4', '5', '6', '7', '8', '9'])

function nexttype(io::IO)
  c = read(io, Char)
  c in skip && return
  haskey(typeencodings, c) || error("Can't parse type encoding: $(takebuf_string(io))")
  t = typeencodings[c]
  t == Ptr && (t = Ptr{nexttype(io)})
  return t
end

function parseencoding(io::IO)
  types = []
  while !eof(io)
    t = nexttype(io)
    t == nothing || push!(types, t)
  end
  return types
end

parseencoding(s::String) = parseencoding(IOBuffer(s))

signature(m::Ptr) = m |> types |> parseencoding

function signature(class::Class, sel::Selector)
  m = method(class, sel)
  m == C_NULL && error("$class doesn't respond to $sel")
  signature(m)
end

signature(obj::Object, sel::Selector) =
  signature(class(obj), sel)
