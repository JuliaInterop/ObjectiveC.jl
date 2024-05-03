# platform ABI information

module ABI

if Sys.ARCH == :aarch64

# arm64 uses objc_msgSend for stret methods
use_stret(typ) = false

elseif Sys.ARCH == :x86_64

# implementation of the psABI standard's parameter classification algorithm [1],
# ignoring Apple's extensions [2], as these don't matter for Julia code.
#
# 1: https://uclibc.org/docs/psABI-x86_64.pdf
# 2: https://developer.apple.com/documentation/xcode/writing-64-bit-intel-code-for-apple-platforms

# this implementation is based on Julia's ABI implementation for 64-bit x86,
# which in turn is based on the implementation from the LLVM D Compiler (LDC).
#
# Copyright (c) 2007-2012 LDC Team.
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
#     * Redistributions of source code must retain the above copyright notice,
#       this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above copyright notice,
#       this list of conditions and the following disclaimer in the documentation
#       and/or other materials provided with the distribution.
#     * Neither the name of the LDC Team nor the names of its contributors may be
#       used to endorse or promote products derived from this software without
#       specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
# ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
# ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

@enum RegisterClass begin
    # integral types that fit into one of the general purpose registers
    Integer

    # types that fit into a vector register
    Sse

    # types that fit into a vector register and can be passed and returned in the upper
    # bytes of it
    SseUp

    # types that will be returned via the x87 FPU
    X87
    X87Up
    ComplexX87

    # types that will be passed and returned in memory via the stack
    Memory
end

mutable struct Classification
    is_memory::Bool
    classes::Vector{Union{Nothing,RegisterClass}}
end

Classification() = Classification(false, [nothing, nothing])

function add_field!(accum::Classification, offset::Base.Integer, cl::RegisterClass)
    accum.is_memory && return

    # Note that we don't need to bother checking if it crosses 8 bytes.
    # We don't get here with unaligned fields, and anything that can be
    # big enough to cross 8 bytes (cdoubles, reals, structs and arrays)
    # is special-cased in classifyType()
    idx = offset < 8 ? 1 : 2

    nw = merge(accum.classes[idx], cl)
    if nw != accum.classes[idx]
        accum.classes[idx] = nw

        if nw == Memory
            accum.classes .= Memory
            accum.is_memory = true
        end
    end
end

function merge(accum, cl)::RegisterClass
    if accum == cl
        accum
    elseif accum == nothing
        cl
    elseif cl == nothing
        accum
    elseif cl == Memory || accum == Memory
        Memory
    elseif cl == Integer && accum == Integer
        Integer
    elseif accum in (X87, X87Up, ComplexX87) || cl in (X87, X87Up, ComplexX87)
        Memory
    else
        Sse
    end
end

function classify!(accum::Classification, dt, offset)
    # floating point types
    # TODO: BFloat16 in Julia 1.11
    # TODO: Float80, if ever added to Julia
    if dt in (Float64, Float32, Float16)
        add_field!(accum, offset, Sse)

    # misc types
    elseif dt <: Ptr
        add_field!(accum, offset, Integer)

    # ghost
    elseif sizeof(dt) == 0
        # do nothing

    # non-float bitstypes are passed as integers
    elseif isprimitivetype(dt)
        if sizeof(dt) <= 8
            add_field!(accum, offset, Integer)
        elseif sizeof(dt) <= 16
            # Int128 or other 128bit-wide integer types
            add_field!(accum, offset, Integer)
            add_field!(accum, offset + 8, Integer)
        else
            add_field!(accum, offset, Memory)
        end
    end

    # TODO: struct types that map to SIMD registers

    # other struct types
    if sizeof(dt) <= 16 && dt.layout != C_NULL
        for (i, ty) in enumerate(fieldtypes(dt))
            if ty <: Ptr
                ty = Ptr{Cvoid}
            elseif !isa(ty, DataType)   # inline union
                add_field!(accum, offset, Memory)
                continue
            end
            classify!(accum, ty, offset + fieldoffset(dt, i))
        end

    else
        add_field!(accum, offset, Memory)
    end

    return
end

function classify(dt)
    cl = Classification()
    classify!(cl, dt, 0)
    return cl
end

use_stret(::Type{T}) where T = classify(T).is_memory

elseif Sys.ARCH == :x86

function use_stret(::Type{T}) where T
    if sizeof(T) == 0
        return false
    elseif T == ComplexF32 || (isprimitivetype(T) && sizeof(T) <= 8)
        return false
    else
        return true
    end
end

else

error("Unsupported architecture $(Sys.ARCH); please file an issue")

end

end
