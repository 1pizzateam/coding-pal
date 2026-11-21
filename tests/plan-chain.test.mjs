import assert from 'node:assert/strict';
import test from 'node:test';
import { planChain } from '../skills/release-bump/scripts/plan-chain.mjs';

const issue = (number, ...labels) => ({ number, labels });
const pr = (...nums) => nums.map((n) => ({ headRefName: `feature/issue-${n}-slug` }));
const base = { issues: [issue(1), issue(2, 'ready'), issue(3, 'ready'), issue(4)] };

test('intercept: proceeds when no other milestone issue has an open PR', () => {
  assert.deepEqual(planChain({ ...base, mode: 'intercept', issueNumber: 2 }), { action: 'proceed', blockers: [] });
});

test('intercept: parks the issue while another one is in flight', () => {
  const r = planChain({ ...base, mode: 'intercept', issueNumber: 3, openPrs: pr(2) });
  assert.deepEqual(r, { action: 'intercept', blockers: [2] });
});

test('intercept: an issue never blocks itself (Code re-run of its own PR)', () => {
  assert.equal(planChain({ ...base, mode: 'intercept', issueNumber: 2, openPrs: pr(2) }).action, 'proceed');
});

test('intercept: merged issues and needs:developer issues do not block', () => {
  const issues = [issue(1), issue(2, 'needs:developer'), issue(3)];
  const r = planChain({ issues, mode: 'intercept', issueNumber: 3, openPrs: pr(1, 2), mergedPrs: pr(1) });
  assert.equal(r.action, 'proceed');
});

test('advance: starts the lowest-numbered ready issue', () => {
  assert.deepEqual(planChain({ ...base, mode: 'advance', issueNumber: 1, mergedPrs: pr(1) }), { action: 'trigger', issue: 2 });
});

test('advance: waits while another issue is in flight or queued by label', () => {
  const r = planChain({ ...base, mode: 'advance', issueNumber: 1, mergedPrs: pr(1), openPrs: pr(4) });
  assert.deepEqual(r, { action: 'none', reason: 'busy', busy: [4] });
  const queued = planChain({ issues: [issue(1), issue(2, 'ready'), issue(5, '5-release')], mode: 'advance', issueNumber: 1, mergedPrs: pr(1) });
  assert.deepEqual(queued, { action: 'none', reason: 'busy', busy: [5] });
});

test('advance: nothing ready means the chain stops; unmarked issues are never started', () => {
  const r = planChain({ issues: [issue(1), issue(2), issue(3)], mode: 'advance', issueNumber: 1, mergedPrs: pr(1) });
  assert.deepEqual(r, { action: 'none', reason: 'no-ready' });
});

test('advance: a failed (needs:developer) issue is skipped, not started and not blocking', () => {
  const issues = [issue(1), issue(2, 'ready', 'needs:developer'), issue(3, 'ready')];
  assert.deepEqual(planChain({ issues, mode: 'advance', issueNumber: 1, mergedPrs: pr(1) }), { action: 'trigger', issue: 3 });
});

test('advance: merged ready issues are not started again', () => {
  const issues = [issue(1), issue(2, 'ready'), issue(3, 'ready')];
  assert.equal(planChain({ issues, mode: 'advance', issueNumber: 1, mergedPrs: pr(1, 2) }).issue, 3);
});

test('repo-wide: issues without a milestone are chained and intercepted too', () => {
  const issues = [issue(1), issue(2, 'ready'), issue(3, 'ready')];
  assert.deepEqual(planChain({ issues, mode: 'advance', issueNumber: 1, mergedPrs: pr(1) }), { action: 'trigger', issue: 2 });
  assert.equal(planChain({ issues, mode: 'intercept', issueNumber: 3, openPrs: pr(2) }).action, 'intercept');
});

test('advance prefers the ready issue of the same milestone, then the lowest number', () => {
  const issues = [
    { number: 1, labels: [], milestone: { title: '5.0.0' } },
    { number: 2, labels: ['ready'], milestone: null },
    { number: 9, labels: ['ready'], milestone: { title: '5.0.0' } },
  ];
  assert.equal(planChain({ issues, mode: 'advance', issueNumber: 1, milestone: '5.0.0', mergedPrs: pr(1) }).issue, 9);
  assert.equal(planChain({ issues, mode: 'advance', issueNumber: 1, milestone: '', mergedPrs: pr(1) }).issue, 2);
});

test('a milestone issue in flight blocks a non-milestone issue and vice versa', () => {
  const issues = [{ number: 1, labels: [], milestone: { title: '5.0.0' } }, issue(2)];
  assert.deepEqual(planChain({ issues, mode: 'intercept', issueNumber: 2, openPrs: pr(1) }), { action: 'intercept', blockers: [1] });
});
