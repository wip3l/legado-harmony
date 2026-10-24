import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { projectRoot } from './lib/ets-module-staging.mjs';

const read = file => fs.readFileSync(`${projectRoot}/entry/src/main/ets/${file}`, 'utf8');
const compile = text => stripTypeScriptTypes(text.replace(/^import [\s\S]*?;\r?\n/gm, '')
  .replace(/^export /gm, ''), { mode: 'strip' });
// The graphics enum is deliberately zero-based like the SDK, unlike ArkUI's numeric font weight.
const context = vm.createContext({
  graphicsText: { FontWeight: Object.fromEntries(Array.from({ length: 9 }, (_, i) => [`W${(i + 1) * 100}`, i])) },
  ReaderCommentBubbleStyle: class { identity() { return 'bubble'; } }
});
const typography = read('components/reader/ReaderLayoutSettings.ets');
const fields = typography.slice(typography.indexOf('export class ReaderTypographyField'), typography.indexOf('/**\n * 正文排版') > 0 ?
  typography.indexOf('/**\n * 正文排版') : typography.indexOf('/**\r\n * 正文排版'));
vm.runInContext([
  'core/reader/ReaderCommentBubbleSize.ts', 'core/reader/ReaderFontWeight.ts', 'core/reader/ReaderV2LayoutSnapshot.ets',
  'core/reader/ReaderV2PageLayout.ets', 'core/reader/ReaderV2Style.ets', 'core/reader/ReaderV2Paginator.ets'
].map(file => compile(read(file))).join('\n') + '\n' + compile(fields) + `
  globalThis.api = { ReaderFontWeight, ReaderTypographyField, ReaderV2LayoutInput,
    ReaderV2LayoutSnapshot, ReaderV2Paginator, ReaderV2SpanStyleRange };
`, context);
const { ReaderFontWeight: Weight, ReaderTypographyField: Field, ReaderV2LayoutInput: Input,
  ReaderV2LayoutSnapshot: Snapshot, ReaderV2Paginator: Paginator, ReaderV2SpanStyleRange: Range } = context.api;

for (const [value, expected] of [[undefined, 400], [NaN, 400], [Infinity, 400], [-5, 50], [940, 900], [450, 450], [475, 475], [649, 649], [650, 650]]) {
  assert.equal(Weight.normalize(value), expected);
}
assert.equal(Field.LABELS[Field.FONT_WEIGHT], '字体粗细');
assert.equal(Field.FONT_WEIGHT, Field.FONT_SIZE + 1);
assert.equal(Field.step(Field.FONT_WEIGHT), 50);
assert.equal(Field.min(Field.FONT_WEIGHT), 50);
assert.equal(Field.max(Field.FONT_WEIGHT), 900);
assert.equal(Field.clamp(Field.FONT_WEIGHT, 649), 649);
assert.equal(Field.step(Field.FONT_SIZE), 1);
assert.equal(Field.clamp(Field.FONT_SIZE, 100), 50);
console.log('PASS: typography range, steps and input normalization');

