import assert from 'node:assert/strict';
import test from 'node:test';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';

const root = new URL('../entry/src/main/ets/', import.meta.url);
const key = 'immersiveLightLevel';
const source = fs.readFileSync(new URL('utils/ImmersiveLightSettingsStore.ets', root), 'utf8');
function process(disk = new Map(), initial = 'adaptive') {
  const storage = new Map([[key, initial]]);
  const state = { failFlush: false, blockRead: null, flushes: 0 };
  const sandbox = vm.createContext({ AppStorage: {
    get: name => storage.get(name), setOrCreate: (name, value) => storage.set(name, value)
  }, preferences: { getPreferences: async () => {
    const pending = new Map(disk);
    return {
      get: async (name, fallback) => {
        const value = pending.get(name) ?? fallback;
        if (state.blockRead) await state.blockRead;
        return value;
      },
      put: async (name, value) => pending.set(name, value),
      flush: async () => {
        if (state.failFlush) throw new Error('disk failure');
        state.flushes++;
        for (const [name, value] of pending) disk.set(name, value);
      }
    };
  } } });
  vm.runInContext(stripTypeScriptTypes(source.replace(/^import .*;\r?\n/gm, '').replace('export class', 'class')), sandbox);
  return { store: vm.runInContext('ImmersiveLightSettingsStore', sandbox), storage, disk, state };
}

test('every setting survives a cold process restart even if AppStorage starts at adaptive', async () => {
  const disk = new Map();
  for (const level of ['balanced', 'weak', 'high', 'adaptive']) {
    const before = process(disk);
    await before.store.load({});
    await before.store.save({}, level);
    assert.equal(disk.get(key), level);
    const after = process(disk);
    await after.store.load({});
    assert.equal(after.storage.get(key), level);
  }
});

test('legacy values migrate to durable preferences; corrupt values normalize safely', async () => {
  const old = process(new Map(), 'balanced');
  await old.store.load({});
  assert.equal(old.disk.get(key), 'balanced');
  const corrupt = process(new Map([[key, 'bad-value']]), 'weak');
  await corrupt.store.load({});
  assert.equal(corrupt.storage.get(key), 'adaptive');
});

test('failed flush does not report the setting as applied, and retry recovers', async () => {
  const f = process(new Map([[key, 'balanced']]), 'balanced');
  f.state.failFlush = true;
  await assert.rejects(f.store.save({}, 'weak'), /disk failure/);
  assert.equal(f.storage.get(key), 'balanced');
  assert.equal(f.disk.get(key), 'balanced');
  f.state.failFlush = false;
  await f.store.save({}, 'weak');
  assert.equal(f.storage.get(key), 'weak');
  assert.equal(f.disk.get(key), 'weak');
});

test('rapid saves keep their order and delayed startup reads cannot overwrite a newer choice', async () => {
  const f = process(new Map([[key, 'adaptive']]));
  await Promise.all(['balanced', 'high', 'weak'].map(level => f.store.save({}, level)));
  assert.equal(f.disk.get(key), 'weak');
  let resume;
  f.state.blockRead = new Promise(resolve => { resume = resolve; });
  const loading = f.store.load({});
  await Promise.resolve();
  await f.store.save({}, 'balanced');
  resume();
  await loading;
  assert.equal(f.storage.get(key), 'balanced');
});

test('startup waits for display settings before constructing the page tree', () => {
  const ability = fs.readFileSync(new URL('entryability/EntryAbility.ets', root), 'utf8');
  const startup = ability.match(/Promise\.all\(\[([^\]]+)\]\)\.finally\(\(\) => \{\s*this\.loadStartupContent/);
  assert.ok(startup, 'page construction waits for startup preferences');
  const dependencies = startup[1].split(',').map(value => value.trim());
  for (const name of ['themeBootstrapPromise', 'immersiveLightBootstrapPromise', 'memberSettingsBootstrapPromise']) {
    assert.ok(dependencies.includes(`this.${name}`), `startup waits for ${name}`);
  }
});
