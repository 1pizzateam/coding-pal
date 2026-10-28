---
description: "Zero-GC hot-path rules and runtime/render efficiency for apps and libraries."
applyTo: "**"
---

# Hot-Loop Performance

- **Zero hot-path allocations**: Never allocate `{}` literals, `[]` arrays, `[...]` spreads, closures, or `new` instances, or call allocating methods (`.map`, `.filter`, `.slice`, `Object.keys`) inside per-frame loops or library runtime methods (math, collision, physics, AI, audio, rendering).
- **Hoist & reuse**: Pre-allocate module/class scratch instances and typed arrays, mutate in-place, cache loop invariants, and use index `for` loops.
- **State caching**: Skip redundant state switches, uniform uploads, and buffer re-binds when values are unchanged.
