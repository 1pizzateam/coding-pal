---
description: "Dependency delegation, braceless control flow, TypeScript/JS style, and test/build verification."
applyTo: "**"
---

# Engineering Guidelines

- **Delegate to dependencies**: Inspect `package.json` and `node_modules/<pkg>/**/*.d.ts` before coding. Never hand-roll logic already provided by an installed dependency.
- **Braceless single-statement blocks**: Never use `{ }` around single-statement `if`, `else`, `for`, or `while` blocks.
- **TypeScript/JS style**: Prefer `import type` and template literals; avoid `any`.
- **Verification**: Preserve runtime behavior. Run `npm test --if-present` and `npm run build --if-present`, reverting any breaking change.
