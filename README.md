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

## Adding the Audit UI to a Project

Add a single `.github/workflows/audits.yml` file to the project. In GitHub's **Actions → Copilot Audits → Run workflow** menu, it renders a dropdown (`type: choice`) to pick which audit to run on demand:

```yaml
name: Copilot Audits

on:
  workflow_dispatch:
    inputs:
      audit:
        description: 'Audit to run'
        type: choice
        required: true
        default: dependency-audit
        options:
          - dependency-audit
          - vector-first-audit
          - perf-audit
          - dead-code-audit
          - test-gap-audit
          - docs-sync-audit
      scope:
        description: 'Path to audit (e.g. src/)'
        type: string
        default: 'src/'
      dependency:
        description: 'Dependency filter for Dependency Audit (or "all")'
        type: string
        default: 'all'

permissions:
  contents: write
  pull-requests: write

jobs:
  dependency-audit:
    if: inputs.audit == 'dependency-audit'
    uses: 1pizzateam/coding-pal/.github/workflows/dependency-audit.yml@main
    with:
      scope: ${{ inputs.scope }}
      dependency: ${{ inputs.dependency }}
    secrets: inherit

  vector-first-audit:
    if: inputs.audit == 'vector-first-audit'
    uses: 1pizzateam/coding-pal/.github/workflows/vector-first-audit.yml@main
    with:
      scope: ${{ inputs.scope }}
    secrets: inherit

  perf-audit:
    if: inputs.audit == 'perf-audit'
    uses: 1pizzateam/coding-pal/.github/workflows/perf-audit.yml@main
    with:
      scope: ${{ inputs.scope }}
    secrets: inherit

  dead-code-audit:
    if: inputs.audit == 'dead-code-audit'
    uses: 1pizzateam/coding-pal/.github/workflows/dead-code-audit.yml@main
    with:
      scope: ${{ inputs.scope }}
    secrets: inherit

  test-gap-audit:
    if: inputs.audit == 'test-gap-audit'
    uses: 1pizzateam/coding-pal/.github/workflows/test-gap-audit.yml@main
    with:
      scope: ${{ inputs.scope }}
    secrets: inherit

  docs-sync-audit:
    if: inputs.audit == 'docs-sync-audit'
    uses: 1pizzateam/coding-pal/.github/workflows/docs-sync-audit.yml@main
    with:
      scope: ${{ inputs.scope }}
    secrets: inherit
```
