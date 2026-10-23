import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { projectRoot } from './lib/ets-module-staging.mjs';

const read = file => fs.readFileSync(`${projectRoot}/entry/src/main/ets/${file}`, 'utf8');
const compile = text => stripTypeScriptTypes(text.replace(/^import .*;\r?\n/gm, '')
  .replace(/^export /gm, ''), { mode: 'strip' });

function harness() {
  const values = new Map([['appThemeId', 'classic-blue']]);
  const disk = new Map();
  let syncMarks = 0;
  let nextGate;
  const store = {
    get: async (key, fallback) => disk.has(key) ? disk.get(key) : fallback,
    put: async (key, value) => { disk.set(key, value); },
    flush: async () => {}
  };
  const context = vm.createContext({
    console,
    AppStorage: { get: key => values.get(key), setOrCreate: (key, value) => values.set(key, value) },
    preferences: { getPreferences: async () => {
      const gate = nextGate;
      nextGate = undefined;
      if (gate) await gate;
      return store;
    } },
    CloudSyncChangeTracker: { markPreferenceChanged() { syncMarks++; } },
    ReaderThemeHelper: {
      LIGHT_CUSTOM_BACKGROUND_COLOR: '#FFFFFF', LIGHT_CUSTOM_TEXT_COLOR: '#333333',
      DARK_CUSTOM_BACKGROUND_COLOR: '#121212', DARK_CUSTOM_TEXT_COLOR: '#CCCCCC',
      APP_THEME_INDEX: 0, normalizeIndex: value => value || 0
    },
    HexColor: { normalize: (value, fallback) => value || fallback }
  });
  vm.runInContext(compile(read('core/reader/ReaderFontWeight.ts')) + '\n' +
    compile(read('core/reader/ReaderParagraphIndent.ts')) + '\n' +
    compile(read('core/reader/ReaderInfoBarModel.ts')) + '\n' +
    compile(read('utils/ReaderSettingsStore.ets')) +
    '\n' + compile(read('account/ReaderPreferencesSync.ets')) +
    '\nglobalThis.api = { ReaderSettingsStore, ReaderSettings, ReaderInfoBarConfig, ReaderPreferencesSync };', context);
  const coordinator = read('account/CloudSyncCoordinator.ets');
  const remoteStart = coordinator.indexOf('      const remote = JSON.parse(raw) as ReaderPreferencesSyncPayload;');
  const remoteEnd = coordinator.indexOf("    } else if (entityType === 'replace_rule')", remoteStart);
  assert(remoteStart > 0 && remoteEnd > remoteStart);
  vm.runInContext(compile(`async function receive(raw: string): Promise<boolean> {
    const context = {};
    const entityState = { localKey: '' };
    const CloudSyncCoordinator = { readerSettingsBackfillPending: false };
    ${coordinator.slice(remoteStart, remoteEnd)}
    return CloudSyncCoordinator.readerSettingsBackfillPending;
  }
  globalThis.receiveReaderPreferences = receive;`), context);
  const { ReaderSettingsStore: settings, ReaderSettings, ReaderInfoBarConfig: Config } = context.api;
  settings.applyToStorage(new ReaderSettings());
  return { settings, Config, values, disk, context, sync: context.api.ReaderPreferencesSync,
    receive: context.receiveReaderPreferences,
    get syncMarks() { return syncMarks; },
    pauseNextAccess() {
      let release;
      nextGate = new Promise(resolve => { release = resolve; });
      return release;
    }
  };
}

