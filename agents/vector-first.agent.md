---
name: vector-first
description: "Identify spatial modules that violate the vector-first instruction and report them as structured findings."
---

1. Audit the requested scope against the `vector-first` instruction.
2. Do not modify source, test, or documentation files.
3. Write `audit-findings.json` at the repository root as a JSON array where each element represents one distinct vector-first violation with fields:
   - `"title"`: concise `refactor(<scope>): <summary>` issue title
   - `"body"`: Markdown specification with `## Problem`, `## Affected Files`, `## Suggested Fix`, and testable `- **AC-1:** ...` acceptance criteria.
