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

const models = read('entry/src/main/ets/theme/ThemeModels.ets');
const registry = read('entry/src/main/ets/theme/BuiltinThemeRegistry.ets');
const runtime = read('entry/src/main/ets/theme/ThemeRuntime.ets');
const assets = read('entry/src/main/ets/theme/ThemeAssetRegistry.ets');
const readerThemes = read('entry/src/main/ets/utils/ReaderThemeHelper.ets');
const regexModel = read('entry/src/main/ets/model/reader/ReaderRegexFontRule.ets');
const regexSettings = read('entry/src/main/ets/pages/ReaderFontSettings.ets');
const reader = read('entry/src/main/ets/pages/ReadBook.ets');
const indexPage = read('entry/src/main/ets/pages/Index.ets');
const bookModel = read('entry/src/main/ets/model/data/Book.ts');
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
const appIconManager = read('entry/src/main/ets/utils/AppIconManager.ets');
const fontBootstrap = read('entry/src/main/ets/utils/ReaderFontBootstrap.ets');
const entryAbility = read('entry/src/main/ets/entryability/EntryAbility.ets');
const pages = JSON.parse(read('entry/src/main/resources/base/profile/main_pages.json'));

const expectedThemes = ['classic-blue', 'warm-paper', 'forest-mist', 'ink-wash', 'neon-night'];
for (const themeId of expectedThemes) {
  assert(models.includes(`'${themeId}'`), `Theme id is missing from ThemeModels: ${themeId}`);
  assert(registry.includes(`ThemeIds.`), 'Builtin registry is not using stable ThemeIds');
}
assert((registry.match(/themes\.push\(/g) || []).length >= expectedThemes.length,
  'Builtin registry must publish at least five themes');
assert(registry.includes('static register(theme: ThemePack)'), 'Compiled theme registration API is missing');

const expectedBackgrounds = [
  'paper-light', 'paper-dark', 'forest-light', 'forest-dark',
  'ink-light', 'ink-dark', 'neon-light', 'neon-dark'
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

const themedIconFiles = fs.readdirSync(mediaRoot).filter(fileName => /^ic_theme_.*\.svg$/.test(fileName));
assert(themedIconFiles.length >= 8, 'Rounded and ink icon packs must each contain four icons');
for (const fileName of themedIconFiles) {
  const source = fs.readFileSync(path.join(mediaRoot, fileName), 'utf8');
  assert(/viewBox="0 0 24 24"/.test(source), `Invalid themed icon viewBox: ${fileName}`);
  assert(!/(<script|<image|<use|href=|url\(|<filter)/i.test(source), `Unsafe SVG feature in ${fileName}`);
}

const themeLogoFiles = fs.readdirSync(mediaRoot).filter(fileName => /^theme_logo_.*\.svg$/.test(fileName));
assert(themeLogoFiles.length >= expectedThemes.length, 'Every builtin theme must provide a dedicated logo');
for (const fileName of themeLogoFiles) {
  const source = fs.readFileSync(path.join(mediaRoot, fileName), 'utf8');
  assert(/viewBox="0 0 64 64"/.test(source), `Invalid theme logo viewBox: ${fileName}`);
  assert(!/(<script|<image|<use|href=|url\(|<filter)/i.test(source), `Unsafe SVG feature in ${fileName}`);
}
assert(assets.includes('static themeLogo(themeId: string)'), 'Theme logo resolver is missing');

const bubbleStyles = ['qq-soft', 'qq-solid', 'capsule', 'paper', 'neon'];
for (const styleId of bubbleStyles) {
  assert(models.includes(`'${styleId}'`), `Bubble style is missing from ThemeModels: ${styleId}`);
  assert(regexModel.includes(`'${styleId}'`), `Bubble resolver/codec is missing style: ${styleId}`);
  assert(regexSettings.includes(`'${styleId}'`), `Reader font settings cannot select style: ${styleId}`);
}
assert(regexModel.includes('schemaVersion: number = 3'), 'Regex rule schema must be version 3');
assert(regexSettings.includes('ReaderRegexFontCodec.decode'), 'Settings page must use the shared regex codec');
assert(reader.includes('ReaderRegexFontCodec.decode'), 'Reader page must use the shared regex codec');
assert(reader.includes('if (slice.ttsHighlighted)'), 'TTS highlight precedence is missing');
assert(reader.includes('start >= displayText.length || regex.lastIndex >= displayText.length'),
  'Reader zero-length regex guard is missing');
assert(regexSettings.includes('start >= text.length || regex.lastIndex >= text.length'),
  'Preview zero-length regex guard is missing');

assert(readerThemes.includes('APP_THEME_INDEX: number = 4'), 'Reader app-theme compatibility index is missing');
assert(runtime.includes("KEY_THEME_REVISION"), 'Theme runtime revision broadcast is missing');
assert(reader.includes('ThemeAssetRegistry.readerBackground'), 'Reader background asset resolver is not connected');
assert(reader.includes('Image(this.getBackgroundImage())') && reader.includes('.objectFit(this.getBackgroundImageFit())'),
  'Reader root surface does not draw the theme background image');
assert(indexPage.includes('ThemeRuntime.iconPackId()'), 'Floating tab bar does not resolve the active icon pack');
for (const tabId of ['bookshelf', 'explore', 'search', 'mine']) {
  assert(indexPage.includes(`this.navigationIcon('${tabId}')`), `Floating tab icon is not themed: ${tabId}`);
}
const settingsPageSource = indexPage.slice(indexPage.indexOf('struct SettingsPage'));
assert(settingsPageSource.includes('.backgroundColor(this.pageColor())'),
  'Mine page background is not connected to the active theme');
assert(!settingsPageSource.includes(".backgroundColor(this.appDarkMode ? '#101113' : '#F5F5F5')"),
  'Mine page still contains the legacy fixed background color');
assert(settingsPageSource.includes('ThemeRuntime.primaryTextColor') &&
  settingsPageSource.includes('ThemeRuntime.subTextColor'),
  'Mine page semantic text colors are not connected to ThemeRuntime');
assert(settingsPageSource.includes('menuItem(title: string, desc: string, onClick: () => void)') &&
  !settingsPageSource.includes('.border({ width: 1') &&
  !settingsPageSource.includes('List({ space: 1 })'),
  'Mine page menu items have regressed to the old divided-list style');
assert(fontBootstrap.includes('ThemeRuntime.fontFamily()'), 'Cold-start font bootstrap ignores the theme font');
assert(entryAbility.includes('this.themeBootstrapPromise.then'), 'Theme bootstrap must finish before font bootstrap');
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
assert(themePage.includes('theme.light.reader.backgroundColor = this.customLightReaderBackgroundColor'),
  'Custom theme preview does not use the migrated reader background');
assert(!themeColorPage.includes("'pages/AppIconSettings'") &&
  !themeColorPage.includes("'pages/FontSettings'") &&
  !themeStore.includes('updateCustomFont') && !themeStore.includes('updateCustomDesktopIcon'),
  'Theme and appearance must remain independent from fonts and desktop icons');
assert(themePage.includes("this.sectionTitle('自定义主题')") &&
  themePage.includes("router.pushUrl({ url: 'pages/ThemeColorSettings' })"),
  'Theme page does not expose the custom theme before builtin themes');
assert(themeColorPage.includes('settings.themeId = ThemeIds.CUSTOM') &&
  themeColorPage.includes('settings.customLightAccentColor = this.lightAccentColor'),
  'Color edits do not automatically activate and update the custom theme');
assert(!otherSettingsPage.includes("router.pushUrl({ url: 'pages/ThemeColorSettings' })"),
  'Other settings still exposes the removed legacy theme-color entry');
assert(themePage.includes('ReaderThemeHelper.APP_THEME_INDEX'), 'Theme selection does not enable the app reader theme');
assert(themePage.includes('settings.fontFilePath'), 'Custom font override is not protected during theme selection');
assert(themePage.includes('ThemeAssetRegistry.themeLogo(this.activeTheme().id)') &&
  !themePage.includes("Text('Aa')") &&
  !themePage.includes('颜色、阅读背景、正则气泡与悬浮底栏已统一'),
  'Current theme summary must use the theme logo without the legacy description');
assert(runtime.includes('static accentSurfaceColor(darkMode: boolean)'),
  'Theme runtime does not expose a themed selected-surface color');
assert(ttsSettingsPage.includes('ThemeRuntime.accentSurfaceColor(this.appDarkMode)') &&
  ttsSettingsPage.includes(': this.inputColor()'),
  'TTS voice or speed controls are not connected to theme surfaces');
assert(!readerSettingsPage.includes("this.appDarkMode ? '#24272D' : '#F0F2F5'"),
  'Reader settings still contains legacy fixed control backgrounds');
for (const marginName of ['Left', 'Right', 'Top', 'Bottom']) {
  assert(readerStore.includes(`KEY_MARGIN_${marginName.toUpperCase()}`) &&
    reader.includes(`readerMargin${marginName}`),
    `Reader ${marginName.toLowerCase()} margin is not persisted or applied`);
}
assert(readerSettingsPage.includes('this.typographyStepper()') &&
  readerSettingsPage.includes("{ value: '左边距' }") &&
  readerSettingsPage.includes("{ value: '右边距' }") &&
  readerSettingsPage.includes("{ value: '上边距' }") &&
  readerSettingsPage.includes("{ value: '下边距' }") &&
  readerSettingsPage.includes('adjustCurrentTypographySetting'),
  'Reader typography dropdown/stepper does not expose all four margins');
assert(reader.includes('this.readerMarginLeft + this.readerMarginRight') &&
  reader.includes('this.readerMarginTop + this.getReaderContentBottomPadding()') &&
  reader.includes('this.readerMarginBottom + this.getReaderContentBottomReserve()'),
  'Reader pagination does not account for configured margins');
assert(reader.includes('.textAlign(TextAlign.JUSTIFY)') &&
  reader.includes('align: graphicsText.TextAlign.JUSTIFY'),
  'Reader body rendering and pagination measurement must both use justified alignment');
assert(reader.includes('const safeBest = Math.max(start + 1, Math.min(best, source.length))') &&
  !reader.includes('Math.floor((best - start) * 0.96)'),
  'Reader pagination must not roll back a full line merely to prefer sentence boundaries');
assert(reader.includes('buildReaderMeasureTextStyle(this.readerFontSize, this.getBodyReaderFontFamily())') &&
  reader.includes('fontFamily: this.getBodyReaderFontFamily()'),
  'Reader pagination measurement must use the same body font as rendering');
assert(reader.includes('this.readerQuickTypographyStepper()') &&
  reader.includes('quickTypographySettingOptions') &&
  reader.includes('adjustQuickTypographySetting') &&
  reader.includes('applyReaderMargin'),
  'In-reader settings do not provide the shared typography dropdown/stepper');
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
  readerSettingsPage.includes('tapZoneSettingsDialog()'),
  'Reading settings must expose the shared tap-zone action editor for click page turning');
assert(bookSourcePage.includes('checkOptionsDialog()') &&
  bookSourcePage.includes("this.checkActionOption('自动禁用'") &&
  bookSourcePage.includes("this.checkActionOption('自动删除'") &&
  bookSourcePage.includes('handleCheckedSourceCompletion') &&
  searchCoordinator.includes('await options.onSourceComplete'),
  'Book source validation must support immediate disable/delete actions per completed source');
assert(indexPage.includes("TextInput({ placeholder: '输入书源关键词'") &&
  indexPage.includes("Button('搜索')") &&
  indexPage.includes('this.exploreSourceDropdown()') &&
  !indexPage.includes('builder: this.exploreSourcePopup') &&
  indexPage.includes('applyExploreSourceFilter') &&
  indexPage.includes('getFilteredExploreSourceOptions()'),
  'Explore source dropdown must support keyword filtering from an explicit search button');
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
  const filePath = path.join(mediaRoot, fileName);
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
  'theme/ThemeAssetRegistry.ets', 'pages/ThemeSettings.ets'
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
  `${backgroundFiles.length} backgrounds, ${themedIconFiles.length} themed icons, ` +
  `${bubbleStyles.length} bubble styles.`);
