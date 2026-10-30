# 1pizzateam/coding-pal

Centralized CI audit instructions, specialist agents, and reusable GitHub Actions audit workflows for 1PizzaTeam repositories.

## How It Works

- **100% CI Runtime Injection**: Consumer projects (`DoomR.js`, `Cadenza`, `MappR`, `PixelGun`, `PolyGun`, `ShaderGun`, `Spock.js`, `BumpR.js`, `LoopR.js`, `RoostR.js`, `GroovR.js`) **do not install** `1pizzateam/coding-pal` locally via `apm.yml`.
- When an audit workflow runs in GitHub Actions, [`copilot-audit.yml`](.github/workflows/copilot-audit.yml) temporarily replaces any local IDE instructions/agents (`.github/`, `.claude/`, `.cursor/`, `.gemini/`, etc.) with `1pizzateam/coding-pal`'s `instructions/` and `agents/`, runs `@github/copilot`, restores the repo's original files, verifies `npm test` & `npm run build`, and opens a Pull Request if code changed.

## Inventory

| Category | Path | Purpose |
|---|---|---|
| **Instructions** (4) | `instructions/engineering-guidelines.instructions.md` | Dynamic `package.json` dependency delegation, braceless single-statement blocks, TypeScript/JS style, `npm test` & `npm run build` verification |
| | `instructions/ecosystem-sync.instructions.md` | Cross-repository upstream `@1pizzateam/*` library escalation (`upstream-requests.json`) and companion game editor synchronization (`editor-requests.json` for `Cadenza`, `MappR`, `PixelGun`, `PolyGun`, `ShaderGun`) |
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
| **Delivery Pipeline** (7 reusable workflows) | `.github/workflows/pipeline-think.yml` | FIFO-queued Think phase (validates `think.md`, supports `upstream-request.json` escalation to `@1pizzateam/*` libraries and `editor-requests.json` synchronization to companion game editors) |
| | `.github/workflows/pipeline-plan.yml` | Plan phase (validates `plan.md` against `think.md`, enforces library documentation scope when public exports change, clones sibling `../DoomR.js` for companion game editors) |
| | `.github/workflows/pipeline-code.yml` | Code phase (step-by-step `code-loop`, deterministic exit gates including `verify-release-readiness.mjs --mode pr`, opens PR) |
| | `.github/workflows/pipeline-prove.yml` | Prove phase (13 deterministic controls + `gate-fix` loop, auto-merge, pre-release readiness verification + auto-release for `@1pizzateam/*` packages, companion game editor issue dispatch, FIFO queue advancement) |
| | `.github/workflows/pipeline-publish-npm.yml` | Reusable npm publish & dry-run workflow for `@1pizzateam/*` libraries (verifies `release-readiness`, publishes with OIDC provenance, and dispatches `upstream-library-released` to consumers with open `blocked:upstream` issues) |
| | `.github/workflows/pipeline-deploy-docs.yml` | Reusable VitePress documentation build and GitHub Pages deployment workflow for `@1pizzateam/*` libraries |
| | `.github/workflows/pipeline-upstream-resume.yml` | Reusable consumer workflow that waits for npm registry propagation, unblocks `blocked:upstream` issues, and resumes the FIFO pipeline |
| **Skills** (1) | `skills/release-readiness/SKILL.md` & `skills/release-readiness/scripts/verify-release-readiness.mjs` | Deterministic pre-release gate for `@1pizzateam/*` libraries verifying `package.json` & lockfile sync, `CHANGELOG.md` top version entry & format, public `src/` export documentation coverage (`website/docs/**` & `README.md`), VitePress sidebar links, docs build, and `npm pack --dry-run --json` tarball contents |

## Cross-Repository Upstream Escalation & Companion Editor Synchronization

### 1. Upstream `@1pizzateam/*` Library Escalation Loop & Pre-Release Controls
1. **Detect & Escalate**: During an audit (`upstream-requests.json`) or the `Think` phase (`specs/issue-<N>/upstream-request.json`), if an agent determines that a general-purpose capability belongs in an upstream `@1pizzateam/*` library (`@1pizzateam/roostr`, `@1pizzateam/bumpr`, `@1pizzateam/loopr`, `@1pizzateam/spock`, `@1pizzateam/groovr`), the workflow pauses the consumer issue (`blocked:upstream`, `upstream-escalated:1`), opens a `ready` issue in the target library repo (`1pizzateam/<Lib>.js`), and advances the consumer FIFO queue.
2. **Library Implementation & Pre-Release Readiness Gate**: The `ready` label in `1pizzateam/<Lib>.js` triggers `Think -> Plan -> Code -> Prove`.
   - During `Think` and `Plan`, public API changes automatically bring `website/docs/**` (or `README.md`) into `## In Scope`.
   - During `Code` and `Prove`, `task-gate` runs `.agents/skills/release-readiness/scripts/verify-release-readiness.mjs --mode pr --require-dist --build-docs` to verify every public runtime export in `src/` is documented, VitePress sidebar links resolve, the docs site builds cleanly, and the `npm pack --dry-run --json` tarball contains the exact expected file list.
   - After `Prove` squash-merges the PR and bumps `package.json` (`npm version`), it syncs `website/package.json` & lockfiles, updates `CHANGELOG.md` (`Version X.Y.Z (Month Day<st|nd|rd|th> Year)`) and any missing docs, and runs `.agents/skills/release-readiness/scripts/verify-release-readiness.mjs --mode release --expected-version <new> --previous-version <old> --require-dist --build-docs` + `npm publish --dry-run` **before** committing, tagging `vX.Y.Z`, and creating the GitHub Release.
   - `publish-npm.yml` and `publish-npm-dry-run.yml` also run `skills/release-readiness/scripts/verify-release-readiness.mjs --mode release --require-dist --build-docs` before publishing to npm.
3. **Downstream Resume**: After `npm publish`, `publish-npm.yml` sends a `repository_dispatch` (`upstream-library-released`) to downstream consumers (`1pizzateam/DoomR.js`), which waits for npm registry propagation, unblocks the `blocked:upstream` issue, re-adds `ready`, and resumes the consumer's FIFO pipeline.

### 2. Companion Game Editor Synchronization (`Cadenza`, `MappR`, `PixelGun`, `PolyGun`, `ShaderGun`)
1. **Detect During `DoomR.js` Think or Audit**: When a `DoomR.js` feature or schema change requires updates to one or more companion game editors (`cadenza` -> `1pizzateam/Cadenza`, `mappr` -> `1pizzateam/MappR`, `pixelgun` -> `1pizzateam/PixelGun`, `polygun` -> `1pizzateam/PolyGun`, `shadergun` -> `1pizzateam/ShaderGun`), the agent emits `editor-requests.json` (`specs/issue-<N>/editor-requests.json` in `Think`, or `editor-requests.json` during an audit).
2. **Dispatch After `DoomR.js` Merge**: Once `Prove` validates and squash-merges the `DoomR.js` PR to `main` (so the updated `DoomR.js` schema/contracts are live on `main`), `Prove` automatically opens `ready` issues (labeled `ready,upstream:doomr`) in each target editor repository.
3. **Autonomous Editor Pipeline with Sibling `../DoomR.js`**: Each editor repository runs the reusable `Think -> Plan -> Code -> Prove` FIFO pipeline (`pipeline-*.yml`), which automatically clones `1pizzateam/DoomR.js` into `../DoomR.js` so cross-repo imports (`../../DoomR.js/src/...`), unit tests (`scripts/test-*.mjs`), and Vite builds succeed end-to-end before auto-merging the editor PR.

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
