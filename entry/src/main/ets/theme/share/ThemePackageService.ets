import { common, Context } from '@kit.AbilityKit';
import { UIContext } from '@kit.ArkUI';
import { bundleManager } from '@kit.AbilityKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import fs from '@ohos.file.fs';
import fileUri from '@ohos.file.fileuri';
import hash from '@ohos.file.hash';
import picker from '@ohos.file.picker';
import zlib from '@ohos.zlib';
import { AccountSessionStore } from '../../account/AccountSessionStore';
import { CustomThemeQuota } from '../../account/CustomThemeQuota';
import { ReaderRegexFontCodec, ReaderRegexFontRule, ReaderRegexLegacySettings } from '../../model/reader/ReaderRegexFontRule';
import { ThemeAccessPolicy } from '../../account/ThemeAccessPolicy';
import { AppThemeSettings, AppThemeSettingsStore } from '../../utils/AppThemeSettingsStore';
import { CustomThemeScheme, CustomThemeSchemeStore } from '../../utils/CustomThemeSchemeStore';
import { ReaderFontBootstrap } from '../../utils/ReaderFontBootstrap';
import { ReaderFontHelper } from '../../utils/ReaderFontHelper';
import { ReaderSettings, ReaderSettingsStore } from '../../utils/ReaderSettingsStore';
import { ReaderThemeHelper } from '../../utils/ReaderThemeHelper';
import { BuiltinThemeRegistry } from '../BuiltinThemeRegistry';
import { ThemeIds, ThemePack } from '../ThemeModels';
import {
  applyLayout,
  assetIdFromRef,
  assetPath,
  assetRef,
  decodeManifest,
  decodeTheme,
  encodeManifest,
  encodeTheme,
  findAsset,
  IMAGE_SETTING_KEYS,
  isLocalFileReference,
  kindForExtension,
  mergeRules,
  packageFileName,
  pickLayout,
  QYTHEME_EXTENSION,
  remapFonts,
  restrictSources,
  sanitizeAuthor,
  sanitizeThemeName,
  sniffAssetExtension,
  SourceRestriction,
  ThemePackageAsset,
  ThemePackageAssetKinds,
  ThemePackageEmphasis,
  ThemePackageFeatures,
  ThemePackageFont,
  ThemePackageLimits,
  ThemePackageManifest,
  ThemePackageTheme
} from './ThemePackageFormat';
import { ZipEntryInfo, ZipEntryInspector, ZipInspectLimits } from './ZipEntryInspector';

class CustomFontRecord {
  familyName: string = '';
  filePath: string = '';
  sourceName: string = '';
}

class CustomFontList {
  fonts: CustomFontRecord[] = [];
}

export class ThemeExportFontInfo {
  family: string = '';
  name: string = '';
  // 用在哪里，例如“正文、标题”“强调规则”。
  usage: string = '';
  // 只被强调规则用到：不附带规则时不打包。
  ruleOnly: boolean = false;
  filePath: string = '';
  size: number = 0;
  available: boolean = false;
}

/** 导出面板展示用：方案里有什么、要打包多少、缺了什么。 */
export class ThemeExportPlan {
  schemeId: string = '';
  name: string = '';
  author: string = '';
  imageCount: number = 0;
  imageBytes: number = 0;
  missingImages: string[] = [];
  ruleCount: number = 0;
  fonts: ThemeExportFontInfo[] = [];
}

export class ThemeExportOptions {
  includeAuthor: boolean = false;
  authorName: string = '';
  includeRules: boolean = false;
  includeFonts: boolean = false;
}

export class ThemeExportResult {
  zipPath: string = '';
  fileName: string = '';
  size: number = 0;
  workDir: string = '';
}

/** 导入前的检查结果，用户确认后才写入。 */
export class ThemeImportPreview {
  workDir: string = '';
  baseDir: string = '';
  manifest: ThemePackageManifest = new ThemePackageManifest();
  theme: ThemePackageTheme = new ThemePackageTheme();
  settingsJson: string = '';
  replaced: string[] = [];
  unknown: string[] = [];
  missingFonts: string[] = [];
  lockedBubbles: string[] = [];
  ruleCount: number = 0;
  bundledFontCount: number = 0;
  imageCount: number = 0;
  hasLayout: boolean = false;
}

export class ThemeImportResult {
  scheme: CustomThemeScheme = new CustomThemeScheme();
  addedRules: number = 0;
  skippedRules: number = 0;
  missingFonts: string[] = [];
}

const IMAGE_KEY_LABELS: Map<string, string> = new Map<string, string>([
  ['customLightStartupImagePath', '浅色启动封面图片'],
  ['customDarkStartupImagePath', '深色启动封面图片'],
  ['customLightReaderBackgroundAssetId', '浅色阅读背景图片'],
  ['customDarkReaderBackgroundAssetId', '深色阅读背景图片']
]);

/**
 * 自定义主题分享（Beta，会员专享）：把一套自定义方案打成 .qytheme 主题包，或从主题包导入为新方案。
 * 格式与校验规则见 ThemePackageFormat。
 */
