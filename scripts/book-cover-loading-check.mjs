import assert from 'node:assert/strict';
import test from 'node:test';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';

const root = new URL('../entry/src/main/ets/', import.meta.url);
const read = file => fs.readFileSync(new URL(file, root), 'utf8');
const compile = text => stripTypeScriptTypes(text.replace(/^import .*;\r?\n/gm, '').replace(/^export /gm, ''));
const tick = async () => { for (let i = 0; i < 12; i++) await Promise.resolve(); };

function coverHarness() {
  const source = read('components/book/BookCover.ets');
  const methods = ['clearCoverRetries', 'resolveDisplayCovers', 'loadDisplayCover', 'scheduleCoverRetry',
    'markFailed', 'activeCover', 'isActiveCoverReady', 'notifyReadyCover', 'markLoaded', 'aboutToDisappear'];
  const body = methods.map(name => {
    const start = new RegExp(`^  (?:private )?(?:async )?${name}\\(`, 'm').exec(source)?.index;
    assert.notEqual(start, undefined, name);
    return source.slice(start, source.indexOf('\n  }', start) + 4).replace('private ', '');
  }).join(',');
  const requests = [], invalidated = [], ready = [], timers = new Map(), cache = new Map();
  let nextTimer = 0;
  const sandbox = vm.createContext({
    getContext: () => ({}),
    setTimeout: fn => { const id = ++nextTimer; timers.set(id, fn); return id; },
    clearTimeout: id => timers.delete(id),
    BookCoverCache: {
      resolveCachedCover: (_context, raw) => cache.get(raw) || '',
      resolveCover: (_context, raw) => new Promise((resolve, reject) => requests.push({ raw, resolve, reject })),
      deleteCachedCover: (_context, raw) => { invalidated.push(raw); cache.delete(raw); }
    }
  });
  const cover = vm.runInContext(compile(`({${body}})`), sandbox);
  Object.assign(cover, { mounted: true, covers: [], displayCovers: [], activeIndex: 0,
    loadedRevision: 0, loadedUrls: new Set(), coverLoadSerial: 0, requestSerial: 0,
    retryTimers: new Map(), retryCounts: new Map(), onReadyCover: value => ready.push(value) });
  const fire = async () => { const pending = [...timers.values()]; timers.clear(); pending.forEach(fn => fn()); await tick(); };
  return { cover, requests, invalidated, ready, timers, cache, fire };
}

test('cold source covers update the mounted image and backdrop without a global revision or restart', async () => {
  const f = coverHarness();
  const url = 'https://image/1.jpg#source-cover-v1=source';
  f.cover.covers = [url];
  f.cover.resolveDisplayCovers();
  assert.equal(f.cover.activeCover(), '');
  assert.equal(f.requests.length, 1);
  f.requests[0].resolve('file:///cache/1.jpg');
  await tick();
  assert.equal(f.cover.activeCover(), 'file:///cache/1.jpg');
  assert.equal(f.ready.at(-1), '', 'backdrop waits for native image decode');
  f.cover.markLoaded('file:///cache/1.jpg');
  assert.equal(f.ready.at(-1), 'file:///cache/1.jpg');
  assert.equal(f.cover.covers[0], url, 'persistent source selection stays unchanged');
});

test('out-of-order completions stay in their carousel slots; resources and local covers do not download', async () => {
  const f = coverHarness();
  const resource = { id: 123 };
  f.cover.covers = ['https://image/a', resource, '/local/cover.jpg', 'https://image/b'];
  f.cover.resolveDisplayCovers();
  assert.equal(f.requests.length, 2);
  f.requests[1].resolve('file:///b');
  await tick();
  assert.equal(f.cover.displayCovers[0], '');
  assert.equal(f.cover.displayCovers[1], resource);
  assert.equal(f.cover.displayCovers[2], '/local/cover.jpg');
  assert.equal(f.cover.displayCovers[3], 'file:///b');
  f.requests[0].resolve('file:///a');
  await tick();
  assert.equal(f.cover.displayCovers[0], 'file:///a');
});

test('changing books and unmounting reject old downloads and cancel retry timers', async () => {
  const f = coverHarness();
  f.cover.covers = ['https://image/old'];
  f.cover.resolveDisplayCovers();
  f.cover.covers = ['https://image/new'];
  f.cover.resolveDisplayCovers();
  f.requests[0].resolve('file:///old');
  await tick();
  assert.equal(f.cover.activeCover(), '');
  f.requests[1].resolve('file:///new');
  await tick();
  f.cover.markFailed('file:///new');
  assert.equal(f.timers.size, 1);
  f.cover.aboutToDisappear();
  assert.equal(f.timers.size, 0);
  await f.fire();
  assert.equal(f.requests.length, 2);
});

