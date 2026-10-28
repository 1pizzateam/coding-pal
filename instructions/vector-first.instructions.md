---
description: "Strict Vector-Only spatial signatures and zero runtime type-branching."
applyTo: "**"
---

# Vector-First Architecture

- **Vector-only signatures**: Spatial functions, constructors, setters, and options must accept vector/spatial primitives (`Vec2`, `Vec3`, `Box`, `Sphere`, `Ray2`, `Ray3`, `Plane`, `Frustum`, `Quat`, `Mat4`, `Mat4x3`, `Mat3`, `Rect`, `Circ`). Never accept loose scalar coordinates (`x, y, z`, `width, height`) or coordinate arrays (`[x, y, z]`).
- **No runtime type-branching**: Never sniff parameter types (`typeof === 'number'`, `Array.isArray()`, `instanceof`). Copy or reference vector parameters directly.