const input = new Input();
input.viewportWidthPx = 800;
input.viewportHeightPx = 1200;
const original = Snapshot.create(input);
assert.equal(original.fontWeight, 400);
const block = { title: false, headingLevel: 0, text: '前文特殊字体后文', displayStart: 0 };
const document = { actions: [] };
const rule = new Range(2, 6);
rule.fontFamily = 'custom-face';
rule.fontSizePx = 48;
const identities = new Set();
for (let weight = 50; weight <= 900; weight += 50) {
  input.fontWeight = weight;
  const snapshot = Snapshot.create(input);
  identities.add(snapshot.identity);
  assert.equal(Paginator.baseTextStyle(block, snapshot).fontWeight, Math.max(0, Math.round(weight / 100) - 1));
  const styled = Paginator.styleAt(document, block, 3, snapshot, [rule]);
  assert.equal(styled.fontWeight, Math.max(0, Math.round(weight / 100) - 1));
  assert.equal(styled.fontVariations[0].value, weight);
  assert.equal(styled.fontFamilies[0], 'custom-face');
  assert.equal(styled.fontSize, 48);
  for (const heading of [{ ...block, title: true }, { ...block, headingLevel: 2 }]) {
    assert.equal(Paginator.baseTextStyle(heading, snapshot).fontWeight, 5);
    assert.equal(Paginator.buildSelectionRuns(document, heading, snapshot, [], 0, block.text.length)[0].fontWeight, 600);
  }
  const runs = Paginator.buildSelectionRuns(document, block, snapshot, [rule], 0, block.text.length);
  assert.equal(runs.map(run => run.text).join(''), block.text);
  assert(runs.every(run => run.fontWeight === weight));
  assert.equal(runs[1].fontFamily, 'custom-face');
}
assert.equal(identities.size, 18, 'weight changes must invalidate layout/page/selection caches');
assert.equal(original.fontWeight, 400, 'existing snapshots stay immutable when input changes');
console.log('PASS: all eighteen weights reach body and regex styles, selection metadata and cache identities; headings stay at 600');

// Execute the settings page's real handlers so insertion cannot silently shift the other typography controls.
const settingsPage = read('pages/Settings.ets');
const methods = settingsPage.slice(settingsPage.indexOf('  typographySettingOptions():'), settingsPage.indexOf('  setCurrentThemeBackgroundColor('));
const fontSetter = settingsPage.slice(settingsPage.indexOf('  setReaderFontWeight('), settingsPage.indexOf('  setReaderLetterSpacing('));
context.ReaderTypographyField = Field;
context.ReaderFontWeight = Weight;
vm.runInContext(compile(`class Controls {
  typographySettingIndex = 0;
  readerFontWeight = 400;
  readerFontSize = 20;
  readerLetterSpacing = 2;
  readerLineHeight = 12;
  readerParagraphSpacing = 4;
  readerMarginLeft = 18;
  readerMarginRight = 19;
  readerMarginTop = 20;
  readerMarginBottom = 21;
  readerCommentBubbleSize = 100;
  saves = 0;
  saveReaderLayoutSettings() { this.saves++; }
  ${settingsPage.slice(settingsPage.indexOf('  setReaderCommentBubbleSize('), settingsPage.indexOf('  typographySettingOptions():'))}
  ${fontSetter}
  ${methods}
}
globalThis.controls = new Controls();`), context);
const controls = context.controls;
const options = controls.typographySettingOptions();
for (const [field, label] of [[Field.MARGIN_LEFT, '左边距'], [Field.MARGIN_RIGHT, '右边距'],
  [Field.MARGIN_TOP, '上边距'], [Field.MARGIN_BOTTOM, '下边距']]) {
  assert.equal(options[field]?.value, label, `Settings dropdown must expose ${label}`);
}
controls.typographySettingIndex = Field.FONT_WEIGHT;
controls.adjustCurrentTypographySetting(1);
assert.equal(controls.readerFontWeight, 450);
controls.adjustCurrentTypographySetting(-1);
assert.equal(controls.readerFontWeight, 400);
controls.openTypographyValueInput();
controls.typographyValueDraft = '450';
controls.applyTypographyValueInput();
assert.equal(controls.readerFontWeight, 450);
assert.equal(controls.saves, 3);
for (const [field, expected] of [[Field.LETTER_SPACING, 2], [Field.LINE_HEIGHT, 12], [Field.PARAGRAPH_SPACING, 4],
  [Field.MARGIN_LEFT, 18], [Field.MARGIN_RIGHT, 19], [Field.MARGIN_TOP, 20], [Field.MARGIN_BOTTOM, 21]]) {
  controls.typographySettingIndex = field;
  assert.equal(controls.currentTypographySettingValue(), expected);
}
console.log('PASS: settings handlers step by 50, preserve precise input and preserve all existing control mappings');