export class ThemePackageService {
  static readonly IMPORTED_FILE_PREFIX: string = 'qytheme_';

  /** 导出和导入都需要有效会员。 */
  static isAvailable(): boolean {
    return AccountSessionStore.activeMembershipSku() !== '';
  }

  static async planExport(context: Context, scheme: CustomThemeScheme): Promise<ThemeExportPlan> {
    const plan = new ThemeExportPlan();
    plan.schemeId = scheme.id;
    plan.name = scheme.name;
    plan.author = scheme.author;
    const settingsRecord = ThemePackageService.settingsRecord(scheme.settings);
    const seen = new Set<string>();
    for (const key of IMAGE_SETTING_KEYS) {
      const value = settingsRecord[key];
      if (typeof value !== 'string' || !isLocalFileReference(value)) continue;
      const path = ThemePackageService.pathFromUri(value);
      if (!ThemePackageService.exists(path)) {
        plan.missingImages.push(IMAGE_KEY_LABELS.get(key) || key);
        continue;
      }
      if (seen.has(path)) continue;
      seen.add(path);
      plan.imageCount++;
      plan.imageBytes += fs.statSync(path).size;
    }
    const profile = await ThemePackageService.schemeProfile(context, scheme);
    plan.ruleCount = ThemePackageService.profileRules(profile).length;
    plan.fonts = ThemePackageService.effectiveFonts(profile, true);
    return plan;
  }

  /** 在临时目录生成主题包（ZIP），之后由用户选择保存到文件或分享。 */
  static async buildPackage(context: Context, scheme: CustomThemeScheme,
    options: ThemeExportOptions): Promise<ThemeExportResult> {
    const workDir = `${context.tempDir}/qytheme_export_${Date.now()}`;
    const pkgDir = `${workDir}/theme`;
    const assetsDir = `${pkgDir}/assets`;
    fs.mkdirSync(assetsDir, true);
    try {
      const manifest = new ThemePackageManifest();
      manifest.packageId = ThemePackageService.randomHex(16);
      manifest.name = sanitizeThemeName(scheme.name) || '自定义主题';
      manifest.author = options.includeAuthor ? sanitizeAuthor(options.authorName) : '';
      if (options.includeAuthor && !manifest.author) {
        throw new Error('请填写作者名称');
      }
      manifest.exportedAt = Date.now();
      manifest.appVersion = ThemePackageService.appVersion();
      manifest.requires = [ThemePackageFeatures.CUSTOM_SCHEME, ThemePackageFeatures.READER_LAYOUT];

      const settingsRecord = ThemePackageService.settingsRecord(scheme.settings);
      // 是否使用主题封面、应用时是否带排版是本机偏好，不随主题走。
      settingsRecord['themeBookCoverEnabled'] = false;
      settingsRecord['themeApplyLayoutEnabled'] = false;
      const copied = new Map<string, string>();
      for (const key of IMAGE_SETTING_KEYS) {
        const value = settingsRecord[key];
        if (typeof value !== 'string' || !isLocalFileReference(value)) continue;
        const path = ThemePackageService.pathFromUri(value);
        if (!ThemePackageService.exists(path)) {
          throw new Error(`${IMAGE_KEY_LABELS.get(key) || '图片'}已丢失，请在编辑主题里重新上传后再导出`);
        }
        let id = copied.get(path) || '';
        if (!id) {
          const asset = await ThemePackageService.packAsset(path, assetsDir, ThemePackageAssetKinds.IMAGE, '');
          manifest.assets.push(asset);
          id = asset.id;
          copied.set(path, id);
        }
        settingsRecord[key] = assetRef(id);
      }

      const profile = await ThemePackageService.schemeProfile(context, scheme);
      const profileRecord = ThemePackageService.readerRecord(profile);
      // 全局字体是整机设置，导入方不会被改动；方案正文/标题跟随全局字体且全局用的是自定义字体时，
      // 换成直接绑定这款字体，导入后效果一致。
      if (profile.fontMode === ReaderSettingsStore.FONT_MODE_CUSTOM && profile.fontFamily) {
        for (const pair of [['bodyFontMode', 'bodyFontFamily'], ['titleFontMode', 'titleFontFamily']]) {
          if (profileRecord[pair[0]] === 'global') {
            profileRecord[pair[0]] = 'custom';
            profileRecord[pair[1]] = profile.fontFamily;
          }
        }
      }
      const theme = new ThemePackageTheme();
      theme.settingsJson = JSON.stringify(settingsRecord);
      theme.layoutJson = JSON.stringify(pickLayout(profileRecord));

      const rules = options.includeRules ? ThemePackageService.profileRules(profile) : [];
      if (rules.length > 0) {
        manifest.requires.push(ThemePackageFeatures.EMPHASIS_RULES);
        theme.emphasis = new ThemePackageEmphasis();
        theme.emphasis.enabled = profile.regexFontEnabled;
        theme.emphasis.rulesJson = JSON.stringify(ReaderRegexFontCodec.cleanRules(rules));
      }

      // 只打包这套方案实际生效的字体：正文、标题，以及开着强调规则时规则用的字体。
      // 规则开关关着时，规则字体只记名字，导入方看得到用的是哪款。
      const effective = ThemePackageService.effectiveFonts(profile, options.includeRules);
      for (const family of ThemePackageService.boundFamilies(profileRecord, rules)) {
        const info = effective.find((item: ThemeExportFontInfo): boolean => item.family === family);
        const font = new ThemePackageFont();
        font.family = family;
        font.name = info ? info.name : ThemePackageService.fontDisplayName(profile, family);
        // 文件已丢失的字体只记名字，导入方会退回全局字体；导出面板已提示。
        if (options.includeFonts && info && info.available) {
          const existing = manifest.assets.find((item: ThemePackageAsset): boolean =>
            item.kind === ThemePackageAssetKinds.FONT && item.name === info.name && item.size === info.size);
          if (existing) {
            font.assetId = existing.id;
          } else {
            const asset = await ThemePackageService.packAsset(info.filePath, assetsDir,
              ThemePackageAssetKinds.FONT, info.name);
            manifest.assets.push(asset);
            font.assetId = asset.id;
          }
        }
        theme.fonts.push(font);
      }
      if (manifest.assets.some((item: ThemePackageAsset): boolean => item.kind === ThemePackageAssetKinds.FONT)) {
        manifest.requires.push(ThemePackageFeatures.FONTS);
      }
      if (manifest.assets.length > ThemePackageLimits.MAX_ASSETS) {
        throw new Error('主题素材过多，无法导出');
      }

      ThemePackageService.writeText(`${pkgDir}/manifest.json`, encodeManifest(manifest));
      ThemePackageService.writeText(`${pkgDir}/theme.json`, encodeTheme(theme));
      // 系统压缩接口要求输出路径是 .zip；保存时再用 .qytheme 作为文件名。
      const zipPath = `${workDir}/theme.zip`;
      await zlib.compressFile(pkgDir, zipPath, { level: zlib.CompressLevel.COMPRESS_LEVEL_DEFAULT_COMPRESSION });
      const result = new ThemeExportResult();
      result.zipPath = zipPath;
      result.fileName = packageFileName(manifest.name);
      result.size = fs.statSync(zipPath).size;
      result.workDir = workDir;
      if (result.size > ThemePackageLimits.MAX_PACKAGE_BYTES) {
        throw new Error('主题包超过 80 MB，请减少附带的字体后再导出');
      }
      return result;
    } catch (e) {
      ThemePackageService.removeDir(workDir);
      throw e as Error;
    }
  }

