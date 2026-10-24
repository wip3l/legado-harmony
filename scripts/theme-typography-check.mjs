import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { pathToFileURL } from 'node:url';
import { projectRoot } from './lib/ets-module-staging.mjs';

// 主题排版页：排版写进某套自定义主题的阅读档案、记为已绑定，切换到该主题时随档案生效。

const read = file => fs.readFileSync(`${projectRoot}/entry/src/main/ets/${file}`, 'utf8');
const compile = text => stripTypeScriptTypes(text.replace(/^import .*;\r?\n/gm, '')
  .replace(/^export /gm, ''), { mode: 'strip' });
const APP_THEME_INDEX = 4;
const format = await import(pathToFileURL(
  `${projectRoot}/entry/src/main/ets/theme/share/ThemePackageFormat.ts`).href);

function harness() {
  const values = new Map([['appThemeId', 'classic-blue']]);
  const disk = new Map();
  let syncMarks = 0;
  const store = {
    get: async (key, fallback) => disk.has(key) ? disk.get(key) : fallback,
    put: async (key, value) => { disk.set(key, value); },
    delete: async key => { disk.delete(key); },
    flush: async () => {}
  };
  const context = vm.createContext({
    console,
    AppStorage: { get: key => values.get(key), setOrCreate: (key, value) => values.set(key, value) },
    preferences: { getPreferences: async () => store },
    CloudSyncChangeTracker: { markPreferenceChanged() { syncMarks++; } },
    ReaderThemeHelper: {
      LIGHT_CUSTOM_BACKGROUND_COLOR: '#FFFFFF', LIGHT_CUSTOM_TEXT_COLOR: '#333333',
      DARK_CUSTOM_BACKGROUND_COLOR: '#121212', DARK_CUSTOM_TEXT_COLOR: '#CCCCCC',
      APP_THEME_INDEX, normalizeIndex: value => value || 0
    },
  });
  vm.runInContext(compile(read('utils/HexColor.ts')) + '\n' +
    compile(read('core/reader/ReaderCommentBubbleSize.ts')) + '\n' +
    compile(read('core/reader/ReaderFontWeight.ts')) + '\n' +
    compile(read('core/reader/ReaderParagraphIndent.ts')) + '\n' +
    compile(read('core/reader/ReaderInfoBarModel.ts')) + '\n' +
    compile(read('utils/ReaderSettingsStore.ets')) + '\n' +
    compile(read('utils/ThemeTypographyDraft.ets')) +
    '\nglobalThis.api = { ReaderSettingsStore, ReaderSettings, ReaderInfoBarConfig, ThemeTypographyDraft };', context);
  const { ReaderSettingsStore: settings, ReaderSettings, ReaderInfoBarConfig: Config, ThemeTypographyDraft } =
    context.api;
  settings.applyToStorage(new ReaderSettings());
  return { settings, ReaderSettings, Config, ThemeTypographyDraft, values, disk,
    get syncMarks() { return syncMarks; } };
}

function typography(h) {
  const source = new h.ReaderSettings();
  source.fontSize = 26;
  source.fontWeight = 550;
  source.letterSpacing = 2;
  source.textAlign = 'start';
  source.lineHeight = 20;
  source.paragraphSpacing = 9;
  source.paragraphIndent = 1;
  source.marginLeft = 30;
  source.marginRight = 31;
  source.marginTop = 40;
  source.marginBottom = 41;
  source.extendToStatusBar = true;
  source.readerHeaderEnabled = true;
  source.readerFooterEnabled = false;
  const config = new h.Config();
  config.headerOffset = 12;
  source.readerInfoBarConfig = config.serialize();
  source.bodyFontMode = 'custom';
  source.bodyFontFamily = 'theme-body';
  source.titleFontMode = 'system';
  source.titleFontSize = 30;
  source.regexFontEnabled = true;
  source.regexFontRulesRaw = '{"schemaVersion":3,"rules":[]}';
  // 不属于排版的字段不能被带进档案。
  source.pageTurnMode = 2;
  source.fontFamily = 'should-not-copy';
  source.volumeTurnPage = true;
  return source;
}

