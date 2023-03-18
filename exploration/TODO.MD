Short Term Fluff
===================
- Analyze Foundation
  - types of cursors
  - File
  - Modules

Tedius
=========
- document module.jl in Clang
- static in Julia 

Medium
==============
- modulemap parser
- Module dependecy graph
- List system modules

Finally
============
Generation
- attributes -- NonNull, NS_RELEASE_RETAIN, etc
- Syntax -- Swift, Julia, @objc
- Null Strategy
- Type strategy: inheritance, protocols, null
- Memory management: autorelease pools,  blocks, delegates
- Creating delegates
  - support super
- creating classes
- libuv (autorelease)
- threading
- Package Naming
- Registry
- objc_msgSend
  - message nil
  - correct msgSend for structs, fp, super, etc

Later
=============
- debug why @import works on executable but not libclang (need to debug executable)
