# 1pizzateam/coding-pal

Centralized AI coding instructions, CI audit agents, and reusable GitHub Actions audit workflows for 1PizzaTeam repositories.

## How Local APM vs. CI Audits Work

- **Local IDE (`apm install`)**: Consumer projects only reference `instructions/*.instructions.md` in their `apm.yml` so local AI coding assistants follow 1PizzaTeam rules while you write code. **Audit agents (`agents/*.agent.md`) are never installed locally.**
- **GitHub Actions CI (`copilot-audit.yml`)**: Automatically injects `instructions/` and `agents/` on the GitHub runner before invoking `@github/copilot`, and cleans them up before opening a Pull Request.

## Inventory

| Category | Path | Used Where | Purpose |
|---|---|---|---|
| **Instructions** (4) | `instructions/engineering-guidelines.instructions.md` | Local (`apm.yml`) & CI | Dynamic `package.json` dependency delegation, braceless single-statement blocks, TypeScript/JS style, `npm test` & `npm run build` verification |
| | `instructions/vector-first.instructions.md` | Local (`apm.yml`) & CI | Vector-only spatial signatures, no runtime type-branching, `target` out-parameters |
| | `instructions/hot-loop-performance.instructions.md` | Local (`apm.yml`) & CI | Zero hot-loop allocations, hoisted scratch instances/TypedArrays, WebGL state caching |
| | `instructions/api-design.instructions.md` | Local (`apm.yml`) & CI | Naming (`get*`/`set*`/`is*`/`has*`/`reset()`/`dispose()`), fluent `return this` mutators, unified primitive re-exports |
| **Agents** (6) | `agents/dependency-leverage.agent.md` | CI only | Replaces duplicated/hand-rolled code with calls to installed `package.json` libraries |
| | `agents/vector-first.agent.md` | CI only | Refactors spatial modules to enforce `vector-first` signatures |
| | `agents/perf-audit.agent.md` | CI only | Eliminates per-frame GC allocations in hot update/render loops |
| | `agents/dead-code.agent.md` | CI only | Removes unused internal exports, orphaned helpers, and dead state fields |
| | `agents/test-gap.agent.md` | CI only | Adds unit tests in `tests/` for untested branches and edge cases |
| | `agents/api-consistency.agent.md` | CI only | Aligns public API signatures and documentation with `api-design` |
| **Workflows** (6 + 1 runner) | `.github/workflows/copilot-audit.yml` | CI only | Shared runner engine (injects primitives, runs `@github/copilot`, verifies tests/build, opens PR if code changed) |
| | `.github/workflows/dependency-audit.yml` | CI only | Reusable Dependency Audit workflow |
| | `.github/workflows/vector-first-audit.yml` | CI only | Reusable Vector-First Audit workflow |
| | `.github/workflows/perf-audit.yml` | CI only | Reusable Performance & Zero-GC Audit workflow |
| | `.github/workflows/dead-code-audit.yml` | CI only | Reusable Dead Code Audit workflow |
| | `.github/workflows/test-gap-audit.yml` | CI only | Reusable Test Coverage Gap Audit workflow |
| | `.github/workflows/api-consistency-audit.yml` | CI only | Reusable API Consistency & Docs Audit workflow |