  /** 用系统保存面板写到用户选的位置；取消时返回 false。 */
  static async saveToFile(context: Context, result: ThemeExportResult): Promise<boolean> {
    const options = new picker.DocumentSaveOptions();
    options.newFileNames = [result.fileName];
    const uris = await new picker.DocumentViewPicker(context).save(options);
    if (!uris || uris.length === 0) {
      return false;
    }
    await fs.copy(fileUri.getUriFromPath(result.zipPath), uris[0]);
    return true;
  }

  static async share(context: common.UIAbilityContext, result: ThemeExportResult): Promise<void> {
    // 分享出去的文件名就是接收方看到的名字，复制一份带 .qytheme 后缀的。
    const sharePath = `${result.workDir}/${result.fileName}`;
    if (!ThemePackageService.exists(sharePath)) {
      fs.copyFileSync(result.zipPath, sharePath);
    }
    let utd = 'general.zip';
    try {
      utd = uniformTypeDescriptor.getUniformDataTypeByFilenameExtension(QYTHEME_EXTENSION, 'general.zip');
    } catch (_) {
    }
    const data = new systemShare.SharedData({
      utd: utd,
      uri: fileUri.getUriFromPath(sharePath),
      title: result.fileName
    });
    const controller = new systemShare.ShareController(data);
    await controller.show(context, {
      previewMode: systemShare.SharePreviewMode.DEFAULT,
      selectionMode: systemShare.SelectionMode.SINGLE
    });
  }

  static discardExport(result: ThemeExportResult | null): void {
    if (result) ThemePackageService.removeDir(result.workDir);
  }

  /** 选择主题包文件；取消时返回空串。 */
  static async pickPackage(context: Context): Promise<string> {
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    options.fileSuffixFilters = [`主题包|${QYTHEME_EXTENSION}`];
    const result = await new picker.DocumentViewPicker(context).select(options);
    return result && result.length > 0 ? result[0] : '';
  }

