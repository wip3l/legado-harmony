/**
 * .qytheme 主题包的格式定义与纯逻辑（不依赖系统接口，Node 回归脚本可直接加载）。
 *
 * 包是一个 ZIP：manifest.json（格式、版本、名称、作者、所需能力、资源清单）+ theme.json（方案设置、
 * 方案排版、可选的强调规则和字体绑定）+ assets/（用户自己上传的图片和可选字体）。
 * 内置主题的素材随应用安装，包里只写部件来源 ID，不复制内置图片，也就不会把付费素材带出去。
 */

export const QYTHEME_FORMAT: string = 'qytheme';
export const QYTHEME_FORMAT_VERSION: number = 1;
export const QYTHEME_EXTENSION: string = '.qytheme';
export const QYTHEME_ASSET_PREFIX: string = 'qytheme-asset:';

export class ThemePackageFeatures {
  static readonly CUSTOM_SCHEME: string = 'custom-scheme-v1';
  static readonly READER_LAYOUT: string = 'reader-layout-v1';
  static readonly EMPHASIS_RULES: string = 'emphasis-rules-v3';
  static readonly FONTS: string = 'fonts-v1';
  static readonly KNOWN: string[] = [
    ThemePackageFeatures.CUSTOM_SCHEME,
    ThemePackageFeatures.READER_LAYOUT,
    ThemePackageFeatures.EMPHASIS_RULES,
    ThemePackageFeatures.FONTS
  ];
}

export class ThemePackageLimits {
  static readonly MAX_PACKAGE_BYTES: number = 80 * 1024 * 1024;
  static readonly MAX_TOTAL_UNCOMPRESSED: number = 160 * 1024 * 1024;
  static readonly MAX_IMAGE_BYTES: number = 20 * 1024 * 1024;
  static readonly MAX_FONT_BYTES: number = 40 * 1024 * 1024;
  static readonly MAX_JSON_BYTES: number = 1024 * 1024;
  static readonly MAX_ASSETS: number = 24;
  static readonly MAX_ZIP_ENTRIES: number = 40;
  static readonly MAX_RULES: number = 200;
  static readonly MAX_NAME_LENGTH: number = 24;
  static readonly MAX_AUTHOR_LENGTH: number = 24;
}

export class ThemePackageAssetKinds {
  static readonly IMAGE: string = 'image';
  static readonly FONT: string = 'font';
}

const IMAGE_EXTENSIONS: string[] = ['png', 'jpg', 'webp', 'gif', 'bmp'];
const FONT_EXTENSIONS: string[] = ['ttf', 'otf', 'ttc'];

export class ThemePackageAsset {
  id: string = '';
  path: string = '';
  kind: string = ThemePackageAssetKinds.IMAGE;
  size: number = 0;
  sha256: string = '';
  // 字体的显示名；图片为空。
  name: string = '';
}

export class ThemePackageManifest {
  format: string = QYTHEME_FORMAT;
  formatVersion: number = QYTHEME_FORMAT_VERSION;
  packageId: string = '';
  name: string = '';
  author: string = '';
  exportedAt: number = 0;
  appVersion: string = '';
  requires: string[] = [];
  assets: ThemePackageAsset[] = [];
}

/** 方案排版或强调规则引用到的字体。assetId 为空表示导出时没有附带字体文件。 */
export class ThemePackageFont {
  family: string = '';
  name: string = '';
  assetId: string = '';
}

export class ThemePackageEmphasis {
  enabled: boolean = false;
  // ReaderRegexFontRule 的 JSON 形式（schemaVersion 3）。
  rulesJson: string = '';
}

export class ThemePackageTheme {
  // AppThemeSettings 的 JSON 形式，图片路径替换为 qytheme-asset:<id>。
  settingsJson: string = '';
  // 方案排版：LAYOUT_KEYS 列出的阅读设置字段。
  layoutJson: string = '';
  emphasis: ThemePackageEmphasis | null = null;
  fonts: ThemePackageFont[] = [];
}

