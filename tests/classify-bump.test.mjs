import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { classify, intentFloor } from '../skills/release-bump/scripts/classify-bump.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const TS_FROM = process.env.TS_FROM || path.join(here, '../../BumpR.js');

function pkg({ js = 'export const a = 1;\n', dts = 'export declare const a: number;\n', md = '# readme\n', version = '1.2.0' } = {}) {
  const dir = mkdtempSync(path.join(tmpdir(), 'classify-bump-'));
  mkdirSync(path.join(dir, 'dist'));
  writeFileSync(path.join(dir, 'package.json'), JSON.stringify({ name: '@1pizzateam/x', version, types: 'dist/x.d.ts' }));
  writeFileSync(path.join(dir, 'dist/x.js'), js);
  writeFileSync(path.join(dir, 'dist/x.d.ts'), dts);
  writeFileSync(path.join(dir, 'README.md'), md);
  return dir;
}

const run = (prev, next, extra = {}) =>
  classify({ prev, next, currentVersion: '1.2.0', title: '', labels: [], tsFrom: TS_FROM, ...extra });

test('identical shipped files (docs only change) => no release', () => {
  const r = run(pkg(), pkg({ md: '# changed docs\n' }), { title: 'docs: update readme' });
  assert.equal(r.bump, 'none');
});

test('title says feat but nothing shipped => still no release', () => {
  assert.equal(run(pkg(), pkg(), { title: 'feat: nothing real' }).bump, 'none');
});

test('embedded version string alone is not a change', () => {
  const r = run(pkg({ js: 'export const v = "1.2.0";\n' }), pkg({ js: 'export const v = "1.2.0";\n', version: '1.2.0' }));
  assert.equal(r.bump, 'none');
});

test('runtime-only change => patch; feat title floors it to minor', () => {
  const prev = pkg();
  const next = pkg({ js: 'export const a = 2;\n' });
  assert.equal(run(prev, next).bump, 'patch');
  assert.equal(run(prev, next, { title: 'feat: new thing' }).bump, 'minor');
  assert.equal(run(prev, next, { title: 'fix: bug' }).bump, 'patch');
});

test('added export => minor even when title says fix', () => {
  const r = run(pkg(), pkg({ js: 'export const a = 1; export const b = 2;\n', dts: 'export declare const a: number;\nexport declare const b: number;\n' }), { title: 'fix: tiny' });
  assert.equal(r.bump, 'minor');
  assert.deepEqual(r.apiChanges.map((c) => [c.name, c.level]), [['b', 'minor']]);
});

test('removed export => major needing confirmation', () => {
  const prev = pkg({ dts: 'export declare const a: number;\nexport declare const b: number;\n' });
  const r = run(prev, pkg({ js: 'export const a = 1;\n// changed\n' }), { title: 'fix: cleanup' });
  assert.equal(r.bump, 'major');
  assert.equal(r.needsConfirmation, true);
});

test('breaking label confirms major', () => {
  const prev = pkg({ dts: 'export declare const a: number;\nexport declare const b: number;\n' });
  const r = run(prev, pkg({ js: '// changed\n' }), { labels: ['breaking'] });
  assert.equal(r.bump, 'major');
  assert.equal(r.needsConfirmation, false);
});

test('function gaining optional parameter => minor; required parameter => major', () => {
  const prev = pkg({ dts: 'export declare function f(a: string): void;\n' });
  const optional = run(prev, pkg({ js: '// o\n', dts: 'export declare function f(a: string, b?: number): void;\n' }));
  assert.equal(optional.bump, 'minor');
  const required = run(prev, pkg({ js: '// r\n', dts: 'export declare function f(a: string, b: number): void;\n' }));
  assert.equal(required.bump, 'major');
});

test('return type widened => major, narrowed => minor', () => {
  const prev = pkg({ dts: 'export declare function f(): string | number;\n' });
  assert.equal(run(prev, pkg({ js: '// n\n', dts: 'export declare function f(): string;\n' })).bump, 'minor');
  const prevNarrow = pkg({ dts: 'export declare function f(): string;\n' });
  assert.equal(run(prevNarrow, pkg({ js: '// w\n', dts: 'export declare function f(): string | number;\n' })).bump, 'major');
});

test('interface gaining a required member => major, optional member => minor', () => {
  const prev = pkg({ dts: 'export interface Opts { a: number }\n' });
  assert.equal(run(prev, pkg({ js: '// r\n', dts: 'export interface Opts { a: number; b: string }\n' })).bump, 'major');
  assert.equal(run(prev, pkg({ js: '// o\n', dts: 'export interface Opts { a: number; b?: string }\n' })).bump, 'minor');
});

test('comment-only d.ts change does not alter the API', () => {
  const prev = pkg({ dts: 'export declare const a: number;\n' });
  const r = run(prev, pkg({ js: '// c\n', dts: '/** doc */\nexport declare const a: number;\n' }));
  assert.equal(r.bump, 'patch');
});

test('0.x stable: breaking change releases as minor', () => {
  const prev = pkg({ dts: 'export declare const a: number;\nexport declare const b: number;\n', version: '0.4.0' });
  const r = run(prev, pkg({ js: '// x\n', version: '0.4.0' }), { currentVersion: '0.4.0' });
  assert.equal(r.bump, 'minor');
  assert.equal(r.needsConfirmation, false);
});

test('prerelease version: any shipped change => prerelease; nothing shipped => none', () => {
  const prev = pkg({ version: '0.1.0-alpha.4' });
  assert.equal(run(prev, pkg({ js: '// x\n', version: '0.1.0-alpha.4' }), { currentVersion: '0.1.0-alpha.4' }).bump, 'prerelease');
  assert.equal(run(prev, pkg({ version: '0.1.0-alpha.4' }), { currentVersion: '0.1.0-alpha.4' }).bump, 'none');
});

test('no published baseline => at least minor', () => {
  const r = classify({ prev: '', next: pkg(), currentVersion: '0.1.0', title: 'fix: first', labels: [], tsFrom: TS_FROM });
  assert.equal(r.bump, 'minor');
  assert.equal(r.evidence, 'no-baseline');
});

test('intent floor parsing', () => {
  assert.equal(intentFloor('feat(x): y', []).level, 'minor');
  assert.equal(intentFloor('fix: y', []).level, 'patch');
  assert.equal(intentFloor('chore: y', []).level, 'none');
  assert.deepEqual(intentFloor('feat!: y', []), { level: 'major', confirmedMajor: true });
  assert.equal(intentFloor('anything', ['breaking']).level, 'major');
});
