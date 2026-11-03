---
name: perf-audit
description: "Identify hot-loop and library runtime method violations of the hot-loop-performance instruction and report them as structured findings."
---

1. Audit per-frame update/render loops and library runtime methods in the requested scope against the `hot-loop-performance` instruction.
2. Do not modify source, test, or documentation files.
3. Write `audit-findings.json` at the repository root as a JSON array where each element represents one distinct performance or Zero-GC finding with fields:
   - `"title"`: concise `perf(<scope>): <summary>` issue title
   - `"problem"`: clear explanation of the hot-loop or Zero-GC violation
   - `"affectedFiles"`: array of affected file paths (e.g. `["src/foo.js"]`)
   - `"suggestedFix"`: concrete remediation steps
   - `"acceptanceCriteria"`: array of testable `AC-<n>` criteria strings (e.g. `["- **AC-1:** ..."]`)
   - `"body"`: multi-line Markdown specification (using `\n\n` between sections and `\n` after every `##` heading) with `## Problem`, `## Affected Files`, `## Suggested Fix`, and `## Acceptance Criteria` (`- **AC-1:** ...`).