/** 随主题走的阅读排版字段：正文、标题、缩进、边距、页眉页脚与进度条、方案字体绑定。翻页和手势不属于主题。 */
export const LAYOUT_KEYS: string[] = [
  'fontSize', 'fontWeight', 'letterSpacing', 'textAlign', 'lineHeight', 'paragraphSpacing', 'paragraphIndent',
  'marginLeft', 'marginRight', 'marginTop', 'marginBottom',
  'readerHeaderEnabled', 'readerHeaderContentMode', 'readerFooterEnabled', 'readerFooterLeftMode',
  'readerFooterProgressMode', 'readerFooterShowProgressBar', 'readerInfoBarConfig',
  'bodyFontMode', 'bodyFontFamily', 'titleFontMode', 'titleFontFamily', 'titleFontSize'
];

/** 方案设置里可能指向本机图片文件的字段。 */
export const IMAGE_SETTING_KEYS: string[] = [
  'customLightStartupImagePath', 'customDarkStartupImagePath',
  'customLightReaderBackgroundAssetId', 'customDarkReaderBackgroundAssetId'
];

export class ThemeSourceField {
  key: string = '';
  label: string = '';

  constructor(key: string, label: string) {
    this.key = key;
    this.label = label;
  }
}

export const THEME_SOURCE_FIELDS: ThemeSourceField[] = [
  new ThemeSourceField('startupThemeId', '启动封面'),
  new ThemeSourceField('paletteThemeId', '完整配色'),
  new ThemeSourceField('readerThemeId', '阅读背景'),
  new ThemeSourceField('ttsPanelThemeId', '朗读/有声书面板'),
  new ThemeSourceField('bubbleThemeId', '强调气泡'),
  new ThemeSourceField('navigationThemeId', '导航图标'),
  new ThemeSourceField('bookThemeId', '书籍素材'),
  new ThemeSourceField('typographyThemeId', '字体'),
  new ThemeSourceField('layoutThemeId', '阅读排版'),
  new ThemeSourceField('radiusThemeId', '圆角形状'),
  new ThemeSourceField('glassThemeId', '磨砂效果')
];

export function assetRef(id: string): string {
  return `${QYTHEME_ASSET_PREFIX}${id}`;
}

export function assetIdFromRef(value: string): string {
  return typeof value === 'string' && value.startsWith(QYTHEME_ASSET_PREFIX) ?
    value.substring(QYTHEME_ASSET_PREFIX.length) : '';
}

/** 本机文件（file:// 或绝对路径）；内置素材是不带斜杠的资源键。 */
export function isLocalFileReference(value: string): boolean {
  return typeof value === 'string' && (value.startsWith('file://') || value.startsWith('/'));
}

function stripControlChars(value: string): string {
  let result = '';
  for (let i = 0; i < value.length; i++) {
    const code = value.charCodeAt(i);
    if (code < 0x20 || code === 0x7F || (code >= 0x200B && code <= 0x200F) || (code >= 0x202A && code <= 0x202E) ||
      (code >= 0x2066 && code <= 0x2069)) {
      continue;
    }
    result += value.charAt(i);
  }
  return result;
}

function limitChars(value: string, max: number): string {
  const chars = Array.from(value);
  return chars.length > max ? chars.slice(0, max).join('') : value;
}

/** 署名只做展示：去掉换行、控制字符和改变书写方向的字符，限制长度。 */
export function sanitizeAuthor(raw: string): string {
  return limitChars(stripControlChars((raw || '').replace(/\s+/g, ' ')).trim(), ThemePackageLimits.MAX_AUTHOR_LENGTH);
}

export function sanitizeThemeName(raw: string): string {
  return limitChars(stripControlChars((raw || '').replace(/\s+/g, ' ')).trim(), ThemePackageLimits.MAX_NAME_LENGTH);
}

