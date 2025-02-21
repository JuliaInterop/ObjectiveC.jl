# macros for creating Objective-C blocks from Julia callables.
#
# related links:
#  - LLVM/Clang: https://clang.llvm.org/docs/Block-ABI-Apple.html
#                https://github.com/llvm/llvm-project/blob/33912468a7dbd2cdef3648878ccd6b8f99e0b5bf/compiler-rt/lib/BlocksRuntime/Block_private.h
#  - Rust: https://crates.io/crates/block
#  - Lua: https://github.com/rweichler/objc.lua/blob/cbe2a80462fdcc270c37482f648135de079040e7/src/init.lua#L1996-L2070

using .Foundation


export @objcblock

struct JuliaBlockDescriptor
    reserved::Culong
    size::Culong
    copy_helper::Ptr{Cvoid}
    dispose_helper::Ptr{Cvoid}
end

struct JuliaBlock
    isa::Ptr{Cvoid}
    flags::Cint
    reserved::Cint
    invoke::Ptr{Cvoid}
    descriptor::Ptr{JuliaBlockDescriptor}

    # custom fields
    lambda::Function
end

# NSBlocks are untracked by the Julia GC, so we need to manually root the Julia objects
const julia_block_roots = Dict{NSBlock,JuliaBlock}()
function julia_block_copy(_dst, _src)
    dst_nsblock = NSBlock(reinterpret(id{NSBlock}, _dst))
    src_nsblock = NSBlock(reinterpret(id{NSBlock}, _src))

    @assert haskey(julia_block_roots, src_nsblock)
    julia_block_roots[dst_nsblock] = julia_block_roots[src_nsblock]

    return
end
function julia_block_dispose(_block)
    block = unsafe_load(_block)
    nsblock = NSBlock(reinterpret(id{NSBlock}, _block))

    @assert haskey(julia_block_roots, nsblock)
    delete!(julia_block_roots, nsblock)

    return
end

# JuliaBlock is the concrete version of NSBlock, so make it possible to derive a regular
# Objective-C object by temporarily boxing the structure and copying it to the heap.
function Foundation.NSBlock(block::JuliaBlock)
    block_box = Ref(block)
    nsblock = GC.@preserve block_box begin
        block_ptr = Base.unsafe_convert(Ptr{Cvoid}, block_box)
        nsblock_ptr = reinterpret(id{NSBlock}, block_ptr)

        # root the temporary Julia object so that the copy handler can find it
        src_nsblock = NSBlock(nsblock_ptr)
        julia_block_roots[src_nsblock] = block
        dst_nsblock = NSBlock(copy(src_nsblock))
        delete!(julia_block_roots, src_nsblock)
        dst_nsblock
    end

    # XXX: who is responsible for releasing this block; the user?

    julia_block_roots[nsblock] = block
    return nsblock
end

# descriptor and block creation
const julia_block_descriptor = Ref{JuliaBlockDescriptor}()
const julia_block_descriptor_initialized = Ref{Bool}(false)
function JuliaBlock(trampoline, callable)
    # lazily create a descriptor (these sometimes don't precompile properly)
    if !julia_block_descriptor_initialized[]
        # simple cfunctions, so don't need to be rooted
        copy_cb = @cfunction(julia_block_copy, Nothing, (Ptr{JuliaBlock}, Ptr{JuliaBlock}))
        dispose_cb = @cfunction(julia_block_dispose, Nothing, (Ptr{JuliaBlock},))

        julia_block_descriptor[] = JuliaBlockDescriptor(0, sizeof(JuliaBlock),
                                                        copy_cb, dispose_cb)
        julia_block_descriptor_initialized[] = true
    end

    # set-up the block data structures
    desc_ptr = Base.unsafe_convert(Ptr{Cvoid}, julia_block_descriptor)
    block = JuliaBlock(Foundation.NSConcreteStackBlock(), Foundation.BLOCK_HAS_COPY_DISPOSE,
                       0, trampoline, desc_ptr, callable)

    return block
end

function julia_block_trampoline(_block, args...)
    block = unsafe_load(_block)
    nsblock = NSBlock(reinterpret(id{NSBlock}, _block))

    # call the user lambda
    block.lambda(args...)
end

