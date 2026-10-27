---
description: "Zero-GC hot-loop rules and render-pass efficiency."
applyTo: "**"
---

# Hot-Loop Performance

- **Zero hot-loop allocations**: Never allocate `{}` literals, `[]` arrays, `[...]` spreads, closures, or `new` instances, or call allocating methods (`.map`, `.filter`, `.slice`, `Object.keys`) inside per-frame update, physics, AI, audio, or render paths.
- **Hoist & reuse**: Pre-allocate module/class scratch instances and typed arrays, mutate in-place, cache loop invariants, and use index `for` loops.
- **State caching**: Skip redundant WebGL state switches, uniform uploads, and buffer re-binds when values are unchanged.
