import assert from 'node:assert/strict';
import vm from 'node:vm';
import { loadObsidianReader } from './lib/obsidian-reader-fixture.mjs';

const { ThemeRuntime: runtime, ReaderHarness, ReaderRegexFontRule: Rule, store, sandbox } = loadObsidianReader();
const codec = vm.runInContext('ReaderRegexFontCodec', sandbox);
const reader = new ReaderHarness();
const argb = color => Number.parseInt(`FF${color.slice(1)}`, 16);

for (const [theme, style, lightFill, darkFill] of [
  ['obsidian-archive', 'gilded-orbit', '#292620', '#463B2A'],
  ['neon-harbor', 'harbor-postcard', '#EEDBD7', '#3B3048']
]) {
  runtime.applyTheme(theme);
  for (const dark of [false, true]) {
    store.set('appDarkMode', dark);
    reader.appDarkMode = dark;
    for (const selectedStyle of [style, 'inherit']) {
      for (const color of ['#17324F', '#F0E9D8', '#C02A45']) {
        const rule = new Rule();
        rule.pattern = '测试';
        rule.emphasisMode = 'custom';
        rule.bubbleStyleId = selectedStyle;
        rule.customBubbleEnabled = true;
        rule.customBubbleColor = color;
        // Exercise the same persistence codec used when editing and reopening a rule.
        reader.rule = codec.decode(codec.encode([rule]))[0];
        const resolved = reader.resolvedRegexEmphasis(reader.rule);
        assert.equal(resolved.backgroundColor, color, `${style}, dark=${dark}: selected bubble color`);
        assert.equal(resolved.textColor, color === '#F0E9D8' ? '#2F261D' : '#FFF9F2');
        const native = reader.buildReaderV2RegexStyleTemplate({});
        assert.equal(native.backgroundColor, argb(color));
        assert.equal(native.decorationStyleId, style);
        assert.equal(native.decorationEnabled, true);

        reader.rule.customTextColorEnabled = true;
        reader.rule.customTextColor = '#12AB34';
        assert.equal(reader.buildReaderV2RegexStyleTemplate({}).color, 0xFF12AB34);
        reader.rule.customHighlightEnabled = true;
        reader.rule.customHighlightColor = '#654321';
        assert.equal(reader.buildReaderV2RegexStyleTemplate({}).backgroundColor, 0xFF654321);

        // Returning to the theme ignores the saved custom colors.
        reader.rule.emphasisMode = 'inherit';
        assert.equal(reader.buildReaderV2RegexStyleTemplate({}).backgroundColor, argb(dark ? darkFill : lightFill));
        reader.rule.emphasisMode = 'custom';
        reader.rule.customBubbleEnabled = false;
        reader.rule.customHighlightEnabled = false;
        const disabled = reader.buildReaderV2RegexStyleTemplate({});
        assert.equal(disabled.backgroundEnabled, false);
        assert.equal(disabled.decorationEnabled, false);
      }
    }
  }
}

console.log('PASS: custom bubble colors survive persistence and reach reader styles in both modes; theme defaults, text/highlight overrides and disabled bubbles are preserved.');
