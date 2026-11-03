---
name: docs-sync
description: "Identify mismatches between documentation pages/README and public exports/signatures in src/ and report them as structured findings."
---

1. Compare public exports, signatures, and behavior in `src/` against existing documentation (`website/docs/`, `docs/`, `README.md`).
2. Do not modify source, test, or documentation files.
3. Write `audit-findings.json` at the repository root as a JSON array where each element represents one distinct documentation mismatch with fields:
   - `"title"`: concise `docs(<scope>): <summary>` issue title
   - `"body"`: Markdown specification with `## Problem`, `## Affected Files`, `## Suggested Fix`, and testable `- **AC-1:** ...` acceptance criteria.
