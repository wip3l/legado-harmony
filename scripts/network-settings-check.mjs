import assert from 'node:assert/strict';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { readEtsModule } from './lib/ets-module-staging.mjs';

const key = 'networkForceHttp1';
function process(disk = new Map()) {
  const storage = new Map(); const http = { forceHttp1: false };
  const state = { fail: false, readGate: null };
  const context = vm.createContext({ HttpClient: http, setInterval, clearInterval,
    AppStorage: { setOrCreate: (key, value) => storage.set(key, value) },
    preferences: { getPreferences: async () => {
      const pending = new Map(disk);
      return { get: async (key, fallback) => { const value = pending.get(key) ?? fallback; await state.readGate; return value; },
        put: async (key, value) => pending.set(key, value),
        flush: async () => { if (state.fail) throw new Error('disk failure'); for (const [key, value] of pending) disk.set(key, value); } };
    } }
  });
  for (const file of ['core/book/ReaderImageScheduler.ts', 'utils/NetworkSettingsStore.ets']) {
    vm.runInContext(stripTypeScriptTypes(readEtsModule(file)
      .replace(/^import .*;\r?\n/gm, '').replace(/^export /gm, ''), { mode: 'strip' }), context);
  }
  return { store: vm.runInContext('NetworkSettingsStore', context),
    scheduler: vm.runInContext('ReaderImageScheduler', context), storage, http, state };
}
const disk = new Map();
for (const value of [true, false]) {
  const before = process(disk); await before.store.save({}, value);
  const after = process(disk); await after.store.load({});
  assert.equal(after.http.forceHttp1, value); assert.equal(after.storage.get(key), value);
}
{
  const f = process(disk); f.state.fail = true;
  await assert.rejects(f.store.save({}, true), /disk failure/);
  assert.equal(f.http.forceHttp1, false); assert.equal(disk.get(key), false);
  f.state.fail = false; await f.store.save({}, true); assert.equal(f.http.forceHttp1, true);
}
{
  const f = process(new Map([[key, false]])); let release;
  f.state.readGate = new Promise(resolve => { release = resolve; });
  const load = f.store.load({}); await Promise.resolve();
  await f.store.save({}, true); release(); await load;
  assert.equal(f.http.forceHttp1, true, 'late startup load cannot override a newer choice');
  await Promise.all([f.store.save({}, false), f.store.save({}, true)]);
  assert.equal(f.http.forceHttp1, true);
}
for (const value of [4, 8, 12]) {
  const f = process(disk);
  await Promise.all([f.store.save({}, true), f.store.saveImageConcurrency({}, value)]);
  const cold = process(disk); await cold.store.load({});
  assert.equal(cold.scheduler.concurrency, value); assert.equal(cold.http.forceHttp1, true);
  assert.equal(cold.storage.get('readerImageConcurrency'), value);
}
{
  const f = process(new Map([['readerImageConcurrency', 12]]));
  await f.store.load({}); f.state.fail = true;
  await assert.rejects(f.store.saveImageConcurrency({}, 8), /disk failure/);
  assert.equal(f.scheduler.concurrency, 12);
}
{
  const f = process(new Map([['readerImageConcurrency', '12']])); await f.store.load({});
  assert.equal(f.scheduler.concurrency, 4);
  let release; f.state.readGate = new Promise(resolve => { release = resolve; });
  const late = f.store.load({}); await Promise.resolve();
  await f.store.saveImageConcurrency({}, 8); release(); await late;
  assert.equal(f.scheduler.concurrency, 8);
}
console.log('network-settings-check: both settings survive restart, failed persistence, write ordering and startup races');
