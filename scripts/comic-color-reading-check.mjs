import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';

const root = new URL('../entry/src/main/ets/core/reader/', import.meta.url);
let member = true, supported = true, now = 1000;
const tasks = [];
const timers = new Set();
const context = vm.createContext({
  Map, Set, Promise, Error, Number, Array,
  Date: { now: () => now },
  setInterval: callback => { timers.add(callback); return callback; },
  clearInterval: callback => timers.delete(callback),
  ComicColorizer: {
    CANCELLED: '已取消着色', MEMBER_REQUIRED: '会员',
    supported: () => supported, memberAllowed: () => member,
    colorize: (_, source, active) => new Promise((resolve, reject) => tasks.push({ source, active, resolve, reject }))
  },
  ReaderImageMarker: { parse: source => ({ source }), pendingRaw: () => '', failureReason: () => '' },
  ReaderImageResults: {}
});
function load(name) {
  const source = fs.readFileSync(new URL(name, root), 'utf8').replace(/^import .*;\r?\n/gm, '').replace(/export /g, '');
  vm.runInContext(stripTypeScriptTypes(source), context);
}
load('ReaderComicColorSession.ets');
load('ReaderComicComputeQueue.ts');
const Session = vm.runInContext('ReaderComicColorSession', context);
const Candidate = vm.runInContext('ComicColorCandidate', context);
const Queue = vm.runInContext('ReaderComicComputeQueue', context);
const candidate = (source, visible = true, distance = 0) => new Candidate(source, visible, distance, source);
const flush = async () => { for (let i = 0; i < 8; i++) await Promise.resolve(); };
const finish = async task => { task.resolve({ uri: `file://${task.source}.jpg` }); await flush(); };
const session = new Session();
session.configure({}, 'book-a', true);
session.setForeground(true);
session.update([candidate('ahead', false, 1), candidate('edge', true, 200), candidate('center', true, 1)]);
assert.equal(tasks.length, 1);
assert.equal(tasks[0].source, 'center', 'screen center precedes visible edges and nearby pages');
session.update([candidate('jump'), candidate('jump-ahead', false, 1)]);
assert.equal(tasks[0].active(), false, 'stale native request is cooperatively cancelled');
assert.equal(tasks.length, 1, 'never submit another native request until completion');
await finish(tasks[0]);
assert.equal(tasks[1].source, 'jump');
assert.equal(session.uri('center'), '', 'late result does not appear after a jump');
await finish(tasks[1]);
assert.equal(session.uri('jump'), 'file://jump.jpg');
assert.equal(tasks[2].source, 'jump-ahead');
session.togglePause();
assert.equal(tasks[2].active(), false);
await finish(tasks[2]);
assert.equal(tasks.length, 3);
assert.equal(session.uri('jump'), 'file://jump.jpg', 'pause preserves displayed pages');
session.toggleCompare();
assert.equal(session.uri('jump'), '');
session.update([candidate('jump-ahead')]);
assert.ok(session.compared.has('jump'), 'webtoon comparison target is frozen at the tap');
assert.ok(!session.compared.has('jump-ahead'));
session.toggleCompare();
session.togglePause();
assert.equal(tasks.length, 4);
await finish(tasks[3]);
session.update([candidate('jump'), candidate('jump-ahead')]);
assert.equal(session.uri('jump-ahead'), 'file://jump-ahead.jpg');
member = false;
session.tick();
assert.equal(session.uri('jump'), '');
assert.equal(session.exportUri('jump'), '');
member = true;
session.tick();
assert.equal(session.uri('jump'), 'file://jump.jpg');
session.setEnabled(false);
assert.equal(session.uri('jump'), '', 'off restores originals, including manual results');
session.single('jump');
assert.equal(session.uri('jump'), 'file://jump.jpg');
assert.equal(session.uri('jump-ahead'), '', 'single-page action does not enable the whole book');
session.setEnabled(true);
session.update([candidate('background')]);
const background = tasks.at(-1);
session.setForeground(false);
assert.equal(background.active(), false);
assert.equal(timers.size, 0);
await finish(background);
assert.equal(session.uri('background'), '');
const beforeResume = tasks.length;
session.configure({}, 'book-b', true);
session.setForeground(true);
assert.equal(session.uri('jump'), '', 'book changes clear previous display state');
session.touch(true);
session.update([candidate('book-b')]);
assert.equal(tasks.length, beforeResume, 'do not start while a finger is down');
session.touch(false);
now += 301;
session.tick();
assert.equal(tasks.at(-1).source, 'book-b');
tasks.at(-1).reject(new Error('长条图暂不支持'));
await flush();
assert.match(session.status, /长条图/);
const failures = tasks.length;
session.update([candidate('book-b')]);
assert.equal(tasks.length, failures, 'failed pages are not retried endlessly');
session.retry();
assert.equal(tasks.length, failures + 1);
await finish(tasks.at(-1));
session.failed('book-b');
assert.equal(session.uri('book-b'), '', 'evicted files fall back to originals');
session.retry();
await finish(tasks.at(-1));
session.setForeground(false);

// Shared native gate must survive failure and hold the next kind of operation.
const order = [];
let release;
const first = Queue.run(async () => { order.push('sr-start'); await new Promise(r => { release = r; }); throw Error('sr'); });
const caught = first.catch(() => {});
const second = Queue.run(async () => { order.push('color-start'); return 7; });
await flush();
assert.deepEqual(order, ['sr-start']);
release();
await caught;
assert.equal(await second, 7);
assert.deepEqual(order, ['sr-start', 'color-start']);
console.log('Color reading: viewport priority, jump cancellation, serial native work, pause/off/compare, single page, membership, background, book isolation, touch deferral, failure/retry and cache eviction passed.');