test('transient network and decoder failures retry in place, with a hard two-retry limit', async () => {
  const f = coverHarness();
  f.cover.covers = ['https://image/a'];
  f.cover.resolveDisplayCovers();
  f.requests[0].resolve('https://image/a'); // Legacy failure fallback must not bypass headers via native Image.
  await tick();
  assert.equal(f.cover.activeCover(), '');
  await f.fire();
  f.requests[1].resolve('file:///cache/a');
  await tick();
  f.cover.markFailed('file:///cache/a');
  assert.equal(f.cover.activeCover(), '', 'remove failed Image before reusing the same cache URI');
  await f.fire();
  assert.deepEqual(f.invalidated, ['https://image/a']);
  f.requests[2].reject(new Error('offline'));
  await tick();
  assert.equal(f.timers.size, 0);
  assert.equal(f.requests.length, 3);
});

function cacheHarness() {
  const files = new Map(), handles = new Map();
  const state = { pauseWrite: null, shortWrite: false, failWrite: false, nextFd: 0 };
  const sandbox = vm.createContext({ console, Uint8Array, ArrayBuffer,
    fs: {
      OpenMode: { CREATE: 1, WRITE_ONLY: 2, TRUNC: 4 },
      open: async path => { files.set(path, Buffer.alloc(0)); const fd = ++state.nextFd; handles.set(fd, path); return { fd }; },
      write: async (fd, bytes) => {
        if (state.pauseWrite) await state.pauseWrite;
        if (state.failWrite) throw new Error('disk');
        const count = state.shortWrite ? Math.min(2, bytes.byteLength) : bytes.byteLength;
        const path = handles.get(fd);
        files.set(path, Buffer.concat([files.get(path), Buffer.from(bytes).subarray(0, count)]));
        return count;
      },
      close: async file => handles.delete(typeof file === 'number' ? file : file.fd),
      rename: async (from, to) => { assert(files.has(from)); files.set(to, files.get(from)); files.delete(from); },
      unlink: async path => files.delete(path),
      statSync: path => { if (!files.has(path)) throw new Error('missing'); return { size: files.get(path).length }; },
      stat: async path => { if (!files.has(path)) throw new Error('missing'); return { size: files.get(path).length }; }
    }, fileUri: { getUriFromPath: path => 'file://' + path }
  });
  vm.runInContext(compile(read('utils/BookCoverCache.ets')), sandbox);
  return { cache: vm.runInContext('BookCoverCache', sandbox), files, handles, state };
}

test('cache path is published only after all short writes finish and the file closes', async () => {
  const f = cacheHarness(), context = { cacheDir: '/cache' }, raw = 'https://image/a';
  const path = f.cache.cachedCoverPath(context, raw);
  let resume;
  f.state.shortWrite = true;
  f.state.pauseWrite = new Promise(resolve => { resume = resolve; });
  const writing = f.cache.storeCover(context, raw, new Uint8Array([0, 1, 2, 3, 4, 5]).subarray(1, 5));
  await tick();
  assert.equal(f.cache.resolveCachedCover(context, raw), '', 'never hand Image a partially written file');
  resume();
  await writing;
  assert.deepEqual([...f.files.get(path)], [1, 2, 3, 4]);
  assert.equal(f.handles.size, 0);
  assert.equal(f.files.size, 1, 'no temporary files left behind');
  assert.equal(f.cache.resolveCachedCover(context, raw), 'file://' + path);
});

test('write failure preserves an old good cache; deleted and zero-byte caches are not remembered', async () => {
  const f = cacheHarness(), context = { cacheDir: '/cache' }, raw = 'https://image/a';
  await f.cache.storeCover(context, raw, new Uint8Array([1, 2]));
  const path = f.cache.cachedCoverPath(context, raw);
  f.state.failWrite = true;
  await assert.rejects(f.cache.storeCover(context, raw, new Uint8Array([3, 4])), /disk/);
  assert.deepEqual([...f.files.get(path)], [1, 2]);
  assert.equal(f.files.size, 1);
  assert.equal(f.handles.size, 0);
  f.files.delete(path);
  assert.equal(f.cache.resolveCachedCover(context, raw), '');
  f.files.set(path, Buffer.alloc(0));
  assert.equal(await f.cache.resolveCachedCoverAsync(context, raw), '');
});

test('shared resolutions are released after success or failure so retries start a new request', async () => {
  const f = cacheHarness(), context = { cacheDir: '/cache' }, raw = 'https://image/a';
  const requests = [];
  f.cache.resolveCoverInternal = () => new Promise((resolve, reject) => requests.push({ resolve, reject }));
  const first = f.cache.resolveCover(context, raw);
  const shared = f.cache.resolveCover(context, raw);
  assert.equal(requests.length, 1);
  requests[0].resolve('');
  assert.deepEqual(await Promise.all([first, shared]), ['', '']);
  assert.equal(f.cache.inFlightResolutions.size, 0);
  const retry = f.cache.resolveCover(context, raw);
  assert.equal(requests.length, 2);
  requests[1].reject(new Error('offline'));
  await assert.rejects(retry, /offline/);
  assert.equal(f.cache.inFlightResolutions.size, 0);
  const final = f.cache.resolveCover(context, raw);
  requests[2].resolve('file:///cache/a');
  assert.equal(await final, 'file:///cache/a');
  assert.equal(f.cache.inFlightResolutions.size, 0);
});
