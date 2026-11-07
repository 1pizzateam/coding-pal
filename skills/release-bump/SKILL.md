---
name: release-bump
description: "Choose the semver bump for @1pizzateam/* library releases from what actually ships (npm tarball + .d.ts API diff vs the published version), not from the issue title."
---

# Release Bump Skill

Used by the `Auto-release merged @1pizzateam/* library version` step in `pipeline-prove.yml`.

```bash
node .agents/skills/release-bump/scripts/classify-bump.mjs \
  --next <extracted new tarball> [--prev <extracted published tarball>] \
  --current-version <X.Y.Z> --title "<issue title>" --labels "a,b" --ts-from "$PWD"
```

## Rules

| Evidence (new tarball vs published `name@current-version`) | Bump |
| :--- | :--- |
| No shipped file changed (README/CHANGELOG/package.json/LICENSE are ignored; embedded version string ignored) | `none` - no release |
| Shipped runtime changed, `.d.ts` API unchanged | `patch` |
| Export added, optional parameter added, return type narrowed, parameter widened, optional member added | `minor` |
| Export removed, incompatible signature/type change, interface gained a required member | `major` |
| Package never published | at least `minor` |

- Intent only raises the bump: `feat...` floors at minor, `fix...` at patch, `feat!:` / `BREAKING CHANGE` / label `breaking` or `release:major` floors at major. `release:minor` / `release:patch` labels also set floors.
- A **major** derived from evidence alone (no `breaking`/`release:major`/`!` marker) is not released: the step fails with an issue comment asking for the `breaking` label, then the release is re-run.
- `0.x` stable versions release breaking changes as `minor`. Prerelease versions (`-alpha/-beta/-rc`) release any shipped change as `prerelease`.
- Compatibility is judged from the consumer side with the TypeScript checker (`isTypeAssignableTo`, old and new declarations in one program), so `typescript` must be resolvable from `--ts-from`; without it a changed `.d.ts` is treated as at least minor.
