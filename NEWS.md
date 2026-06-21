# ObjectiveC.jl 6.0.0

## Breaking changes

- Replaced `@objcwrapper immutable=` with `managed=`. Wrappers are now managed
  by default: they are mutable and participate in Objective-C ownership through
  `adopt(T, ptr)`, `retain(T, ptr)`, and ARC-style `@objc [...]::T` returns.
  Use `managed=false` only for borrowed/value-like wrappers whose lifetime is
  owned elsewhere; those wrappers remain immutable and `isbits`.
- Manual ownership helpers such as `retain`, `release`, `autorelease`, and
  `adopt` are public but no longer exported from `ObjectiveC.Foundation`.
  Qualify them or import them explicitly when writing manual-ownership code.
- `release(obj)` is now ownership-aware for managed wrappers: it eagerly
  releases the wrapper's owned reference at most once, and a later finalizer or
  repeated `release` call is a no-op.

## Added

- Added `adopt(T, ptr)` for +1 Objective-C pointers and `retain(T, ptr)` for
  borrowed +0 pointers, both attaching a release finalizer.
- Added `checked_release` and `unsafe_release` as public extension seams for
  packages that need custom release behavior.
- Added ARC-style managed returns to `@objc`: `::id{T}` remains raw, while
  `::T` wraps Objective-C object pointers and chooses `adopt` or `retain`
  from the selector's method family.
- Added nullable object returns to `@objc`: `::Union{Nothing,T}` returns
  `nothing` for nil pointers. Managed wrapper results apply the same ownership
  behavior as `::T`; unmanaged wrapper results are borrowed wrappers.
- Added a macro guard rejecting owned-family `@objc [...]::T` returns into
  unmanaged wrappers, which would otherwise leak the +1 object.
