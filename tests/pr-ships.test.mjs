import assert from 'node:assert/strict';
import test from 'node:test';
import { isShippedPath, prShipsCode } from '../skills/release-bump/scripts/pr-ships.mjs';

test('test suites, docs, CI and housekeeping never ship', () => {
  for (const f of [
    'tests/trigo.test.js', 'tests/geometry/circ.test.js', 'src/foo.test.ts', 'src/__tests__/a.ts',
    'README.md', 'CHANGELOG.md', 'website/docs/a.md', 'website/package.json', 'docs/x.md',
    '.github/workflows/code.yml', 'specs/issue-1/plan.md', 'pr.md', 'jest.config.js', '.gitignore',
    'dockerfile', 'docker-compose.yml', 'scripts/dev.mjs', 'contributor.md', 'LICENSE',
  ]) assert.equal(isShippedPath(f), false, f);
});

test('library source and package metadata ship', () => {
  for (const f of ['src/geometry/circ.ts', 'src/index.ts', 'package.json', 'rollup.config.mjs', 'tsconfig.json'])
    assert.equal(isShippedPath(f), true, f);
});

test('a PR ships when any file ships', () => {
  assert.equal(prShipsCode(['tests/trigo.test.js', 'pr.md']), false);
  assert.equal(prShipsCode(['tests/trigo.test.js', 'src/trigo.ts']), true);
  assert.equal(prShipsCode([]), false);
});