function assertTypography(actual) {
  assert.equal(actual.fontSize, 26);
  assert.equal(actual.fontWeight, 550);
  assert.equal(actual.letterSpacing, 2);
  assert.equal(actual.textAlign, 'start');
  assert.equal(actual.lineHeight, 20);
  assert.equal(actual.paragraphSpacing, 9);
  assert.equal(actual.paragraphIndent, 1);
  assert.equal(actual.marginLeft, 30);
  assert.equal(actual.marginRight, 31);
  assert.equal(actual.marginTop, 40);
  assert.equal(actual.marginBottom, 41);
  assert.equal(actual.extendToStatusBar, true);
  assert.equal(actual.readerHeaderEnabled, true);
  assert.equal(actual.readerFooterEnabled, false);
  assert.equal(JSON.parse(actual.readerInfoBarConfig).headerOffset, 12);
  assert.equal(actual.bodyFontMode, 'custom');
  assert.equal(actual.bodyFontFamily, 'theme-body');
  assert.equal(actual.titleFontMode, 'system');
  assert.equal(actual.titleFontSize, 30);
  assert.equal(actual.regexFontEnabled, true);
}

const SCHEME_PROFILE = 'custom__custom_1';

const tests = {
  async 'saving an inactive scheme writes only its profile and marks it bound'() {
    const h = harness();
    await h.settings.saveLayoutSettings({}, 20, 12, 0);
    const existing = new h.ReaderSettings();
    existing.pageTurnMode = 0;
    existing.lightThemeIndex = 2;
    h.disk.set(`readerThemeProfileV1_${SCHEME_PROFILE}`, JSON.stringify(existing));
    assert.equal(await h.settings.isTypographyBound({}, SCHEME_PROFILE), false);

    await h.settings.saveTypographyToProfile({}, SCHEME_PROFILE, typography(h));

    const saved = JSON.parse(h.disk.get(`readerThemeProfileV1_${SCHEME_PROFILE}`));
    assertTypography(saved);
    assert.equal(saved.pageTurnMode, 0, 'unrelated settings in the scheme profile stay');
    assert.equal(saved.lightThemeIndex, 2);
    assert.equal(saved.volumeTurnPage, false);
    assert.notEqual(saved.fontFamily, 'should-not-copy');
    assert.equal(await h.settings.isTypographyBound({}, SCHEME_PROFILE), true);
    // 正在使用的主题完全不受影响。
    assert.equal(h.values.get('readerFontSize'), 20);
    assert.equal(h.values.get('readerHeaderEnabled'), false);
    assert.equal((await h.settings.load({})).fontSize, 20);
    assert.equal(h.syncMarks, 0, 'typography stays device-local like other layout edits');
  },

  async 'a scheme without a profile copies current settings and follows the theme background'() {
    const h = harness();
    await h.settings.savePageTurnMode({}, 0);
    await h.settings.saveTypographyToProfile({}, 'custom__fresh', typography(h));
    const saved = JSON.parse(h.disk.get('readerThemeProfileV1_custom__fresh'));
    assertTypography(saved);
    assert.equal(saved.pageTurnMode, 0);
    assert.equal(saved.themeIndex, APP_THEME_INDEX);
    assert.equal(saved.lightThemeIndex, APP_THEME_INDEX);
    assert.equal(saved.darkThemeIndex, APP_THEME_INDEX);
  },

  async 'switching to a bound scheme applies its typography but keeps the global font'() {
    const h = harness();
    await h.settings.saveFontSettings({}, 'global-face', '/fonts/a.ttf', 'A', 'custom', '', '');
    await h.settings.saveTypographyToProfile({}, SCHEME_PROFILE, typography(h));
    h.values.set('appThemeId', 'custom');
    h.values.set('activeCustomThemeSchemeId', 'custom_1');
    const next = await h.settings.switchThemeProfile({}, 'classic-blue', SCHEME_PROFILE);
    assertTypography(next);
    assert.equal(next.fontFamily, 'global-face');
    assert.equal(h.values.get('readerFontSize'), 26);
    assert.equal(h.values.get('readerHeaderEnabled'), true);
    assert.equal(h.values.get('readerBodyFontFamily'), 'theme-body');
    assert.equal(h.values.get('readerExtendToStatusBar'), true);
    h.values.set('appThemeId', 'classic-blue');
    const back = await h.settings.switchThemeProfile({}, SCHEME_PROFILE, 'classic-blue');
    assert.equal(back.fontSize, 20);
    assert.equal(back.readerHeaderEnabled, false);
  },

  async 'saving the active scheme updates the live settings immediately'() {
    const h = harness();
    h.values.set('appThemeId', 'custom');
    h.values.set('activeCustomThemeSchemeId', 'custom_1');
    await h.settings.reload({});
    await h.settings.saveReadingInteractionSettings({}, true, 5, false);
    await h.settings.saveTypographyToProfile({}, SCHEME_PROFILE, typography(h));
    assert.equal(h.values.get('readerFontSize'), 26);
    assert.equal(h.values.get('readerFontWeight'), 550);
    assert.equal(h.values.get('readerHeaderEnabled'), true);
    assert.equal(h.values.get('readerFooterEnabled'), false);
    assert.equal(h.values.get('readerTitleFontSize'), 30);
    assert.equal(h.values.get('readerExtendToStatusBar'), true);
    const reloaded = await h.settings.reload({});
    assertTypography(reloaded);
    assert.equal(reloaded.volumeTurnPage, true, 'other interaction settings are kept');
    assert.equal(reloaded.screenTimeoutMinutes, 5);
    assert.equal(await h.settings.isTypographyBound({}, SCHEME_PROFILE), true);
  },

  async 'deleting a scheme profile forgets the binding'() {
    const h = harness();
    await h.settings.saveTypographyToProfile({}, SCHEME_PROFILE, typography(h));
    await h.settings.deleteProfile({}, SCHEME_PROFILE);
    assert.equal(h.disk.has(`readerThemeProfileV1_${SCHEME_PROFILE}`), false);
    assert.equal(await h.settings.isTypographyBound({}, SCHEME_PROFILE), false);
  },

  async 'every field the layout page saves travels in a theme package'() {
    // 主题排版页保存的字段（copyTypography 写的那些）里，除强调规则另走 emphasis 外都必须在 LAYOUT_KEYS 里，
    // 否则导出到别的设备后会丢。
    const source = read('utils/ReaderSettingsStore.ets').replace(/\r\n/g, '\n');
    const start = source.indexOf('  static copyTypography(');
    const body = source.slice(start, source.indexOf('\n  }\n', start));
    const copied = [...body.matchAll(/target\.(\w+) =/g)].map(match => match[1]);
    assert(copied.length >= 20, 'copyTypography fields found');
    const missing = copied.filter(key => !format.LAYOUT_KEYS.includes(key));
    assert.deepEqual(missing, [], `fields lost on export: ${missing.join(', ')}`);
    assert(body.includes('updateFontRules(target, source)'), 'regex rules are copied separately');

    const h = harness();
    const exported = format.pickLayout(JSON.parse(JSON.stringify(typography(h))));
    const target = JSON.parse(JSON.stringify(new h.ReaderSettings()));
    format.applyLayout(target, JSON.parse(JSON.stringify(exported)));
    assertTypography({ ...target, regexFontEnabled: true });
    assert.equal(target.pageTurnMode, new h.ReaderSettings().pageTurnMode, 'page turning does not travel');
    assert.equal(target.volumeTurnPage, false);
  },

  async 'font page draft only takes the fields it manages'() {
    const h = harness();
    const draft = typography(h);
    h.ThemeTypographyDraft.begin(draft);
    const revision = h.ThemeTypographyDraft.revision();
    const fontPage = new h.ReaderSettings();
    fontPage.fontSize = 18;
    fontPage.bodyFontMode = 'global';
    fontPage.titleFontSize = 24;
    fontPage.regexFontEnabled = false;
    fontPage.marginLeft = 0;
    h.ThemeTypographyDraft.applyFontStyle(fontPage);
    const current = h.ThemeTypographyDraft.current();
    assert.notEqual(h.ThemeTypographyDraft.revision(), revision);
    assert.equal(current.fontSize, 18);
    assert.equal(current.bodyFontMode, 'global');
    assert.equal(current.bodyFontFamily, '');
    assert.equal(current.titleFontSize, 24);
    assert.equal(current.regexFontEnabled, false);
    assert.equal(current.marginLeft, 30, 'layout fields are not touched by the font page');
    h.ThemeTypographyDraft.end();
    assert.equal(h.ThemeTypographyDraft.current(), null);
  }
};

let failed = 0;
for (const [name, test] of Object.entries(tests)) {
  try {
    await test();
    console.log(`PASS: ${name}`);
  } catch (e) {
    failed++;
    console.error(`FAIL: ${name}`);
    console.error(e);
  }
}
if (failed > 0) process.exit(1);
