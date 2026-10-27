# 1pizzateam/coding-pal

Centralized AI instructions, specialist agents, and reusable GitHub Actions audit workflows for 1PizzaTeam repositories.

Consumer repositories **do not need to install or commit any primitives** — [`copilot-audit.yml`](.github/workflows/copilot-audit.yml) automatically injects `instructions/` and `agents/` at runtime and cleans them up before opening a Pull Request.

## Inventory

| Category | Path | Purpose |
|---|---|---|
| **Instructions** (4) | `instructions/engineering-guidelines.instructions.md` | Dynamic `package.json` dependency delegation, braceless single-statement blocks, TypeScript/JS style, `npm test` & `npm run build` verification |
| | `instructions/vector-first.instructions.md` | Vector-only spatial signatures, no runtime type-branching, `target` out-parameters |
| | `instructions/hot-loop-performance.instructions.md` | Zero hot-loop allocations, hoisted scratch instances/TypedArrays, WebGL state caching |
| | `instructions/api-design.instructions.md` | Naming (`get*`/`set*`/`is*`/`has*`/`reset()`/`dispose()`), fluent `return this` mutators, unified primitive re-exports |
| **Agents** (6) | `agents/dependency-leverage.agent.md` | Replaces duplicated/hand-rolled code with calls to installed `package.json` libraries |
| | `agents/vector-first.agent.md` | Refactors spatial modules to enforce `vector-first` signatures |
| | `agents/perf-audit.agent.md` | Eliminates per-frame GC allocations in hot update/render loops |
| | `agents/dead-code.agent.md` | Removes unused internal exports, orphaned helpers, and dead state fields |
| | `agents/test-gap.agent.md` | Adds unit tests in `tests/` for untested branches and edge cases |
| | `agents/api-consistency.agent.md` | Aligns public API signatures and documentation with `api-design` |
| **Workflows** (6 + 1 runner) | `.github/workflows/copilot-audit.yml` | Shared runner engine (injects primitives, runs `@github/copilot`, verifies tests/build, opens PR if code changed) |
| | `.github/workflows/dependency-audit.yml` | Reusable Dependency Audit workflow |
| | `.github/workflows/vector-first-audit.yml` | Reusable Vector-First Audit workflow |
| | `.github/workflows/perf-audit.yml` | Reusable Performance & Zero-GC Audit workflow |
| | `.github/workflows/dead-code-audit.yml` | Reusable Dead Code Audit workflow |
| | `.github/workflows/test-gap-audit.yml` | Reusable Test Coverage Gap Audit workflow |
| | `.github/workflows/api-consistency-audit.yml` | Reusable API Consistency & Docs Audit workflow |

## Usage in Any Project (`DoomR.js`, `Spock.js`, etc.)

Add thin trigger files in the project's `.github/workflows/` (no primitives or `apm.yml` needed in the project):

```yaml
name: Vector-First Audit

on:
  schedule: [{ cron: '0 7 * * 1' }]
  workflow_dispatch:
    inputs:
      scope: { default: 'src/', type: string }

permissions:
  contents: write
  pull-requests: write

jobs:
  audit:
    uses: 1pizzateam/coding-pal/.github/workflows/vector-first-audit.yml@main
    with:
      scope: ${{ inputs.scope || 'src/' }}
    secrets: inherit
```
