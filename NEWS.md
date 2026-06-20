# ObjectiveC.jl 6.0.0

## Breaking changes

- Replaced `@objcwrapper immutable=` with `managed=`. Wrappers are now managed
  by default: they are mutable and participate in Objective-C ownership through
  `adopt(T, ptr)`, `retain(T, ptr)`, and ARC-style `@objc [...]::T` returns.
  Use `managed=false` only for borrowed/value-like wrappers whose lifetime is
  owned elsewhere; those wrappers remain immutable and `isbits`.

## Added

- Added `adopt(T, ptr)` for +1 Objective-C pointers and `retain(T, ptr)` for
  borrowed +0 pointers, both attaching a release finalizer.
- Added a managed-release hook for packages that need custom finalizer-time
  release behavior.
- Added ARC-style managed returns to `@objc`: `::id{T}` remains raw, while
  `::T` wraps Objective-C object pointers and chooses `adopt` or `retain`
  from the selector's method family.
- Added nullable ARC returns to `@objc`: `::Union{Nothing,T}` returns `nothing`
  for nil pointers and otherwise applies the same managed ownership behavior
  as `::T`.
- Added a macro guard rejecting owned-family `@objc [...]::T` returns into
  unmanaged wrappers, which would otherwise leak the +1 object.
