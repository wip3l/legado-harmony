import assert from 'node:assert/strict';
import test from 'node:test';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';

import { readEtsModule as read } from './lib/ets-module-staging.mjs';
const withoutImports = source => source.replace(/^import\s[\s\S]*?;\r?\n/gm, '').replace(/^export /gm, '');
const access = { READY: 'ready', MEMBER_REQUIRED: 'member', UNSUPPORTED: 'unsupported' };

test('AI color and translation require active membership, including expiry, restriction, debt and logout', async () => {
  const clock = { now: 1800000000000 };
  const values = new Map();
  const sandbox = vm.createContext({
    Date: class extends Date { static now() { return clock.now; } },
    preferences: { getPreferences: async () => ({ put: async () => {}, delete: async () => {}, flush: async () => {} }) },
    AppStorage: { get: key => values.get(key), setOrCreate: (key, value) => values.set(key, value) },
    ReaderComicSuperResolutionAccess: access,
    ComicTextRecognizer: { supported: () => true },
    canIUse: () => true
  });
  for (const file of ['account/AccountCommerceModels.ets', 'account/AccountSessionStore.ets',
    'account/AiAccessPolicy.ets', 'runtime/AiRuntime.ets', 'utils/AppAiHost.ets', 'core/reader/ReaderComicComputeQueue.ts',
    'core/reader/ComicColorizer.ets', 'core/reader/ComicChineseConverter.ets']) {
    vm.runInContext(stripTypeScriptTypes(withoutImports(read(file))), sandbox);
  }
  const { session, color, translation } = vm.runInContext(
    '({ session: AccountSessionStore, color: ComicColorizer, translation: ComicChineseConverter })', sandbox);
  vm.runInContext('AppAiHost.install()', sandbox);
  async function login(sku, options = {}) {
    await session.saveLogin({}, { sessionToken: 'token', account: {
      userId: 'reader', memberVerifiedAt: clock.now, iapDebtPoints: options.debt || 0,
      membership: { active: true, restricted: options.restricted || false, serverNow: clock.now,
        tierSku: sku, state: { sku, expiresAt: clock.now + 1000 } }
    } });
  }
  async function denied() {
    assert.equal(color.memberAllowed(), false);
    assert.equal(translation.access(), access.MEMBER_REQUIRED);
    // 无权限时不得读取图片、缓存或启动 Worker：无需提供这些依赖即可拒绝任务。
    await assert.rejects(color.colorize({}, 'image', () => true, () => {}), /会员专享/);
  }
  await denied();
  for (const sku of ['MONTHLY', 'ANNUAL', 'LIFETIME', 'SUPER_LIFETIME']) {
    await login(sku);
    assert.equal(color.memberAllowed(), true);
    assert.equal(translation.access(), access.READY);
    clock.now += 1000;
    await denied();
  }
  for (const options of [{ restricted: true }, { debt: 1 }]) {
    await login('SUPER_LIFETIME', options);
    await denied();
  }
  await login('MONTHLY');
  await session.clear({});
  await denied();
});

test('translation menu cannot enable unreleased languages or bypass membership/device checks', () => {
  let source = withoutImports(read('components/reader/ReaderComicTranslationRow.ets'));
  source = source.slice(0, source.indexOf('  build()')) + '}';
  source = source.replace('@Component', '').replace('struct ReaderComicTranslationRow', 'class ReaderComicTranslationRow')
    .replace(/@(?:State|Prop)\s+|@StorageProp\('[^']+'\)\s+/g, '');
  const sandbox = vm.createContext({ ReaderComicSuperResolutionAccess: access });
  vm.runInContext(stripTypeScriptTypes(source), sandbox);
  const Row = vm.runInContext('ReaderComicTranslationRow', sandbox);
  const row = new Row();
  const changes = [];
  let membershipPrompts = 0;
  row.onChange = value => { changes.push(value); row.textConvert = value; };
  row.onOpenMembership = () => membershipPrompts++;
  for (const state of Object.values(access)) {
    row.access = state;
    row.textConvert = true;
    for (const index of [-1, 2, 3, 4]) row.selectOption(index);
    assert.equal(row.textConvert, true, 'upcoming/invalid selections preserve saved conversion');
    const before = changes.length;
    row.selectOption(0);
    assert.equal(row.textConvert, false, 'off remains available after expiry or capability loss');
    row.selectOption(1);
    assert.equal(row.textConvert, state === access.READY);
    assert.equal(changes.length - before, state === access.READY ? 2 : 1);
  }
  assert.equal(membershipPrompts, 1);
});

test('translation Select commits only available choices and preserves its value when access is denied', () => {
  const source = read('components/reader/ReaderComicTranslationRow.ets');
  const modifierSource = source.slice(source.indexOf('class TranslationMenuModifier'), source.indexOf('\n@Builder'));
  const sandbox = vm.createContext({ ReaderComicSuperResolutionAccess: access });
  vm.runInContext(stripTypeScriptTypes(modifierSource), sandbox);
  const Modifier = vm.runInContext('TranslationMenuModifier', sandbox);
  for (const state of Object.values(access)) {
    const selections = [];
    let prompts = 0;
    const modifier = new Modifier(state, '#000000', false, () => prompts++);
    for (const index of [-1, 0, 1, 2, 3, 4]) {
      modifier.select({ index, triggerSelect: (selected, value) => selections.push([selected, value]) });
    }
    assert.deepEqual(selections, state === access.READY ? [[0, '关闭'], [1, '繁→简']] : [[0, '关闭']]);
    assert.equal(prompts, state === access.MEMBER_REQUIRED ? 1 : 0);
    assert.equal(modifier.enabled(2), false);
    assert.equal(modifier.enabled(3), false);
    assert.equal(modifier.enabled(1), state !== access.UNSUPPORTED);
  }
});

test('new custom theme badge uses the lowest tier that can hold the requested count', () => {
  const sandbox = vm.createContext({});
  vm.runInContext(stripTypeScriptTypes(withoutImports(read('account/CustomThemeQuota.ets'))), sandbox);
  const quota = vm.runInContext('CustomThemeQuota', sandbox);
  const tiers = ['', 'MONTHLY', 'ANNUAL', 'LIFETIME', 'SUPER_LIFETIME'];
  for (let count = 1; count <= 100; count++) {
    const minimum = quota.minimumForCount(count);
    const tierIndex = tiers.indexOf(minimum);
    assert.ok(quota.forSku(minimum) >= count);
    if (tierIndex > 0) assert.ok(quota.forSku(tiers[tierIndex - 1]) < count);
  }
});