  /** 复制到临时目录、检查压缩包结构、解压、核对清单与每个素材的摘要，算出导入后会有哪些替换。 */
  static async prepareImport(context: Context, uri: string): Promise<ThemeImportPreview> {
    const workDir = `${context.tempDir}/qytheme_import_${Date.now()}`;
    fs.mkdirSync(workDir, true);
    try {
      const zipPath = `${workDir}/source.zip`;
      const copySource = uri.startsWith('/') ? fileUri.getUriFromPath(uri) : uri;
      await fs.copy(copySource, fileUri.getUriFromPath(zipPath));
      const size = fs.statSync(zipPath).size;
      if (size > ThemePackageLimits.MAX_PACKAGE_BYTES) {
        throw new Error('主题包超过 80 MB，无法导入');
      }
      const entries = ThemePackageService.inspectZip(zipPath, size);
      const root = ZipEntryInspector.commonRoot(entries);
      const outDir = `${workDir}/out`;
      fs.mkdirSync(outDir, true);
      await zlib.decompressFile(zipPath, outDir);
      fs.unlinkSync(zipPath);
      const baseDir = root ? `${outDir}/${root.substring(0, root.length - 1)}` : outDir;
      const manifest = decodeManifest(ThemePackageService.readSmallText(`${baseDir}/manifest.json`));
      ThemePackageService.checkEntries(entries, root, manifest);
      const theme = decodeTheme(ThemePackageService.readSmallText(`${baseDir}/theme.json`), manifest);
      for (const asset of manifest.assets) {
        await ThemePackageService.verifyAsset(baseDir, asset);
      }

      const preview = new ThemeImportPreview();
      preview.workDir = workDir;
      preview.baseDir = baseDir;
      preview.manifest = manifest;
      preview.theme = theme;
      preview.hasLayout = !!theme.layoutJson;
      const settings = JSON.parse(theme.settingsJson) as Record<string, Object>;
      const restriction: SourceRestriction = restrictSources(settings,
        (themeId: string): boolean => ThemePackageService.canUseTheme(themeId),
        (themeId: string): boolean => BuiltinThemeRegistry.has(themeId) && themeId !== ThemeIds.CUSTOM,
        (themeId: string): string => BuiltinThemeRegistry.findById(themeId).name,
        BuiltinThemeRegistry.DEFAULT_THEME_ID);
      preview.replaced = restriction.replaced;
      preview.unknown = restriction.unknown;
      ThemePackageService.restrictBackgroundAssets(settings, preview.replaced);
      preview.settingsJson = JSON.stringify(settings);
      for (const key of IMAGE_SETTING_KEYS) {
        const value = settings[key];
        if (typeof value === 'string' && assetIdFromRef(value)) preview.imageCount++;
      }
      if (theme.emphasis) {
        const rules = ReaderRegexFontCodec.decode(theme.emphasis.rulesJson);
        preview.ruleCount = rules.length;
        for (const rule of rules) {
          if (!ThemeAccessPolicy.canUseBubbleStyle(rule.bubbleStyleId)) {
            const label = `${rule.name}（${ThemeAccessPolicy.requiredThemeNameForBubbleStyle(rule.bubbleStyleId)}）`;
            if (!preview.lockedBubbles.includes(label)) preview.lockedBubbles.push(label);
          }
        }
      }
      for (const font of theme.fonts) {
        if (font.assetId) {
          preview.bundledFontCount++;
        } else {
          const name = font.name || font.family;
          if (!preview.missingFonts.includes(name)) preview.missingFonts.push(name);
        }
      }
      return preview;
    } catch (e) {
      ThemePackageService.removeDir(workDir);
      throw e as Error;
    }
  }

  static discardImport(preview: ThemeImportPreview | null): void {
    if (preview) ThemePackageService.removeDir(preview.workDir);
  }

