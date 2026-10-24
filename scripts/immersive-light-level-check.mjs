import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';
import { stripTypeScriptTypes } from 'node:module';

const root = new URL('../entry/src/main/ets/', import.meta.url);
const read = file => fs.readFileSync(new URL(file, root), 'utf8');
const compile = source => stripTypeScriptTypes(source.replace(/^import .*;\r?\n/gm, '')
  .replace(/^export /gm, ''), { mode: 'strip' });

function harness(api = 26, supported = true) {
  const state = { level: 'adaptive', opened: [], closed: [], nativeMaterials: 0 };
  const empty = Object.freeze({ empty: true });
  const sandbox = vm.createContext({
    console,
    deviceInfo: { sdkApiVersion: api },
    AppStorage: { get: key => key === 'immersiveLightLevel' ? state.level : false },
    uiMaterial: {
      Material: { empty },
      isImmersiveMaterialSupported: () => supported,
      ImmersiveStyle: { ULTRA_THIN: 'thin', REGULAR: 'regular', THICK: 'thick' },
      ImmersiveMaterial: class { constructor(options) { state.nativeMaterials++; Object.assign(this, options); } }
    },
    hdsMaterial: {
      getSystemMaterialTypes: () => ['immersive'],
      MaterialType: { IMMERSIVE: 'immersive', NONE: 'none', ADAPTIVE: 'adaptive' },
      MaterialLevel: { EXQUISITE: 'high', GENTLE: 'balanced', SMOOTH: 'weak', ADAPTIVE: 'adaptive' }
    },
    ThemeRuntime: { glassPanelColor: () => '#80FFFFFF', cardColor: dark => dark ? '#222222' : '#FFFFFF' },
    Color: { Transparent: 'transparent' },
    BlurStyle: { COMPONENT_THICK: 'blur', NONE: 'none' },
    DialogAlignment: { Center: 'center' }
  });
  vm.runInContext(compile(read('utils/ImmersiveMaterialRuntime.ets')) + '\n' +
    compile(read('utils/SystemDialogSession.ets')) +
    '\nglobalThis.api = { ImmersiveMaterialRuntime, SystemDialogSession };', sandbox);
  const prompt = {
    openCustomDialog: async options => { state.opened.push(options); return state.opened.length; },
    closeCustomDialog: id => state.closed.push(id)
  };
  return { ...sandbox.api, state, empty, uiContext: { getPromptAction: () => prompt } };
}

test('manual weak/balanced disable native refraction across every popup, sheet, select and component', () => {
  const { ImmersiveMaterialRuntime: runtime, state, empty } = harness();
  for (const level of ['weak', 'balanced']) {
    state.level = level;
    assert.equal(runtime.materialLevel(level), level);
    const popup = runtime.popupMenuOptions(level, () => {}, 'bottom', false, '#123456', () => {});
    const context = runtime.contextMenuOptions(level, '#123456', () => {});
    const sheet = runtime.applySheetMaterial(level, {}, false, '#123456');
    let select, color, blur;
    runtime.selectMenuModifier(level).applyNormalAttribute({ menuOutline: () => {}, menuSystemMaterial: value => { select = value; },
      menuBackgroundColor: value => { color = value; }, menuBackgroundBlurStyle: value => { blur = value; } });
    for (const material of [popup.systemMaterial, context.systemMaterial, sheet.systemMaterial, select,
      runtime.componentMaterial({ interactive: true }, level)]) assert.equal(material, empty);
    const expectedColor = level === 'weak' ? '#FFFFFF' : '#80FFFFFF';
    for (const surface of [popup.popupColor, context.backgroundColor, sheet.backgroundColor, color]) {
      assert.equal(surface, expectedColor);
    }
    const expectedBlur = level === 'weak' ? 'none' : 'blur';
    assert.equal(blur, expectedBlur);
    assert.equal(popup.backgroundBlurStyle, expectedBlur);
    assert.equal(sheet.blurStyle, expectedBlur);
    assert.equal(runtime.surfaceColor('weak', true, '#123456'), '#123456', 'reader solid theme retained');
  }
  assert.equal(state.nativeMaterials, 0, 'no native immersive material may leak into reduced modes');
});

