# 1pizzateam/coding-pal

Centralized CI audit instructions, specialist agents, and reusable GitHub Actions audit workflows for 1PizzaTeam repositories.

## How It Works

- **100% CI Runtime Injection**: Consumer projects (`DoomR.js`, `Cadenza`, `MappR`, `PixelGun`, `PolyGun`, `ShaderGun`, `Spock.js`, `BumpR.js`, `LoopR.js`, `RoostR.js`, `GroovR.js`) **do not install** `1pizzateam/coding-pal` locally via `apm.yml`.
- When an audit workflow runs in GitHub Actions, [`audit-runner.yml`](.github/workflows/audit-runner.yml) temporarily replaces any local IDE instructions/agents (`.github/`, `.claude/`, `.cursor/`, `.gemini/`, etc.) with `1pizzateam/coding-pal`'s `instructions/` and `agents/`, runs `@github/copilot`, restores the repo's original files, verifies `npm test` & `npm run build`, and opens a Pull Request if code changed.

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
| **Audit Workflows** (6 + 1 runner) | `.github/workflows/audit-runner.yml` | Shared runner engine (injects primitives, runs `@github/copilot`, verifies tests/build, opens PR if code changed, and escalates missing upstream `@1pizzateam/*` capabilities via `upstream-requests.json`) |
| | `.github/workflows/audit-dependency.yml` | Reusable Audit - Dependencies workflow |
| | `.github/workflows/audit-vector-first.yml` | Reusable Audit - Vector-first workflow |
| | `.github/workflows/audit-perf.yml` | Reusable Audit - Performance & Zero-GC workflow |
| | `.github/workflows/audit-dead-code.yml` | Reusable Audit - Dead code workflow |
| | `.github/workflows/audit-test-gap.yml` | Reusable Audit - Test coverage gaps workflow |
| | `.github/workflows/audit-docs-sync.yml` | Reusable Audit - Documentation sync workflow |
| **Delivery Pipeline** (7 reusable workflows) | `.github/workflows/pipeline-think.yml` | FIFO-queued Think phase with Smart Resume and manual validation checkpoints (`1-think` / `pause:think`), `upstream-request.json` escalation to `@1pizzateam/*` libraries, and `editor-requests.json` synchronization to companion game editors |
| | `.github/workflows/pipeline-plan.yml` | Plan phase with manual validation checkpoints (`2-plan` / `pause:plan`), validates `plan.md` against `think.md`, enforces library documentation scope when public exports change, and clones sibling `../DoomR.js` for companion game editors |
| | `.github/workflows/pipeline-code.yml` | Code phase (step-by-step `code-loop`, deterministic exit gates including `verify-release-readiness.mjs --mode pr`, opens PR; supports `workflow_dispatch` resume from an approved `# Plan:` issue comment) |
| | `.github/workflows/pipeline-prove.yml` | Prove phase (13 deterministic controls + `gate-fix` loop, auto-merge, pre-release readiness verification + auto-release for `@1pizzateam/*` packages, companion game editor issue dispatch, FIFO queue advancement) |
| | `.github/workflows/pipeline-publish-npm.yml` | Reusable npm publish & dry-run workflow for `@1pizzateam/*` libraries (verifies `release-readiness`, publishes with OIDC provenance, and dispatches `upstream-library-released` to consumers with open `blocked:upstream` issues) |
| | `.github/workflows/pipeline-deploy-docs.yml` | Reusable VitePress documentation build and GitHub Pages deployment workflow for `@1pizzateam/*` libraries |
| | `.github/workflows/pipeline-upstream-resume.yml` | Reusable consumer workflow that waits for npm registry propagation, unblocks `blocked:upstream` issues, and resumes the FIFO pipeline |
| **Skills** (1) | `skills/release-readiness/SKILL.md` & `skills/release-readiness/scripts/verify-release-readiness.mjs` | Deterministic pre-release gate for `@1pizzateam/*` libraries verifying `package.json` & lockfile sync, `CHANGELOG.md` top version entry & format, public `src/` export documentation coverage (`website/docs/**` & `README.md`), VitePress sidebar links, docs build, and `npm pack --dry-run --json` tarball contents |

## Pipeline Walkthrough

