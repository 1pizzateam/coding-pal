---
name: release-readiness
description: "Verify @1pizzateam/* library package.json, lockfiles, npm tarball contents, CHANGELOG.md, and documentation before PR validation or release."
---

# Release Readiness Skill

Deterministic pre-release gate for `@1pizzateam/*` libraries (`RoostR.js`, `BumpR.js`, `LoopR.js`, `Spock.js`, `GroovR.js`).

## Usage

### 1. During PR Validation (`Code` & `Prove`)
```bash
node .agents/skills/release-readiness/scripts/verify-release-readiness.mjs --mode pr --require-dist --build-docs
```

### 2. Before Tagging & Publishing a Release
```bash
node .agents/skills/release-readiness/scripts/verify-release-readiness.mjs \
  --mode release \
  --expected-version <X.Y.Z> \
  --previous-version <prev-X.Y.Z> \
  --require-dist \
  --build-docs
```

## Deterministic Checks Enforced

1. **`package.json`, Lockfiles & Tarball Contents**:
   - `name` starts with `@1pizzateam/` and `version` is valid SemVer (matching `--expected-version` and strictly greater than `--previous-version` when provided).
   - `package-lock.json`, `website/package.json`, and `website/package-lock.json` versions match root `package.json`.
   - `main`, `types`, and `exports["."]` (`import` and `types`) are consistent, built on disk, and `npm pack --dry-run --json` contains strictly `LICENSE`, `README.md`, `package.json`, `dist/<lib>.js`, and `dist/<lib>.d.ts` (when `--require-dist` is passed).
2. **`CHANGELOG.md`**:
   - Line 1 matches `Version X.Y.Z (Month Day<st|nd|rd|th> Year)` (and matches `package.json` `version` when `--mode release`).
   - Line 2 is a dashed underline (`-----------------------------`).
   - Top section has one or more ` * ` bullet points, no `TODO`/`TBD`/`FIXME` placeholders, and no duplicate `Version X.Y.Z` sections.
3. **Documentation (`website/docs/**` & `README.md`)**:
   - Every public runtime export (`class`, `function`, `const`, `let`, `enum`) re-exported from the root `src/` entrypoint is documented in `website/docs/**` (or `README.md` if `website/docs` does not exist).
   - Every internal VitePress sidebar link in `website/docs/.vitepress/config.mjs` resolves to an existing Markdown file, and no `website/docs/{api,guide}/*.md` file is orphaned from the sidebar.
   - `npm --prefix website run build` succeeds when `--build-docs` is passed.
