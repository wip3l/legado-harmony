import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const etsRoot = path.join(root, 'entry', 'src', 'main', 'ets');
const mediaRoot = path.join(root, 'entry', 'src', 'main', 'resources', 'base', 'media');

function read(relativePath) {
  return fs.readFileSync(path.join(root, relativePath), 'utf8');
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function jpegDimensions(filePath) {
  const data = fs.readFileSync(filePath);
  assert(data.length >= 4 && data[0] === 0xff && data[1] === 0xd8, `Invalid JPEG: ${filePath}`);
  const sofMarkers = new Set([0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf]);
  let offset = 2;
  while (offset + 9 < data.length) {
    if (data[offset] !== 0xff) {
      offset++;
      continue;
    }
    const marker = data[offset + 1];
    offset += 2;
    if (marker === 0xd8 || marker === 0xd9 || marker === 0x01 || (marker >= 0xd0 && marker <= 0xd7)) {
      continue;
    }
    if (offset + 2 > data.length) break;
    const length = data.readUInt16BE(offset);
    if (sofMarkers.has(marker) && offset + 7 <= data.length) {
      return { width: data.readUInt16BE(offset + 5), height: data.readUInt16BE(offset + 3) };
    }
    if (length < 2) break;
    offset += length;
  }
  throw new Error(`JPEG dimensions are unreadable: ${filePath}`);
}

const models = read('entry/src/main/ets/theme/ThemeModels.ets');
const registry = read('entry/src/main/ets/theme/BuiltinThemeRegistry.ets');
const runtime = read('entry/src/main/ets/theme/ThemeRuntime.ets');
const assets = read('entry/src/main/ets/theme/ThemeAssetRegistry.ets');
const readerThemes = read('entry/src/main/ets/utils/ReaderThemeHelper.ets');
const regexModel = read('entry/src/main/ets/model/reader/ReaderRegexFontRule.ets');
const regexSettings = read('entry/src/main/ets/pages/ReaderFontSettings.ets');
const reader = read('entry/src/main/ets/pages/ReadBook.ets');
const readerPaginator = read('entry/src/main/ets/core/reader/ReaderV2Paginator.ets');
const readerLayoutSettings = read('entry/src/main/ets/components/reader/ReaderLayoutSettings.ets');
const readerBackgroundComponent = read('entry/src/main/ets/components/ReaderThemeBackground.ets');
// 首页各页签已拆到 components/home，检查时与入口页拼在一起看。
const indexPage = read('entry/src/main/ets/pages/Index.ets') + '\n' +
  ['HomeTabShells', 'BookshelfPage', 'ExplorePage', 'SearchPage', 'SettingsTabPage']
    .map((name) => read(`entry/src/main/ets/components/home/${name}.ets`)).join('\n');
const bookModel = read('harmony-book-source-engine/sourceengine/src/main/ets/model/data/Book.ts');
const themePage = read('entry/src/main/ets/pages/ThemeSettings.ets');
const readerSettingsPage = read('entry/src/main/ets/pages/Settings.ets');
const ttsSettingsPage = read('entry/src/main/ets/pages/TtsSettings.ets');
const themeStore = read('entry/src/main/ets/utils/AppThemeSettingsStore.ets');
const readerStore = read('entry/src/main/ets/utils/ReaderSettingsStore.ets');
const moduleConfig = read('entry/src/main/module.json5');
const bookshelfSortHelper = read('entry/src/main/ets/utils/BookshelfSortHelper.ets');
const recentReadCardData = read('entry/src/main/ets/utils/RecentReadCardData.ets');
const themeColorPage = read('entry/src/main/ets/pages/ThemeColorSettings.ets');
const otherSettingsPage = read('entry/src/main/ets/pages/OtherSettings.ets');
const bookSourcePage = read('entry/src/main/ets/pages/BookSource.ets');
const searchCoordinator = read('entry/src/main/ets/core/book/SearchCoordinator.ts');
const sourcePickerKit = read('entry/src/main/ets/components/home/SourcePickerKit.ets');
const appIconManager = read('entry/src/main/ets/utils/AppIconManager.ets');
const fontBootstrap = read('entry/src/main/ets/utils/ReaderFontBootstrap.ets');
const entryAbility = read('entry/src/main/ets/entryability/EntryAbility.ets');
const serverIndex = read('server/src/index.ts');
const serverThemeCatalog = read('server/migrations/011_theme_catalog.sql') + '\n' +
  read('server/migrations/012_qingluan_water_theme.sql') + '\n' +
  read('server/migrations/013_cat_pipi_theme.sql') + '\n' +
  read('server/migrations/014_anime_themes.sql') + '\n' +
  read('server/migrations/015_letterpress_page_theme.sql') + '\n' +
  read('server/migrations/024_neon_harbor_theme.sql');
const pages = JSON.parse(read('entry/src/main/resources/base/profile/main_pages.json'));

const expectedThemes = [
  'classic-blue', 'warm-paper', 'forest-mist', 'ink-wash', 'neon-night', 'sword-frost',
  'qingluan-water', 'cat-pipi', 'azure-mecha', 'starwish-magic', 'letterpress-page', 'obsidian-archive', 'neon-harbor'
];
for (const themeId of expectedThemes) {
  assert(models.includes(`'${themeId}'`), `Theme id is missing from ThemeModels: ${themeId}`);
  assert(registry.includes(`ThemeIds.`), 'Builtin registry is not using stable ThemeIds');
}
const redeemableThemeIds = [
  'classic-blue', 'warm-paper', 'forest-mist', 'ink-wash', 'neon-night',
  'strawberry-cream', 'crimson-archive', 'plum-tea', 'rose-letter', 'moon-crane', 'sword-frost',
  'qingluan-water', 'cat-pipi', 'azure-mecha', 'starwish-magic', 'letterpress-page', 'neon-harbor'
];
for (const themeId of redeemableThemeIds) {
  assert(serverThemeCatalog.includes(`('${themeId}'`), `Database theme catalog is missing: ${themeId}`);
}
assert(serverIndex.includes('findRedeemableTheme(client, themeId)'),
  'Theme redemption must use the database catalog');
assert((registry.match(/themes\.push\(/g) || []).length >= expectedThemes.length,
  `Builtin registry must publish at least ${expectedThemes.length} themes`);
assert(registry.includes('static register(theme: ThemePack)'), 'Compiled theme registration API is missing');

const expectedBackgrounds = [
  'paper-light', 'paper-dark', 'forest-light', 'forest-dark',
  'ink-light', 'ink-dark', 'neon-light', 'neon-dark',
  'sword-frost-light', 'sword-frost-dark', 'qingluan-water-light', 'qingluan-water-dark',
  'cat-pipi-light', 'cat-pipi-dark', 'azure-mecha-light', 'azure-mecha-dark',
  'starwish-magic-light', 'starwish-magic-dark', 'letterpress-page-light', 'letterpress-page-dark',
  'neon-harbor-light', 'neon-harbor-dark'
];
for (const assetId of expectedBackgrounds) {
  assert(assets.includes(`'${assetId}'`), `Background asset id is not mapped: ${assetId}`);
  assert(registry.includes(`'${assetId}'`), `No builtin theme uses background asset: ${assetId}`);
}

const resourceNames = [...assets.matchAll(/\$r\('app\.media\.([^']+)'\)/g)].map(match => match[1]);
for (const resourceName of resourceNames) {
  const found = fs.readdirSync(mediaRoot).some(fileName => path.parse(fileName).name === resourceName);
  assert(found, `ThemeAssetRegistry references a missing resource: ${resourceName}`);
}

const backgroundFiles = fs.readdirSync(mediaRoot).filter(fileName => /^reader_bg_.*\.svg$/.test(fileName));
assert(backgroundFiles.length >= 8, 'At least eight light/dark reader background SVGs are required');
for (const fileName of backgroundFiles) {
  const source = fs.readFileSync(path.join(mediaRoot, fileName), 'utf8');
  assert(/viewBox="0 0 1080 1920"/.test(source), `Invalid reader background viewBox: ${fileName}`);
  assert(/width="1080"/.test(source) && /height="1920"/.test(source),
    `Invalid reader background dimensions: ${fileName}`);
  assert(!/(<script|<image|<use|href=|url\(|<filter)/i.test(source), `Unsafe SVG feature in ${fileName}`);
}

const readerDecorationFiles = fs.readdirSync(mediaRoot).filter(fileName => /^reader_decor_.*\.svg$/.test(fileName));
assert(readerDecorationFiles.length >= 18, 'Every light/dark builtin reader background needs a responsive ornament');
for (const fileName of readerDecorationFiles) {
  const source = fs.readFileSync(path.join(mediaRoot, fileName), 'utf8');
  assert(/viewBox="0 0 480 480"/.test(source), `Invalid reader decoration viewBox: ${fileName}`);
  assert(/width="480"/.test(source) && /height="480"/.test(source),
    `Invalid reader decoration dimensions: ${fileName}`);
  assert(!/(<script|<image|<use|href=|url\(|<filter)/i.test(source), `Unsafe SVG feature in ${fileName}`);
}

// Reader backgrounds pair the top-left ornament with a dedicated bottom-right drawing, not a mirror.
const assetRegistrySource = read('entry/src/main/ets/theme/ThemeAssetRegistry.ets');
for (const name of ['paper', 'forest', 'ink', 'neon', 'strawberry', 'crimson', 'plum_tea', 'rose_letter',
  'moon_crane', 'sword_frost', 'qingluan_water', 'azure_mecha', 'starwish_magic', 'letterpress_page', 'neon_harbor']) {
  for (const mode of ['light', 'dark']) {
    const resourceName = `reader_decor_${name}_trailing_${mode}`;
    assert(fs.existsSync(path.join(mediaRoot, `${resourceName}.svg`)),
      `Reader trailing ornament is missing: ${resourceName}.svg`);
    assert(assetRegistrySource.includes(`app.media.${resourceName}`),
      `Reader trailing ornament is not mapped in ThemeAssetRegistry: ${resourceName}`);
  }
}

// Every builtin theme ships its own TTS / audiobook panel artwork in both modes.
const ttsPanelThemeNames = [
  'plain_default', 'classic_blue', 'warm_paper', 'forest_mist', 'ink_wash', 'neon_night', 'strawberry_cream',
  'crimson_archive', 'plum_tea', 'rose_letter', 'moon_crane', 'sword_frost', 'qingluan_water', 'cat_pipi',
  'azure_mecha', 'starwish_magic', 'letterpress_page', 'neon_harbor'
];
const ttsPanelStyles = read('entry/src/main/ets/theme/TtsPanelThemeStyles.ets');
for (const themeName of ttsPanelThemeNames) {
  for (const mode of ['light', 'dark']) {
    const resourceName = `tts_panel_${themeName}_${mode}`;
    if (themeName === 'neon_harbor') {
      const dimensions = jpegDimensions(path.join(mediaRoot, `${resourceName}.jpg`));
      assert(dimensions.width === 720 && dimensions.height === 520, `Invalid TTS bitmap dimensions: ${resourceName}`);
      assert(ttsPanelStyles.includes(`app.media.${resourceName}`), `Unmapped TTS bitmap: ${resourceName}`);
      continue;
    }
    const filePath = path.join(mediaRoot, `${resourceName}.svg`);
    assert(fs.existsSync(filePath), `TTS panel artwork is missing: ${resourceName}.svg`);
    const source = fs.readFileSync(filePath, 'utf8');
    assert(/viewBox="0 0 720 520"/.test(source), `Invalid TTS panel artwork viewBox: ${resourceName}.svg`);
    assert(!/(<script|<image|<use|href=|url\(|<filter)/i.test(source), `Unsafe SVG feature in ${resourceName}.svg`);
    assert(ttsPanelStyles.includes(`app.media.${resourceName}`),
      `TTS panel artwork is not mapped in TtsPanelThemeStyles: ${resourceName}`);
  }
}
assert(read('entry/src/main/ets/components/ReaderTtsPlayerPanel.ets').includes('TtsPanelThemeBackground('),
  'TTS player panel must draw the themed panel background');
assert(themePage.includes('this.storeTtsPane(theme, customSchemeId, inPager)'),
  'Theme previews must include the TTS panel pane');

const themedIconFiles = fs.readdirSync(mediaRoot).filter(fileName => /^ic_theme_.*\.svg$/.test(fileName));
assert(themedIconFiles.length >= 8, 'Rounded and ink icon packs must each contain four icons');
for (const fileName of themedIconFiles) {
  const source = fs.readFileSync(path.join(mediaRoot, fileName), 'utf8');
  assert(/viewBox="0 0 24 24"/.test(source), `Invalid themed icon viewBox: ${fileName}`);
  assert(!/(<script|<image|<use|href=|url\(|<filter)/i.test(source), `Unsafe SVG feature in ${fileName}`);
  if (/^ic_theme_(obsidian_archive|neon_harbor)_/.test(fileName)) {
    assert(!/stroke=|fill="none"/.test(source), `Exclusive tab icon needs filled outlines for tinting: ${fileName}`);
  }
}

const themeLogoFiles = fs.readdirSync(mediaRoot).filter(fileName => /^theme_logo_.*\.svg$/.test(fileName));
assert(themeLogoFiles.length >= expectedThemes.length, 'Every builtin theme must provide a dedicated logo');
for (const fileName of themeLogoFiles) {
  const source = fs.readFileSync(path.join(mediaRoot, fileName), 'utf8');
  assert(/viewBox="0 0 64 64"/.test(source), `Invalid theme logo viewBox: ${fileName}`);
  assert(!/(<script|<image|<use|href=|url\(|<filter)/i.test(source), `Unsafe SVG feature in ${fileName}`);
}
assert(assets.includes('static themeLogo(themeId: string)'), 'Theme logo resolver is missing');

const swordFrostJpegs = [
  'theme_startup_sword_frost.jpg',
  'theme_cover_sword_frost_01.jpg', 'theme_cover_sword_frost_02.jpg',
  'theme_cover_sword_frost_03.jpg', 'theme_cover_sword_frost_04.jpg',
  'theme_cover_sword_frost_05.jpg', 'theme_cover_sword_frost_06.jpg',
  'theme_folder_art_sword_frost.jpg'
];
for (const fileName of ['theme_startup_neon_harbor.jpg', 'theme_folder_art_neon_harbor.jpg',
  ...Array.from({ length: 6 }, (_, i) => `theme_cover_neon_harbor_0${i + 1}.jpg`)]) {
  const dimensions = jpegDimensions(path.join(mediaRoot, fileName));
  const expected = fileName.includes('startup') ? { width: 841, height: 1870 } : { width: 450, height: 660 };
  assert(dimensions.width === expected.width && dimensions.height === expected.height,
    `Invalid Neon Harbor artwork dimensions: ${fileName}`);
}
for (const fileName of ['theme_startup_obsidian_archive.jpg', 'theme_cover_obsidian_archive_01.jpg',
  'theme_cover_obsidian_archive_02.jpg', 'theme_cover_obsidian_archive_03.jpg',
  'theme_cover_obsidian_archive_04.jpg', 'theme_cover_obsidian_archive_05.jpg',
  'theme_cover_obsidian_archive_06.jpg', 'theme_folder_art_obsidian_archive.jpg']) {
  const dimensions = jpegDimensions(path.join(mediaRoot, fileName));
  const expected = fileName.includes('startup') ? { width: 841, height: 1870 } : { width: 450, height: 660 };
  assert(dimensions.width === expected.width && dimensions.height === expected.height,
    `Invalid Obsidian artwork dimensions: ${fileName}`);
}
for (const fileName of swordFrostJpegs) {
  const filePath = path.join(mediaRoot, fileName);
  assert(fs.existsSync(filePath), `Sword Frost artwork is missing: ${fileName}`);
  const dimensions = jpegDimensions(filePath);
  const expected = fileName === 'theme_startup_sword_frost.jpg' ? { width: 841, height: 1870 } :
    { width: 450, height: 660 };
  assert(dimensions.width === expected.width && dimensions.height === expected.height,
    `Invalid Sword Frost artwork dimensions: ${fileName}`);
}
const swordFrostSvgs = [
  'theme_logo_sword_frost.svg', 'theme_frame_sword_frost.svg',
  'reader_bg_sword_frost_light.svg', 'reader_bg_sword_frost_dark.svg',
  'reader_decor_sword_frost_light.svg', 'reader_decor_sword_frost_dark.svg',
  'ic_theme_sword_frost_bookshelf.svg', 'ic_theme_sword_frost_explore.svg',
  'ic_theme_sword_frost_search.svg', 'ic_theme_sword_frost_mine.svg',
  'regex_frame_sword_talisman.svg', 'regex_cap_sword_talisman.svg'
];
for (const fileName of swordFrostSvgs) {
  assert(fs.existsSync(path.join(mediaRoot, fileName)), `Sword Frost vector asset is missing: ${fileName}`);
}

const qingluanWaterJpegs = [
  'theme_startup_qingluan_water.jpg',
  'theme_cover_qingluan_water_01.jpg', 'theme_cover_qingluan_water_02.jpg',
  'theme_cover_qingluan_water_03.jpg', 'theme_cover_qingluan_water_04.jpg',
  'theme_cover_qingluan_water_05.jpg', 'theme_cover_qingluan_water_06.jpg',
  'theme_folder_art_qingluan_water.jpg'
];
for (const fileName of qingluanWaterJpegs) {
  const filePath = path.join(mediaRoot, fileName);
  assert(fs.existsSync(filePath), `Qingluan Water artwork is missing: ${fileName}`);
  const dimensions = jpegDimensions(filePath);
  const expected = fileName === 'theme_startup_qingluan_water.jpg' ? { width: 841, height: 1870 } :
    { width: 450, height: 660 };
  assert(dimensions.width === expected.width && dimensions.height === expected.height,
    `Invalid Qingluan Water artwork dimensions: ${fileName}`);
}
const qingluanWaterSvgs = [
  'theme_logo_qingluan_water.svg', 'theme_frame_qingluan_water.svg',
  'reader_bg_qingluan_water_light.svg', 'reader_bg_qingluan_water_dark.svg',
  'reader_decor_qingluan_water_light.svg', 'reader_decor_qingluan_water_dark.svg',
  'ic_theme_qingluan_water_bookshelf.svg', 'ic_theme_qingluan_water_explore.svg',
  'ic_theme_qingluan_water_search.svg', 'ic_theme_qingluan_water_mine.svg',
  'regex_frame_qingluan_jade.svg', 'regex_cap_qingluan_jade.svg'
];
for (const fileName of qingluanWaterSvgs) {
  assert(fs.existsSync(path.join(mediaRoot, fileName)), `Qingluan Water vector asset is missing: ${fileName}`);
}

const catPipiJpegs = [
  'theme_startup_cat_pipi.jpg',
  'theme_cover_cat_pipi_01.jpg', 'theme_cover_cat_pipi_02.jpg',
  'theme_cover_cat_pipi_03.jpg', 'theme_cover_cat_pipi_04.jpg',
  'theme_cover_cat_pipi_05.jpg', 'theme_cover_cat_pipi_06.jpg',
  'theme_folder_art_cat_pipi.jpg'
];
for (const fileName of catPipiJpegs) {
  const filePath = path.join(mediaRoot, fileName);
  assert(fs.existsSync(filePath), `Cat Pipi artwork is missing: ${fileName}`);
  const dimensions = jpegDimensions(filePath);
  const expected = fileName === 'theme_startup_cat_pipi.jpg' ? { width: 841, height: 1870 } :
    { width: 450, height: 660 };
  assert(dimensions.width === expected.width && dimensions.height === expected.height,
    `Invalid Cat Pipi artwork dimensions: ${fileName}`);
}
const catPipiSvgs = [
  'theme_logo_cat_pipi.svg', 'theme_frame_cat_pipi.svg',
  'reader_bg_cat_pipi_light.svg', 'reader_bg_cat_pipi_dark.svg',
  'reader_decor_cat_pipi_light.svg', 'reader_decor_cat_pipi_dark.svg',
  'ic_theme_cat_pipi_bookshelf.svg', 'ic_theme_cat_pipi_explore.svg',
  'ic_theme_cat_pipi_search.svg', 'ic_theme_cat_pipi_mine.svg',
  'regex_frame_pipi_soft_paw.svg', 'regex_cap_pipi_soft_paw.svg'
];
for (const fileName of catPipiSvgs) {
  assert(fs.existsSync(path.join(mediaRoot, fileName)), `Cat Pipi vector asset is missing: ${fileName}`);
}

const bubbleStyles = ['qq-soft', 'qq-solid', 'capsule', 'paper', 'neon', 'sword-talisman', 'qingluan-jade',
  'pipi-soft-paw', 'mecha-comm', 'starwish-ribbon', 'pencil-mark', 'gilded-orbit', 'harbor-postcard'];
for (const styleId of bubbleStyles) {
  assert(models.includes(`'${styleId}'`), `Bubble style is missing from ThemeModels: ${styleId}`);
  assert(regexModel.includes(`'${styleId}'`), `Bubble resolver/codec is missing style: ${styleId}`);
  assert(regexSettings.includes(`'${styleId}'`), `Reader font settings cannot select style: ${styleId}`);
}
assert(regexModel.includes('schemaVersion: number = 3'), 'Regex rule schema must be version 3');
assert(regexSettings.includes('ReaderRegexFontCodec.decode'), 'Settings page must use the shared regex codec');
assert(reader.includes('ReaderRegexFontCodec.decode'), 'Reader page must use the shared regex codec');
// The TTS focus is painted from paragraph geometry as its own layer above the text and regex bubbles.
assert(reader.includes('readerV2TtsHighlightRects(') && reader.includes('this.readerCurrentV2TtsOverlay('),
  'TTS highlight overlay is missing');
assert(reader.includes('start >= displayText.length || regex.lastIndex >= displayText.length'),
  'Reader zero-length regex guard is missing');
assert(regexSettings.includes('start >= text.length || regex.lastIndex >= text.length'),
  'Preview zero-length regex guard is missing');

assert(readerThemes.includes('APP_THEME_INDEX: number = 4'), 'Reader app-theme compatibility index is missing');
assert(runtime.includes("KEY_THEME_REVISION"), 'Theme runtime revision broadcast is missing');
assert(readerBackgroundComponent.includes('ThemeAssetRegistry.readerBackgroundDecoration'),
  'Responsive reader background decoration resolver is not connected');
assert(reader.includes('ReaderThemeBackground({') && reader.includes('customImageFit: this.getBackgroundImageFit()'),
  'Reader root surface does not draw the responsive theme background');
assert(readerBackgroundComponent.includes('.objectFit(ImageFit.Contain)') &&
  !readerBackgroundComponent.includes('.border('),
  'Builtin reader backgrounds must preserve ornament proportions and draw no frame border');
assert(indexPage.includes('ThemeRuntime.iconPackId()'), 'Floating tab bar does not resolve the active icon pack');
for (const tabId of ['bookshelf', 'explore', 'search', 'mine']) {
  assert(indexPage.includes(`this.navigationIcon('${tabId}')`), `Floating tab icon is not themed: ${tabId}`);
}
assert(indexPage.includes('this.shelfSortButton()') &&
  indexPage.includes('shelfSortDropdown()') &&
  indexPage.includes("this.sortDropdownItem('新阅读', 'recentRead')") &&
  !indexPage.includes("this.sortChip('新阅读', 'recentRead')"),
  'Bookshelf sorting must use a compact dropdown selector');
assert(indexPage.includes('this.shelfScopeTabs()') &&
  indexPage.includes('this.shelfScopeTabIndicatorX()') &&
  indexPage.includes("TYPE_TAB_IDS: string[] = ['all', 'text', 'image', 'audio', 'video']") &&
  indexPage.includes('this.refreshShelfTypeTabs()') &&
  indexPage.includes('this.switchShelfScopeBySelection(id)') &&
  !indexPage.includes('expandedShelfScopeSegment()'),
  'Bookshelf tabs must switch book types, hide empty types and keep the private shelf out of the bar');
assert(indexPage.includes('this.shelfFilterButton()') &&
  indexPage.includes("FILTER_SOURCE_KEYS: string[] = ['network', 'local']") &&
  indexPage.includes("FILTER_STATUS_KEYS: string[] = ['finished', 'ongoing']") &&
  indexPage.includes('this.matchesShelfFilters(book)'),
  'Bookshelf filter must offer source and status conditions beside the layout button');
assert(indexPage.includes('ImmersiveMaterialSurface({') &&
  read('entry/src/main/ets/components/ImmersiveMaterialSurface.ets').includes('barFloatingStyle({'),
  'Bookshelf header controls must sit on the HDS immersive material surface');
assert(indexPage.includes('this.shelfMenuPopupOptions(') &&
  indexPage.includes('ImmersiveMaterialRuntime.popupMenuOptions(') &&
  !indexPage.includes('shelfSortFloatingMenu()') && !indexPage.includes('shelfGroupFloatingMenu()'),
  'Bookshelf header dropdowns must use system popups with the immersive material');
assert((indexPage.includes("this.actionItem('多选'") ||
  indexPage.includes("this.contextActionItem($r('sys.symbol.checkmark_circle'), '多选'")) &&
  indexPage.includes('this.bookMultiSelectBar()'),
  'Bookshelf multi-select entry and action bar must stay connected');
assert(indexPage.includes('this.shelfGroupSwitcher()') &&
  indexPage.includes("this.shelfGroupMenuItem('未分组', -1)") && indexPage.includes("Text('新建分组')"),
  'Bookshelf group menu must include ungrouped and add-group actions');
const settingsPageSource = indexPage.slice(indexPage.indexOf('struct SettingsPage'));
assert(settingsPageSource.includes('.backgroundColor(this.pageColor())'),
  'Mine page background is not connected to the active theme');
assert(!settingsPageSource.includes(".backgroundColor(this.appDarkMode ? '#101113' : '#F5F5F5')"),
  'Mine page still contains the legacy fixed background color');
assert(settingsPageSource.includes('ThemeRuntime.primaryTextColor') &&
  settingsPageSource.includes('ThemeRuntime.subTextColor'),
  'Mine page semantic text colors are not connected to ThemeRuntime');
assert(settingsPageSource.includes('menuItem(icon: Resource, title: string, showDivider: boolean, onClick: () => void)') &&
  settingsPageSource.includes('SymbolGlyph(icon)') &&
  settingsPageSource.includes("SymbolGlyph($r('sys.symbol.chevron_right'))") &&
  settingsPageSource.includes('Divider()') &&
  settingsPageSource.includes('dividerColor()'),
  'Mine page menu items must use official symbols and themed dividers');
assert(fontBootstrap.includes('ThemeRuntime.fontFamily()'), 'Cold-start font bootstrap ignores the theme font');
// First content now waits for theme + light + member settings together; fonts additionally wait
// for the theme-dependent reader settings. Do not require the former single-promise spelling.
assert(/Promise\.all\(\[this\.themeBootstrapPromise,[\s\S]*?\]\)\.finally\(\(\) => \{\s*this\.loadStartupContent\(windowStage\)/.test(entryAbility) &&
  /this\.readerBootstrapPromise\s*\.then\(\(\) => ReaderFontBootstrap\.registerFromSettings/.test(entryAbility) &&
  entryAbility.includes('this.scheduleDeferredStartupInitialization()') &&
  entryAbility.includes("'ability-after-first-content'"),
  'Theme bootstrap and first content must finish before font bootstrap');
assert(themeStore.includes('KEY_THEME_ID') && themeStore.includes('createForTheme'),
  'Theme id persistence or theme selection factory is missing');
assert(models.includes("static readonly CUSTOM: string = 'custom'"), 'Custom theme id is missing');
assert(themeStore.includes('KEY_CUSTOM_LIGHT_ACCENT_COLOR') &&
  themeStore.includes('settings.lightAccentColor),') &&
  themeStore.includes('activateTheme(themeId: string, previous: AppThemeSettings)'),
  'Custom colors are not persisted, migrated, or preserved across builtin theme changes');
assert(themeStore.includes('loadMigratedReaderAppearance') &&
  themeStore.includes('ReaderThemeHelper.themeAt') &&
  themeStore.includes('persistCustomSnapshot'),
  'Existing reader backgrounds are not migrated into the initial custom theme snapshot');
assert(themePage.includes('AppThemeSettingsStore.customTheme(scheme.settings, this.appDarkMode)') &&
  themePage.includes('this.activeVariant(theme).reader.backgroundColor'),
  'Custom theme preview does not use the persisted reader background');
assert(!themeColorPage.includes("'pages/AppIconSettings'") &&
  !themeColorPage.includes("'pages/FontSettings'") &&
  !themeStore.includes('updateCustomFont') && !themeStore.includes('updateCustomDesktopIcon'),
  'Theme and appearance must remain independent from fonts and desktop icons');
// 主题页重做后“默认与自定义”区块由 myThemesSectionTitle() 起头，排在“已购主题”“更多主题”之前。
assert(themePage.includes('this.myThemesSectionTitle()') &&
  themePage.indexOf('this.myThemesSectionTitle()') < themePage.indexOf("this.sectionTitle('已购主题')") &&
  themePage.indexOf('this.myThemesSectionTitle()') < themePage.indexOf("this.sectionTitle('更多主题')") &&
  themePage.includes("url: 'pages/ThemeColorSettings'"),
  'Theme page does not expose the custom theme before builtin themes');
assert(themeColorPage.includes('settings.themeId = ThemeIds.CUSTOM') &&
  themeColorPage.includes('settings.customLightAccentColor = this.lightAccentColor'),
  'Color edits do not automatically activate and update the custom theme');
assert(!otherSettingsPage.includes("router.pushUrl({ url: 'pages/ThemeColorSettings' })"),
  'Other settings still exposes the removed legacy theme-color entry');
assert(themePage.includes('ReaderThemeHelper.APP_THEME_INDEX'), 'Theme selection does not enable the app reader theme');
// Global fonts are preserved by the settings store when switching theme profiles.
// The theme page delegates to that store and reapplies the selected application font.
assert(themePage.includes('await ReaderSettingsStore.switchThemeProfile(') &&
  themePage.includes('ReaderFontBootstrap.applyApplicationFont('),
  'Theme selection must switch reader profiles and reapply the global application font');
const switchThemeProfile = readerStore.match(/static async switchThemeProfile\b[\s\S]*?(?=\n  static async )/)?.[0] || '';
const preserveFontsAt = switchThemeProfile.indexOf('ReaderSettingsStore.copyGlobalFontSettings(current, next)');
assert(preserveFontsAt >= 0 &&
  preserveFontsAt < switchThemeProfile.indexOf('ReaderSettingsStore.persistThemeProfile(store, nextId, next)') &&
  preserveFontsAt < switchThemeProfile.indexOf('ReaderSettingsStore.applyToStorage(next)'),
  'Theme profile switching must preserve global fonts before persisting or applying the next profile');
const copyGlobalFontSettings = readerStore.match(/private static copyGlobalFontSettings\b[\s\S]*?(?=\n  private static )/)?.[0] || '';
for (const field of ['fontFamily', 'fontFilePath', 'fontSourceName', 'fontMode', 'systemFontFamily', 'customFontsRaw']) {
  assert(copyGlobalFontSettings.includes(`target.${field} = source.${field};`),
    `Theme profile switching must preserve the global font setting: ${field}`);
}
assert(/if \(activeFamily && AppStorage\.get<boolean>\('readerFontRegistered'\)\)\s*\{\s*return activeFamily;/.test(fontBootstrap),
  'A registered global font must take precedence over the theme application font');
assert(themePage.includes('AppIconManager.optionById(this.appIconId).preview') &&
  !themePage.includes("Text('Aa')") &&
  !themePage.includes('颜色、阅读背景、正则气泡与悬浮底栏已统一'),
  'Current theme summary must display the actual desktop icon without the legacy description');
assert(runtime.includes('static accentSurfaceColor(darkMode: boolean)'),
  'Theme runtime does not expose a themed selected-surface color');
assert(ttsSettingsPage.includes('? this.accentColor() : this.inputColor()') &&
  ttsSettingsPage.includes('.backgroundColor(this.inputColor())'),
  'TTS voice or speed controls are not connected to theme surfaces');
assert(!readerSettingsPage.includes("this.appDarkMode ? '#24272D' : '#F0F2F5'"),
  'Reader settings still contains legacy fixed control backgrounds');
for (const marginName of ['Left', 'Right', 'Top', 'Bottom']) {
  assert(readerStore.includes(`KEY_MARGIN_${marginName.toUpperCase()}`) &&
    reader.includes(`readerMargin${marginName}`),
    `Reader ${marginName.toLowerCase()} margin is not persisted or applied`);
}
assert(readerSettingsPage.includes('this.typographyStepper()') &&
  readerSettingsPage.includes('Select(this.typographySettingOptions())') &&
  readerSettingsPage.includes('return ReaderTypographyField.LABELS.map((label: string): SelectOption => ({ value: label }))') &&
  readerLayoutSettings.includes("'左边距', '右边距', '上边距', '下边距'") &&
  readerSettingsPage.includes('adjustCurrentTypographySetting'),
  'Reader typography dropdown/stepper does not expose all four margins');
assert(reader.includes('input.marginLeftPx = this.toMeasurePx(this.getEffectiveReaderMarginLeft())') &&
  reader.includes('input.marginRightPx = this.toMeasurePx(this.getEffectiveReaderMarginRight())') &&
  reader.includes('this.toMeasurePx(this.getEffectiveReaderMarginTop())') &&
  reader.includes('this.toMeasurePx(this.getEffectiveReaderMarginBottom())'),
  'Reader pagination does not account for configured margins');
// Body rendering and pagination must resolve alignment from the same reader
// setting.  The reader intentionally supports start/end/justify now, so do
// not require the old hard-coded JUSTIFY literals here.
assert(reader.includes('readerTextAlignValue(): TextAlign') &&
  reader.includes("if (this.readerTextAlign === 'start') return TextAlign.Start") &&
  reader.includes("if (this.readerTextAlign === 'end') return TextAlign.End") &&
  reader.includes('.textAlign(this.readerTextAlignValue())') &&
  reader.includes('input.textAlign = this.readerTextAlign') &&
  readerPaginator.includes('align: ReaderV2Paginator.textAlign(snapshot.textAlign)') &&
  readerPaginator.includes("if (value === 'start') return graphicsText.TextAlign.LEFT") &&
  readerPaginator.includes("if (value === 'end') return graphicsText.TextAlign.RIGHT"),
  'Reader body rendering and pagination measurement must use the shared text alignment setting');
// Pages break on native line metrics, so no measured page end is ever rolled back to a sentence boundary.
assert(reader.includes('input.bodyFontFamily = this.getBodyReaderFontFamily()') &&
  readerPaginator.includes('fontFamilies: [heading ? snapshot.titleFontFamily : snapshot.bodyFontFamily]'),
  'Reader pagination measurement must use the same body font as rendering');
assert(reader.includes('this.readerTypographySettingsPanel()') &&
  reader.includes('readerTypographyCombinedSettings()') &&
  reader.includes('ReaderTypographyStepper({') &&
  readerLayoutSettings.includes("'左边距', '右边距', '上边距', '下边距'") &&
  readerLayoutSettings.includes('static clamp(field: number, value: number)') &&
  reader.includes('onReaderTypographyDraftChange') &&
  reader.includes('commitReaderTypographyDraft'),
  'In-reader settings do not provide the shared typography controls');
assert(bookModel.includes('static hasStartedReading(book: Book | null)') &&
  bookModel.includes("book.getVariable('readStarted')"),
  'Book model must provide a shared started-reading check');
assert(reader.includes("this.book.putVariable('readStarted', '1')") &&
  reader.includes('!Book.hasStartedReading(this.book) && chapterIndex <= 0 && pageIndex <= 0') &&
  reader.includes('if (Book.hasStartedReading(this.book))'),
  'Reader must not persist first-open progress before the reader turns forward');
assert(indexPage.includes('Book.hasStartedReading(book)') &&
  bookshelfSortHelper.includes('!Book.hasStartedReading(book)') &&
  recentReadCardData.includes('!Book.hasStartedReading(book)'),
  'Bookshelf and recent-read surfaces must treat unopened first pages as unread');
assert(readerSettingsPage.includes("this.selectItem('翻页方式'") &&
  reader.includes("this.readerSelectSettingItem('翻页方式'") &&
  !readerSettingsPage.includes('this.pageTurnOptions()') &&
  !reader.includes('pageTurnModeButton('),
  'Page-turn mode must use dropdown selectors in both settings entries');
assert(readerSettingsPage.includes('if (this.readerPageTurnMode === 2)') &&
  readerSettingsPage.includes('this.tapZoneSettingItem()') &&
  readerSettingsPage.includes('ReaderSettingsStore.saveTapZoneActions') &&
  readerSettingsPage.includes('TapZoneSettingsDialogContent({') &&
  reader.includes('TapZoneSettingsDialogContent({'),
  'Reading settings must expose the shared tap-zone action editor for click page turning');
assert(bookSourcePage.includes('checkOptionsDialog()') &&
  bookSourcePage.includes("this.checkActionOption('自动禁用'") &&
  bookSourcePage.includes("this.checkActionOption('自动删除'") &&
  bookSourcePage.includes('handleCheckedSourceCompletion') &&
  searchCoordinator.includes('await options.onSourceComplete'),
  'Book source validation must support immediate disable/delete actions per completed source');
// 搜索框与搜索范围面板共用 SourcePickerKit 的 SourcePickerSearchField。
assert(indexPage.includes('SourcePickerSearchField({') &&
  sourcePickerKit.includes("SEARCH_PLACEHOLDER: string = '搜索书源名称、地址或分组'") &&
  /struct SourcePickerSearchField[\s\S]*?TextInput\(/.test(sourcePickerKit) &&
  indexPage.includes('this.exploreSourcePickerContent()') &&
  !indexPage.includes('builder: this.exploreSourcePopup') &&
  indexPage.includes('applyExploreSourceFilter') &&
  indexPage.includes('getFilteredExploreSourceOptions()'),
  'Explore source picker must filter sources by keyword inside the immersive popup');
assert(indexPage.includes('this.exploreChannelBar()') &&
  indexPage.includes('this.explorePlatformMenuContent()') &&
  indexPage.includes('this.exploreFilterPopupContent()') &&
  !indexPage.includes('compactExploreFilterBar()') && !indexPage.includes('inlineExploreFilterRow('),
  'Explore header must stay at a title row plus one channel bar, with modes and filters in popups');
assert(indexPage.includes('this.searchScopeLabel()') &&
  indexPage.includes('this.searchSettingsContent()') &&
  indexPage.includes('this.searchIdleContent()') &&
  !indexPage.includes('searchSettingsDialog()'),
  'Search header must use the title row scope label, a settings popup and inline search history');
assert(!themePage.includes("'衬线字体'") && !themePage.includes("'清晰字体'") &&
  !themePage.includes("'水墨图标'") && !themePage.includes("'主题图标'") &&
  !themePage.includes('themeFeatureChips') && !themePage.includes('featureChip(') &&
  !themePage.includes("this.advancedEntry('字体管理'") &&
  !themePage.includes("this.advancedEntry('桌面图标'"),
  'Theme page must not expose font descriptions, font management, or desktop icon entries');
assert(pages.src.includes('pages/ThemeSettings'), 'Theme settings page is not registered');
assert(moduleConfig.includes('"orientation": "auto_rotation_restricted"'),
  'Entry ability orientation must respect the system rotation lock');

const desktopThemeIcons = [
  'classic_blue', 'warm_paper', 'forest_mist', 'ink_wash', 'neon_night'
];
for (const iconName of desktopThemeIcons) {
  const fileName = `ic_app_theme_${iconName}.png`;
  const filePath = path.join(root, 'AppScope/resources/base/media', fileName);
  assert(fs.existsSync(filePath), `Theme desktop icon is missing: ${fileName}`);
  const png = fs.readFileSync(filePath);
  assert(png.length < 500 * 1024, `Theme desktop icon exceeds 500 KB: ${fileName}`);
  assert(png.readUInt32BE(16) === 216 && png.readUInt32BE(20) === 216,
    `Theme desktop icon must be 216x216: ${fileName}`);
  assert(appIconManager.includes(`app.media.ic_app_theme_${iconName}`),
    `Theme desktop icon is not available in app settings: ${fileName}`);
}

const requiredFiles = [
  'theme/ThemeModels.ets', 'theme/BuiltinThemeRegistry.ets', 'theme/ThemeRuntime.ets',
  'theme/ThemeAssetRegistry.ets', 'theme/TtsPanelThemeStyles.ets', 'components/ReaderThemeBackground.ets',
  'components/TtsPanelThemeBackground.ets', 'pages/ThemeSettings.ets'
];
for (const relativePath of requiredFiles) {
  assert(fs.existsSync(path.join(etsRoot, relativePath)), `Required theme file is missing: ${relativePath}`);
}

const pageRoot = path.join(etsRoot, 'pages');
for (const fileName of fs.readdirSync(pageRoot).filter(fileName => fileName.endsWith('.ets'))) {
  const source = fs.readFileSync(path.join(pageRoot, fileName), 'utf8');
  if (source.includes('pageColor(): string')) {
    assert(source.includes('ThemeRuntime.pageColor'), `Page color is not connected to ThemeRuntime: ${fileName}`);
  }
}

console.log(`Theme framework check passed: ${expectedThemes.length} themes, ` +
  `${backgroundFiles.length} legacy backgrounds, ${readerDecorationFiles.length} responsive ornaments, ` +
  `${themedIconFiles.length} themed icons, ` +
  `${bubbleStyles.length} bubble styles.`);