"""
    @objcblock(callable, rettyp, argtyps...)

Returns an Objective-C block (as an `NSBlock` object) that wraps the provided
Julia callable. This callable should accept argument types `argtyps` and return
a value of type `rettyp`, similar to how `@cfunction` works.

The callback may be a closure, and does not need any special syntax for that case.

!!! warn

    Note that on Julia 1.8 or earlier, the block may only be called from Julia threads.
    If this is a problem, you can use `@objcasyncblock` instead.

Also see: [`@cfunction`](@ref), [`@objcasyncblock`](@ref)
"""
macro objcblock(callable, rettyp, argtyps)
    quote
        # create a trampoline to forward all args to the user-provided callable.
        # this is a simple cfunction, so doesn't need to be rooted.
        trampoline = @cfunction($julia_block_trampoline, $(esc(rettyp)),
                                (Ptr{JuliaBlock}, $(esc(argtyps))...))

        # create an Objective-C block on the stack that wraps the trampoline
        block = JuliaBlock(trampoline, $(esc(callable)))

        # convert it to an untracked NSObject on the heap
        NSBlock(block)
    end
end


export @objcasyncblock

struct JuliaAsyncBlockDescriptor
    reserved::Culong
    size::Culong
    copy_helper::Ptr{Cvoid}
    dispose_helper::Ptr{Cvoid}
end

struct JuliaAsyncBlock
    isa::Ptr{Cvoid}
    flags::Cint
    reserved::Cint
    invoke::Ptr{Cvoid}
    descriptor::Ptr{JuliaAsyncBlockDescriptor}

    # custom fields
    async_send::Ptr{Cvoid}
    cond_handle::Ptr{Cvoid}
end

# async conditions are kept alive by the Julia scheduler, so we don't need to do anything

function Foundation.NSBlock(block::JuliaAsyncBlock)
    block_box = Ref(block)
    nsblock = GC.@preserve block_box begin
        block_ptr = Base.unsafe_convert(Ptr{Cvoid}, block_box)
        nsblock_ptr = reinterpret(id{NSBlock}, block_ptr)
        src_nsblock = NSBlock(nsblock_ptr)
        NSBlock(copy(src_nsblock))
    end
end

function julia_async_block_trampoline(_block)
    block = unsafe_load(_block)
    # note that this requires the JuliaAsyncBlock structure to be immutable without any
    # contained mutable references (i.e. no AsyncCondition), or the load would allocate.

    ccall(block.async_send, Cint, (Ptr{Cvoid},), block.cond_handle)
    return
end

# descriptor and block creation
const julia_async_block_descriptor = Ref{JuliaAsyncBlockDescriptor}()
const julia_async_block_descriptor_initialized = Ref{Bool}(false)
function JuliaAsyncBlock(cond)
    # lazily create a descriptor (these sometimes don't precompile properly)
    if !julia_async_block_descriptor_initialized[]
        # simple cfunctions, so don't need to be rooted
        julia_async_block_descriptor[] = JuliaAsyncBlockDescriptor(0, sizeof(JuliaAsyncBlock),
                                                                    C_NULL, C_NULL)
        julia_async_block_descriptor_initialized[] = true
    end

    # create a trampoline to wake libuv with the user-provided condition
    trampoline = @cfunction(julia_async_block_trampoline, Nothing,
                            (Ptr{JuliaAsyncBlock},))

    # set-up the block data structures
    desc_ptr = Base.unsafe_convert(Ptr{Cvoid}, julia_async_block_descriptor)
    block = JuliaAsyncBlock(Foundation.NSConcreteStackBlock(), 0, 0,
                            trampoline, desc_ptr, cglobal(:uv_async_send), cond.handle)
    # the condition is kept alive by the Julia scheduler, so we don't need to do anything

    return block
end

"""
    @objcasyncblock(cond::AsyncCondition)

Returns an Objective-C block (as an `NSBlock` object) that schedules an async condition
object `cond` for execution on the libuv event loop.

!!! note

    This macro is intended for use on Julia 1.8 and earlier. On Julia 1.9, you can always
    use `@objcblock` instead.

Also see: [`Base.AsyncCondition`](@ref)
"""
macro objcasyncblock(cond)
    quote
        # create an Objective-C block on the stack that calls into libuv
        block = JuliaAsyncBlock($(esc(cond)))

        # convert it to an untracked NSObject on the heap
        NSBlock(block)
    end
end
