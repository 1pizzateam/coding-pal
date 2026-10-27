---
name: perf-audit
description: "Refactor per-frame update and render paths to satisfy the hot-loop-performance instruction."
---

1. Trace the per-frame update, simulation, physics, AI, audio, and render call graph in the requested scope.
2. Refactor all violations of the `hot-loop-performance` instruction in-place.
