import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';
import { stripTypeScriptTypes } from 'node:module';

function pageFixture(file, methods) {
  const source = fs.readFileSync(new URL(`../entry/src/main/ets/pages/${file}.ets`, import.meta.url), 'utf8');
  const state = { succeeds: true, saves: 0, applied: [], notices: [] };
  const context = vm.createContext({
    ReaderFontItem: class {},
    ReaderCustomFontItem: class {},
    ReaderFontHelper: {
      registerFont: (_ctx, item) => ({ registered: state.succeeds, familyName: `runtime:${item.filePath}`, filePath: item.filePath }),
      resolveDisplayName: name => name,
      fontFileExists: path => !!path && path !== '/missing.ttf'
    },
    HdsFeedback: { showToast: message => state.notices.push(message) }
  });
  const body = methods.map(name => {
    const match = source.match(new RegExp(`^  ${name}\\([\\s\\S]*?^  }`, 'm'));
    assert.ok(match, `${file}.${name}`);
    return match[0];
  }).join(',\n');
  vm.runInContext(stripTypeScriptTypes(`globalThis.page = {${body}}`, { mode: 'strip' }), context);
  const page = context.page;
  Object.assign(page, {
    readerFontMode: 'system', readerFontFamily: '', readerFontFilePath: '', readerFontSourceName: '跟随主题',
    readerActiveFontFamily: '', readerFontRegistered: false, previewFontRenderVersion: 0,
    registeredFontFamilies: new Map(),
    getUIContext: () => ({}), familyNameForPath: path => `stable:${path}`, fontFileExists: () => true,
    reloadCustomFonts() {}, rememberCurrentSystemFont() {},
    saveFontSettings: () => state.saves++,
    // applyApplicationFont() 不带参数，读页面当前状态：记下调用时生效的字体。
    applyApplicationFont() { state.applied.push(this.readerActiveFontFamily); }
  });
  return { page, state };
}

for (const file of ['FontSettings', 'Settings']) {
  test(`${file}: selecting A then B updates the active font; failed registration preserves selection`, () => {
    const { page, state } = pageFixture(file, ['registerCustomFont', 'selectCustomFont']);
    const a = { familyName: 'A', filePath: '/a.ttf', sourceName: '字体 A' };
    const b = { familyName: 'B', filePath: '/b.ttf', sourceName: '字体 B' };
    state.succeeds = false;
    page.selectCustomFont(a);
    assert.equal(page.readerFontMode, 'system');
    assert.equal(state.saves, 0);
    state.succeeds = true;
    page.selectCustomFont(a);
    page.selectCustomFont(b);
    assert.equal(page.readerFontFilePath, '/b.ttf');
    assert.equal(page.readerActiveFontFamily, 'runtime:/b.ttf');
    assert.equal(page.readerFontRegistered, true);
    assert.equal(page.readerFontMode, 'custom');
    assert.deepEqual(state.applied, ['runtime:/a.ttf', 'runtime:/b.ttf']);
    state.succeeds = false;
    page.selectCustomFont({ familyName: 'C', filePath: '/bad.ttf', sourceName: '损坏字体' });
    assert.equal(page.readerFontFilePath, '/b.ttf');
    assert.equal(page.readerActiveFontFamily, 'runtime:/b.ttf');
    assert.equal(state.saves, 2);
    assert.match(state.notices.at(-1), /注册失败/);
  });
}

test('font manager reports failed registration as failure instead of returning the system family', () => {
  const { page, state } = pageFixture('CustomFontManager', ['registerCustomFont']);
  page.readerSystemFontFamily = 'HarmonyOS Sans';
  state.succeeds = false;
  assert.equal(page.registerCustomFont({ filePath: '/bad.ttf', familyName: 'bad', sourceName: 'bad' }), '');
  assert.equal(page.readerFontRegistered, false);
});

test('reader body/title/rule selection rejects bad fonts and filters missing local files', () => {
  const { page, state } = pageFixture('ReaderFontSettings', ['registerCustomFont', 'modeAndFamilyByIndex', 'customFonts']);
  page.readerCustomFontsRaw = JSON.stringify({ fonts: [
    { familyName: 'A', filePath: '/a.ttf', sourceName: 'A' },
    { familyName: 'missing', filePath: '/missing.ttf', sourceName: '已删除' }
  ] });
  assert.equal(page.customFonts().length, 1);
  assert.equal(page.customFonts()[0].filePath, '/a.ttf');
  state.succeeds = false;
  assert.equal(page.modeAndFamilyByIndex(2).length, 0);
  assert.match(state.notices.at(-1), /注册失败/);
  state.succeeds = true;
  assert.deepEqual(Array.from(page.modeAndFamilyByIndex(2)), ['custom', 'runtime:/a.ttf']);
  assert.deepEqual(Array.from(page.modeAndFamilyByIndex(0)), ['global', '']);
  assert.deepEqual(Array.from(page.modeAndFamilyByIndex(1)), ['system', '']);
});
