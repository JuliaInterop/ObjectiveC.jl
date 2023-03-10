Framework Wrapper
=====================
- Generates Julia package for a Framework
- Syntax: Swift-like and not particularly "Julian"
    - e.g. `[obj doSomethingWith: bar assuming: foo]` -> `obj.doSomethingWith(bar, assuming=foo)`
    - Idiomatic Julian wrappers can be provided by downstream packages
- Naming: 
    - e.g. Foundation.framework -> FoundationFramework.jl
- Versioning?
    - starts at 1.0
    - Major version: syntax specific (e.g. maybe be start with Swift-like in V1, and change later on)    
    - Minor version: MacOS compatability
    - e.g. v1.13 is syntax version 1.0 for macOS 13
    - maybe this is too complicated...
- Resolve Selectors and Classes at load time e.g. in `__init__`

ObjectiveC.jl New Features
==========================
- Bring back @class syntax, with support for Protocols and Categories

Demo
==========================
- Non-trivial ui demo