The main delivery flow is **Think -> Plan -> Code -> Prove**. The issue's trigger label chooses where it pauses; Project Status shows the current phase rather than starting it.

**When statuses change:** each workflow sets its phase status near the start of its own run, before running the agent.

| Workflow | Status at phase start | Status after successful completion |
|---|---|---|
| Think | **Think** | Stays **Think** until Plan starts |
| Plan | **Plan** | Stays **Plan** until Code starts |
| Code | **Code** | Stays **Code** until Prove starts, including when paused for human review with `review:code` |
| Prove | **Release** | Changes to **Done** after merge and any configured release preparation |

Unlike the other phases, **Prove explicitly marks final completion**. **Release** means the ticket has entered validation/merge/release preparation, not that it has passed. A failed Prove run can leave it in **Release** with `needs:developer`; check the workflow result and labels rather than treating a phase status as proof that a run is still active. **Done** does not certify completion of the separate npm publishing workflow.

### Pipeline - Think

[`Pipeline - Think`](.github/workflows/pipeline-think.yml) turns an issue into a validated specification:

1. Checks the FIFO queue and existing specification comments or PR to decide whether to wait, start Think, or resume a later phase.
2. Sets the ticket's Project Status to **Think** when a new Think phase starts.
3. Runs the Think agent to define the problem, scope, constraints, and acceptance criteria.
4. Validates the Think contract and posts the specification as a `# Think:` issue comment.
5. If an upstream library change is required, opens an upstream `4-release` issue and pauses this issue with `blocked:upstream`.
6. Otherwise, pauses with `review:think` when requested by `1-think` or a Think pause directive; if not paused, uploads the specification for Plan.

**Stopping point:** the Think specification for manual review, an upstream dependency gate, or handoff to Plan. A failed Think run marks the issue `needs:developer` and advances the queue.

### Pipeline - Plan

[`Pipeline - Plan`](.github/workflows/pipeline-plan.yml) converts the specification into an implementation plan:

1. Restores the Think specification from the preceding artifact or the issue's existing comment.
2. Sets the ticket's Project Status to **Plan** before generating the plan.
3. Runs the Plan agent to define implementation steps, affected files, tests, and documentation scope.
4. Validates the plan and cross-checks it against the Think specification.
5. Posts the plan as a `# Plan:` issue comment.
6. Pauses with `review:plan` when requested by `2-plan` or a Plan pause directive; otherwise, uploads the specifications for Code.

**Stopping point:** the implementation plan for manual review, or handoff to Code. A failed Plan run marks the issue `needs:developer` and advances the queue.

### Pipeline - Code

[`Pipeline - Code`](.github/workflows/pipeline-code.yml) implements the plan and opens a PR:

1. Restores the Think and Plan specifications and determines the base branch.
2. Sets the ticket's Project Status to **Code** before implementation starts.
3. Prepares the implementation branch and runs the Code agent to implement the plan and prepare the PR record.
4. Runs deterministic exit gates, including the applicable tests, build, scope checks, and library release-readiness checks.
5. Pushes the branch and creates or updates the PR.
6. When requested by `3-code` or a Code pause directive, keeps the status at **Code**, adds `review:code`, and withholds the artifact that would start Prove. Otherwise, uploads the specifications and PR number for Prove.

**Stopping point:** an open PR awaiting human review, or handoff to Prove. Code does not merge the PR. A failed Code run marks the issue `needs:developer` and advances the queue.

### Pipeline - Prove

[`Pipeline - Prove`](.github/workflows/pipeline-prove.yml) validates an existing PR before merging it:

1. Sets the ticket's Project Status to **Release** before validation starts; this does not mean the PR has passed Prove.
2. Runs checks covering specs, scope, secrets, dependencies, tests, builds, acceptance criteria, and PR metadata.
3. Runs the Prove agent to independently assess the implementation and write a validation record. Automated validation is supported at every risk tier: High/Critical require rollback verification evidence, and Critical also requires a staged rollout reference. Missing evidence blocks merge; automation never fabricates human sign-off.
4. If checks fail, runs automatic fixes and retries, up to the configured limit, **5 by default**.
5. If everything passes, approves and **squash-merges the PR**, deleting its branch.