  /**
   * 写入导入结果：安装图片和字体、新建（或替换）方案，并给这套方案建一份阅读设置——
   * 以当前（或被替换方案）的设置为底，换上包内排版，包内强调规则追加在原有规则之后。
   */
  static async commitImport(context: Context, uiContext: UIContext | null, preview: ThemeImportPreview,
    replaceSchemeId: string): Promise<ThemeImportResult> {
    try {
      const appSettings = await AppThemeSettingsStore.load(context);
      const schemes = await CustomThemeSchemeStore.load(context, appSettings);
      if (replaceSchemeId) {
        if (appSettings.themeId === ThemeIds.CUSTOM &&
          (AppStorage.get<string>(CustomThemeSchemeStore.STORAGE_ACTIVE_SCHEME_ID) || '') === replaceSchemeId) {
          throw new Error('正在使用的方案不能被替换，请先换用其他主题');
        }
      } else if (schemes.length >= CustomThemeQuota.current()) {
        throw new Error(`已达到 ${CustomThemeQuota.current()} 套方案上限，请选择替换一套已有方案`);
      }
      const manifest = preview.manifest;
      const settings = JSON.parse(preview.settingsJson) as Record<string, Object>;
      for (const key of IMAGE_SETTING_KEYS) {
        const value = settings[key];
        const id = typeof value === 'string' ? assetIdFromRef(value) : '';
        if (!id) continue;
        const asset = findAsset(manifest, id);
        if (!asset) {
          settings[key] = '';
          continue;
        }
        const dir = key.endsWith('ImagePath') ? 'theme_startups' : 'reader_backgrounds';
        settings[key] = fileUri.getUriFromPath(ThemePackageService.installAsset(context, preview.baseDir, asset, dir));
      }

      const baseProfile = replaceSchemeId ?
        await ReaderSettingsStore.loadProfile(context, ReaderSettingsStore.profileIdFor(ThemeIds.CUSTOM, replaceSchemeId)) :
        await ReaderSettingsStore.load(context);
      const installed = await ThemePackageService.installFonts(context, uiContext, preview, baseProfile);
      const displayNames = new Map<string, string>();
      for (const font of preview.theme.fonts) {
        displayNames.set(font.family, font.name || font.family);
      }
      const profileRecord = ThemePackageService.readerRecord(baseProfile);
      const layout = preview.theme.layoutJson ? JSON.parse(preview.theme.layoutJson) as Record<string, Object> : null;
      const incomingRules: Record<string, Object>[] = preview.theme.emphasis ?
        JSON.parse(JSON.stringify(ReaderRegexFontCodec.cleanRules(
          ReaderRegexFontCodec.decode(preview.theme.emphasis.rulesJson)))) as Record<string, Object>[] : [];
      const result = new ThemeImportResult();
      result.missingFonts = remapFonts(layout, incomingRules, installed, displayNames);
      if (layout) {
        applyLayout(profileRecord, layout);
      }
      profileRecord['themeIndex'] = ReaderThemeHelper.APP_THEME_INDEX;
      profileRecord['lightThemeIndex'] = ReaderThemeHelper.APP_THEME_INDEX;
      profileRecord['darkThemeIndex'] = ReaderThemeHelper.APP_THEME_INDEX;
      if (incomingRules.length > 0 && preview.theme.emphasis) {
        const existing = ReaderRegexFontCodec.encode(ThemePackageService.profileRules(baseProfile));
        const merged = mergeRules(existing, JSON.stringify(incomingRules), Date.now());
        profileRecord['regexFontRulesRaw'] = ReaderRegexFontCodec.encode(
          ReaderRegexFontCodec.decode(merged.rulesJson));
        if (merged.added > 0 && preview.theme.emphasis.enabled) {
          profileRecord['regexFontEnabled'] = true;
        }
        result.addedRules = merged.added;
        result.skippedRules = merged.skipped;
      }

      const schemeSettings = AppThemeSettingsStore.cloneSettings(
        JSON.parse(JSON.stringify(settings)) as AppThemeSettings);
      schemeSettings.themeId = ThemeIds.CUSTOM;
      schemeSettings.themeBookCoverEnabled = false;
      schemeSettings.themeApplyLayoutEnabled = false;
      const scheme = await CustomThemeSchemeStore.addImported(context, appSettings, manifest.name, schemeSettings,
        manifest.author, replaceSchemeId);
      if (!scheme) {
        throw new Error(replaceSchemeId ? '要替换的方案已不存在' :
          `已达到 ${CustomThemeQuota.current()} 套方案上限`);
      }
      await ReaderSettingsStore.writeProfile(context, ReaderSettingsStore.profileIdFor(ThemeIds.CUSTOM, scheme.id),
        JSON.parse(JSON.stringify(profileRecord)) as ReaderSettings);
      result.scheme = scheme;
      if (replaceSchemeId) {
        await ThemePackageService.cleanupImportedFiles(context);
      }
      return result;
    } finally {
      ThemePackageService.discardImport(preview);
    }
  }

  /** 删除或替换方案后，清掉没有任何方案再引用的导入图片（只清本功能写入的 qytheme_ 文件）。 */
  static async cleanupImportedFiles(context: Context): Promise<void> {
    try {
      const appSettings = await AppThemeSettingsStore.load(context);
      const schemes = await CustomThemeSchemeStore.load(context, appSettings);
      const referenced = new Set<string>();
      const collect = (settings: AppThemeSettings): void => {
        const record = ThemePackageService.settingsRecord(settings);
        for (const key of IMAGE_SETTING_KEYS) {
          const value = record[key];
          if (typeof value === 'string' && isLocalFileReference(value)) {
            referenced.add(ThemePackageService.pathFromUri(value));
          }
        }
      };
      collect(appSettings);
      for (const scheme of schemes) {
        collect(scheme.settings);
      }
      for (const dir of ['theme_startups', 'reader_backgrounds']) {
        const fullDir = `${context.filesDir}/${dir}`;
        let names: string[] = [];
        try {
          names = fs.listFileSync(fullDir);
        } catch (_) {
          continue;
        }
        for (const name of names) {
          const path = `${fullDir}/${name}`;
          if (name.startsWith(ThemePackageService.IMPORTED_FILE_PREFIX) && !referenced.has(path)) {
            fs.unlinkSync(path);
          }
        }
      }
    } catch (e) {
      console.warn('清理导入主题图片失败:', (e as Error).message);
    }
  }

  /** 导入方能否使用某个内置主题的部件：免费、已获得或会员主题库内；试用中的主题不算。 */
  static canUseTheme(themeId: string): boolean {
    if (themeId === ThemeIds.OBSIDIAN_ARCHIVE) return AccountSessionStore.hasOwnedEntitlement(themeId);
    return BuiltinThemeRegistry.isFree(themeId) || AccountSessionStore.hasValidEntitlement(themeId);
  }

