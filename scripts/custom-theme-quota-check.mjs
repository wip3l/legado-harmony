import assert from 'node:assert/strict';
import test from 'node:test';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';

function fixture() {
  const clock = { now: 1800000000000 };
  const values = new Map(), stores = new Map(), deletedProfiles = [];
  const sandbox = vm.createContext({
    Date: class extends Date { static now() { return clock.now; } },
    preferences: { getPreferences: async (_context, name) => {
      if (!stores.has(name)) stores.set(name, new Map());
      const data = stores.get(name);
      return { get: async (key, fallback) => data.get(key) ?? fallback,
        put: async (key, value) => data.set(key, value), delete: async key => data.delete(key),
        flush: async () => {} };
    } },
    AppStorage: { get: key => values.get(key), setOrCreate: (key, value) => values.set(key, value) },
    ThemeIds: { CUSTOM: 'custom' },
    AppThemeSettings: class {},
    AppThemeSettingsStore: { cloneSettings: value => structuredClone(value), createForTheme: () => ({}) },
    CloudSyncChangeTracker: { markPreferenceChanged: () => {} },
    ReaderSettingsStore: { profileIdFor: (themeId, schemeId) => `${themeId}__${schemeId}`,
      deleteProfile: async (_context, id) => { deletedProfiles.push(id); } }
  });
  for (const file of ['account/AccountCommerceModels.ets', 'account/AccountSessionStore.ets',
    'account/CustomThemeQuota.ets', 'utils/CustomThemeSchemeStore.ets']) {
    const source = fs.readFileSync(new URL('../entry/src/main/ets/' + file, import.meta.url), 'utf8');
    vm.runInContext(stripTypeScriptTypes(source.replace(/^import\s[\s\S]*?;\r?\n/gm, '')
      .replace(/^export /gm, ''), { mode: 'strip' }), sandbox);
  }
  const { session, quota, schemes } = vm.runInContext(
    '({session: AccountSessionStore, quota: CustomThemeQuota, schemes: CustomThemeSchemeStore})', sandbox);
  async function login(sku, options = {}) {
    await session.saveLogin({}, { sessionToken: 'token', account: {
      userId: 'user', memberVerifiedAt: clock.now, iapDebtPoints: options.debt || 0,
      membership: { active: true, restricted: options.restricted || false, serverNow: clock.now,
        tierSku: options.tierSku || sku,
        state: { sku, expiresAt: options.expiresAt ?? null } }
    } });
  }
  return { clock, session, quota, schemes, login, deletedProfiles };
}

for (const [sku, limit] of [['', 5], ['MONTHLY', 10], ['ANNUAL', 20], ['LIFETIME', 50], ['SUPER_LIFETIME', 100]]) {
  test(`${sku || 'free'} can create exactly ${limit} schemes and retains them after reload`, async () => {
    const f = fixture();
    if (sku) await f.login(sku);
    assert.equal(f.quota.current(), limit);
    await f.schemes.load({}, {});
    for (let index = 1; index < limit; index++) assert.ok(await f.schemes.add({}, {}));
    assert.equal(await f.schemes.add({}, {}), null);
    const saved = await f.schemes.load({}, {});
    assert.equal(saved.length, limit);
    assert.equal(new Set(saved.map(item => item.id)).size, limit);
    assert.equal(new Set(saved.map(item => item.name)).size, limit);
    assert.equal(await f.schemes.delete({}, {}, saved.at(-1).id), true);
    assert.ok(await f.schemes.add({}, {}));
  });
}

test('quota follows active coverage, expiry, restriction, debt and logout', async () => {
  const f = fixture();
  await f.login('MONTHLY', { tierSku: 'ANNUAL', expiresAt: f.clock.now + 1000 });
  assert.equal(f.quota.current(), 20);
  f.clock.now += 1000;
  assert.equal(f.quota.current(), 5);
  await f.login('SUPER_LIFETIME', { restricted: true });
  assert.equal(f.quota.current(), 5);
  await f.login('LIFETIME', { debt: 1 });
  assert.equal(f.quota.current(), 5);
  await f.login('unknown');
  assert.equal(f.quota.current(), 5);
  await f.login('SUPER_LIFETIME');
  assert.equal(f.quota.current(), 100);
  await f.session.clear({});
  assert.equal(f.quota.current(), 5);
});

test('downgrade preserves loaded/synced schemes, editing and active selection; upgrade restores creation', async () => {
  const f = fixture();
  await f.login('MONTHLY');
  for (let index = 1; index < 10; index++) await f.schemes.add({}, {});
  const original = await f.schemes.load({}, {});
  await f.schemes.setActiveScheme({}, original[9]);
  await f.session.clear({});
  assert.equal((await f.schemes.load({}, {})).length, 10);
  assert.equal(await f.schemes.add({}, {}), null);
  assert.equal(await f.schemes.rename({}, {}, original[9].id, '保留的方案'), true);
  original[9].settings.customLightAccentColor = '#123456';
  await f.schemes.saveScheme({}, {}, original[9]);
  assert.equal((await f.schemes.load({}, {}))[9].settings.customLightAccentColor, '#123456');
  const incoming = Array.from({ length: 100 }, (_, index) => ({
    id: `remote_${index}`, name: `远程方案 ${index}`, revision: 1, settings: {}
  }));
  await f.schemes.replaceFromSync({}, {}, incoming);
  assert.equal((await f.schemes.load({}, {})).length, 100);
  assert.equal(await f.schemes.add({}, {}), null);
  await f.schemes.replaceFromSync({}, {}, original);
  await f.login('ANNUAL');
  assert.ok(await f.schemes.add({}, {}));
});

test('deleting a scheme drops its own reader profile', async () => {
  const f = fixture();
  await f.schemes.load({}, {});
  const added = await f.schemes.add({}, {});
  assert.equal(await f.schemes.delete({}, {}, added.id), true);
  assert.deepEqual(f.deletedProfiles, [`custom__${added.id}`]);
});

test('imported schemes count toward the quota, keep the author and can replace an existing scheme', async () => {
  const f = fixture();
  const first = (await f.schemes.load({}, {}))[0];
  for (let index = 1; index < 5; index++) assert.ok(await f.schemes.add({}, {}));
  assert.equal(await f.schemes.addImported({}, {}, '分享主题', {}, '作者甲', ''), null);
  const replaced = await f.schemes.addImported({}, {}, '自定义主题 2', {}, '作者甲', first.id);
  assert.equal(replaced.id, first.id);
  assert.equal(replaced.revision, first.revision + 1);
  assert.equal(replaced.author, '作者甲');
  // 同名方案自动加序号；替换的那套不算重名。
  assert.equal(replaced.name, '自定义主题 2 (2)');
  const saved = await f.schemes.load({}, {});
  assert.equal(saved.length, 5);
  assert.equal(saved.find(item => item.id === first.id).author, '作者甲');
  await f.schemes.rename({}, {}, first.id, '改名后');
  assert.equal((await f.schemes.load({}, {})).find(item => item.id === first.id).author, '作者甲');
  assert.equal(await f.schemes.addImported({}, {}, 'x', {}, '', 'missing'), null);
  await f.login('MONTHLY');
  const added = await f.schemes.addImported({}, {}, '分享主题', {}, '', '');
  assert.ok(added.id.endsWith('_import'));
  assert.equal(added.author, '');
});
