---
name: docs-sync
description: "Identify mismatches between documentation pages/README and public exports/signatures in src/ and report them as structured findings."
---

1. Compare public exports, signatures, and behavior in `src/` against existing documentation (`website/docs/`, `docs/`, `README.md`).
2. Do not modify source, test, or documentation files.
3. Write `audit-findings.json` at the repository root as a JSON array where each element represents one distinct documentation mismatch with fields:
   - `"title"`: concise `docs(<scope>): <summary>` issue title
   - `"problem"`: clear explanation of the documentation mismatch
   - `"affectedFiles"`: array of affected documentation and source file paths
   - `"suggestedFix"`: concrete documentation updates needed
   - `"acceptanceCriteria"`: array of testable `AC-<n>` criteria strings (e.g. `["- **AC-1:** ..."]`)
   - `"body"`: multi-line Markdown specification (using `\n\n` between sections and `\n` after every `##` heading) with `## Problem`, `## Affected Files`, `## Suggested Fix`, and `## Acceptance Criteria` (`- **AC-1:** ...`).
