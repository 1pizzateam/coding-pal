---
name: test-gap
description: "Identify untested branches and edge cases in source modules and report them as structured findings."
---

1. Compare exported functions, methods, and branches in the requested scope against existing test files in `tests/`.
2. Do not modify source, test, or documentation files.
3. Write `audit-findings.json` at the repository root as a JSON array where each element represents one distinct test coverage gap with fields:
   - `"title"`: concise `test(<scope>): <summary>` issue title
   - `"priority"`: GitHub issue priority (`"Urgent"`, `"High"`, `"Medium"`, or `"Low"`)
   - `"problem"`: clear explanation of the untested branches, methods, or edge cases
   - `"affectedFiles"`: array of affected source and test file paths
   - `"suggestedFix"`: concrete unit tests to add
   - `"acceptanceCriteria"`: array of testable `AC-<n>` criteria strings (e.g. `["- **AC-1:** ..."]`)
   - `"body"`: multi-line Markdown specification (using `\n\n` between sections and `\n` after every `##` heading) with `## Problem`, `## Affected Files`, `## Suggested Fix`, and `## Acceptance Criteria` (`- **AC-1:** ...`).
