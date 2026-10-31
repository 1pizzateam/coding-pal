# 1pizzateam/coding-pal

Shared agents, instructions, and GitHub Actions workflows for 1PizzaTeam.

The delivery pipeline turns an issue into a merged PR:

**Think -> Plan -> Code -> Prove**

Audits find and fix specific problems. Separate workflows publish npm packages and deploy documentation.

## Setup

1. Add the two organization Actions secrets below.
2. Grant both secrets to each application repository that runs the pipeline.
3. Use `secrets: inherit` in jobs that call the shared workflows. Existing application callers already do this.
4. Create the [trigger labels](#start-pause-and-resume) and [Project Status options](#project-status).
5. Add a trigger label to an open issue.

Applications do not install this repository through `apm.yml`. Workflows load the required agents and instructions at runtime.

## Model selection

Every Copilot call uses **`--model="auto"`**: Think, Plan, Code, Prove, automatic fixes, release preparation, and audits. Copilot selects the model within your account and organization policies.

No model variables or issue selections are required. Per-issue Standard/High effort selection is not implemented: the verified CLI release exposes `--auto-tier`, but its catalog-specific profile IDs have not been verified. Fusion's documented `--fusion-tier` flag is unavailable in CLI 1.0.105 and prerelease 1.0.106-0. `--reasoning-effort` is a separate setting, not a substitute for Fusion tiers.

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

| Label | Runs through | Stops at |
|---|---|---|
| `1-think` | Think | Specification comment, with `review:think` |
| `2-plan` | Think -> Plan | Plan comment, with `review:plan` |
| `3-code` | Think -> Plan -> Code | Open PR, with `review:code` |
| `4-release` | Think -> Plan -> Code -> Prove | Automatic merge and any configured release preparation |

Use **`4-release`** for the full autonomous pipeline. With an existing PR, it resumes directly at Prove.

Only the numbered labels trigger delivery. The old `ready*` labels and unprefixed `think`, `plan`, `code`, and `release` labels do not.

**Think and Plan run in parallel across issues.** They do not wait for another issue's implementation or review.

**Code onward is serialized per repository.** Code holds one delivery slot through its dependent Prove job, merge, and configured release preparation. A standalone Prove request joins the same queue. Other repositories have their own queues.

GitHub queues up to **100 pending deliveries** with `queue: max`, without replacing earlier pending runs. FIFO follows entry into the concurrency queue, not issue creation or label time. GitHub does not guarantee dispatch-time ordering; requests beyond the limit are canceled and must be resubmitted.

A Code review pause releases the slot. Adding `4-release` later queues Prove as a new delivery request. Failures also release the slot and leave the issue flagged for attention. Separate npm publication and documentation deployment are outside this queue.

Before validation, Prove merges the latest base into the PR branch and pushes clean updates. Merge conflicts stop with a PR comment and `needs:developer`; resolve them within the approved plan, or revise Think/Plan before retrying. All controls and the independent assessment run on the refreshed branch, including checks for interactions with intervening changes.

If the base or PR head changes during validation, Prove blocks merge and requires a rerun. The merge request is pinned to the validated head commit. Enable branch protection requiring an up-to-date branch (or a merge queue) to cover the final race with merges outside this pipeline.

Think explicitly starts Plan, and Plan starts Code, only after uploading a handoff artifact. Prove is a dependent job inside the Code workflow run, not a separately dispatched run. Queued or paused preparation creates no downstream workflow; a Code review pause skips the Prove job.

Before deploying this change, stop or finish active delivery runs. Deploy the shared workflow changes and all application callers before resuming issues. Do not mix the old dispatch/completion chain with the new dependent Prove job: it can duplicate Prove or leave a handoff unprocessed.

### Request an extra pause

Use a trigger label and add a checked box to the issue body:

```markdown
- [x] Pause after Think
- [ ] Pause after Plan
- [ ] Pause after Code
```

Inline `[pause:think]`, `[pause:plan]`, and `[pause:code]` directives also work.

### Review and resume

1. Review or edit the `# Think:` or `# Plan:` issue comment.
2. Clear any pause checkbox or directive for the phase you want to pass.
3. Add a later trigger label. For example, add `4-release` to continue from any review checkpoint through merge.

The pipeline reuses existing specifications and PRs. To regenerate Think or Plan, delete its specification comment before reapplying a trigger label.

## Project Status

**Labels start work. Status reports the phase entered, not whether it passed or is still running.**

Add these options to the Project's `Status` field:

| Workflow | Status when it starts | After success |
|---|---|---|
| Think | **Think** | Stays Think until Plan starts |
| Plan | **Plan** | Stays Plan until Code starts |
| Code | **Code** | Stays Code until Prove starts, including review pauses |
| Prove | **Release** | Changes to **Done** after merge and configured release preparation |

Prove is different: it sets **Release** before validation and **Done** after completion. A failed run can remain in Release with `needs:developer`. Check the workflow result and labels.

**Done does not mean npm publishing has finished.** Publishing runs separately.

## Pipeline Walkthrough

### Pipeline - Think

[`Pipeline - Think`](.github/workflows/pipeline-think.yml) defines the change:

1. Checks existing specs and PRs to start Think or resume a later phase.
2. Sets Project Status to **Think**.
3. Runs the Think agent to define the problem, scope, constraints, and acceptance criteria.
4. Validates the spec and posts it as a `# Think:` issue comment.
5. If an upstream library must change first, opens a `4-release` issue there and marks this issue `blocked:upstream`.
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
3. Runs the Code agent to implement the plan and prepare the PR record.
4. Checks tests, build, scope, and applicable library release requirements.
5. Pushes the branch and creates or updates the PR.
6. Pauses with `review:code` if requested; otherwise, passes the specs and PR number to Prove.

**Stops at:** an open PR for review or handoff to Prove. Code does not merge.

Failed Think, Plan, or Code runs mark the issue `needs:developer`. They do not restart other issues.

### Pipeline - Prove

[`Pipeline - Prove`](.github/workflows/pipeline-prove.yml) validates and merges the PR:

1. Sets Project Status to **Release**.
2. Checks specs, scope, secrets, dependencies, tests, builds, acceptance criteria, and PR metadata.
3. Runs the Prove agent for an independent assessment and validation record.
4. Fixes failures and retries, **up to 5 times by default**.
5. If everything passes, attempts approval and **squash-merges the PR**, deleting its branch.
6. Dispatches companion editor updates. For eligible libraries with automatic release enabled, prepares the version and creates a GitHub Release.
7. Sets **Done**. Finishing the delivery run releases the slot for the next queued request.

High/Critical changes require rollback verification evidence. Critical also requires a staged rollout reference. Missing evidence blocks merge; automation does not fabricate human sign-off.

**Stops at:** successful merge/release preparation or a failure needing attention. There is no routine human approval pause. At the fix limit, the PR stays open and the issue/PR get `needs:developer`. A failure after merge does not undo it.

Manual Prove dispatch also permits auto-merge without a `4-release` label. DoomR disables automatic npm release. Library npm publication runs separately.

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
3. Posts upgrade instructions, removes the block, and adds `4-release`.
4. The new label triggers Think independently for each unblocked issue.

**Stops at:** unblocked issues ready for Think, or no matching issues. Registry polling is best-effort: exhausted retries do not prevent unblocking.

## Cross-repository changes

### Upstream libraries

When a capability belongs in an upstream `@1pizzateam/*` library:

1. Think writes `specs/issue-<N>/upstream-request.json`, or an audit writes `upstream-requests.json`.
2. The workflow opens a `4-release` issue in the library and blocks the consumer with `blocked:upstream` and `upstream-escalated:1`. Other issues continue independently.
3. The library pipeline implements, validates, and merges the change. Public API changes include documentation in the plan's scope.
4. Release checks verify documented exports, version/lockfile sync, changelog, docs links/build, and tarball contents. Release preparation also checks the previous/new versions and runs an npm publish dry run before creating the tag and GitHub Release.
5. After npm publication, downstream notifications unblock consumers so they can upgrade.

The [release-readiness skill](skills/release-readiness/SKILL.md) runs in Code/Prove with `--mode pr` and in release preparation/publishing with `--mode release`.

### Companion game editors

DoomR changes can require updates to Cadenza, MappR, PixelGun, PolyGun, or ShaderGun:

1. Think or an audit writes `editor-requests.json`.
2. After DoomR merges, Prove opens `4-release,upstream:doomr` issues in the affected editor repositories.
3. Each editor runs its own pipeline with a sibling `../DoomR.js` checkout for imports, tests, and builds.

## Audits and repository contents

[The audit runner](.github/workflows/audit-runner.yml) temporarily loads this repository's instructions and agents, runs Copilot, restores the application's original instructions, checks tests/build, and opens a PR if code changed.

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

To also check triggers and handoff inputs in all 11 adjacent application workflow wrappers:

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
