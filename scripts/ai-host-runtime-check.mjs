import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';

let now = 10_000_000, cacheDir = '/cache', scans = 0, timer, onStat;
const files = new Map();
const path = name => `${cacheDir}/comic_images/${name}`;
const put = (name, size, mtime = 1) => {
  const id = path(name);
  files.set(id, { size, mtime, isFile: () => true });
  return id;
};
const fileStat = id => { if (!files.has(id)) throw Error('missing'); return { ...files.get(id) }; };
const ctx = vm.createContext({ Map, Array, Math, Promise, Error, console, Date: { now: () => now },
  AppStorage: { get: () => cacheDir },
  setTimeout(fn) { timer = fn; return 1; },
  fs: {
    accessSync: () => true,
    async listFile(dir) { scans++; return [...files.keys()].filter(id => id.startsWith(`${dir}/`)).map(id => id.slice(dir.length + 1)); },
    async stat(id) { const value = fileStat(id); if (onStat) await onStat(id); return value; },
    statSync: fileStat,
    unlinkSync(id) { if (!files.delete(id)) throw Error('missing'); },
    utimes(id, time) { if (files.has(id)) files.get(id).mtime = time / 1000; }
  }
});
const load = relative => vm.runInContext(stripTypeScriptTypes(fs.readFileSync(new URL(`../entry/src/main/ets/${relative}`, import.meta.url), 'utf8')
  .replace(/^import [^;]*;\r?\n/gm, '').replace(/^export /gm, '')), ctx);
load('core/book/ReaderCacheBudgetPolicy.ts');
load('core/book/ReaderCacheBudget.ts');
const Budget = vm.runInContext('ReaderCacheBudget', ctx);
const idle = () => Budget.chain;
const trim = async () => { const fire = timer; timer = undefined; assert.ok(fire); fire(); await idle(); };
const sumIndex = () => [...Budget.comicIndex.values()].reduce((sum, item) => sum + item.bytes, 0);

const original = put('12345678.jpg', 100);
const color = put(`color_alac-fp16-v4_${'a'.repeat(64)}.jpg`, 200);
put('inflight.jpg.tmp', 9999); put('inflight.jpg.part', 9999);
assert.equal(await Budget.comicUsageBytes(), 300, 'initial scan includes versioned color files, excludes temporary files');
assert.equal(scans, 1);
const sr = put(`sr_${'b'.repeat(64)}.jpg`, 300);
Budget.noteComicWrite(sr); await idle();
assert.equal(sumIndex(), 600);
assert.equal(scans, 1, 'completed writes stat only their own file');
put(`sr_${'b'.repeat(64)}.jpg`, 350);
Budget.noteComicWrite(sr); await idle(); await trim();
assert.equal(sumIndex(), 650, 'overwriting a path replaces, rather than doubles, its size');
assert.equal(scans, 1, 'automatic trim reuses the index');
const ocr = put(`ocr_v4_${'c'.repeat(64)}.json`, 50);
Budget.noteComicWrite(ocr); await idle(); await trim();
assert.equal(sumIndex(), 700); assert.equal(scans, 1);

Budget.touchComicFile(original);
let cleared = await Budget.clearComic();
assert.equal(cleared.removed, 1); assert.ok(!files.has(color));
assert.ok(files.has(original) && files.has(sr) && files.has(ocr), 'recent hits and writes are protected');
assert.equal(sumIndex(), 500, 'deletions update the index');

put('legacy.png', 75);
Budget.noteComicWrite(); await idle(); await trim();
assert.equal(sumIndex(), 575, 'legacy no-argument notifications force discovery');
const beforeTTL = scans;
now += 300001;
files.delete(path('legacy.png'));
Budget.noteComicWrite(sr); await idle(); await trim();
assert.equal(scans, beforeTTL + 1, 'periodic reconciliation notices external deletion');
assert.equal(sumIndex(), 500);

Budget.noteComicWrite(path('missing.jpg')); await idle();
assert.equal(Budget.comicIndexAt, 0, 'stat failure forces reconciliation');
await trim();
const beforeInvalid = scans;
Budget.noteComicWrite('/outside/file.jpg'); await idle(); await trim();
assert.equal(scans, beforeInvalid + 1, 'out-of-directory paths are never indexed');

// A cache hit can race with the asynchronous scan; it must still prevent deletion.
const racing = put('racing.jpg', 10);
onStat = async id => { if (id === racing) Budget.touchComicFile(racing); };
await Budget.clearComic();
assert.ok(files.has(racing));
onStat = undefined;
now += 600001;
cleared = await Budget.clearComic();
assert.ok(cleared.removed >= 4);
assert.equal(sumIndex(), 0);
assert.ok(files.has(path('inflight.jpg.tmp')));

cacheDir = '/other'; put('other.jpg', 42);
Budget.noteComicWrite(path('other.jpg')); await idle(); await trim();
assert.equal(sumIndex(), 42, 'changing the cache root discards the old index');
assert.equal(Budget.comicIndexDir, '/other/comic_images');

Budget.COMIC_LIMIT_BYTES = 100;
const oversized = put('old.jpg', 150);
Budget.noteComicWrite(); await idle(); await trim();
assert.ok(!files.has(oversized), 'automatic trimming removes old files when over budget');
assert.equal(sumIndex(), 42, 'automatic trimming preserves recent writes and updates accounting');

let concurrentWrite;
onStat = async id => {
  if (id === path('other.jpg') && !concurrentWrite) {
    concurrentWrite = put('during-scan.jpg', 10);
    Budget.noteComicWrite(concurrentWrite);
  }
};
await Budget.comicUsageBytes(); await idle();
onStat = undefined;
assert.ok(Budget.comicIndex.has(concurrentWrite), 'a write arriving after listFile is indexed after the scan');
assert.equal(sumIndex(), 52);

// Exercise the actual host forwarding method, and the Ability lifecycle hook.
const notifications = [];
// Intercept the lexical class method for the real host invocation.
Budget.noteComicWrite = value => notifications.push(value);
load('utils/AppAiHost.ets');
const Host = vm.runInContext('AppAiHost', ctx);
new Host().noteComicWrite('/cache/comic_images/done.jpg'); new Host().noteComicWrite();
assert.deepEqual(notifications, ['/cache/comic_images/done.jpg', undefined]);
const ability = fs.readFileSync(new URL('../entry/src/main/ets/entryability/EntryAbility.ets', import.meta.url), 'utf8');
assert.match(ability, /onMemoryLevel\(level: AbilityConstant.MemoryLevel\): void\s*\{\s*ComicColorizer.onMemoryPressure\(level\)/);
console.log('AI host: path forwarding, incremental accounting, overwrite, legacy/TTL reconciliation, recent-use races, cleanup and memory-level forwarding passed.');