test('follow-system and high restore native materials after leaving a manual reduced mode', () => {
  const { ImmersiveMaterialRuntime: runtime, state, empty } = harness();
  for (const level of ['weak', 'adaptive', 'balanced', 'high', 'adaptive']) {
    state.level = level;
    const material = runtime.sheetMaterial('#123456');
    if (runtime.reducedMaterial(level)) assert.equal(material, empty);
    else {
      assert.notEqual(material, empty);
      assert.equal(material.style, 'regular');
      assert.equal(material.lightEffect.color, level === 'high' ? '#88123456' : '#55123456');
      assert.equal(runtime.surfaceColor(level, false), '#80FFFFFF');
      assert.equal(runtime.surfaceBlur(level), 'none');
    }
  }
  state.level = 'high';
  assert.equal(runtime.sheetMaterial('#FFFFFF', 'balanced'), empty, 'explicit reactive value wins over global');
  const selectState = {};
  const select = {
    menuOutline: () => {},
    menuSystemMaterial: value => { selectState.material = value; },
    menuBackgroundColor: value => { selectState.color = value; },
    menuBackgroundBlurStyle: value => { selectState.blur = value; }
  };
  for (const level of ['weak', 'balanced', 'adaptive']) runtime.selectMenuModifier(level).applyNormalAttribute(select);
  assert.notEqual(selectState.material, empty);
  assert.equal(selectState.color, 'transparent', 'native material owns the tint without a second background layer');
  assert.equal(selectState.material.materialColor, '#80FFFFFF');
  assert.equal(selectState.blur, 'none');
  assert.equal(runtime.lightEffect(true, 'weak'), null);
  assert.equal(runtime.touchGlowOpacity('weak'), 0);
});

test('older systems and unsupported devices keep non-material popup/sheet fallbacks', () => {
  for (const [api, supported] of [[22, true], [25, true], [26, false]]) {
    const { ImmersiveMaterialRuntime: runtime } = harness(api, supported);
    const popup = runtime.popupMenuOptions('adaptive', () => {}, 'bottom', false, '#123456', () => {});
    const sheet = runtime.applySheetMaterial('adaptive', {}, false, '#123456');
    assert.equal(popup.systemMaterial, undefined);
    assert.equal(sheet.systemMaterial, undefined);
    assert.equal(popup.popupColor, '#80FFFFFF');
    assert.equal(sheet.backgroundColor, '#80FFFFFF');
    assert.equal(sheet.blurStyle, 'blur');
    if (api < 23) assert.equal(runtime.materialType(), 'none');
    else assert.equal(runtime.materialLevel('balanced'), 'balanced');
  }
});

test('weak surfaces have contrasting outlines and switching levels clears the manual outline', () => {
  const { ImmersiveMaterialRuntime: runtime } = harness();
  for (const dark of [false, true]) {
    const edge = runtime.surfaceBorder('weak', dark);
    assert.ok(edge.width > 0 && edge.width <= 1);
    assert.equal(edge.color, dark ? '#40FFFFFF' : '#26000000');
    const popup = runtime.popupMenuOptions('weak', () => {}, 'bottom', dark, '#123456', () => {});
    assert.equal(popup.borderWidth, edge.width);
    assert.equal(popup.borderLinearGradient.colors[0][0], edge.color);
    const sheet = runtime.applySheetMaterial('weak', {}, dark, '#123456');
    assert.equal(sheet.borderColor, edge.color);
    runtime.applySheetMaterial('adaptive', sheet, dark, '#123456');
    assert.equal(sheet.borderWidth, 0);
  }
  let outline;
  const select = { menuOutline: value => { outline = value; }, menuSystemMaterial() {},
    menuBackgroundColor() {}, menuBackgroundBlurStyle() {} };
  for (const level of ['weak', 'balanced', 'weak', 'adaptive', 'high']) {
    runtime.selectMenuModifier(level).applyNormalAttribute(select);
    assert.equal(outline.width > 0, level === 'weak');
    const edge = runtime.surfaceBorder(level, false, 1, '#ABCDEF');
    if (level !== 'weak') {
      assert.equal(edge.width, 1, 'retain existing non-weak borders');
      assert.equal(edge.color, '#ABCDEF');
    }
  }
});

test('custom dialogs use the latest light level when opened and preserve dismissal behavior', async () => {
  const { SystemDialogSession: Session, state, uiContext, empty } = harness();
  const session = new Session();
  let dismissed = 0;
  const options = { autoCancel: true, maskColor: '#66000000', warnTag: 'test', onDismiss: () => dismissed++ };
  for (const level of ['high', 'balanced', 'weak']) {
    state.level = level;
    session.open(uiContext, () => {}, options);
    await Promise.resolve();
    const dialog = state.opened.at(-1);
    if (level === 'high') assert.equal(dialog.systemMaterial.style, 'regular');
    else assert.equal(dialog.systemMaterial, empty);
    if (level === 'weak') assert.equal(dialog.backgroundBlurStyle, 'none');
    dialog.onWillDismiss({ dismiss: () => {} });
    assert.equal(session.isOpen(), false);
  }
  assert.equal(dismissed, 3);
  const fallback = harness(25);
  new fallback.SystemDialogSession().open(fallback.uiContext, () => {}, options);
  assert.equal(fallback.state.opened[0].systemMaterial, undefined);
  assert.equal(fallback.state.opened[0].backgroundColor, '#80FFFFFF');
});

