##
using ObjectiveC

##  
ObjectiveC.load_framework("Foundation")

##
num_classes = ccall(:objc_getClassList, Cint, (Ptr{Cvoid}, Cint), C_NULL, 0)

##
classes = Array{Ptr{Cvoid}}(undef, num_classes)
num_classes = ccall(:objc_getClassList, Cint, (Ptr{Cvoid}, Cint), classes, num_classes)

##
names = [ccall(:class_getName, Ptr{Cchar}, (Ptr{Cvoid},),c) |> unsafe_string for c in classes] 

##
images = [ccall(:class_getImageName, Ptr{Cchar}, (Ptr{Cvoid},),c) |> unsafe_string for c in classes] 


##lookup test
class = C_NULL
start = time_ns()
for n in names
    class = ccall(:objc_getClass, Ptr{Cvoid}, (Ptr{Cchar},),n)
end
fin = time_ns()

print("Lookup by name: $((fin-start)/1000)us Total, $((fin-start)/num_classes)ns per Class")

##
using BenchmarkTools

##
@benchmark ccall(:objc_getClass, Ptr{Cvoid}, (Ptr{Cchar},),$(names[10]))