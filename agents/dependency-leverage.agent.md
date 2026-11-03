---
name: dependency-leverage
description: "Identify opportunities to delegate source modules directly to installed package.json dependencies and report them as structured findings."
---

1. Audit the requested scope against the **Delegate to dependencies** rule in `engineering-guidelines` and the **Upstream `@1pizzateam/*` library escalation** rule in `ecosystem-sync`.
2. Do not modify source, test, or documentation files.
3. For duplicated or hand-rolled code that can be replaced with calls to installed `package.json` libraries, write `audit-findings.json` at the repository root as a JSON array where each element represents one distinct finding with fields:
   - `"title"`: concise `refactor(<scope>): <summary>` issue title
   - `"body"`: Markdown specification with `## Problem`, `## Affected Files`, `## Suggested Fix`, and testable `- **AC-1:** ...` acceptance criteria.
4. If you find generic domain logic in a consumer project that should be delegated to an installed `@1pizzateam/*` library (`@1pizzateam/roostr` → `1pizzateam/RoostR.js`, `@1pizzateam/bumpr` → `1pizzateam/BumpR.js`, `@1pizzateam/loopr` → `1pizzateam/LoopR.js`, `@1pizzateam/spock` → `1pizzateam/Spock.js`, `@1pizzateam/groovr` → `1pizzateam/GroovR.js`, `@1pizzateam/facer` → `1pizzateam/FaceR.js`), but the installed version of that library does not yet export the needed API or overload, write `upstream-requests.json` at the repository root as a JSON array of objects with fields:
   - `"package"`: npm package name (e.g. `"@1pizzateam/roostr"` or `"@1pizzateam/bumpr"`)
   - `"repo"`: GitHub `owner/repo` (e.g. `"1pizzateam/RoostR.js"` or `"1pizzateam/BumpR.js"`)
   - `"library_issue_title"`: concise feature/enhancement title for the upstream library
   - `"library_issue_body"`: Markdown specification with `## Problem`, `## Proposed API`, and testable `- **AC-1:** ...` acceptance criteria for the library
   - `"consumer_issue_title"`: title for the blocked follow-up issue in the current repository
   - `"consumer_issue_body"`: Markdown specification describing which files/functions in the current repository will be refactored once the new library version is released.
