---
name: dead-code
description: "Identify unused internal exports, dead state properties, and orphaned helpers/assets and report them as structured findings."
---

1. Scan the requested scope for unused internal exports, orphaned helpers, write-only state fields, unused uniforms/assets, and unreachable branches.
2. Do not modify source, test, or documentation files.
3. Write `audit-findings.json` at the repository root as a JSON array where each element represents one distinct finding with fields:
   - `"title"`: concise `chore(<scope>): <summary>` issue title
   - `"body"`: Markdown specification with `## Problem`, `## Affected Files`, `## Suggested Fix`, and testable `- **AC-1:** ...` acceptance criteria.