After merging, Prove dispatches any companion editor updates. For eligible `@1pizzateam/*` libraries with automatic release enabled, it bumps the version, updates release documentation, runs release-readiness checks and an npm dry run, then pushes the version commit/tag and creates a GitHub Release. It finally sets **Done** and advances the queue.

**Stopping point:** successful merge and any configured GitHub Release preparation, or a failure requiring developer attention. There is **no human approval pause before auto-merge**. If the fix limit is reached, the PR remains open and the issue/PR are flagged `needs:developer`. A failure after merging does not undo the merge.

The `4-release` label continues through Prove automatically; on an issue with an existing PR, it resumes directly at Prove. Manually dispatching Prove also permits auto-merge and does not require the label. DoomR disables automatic npm release, so its successful Prove path ends after merge and completion bookkeeping. Actual npm publication for libraries is a separate workflow; **Done does not guarantee npm publishing has finished**.

### Release - Publish npm

[`Release - Publish npm`](.github/workflows/pipeline-publish-npm.yml) publishes a prepared library version:

1. Checks the release tag belongs to the default branch and matches the package version, or verifies a manual publish uses the default branch.
2. Installs dependencies, builds the library, and runs its tests.
3. Verifies release documentation, package metadata, and the distributable tarball.
4. Selects the npm dist-tag and runs `npm publish --dry-run`.
5. Unless dry-run mode is enabled, publishes to npm with provenance and attempts to notify downstream repositories with blocked issues.

**Stopping point:** a verified dry run, a published npm package, or the first failing validation/publish step. This workflow does not implement or merge a PR.

### Deploy - Documentation

[`Deploy - Documentation`](.github/workflows/pipeline-deploy-docs.yml) builds and deploys library documentation:

1. Installs dependencies and builds the library.
2. Installs the website dependencies and builds the VitePress site.
3. Uploads the generated site as a Pages artifact.
4. Deploys that artifact to GitHub Pages, subject to any configured environment approvals.

**Stopping point:** a deployed documentation site, a required environment approval, or a failed build/deployment. This is separate from PR validation and npm publishing.

### Pipeline - Resume upstream

[`Pipeline - Resume upstream`](.github/workflows/pipeline-upstream-resume.yml) restarts consumer work after an upstream release notification:

1. Reads the released package/version and polls npm for propagation for `@1pizzateam/*` packages.
2. Finds open `blocked:upstream` issues referencing that package or upstream repository.
3. Posts upgrade instructions, removes `blocked:upstream`, and applies `4-release`.
4. If the pipeline is idle, dispatches Think for the first unblocked issue; otherwise, leaves the issues for queue processing.

**Stopping point:** issues unblocked and queued/dispatched, or no matching blocked issues. The propagation polling is currently best-effort: exhausting its retries does not prevent unblocking.

## Manual Validation Checkpoints & Smart Resume (`Think` & `Plan`)

Add one of the following labels to an open issue to choose how far the pipeline runs. Create the labels in each repository first so they appear in the issue's Labels picker.

### 1. Triggering via Labels
- **`1-think`**: Runs Think, posts the `# Think: ...` spec as an issue comment, swaps the label for `review:think`, and pauses for review without starting Plan.
- **`2-plan`**: Runs Think -> Plan (or reuses the existing `# Think:` comment), posts `# Plan: ...`, swaps the label for `review:plan`, and pauses before Code.
- **`3-code`**: Runs Think -> Plan -> Code (reusing existing specs when available), opens a PR, and pauses with `review:code` before Prove or auto-merge.
- **`4-release`**: Runs Think -> Plan -> Code -> Prove autonomously. Prove merges the PR; `@1pizzateam/*` libraries then run their automated release and npm publish steps.

The old `ready`, `ready:think`, `ready:plan`, and `ready:code` labels are no longer pipeline triggers.

The unprefixed labels `think`, `plan`, `code`, and `release` are also no longer triggers. Create or rename the repository labels to the numbered names above; the prefixes keep them in pipeline order in GitHub's label picker. Project Status options remain unprefixed.