  // ---- 导出辅助 ----

  private static async schemeProfile(context: Context, scheme: CustomThemeScheme): Promise<ReaderSettings> {
    return await ReaderSettingsStore.loadProfile(context, ReaderSettingsStore.profileIdFor(ThemeIds.CUSTOM, scheme.id));
  }

  private static profileRules(profile: ReaderSettings): ReaderRegexFontRule[] {
    const legacy = new ReaderRegexLegacySettings();
    legacy.pattern = profile.regexFontPattern;
    legacy.fontMode = profile.regexFontMode;
    legacy.fontFamily = profile.regexFontFamily;
    legacy.fontSize = profile.regexFontSize;
    legacy.shadowColor = profile.regexShadowColor;
    return ReaderRegexFontCodec.decode(profile.regexFontRulesRaw, legacy);
  }

  /** 排版和规则实际绑定的自定义字体名（去重）。 */
  private static boundFamilies(profileRecord: Record<string, Object>, rules: ReaderRegexFontRule[]): string[] {
    const families: string[] = [];
    const add = (mode: Object, family: Object): void => {
      if (mode === 'custom' && typeof family === 'string' && family && !families.includes(family)) {
        families.push(family);
      }
    };
    add(profileRecord['bodyFontMode'], profileRecord['bodyFontFamily']);
    add(profileRecord['titleFontMode'], profileRecord['titleFontFamily']);
    for (const rule of rules) {
      add(rule.fontMode, rule.fontFamily);
    }
    return families;
  }

  /**
   * 这套方案实际生效的自定义字体：正文、标题（跟随全局字体且全局用的是自定义字体时算全局这款），
   * withRules 时再加上强调规则用的字体（规则总开关关着时不算）。字体库里其他字体不在其列。
   */
  private static effectiveFonts(profile: ReaderSettings, withRules: boolean): ThemeExportFontInfo[] {
    const library = ThemePackageService.fontLibrary(profile.customFontsRaw);
    const globalCustom = profile.fontMode === ReaderSettingsStore.FONT_MODE_CUSTOM ? profile.fontFamily : '';
    const result: ThemeExportFontInfo[] = [];
    const add = (mode: string, family: string, usage: string, ruleOnly: boolean): void => {
      const resolved = mode === 'custom' ? family : (mode === 'global' && !ruleOnly ? globalCustom : '');
      if (!resolved) return;
      const existing = result.find((item: ThemeExportFontInfo): boolean => item.family === resolved);
      if (existing) {
        if (!existing.usage.includes(usage)) existing.usage += `、${usage}`;
        existing.ruleOnly = existing.ruleOnly && ruleOnly;
        return;
      }
      const info = new ThemeExportFontInfo();
      info.family = resolved;
      info.usage = usage;
      info.ruleOnly = ruleOnly;
      const item = library.find((font: CustomFontRecord): boolean => font.familyName === resolved);
      if (item) {
        info.name = ReaderFontHelper.resolveDisplayName(item.sourceName, item.filePath);
        info.filePath = item.filePath;
        info.available = ThemePackageService.exists(item.filePath);
        info.size = info.available ? fs.statSync(item.filePath).size : 0;
      } else {
        info.name = resolved;
      }
      result.push(info);
    };
    add(profile.bodyFontMode, profile.bodyFontFamily, '正文', false);
    add(profile.titleFontMode, profile.titleFontFamily, '标题', false);
    if (withRules && profile.regexFontEnabled) {
      for (const rule of ThemePackageService.profileRules(profile)) {
        add(rule.fontMode, rule.fontFamily, '强调规则', true);
      }
    }
    return result;
  }

  private static fontDisplayName(profile: ReaderSettings, family: string): string {
    const item = ThemePackageService.fontLibrary(profile.customFontsRaw)
      .find((font: CustomFontRecord): boolean => font.familyName === family);
    return item ? ReaderFontHelper.resolveDisplayName(item.sourceName, item.filePath) : '';
  }

  private static async packAsset(path: string, assetsDir: string, kind: string,
    name: string): Promise<ThemePackageAsset> {
    const size = fs.statSync(path).size;
    const maxSize = kind === ThemePackageAssetKinds.FONT ?
      ThemePackageLimits.MAX_FONT_BYTES : ThemePackageLimits.MAX_IMAGE_BYTES;
    if (size <= 0 || size > maxSize) {
      throw new Error(kind === ThemePackageAssetKinds.FONT ? `字体「${name}」超过 40 MB，无法附带` :
        '图片超过 20 MB，无法导出');
    }
    const extension = sniffAssetExtension(ThemePackageService.readHead(path));
    if (!extension || kindForExtension(extension) !== kind) {
      throw new Error(kind === ThemePackageAssetKinds.FONT ? `字体「${name}」的格式不支持` : '有图片的格式不支持导出');
    }
    const sha256 = (await hash.hash(path, 'sha256')).toLowerCase();
    const asset = new ThemePackageAsset();
    asset.id = sha256.substring(0, 24);
    asset.kind = kind;
    asset.size = size;
    asset.sha256 = sha256;
    asset.name = name;
    asset.path = assetPath(asset.id, extension);
    fs.copyFileSync(path, `${assetsDir}/${asset.id}.${extension}`);
    return asset;
  }

