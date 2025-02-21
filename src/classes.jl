# the @class functionality has been removed, due to bitrot. if you are interested in
# resurrecting it, please look at the repository at commit 22118319da.

function allocclass(name, super)
    ptr = ccall(:objc_allocateClassPair, Ptr{Cvoid}, (Ptr{Cvoid}, Ptr{Cchar}, Csize_t),
                super, name, 0)
    ptr == C_NULL && error("Couldn't allocate class $name")
    return Class(ptr)
end

function register(class::Class)
    ccall(:objc_registerClassPair, Cvoid, (Ptr{Cvoid},),
            class)
    return class
end

createclass(name, super) = allocclass(name, super) |> register

getmethod(class::Class, sel::Selector) =
    ccall(:class_getInstanceMethod, Ptr{Cvoid}, (Ptr{Cvoid}, Ptr{Cvoid}),
            class, sel)

methodtypeenc(method::Ptr) =
    ccall(:method_getTypeEncoding, Ptr{Cchar}, (Ptr{Cvoid},),
            method) |> unsafe_string

methodtypeenc(class::Class, sel::Selector) = methodtypeenc(getmethod(class, sel))

methodtype(args...) = methodtypeenc(args...) |> parseencoding

replacemethod(class::Class, sel::Selector, imp::Ptr{Cvoid}, types::String) =
    ccall(:class_replaceMethod, Bool, (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cchar}),
            class, sel, imp, types)

function setmethod(class::Class, sel::Selector, imp::Ptr{Cvoid}, types::String)
    meth = getmethod(class, sel)
    meth ≠ C_NULL && methodtype(meth) != parseencoding(types) &&
        error("New method $(name(sel)) of $class must match $(methodtype(meth))")
    replacemethod(class, sel, imp, types)
end
