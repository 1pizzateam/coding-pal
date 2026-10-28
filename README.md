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
| **Audit Workflows** (6 + 1 runner) | `.github/workflows/copilot-audit.yml` | Shared runner engine (injects primitives, runs `@github/copilot`, verifies tests/build, opens PR if code changed, and escalates missing upstream `@1pizzateam/*` capabilities via `upstream-requests.json`) |
| | `.github/workflows/dependency-audit.yml` | Reusable Dependency Audit workflow |
| | `.github/workflows/vector-first-audit.yml` | Reusable Vector-First Audit workflow |
| | `.github/workflows/perf-audit.yml` | Reusable Performance & Zero-GC Audit workflow |
| | `.github/workflows/dead-code-audit.yml` | Reusable Dead Code Audit workflow |
| | `.github/workflows/test-gap-audit.yml` | Reusable Test Coverage Gap Audit workflow |
| | `.github/workflows/docs-sync-audit.yml` | Reusable Documentation Sync Audit workflow |
| **Delivery Pipeline** (4 reusable phases) | `.github/workflows/pipeline-think.yml` | FIFO-queued Think phase (validates `think.md`, supports `upstream-request.json` escalation to `@1pizzateam/*` libraries) |
| | `.github/workflows/pipeline-plan.yml` | Plan phase (validates `plan.md` against `think.md`) |
| | `.github/workflows/pipeline-code.yml` | Code phase (step-by-step `code-loop`, deterministic exit gates, opens PR) |
| | `.github/workflows/pipeline-prove.yml` | Prove phase (13 deterministic controls + `gate-fix` loop, auto-merge, auto-release for `@1pizzateam/*` packages, FIFO queue advancement) |

## Cross-Repository Upstream Escalation Loop

1. **Detect & Escalate**: During an audit (`upstream-requests.json`) or the `Think` phase (`specs/issue-<N>/upstream-request.json`), if an agent determines that a general-purpose capability belongs in an upstream `@1pizzateam/*` library (`@1pizzateam/roostr`, `@1pizzateam/bumpr`, `@1pizzateam/loopr`, `@1pizzateam/spock`, `@1pizzateam/groovr`), the workflow pauses the consumer issue (`blocked:upstream`, `upstream-escalated:1`), opens a `ready` issue in the target library repo (`1pizzateam/<Lib>.js`), and advances the consumer FIFO queue.
2. **Library Implementation & Release**: The `ready` label in `1pizzateam/<Lib>.js` triggers `Think -> Plan -> Code -> Prove`, auto-merges the PR, bumps `package.json`, creates a `vX.Y.Z` GitHub Release, and runs `publish-npm.yml`.
3. **Downstream Resume**: After `npm publish`, `publish-npm.yml` sends a `repository_dispatch` (`upstream-library-released`) to downstream consumers (`1pizzateam/DoomR.js`), which waits for npm registry propagation, unblocks the `blocked:upstream` issue, re-adds `ready`, and resumes the consumer's FIFO pipeline.

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