  // ---- 导入辅助 ----

  private static inspectZip(zipPath: string, size: number): ZipEntryInfo[] {
    const file = fs.openSync(zipPath, fs.OpenMode.READ_ONLY);
    try {
      const limits = new ZipInspectLimits();
      limits.maxEntries = ThemePackageLimits.MAX_ZIP_ENTRIES;
      limits.maxTotalUncompressed = ThemePackageLimits.MAX_TOTAL_UNCOMPRESSED;
      limits.maxEntryUncompressed = ThemePackageLimits.MAX_FONT_BYTES;
      return ZipEntryInspector.inspect(size, (offset: number, length: number): Uint8Array => {
        const buffer = new ArrayBuffer(length);
        const read = fs.readSync(file.fd, buffer, { offset: offset, length: length });
        return new Uint8Array(buffer, 0, read);
      }, limits);
    } finally {
      fs.closeSync(file);
    }
  }

  /** 包里只能有 manifest.json、theme.json 和清单列出的素材，素材大小要与清单一致。 */
  private static checkEntries(entries: ZipEntryInfo[], root: string, manifest: ThemePackageManifest): void {
    const found = new Set<string>();
    for (const entry of entries) {
      const name = entry.name.substring(root.length);
      if (entry.directory) {
        if (name === '' || name === 'assets/') continue;
        throw new Error('主题包内含有无法识别的内容');
      }
      if (name === 'manifest.json' || name === 'theme.json') {
        if (entry.uncompressedSize > ThemePackageLimits.MAX_JSON_BYTES) {
          throw new Error('主题包的设置文件过大');
        }
        found.add(name);
        continue;
      }
      const asset = manifest.assets.find((item: ThemePackageAsset): boolean => item.path === name);
      if (!asset || asset.size !== entry.uncompressedSize) {
        throw new Error('主题包内含有无法识别的内容');
      }
      found.add(name);
    }
    if (!found.has('manifest.json') || !found.has('theme.json')) {
      throw new Error('主题包不完整');
    }
    for (const asset of manifest.assets) {
      if (!found.has(asset.path)) {
        throw new Error('主题包缺少素材文件');
      }
    }
  }

  private static async verifyAsset(baseDir: string, asset: ThemePackageAsset): Promise<void> {
    const path = `${baseDir}/${asset.path}`;
    if (!ThemePackageService.exists(path) || fs.statSync(path).size !== asset.size) {
      throw new Error('主题包缺少素材文件');
    }
    const dot = asset.path.lastIndexOf('.');
    if (sniffAssetExtension(ThemePackageService.readHead(path)) !== asset.path.substring(dot + 1)) {
      throw new Error('主题包内有素材格式与声明不符');
    }
    const digest = (await hash.hash(path, 'sha256')).toLowerCase();
    if (digest !== asset.sha256) {
      throw new Error('主题包已损坏（素材校验失败）');
    }
  }

  /** 包内阅读背景若是内置素材键，导入方得能使用拥有它的某个主题，否则换成替代主题的背景。 */
  private static restrictBackgroundAssets(settings: Record<string, Object>, replaced: string[]): void {
    const themes: ThemePack[] = BuiltinThemeRegistry.all();
    const fallback = BuiltinThemeRegistry.findById(BuiltinThemeRegistry.DEFAULT_THEME_ID);
    const modes: string[][] = [['customLightReaderBackgroundAssetId', 'light', '浅色'],
      ['customDarkReaderBackgroundAssetId', 'dark', '深色']];
    for (const mode of modes) {
      const value = settings[mode[0]];
      if (typeof value !== 'string' || !value || assetIdFromRef(value)) continue;
      const allowed = themes.some((theme: ThemePack): boolean => ThemePackageService.canUseTheme(theme.id) &&
        (theme.light.reader.backgroundAssetId === value || theme.dark.reader.backgroundAssetId === value));
      if (!allowed) {
        settings[mode[0]] = mode[1] === 'light' ? fallback.light.reader.backgroundAssetId :
          fallback.dark.reader.backgroundAssetId;
        replaced.push(`${mode[2]} · 阅读背景素材`);
      }
    }
  }

  /** 素材按内容命名：同一张图重复导入只存一份。 */
  private static installAsset(context: Context, baseDir: string, asset: ThemePackageAsset, dir: string): string {
    const fullDir = `${context.filesDir}/${dir}`;
    fs.mkdirSync(fullDir, true);
    const dot = asset.path.lastIndexOf('.');
    const target = `${fullDir}/${ThemePackageService.IMPORTED_FILE_PREFIX}${asset.id}${asset.path.substring(dot)}`;
    if (!ThemePackageService.exists(target) || fs.statSync(target).size !== asset.size) {
      fs.copyFileSync(`${baseDir}/${asset.path}`, target);
    }
    return target;
  }

