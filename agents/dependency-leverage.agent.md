---
name: dependency-leverage
description: "Identify opportunities to delegate source modules directly to installed package.json dependencies and report them as structured findings."
---

1. Audit the requested scope against the **Delegate to dependencies** rule in `engineering-guidelines` and the **Upstream `@1pizzateam/*` library escalation** rule in `ecosystem-sync`.
2. Do not modify source, test, or documentation files.
3. For duplicated or hand-rolled code that can be replaced with calls to installed `package.json` libraries, write `audit-findings.json` at the repository root as a JSON array where each element represents one distinct finding with fields:
   - `"title"`: concise `refactor(<scope>): <summary>` issue title
   - `"priority"`: GitHub issue priority (`"Urgent"`, `"High"`, `"Medium"`, or `"Low"`)
   - `"model"`: recommended Copilot model for remediation (`"claude-sonnet-5.5"`, `"claude-opus-5.5"`, `"claude-haiku-5.5"`, `"gpt-6.1-sol"`, `"gpt-5.3-codex"`, `"gemini-4-argon"`, `"gemini-3.8-flash"`, or `"auto"`) based on finding complexity
   - `"effort"`: recommended thinking effort (`"Low"`, `"Medium"`, `"High"`, or `"Max"`) based on reasoning depth required
   - `"problem"`: clear explanation of the duplicated or hand-rolled logic
   - `"affectedFiles"`: array of affected file paths (e.g. `["src/foo.js"]`)
   - `"suggestedFix"`: concrete refactoring steps using the installed dependency
   - `"acceptanceCriteria"`: array of testable `AC-<n>` criteria strings (e.g. `["- **AC-1:** ..."]`)
   - `"body"`: multi-line Markdown specification (using `\n\n` between sections and `\n` after every `##` heading) with `## Problem`, `## Affected Files`, `## Suggested Fix`, and `## Acceptance Criteria` (`- **AC-1:** ...`).
4. If you find generic domain logic in a consumer project that should be delegated to an installed `@1pizzateam/*` library (`@1pizzateam/roostr` → `1pizzateam/RoostR.js`, `@1pizzateam/bumpr` → `1pizzateam/BumpR.js`, `@1pizzateam/loopr` → `1pizzateam/LoopR.js`, `@1pizzateam/spock` → `1pizzateam/Spock.js`, `@1pizzateam/groovr` → `1pizzateam/GroovR.js`, `@1pizzateam/facer` → `1pizzateam/FaceR.js`), but the installed version of that library does not yet export the needed API or overload, write `upstream-requests.json` at the repository root as a JSON array of objects with fields:
   - `"package"`: npm package name (e.g. `"@1pizzateam/roostr"` or `"@1pizzateam/bumpr"`)
   - `"repo"`: GitHub `owner/repo` (e.g. `"1pizzateam/RoostR.js"` or `"1pizzateam/BumpR.js"`)
   - `"priority"`: GitHub issue priority (`"Urgent"`, `"High"`, `"Medium"`, or `"Low"`)
   - `"model"`: recommended Copilot model (`"claude-sonnet-5.5"`, `"claude-opus-5.5"`, `"claude-haiku-5.5"`, `"gpt-6.1-sol"`, `"gpt-5.3-codex"`, `"gemini-4-argon"`, `"gemini-3.8-flash"`, or `"auto"`)
   - `"effort"`: recommended thinking effort (`"Low"`, `"Medium"`, `"High"`, or `"Max"`)
   - `"library_issue_title"`: concise feature/enhancement title for the upstream library
   - `"library_issue_body"`: multi-line Markdown specification (using `\n\n` between sections and `\n` after every `##` heading) with `## Problem`, `## Proposed API`, and `## Acceptance Criteria` (`- **AC-1:** ...`) for the library
   - `"consumer_issue_title"`: title for the blocked follow-up issue in the current repository
   - `"consumer_issue_body"`: multi-line Markdown specification (using `\n\n` between sections and `\n` after every `##` heading) with `## Problem`, `## Affected Files`, `## Suggested Fix`, and `## Acceptance Criteria` describing which files/functions in the current repository will be refactored once the new library version is released.
