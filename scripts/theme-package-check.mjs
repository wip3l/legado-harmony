// 主题包（.qytheme）纯逻辑回归：ZIP 中央目录检查、清单与主题设置校验、付费部件替换、强调规则追加、字体重映射。
// node --experimental-strip-types scripts/theme-package-check.mjs
import assert from 'node:assert/strict';
import test from 'node:test';
import { createHash } from 'node:crypto';
import { pathToFileURL } from 'node:url';
import path from 'node:path';
import { projectRoot } from './lib/ets-module-staging.mjs';

const shareDir = path.join(projectRoot, 'entry', 'src', 'main', 'ets', 'theme', 'share');
const zip = await import(pathToFileURL(path.join(shareDir, 'ZipEntryInspector.ts')).href);
const format = await import(pathToFileURL(path.join(shareDir, 'ThemePackageFormat.ts')).href);

/** 只写中央目录需要的字段，足够检查器使用；data 不压缩。 */
function makeZip(entries, { flags = 0x800, zip64 = false } = {}) {
  const locals = [];
  const centrals = [];
  let offset = 0;
  for (const entry of entries) {
    const name = Buffer.from(entry.name, 'utf8');
    const data = Buffer.from(entry.data ?? '');
    const size = entry.size ?? data.length;
    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50, 0);
    local.writeUInt16LE(entry.flags ?? flags, 6);
    local.writeUInt32LE(size, 18);
    local.writeUInt32LE(size, 22);
    local.writeUInt16LE(name.length, 26);
    locals.push(local, name, data);
    const central = Buffer.alloc(46);
    central.writeUInt32LE(0x02014b50, 0);
    central.writeUInt16LE(entry.flags ?? flags, 8);
    central.writeUInt32LE(zip64 ? 0xFFFFFFFF : data.length, 20);
    central.writeUInt32LE(zip64 ? 0xFFFFFFFF : size, 24);
    central.writeUInt16LE(name.length, 28);
    central.writeUInt32LE(offset, 42);
    centrals.push(central, name);
    offset += 30 + name.length + data.length;
  }
  const directory = Buffer.concat(centrals);
  const eocd = Buffer.alloc(22);
  eocd.writeUInt32LE(0x06054b50, 0);
  eocd.writeUInt16LE(entries.length, 8);
  eocd.writeUInt16LE(entries.length, 10);
  eocd.writeUInt32LE(directory.length, 12);
  eocd.writeUInt32LE(offset, 16);
  return Buffer.concat([...locals, directory, eocd]);
}

function inspect(buffer, limits = {}) {
  const l = new zip.ZipInspectLimits();
  Object.assign(l, { maxEntries: 40, maxTotalUncompressed: 1000, maxEntryUncompressed: 500 }, limits);
  return zip.ZipEntryInspector.inspect(buffer.length,
    (offset, length) => new Uint8Array(buffer.subarray(offset, offset + length)), l);
}

test('reads entry names and sizes, finds the shared root folder', () => {
  const entries = inspect(makeZip([
    { name: 'theme/' }, { name: 'theme/manifest.json', data: '{}' }, { name: 'theme/assets/' },
    { name: 'theme/assets/中文.png', data: 'abc' }
  ]));
  assert.deepEqual(entries.map(e => [e.name, e.uncompressedSize, e.directory]), [
    ['theme/', 0, true], ['theme/manifest.json', 2, false], ['theme/assets/', 0, true],
    ['theme/assets/中文.png', 3, false]
  ]);
  assert.equal(zip.ZipEntryInspector.commonRoot(entries), 'theme/');
  assert.equal(zip.ZipEntryInspector.commonRoot(inspect(makeZip([{ name: 'manifest.json' }, { name: 'a/b' }]))), '');
});

test('rejects traversal, absolute, backslash and duplicate names', () => {
  for (const name of ['../evil.json', 'theme/../../x', '/abs/x', 'a\\b', 'C:/x', 'a//b', './a', 'a/\u0001']) {
    assert.throws(() => inspect(makeZip([{ name }])), /不安全/, name);
  }
  assert.throws(() => inspect(makeZip([{ name: 'a' }, { name: 'a' }])), /重复/);
});

