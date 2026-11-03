---
name: perf-audit
description: "Identify hot-loop and library runtime method violations of the hot-loop-performance instruction and report them as structured findings."
---

1. Audit per-frame update/render loops and library runtime methods in the requested scope against the `hot-loop-performance` instruction.
2. Do not modify source, test, or documentation files.
3. Write `audit-findings.json` at the repository root as a JSON array where each element represents one distinct performance or Zero-GC finding with fields:
   - `"title"`: concise `perf(<scope>): <summary>` issue title
   - `"body"`: Markdown specification with `## Problem`, `## Affected Files`, `## Suggested Fix`, and testable `- **AC-1:** ...` acceptance criteria.
