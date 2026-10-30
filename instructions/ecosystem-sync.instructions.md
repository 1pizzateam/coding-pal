---
description: "Cross-repository upstream @1pizzateam/* library escalation and companion game editor synchronization."
applyTo: "**"
---

# Ecosystem Synchronization

- **Upstream `@1pizzateam/*` library escalation (`upstream-requests.json`)**: When auditing or designing in a consumer project that depends on `@1pizzateam/*` packages (`@1pizzateam/roostr` → `1pizzateam/RoostR.js`, `@1pizzateam/bumpr` → `1pizzateam/BumpR.js`, `@1pizzateam/loopr` → `1pizzateam/LoopR.js`, `@1pizzateam/spock` → `1pizzateam/Spock.js`, `@1pizzateam/groovr` → `1pizzateam/GroovR.js`), if generic math, physics, loop, audio, or rendering logic belongs in one of those libraries rather than the consumer app—and the installed library does not yet export it—emit `upstream-requests.json` (or `specs/issue-<N>/upstream-request.json` in `Think`) to trigger an upstream library issue and release instead of duplicating library-grade primitives in the app.
- **Companion game editor synchronization (`editor-requests.json`)**: When designing, implementing, or auditing a feature in `DoomR.js` that changes data schemas, formats, or capabilities managed by one of the 1PizzaTeam game editors (`cadenza` → `1pizzateam/Cadenza` for songs/SFX/rack instruments, `mappr` → `1pizzateam/MappR` for map tile glyphs/level rules/validator, `pixelgun` → `1pizzateam/PixelGun` for texture atlases/procedural surface stamps/shader modes, `polygun` → `1pizzateam/PolyGun` for 3D models/primitives/animations, `shadergun` → `1pizzateam/ShaderGun` for GLSL shaders/uniforms/layers), emit `editor-requests.json` (or `specs/issue-<N>/editor-requests.json` in `Think`) so the CI pipeline automatically opens a `ready` issue in each affected editor repository to update the editor in lockstep.
