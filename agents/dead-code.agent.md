---
name: dead-code
description: "Remove cross-module unused exports, dead state properties, and orphaned helpers/assets."
---

1. Scan `src/` and `tests/` for unused exports (excluding `package.json` `main`/`exports` entry points), orphaned helpers, write-only state fields, unused uniforms/assets, and unreachable branches in the requested scope.
2. Delete the dead code in-place.