// Execute the real panel event callbacks without ArkUI watchers or a panel-close event.
function openChromePanel(h) {
  const source = read('components/reader/ReaderLayoutSettings.ets');
  const page = read('pages/ReadBook.ets');
  function balanced(text, start, open, close) {
    let depth = 0;
    for (let i = start; i < text.length; i++) {
      if (text[i] === open) depth++;
      if (text[i] === close && --depth === 0) return text.slice(start, i + 1);
    }
    throw new Error('Unbalanced source snippet');
  }
  function method(text, name) {
    const start = text.indexOf(`  ${name}(`);
    assert(start >= 0, name);
    const body = text.indexOf('{', start);
    return text.slice(start, body) + balanced(text, body, '{', '}');
  }
  const calls = [...source.matchAll(/this\.switchItem\(/g)].map(match => {
    const start = match.index + 'this.switchItem'.length;
    return `this.switchItem${balanced(source, start, '(', ')')};`;
  });
  assert.equal(calls.length, 5);
  h.context.getContext = () => ({});
  vm.runInContext(compile(`{
    const page = { ${method(page, 'saveReaderChromeSettings')} };
    class Panel {
      readerHeaderEnabled = AppStorage.get('readerHeaderEnabled');
      readerFooterEnabled = AppStorage.get('readerFooterEnabled');
      readerInfoBarConfig = AppStorage.get('readerInfoBarConfig');
      options = new Map();
      onChanged = (header, footer, raw) => page.saveReaderChromeSettings(header, footer, raw);
      switchItem(options) { this.options.set(options.title, options); }
      ${method(source, 'private config').replace('private ', '')}
      ${method(source, 'private commit').replace('private ', '')}
      ${method(source, 'private notifyChanged').replace('private ', '')}
      buildOptions() { ${calls.join('\n')} }
    }
    globalThis.panel = new Panel();
    globalThis.panel.buildOptions();
  }`), h.context);
  return h.context.panel;
}

const tests = {
  async 'legacy keep-indent switch is ignored when restoring preferences'() {
    for (const keep of [false, true]) {
      const h = harness();
      h.disk.set('readerKeepParagraphIndent', keep);
      h.disk.set('readerThemeProfileV1_classic-blue', JSON.stringify({
        paragraphIndent: 3, keepParagraphIndent: keep
      }));
      const restored = await h.settings.reload({});
      assert.equal(restored.paragraphIndent, 3);
      assert.equal(Object.hasOwn(restored, 'keepParagraphIndent'), false);
      assert.equal(h.values.has('readerKeepParagraphIndent'), false);
    }
  },
  async 'paragraph indent defaults to two and preserves all five choices across reloads'() {
    const h = harness();
    assert.equal((await h.settings.load({})).paragraphIndent, 2);
    for (let chars = 0; chars <= 4; chars++) {
      await h.settings.saveLayoutSettings({}, 20, 12, 0, 18, 18, 18, 18, 0, 'justify', 400, chars);
      assert.equal(h.values.get('readerParagraphIndent'), chars);
      assert.equal(h.disk.get('readerParagraphIndent'), chars);
      assert.equal((await h.settings.reload({})).paragraphIndent, chars);
      // Existing callers that save other typography fields must preserve the indent.
      await h.settings.saveLayoutSettings({}, 24, 14, 3);
      assert.equal((await h.settings.reload({})).paragraphIndent, chars);
    }
  },
  async 'paragraph indent survives saveAll and legacy theme profiles default to two'() {
    const h = harness();
    const initial = await h.settings.load({});
    initial.paragraphIndent = 0;
    await h.settings.saveAll({}, initial);
    assert.equal((await h.settings.reload({})).paragraphIndent, 0);
    h.disk.set('readerThemeProfileV1_legacy', JSON.stringify({ fontSize: 23 }));
    h.values.set('appThemeId', 'legacy');
    assert.equal((await h.settings.switchThemeProfile({}, 'classic-blue', 'legacy')).paragraphIndent, 2);
    h.values.set('appThemeId', 'classic-blue');
    assert.equal((await h.settings.switchThemeProfile({}, 'legacy', 'classic-blue')).paragraphIndent, 0);
  },
  async 'font weight defaults survive legacy settings and profiles'() {
    const h = harness();
    assert.equal((await h.settings.reload({})).fontWeight, 400);
    const legacy = { ...await h.settings.load({}) };
    delete legacy.fontWeight;
    h.disk.set('readerThemeProfileV1_classic-blue', JSON.stringify(legacy));
    assert.equal((await h.settings.reload({})).fontWeight, 400);
    h.disk.delete('readerThemeProfileV1_classic-blue');
    h.disk.set('readerFontWeight', '650');
    assert.equal((await h.settings.reload({})).fontWeight, 700);
    h.disk.delete('readerThemeProfileV1_classic-blue');
    h.disk.set('readerFontWeight', 'invalid');
    assert.equal((await h.settings.reload({})).fontWeight, 400);
  },
  async 'font weight normalizes, persists and survives omitted arguments and font changes'() {
    const h = harness();
    await h.settings.saveLayoutSettings({}, 20, 12, 0, 18, 18, 18, 18, 0, 'justify', 650);
    assert.equal(h.values.get('readerFontWeight'), 700);
    assert.equal(h.disk.get('readerFontWeight'), 700);
    assert.equal((await h.settings.reload({})).fontWeight, 700);
    // Older callers, including applying a theme's layout, must preserve the selected weight.
    await h.settings.saveLayoutSettings({}, 24, 14, 2);
    const style = await h.settings.load({});
    style.bodyFontFamily = 'custom-face';
    await h.settings.saveReaderFontStyleSettings({}, style);
    assert.equal((await h.settings.reload({})).fontWeight, 700);
    assert.equal(h.syncMarks, 0);
    assert.equal('fontWeight' in h.sync.toPayload(style), false);
    assert.equal(h.sync.merge(style, { fontWeight: 100 }).fontWeight, 700);
    style.fontWeight = 300;
    await h.settings.saveAll({}, style);
    assert.equal((await h.settings.reload({})).fontWeight, 300);
  },
  async 'rapid font weight edits retain the latest value across theme switches'() {
    const h = harness();
    const release = h.pauseNextAccess();
    const first = h.settings.saveLayoutSettings({}, 20, 12, 0, 18, 18, 18, 18, 0, 'justify', 500);
    const last = h.settings.saveLayoutSettings({}, 20, 12, 0, 18, 18, 18, 18, 0, 'justify', 800);
    await new Promise(resolve => setImmediate(resolve));
    const reload = h.settings.reload({});
    release();
    await Promise.all([first, last]);
    assert.equal((await reload).fontWeight, 800);
    h.values.set('appThemeId', 'other-theme');
    await h.settings.switchThemeProfile({}, 'classic-blue', 'other-theme');
    await h.settings.saveLayoutSettings({}, 20, 12, 0, 18, 18, 18, 18, 0, 'justify', 200);
    h.values.set('appThemeId', 'classic-blue');
    assert.equal((await h.settings.switchThemeProfile({}, 'other-theme', 'classic-blue')).fontWeight, 800);
    h.values.set('appThemeId', 'other-theme');
    assert.equal((await h.settings.switchThemeProfile({}, 'classic-blue', 'other-theme')).fontWeight, 200);
    h.values.set('appDarkMode', true);
    assert.equal((await h.settings.reload({})).fontWeight, 200);
  },
  async 'open panel switches persist immediately across day/night rebuilds'() {
    const h = harness();
    const switches = [['显示页眉', true], ['页眉分隔线', true],
      ['页脚分隔线', true], ['边距跟随正文', false], ['显示页脚', false]];
    for (const [name, value] of switches) {
      const panel = openChromePanel(h);
      panel.options.get(name).onChange(value);
      h.values.set('appDarkMode', !h.values.get('appDarkMode'));
      // A color-mode refresh rebuilds the controls while the panel remains open.
      const rebuilt = openChromePanel(h);
      assert.equal(rebuilt.options.get(name).checked, value, name);
      const loaded = await h.settings.reload({});
      assert.equal(loaded.readerHeaderEnabled, h.values.get('readerHeaderEnabled'));
      assert.equal(loaded.readerFooterEnabled, h.values.get('readerFooterEnabled'));
      assert.equal(loaded.readerInfoBarConfig, h.values.get('readerInfoBarConfig'));
    }
    const loaded = await h.settings.reload({});
    assert.equal(loaded.readerHeaderEnabled, true);
    assert.equal(loaded.readerFooterEnabled, false);
    const config = h.Config.parse(loaded.readerInfoBarConfig);
    assert.equal(config.headerDivider, true);
    assert.equal(config.footerDivider, true);
    assert.equal(config.followMargin, false);
    assert.equal(h.syncMarks, 0);
  },
  async 'all themes use the reading-preference sync scope'() {
    const coordinator = read('account/CloudSyncCoordinator.ets');
    stripTypeScriptTypes(coordinator, { mode: 'strip' });
    const start = coordinator.indexOf('  private static scopeAllows(');
    const end = coordinator.indexOf('  private static validateResponse(', start);
    const method = coordinator.slice(start, end).replace('private static scopeAllows', 'function scopeAllows');
    const allows = vm.runInNewContext(compile(method) + '\nscopeAllows;');
    const settings = { readingPreferencesEnabled: true, applicationPreferencesEnabled: false };
    for (const type of ['reader_settings', 'replace_rule', 'theme_settings', 'custom_theme_schemes']) {
      assert.equal(allows(settings, type), true, type);
      assert.equal(allows({ ...settings, readingPreferencesEnabled: false,
        applicationPreferencesEnabled: true }, type), false, type);
    }
  },
  async 'legacy cloud receive ignores device settings and keeps rules/themes'() {
    const h = harness();
    await h.settings.saveLayoutSettings({}, 29, 18, 6, 22, 24, 26, 28);
    const config = new h.Config();
    config.footerOffset = 9;
    await h.settings.saveReaderChromeSettings({}, true, true, config.serialize());
    const before = await h.settings.load({});
    const remote = { ...before, fontSize: 14, titleFontSize: 14, marginLeft: 0,
      readerHeaderEnabled: false, readerInfoBarConfig: '', volumeTurnPage: true,
      fontFamily: 'remote-font', fontFilePath: '/remote/font.ttf',
      regexFontEnabled: true, regexFontPattern: 'dialogue', regexFontSize: 24,
      lightCustomThemeBackgroundColor: '#112233' };
    assert.equal(await h.receive(JSON.stringify(remote)), true);
    const after = await h.settings.reload({});
    const allowed = Object.keys(h.sync.toPayload(before));
    for (const key of Object.keys(before).filter(key => !allowed.includes(key) && key !== 'themeIndex')) {
      assert.equal(after[key], before[key], `legacy receive must not change: ${key}`);
    }
    assert.equal(after.regexFontPattern, 'dialogue');
    assert.equal(after.lightCustomThemeBackgroundColor, '#112233');
    assert.equal(await h.receive(JSON.stringify(h.sync.toPayload(after))), false);
  },
  async 'sync payload contains only font rules and themes'() {
    const h = harness();
    const local = await h.settings.load({});
    const payload = h.sync.toPayload(local);
    const allowed = ['syncVersion', 'regexFontEnabled', 'regexFontPattern', 'regexFontMode',
      'regexFontFamily', 'regexFontSize', 'regexShadowColor', 'regexFontRulesRaw',
      'lightThemeIndex', 'darkThemeIndex', 'lightCustomThemeBackgroundColor', 'lightCustomThemeTextColor',
      'darkCustomThemeBackgroundColor', 'darkCustomThemeTextColor', 'customThemesRaw'];
    assert.deepEqual(Object.keys(payload).sort(), allowed.sort());
    const altered = JSON.parse(JSON.stringify(local));
    for (const key of Object.keys(altered).filter(key => !allowed.includes(key))) {
      altered[key] = typeof altered[key] === 'number' ? altered[key] + 3 :
        typeof altered[key] === 'boolean' ? !altered[key] : 'device-specific-value';
    }
    assert.equal(JSON.stringify(h.sync.toPayload(altered)), JSON.stringify(payload));
    const merged = h.sync.merge(local, { ...altered, regexFontPattern: 'dialogue', regexFontEnabled: true });
    for (const key of Object.keys(local).filter(key => !allowed.includes(key))) {
      assert.equal(merged[key], local[key], `legacy cloud field must stay local: ${key}`);
    }
    assert.equal(merged.regexFontPattern, 'dialogue');
    assert.equal(merged.regexFontEnabled, true);
  },
  async 'remote font rules preserve every unrelated local setting'() {
    const h = harness();
    await h.settings.saveLayoutSettings({}, 29, 18, 6, 22, 24, 26, 28);
    const config = new h.Config();
    config.footerOffset = 9;
    await h.settings.saveReaderChromeSettings({}, true, true, config.serialize());
    const before = await h.settings.load({});
    const remote = { ...before, fontSize: 14, titleFontSize: 14, marginLeft: 0,
      readerHeaderEnabled: false, readerInfoBarConfig: '', bodyFontFamily: 'other-device',
      regexFontEnabled: true, regexFontPattern: 'dialogue', regexFontSize: 24,
      regexFontRulesRaw: '{"version":3,"rules":[]}' };
    await h.settings.saveReaderFontRuleSettings({}, remote);
    const after = await h.settings.reload({});
    for (const key of Object.keys(before).filter(key => !key.startsWith('regex'))) {
      assert.equal(after[key], before[key], `font-rule receive must not modify: ${key}`);
    }
    assert.equal(after.regexFontPattern, 'dialogue');
    assert.equal(after.regexFontSize, 24);
    assert.equal(after.regexFontRulesRaw, remote.regexFontRulesRaw);
  },
  async 'local layout edits do not schedule cloud preference sync'() {
    const h = harness();
    await h.settings.saveLayoutSettings({}, 25, 12, 3);
    await h.settings.saveReaderChromeSettings({}, true, true, new h.Config().serialize());
    await h.settings.savePageTurnMode({}, 1);
    await h.settings.saveReadingInteractionSettings({}, true, 5, true);
    const style = await h.settings.load({});
    style.fontSize = 28;
    style.titleFontSize = 30;
    style.bodyFontFamily = 'local-font';
    await h.settings.saveReaderFontStyleSettings({}, style);
    assert.equal(h.syncMarks, 0);
    style.regexFontEnabled = true;
    style.regexFontPattern = 'dialogue';
    await h.settings.saveReaderFontStyleSettings({}, style);
    assert.equal(h.syncMarks, 1);
    const settings = await h.settings.load({});
    await h.settings.saveThemeSettings({}, settings.lightThemeIndex, settings.darkThemeIndex,
      settings.lightCustomThemeBackgroundColor, settings.lightCustomThemeTextColor,
      settings.darkCustomThemeBackgroundColor, settings.darkCustomThemeTextColor, false, settings.customThemesRaw);
    assert.equal(h.syncMarks, 2);
  },
  async 'reload retains the latest rapid typography edit'() {
    const h = harness();
    const release = h.pauseNextAccess();
    const first = h.settings.saveLayoutSettings({}, 24, 12, 0);
    const last = h.settings.saveLayoutSettings({}, 29, 18, 6);
    await new Promise(resolve => setImmediate(resolve));
    const reload = h.settings.reload({});
    await new Promise(resolve => setImmediate(resolve));
    release();
    await Promise.all([first, last]);
    const loaded = await reload;
    assert.equal(loaded.fontSize, 29);
    assert.equal(loaded.lineHeight, 18);
    assert.equal(loaded.paragraphSpacing, 6);
  },
  async 'reload waits for pending header/footer writes'() {
    const h = harness();
    await h.settings.saveReaderChromeSettings({}, false, true, new h.Config().serialize());
    const config = new h.Config();
    config.headerLeft = 'book';
    config.footerOffset = 9;
    config.progressBar = 'footer';
    const release = h.pauseNextAccess();
    const save = h.settings.saveReaderChromeSettings({}, true, true, config.serialize());
    // Let the queued write reach the paused preferences access.
    await new Promise(resolve => setImmediate(resolve));
    const reload = h.settings.reload({});
    await new Promise(resolve => setImmediate(resolve));
    release();
    await save;
    const loaded = await reload;
    assert.equal(loaded.readerHeaderEnabled, true);
    assert.equal(h.Config.parse(loaded.readerInfoBarConfig).footerOffset, 9);
    assert.equal(h.Config.parse(loaded.readerInfoBarConfig).progressBar, 'footer');
  },
  async 'late unrelated save preserves newer layout and header/footer settings'() {
    const h = harness();
    const release = h.pauseNextAccess();
    const oldSave = h.settings.savePreloadEnabled({}, false);
    const config = new h.Config();
    config.headerLeft = 'book';
    config.footerOffset = 7;
    await h.settings.saveReaderChromeSettings({}, true, true, config.serialize());
    await h.settings.saveLayoutSettings({}, 27, 16, 4, 21, 23, 25, 26, 2, 'start');
    release();
    await oldSave;
    // Simulate returning to the reader after switching day/night mode.
    h.values.set('appDarkMode', true);
    let loaded = await h.settings.reload({});
    assert.equal(loaded.fontSize, 27);
    assert.equal(h.Config.parse(loaded.readerInfoBarConfig).footerOffset, 7);
    h.values.set('appDarkMode', false);
    loaded = await h.settings.reload({});
    assert.equal(loaded.fontSize, 27);
    assert.equal(loaded.preloadEnabled, false);
    assert.equal(loaded.readerHeaderEnabled, true);
  },
  async 'obsidian uses 3D once and preserves subsequent manual choices'() {
    const h = harness();
    await h.settings.load({});
    h.values.set('appThemeId', 'obsidian-archive');
    let settings = await h.settings.switchThemeProfile({}, 'classic-blue', 'obsidian-archive');
    assert.equal(settings.pageTurnAnimationType, 7);
    assert.notEqual(settings.pageTurnMode, 0);
    await h.settings.savePageTurnAnimationType({}, 1);
    settings = await h.settings.reload({});
    assert.equal(settings.pageTurnAnimationType, 1);
    h.values.set('appThemeId', 'classic-blue');
    settings = await h.settings.switchThemeProfile({}, 'obsidian-archive', 'classic-blue');
    assert.equal(settings.pageTurnAnimationType, 1);
  },
  async 'existing obsidian profile upgrades without altering typography'() {
    const h = harness();
    h.disk.set('readerThemeProfileV1_obsidian-archive', JSON.stringify({
      pageTurnMode: 0, pageTurnAnimationType: 4, fontSize: 27
    }));
    h.values.set('appThemeId', 'obsidian-archive');
    const settings = await h.settings.reload({});
    assert.equal(settings.pageTurnMode, 2);
    assert.equal(settings.pageTurnAnimationType, 7);
    assert.equal(settings.fontSize, 27);
    assert.equal((await h.settings.reload({})).pageTurnAnimationType, 7);
  },
  async 'theme profiles remain independent after queued saves'() {
    const h = harness();
    await h.settings.saveLayoutSettings({}, 27, 16, 4);
    h.values.set('appThemeId', 'other-theme');
    await h.settings.switchThemeProfile({}, 'classic-blue', 'other-theme');
    await h.settings.saveLayoutSettings({}, 19, 10, 2);
    const config = new h.Config();
    config.headerLeft = 'book';
    const release = h.pauseNextAccess();
    const save = h.settings.saveReaderChromeSettings({}, true, true, config.serialize());
    await new Promise(resolve => setImmediate(resolve));
    h.values.set('appThemeId', 'classic-blue');
    const switched = h.settings.switchThemeProfile({}, 'other-theme', 'classic-blue');
    release();
    await save;
    assert.equal((await switched).fontSize, 27);
    h.values.set('appThemeId', 'other-theme');
    const loaded = await h.settings.switchThemeProfile({}, 'classic-blue', 'other-theme');
    assert.equal(loaded.fontSize, 19);
    assert.equal(loaded.readerHeaderEnabled, true);
    assert.equal(h.Config.parse(loaded.readerInfoBarConfig).headerLeft, 'book');
  }
};

let failures = 0;
for (const [name, test] of Object.entries(tests)) {
  try { await test(); console.log(`PASS: ${name}`); }
  catch (error) { failures++; console.error(`FAIL: ${name}\n${error.stack}`); }
}
if (failures) process.exitCode = 1;