### Project board Status
Project Status tracks pipeline progress; it does not trigger workflows. CI moves the issue through **Think**, **Plan**, **Code**, and **Release** as those phases begin. A PR paused for human review stays in **Code**, with the `review:code` label indicating the pause (for example, when triggered with `3-code`). No separate review status is required. **Done** is set after Prove completes and any configured GitHub Release preparation finishes; separate npm publishing may still be running. Add these options to each board's `Status` field. The `COPILOT_GITHUB_TOKEN` secret must have permission to read and update the project.

### 2. Triggering via Issue Body Checkboxes / Directives
You can also use issue-body checkboxes or directives with a pipeline label to request a manual pause:
```markdown
- [x] Pause after Think
- [ ] Pause after Plan
```
*(or inline `[pause:think]`, `[pause:plan]`, or `[pause:code]`)*

### 3. Reviewing, Editing & Smart Resume
When a workflow pauses at `review:think`, `review:plan`, or `review:code`:
1. **Review / Edit**: You can edit the `# Think: ...` or `# Plan: ...` comment directly on the GitHub issue to refine scope, invariants, or implementation steps (remember to uncheck `- [x] Pause after ...` in the issue body if you used a checkbox).
2. **Resume**:
   - From `review:think`:
     - Add **`2-plan`** to run Plan and pause for review, **`3-code`** to continue through Code and stop at the PR, or **`4-release`** to finish autonomously.
   - From `review:plan`:
     - Add **`3-code`** to continue through Code and stop at the PR, or **`4-release`** to run Prove and merge automatically.
   - From `review:code`, add **`4-release`** to run Prove and auto-merge.
   - Need to regenerate a phase from scratch? Delete the corresponding `# Think:` or `# Plan:` comment, then re-add its trigger label.

## Cross-Repository Upstream Escalation & Companion Editor Synchronization

### 1. Upstream `@1pizzateam/*` Library Escalation Loop & Pre-Release Controls
1. **Detect & Escalate**: During an audit (`upstream-requests.json`) or the `Think` phase (`specs/issue-<N>/upstream-request.json`), if an agent determines that a general-purpose capability belongs in an upstream `@1pizzateam/*` library (`@1pizzateam/roostr`, `@1pizzateam/bumpr`, `@1pizzateam/loopr`, `@1pizzateam/spock`, `@1pizzateam/groovr`), the workflow pauses the consumer issue (`blocked:upstream`, `upstream-escalated:1`), opens a `4-release` issue in the target library repo (`1pizzateam/<Lib>.js`), and advances the consumer FIFO queue.
2. **Library Implementation & Pre-Release Readiness Gate**: The `4-release` label in `1pizzateam/<Lib>.js` triggers `Think -> Plan -> Code -> Prove`.
   - During `Think` and `Plan`, public API changes automatically bring `website/docs/**` (or `README.md`) into `## In Scope`.
   - During `Code` and `Prove`, `task-gate` runs `.agents/skills/release-readiness/scripts/verify-release-readiness.mjs --mode pr --require-dist --build-docs` to verify every public runtime export in `src/` is documented, VitePress sidebar links resolve, the docs site builds cleanly, and the `npm pack --dry-run --json` tarball contains the exact expected file list.
   - After `Prove` squash-merges the PR and bumps `package.json` (`npm version`), it syncs `website/package.json` & lockfiles, updates `CHANGELOG.md` (`Version X.Y.Z (Month Day<st|nd|rd|th> Year)`) and any missing docs, and runs `.agents/skills/release-readiness/scripts/verify-release-readiness.mjs --mode release --expected-version <new> --previous-version <old> --require-dist --build-docs` + `npm publish --dry-run` **before** committing, tagging `vX.Y.Z`, and creating the GitHub Release.
   - `publish-npm.yml` and `publish-npm-dry-run.yml` also run `skills/release-readiness/scripts/verify-release-readiness.mjs --mode release --require-dist --build-docs` before publishing to npm.
3. **Downstream Resume**: After `npm publish`, `publish-npm.yml` sends a `repository_dispatch` (`upstream-library-released`) to downstream consumers (`1pizzateam/DoomR.js`), which waits for npm registry propagation, unblocks the `blocked:upstream` issue, re-adds `4-release`, and resumes the consumer's FIFO pipeline.

