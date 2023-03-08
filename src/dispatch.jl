module Dispatch

using ..ObjectiveC
using ..Foundation

# we deviate from Apple's naming scheme, using `dispatch_object` instead of `dispatch_object`


# Dispatch Objects

export dispatch_object, dispatch_object_t, activate, suspend, resume

@objcwrapper dispatch_object <: NSObject

const dispatch_object_t = id{dispatch_object}

function Foundation.retain(obj::dispatch_object)
    ccall(:dispatch_retain, Cvoid, (dispatch_object_t,), obj)
end

function Foundation.release(obj::dispatch_object)
    ccall(:dispatch_release, Cvoid, (dispatch_object_t,), obj)
end

function activate(obj::dispatch_object)
    ccall(:dispatch_activate, Cvoid, (dispatch_object_t,), obj)
end

function suspend(obj::dispatch_object)
    ccall(:dispatch_suspend, Cvoid, (dispatch_object_t,), obj)
end

function resume(obj::dispatch_object)
    ccall(:dispatch_resume, Cvoid, (dispatch_object_t,), obj)
end


# Dispatch Queue

export dispatch_queue, dispatch_queue_t, main_queue, global_queue

@objcwrapper dispatch_queue <: dispatch_object

const dispatch_queue_t = id{dispatch_queue}

# TODO: dispatch_queue(...) = dispatch_queue_create(...)

main_queue() = dispatch_queue(reinterpret(dispatch_queue_t, cglobal(:_dispatch_main_q)))

function global_queue(identifier, flags)
    queue = ccall(:dispatch_get_global_queue, dispatch_queue_t, ())
    queue == nil && throw(KeyError())
    dispatch_queue(queue)
end


# Dispatch Data

export dispatch_data, dispatch_data_t

@objcwrapper dispatch_data <: dispatch_object

const DISPATCH_DATA_DESTRUCTOR_DEFAULT = C_NULL

const dispatch_data_t = id{dispatch_data}

function dispatch_data(buffer, size;
                       queue=main_queue(),
                       destructor=DISPATCH_DATA_DESTRUCTOR_DEFAULT)
    ccall(:dispatch_data_create, dispatch_data_t,
          (Ptr{Cvoid}, Csize_t, dispatch_queue_t, Ptr{Cvoid}),
          buffer, size, queue, destructor) |> dispatch_data
end

Base.sizeof(data::dispatch_data) =
    ccall(:dispatch_data_get_size, Csize_t, (dispatch_data_t,), data)

end