test('enforces entry count, per-entry and total uncompressed limits', () => {
  assert.throws(() => inspect(makeZip(Array.from({ length: 41 }, (_, i) => ({ name: `f${i}` })))), /过多/);
  assert.throws(() => inspect(makeZip([{ name: 'big', size: 501 }])), /超出大小上限/);
  assert.throws(() => inspect(makeZip([{ name: 'a', size: 400 }, { name: 'b', size: 400 }, { name: 'c', size: 400 }])),
    /解压后超出/);
});

test('rejects encrypted, zip64 and non-zip input', () => {
  assert.throws(() => inspect(makeZip([{ name: 'a', flags: 0x801 }])), /加密/);
  assert.throws(() => inspect(makeZip([{ name: 'a' }], { zip64: true })), /超大/);
  assert.throws(() => inspect(Buffer.from('not a zip file at all, definitely not')), /不是有效/);
  assert.throws(() => inspect(Buffer.alloc(10)), /不是有效/);
});

const sha = (text) => createHash('sha256').update(text).digest('hex');

function manifest(overrides = {}) {
  const image = sha('image');
  return {
    format: 'qytheme', formatVersion: 1, packageId: 'abc', name: '夜读', author: '小明', exportedAt: 1,
    appVersion: '4.3', requires: ['custom-scheme-v1', 'reader-layout-v1'],
    assets: [{ id: image.substring(0, 24), path: `assets/${image.substring(0, 24)}.png`, kind: 'image', size: 10,
      sha256: image, name: '' }],
    ...overrides
  };
}

test('manifest validation: format, newer version, unknown features, asset rules', () => {
  const ok = format.decodeManifest(JSON.stringify(manifest()));
  assert.equal(ok.name, '夜读');
  assert.equal(ok.assets.length, 1);
  assert.throws(() => format.decodeManifest(JSON.stringify(manifest({ format: 'zip' }))), /不是轻页主题包/);
  assert.throws(() => format.decodeManifest(JSON.stringify(manifest({ formatVersion: 2 }))), /更新应用/);
  assert.throws(() => format.decodeManifest(JSON.stringify(manifest({ requires: ['custom-scheme-v1', 'tts-svg-v2'] }))),
    /不支持的功能/);
  assert.throws(() => format.decodeManifest(JSON.stringify(manifest({ requires: ['reader-layout-v1'] }))), /损坏/);
  const m = manifest();
  m.assets[0].path = 'assets/../../evil.png';
  assert.throws(() => format.decodeManifest(JSON.stringify(m)), /损坏/);
  const wrongKind = manifest();
  wrongKind.assets[0].kind = 'font';
  assert.throws(() => format.decodeManifest(JSON.stringify(wrongKind)), /损坏/);
  const tooBig = manifest();
  tooBig.assets[0].size = 21 * 1024 * 1024;
  assert.throws(() => format.decodeManifest(JSON.stringify(tooBig)), /大小上限/);
  const idMismatch = manifest();
  idMismatch.assets[0].sha256 = sha('other');
  assert.throws(() => format.decodeManifest(JSON.stringify(idMismatch)), /损坏/);
  const fontWithoutFeature = manifest();
  const font = sha('font');
  fontWithoutFeature.assets.push({ id: font.substring(0, 24), path: `assets/${font.substring(0, 24)}.ttf`, kind: 'font',
    size: 10, sha256: font });
  assert.throws(() => format.decodeManifest(JSON.stringify(fontWithoutFeature)), /损坏/);
  assert.throws(() => format.decodeManifest('[1,2]'), /损坏/);
  assert.throws(() => format.decodeManifest('{oops'), /损坏/);
});

