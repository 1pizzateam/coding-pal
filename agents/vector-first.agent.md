---
name: vector-first
description: "Identify spatial modules that violate the vector-first instruction and report them as structured findings."
---

1. Audit the requested scope against the `vector-first` instruction.
2. Do not modify source, test, or documentation files.
3. Write `audit-findings.json` at the repository root as a JSON array where each element represents one distinct vector-first violation with fields:
   - `"title"`: concise `refactor(<scope>): <summary>` issue title
   - `"problem"`: clear explanation of the scalar/ad-hoc math violation
   - `"affectedFiles"`: array of affected file paths (e.g. `["src/foo.js"]`)
   - `"suggestedFix"`: concrete refactoring steps using `@1pizzateam/spock` vectors
   - `"acceptanceCriteria"`: array of testable `AC-<n>` criteria strings (e.g. `["- **AC-1:** ..."]`)
   - `"body"`: multi-line Markdown specification (using `\n\n` between sections and `\n` after every `##` heading) with `## Problem`, `## Affected Files`, `## Suggested Fix`, and `## Acceptance Criteria` (`- **AC-1:** ...`).
