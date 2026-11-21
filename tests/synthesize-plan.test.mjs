import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { findTestFile, isTestPath, parseIssueBody, synthesizePlan } from '../skills/plan-fast-path/scripts/synthesize-plan.mjs';

const BODY = `## Problem

\`fillGridCells\` is exported but unused.

## Affected Files

- \`src/geometry/grid.ts\`

## Suggested Fix

1. Remove the \`export\` keyword from \`fillGridCells\` in \`src/geometry/grid.ts\`.
2. Ensure existing tests and build continue to pass.

## Acceptance Criteria

- **AC-1:** \`fillGridCells\` in \`src/geometry/grid.ts\` is unexported (file-private).
- **AC-2:** \`Grid.prototype.getCellsForBounds\` continues to call \`fillGridCells\` without regression.
- **AC-3:** Existing grid tests, TypeScript compilation, and build pass without errors.

---
_Reported by \`dead-code\` audit in \`src/\`._`;

const THINK = '## Blast Radius\n- **Tier:** Low\n';

function repo({ test = true } = {}) {
  const root = mkdtempSync(path.join(tmpdir(), 'fastpath-'));
  mkdirSync(path.join(root, 'src/geometry'), { recursive: true });
  mkdirSync(path.join(root, 'tests/geometry'), { recursive: true });
  writeFileSync(path.join(root, 'src/geometry/grid.ts'), 'export function fillGridCells() {}\n');
  if (test) writeFileSync(path.join(root, 'tests/geometry/grid.test.js'), '// tests\n');
  writeFileSync(path.join(root, 'package.json'), JSON.stringify({ scripts: { test: 'jest', build: 'rollup -c' } }));
  return root;
}

const issue = (over = {}) => ({ title: 'chore(grid): unexport internal fillGridCells helper', body: BODY, labels: [{ name: 'audit:dead-code' }], ...over });
const run = (over = {}, ctx = {}) =>
  synthesizePlan({ issue: issue(over), issueNumber: 70, effort: ctx.effort ?? 'low', think: THINK, root: ctx.root || repo(), today: '2026-11-21' });

test('eligibility is exactly: audit issue and low effort', () => {
  assert.equal(run().eligible, true);
  assert.equal(run({ labels: [] }).eligible, false);
  assert.equal(run({}, { effort: 'medium' }).eligible, false);
  assert.equal(run({}, { effort: 'high' }).eligible, false);
  assert.equal(run({}, { effort: '' }).eligible, false);
  for (const label of ['audit:perf-audit', 'audit:vector-first', 'audit:docs-sync', 'audit:test-gap']) {
    assert.equal(run({ labels: [label] }).eligible, true, label);
  }
});

test('parses affected files, fix text and acceptance criteria', () => {
  const p = parseIssueBody(BODY);
  assert.deepEqual(p.files, ['src/geometry/grid.ts']);
  assert.match(p.fix, /^Remove the export keyword/);
  assert.equal(p.acs.length, 3);
});

test('test file helpers', () => {
  assert.equal(isTestPath('tests/a.js'), true);
  assert.equal(isTestPath('src/a.ts'), false);
  assert.equal(findTestFile(repo(), 'src/geometry/grid.ts'), 'tests/geometry/grid.test.js');
});

test('plan has the fix step and a test step when the matching test file is found', () => {
  const { plan } = run();
  assert.match(plan, /^# Plan: unexport internal fillGridCells helper/);
  assert.match(plan, /- \*\*In Scope:\*\* `src\/geometry\/grid\.ts`, `tests\/geometry\/grid\.test\.js`/);
  assert.match(plan, /### Step 2: Add acceptance criterion tests/);
  assert.match(plan, /- \*\*AC-1:\*\* Given the change for issue #70 is applied, then fillGridCells/);
  assert.match(plan, /\| AC-3 \| tests\/geometry\/grid\.test\.js: .* \| Step 2 \|/);
  assert.match(plan, /Automated by coding-pal-audit on 2026-11-21/);
});

test('without a test file there is a single step and the full test suite is the verification', () => {
  const { plan } = run({}, { root: repo({ test: false }) });
  assert.equal((plan.match(/### Step /g) || []).length, 1);
  assert.match(plan, /- \*\*Verification:\*\* `npm test`/);
});

test('a test file listed by the issue is covered by the fix step', () => {
  const body = BODY.replace('- `src/geometry/grid.ts`\n', '- `src/geometry/grid.ts`\n- `tests/geometry/grid.test.js`\n');
  const { plan } = run({ body });
  assert.equal((plan.match(/### Step /g) || []).length, 1);
  assert.match(plan, /\| AC-1 \| tests\/geometry\/grid\.test\.js: .* \| Step 1 \|/);
});

test('CLI writes plan.md only when eligible', () => {
  const root = repo();
  const dir = mkdtempSync(path.join(tmpdir(), 'fastpath-cli-'));
  writeFileSync(path.join(dir, 'issue.json'), JSON.stringify(issue()));
  writeFileSync(path.join(dir, 'think.md'), THINK);
  const script = path.join(path.dirname(fileURLToPath(import.meta.url)), '../skills/plan-fast-path/scripts/synthesize-plan.mjs');
  const args = (effort, out) => [script, '--issue', path.join(dir, 'issue.json'), '--issue-number', '70', '--effort', effort, '--think', path.join(dir, 'think.md'), '--out', out, '--root', root];
  assert.equal(JSON.parse(execFileSync('node', args('low', path.join(dir, 'specs/plan.md')))).eligible, true);
  assert.ok(existsSync(path.join(dir, 'specs/plan.md')));
  assert.equal(JSON.parse(execFileSync('node', args('high', path.join(dir, 'specs/other.md')))).eligible, false);
  assert.ok(!existsSync(path.join(dir, 'specs/other.md')));
});