### 2. Companion Game Editor Synchronization (`Cadenza`, `MappR`, `PixelGun`, `PolyGun`, `ShaderGun`)
1. **Detect During `DoomR.js` Think or Audit**: When a `DoomR.js` feature or schema change requires updates to one or more companion game editors (`cadenza` -> `1pizzateam/Cadenza`, `mappr` -> `1pizzateam/MappR`, `pixelgun` -> `1pizzateam/PixelGun`, `polygun` -> `1pizzateam/PolyGun`, `shadergun` -> `1pizzateam/ShaderGun`), the agent emits `editor-requests.json` (`specs/issue-<N>/editor-requests.json` in `Think`, or `editor-requests.json` during an audit).
2. **Dispatch After `DoomR.js` Merge**: Once `Prove` validates and squash-merges the `DoomR.js` PR to `main` (so the updated `DoomR.js` schema/contracts are live on `main`), `Prove` automatically opens `4-release` issues (labeled `4-release,upstream:doomr`) in each target editor repository.
3. **Autonomous Editor Pipeline with Sibling `../DoomR.js`**: Each editor repository runs the reusable `Think -> Plan -> Code -> Prove` FIFO pipeline (`pipeline-*.yml`), which automatically clones `1pizzateam/DoomR.js` into `../DoomR.js` so cross-repo imports (`../../DoomR.js/src/...`), unit tests (`scripts/test-*.mjs`), and Vite builds succeed end-to-end before auto-merging the editor PR.

## Testing the Pipeline Workflows

From this repository, run the focused regression suite with Ruby (including Minitest), Bash, and `jq` installed:

```sh
ruby tests/workflows_test.rb
```
No GitHub token, Docker, or Copilot installation is required.

Successful output ends with `0 failures, 0 errors, 0 skips`. A failing test exits with a nonzero status and prints the test name and assertion or command output to investigate.

The tests execute the actual shell scripts extracted from the workflow YAML for checkpoints, Smart Resume, FIFO selection/advancement, and Project Status updates. A strict mock `gh` records writes and returns fixture data; its `--jq` filters run through real `jq`. Each test uses a temporary directory, fake credentials, a cleared environment, and a restricted executable path. No real GitHub, Copilot, Git, merge, or publishing commands run. Unexpected GitHub operations fail the test, even when a workflow script suppresses the command's failure.

To also validate the trigger gates, Project titles, and Think-to-Plan workflow listeners in all 11 adjacent project checkouts:

```sh
PROJECT_WORKFLOWS_ROOT=.. ruby tests/workflows_test.rb
```

This expects all 11 project repositories beside this checkout. Without `PROJECT_WORKFLOWS_ROOT`, only the shared-workflow tests run. Set it to another parent directory if your project checkouts are elsewhere.

To run a single test, pass its method name:

```sh
ruby tests/workflows_test.rb --name test_existing_pr_is_proven_only_for_release
```

For detailed test names and timings, add `--verbose`:

```sh
ruby tests/workflows_test.rb --verbose
```

If a prerequisite is missing, verify it with `ruby --version`, `bash --version`, and `jq --version`. A `cannot load such file -- minitest/autorun` error means Minitest must be installed for the Ruby interpreter you are using.

For static Actions validation, install [actionlint](https://github.com/rhysd/actionlint), then run:

```sh
actionlint -shellcheck= \
  .github/workflows/pipeline-think.yml \
  .github/workflows/pipeline-plan.yml \
  .github/workflows/pipeline-code.yml \
  .github/workflows/pipeline-prove.yml \
  .github/workflows/test-workflows.yml
```

The suite checks Bash syntax separately; ShellCheck is disabled here because the existing pipeline scripts have not been made ShellCheck-clean. [CI - Workflow tests](.github/workflows/test-workflows.yml) runs actionlint and the shared-workflow tests on pushes and pull requests that change workflows or tests, with read-only permissions and no production secrets.

These are focused regression tests, not a local GitHub simulator. Artifact pause gates and Done ordering are checked structurally; the tests do not run the agents, merge/release scripts, or GitHub's expression engine. Real event delivery, artifact transfer, permissions, and release/publishing behavior still require a disposable GitHub integration environment.