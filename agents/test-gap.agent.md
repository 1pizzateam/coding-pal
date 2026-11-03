---
name: test-gap
description: "Identify untested branches and edge cases in source modules and report them as structured findings."
---

1. Compare exported functions, methods, and branches in the requested scope against existing test files in `tests/`.
2. Do not modify source, test, or documentation files.
3. Write `audit-findings.json` at the repository root as a JSON array where each element represents one distinct test coverage gap with fields:
   - `"title"`: concise `test(<scope>): <summary>` issue title
   - `"body"`: Markdown specification with `## Problem`, `## Affected Files`, `## Suggested Fix`, and testable `- **AC-1:** ...` acceptance criteria.
