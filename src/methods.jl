export signature

method(class::Class, sel::Selector) =
    ccall(:class_getInstanceMethod, Ptr{Cvoid}, (Ptr{Cvoid}, Ptr{Cvoid}),
       class, sel)

method(obj::Object, sel::Selector) =
    method(class(obj), sel)

types(m::Ptr) =
    ccall(:method_getTypeEncoding, Ptr{Cchar}, (Ptr{Cvoid},), m) |> unsafe_string

implementation(m::Ptr) =
    ccall(:method_getImplementation, Ptr{Cvoid}, (Ptr{Cvoid},),
            m)

# From https://developer.apple.com/library/mac/documentation/Cocoa/Conceptual/ObjCRuntimeGuide/Articles/ocrtTypeEncodings.html
const typeencodings = Dict('c' => Cchar,
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
                           'v' => Cvoid,
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
const skip = Set(['r', 'V',
                  '0', '1', '2', '3', '4', '5', '6', '7', '8', '9'])

function nexttype(io::IO)
    c = read(io, Char)
    c in skip && return
    haskey(typeencodings, c) || error("Unsupported method type: $(String(take!(io)))")
    t = typeencodings[c]
    t == Ptr && (t = Ptr{nexttype(io)})
    return t
end

function parseencoding(io::IO)
    types = DataType[]
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

# Creating Methods

const revtypeencodings = Dict(v => k for (k, v) in typeencodings)

function encodetype(ts...)
    buf = IOBuffer()
    for t in ts
        (t <: Ptr) && (print(buf, "^"); t = eltype(t))
        haskey(revtypeencodings, t) || error("$t isn't a valid ObjectiveC type")
        print(buf, revtypeencodings[t])
    end
    return String(take!(buf))
end