test('author and name are cleaned for display', () => {
  assert.equal(format.sanitizeAuthor('  小\n明\u202E\u200B  '), '小 明');
  assert.equal(Array.from(format.sanitizeAuthor('作'.repeat(40))).length, 24);
  assert.equal(format.sanitizeAuthor('😀'.repeat(30)), '😀'.repeat(24));
  const m = format.decodeManifest(JSON.stringify(manifest({ author: 'a\u0000b', name: '' })));
  assert.equal(m.author, 'ab');
  assert.equal(m.name, '导入的主题');
  assert.equal(format.packageFileName('我的/主题:1'), '我的_主题_1.qytheme');
});

test('theme validation: asset references must exist, local paths are refused, layout keeps known keys', () => {
  const m = format.decodeManifest(JSON.stringify(manifest()));
  const imageRef = format.assetRef(m.assets[0].id);
  const theme = format.decodeTheme(JSON.stringify({
    settings: { customLightStartupImagePath: imageRef, customDarkStartupImagePath: 'builtin-key',
      customLightReaderBackgroundAssetId: 'paper-light' },
    layout: { fontSize: 22, paragraphIndent: 2, readerInfoBarConfig: '{"x":1}', tapZoneActions: '1,1', eyeTurnEnabled: true },
    fonts: [{ family: 'ReaderCustomFont_a_1', name: '霞鹜', assetId: '' }]
  }), m);
  const settings = JSON.parse(theme.settingsJson);
  assert.equal(settings.customLightStartupImagePath, imageRef);
  assert.equal(settings.customDarkStartupImagePath, '');
  assert.equal(settings.customLightReaderBackgroundAssetId, 'paper-light');
  assert.deepEqual(JSON.parse(theme.layoutJson), { fontSize: 22, paragraphIndent: 2, readerInfoBarConfig: '{"x":1}' });
  assert.equal(theme.fonts.length, 1);
  assert.throws(() => format.decodeTheme(JSON.stringify({ settings: {
    customLightReaderBackgroundAssetId: 'file:///data/storage/el2/base/files/reader_backgrounds/a.jpg' } }), m),
  /导出设备上的文件/);
  assert.throws(() => format.decodeTheme(JSON.stringify({ settings: {
    customLightStartupImagePath: format.assetRef('f'.repeat(24)) } }), m), /缺少图片/);
  assert.throws(() => format.decodeTheme(JSON.stringify({ settings: {}, emphasis: { rules: [] } }), m), /损坏/);
  assert.throws(() => format.decodeTheme(JSON.stringify({ settings: {}, fonts: [{ family: 'x', assetId: m.assets[0].id }] }), m),
    /缺少字体/);
});

test('encode/decode round trip keeps rules and fonts', () => {
  const m = format.decodeManifest(JSON.stringify(manifest({
    requires: ['custom-scheme-v1', 'reader-layout-v1', 'emphasis-rules-v3']
  })));
  const theme = new format.ThemePackageTheme();
  theme.settingsJson = JSON.stringify({ customBaseThemeId: 'plain-default' });
  theme.layoutJson = JSON.stringify({ fontSize: 19 });
  theme.emphasis = new format.ThemePackageEmphasis();
  theme.emphasis.enabled = true;
  theme.emphasis.rulesJson = JSON.stringify([{ id: 'r1', pattern: '“[^”]+”' }]);
  const back = format.decodeTheme(format.encodeTheme(theme), m);
  assert.equal(back.emphasis.enabled, true);
  assert.equal(JSON.parse(back.emphasis.rulesJson)[0].pattern, '“[^”]+”');
  assert.equal(JSON.parse(back.layoutJson).fontSize, 19);
});

