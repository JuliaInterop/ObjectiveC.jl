Goal
===============
Systematically explore a range of ObjectiveC & Julia topics so that knowledge can be used to design a
Framework -> Julia package wrapper generator and to add functionsality to the ObjectiveC.jl. 

Rationale
=================
This `exploration` folder exists for the following reasons:
- Every few years I need to revisit Objective-C, I relearn a bunch of details, and then forget.  
- Same for Julia
- I will quasi-document my attempt to sort out a bunch of somewhat orthogonal, but possibly not topics, via notebooks and scripts


Topics to Explore
======================
- ObjectiveC
    - Objective-C runtime reflection support
    - ObjC memory management
    - System frameworks
        - Basic data
            - num of Classes, Selectors, and Protocols
        - Edge cases
    - Performance costs
        - resolving Classes, Selectors, and Protocols
        - check if an NSObject responds to a Selector or conforms to a protocol 
    - ObjC runtime debugging 
        - via ENV vars
        - via `xctrace record` with canned templates
        - via `xctrace record` with custom instruments
- Frameworks
    - Remember details
        - What is an Umbrella Framework again?
        - can a Framework have more than one shared library inside of it?  Yes, I think so
        - Do Frameworks explicitly specify there dependencies to other Frameworks -- maybe not?
- Julia
    - Relearn
        - Type system
        - Metaprogramming
        - GC
        - libuv/tasks internals
        - C FFI details
- Clang Wrapper
    - Check if bundled clang in `Clang.jl` understand ObjectiveC
    - Can we access
        - Memory management annotations e.g. NS_RETURNS_RELEASED
        - API availability annotations
        - Apple Documentation in comments

References
==============
- https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPFrameworks/Concepts/FrameworkAnatomy.html
- https://developer.apple.com/documentation/objectivec/objective-c_runtime?language=objc