test('each UI material consumer subscribes directly and passes the reactive light level', () => {
  let consumers = 0;
  function walk(dir) {
    for (const item of fs.readdirSync(dir, { withFileTypes: true })) {
      const url = new URL(item.name + (item.isDirectory() ? '/' : ''), dir);
      if (item.isDirectory()) { walk(url); continue; }
      if (!item.name.endsWith('.ets')) continue;
      const text = fs.readFileSync(url, 'utf8');
      const structs = text.split(/(?:export )?struct \w+ \{/).slice(1);
      for (const body of structs) {
        if (!/ImmersiveMaterialRuntime\.(materialStyle|materialLevel|selectMenuModifier|popupMenuOptions|contextMenuOptions|applySheetMaterial)\(/.test(body)) continue;
        consumers++;
        assert.match(body, /@Storage(?:Prop|Link)\('immersiveLightLevel'\)/, url.pathname);
        const calls = [...body.matchAll(/ImmersiveMaterialRuntime\.(?:materialStyle|materialLevel|selectMenuModifier|popupMenuOptions|contextMenuOptions|applySheetMaterial)\(([^\n]*)/g)];
        for (const call of calls) assert.match(call[1], /^this\.immersiveLightLevel/, url.pathname);
      }
    }
  }
  walk(root);
  assert.ok(consumers > 30, `checked ${consumers} components`);
});

// Check the combined tint, not just one colour property: two half-opacity layers would become 75%.
function opacity(color) {
  if (color === 'transparent') return 0;
  return color.length === 9 ? parseInt(color.slice(1, 3), 16) / 255 : 1;
}
function combinedOpacity(background, material) {
  return 1 - (1 - opacity(background)) * (1 - opacity(material?.materialColor || 'transparent'));
}

test('native and fallback overlays preserve half the backdrop across dark/light modes and level changes', () => {
  for (const [api, supported] of [[22, true], [25, true], [26, false], [26, true]]) {
    const { ImmersiveMaterialRuntime: runtime, SystemDialogSession: Session, state, uiContext } = harness(api, supported);
    for (const dark of [false, true]) {
      const base = dark ? '#191B1F' : '#FFFFFF';
      for (const level of ['weak', 'balanced', 'adaptive', 'high', 'balanced', 'adaptive']) {
        state.level = level;
        const expected = level === 'weak' ? 1 : 128 / 255;
        const popup = runtime.popupMenuOptions(level, () => {}, 'bottom', dark, '#123456', () => {});
        const sheet = runtime.applySheetMaterial(level, {}, dark, '#123456');
        const context = runtime.contextMenuOptions(level, '#123456', () => {});
        new Session().open(uiContext, () => {}, { autoCancel: true, maskColor: '#66000000', warnTag: 'test',
          darkMode: dark, backgroundColor: base });
        const dialog = state.opened.at(-1);
        for (const [background, material] of [[popup.popupColor, popup.systemMaterial],
          [sheet.backgroundColor, sheet.systemMaterial], [dialog.backgroundColor, dialog.systemMaterial]]) {
          assert.ok(Math.abs(combinedOpacity(background, material) - expected) < 0.001);
        }
        // Older context menus keep the platform default; supported menus must not double the tint.
        if (context.systemMaterial !== undefined) {
          assert.ok(Math.abs(combinedOpacity(context.backgroundColor, context.systemMaterial) - expected) < 0.001);
        }
        for (const compact of [false, true]) {
          const surface = runtime.surfaceColor(level, dark, base, compact);
          assert.ok(Math.abs(opacity(surface) - expected) < 0.001);
        }
      }
    }
  }
});

test('select and dialog palettes can follow a dark reader inside a light app', () => {
 const { ImmersiveMaterialRuntime: runtime, SystemDialogSession: Session, state, uiContext } = harness();
 const select = {};
 const attributes = { menuOutline() {}, menuSystemMaterial: v => select.material = v,
  menuBackgroundColor: v => select.color = v, menuBackgroundBlurStyle() {} };
 for (const level of ['weak', 'balanced', 'high', 'adaptive']) {
  runtime.selectMenuModifier(level, true, '#191B1F').applyNormalAttribute(attributes);
  assert.equal(select.color, runtime.reducedMaterial(level) ?
    (level === 'weak' ? '#191B1F' : '#80191B1F') : 'transparent');
  if (!runtime.reducedMaterial(level)) assert.equal(select.material.materialColor, '#80191B1F');
 }
 new Session().open(uiContext, () => {}, { autoCancel: true, maskColor: '#66000000', warnTag: 'test',
  darkMode: true, backgroundColor: '#191B1F' });
 assert.equal(state.opened[0].backgroundColor, 'transparent');
 assert.equal(state.opened[0].systemMaterial.materialColor, '#80191B1F');
 assert.equal(runtime.surfaceColor('adaptive', true, '#11191B1F'), '#80191B1F', 'old alpha cannot weaken a menu');
 assert.equal(runtime.surfaceColor('weak', true, '#11191B1F'), '#191B1F');
});