test('sources from themes the importer cannot use are replaced and reported', () => {
  const settings = {
    customBaseThemeId: 'moon-crane',
    customLightSources: { paletteThemeId: 'moon-crane', bubbleThemeId: 'plain-default', readerThemeId: 'future-theme' },
    customDarkSources: { navigationThemeId: 'cat-pipi', layoutThemeId: 'plain-default' }
  };
  const owned = new Set(['plain-default', 'cat-pipi']);
  const known = new Set(['plain-default', 'cat-pipi', 'moon-crane']);
  const result = format.restrictSources(settings, id => owned.has(id), id => known.has(id),
    id => ({ 'moon-crane': '月鹤' })[id] || id, 'plain-default');
  assert.equal(settings.customBaseThemeId, 'plain-default');
  assert.equal(settings.customLightSources.paletteThemeId, 'plain-default');
  assert.equal(settings.customLightSources.readerThemeId, 'plain-default');
  assert.equal(settings.customDarkSources.navigationThemeId, 'cat-pipi');
  assert.deepEqual(result.replaced, ['浅色 · 完整配色（月鹤）']);
  assert.deepEqual(result.unknown, ['浅色 · 阅读背景']);
});

test('incoming emphasis rules are appended after existing ones, same patterns skipped', () => {
  const existing = JSON.stringify({ schemaVersion: 3, rules: [{ id: 'mine', pattern: '「[^」]+」', name: '我的' }] });
  const incoming = JSON.stringify([
    { id: 'mine', pattern: ' 「[^」]+」 ', name: '重复' },
    { id: 'theirs', pattern: '“[^”]+”', name: '对白', expanded: true },
    { id: 'x', pattern: '   ' }
  ]);
  const merged = format.mergeRules(existing, incoming, 42);
  const rules = JSON.parse(merged.rulesJson);
  assert.equal(merged.added, 1);
  assert.equal(merged.skipped, 2);
  assert.deepEqual(rules.map(r => [r.id, r.name]), [['mine', '我的'], ['rule_42_0', '对白']]);
  assert.equal(rules[1].expanded, false);
  assert.equal(format.mergeRules('', incoming, 1).added, 2);
});

test('font bindings move to the installed family or fall back to the global font', () => {
  const layout = { bodyFontMode: 'custom', bodyFontFamily: 'A', titleFontMode: 'custom', titleFontFamily: 'B' };
  const rules = [{ fontMode: 'custom', fontFamily: 'B' }, { fontMode: 'system', fontFamily: 'HarmonyOS Sans' }];
  const missing = format.remapFonts(layout, rules, new Map([['A', 'ReaderCustomFont_local_9']]),
    new Map([['B', '方正书宋']]));
  assert.deepEqual(layout, { bodyFontMode: 'custom', bodyFontFamily: 'ReaderCustomFont_local_9',
    titleFontMode: 'global', titleFontFamily: '' });
  assert.deepEqual(rules, [{ fontMode: 'global', fontFamily: '' }, { fontMode: 'system', fontFamily: 'HarmonyOS Sans' }]);
  assert.deepEqual(missing, ['方正书宋']);
});

test('layout apply only overwrites fields of the same type', () => {
  const target = { fontSize: 20, textAlign: 'justify', readerHeaderEnabled: false, pageTurnMode: 2 };
  format.applyLayout(target, { fontSize: 24, textAlign: 7, readerHeaderEnabled: true, pageTurnMode: 0 });
  assert.deepEqual(target, { fontSize: 24, textAlign: 'justify', readerHeaderEnabled: true, pageTurnMode: 2 });
});

test('asset sniffing recognises supported images and fonts only', () => {
  const bytes = (...values) => new Uint8Array(values);
  assert.equal(format.sniffAssetExtension(bytes(0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)), 'png');
  assert.equal(format.sniffAssetExtension(bytes(0xFF, 0xD8, 0xFF, 0xE0)), 'jpg');
  assert.equal(format.sniffAssetExtension(new Uint8Array(Buffer.from('RIFF0000WEBPVP8 '))), 'webp');
  assert.equal(format.sniffAssetExtension(bytes(0x00, 0x01, 0x00, 0x00)), 'ttf');
  assert.equal(format.sniffAssetExtension(new Uint8Array(Buffer.from('OTTO'))), 'otf');
  assert.equal(format.sniffAssetExtension(new Uint8Array(Buffer.from('ttcf'))), 'ttc');
  assert.equal(format.sniffAssetExtension(new Uint8Array(Buffer.from('<svg xmlns='))), '');
  assert.equal(format.kindForExtension('svg'), '');
});