  /**
   * 安装包内字体：字体库里已有内容相同的文件就复用，否则存进字体目录并加入字体库。
   * 返回“导出方字体名 → 本机字体名”。
   */
  private static async installFonts(context: Context, uiContext: UIContext | null, preview: ThemeImportPreview,
    current: ReaderSettings): Promise<Map<string, string>> {
    const installed = new Map<string, string>();
    const bundled = preview.theme.fonts.filter((font: ThemePackageFont): boolean => !!font.assetId);
    if (bundled.length === 0) return installed;
    const library = ThemePackageService.fontLibrary(current.customFontsRaw);
    let changed = false;
    for (const font of bundled) {
      const asset = findAsset(preview.manifest, font.assetId);
      if (!asset) continue;
      let family = '';
      for (const item of library) {
        if (!ThemePackageService.exists(item.filePath) || fs.statSync(item.filePath).size !== asset.size) continue;
        if ((await hash.hash(item.filePath, 'sha256')).toLowerCase() === asset.sha256) {
          family = item.familyName;
          break;
        }
      }
      if (!family) {
        const target = ThemePackageService.installAsset(context, preview.baseDir, asset, 'reader_fonts');
        family = ReaderFontHelper.stableFontFamily(target);
        if (!library.some((item: CustomFontRecord): boolean => item.filePath === target)) {
          const record = new CustomFontRecord();
          record.familyName = family;
          record.filePath = target;
          record.sourceName = font.name || asset.name || '主题字体';
          library.push(record);
          changed = true;
        }
      }
      installed.set(font.family, family);
    }
    if (changed) {
      const data = new CustomFontList();
      data.fonts = library;
      const latest = await ReaderSettingsStore.load(context);
      await ReaderSettingsStore.saveFontSettings(context, latest.fontFamily, latest.fontFilePath,
        latest.fontSourceName, latest.fontMode, latest.systemFontFamily, JSON.stringify(data));
      current.customFontsRaw = JSON.stringify(data);
      await ReaderFontBootstrap.registerFromSettings(context, uiContext, 'theme-import');
    }
    return installed;
  }

  // ---- 通用 ----

  private static fontLibrary(raw: string): CustomFontRecord[] {
    const text = (raw || '').trim();
    if (!text) return [];
    try {
      const parsed = JSON.parse(text) as CustomFontList | CustomFontRecord[];
      const list = Array.isArray(parsed) ? parsed as CustomFontRecord[] : ((parsed as CustomFontList).fonts || []);
      const result: CustomFontRecord[] = [];
      for (const item of list) {
        if (!item || !item.filePath) continue;
        const record = new CustomFontRecord();
        record.familyName = item.familyName || ReaderFontHelper.stableFontFamily(item.filePath);
        record.filePath = item.filePath;
        record.sourceName = item.sourceName || '';
        result.push(record);
      }
      return result;
    } catch (_) {
      return [];
    }
  }

  private static settingsRecord(settings: AppThemeSettings): Record<string, Object> {
    return JSON.parse(JSON.stringify(settings)) as Record<string, Object>;
  }

  private static readerRecord(settings: ReaderSettings): Record<string, Object> {
    return JSON.parse(JSON.stringify(settings)) as Record<string, Object>;
  }

  private static pathFromUri(value: string): string {
    if (value.startsWith('file://')) {
      try {
        return new fileUri.FileUri(value).path;
      } catch (_) {
        return decodeURIComponent(value.substring(7));
      }
    }
    return value;
  }

  private static exists(path: string): boolean {
    try {
      return !!path && fs.accessSync(path);
    } catch (_) {
      return false;
    }
  }

  private static readHead(path: string): Uint8Array {
    const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
    try {
      const buffer = new ArrayBuffer(16);
      const read = fs.readSync(file.fd, buffer, { offset: 0, length: 16 });
      return new Uint8Array(buffer, 0, read);
    } finally {
      fs.closeSync(file);
    }
  }

  private static readSmallText(path: string): string {
    if (!ThemePackageService.exists(path) || fs.statSync(path).size > ThemePackageLimits.MAX_JSON_BYTES) {
      throw new Error('主题包不完整');
    }
    return fs.readTextSync(path);
  }

  private static writeText(path: string, text: string): void {
    const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, text);
    } finally {
      fs.closeSync(file);
    }
  }

  private static removeDir(path: string): void {
    try {
      if (path && fs.accessSync(path)) fs.rmdirSync(path);
    } catch (e) {
      console.warn('清理主题包临时目录失败:', (e as Error).message);
    }
  }

  private static randomHex(bytes: number): string {
    const random = new Uint8Array(bytes);
    for (let i = 0; i < bytes; i++) {
      random[i] = Math.floor(Math.random() * 256);
    }
    let hex = '';
    for (let i = 0; i < random.length; i++) {
      hex += (random[i] < 16 ? '0' : '') + random[i].toString(16);
    }
    return hex;
  }

  private static appVersion(): string {
    try {
      return bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT).versionName || '';
    } catch (_) {
      return '';
    }
  }
}
