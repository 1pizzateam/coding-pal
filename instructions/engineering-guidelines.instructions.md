---
description: "Dependency delegation, braceless control flow, TypeScript/JS style, and test/build verification."
applyTo: "**"
---

# Engineering Guidelines

- **Delegate to dependencies**: Inspect `package.json` and `node_modules/<pkg>/**/*.d.ts` before coding. Never hand-roll logic already provided by an installed dependency.
- **Upstream `@1pizzateam/*` library escalation**: When auditing or designing in a consumer project that depends on `@1pizzateam/*` packages (`@1pizzateam/roostr` → `1pizzateam/RoostR.js`, `@1pizzateam/bumpr` → `1pizzateam/BumpR.js`, `@1pizzateam/loopr` → `1pizzateam/LoopR.js`, `@1pizzateam/spock` → `1pizzateam/Spock.js`, `@1pizzateam/groovr` → `1pizzateam/GroovR.js`), if generic math, physics, loop, audio, or rendering logic belongs in one of those libraries rather than the consumer app—and the installed library does not yet export it—emit `upstream-requests.json` to trigger an upstream library issue and release instead of duplicating library-grade primitives in the app.
- **Braceless single-statement blocks**: Never use `{ }` around single-statement `if`, `else`, `for`, or `while` blocks.
- **TypeScript/JS style**: Prefer `import type` and template literals; avoid `any`.
- **Verification**: Preserve runtime behavior. Run `npm test --if-present` and `npm run build --if-present`, reverting any breaking change.
