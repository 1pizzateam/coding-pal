---
name: dead-code
description: "Identify unused internal exports, dead state properties, and orphaned helpers/assets and report them as structured findings."
---

1. Scan the requested scope for unused internal exports, orphaned helpers, write-only state fields, unused uniforms/assets, and unreachable branches.
2. Do not modify source, test, or documentation files.
3. Write `audit-findings.json` at the repository root as a JSON array where each element represents one distinct finding with fields:
   - `"title"`: concise `chore(<scope>): <summary>` issue title
   - `"problem"`: clear explanation of the unused export, dead state property, or orphaned helper/asset
   - `"affectedFiles"`: array of affected file paths (e.g. `["src/foo.js"]`)
   - `"suggestedFix"`: concrete remediation steps
   - `"acceptanceCriteria"`: array of testable `AC-<n>` criteria strings (e.g. `["- **AC-1:** ..."]`)
   - `"body"`: multi-line Markdown specification (using `\n\n` between sections and `\n` after every `##` heading) with `## Problem`, `## Affected Files`, `## Suggested Fix`, and `## Acceptance Criteria` (`- **AC-1:** ...`).
