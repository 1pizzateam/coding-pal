---
description: "Public library API conventions: naming, fluent chaining, and primitive re-exports."
applyTo: "src/**"
---

# Public API Design

- **Naming**: Use `get*`/`set*` for accessors, `is*`/`has*` for booleans, and `reset()`/`dispose()` for cleanup.
- **Fluent mutators**: Mutating instance methods (`set*`, `add`, `sub`, `scale`, `copy`, `reset`) must `return this` unless a specific return value is required.
- **Unified re-exports**: Re-export upstream primitive types from the main package entry point.
