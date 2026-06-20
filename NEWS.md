# ObjectiveC.jl 6.0.0

## Breaking changes

- Replaced `@objcwrapper immutable=` with `managed=`. Use `managed=true` for
  mutable wrappers that participate in explicit Objective-C ownership through
  `adopt(T, ptr)` or `retain(T, ptr)`. The bare `T(ptr)` constructor remains
  non-owning.

## Added

- Added `adopt(T, ptr)` for +1 Objective-C pointers and `retain(T, ptr)` for
  borrowed +0 pointers, both attaching a release finalizer.
- Added a managed-release hook for packages that need custom finalizer-time
  release behavior.
- Added ARC-style managed returns to `@objc`: `::id{T}` remains raw, while
  `::T` wraps Objective-C object pointers and chooses `adopt` or `retain`
  from the selector's method family.
