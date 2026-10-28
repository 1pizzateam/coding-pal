---
name: dependency-leverage
description: "Refactor source modules to delegate directly to installed package.json dependencies."
---

1. Audit the requested scope against the **Delegate to dependencies** and **Upstream `@1pizzateam/*` library escalation** rules in `engineering-guidelines`.
2. Replace duplicated or hand-rolled code with calls to installed `package.json` libraries and delete superseded local helpers.
3. If you find generic domain logic in a consumer project that should be delegated to an installed `@1pizzateam/*` library (`@1pizzateam/roostr` → `1pizzateam/RoostR.js`, `@1pizzateam/bumpr` → `1pizzateam/BumpR.js`, `@1pizzateam/loopr` → `1pizzateam/LoopR.js`, `@1pizzateam/spock` → `1pizzateam/Spock.js`, `@1pizzateam/groovr` → `1pizzateam/GroovR.js`), but the installed version of that library does not yet export the needed API or overload, write `upstream-requests.json` at the repository root as a JSON array of objects with fields:
   - `"package"`: npm package name (e.g. `"@1pizzateam/roostr"` or `"@1pizzateam/bumpr"`)
   - `"repo"`: GitHub `owner/repo` (e.g. `"1pizzateam/RoostR.js"` or `"1pizzateam/BumpR.js"`)
   - `"library_issue_title"`: concise feature/enhancement title for the upstream library
   - `"library_issue_body"`: Markdown specification with `## Problem`, `## Proposed API`, and testable `- **AC-1:** ...` acceptance criteria for the library
   - `"consumer_issue_title"`: title for the blocked follow-up issue in the current repository
   - `"consumer_issue_body"`: Markdown specification describing which files/functions in the current repository will be refactored once the new library version is released.
