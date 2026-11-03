# 1pizzateam/coding-pal

Shared agents, instructions, and GitHub Actions workflows for 1PizzaTeam.

The delivery pipeline turns an issue into a merged PR:

**Think -> Plan -> Code -> Prove**

Audits scan repositories for findings and create one GitHub Issue per finding on the repository's GitHub Project V2 board. Separate workflows publish npm packages and deploy documentation.

## Setup

1. Add the two organization Actions secrets below.
2. Grant both secrets to each application repository that runs the pipeline.
3. Use `secrets: inherit` in jobs that call the shared workflows. Existing application callers already do this.
4. Create the [trigger labels](#start-pause-and-resume) and [Project Status options](#project-status).
5. Add a trigger label to an open issue.

Applications do not install this repository through `apm.yml`. Workflows load the required agents and instructions at runtime.

## Model selection

Each workflow step pins an explicit Copilot CLI `--model` flag:

| Workflow / Step | Model |
|---|---|
| `pipeline-think.yml` (Thinker agent) | `claude-sonnet-5.5` |
| `pipeline-plan.yml` (Planner agent) | `claude-sonnet-5.5` |
| `pipeline-code.yml` (Code agent) | `claude-sonnet-5.5` |
| `pipeline-prove.yml` (Prove repair + Prove reviewer) | `claude-sonnet-5.5` |
| `pipeline-prove.yml` (Auto-release `@1pizzateam/*` library version) | `gpt-6-luna` |
| `audit-runner.yml` (All 6 audit workflows) | `gemini-3.8-flash` |

## Pipeline authentication

Create two fine-grained personal access tokens. Do not paste them into issues, source files, or chat.

### 1. Copilot token

Open [New fine-grained token](https://github.com/settings/personal-access-tokens/new):

- **Name:** `1pizzateam-copilot`
- **Resource owner:** your personal account with Copilot access
- **Account permissions:** **Copilot Requests**
- **Expiration:** choose a renewal date

Copilot Requests is under **Account**, not **Repositories**. Classic PATs are not supported by Copilot CLI.

### 2. GitHub automation token

Create another fine-grained token:

- **Name:** `1pizzateam-pipeline`
- **Resource owner:** `1pizzateam`
- **Repository access:** select the applications, libraries, and editors the pipeline must read or update
- **Repository permissions:** **Actions**, **Contents**, **Issues**, and **Pull requests** — read/write
- **Organization permissions:** **Projects** — read/write
- **Expiration:** choose a renewal date

The account creating the token must have the corresponding repository and Project access. Organization approval may be required.

Add **Workflows: write** if the pipeline will change workflow files. Private repositories in another organization need separate credentials.

### 3. Store the tokens

Open [1pizzateam Actions secrets](https://github.com/organizations/1pizzateam/settings/secrets/actions) and create:

| Secret name | Value | Used for |
|---|---|---|
| `COPILOT_GITHUB_TOKEN` | Copilot token | Running Copilot CLI |
| `PIPELINE_GITHUB_TOKEN` | GitHub automation token | GitHub API calls, pushes, workflow dispatches, and Project updates |

For each secret, grant access to the **application repositories**. Storing a secret only in `coding-pal` does not make it available to callers. `secrets: inherit` passes the caller's available secrets to the shared workflow.

Think, Plan, Code, Prove, and audits need both secrets. Upstream resume needs only `PIPELINE_GITHUB_TOKEN`. npm dry runs need neither; actual publishing needs the pipeline token for downstream notifications. npm uses trusted publishing, not either token.

**Required reviews still apply.** GitHub cannot approve a PR using the account that created it. Prove posts a comment if approval fails, but that does not satisfy a required independent review. Use a separate reviewer identity when branch protection requires one.

## Start, pause, and resume

### Choose where to stop

Create these labels in each application repository. Add one to an open issue:

| Label | Triggers workflow | Runs through | Stops at |
|---|---|---|---|
| `1-think` | `think.yml` | Think | Specification comment |
| `2-plan` | `plan.yml` | Plan (falls back to Think if `# Think:` is missing) | Plan comment |
| `3-code` | `code.yml` | Code (falls back to Think/Plan if specs are missing) | Open or updated PR |
| `4-prove` | `code.yml` | Prove (resumes from existing specs/PR or falls back to Think/Plan/Code) | Approved PR and `# Prove:` validation comment (before merge) |
| `5-release` | `code.yml` | Think -> Plan -> Code -> Prove -> Release (resumes from existing specs/PR) | Merge, configured publication/deployment, then Done |

Each stage label (`1-think`, `2-plan`, `3-code`, `4-prove`, `5-release`) triggers only the entry workflow needed (`think.yml`, `plan.yml`, or `code.yml`) without launching duplicate intermediate runs. Use **`4-prove`** to validate and approve the PR without merging, or **`5-release`** for the full autonomous pipeline through merge and release; when an open PR already exists, both `4-prove` and `5-release` resume directly at Prove.

Only the numbered labels trigger delivery. The old `ready*` labels, `4-release`, and unprefixed `think`, `plan`, `code`, `prove`, and `release` labels do not.

**Think and Plan run in parallel across issues.** They do not wait for another issue's implementation or review.

**Code onward is serialized per repository.** Code holds one delivery slot through its dependent Prove job, merge, and completion of required publication/deployment. A standalone Prove request joins the same queue. Other repositories have their own queues.

After obtaining the slot, Code fetches the latest default branch and creates the issue branch from that revision, not the older workflow checkout. This includes earlier deliveries that have merged. Code checks whether the parallel Think/Plan still applies; invalid assumptions require replanning, not an expanded implementation scope.

GitHub queues up to **100 pending deliveries** with `queue: max`, without replacing earlier pending runs. FIFO follows entry into the concurrency queue, not issue creation or label time. GitHub does not guarantee dispatch-time ordering; requests beyond the limit are canceled and must be resubmitted.

A Code or Prove review pause releases the slot. Adding `4-prove` or `5-release` later queues Prove as a new delivery request. Failures also release the slot and leave the issue flagged for attention. Publication/deployment run as separate workflows without acquiring the delivery slot; the delivery run waits for their results before releasing its slot.

Before validation, Prove merges the latest base into the PR branch and pushes clean updates. Merge conflicts stop with a PR comment and `needs:developer`; resolve them within the approved plan, or revise Think/Plan before retrying. All controls and the independent assessment run on the refreshed branch, including checks for interactions with intervening changes.

If the base or PR head changes during validation, Prove blocks merge and requires a rerun. The merge request is pinned to the validated head commit. Enable branch protection requiring an up-to-date branch (or a merge queue) to cover the final race with merges outside this pipeline.

Think explicitly starts Plan, and Plan starts Code, only after uploading a handoff artifact. Prove is a dependent job inside the Code workflow run, not a separately dispatched run. Queued or paused preparation creates no downstream workflow; a Code review pause skips the Prove job.

Before deploying this change, stop or finish active delivery runs. Deploy the shared workflow changes and all application callers before resuming issues. Do not mix the old dispatch/completion chain with the new dependent Prove job: it can duplicate Prove or leave a handoff unprocessed.

### Request an extra pause

Use a trigger label and add a checked box to the issue body (or add a `pause:think`, `pause:plan`, `pause:code`, or `pause:prove` label while a run is in flight):

```markdown
- [x] Pause after Think
- [ ] Pause after Plan
- [ ] Pause after Code
- [ ] Pause after Prove
```

Inline `[pause:think]`, `[pause:plan]`, `[pause:code]`, and `[pause:prove]` directives also work.

### Review, comment, and resume or re-run

1. Review (or edit in place) the `# Think:` or `# Plan:` issue comment, or post follow-up comments directly on the issue (or open PR).
2. Clear any pause checkbox or directive for the phase you want to pass.
3. Add the label for the stage you want to run next:
   - **`1-think`**: Re-runs **Think**, incorporating all non-bot developer comments on the issue and revising the previous `# Think:` specification.
   - **`2-plan`**: Runs (or re-runs) **Plan**, incorporating the latest `# Think:`, any previous `# Plan:`, and all developer comments on the issue.
   - **`3-code`**: Runs (or re-runs) **Code** from the latest default branch using the latest `# Think:`, `# Plan:`, and developer comments on the issue/PR, opening a new PR or force-updating the existing open PR in place.
   - **`4-prove`**: Continues from the furthest completed artifact (`# Think:`, `# Plan:`, or open PR) through **Prove** (8 deterministic gates, up to 5 auto-remediation fix loops, independent `# Prove:` review, and PR approval) and pauses before merging.
   - **`5-release`**: Continues from the furthest completed artifact (`# Think:`, `# Plan:`, or open PR) through **Prove**, merge, and release.

Temporary specification and progress files (`specs/issue-<N>/`) exist only on the runner during the job and are excluded from Git commits and PR diffs via `.git/info/exclude`; the `# Think:` and `# Plan:` issue comments remain the single source of truth.

## Project Status

**Labels start work. Status reports the phase entered, not whether it passed or is still running.**

Add these options to the Project's `Status` field:

| Workflow | Status when it starts | After success |
|---|---|---|
| Think | **Think** | Stays Think until Plan starts |
| Plan | **Plan** | Stays Plan until Code starts |
| Code | **Code** | Enters Prove when opening the PR; returns to Code for a requested review pause |
| Prove | **Prove** | Returns to Code for fixes, or enters Release after checks and independent review pass |
| Release (inside the Prove workflow) | **Release** | Changes to **Done** only after required publication/deployment succeeds |

**Prove** means validation/review, not release. Failed checks or review move the issue back to **Code** for repairs, then **Prove** to verify again. After five unsuccessful repair attempts, it stays in Code with `needs:developer`. **Release** starts only after successful validation/review; it merges the PR and prepares any configured release. A later failure can leave it in Release.

**Done means required release workflows succeeded.** DoomR waits for Pages. Libraries wait for npm publication when an automatic GitHub Release was created, plus applicable documentation deployment. Repositories without configured publication/deployment finish after merge.

**Optional `AI Cost` field:** If the GitHub Project V2 board includes a custom field named **`AI Cost`** (`Number` or `Text`), each stage (`Think`, `Plan`, `Code`, `Prove`, `Release`, and `Done`) automatically syncs the issue's cumulative AI cost in USD alongside `Status`. Each pipeline comment (`# Think:`, `# Plan:`, `Pull request opened for #...`, `# Prove repair request`, `# Prove:`, and `# Release:`) also appends a per-step and cumulative AI cost footer (`<!-- ai-cost-step:{...} -->`), and `# Release report` includes an `## AI Cost Summary` table across all steps.

In the GitHub Project's **Workflows** settings, disable any built-in automation that sets Status to Done when an issue is closed or a PR is merged. Merge can close the issue before publication finishes; only this pipeline should set Done for delivery.

## Pipeline Walkthrough

### Pipeline - Think

[`Pipeline - Think`](.github/workflows/pipeline-think.yml) defines the change:

1. Checks existing specs and PRs to start Think or resume a later phase.
2. Sets Project Status to **Think**.
3. Runs the Think agent to define the problem, scope, constraints, and acceptance criteria.
4. Validates the spec and posts it as a `# Think:` issue comment.
5. If an upstream library must change first, opens a `5-release` issue there and marks this issue `blocked:upstream`.
6. Otherwise, pauses if requested or passes the spec to Plan.

**Stops at:** review, an upstream dependency, or handoff to Plan.

### Pipeline - Plan

[`Pipeline - Plan`](.github/workflows/pipeline-plan.yml) defines how to implement the change:

1. Restores the Think spec from an artifact or issue comment.
2. Sets Project Status to **Plan**.
3. Runs the Plan agent to define steps, files, tests, and documentation changes.
4. Validates the plan against Think and posts a `# Plan:` issue comment.
5. Pauses if requested or passes both specs to Code.

**Stops at:** review or handoff to Code.

### Pipeline - Code

[`Pipeline - Code`](.github/workflows/pipeline-code.yml) implements the plan:

1. Restores both specs and prepares the implementation branch.
2. Sets Project Status to **Code**.
3. Runs the Code agent to implement the plan, verify tests/builds, and prepare the PR record (`pr.md`).
4. Enters **Prove**, pushes the branch, and creates or updates the PR (deterministic exit gates run once in Prove rather than being duplicated in Code).
5. If requested, returns to Code for manual PR review; otherwise, passes the specs and PR number to Prove.

**Stops at:** an open PR for review or handoff to Prove. Code does not merge.

Failed Think, Plan, or Code runs mark the issue `needs:developer`. They do not restart other issues.

### Pipeline - Prove

[`Pipeline - Prove`](.github/workflows/pipeline-prove.yml) validates and merges the PR:

1. Sets Project Status to **Prove**.
2. Runs the 8 deterministic controls (`control-guard`, `secret-guard`, `dependency-guard`, `scope-guard`, `task-gate`, `criteria-verify`, `test-probe`, `preview-smoke`) and waits once for GitHub PR checks (up to 20 minutes, excluding the current delivery run).
3. Only when checks pass, runs the Prove agent for independent code review and a validation record.
4. On failed checks or review, returns to **Code**. The Code agent receives the exact check output, review findings, commit/base, and validated Think/Plan specs. It fixes within scope, then returns to Prove and reruns checks and review, **up to 5 repair attempts by default**.
5. If everything passes, approves the PR and posts `# Prove:`. If `4-prove`, `pause:prove`, or a Prove pause directive is set, pauses here before merging; otherwise enters **Release**, **squash-merges the PR**, and deletes its branch.
6. Dispatches companion editor updates. For eligible libraries with automatic release enabled, prepares the version and creates a GitHub Release.
7. Waits for the existing publication/deployment runs for the exact delivered commit, then sets **Done**. Finishing the delivery run releases the slot for the next queued request.

High/Critical changes require rollback verification evidence. Critical also requires a staged rollout reference. Missing evidence blocks merge; automation does not fabricate human sign-off.

Every failed Prove attempt posts a new **Prove repair request** comment on both the issue and PR, preserving its check output, review findings (when review ran), and commit reference for later analysis. Earlier comments are not overwritten. The workflow's `prove-spec` artifact also contains the latest repair report and validation log, subject to GitHub Actions artifact retention.

Release completion does not launch duplicate workflows. It observes `publish-npm.yml` runs triggered by the GitHub Release and the push-triggered deployment configured by each application's Code and Prove callers (`deployment_workflow`). Documentation callers also pass `deployment_paths`, matching their push filters, so changes which cannot trigger a deployment do not wait for one. The gate tracks the release commit when that push matches, otherwise the merge commit if its push matched. DoomR's Pages workflow runs on every main push.

Each required workflow has a 30-minute completion timeout, including time queued or awaiting environment approval. A failed, cancelled, skipped, missing, or timed-out run prevents Done, leaves the issue in **Release**, and adds `needs:developer`. A **Release report** is posted on the issue and PR with run links and outcomes and included in `prove-spec`. Release failures before the wait step also post the delivery-run link. Fix/retry the failed release workflow and verify its result before manually moving the issue to Done; retrying publication alone does not automatically rerun the completion gate.

**Stops at:** a requested Prove review pause (`4-prove` / `pause:prove`), successful merge and required publication/deployment completion, or a failure needing attention. At the fix limit, the PR stays open and the issue/PR get `needs:developer`. A failure after merge does not undo it.

Manual Prove dispatch also permits auto-merge without a `5-release` label (unless `4-prove` or `pause:prove` is set on the issue). DoomR disables automatic npm release. Library npm publication runs separately.

### Release - Publish npm

[`Release - Publish npm`](.github/workflows/pipeline-publish-npm.yml) publishes a prepared version:

1. Checks notification credentials before publishing.
2. Checks the release tag matches the package version and belongs to the default branch. Manual publishing must also use the default branch.
3. Builds, tests, and verifies docs, package metadata, and tarball contents.
4. Selects the npm dist-tag and runs a publish dry run.
5. Unless in dry-run mode, publishes with provenance and attempts to notify blocked consumers.

**Stops at:** a verified dry run, publication, or a failing step. Does not implement or merge a PR.

### Deploy - Documentation

[`Deploy - Documentation`](.github/workflows/pipeline-deploy-docs.yml) builds the library and VitePress site, uploads the site, and deploys to GitHub Pages.

**Stops at:** deployment, an environment approval, or a failing build/deployment. Separate from Prove and npm publishing.

### Pipeline - Resume upstream

[`Pipeline - Resume upstream`](.github/workflows/pipeline-upstream-resume.yml) restarts work after an upstream release:

1. Reads the package/version and polls npm for `@1pizzateam/*` availability.
2. Finds matching `blocked:upstream` issues.
3. Posts upgrade instructions, removes the block, and adds `5-release`.
4. The new label triggers delivery independently for each unblocked issue.

**Stops at:** unblocked issues ready for delivery, or no matching issues. Registry polling is best-effort: exhausted retries do not prevent unblocking.

## Cross-repository changes

### Upstream libraries

When a capability belongs in an upstream `@1pizzateam/*` library:

1. Think writes `specs/issue-<N>/upstream-request.json`, or an audit writes `upstream-requests.json`.
2. The workflow opens a `5-release` issue in the library and blocks the consumer with `blocked:upstream` and `upstream-escalated:1`. Other issues continue independently.
3. The library pipeline implements, validates, and merges the change. Public API changes include documentation in the plan's scope.
4. Release checks verify documented exports, version/lockfile sync, changelog, docs links/build, and tarball contents. Release preparation also checks the previous/new versions and runs an npm publish dry run before creating the tag and GitHub Release.
5. After npm publication, downstream notifications unblock consumers so they can upgrade.

The [release-readiness skill](skills/release-readiness/SKILL.md) runs in Code/Prove with `--mode pr` and in release preparation/publishing with `--mode release`.

### Companion game editors

DoomR changes can require updates to Cadenza, FaceGun, MappR, PixelGun, PolyGun, or ShaderGun:

1. Think or an audit writes `editor-requests.json`.
2. After DoomR merges, Prove opens `5-release,upstream:doomr` issues in the affected editor repositories.
3. Each editor runs its own pipeline with a sibling `../DoomR.js` checkout (and `../FaceR.js` for FaceGun) for imports, tests, and builds.

## Audits and repository contents

[The audit runner](.github/workflows/audit-runner.yml) temporarily loads this repository's instructions and specialist audit agents, runs Copilot (`gemini-3.8-flash`) in read-only analysis mode, restores the application's original instructions, and creates **1 GitHub Issue per finding** (labeled `audit:<agent>`, deduplicated against existing open issues) and attaches each created issue to the repository's GitHub Project V2 board without setting a pipeline trigger label—leaving findings in the default Project column for manual triage before adding `1-think` or `5-release`.

| Path | Contains |
|---|---|
| [instructions/](instructions/) | Engineering style, ecosystem synchronization, vector-first APIs, and hot-loop performance rules |
| [agents/](agents/) | Dependency reuse, vector-first, performance, dead-code, test-gap, and documentation audits |
| [.github/workflows/](.github/workflows/) | Six audit workflows, their shared runner, and seven delivery/release workflows |
| [skills/release-readiness/](skills/release-readiness/) | Library documentation, metadata, build, and package checks |

## Testing the Pipeline Workflows

Requires Ruby with Minitest, Bash, and `jq`. No real credentials or Copilot installation needed.

```sh
ruby tests/workflows_test.rb
```

The suite checks shell syntax, token separation, checkpoints, spec reuse, parallel preparation, delivery queue configuration, and Project Status updates. Shell tests use a strict mock GitHub CLI and temporary directories. No live GitHub writes, agents, merges, or publishing run.

To also check triggers and handoff inputs in all 13 adjacent application workflow wrappers:

```sh
PROJECT_WORKFLOWS_ROOT=.. ruby tests/workflows_test.rb
```

Set that variable to the parent directory containing the application checkouts. Omit it to test only shared workflows.

Run one test or show detailed results:

```sh
ruby tests/workflows_test.rb --name test_existing_pr_is_proven_only_for_release
ruby tests/workflows_test.rb --verbose
```

Success ends with `0 failures, 0 errors, 0 skips`. If Minitest cannot load, install it for your Ruby interpreter.

For static validation, install [actionlint](https://github.com/rhysd/actionlint):

```sh
actionlint -shellcheck= \
  .github/workflows/pipeline-think.yml \
  .github/workflows/pipeline-plan.yml \
  .github/workflows/pipeline-code.yml \
  .github/workflows/pipeline-prove.yml \
  .github/workflows/test-workflows.yml
```

ShellCheck is disabled because existing scripts are not ShellCheck-clean; the tests check Bash syntax separately. [Workflow CI](.github/workflows/test-workflows.yml) runs actionlint and regression tests without production secrets.

These tests do not simulate GitHub's expression engine or live event/artifact delivery. Permissions, agent runs, merges, and releases still need testing in a disposable GitHub repository.
