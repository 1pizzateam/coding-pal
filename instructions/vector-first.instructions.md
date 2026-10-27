---
description: "Strict Vector-Only spatial signatures, zero runtime type-branching, and target out-parameters."
applyTo: "**"
---

# Vector-First Architecture

- **Vector-only signatures**: Spatial functions, constructors, setters, and options MUST accept vector/spatial primitives (`Vec2`, `Vec3`, `Box`, `Sphere`, `Ray2`, `Ray3`, `Plane`, `Frustum`, `Quat`, `Mat4`, `Mat4x3`, `Mat3`, `Rect`, `Circ`) — never loose scalars (`x, y, z`, `width, height`) or coordinate arrays (`[x, y, z]`).
- **No runtime type-branching**: Never sniff parameter types (`typeof === 'number'`, `Array.isArray()`, `instanceof`).
- **Out-parameters (`target`)**: Getters returning vectors or spatial objects must accept an optional `target` parameter and mutate it in-place.