/** 用于导出文件名：去掉文件系统不允许的字符。 */
export function packageFileName(name: string): string {
  const base = sanitizeThemeName(name).replace(/[\\/:*?"<>|]/g, '_').trim() || '主题';
  return `${base}${QYTHEME_EXTENSION}`;
}

export function assetPath(id: string, extension: string): string {
  return `assets/${id}.${extension}`;
}

/** 根据文件头判断素材类型，返回规范扩展名；无法识别时返回空串。 */
export function sniffAssetExtension(head: Uint8Array): string {
  if (head.length >= 8 && head[0] === 0x89 && head[1] === 0x50 && head[2] === 0x4E && head[3] === 0x47) return 'png';
  if (head.length >= 3 && head[0] === 0xFF && head[1] === 0xD8 && head[2] === 0xFF) return 'jpg';
  if (head.length >= 12 && head[0] === 0x52 && head[1] === 0x49 && head[2] === 0x46 && head[3] === 0x46 &&
    head[8] === 0x57 && head[9] === 0x45 && head[10] === 0x42 && head[11] === 0x50) return 'webp';
  if (head.length >= 6 && head[0] === 0x47 && head[1] === 0x49 && head[2] === 0x46 && head[3] === 0x38) return 'gif';
  if (head.length >= 2 && head[0] === 0x42 && head[1] === 0x4D) return 'bmp';
  if (head.length >= 4) {
    if (head[0] === 0x00 && head[1] === 0x01 && head[2] === 0x00 && head[3] === 0x00) return 'ttf';
    if (head[0] === 0x74 && head[1] === 0x72 && head[2] === 0x75 && head[3] === 0x65) return 'ttf';
    if (head[0] === 0x4F && head[1] === 0x54 && head[2] === 0x54 && head[3] === 0x4F) return 'otf';
    if (head[0] === 0x74 && head[1] === 0x74 && head[2] === 0x63 && head[3] === 0x66) return 'ttc';
  }
  return '';
}

export function kindForExtension(extension: string): string {
  if (IMAGE_EXTENSIONS.includes(extension)) return ThemePackageAssetKinds.IMAGE;
  if (FONT_EXTENSIONS.includes(extension)) return ThemePackageAssetKinds.FONT;
  return '';
}

function isHex(value: string, minLength: number, maxLength: number): boolean {
  return typeof value === 'string' && value.length >= minLength && value.length <= maxLength &&
    /^[0-9a-f]+$/.test(value);
}

function parseJsonObject(text: string, label: string): Record<string, Object> {
  if (!text || text.length > ThemePackageLimits.MAX_JSON_BYTES) {
    throw new Error(`主题包的${label}缺失或过大`);
  }
  let parsed: Object;
  try {
    parsed = JSON.parse(text) as Object;
  } catch (_) {
    throw new Error(`主题包的${label}已损坏`);
  }
  if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
    throw new Error(`主题包的${label}已损坏`);
  }
  return parsed as Record<string, Object>;
}

function stringField(record: Record<string, Object>, key: string): string {
  const value = record[key];
  return typeof value === 'string' ? value : '';
}

function numberField(record: Record<string, Object>, key: string): number {
  const value = record[key];
  return typeof value === 'number' && isFinite(value) ? value : 0;
}

export function encodeManifest(manifest: ThemePackageManifest): string {
  return JSON.stringify(manifest, null, 2);
}

/** 校验并规范化 manifest.json。格式版本或必需能力超出本版本时提示更新应用。 */
export function decodeManifest(text: string): ThemePackageManifest {
  const record = parseJsonObject(text, '清单');
  if (stringField(record, 'format') !== QYTHEME_FORMAT) {
    throw new Error('这不是轻页主题包');
  }
  const version = numberField(record, 'formatVersion');
  if (version < 1 || Math.floor(version) !== version) {
    throw new Error('主题包版本无效');
  }
  if (version > QYTHEME_FORMAT_VERSION) {
    throw new Error('这个主题包来自更新版本的应用，请先更新应用再导入');
  }
  const manifest = new ThemePackageManifest();
  manifest.formatVersion = version;
  manifest.packageId = limitChars(stringField(record, 'packageId'), 64);
  manifest.name = sanitizeThemeName(stringField(record, 'name')) || '导入的主题';
  manifest.author = sanitizeAuthor(stringField(record, 'author'));
  manifest.exportedAt = numberField(record, 'exportedAt');
  manifest.appVersion = limitChars(stringField(record, 'appVersion'), 32);
  const requires = record['requires'];
  if (!Array.isArray(requires) || requires.length > 16) {
    throw new Error('主题包清单已损坏');
  }
  for (const item of requires as Object[]) {
    if (typeof item !== 'string') {
      throw new Error('主题包清单已损坏');
    }
    if (!ThemePackageFeatures.KNOWN.includes(item)) {
      throw new Error('这个主题包用到了当前版本不支持的功能，请先更新应用再导入');
    }
    manifest.requires.push(item);
  }
  if (!manifest.requires.includes(ThemePackageFeatures.CUSTOM_SCHEME)) {
    throw new Error('主题包清单已损坏');
  }
  const assets = record['assets'];
  if (!Array.isArray(assets) || assets.length > ThemePackageLimits.MAX_ASSETS) {
    throw new Error('主题包素材数量超出上限');
  }
  const ids = new Set<string>();
  for (const item of assets as Object[]) {
    if (!item || typeof item !== 'object') {
      throw new Error('主题包清单已损坏');
    }
    const source = item as Record<string, Object>;
    const asset = new ThemePackageAsset();
    asset.id = stringField(source, 'id');
    asset.kind = stringField(source, 'kind');
    asset.size = numberField(source, 'size');
    asset.sha256 = stringField(source, 'sha256');
    asset.path = stringField(source, 'path');
    asset.name = limitChars(stripControlChars(stringField(source, 'name')), 60);
    if (!isHex(asset.id, 16, 64) || ids.has(asset.id) || !isHex(asset.sha256, 64, 64) ||
      !asset.sha256.startsWith(asset.id.substring(0, 16))) {
      throw new Error('主题包清单已损坏');
    }
    const dot = asset.path.lastIndexOf('.');
    const extension = dot > 0 ? asset.path.substring(dot + 1) : '';
    if (asset.path !== assetPath(asset.id, extension) || kindForExtension(extension) !== asset.kind) {
      throw new Error('主题包清单已损坏');
    }
    const maxSize = asset.kind === ThemePackageAssetKinds.FONT ?
      ThemePackageLimits.MAX_FONT_BYTES : ThemePackageLimits.MAX_IMAGE_BYTES;
    if (asset.size <= 0 || asset.size > maxSize || Math.floor(asset.size) !== asset.size) {
      throw new Error('主题包素材超出大小上限');
    }
    if (asset.kind === ThemePackageAssetKinds.FONT && !manifest.requires.includes(ThemePackageFeatures.FONTS)) {
      throw new Error('主题包清单已损坏');
    }
    ids.add(asset.id);
    manifest.assets.push(asset);
  }
  return manifest;
}

export function findAsset(manifest: ThemePackageManifest, id: string): ThemePackageAsset | null {
  for (const asset of manifest.assets) {
    if (asset.id === id) return asset;
  }
  return null;
}

export function encodeTheme(theme: ThemePackageTheme): string {
  const record: Record<string, Object> = {};
  record['settings'] = JSON.parse(theme.settingsJson) as Object;
  if (theme.layoutJson) record['layout'] = JSON.parse(theme.layoutJson) as Object;
  if (theme.emphasis) {
    const emphasis: Record<string, Object> = {};
    emphasis['enabled'] = theme.emphasis.enabled;
    emphasis['rules'] = JSON.parse(theme.emphasis.rulesJson) as Object;
    record['emphasis'] = emphasis;
  }
  record['fonts'] = theme.fonts;
  return JSON.stringify(record, null, 2);
}

/** 校验 theme.json：只保留认得的字段；引用的素材必须在清单里，且类型对得上。 */
export function decodeTheme(text: string, manifest: ThemePackageManifest): ThemePackageTheme {
  const record = parseJsonObject(text, '主题设置');
  const settings = record['settings'];
  if (!settings || typeof settings !== 'object' || Array.isArray(settings)) {
    throw new Error('主题包的主题设置已损坏');
  }
  const settingsRecord = settings as Record<string, Object>;
  for (const key of IMAGE_SETTING_KEYS) {
    const value = settingsRecord[key];
    if (typeof value !== 'string' || !value) continue;
    if (isLocalFileReference(value)) {
      throw new Error('主题包引用了导出设备上的文件，无法导入');
    }
    const id = assetIdFromRef(value);
    if (id) {
      const asset = findAsset(manifest, id);
      if (!asset || asset.kind !== ThemePackageAssetKinds.IMAGE) {
        throw new Error('主题包缺少图片素材');
      }
    } else if (key.endsWith('ImagePath')) {
      // 启动封面只接受包内图片，没有就是空。
      settingsRecord[key] = '';
    }
  }
  const theme = new ThemePackageTheme();
  theme.settingsJson = JSON.stringify(settingsRecord);
  const layout = record['layout'];
  if (layout && typeof layout === 'object' && !Array.isArray(layout)) {
    if (!manifest.requires.includes(ThemePackageFeatures.READER_LAYOUT)) {
      throw new Error('主题包清单已损坏');
    }
    theme.layoutJson = JSON.stringify(pickLayout(layout as Record<string, Object>));
  }
  const emphasis = record['emphasis'];
  if (emphasis && typeof emphasis === 'object' && !Array.isArray(emphasis)) {
    if (!manifest.requires.includes(ThemePackageFeatures.EMPHASIS_RULES)) {
      throw new Error('主题包清单已损坏');
    }
    const emphasisRecord = emphasis as Record<string, Object>;
    const rules = emphasisRecord['rules'];
    if (!Array.isArray(rules) || rules.length > ThemePackageLimits.MAX_RULES) {
      throw new Error('主题包的强调规则已损坏');
    }
    theme.emphasis = new ThemePackageEmphasis();
    theme.emphasis.enabled = emphasisRecord['enabled'] === true;
    theme.emphasis.rulesJson = JSON.stringify(rules);
  }
  const fonts = record['fonts'];
  if (Array.isArray(fonts)) {
    if (fonts.length > ThemePackageLimits.MAX_ASSETS) {
      throw new Error('主题包的字体信息已损坏');
    }
    for (const item of fonts as Object[]) {
      if (!item || typeof item !== 'object') continue;
      const source = item as Record<string, Object>;
      const font = new ThemePackageFont();
      font.family = limitChars(stringField(source, 'family'), 120);
      font.name = limitChars(stripControlChars(stringField(source, 'name')), 60);
      font.assetId = stringField(source, 'assetId');
      if (!font.family) continue;
      if (font.assetId) {
        const asset = findAsset(manifest, font.assetId);
        if (!asset || asset.kind !== ThemePackageAssetKinds.FONT) {
          throw new Error('主题包缺少字体文件');
        }
      }
      theme.fonts.push(font);
    }
  }
  return theme;
}

/** 从阅读设置取出随主题走的排版字段。 */
export function pickLayout(source: Record<string, Object>): Record<string, Object> {
  const layout: Record<string, Object> = {};
  for (const key of LAYOUT_KEYS) {
    const value = source[key];
    if (typeof value === 'number' ? isFinite(value) : (typeof value === 'string' || typeof value === 'boolean')) {
      layout[key] = typeof value === 'string' ? limitChars(value, key === 'readerInfoBarConfig' ? 8000 : 200) : value;
    }
  }
  return layout;
}

/** 把排版字段写回阅读设置；类型与目标字段不同的值忽略，交给阅读设置的规范化处理范围。 */
export function applyLayout(target: Record<string, Object>, layout: Record<string, Object>): void {
  for (const key of LAYOUT_KEYS) {
    const value = layout[key];
    if (value === undefined || value === null) continue;
    if (typeof target[key] === typeof value) {
      target[key] = value;
    }
  }
}

export class SourceRestriction {
  // 被替换掉的部件，用于预览提示，例如「深色 · 强调气泡（月鹤）」。
  replaced: string[] = [];
  // 来自更新版本、本机没有的部件。
  unknown: string[] = [];
}

/**
 * 导入方无权使用的部件来源换成可用的主题。canUse 判断主题是否免费或已获得，known 判断本机是否认得这个主题 ID，
 * themeName 用于提示文案，fallback 是替代用的免费主题。
 */
export function restrictSources(settings: Record<string, Object>, canUse: (themeId: string) => boolean,
  known: (themeId: string) => boolean, themeName: (themeId: string) => string,
  fallback: string): SourceRestriction {
  const result = new SourceRestriction();
  const base = settings['customBaseThemeId'];
  if (typeof base !== 'string' || !known(base) || !canUse(base)) {
    settings['customBaseThemeId'] = fallback;
  }
  const modes: string[] = ['customLightSources', 'customDarkSources'];
  for (const modeKey of modes) {
    const sources = settings[modeKey];
    if (!sources || typeof sources !== 'object' || Array.isArray(sources)) {
      continue;
    }
    const record = sources as Record<string, Object>;
    const modeLabel = modeKey === 'customLightSources' ? '浅色' : '深色';
    for (const field of THEME_SOURCE_FIELDS) {
      const value = record[field.key];
      if (typeof value !== 'string' || !value) continue;
      if (!known(value)) {
        record[field.key] = fallback;
        result.unknown.push(`${modeLabel} · ${field.label}`);
      } else if (!canUse(value)) {
        record[field.key] = fallback;
        result.replaced.push(`${modeLabel} · ${field.label}（${themeName(value)}）`);
      }
    }
  }
  return result;
}

export class RuleMergeResult {
  rulesJson: string = '[]';
  added: number = 0;
  skipped: number = 0;
}

/** 包内强调规则追加到已有规则之后：表达式相同的跳过，新加的规则换新 ID，避免与已有规则冲突。 */
export function mergeRules(existingJson: string, incomingJson: string, idSeed: number): RuleMergeResult {
  const existing = parseRuleArray(existingJson);
  const incoming = parseRuleArray(incomingJson);
  const patterns = new Set<string>();
  for (const rule of existing) {
    patterns.add(ruleString(rule, 'pattern').trim());
  }
  const result = new RuleMergeResult();
  const merged: Record<string, Object>[] = existing.slice();
  for (const rule of incoming) {
    const pattern = ruleString(rule, 'pattern').trim();
    if (!pattern || patterns.has(pattern) || merged.length >= ThemePackageLimits.MAX_RULES) {
      result.skipped++;
      continue;
    }
    patterns.add(pattern);
    const copy: Record<string, Object> = {};
    for (const key of Object.keys(rule)) {
      copy[key] = rule[key];
    }
    copy['id'] = `rule_${idSeed}_${result.added}`;
    copy['expanded'] = false;
    merged.push(copy);
    result.added++;
  }
  result.rulesJson = JSON.stringify(merged);
  return result;
}

function parseRuleArray(text: string): Record<string, Object>[] {
  if (!text) return [];
  try {
    const parsed = JSON.parse(text) as Object;
    const list = Array.isArray(parsed) ? parsed as Object[] :
      (parsed && typeof parsed === 'object' && Array.isArray((parsed as Record<string, Object>)['rules']) ?
        (parsed as Record<string, Object>)['rules'] as Object[] : []);
    const rules: Record<string, Object>[] = [];
    for (const item of list) {
      if (item && typeof item === 'object' && !Array.isArray(item)) {
        rules.push(item as Record<string, Object>);
      }
    }
    return rules;
  } catch (_) {
    return [];
  }
}

function ruleString(rule: Record<string, Object>, key: string): string {
  const value = rule[key];
  return typeof value === 'string' ? value : '';
}

/**
 * 把排版和规则里的字体名从导出设备的名字换成本机安装后的名字。
 * 没能安装的自定义字体退回跟随全局字体，并记下字体显示名用于提示。
 */
export function remapFonts(layout: Record<string, Object> | null, rules: Record<string, Object>[],
  installed: Map<string, string>, displayNames: Map<string, string>): string[] {
  const missing: string[] = [];
  const remap = (holder: Record<string, Object>, modeKey: string, familyKey: string): void => {
    if (holder[modeKey] !== 'custom') return;
    const family = typeof holder[familyKey] === 'string' ? holder[familyKey] as string : '';
    const next = installed.get(family);
    if (next) {
      holder[familyKey] = next;
      return;
    }
    holder[modeKey] = 'global';
    holder[familyKey] = '';
    const name = displayNames.get(family) || family;
    if (name && !missing.includes(name)) missing.push(name);
  };
  if (layout) {
    remap(layout, 'bodyFontMode', 'bodyFontFamily');
    remap(layout, 'titleFontMode', 'titleFontFamily');
  }
  for (const rule of rules) {
    remap(rule, 'fontMode', 'fontFamily');
  }
  return missing;
}