assert.equal(Field.COMMENT_BUBBLE_SIZE, Field.MARGIN_BOTTOM + 1);
assert.equal(options[Field.COMMENT_BUBBLE_SIZE].value, '气泡大小');
controls.typographySettingIndex = Field.COMMENT_BUBBLE_SIZE;
assert.equal(controls.currentTypographySettingValue(), 100);
controls.adjustCurrentTypographySetting(1);
assert.equal(controls.readerCommentBubbleSize, 101);
for (const [draft, expected] of [['10', 10], ['200', 200], ['0', 10], ['999', 200]]) {
  controls.openTypographyValueInput();
  controls.typographyValueDraft = draft;
  controls.applyTypographyValueInput();
  assert.equal(controls.readerCommentBubbleSize, expected);
}
// Actual paragraph/action text styles: size and spacing scale together; chapter comments stay fixed.
input.letterSpacingPx = 2;
const actionDocument = { actions: [{ displayStart: 0, displayEnd: 5, label: '123' }] };
const bubbleIdentities = new Set();
for (const size of [10, 100, 200]) {
  input.commentBubbleSize = size;
  const snapshot = Snapshot.create(input);
  bubbleIdentities.add(snapshot.identity);
  actionDocument.actions[0].label = '123';
  let style = Paginator.styleAt(actionDocument, block, 0, snapshot, []);
  assert.equal(style.fontSize, input.commentFontSizePx * size / 100);
  assert.equal(style.letterSpacing, 2 * size / 100);
  actionDocument.actions[0].label = ' 本章说 ';
  style = Paginator.styleAt(actionDocument, block, 0, snapshot, []);
  assert.equal(style.fontSize, input.commentFontSizePx);
  assert.equal(style.letterSpacing, 2);
}
assert.equal(bubbleIdentities.size, 3);
console.log('PASS: bubble controls clamp to 10–200; paragraph labels scale and chapter labels stay unchanged');

// Use native glyph-box fixtures to verify bubble geometry and hit areas track the scaled label.
context.graphicsText.RectWidthStyle = { TIGHT: 0 };
context.graphicsText.RectHeightStyle = { TIGHT: 0, MAX: 1 };
vm.runInContext(compile(read('core/reader/ReaderCommentBubble.ets')), context);
for (const label of ['123', ' 本章说 ']) {
  for (const size of [10, 100, 200]) {
    input.commentBubbleSize = size;
    const snapshot = Snapshot.create(input);
    const scale = label.includes('本章说') ? 1 : size / 100;
    const action = { id: 'a', marker: 'm', label, bubbleStart: 0, displayStart: 0, displayEnd: 3 };
    const fragment = {
      displayStart: 0, displayEnd: 3, localStart: 0, localEnd: 3,
      paragraphX: 10, paragraphY: 20,
      clipRect: { left: 0, top: 0, right: 1000, bottom: 1000 }, commentBubbleSegments: [],
      paragraph: {
        getLineMetrics: () => [{ startIndex: 0, endIndex: 3 }],
        getRectsForRange: () => [{ rect: { left: 0, right: 60 * scale, top: 0, bottom: 30 * scale } }]
      }
    };
    const page = { actions: [] };
    Paginator.appendActionAreas(page, fragment, [action], snapshot);
    const bubble = fragment.commentBubbleSegments[0];
    assert.equal(bubble.scale, scale);
    assert(Math.abs(bubble.rect.width() - (60 + 30 * 0.36) * scale) < 1e-9);
    assert(Math.abs(bubble.rect.height() - 30 * 1.32 * scale) < 1e-9);
    assert.equal(bubble.tail, true);
    assert.equal(page.actions[0].rect.width(), 60 * scale);
    assert.equal(page.actions[0].actionId, action.id);
  }
}
console.log('PASS: paragraph bubble geometry and action hit areas follow label scaling, including 10% and 200%');
