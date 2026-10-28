---
name: perf-audit
description: "Refactor hot loops and library runtime methods to satisfy the hot-loop-performance instruction."
---

1. Audit per-frame update/render loops and library runtime methods in the requested scope against the `hot-loop-performance` instruction.
2. Refactor all violations in-place.
