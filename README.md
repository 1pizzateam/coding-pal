# 1pizzateam/coding-pal

Centralized CI audit instructions, specialist agents, and reusable GitHub Actions audit workflows for 1PizzaTeam repositories.

## How It Works

- **100% CI Runtime Injection**: Consumer projects (`DoomR.js`, `Spock.js`, `BumpR.js`, `LoopR.js`, `RoostR.js`, etc.) **do not install** `1pizzateam/coding-pal` locally via `apm.yml`.
- When an audit workflow runs in GitHub Actions, [`copilot-audit.yml`](.github/workflows/copilot-audit.yml) temporarily replaces any local IDE instructions/agents (`.github/`, `.claude/`, `.cursor/`, `.gemini/`, etc.) with `1pizzateam/coding-pal`'s `instructions/` and `agents/`, runs `@github/copilot`, restores the repo's original files, verifies `npm test` & `npm run build`, and opens a Pull Request if code changed.

## Inventory

| Category | Path | Purpose |
|---|---|---|
| **Instructions** (3) | `instructions/engineering-guidelines.instructions.md` | Dynamic `package.json` dependency delegation, braceless single-statement blocks, TypeScript/JS style, `npm test` & `npm run build` verification |
| | `instructions/vector-first.instructions.md` | Vector-only spatial signatures and zero runtime type-branching |
| | `instructions/hot-loop-performance.instructions.md` | Zero hot-path allocations, hoisted scratch instances/TypedArrays, and state caching across app loops and library runtime methods |
| **Agents** (6) | `agents/dependency-leverage.agent.md` | Replaces duplicated/hand-rolled code with calls to installed `package.json` libraries |
| | `agents/vector-first.agent.md` | Refactors spatial modules to enforce `vector-first` signatures |
| | `agents/perf-audit.agent.md` | Eliminates hot-path allocations in app loops and library runtime methods |
| | `agents/dead-code.agent.md` | Removes unused internal exports, orphaned helpers, and dead state fields |
| | `agents/test-gap.agent.md` | Adds unit tests in `tests/` for untested branches and edge cases |
| | `agents/docs-sync.agent.md` | Syncs documentation (`website/docs/`, `docs/`, `README.md`) with `src/` signatures and exports |
| **Workflows** (6 + 1 runner) | `.github/workflows/copilot-audit.yml` | Shared runner engine (injects primitives, runs `@github/copilot`, verifies tests/build, opens PR if code changed) |
| | `.github/workflows/dependency-audit.yml` | Reusable Dependency Audit workflow |
| | `.github/workflows/vector-first-audit.yml` | Reusable Vector-First Audit workflow |
| | `.github/workflows/perf-audit.yml` | Reusable Performance & Zero-GC Audit workflow |
| | `.github/workflows/dead-code-audit.yml` | Reusable Dead Code Audit workflow |
| | `.github/workflows/test-gap-audit.yml` | Reusable Test Coverage Gap Audit workflow |
| | `.github/workflows/docs-sync-audit.yml` | Reusable Documentation Sync Audit workflow |

## Calling an Audit Workflow in a Project

Add a trigger file in the project's `.github/workflows/`:

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
