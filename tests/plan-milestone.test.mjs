import assert from 'node:assert/strict';
import test from 'node:test';
import { issueLevel, nextVersion, planMilestone, trainLevel } from '../skills/release-bump/scripts/plan-milestone.mjs';

const plan = (title, { labels = [], milestones = [], published = '4.6.1' } = {}) =>
  planMilestone({ published, title, labels, milestones });

test('issue level from title and labels', () => {
  assert.equal(issueLevel('test(utils): cover x', []), 'none');
  assert.equal(issueLevel('docs(overview): x', []), 'none');
  assert.equal(issueLevel('ci: x', []), 'none');
  assert.equal(issueLevel('perf(circ): x', []), 'patch');
  assert.equal(issueLevel('chore(grid): x', []), 'patch');
  assert.equal(issueLevel('fix(a): x', []), 'patch');
  assert.equal(issueLevel('feat(vec3): x', []), 'minor');
  assert.equal(issueLevel('refactor(a)!: x', []), 'major');
  assert.equal(issueLevel('refactor(a): x', ['audit:vector-first']), 'major');
  assert.equal(issueLevel('refactor(a): x', [{ name: 'breaking' }]), 'major');
  assert.equal(issueLevel('test(a): x', ['release:minor']), 'minor');
});

test('test and docs issues get no milestone', () => {
  assert.deepEqual(plan('test(trigo): cover waves'), { action: 'none', level: 'none' });
});

test('no train in progress: create the next version for the issue level', () => {
  assert.deepEqual(plan('perf(circ): x'), { action: 'create', level: 'patch', title: '4.6.2' });
  assert.deepEqual(plan('feat(vec3): x'), { action: 'create', level: 'minor', title: '4.7.0' });
  assert.deepEqual(plan('refactor(a): x', { labels: ['audit:vector-first'] }), { action: 'create', level: 'major', title: '5.0.0' });
});

test('train in progress is reused when it covers the level', () => {
  const milestones = [{ number: 3, title: '5.0.0' }];
  for (const title of ['perf(a): x', 'feat(a): x', 'refactor(a)!: x']) {
    assert.deepEqual(plan(title, { milestones }), { action: 'use', level: plan(title).level, title: '5.0.0', number: 3 });
  }
});

test('a higher-level issue raises the train instead of opening a second one', () => {
  const milestones = [{ number: 3, title: '4.7.0' }];
  assert.deepEqual(plan('refactor(a)!: x', { milestones }), { action: 'rename', level: 'major', title: '5.0.0', number: 3 });
  assert.deepEqual(plan('perf(a): x', { milestones }), { action: 'use', level: 'patch', title: '4.7.0', number: 3 });
});

test('milestones at or below the published version, or not versions, are not in progress', () => {
  const milestones = [{ number: 1, title: '4.6.1' }, { number: 2, title: '4.5.0' }, { number: 3, title: 'perf-batch' }];
  assert.deepEqual(plan('perf(a): x', { milestones }), { action: 'create', level: 'patch', title: '4.6.2' });
});

test('with several trains the lowest one in progress is used', () => {
  const milestones = [{ number: 9, title: '5.0.0' }, { number: 4, title: '4.7.0' }];
  assert.equal(plan('feat(a): x', { milestones }).number, 4);
});

test('raising a train to a level that already has its own milestone joins that one', () => {
  const milestones = [{ number: 4, title: '4.6.2' }, { number: 9, title: '5.0.0' }];
  assert.deepEqual(plan('refactor(a)!: x', { milestones }), { action: 'use', level: 'major', title: '5.0.0', number: 9 });
});

test('prerelease or unknown published version: no automatic milestone', () => {
  assert.equal(plan('perf(a): x', { published: '2.0.0-beta.1' }).action, 'none');
  assert.equal(plan('perf(a): x', { published: '' }).action, 'none');
});

test('version helpers', () => {
  assert.equal(nextVersion([4, 6, 1], 'patch'), '4.6.2');
  assert.equal(trainLevel([4, 6, 1], 'v5.0.0'), 'major');
  assert.equal(trainLevel([4, 6, 1], '4.6.1'), 'none');
});
