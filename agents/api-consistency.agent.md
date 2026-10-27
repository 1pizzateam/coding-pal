---
name: api-consistency
description: "Align public exports with the api-design instruction and fix documentation drift."
---

1. Refactor public exports in the requested scope (and affected callers/tests) to satisfy the `api-design` instruction.
2. If a documentation folder exists (e.g. `website/docs/`), update signatures and pages to match `src/`.
