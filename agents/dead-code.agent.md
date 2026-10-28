---
name: dead-code
description: "Remove unused internal exports, dead state properties, and orphaned helpers/assets."
---

1. Scan the requested scope for unused internal exports, orphaned helpers, write-only state fields, unused uniforms/assets, and unreachable branches.
2. Delete the dead code in-place.
