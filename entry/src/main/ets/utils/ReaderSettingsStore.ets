import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';
import { ReaderThemeHelper } from './ReaderThemeHelper';
import { CloudSyncChangeTracker } from '../account/CloudSyncChangeTracker';

export class ReaderSettings {
  fontSize: number = 20;
  letterSpacing: number = 0;
  textAlign: string = 'justify';
  lineHeight: number = 12;
  paragraphSpacing: number = 0;
  marginLeft: number = 18;
  marginRight: number = 18;
  marginTop: number = 18;
  marginBottom: number = 18;
  themeIndex: number = 0;
  lightThemeIndex: number = 0;
  darkThemeIndex: number = 0;
  lightCustomThemeBackgroundColor: string = ReaderThemeHelper.LIGHT_CUSTOM_BACKGROUND_COLOR;
  lightCustomThemeTextColor: string = ReaderThemeHelper.LIGHT_CUSTOM_TEXT_COLOR;
  darkCustomThemeBackgroundColor: string = ReaderThemeHelper.DARK_CUSTOM_BACKGROUND_COLOR;
  darkCustomThemeTextColor: string = ReaderThemeHelper.DARK_CUSTOM_TEXT_COLOR;
  customThemesRaw: string = '';
  pageTurnMode: number = 2;
  pageTurnAnimationType: number = 1;
  landscapeDoublePage: boolean = false;
  screenOrientation: string = 'system';
  tapZoneActions: string = '3,3,3,3,1,2,2,2,2';
  volumeTurnPage: boolean = false;
  eyeTurnEnabled: boolean = false;
  eyeTurnPortraitCalibration: string = '';
  eyeTurnLandscapeCalibration: string = '';
  // 眼动方向开关：上一页（向前）默认关闭，下一页（向后）默认开启。
  eyeTurnPreviousEnabled: boolean = false;
  eyeTurnNextEnabled: boolean = true;
  eyeTurnPreviousDwellMs: number = 850;
  eyeTurnNextDwellMs: number = 650;
  screenTimeoutMinutes: number = -1;
  // 保留旧字段用于读取已有主题配置，以及兼容旧版本降级读取。
  keepScreenOn: boolean = true;
  extendToStatusBar: boolean = false;
  preloadEnabled: boolean = true;
  preloadChapterCount: number = 1;
  useTtsQuickAction: boolean = true;
  useChapterQuickJump: boolean = true;
  quickBookmarkEnabled: boolean = true;
  // 阅读页眉页脚配置。默认页眉关闭、页脚保持现有章节/页码信息。
  readerHeaderEnabled: boolean = false;
  readerHeaderContentMode: string = 'chapter';
  readerFooterEnabled: boolean = true;
  readerFooterLeftMode: string = 'chapter';
  readerFooterProgressMode: string = 'page';
  readerFooterShowProgressBar: boolean = false;
  fontFamily: string = '';
  fontFilePath: string = '';
  fontSourceName: string = '系统默认';
  fontMode: string = 'system';
  systemFontFamily: string = '';
  customFontsRaw: string = '';
  bodyFontMode: string = 'global';
  bodyFontFamily: string = '';
  titleFontMode: string = 'global';
  titleFontFamily: string = '';
  titleFontSize: number = 22;
  regexFontEnabled: boolean = false;
  regexFontPattern: string = '';
  regexFontMode: string = 'global';
  regexFontFamily: string = '';
  regexFontSize: number = 20;
  regexShadowColor: string = '';
  regexFontRulesRaw: string = '';
}

export class ReaderSettingsStore {
  static readonly PAGE_TURN_ANIMATION_NONE: number = 0;
  static readonly PAGE_TURN_ANIMATION_SLIDE: number = 1;
  static readonly PAGE_TURN_ANIMATION_FADE: number = 3;
  static readonly PAGE_TURN_ANIMATION_STACK: number = 4;
  static readonly PAGE_TURN_ANIMATION_VERTICAL: number = 5;
  static readonly PAGE_TURN_ANIMATION_SIMULATION: number = 6;
  static readonly PAGE_TURN_ANIMATION_3D: number = 7;
  static readonly SCREEN_TIMEOUT_FOLLOW_SYSTEM: number = 0;
  static readonly SCREEN_TIMEOUT_ALWAYS_ON: number = -1;
  static readonly SCREEN_ORIENTATION_SYSTEM: string = 'system';
  static readonly SCREEN_ORIENTATION_PORTRAIT: string = 'portrait';
  static readonly SCREEN_ORIENTATION_LANDSCAPE: string = 'landscape';
  static readonly KEY_FONT_SIZE: string = 'readerFontSize';
  static readonly KEY_LETTER_SPACING: string = 'readerLetterSpacing';
  static readonly KEY_TEXT_ALIGN: string = 'readerTextAlign';
  static readonly KEY_LINE_HEIGHT: string = 'readerLineHeight';
  static readonly KEY_LINE_HEIGHT_MODE: string = 'readerLineHeightMode';
  static readonly KEY_PARAGRAPH_SPACING: string = 'readerParagraphSpacing';
  static readonly KEY_MARGIN_LEFT: string = 'readerMarginLeft';
  static readonly KEY_MARGIN_RIGHT: string = 'readerMarginRight';
  static readonly KEY_MARGIN_TOP: string = 'readerMarginTop';
  static readonly KEY_MARGIN_BOTTOM: string = 'readerMarginBottom';
  static readonly KEY_THEME_INDEX: string = 'readerThemeIndex';
  static readonly KEY_LIGHT_THEME_INDEX: string = 'readerLightThemeIndex';
  static readonly KEY_DARK_THEME_INDEX: string = 'readerDarkThemeIndex';
  static readonly KEY_LIGHT_CUSTOM_THEME_BACKGROUND_COLOR: string = 'readerLightCustomThemeBackgroundColor';
  static readonly KEY_LIGHT_CUSTOM_THEME_TEXT_COLOR: string = 'readerLightCustomThemeTextColor';
  static readonly KEY_DARK_CUSTOM_THEME_BACKGROUND_COLOR: string = 'readerDarkCustomThemeBackgroundColor';
  static readonly KEY_DARK_CUSTOM_THEME_TEXT_COLOR: string = 'readerDarkCustomThemeTextColor';
  static readonly KEY_CUSTOM_THEMES_RAW: string = 'readerCustomThemesRaw';
  static readonly KEY_PAGE_TURN_MODE: string = 'readerPageTurnMode';
  static readonly KEY_PAGE_TURN_ANIMATION: string = 'readerPageTurnAnimation';
  static readonly KEY_PAGE_TURN_ANIMATION_TYPE: string = 'readerPageTurnAnimationType';
  static readonly KEY_LANDSCAPE_DOUBLE_PAGE: string = 'readerLandscapeDoublePage';
  static readonly KEY_SCREEN_ORIENTATION: string = 'readerScreenOrientation';
  static readonly KEY_TAP_ZONE_ACTIONS: string = 'readerTapZoneActions';
  static readonly KEY_VOLUME_TURN_PAGE: string = 'readerVolumeTurnPage';
  static readonly KEY_EYE_TURN_ENABLED: string = 'readerEyeTurnEnabled';
  static readonly KEY_EYE_TURN_PORTRAIT_CALIBRATION: string = 'readerEyeTurnPortraitCalibration';
  static readonly KEY_EYE_TURN_LANDSCAPE_CALIBRATION: string = 'readerEyeTurnLandscapeCalibration';
  static readonly KEY_EYE_TURN_PREVIOUS_ENABLED: string = 'readerEyeTurnPreviousEnabled';
  static readonly KEY_EYE_TURN_NEXT_ENABLED: string = 'readerEyeTurnNextEnabled';
  static readonly KEY_EYE_TURN_PREVIOUS_DWELL_MS: string = 'readerEyeTurnPreviousDwellMs';
  static readonly KEY_EYE_TURN_NEXT_DWELL_MS: string = 'readerEyeTurnNextDwellMs';
  static readonly KEY_SCREEN_TIMEOUT_MINUTES: string = 'readerScreenTimeoutMinutes';
  static readonly KEY_KEEP_SCREEN_ON: string = 'readerKeepScreenOn';
  static readonly KEY_EXTEND_TO_STATUS_BAR: string = 'readerExtendToStatusBar';
  static readonly KEY_PRELOAD_ENABLED: string = 'readerPreloadEnabled';
  static readonly KEY_PRELOAD_CHAPTER_COUNT: string = 'readerPreloadChapterCount';
  static readonly KEY_USE_TTS_QUICK_ACTION: string = 'readerUseTtsQuickAction';
  static readonly KEY_USE_CHAPTER_QUICK_JUMP: string = 'readerUseChapterQuickJump';
  static readonly KEY_QUICK_BOOKMARK_ENABLED: string = 'readerQuickBookmarkEnabled';
  static readonly KEY_HEADER_ENABLED: string = 'readerHeaderEnabled';
  static readonly KEY_HEADER_CONTENT_MODE: string = 'readerHeaderContentMode';
  static readonly KEY_FOOTER_ENABLED: string = 'readerFooterEnabled';
  static readonly KEY_FOOTER_LEFT_MODE: string = 'readerFooterLeftMode';
  static readonly KEY_FOOTER_PROGRESS_MODE: string = 'readerFooterProgressMode';
  static readonly KEY_FOOTER_SHOW_PROGRESS_BAR: string = 'readerFooterShowProgressBar';
  static readonly KEY_FONT_FAMILY: string = 'readerFontFamily';
  static readonly KEY_FONT_FILE_PATH: string = 'readerFontFilePath';
  static readonly KEY_FONT_SOURCE_NAME: string = 'readerFontSourceName';
  static readonly KEY_FONT_MODE: string = 'readerFontMode';
  static readonly KEY_SYSTEM_FONT_FAMILY: string = 'readerSystemFontFamily';
  static readonly KEY_CUSTOM_FONTS_RAW: string = 'readerCustomFontsRaw';
  static readonly KEY_BODY_FONT_MODE: string = 'readerBodyFontMode';
  static readonly KEY_BODY_FONT_FAMILY: string = 'readerBodyFontFamily';
  static readonly KEY_TITLE_FONT_MODE: string = 'readerTitleFontMode';
  static readonly KEY_TITLE_FONT_FAMILY: string = 'readerTitleFontFamily';
  static readonly KEY_TITLE_FONT_SIZE: string = 'readerTitleFontSize';
  static readonly KEY_REGEX_FONT_ENABLED: string = 'readerRegexFontEnabled';
  static readonly KEY_REGEX_FONT_PATTERN: string = 'readerRegexFontPattern';
  static readonly KEY_REGEX_FONT_MODE: string = 'readerRegexFontMode';
  static readonly KEY_REGEX_FONT_FAMILY: string = 'readerRegexFontFamily';
  static readonly KEY_REGEX_FONT_SIZE: string = 'readerRegexFontSize';
  static readonly KEY_REGEX_SHADOW_COLOR: string = 'readerRegexShadowColor';
  static readonly KEY_REGEX_FONT_RULES_RAW: string = 'readerRegexFontRulesRaw';
  private static readonly STORE_NAME: string = 'reader_settings';
  private static readonly THEME_PROFILE_PREFIX: string = 'readerThemeProfileV1_';
  private static cachedSettings: ReaderSettings | null = null;
  private static cachedThemeId: string = '';
  private static readerFontStyleSaveQueue: Promise<void> = Promise.resolve();
  private static layoutElementSaveQueue: Promise<void> = Promise.resolve();
  private static readerChromeSaveQueue: Promise<void> = Promise.resolve();

  static async load(context: Context): Promise<ReaderSettings> {
    const activeThemeId = ReaderSettingsStore.activeThemeId();
    if (ReaderSettingsStore.cachedSettings && ReaderSettingsStore.cachedThemeId === activeThemeId) {
      return ReaderSettingsStore.clone(ReaderSettingsStore.cachedSettings);
    }
    const store = await preferences.getPreferences(context, ReaderSettingsStore.STORE_NAME);
    const profile = await ReaderSettingsStore.loadThemeProfile(store, activeThemeId);
    if (profile) {
      ReaderSettingsStore.cachedSettings = ReaderSettingsStore.clone(profile);
      ReaderSettingsStore.cachedThemeId = activeThemeId;
      return ReaderSettingsStore.clone(profile);
    }
    const settings = new ReaderSettings();
    settings.fontSize = await ReaderSettingsStore.getNumber(
      store,
      ReaderSettingsStore.KEY_FONT_SIZE,
      20,
      'fontSize'
    );
    settings.letterSpacing = await ReaderSettingsStore.getNumber(
      store, ReaderSettingsStore.KEY_LETTER_SPACING, 0, 'letterSpacing');
    settings.textAlign = ReaderSettingsStore.normalizeTextAlign(
      await ReaderSettingsStore.getString(store, ReaderSettingsStore.KEY_TEXT_ALIGN, 'justify'));
    settings.lineHeight = await ReaderSettingsStore.getNumber(
      store,
      ReaderSettingsStore.KEY_LINE_HEIGHT,
      32,
      'legacyLineHeight',
      settings.fontSize,
      await ReaderSettingsStore.getString(store, ReaderSettingsStore.KEY_LINE_HEIGHT_MODE, '')
    );
    settings.paragraphSpacing = await ReaderSettingsStore.getNumber(
      store,
      ReaderSettingsStore.KEY_PARAGRAPH_SPACING,
      0,
      'paragraphSpacing'
    );
    settings.marginLeft = await ReaderSettingsStore.getNumber(
      store, ReaderSettingsStore.KEY_MARGIN_LEFT, 18, 'horizontalMargin');
    settings.marginRight = await ReaderSettingsStore.getNumber(
      store, ReaderSettingsStore.KEY_MARGIN_RIGHT, 18, 'horizontalMargin');
    settings.marginTop = await ReaderSettingsStore.getNumber(
      store, ReaderSettingsStore.KEY_MARGIN_TOP, 18, 'verticalMargin');
    settings.marginBottom = await ReaderSettingsStore.getNumber(
      store, ReaderSettingsStore.KEY_MARGIN_BOTTOM, 18, 'verticalMargin');
    const legacyThemeIndex = await ReaderSettingsStore.getNumber(
      store,
      ReaderSettingsStore.KEY_THEME_INDEX,
      0,
      'themeIndex'
    );
    settings.themeIndex = legacyThemeIndex;
    settings.lightThemeIndex = await ReaderSettingsStore.getNumber(
      store,
      ReaderSettingsStore.KEY_LIGHT_THEME_INDEX,
      legacyThemeIndex,
      'themeIndex'
    );
    settings.darkThemeIndex = await ReaderSettingsStore.getNumber(
      store,
      ReaderSettingsStore.KEY_DARK_THEME_INDEX,
      legacyThemeIndex,
      'themeIndex'
    );
    settings.lightCustomThemeBackgroundColor = ReaderSettingsStore.normalizeColor(
      await ReaderSettingsStore.getString(
        store,
        ReaderSettingsStore.KEY_LIGHT_CUSTOM_THEME_BACKGROUND_COLOR,
        ReaderThemeHelper.LIGHT_CUSTOM_BACKGROUND_COLOR
      ),
      ReaderThemeHelper.LIGHT_CUSTOM_BACKGROUND_COLOR
    );
    settings.lightCustomThemeTextColor = ReaderSettingsStore.normalizeColor(
      await ReaderSettingsStore.getString(
        store,
        ReaderSettingsStore.KEY_LIGHT_CUSTOM_THEME_TEXT_COLOR,
        ReaderThemeHelper.LIGHT_CUSTOM_TEXT_COLOR
      ),
      ReaderThemeHelper.LIGHT_CUSTOM_TEXT_COLOR
    );
    settings.darkCustomThemeBackgroundColor = ReaderSettingsStore.normalizeColor(
      await ReaderSettingsStore.getString(
        store,
        ReaderSettingsStore.KEY_DARK_CUSTOM_THEME_BACKGROUND_COLOR,
        ReaderThemeHelper.DARK_CUSTOM_BACKGROUND_COLOR
      ),
      ReaderThemeHelper.DARK_CUSTOM_BACKGROUND_COLOR
    );
    settings.darkCustomThemeTextColor = ReaderSettingsStore.normalizeColor(
      await ReaderSettingsStore.getString(
        store,
        ReaderSettingsStore.KEY_DARK_CUSTOM_THEME_TEXT_COLOR,
        ReaderThemeHelper.DARK_CUSTOM_TEXT_COLOR
      ),
      ReaderThemeHelper.DARK_CUSTOM_TEXT_COLOR
    );
    settings.customThemesRaw = await ReaderSettingsStore.getString(
      store,
      ReaderSettingsStore.KEY_CUSTOM_THEMES_RAW,
      ''
    );
    settings.pageTurnMode = await ReaderSettingsStore.getNumber(
      store,
      ReaderSettingsStore.KEY_PAGE_TURN_MODE,
      2,
      'pageTurnMode'
    );
    const legacyPageTurnAnimation = await ReaderSettingsStore.getBoolean(
      store,
      ReaderSettingsStore.KEY_PAGE_TURN_ANIMATION,
      AppStorage.get<boolean>(ReaderSettingsStore.KEY_PAGE_TURN_ANIMATION) ?? true
    );
    const storedPageTurnAnimationType = await ReaderSettingsStore.getNumber(
      store,
      ReaderSettingsStore.KEY_PAGE_TURN_ANIMATION_TYPE,
      legacyPageTurnAnimation ?
        ReaderSettingsStore.PAGE_TURN_ANIMATION_SLIDE :
        ReaderSettingsStore.PAGE_TURN_ANIMATION_NONE,
      'pageTurnAnimationType'
    );
    settings.pageTurnAnimationType = legacyPageTurnAnimation ?
      storedPageTurnAnimationType :
      ReaderSettingsStore.PAGE_TURN_ANIMATION_NONE;
    settings.pageTurnAnimationType = ReaderSettingsStore.normalizePageTurnAnimationForMode(
      settings.pageTurnMode, settings.pageTurnAnimationType);
    settings.landscapeDoublePage = await ReaderSettingsStore.getBoolean(
      store,
      ReaderSettingsStore.KEY_LANDSCAPE_DOUBLE_PAGE,
      AppStorage.get<boolean>(ReaderSettingsStore.KEY_LANDSCAPE_DOUBLE_PAGE) ?? false
    );
    settings.screenOrientation = ReaderSettingsStore.normalizeScreenOrientation(
      await ReaderSettingsStore.getString(
        store,
        ReaderSettingsStore.KEY_SCREEN_ORIENTATION,
        AppStorage.get<string>(ReaderSettingsStore.KEY_SCREEN_ORIENTATION) ||
          ReaderSettingsStore.SCREEN_ORIENTATION_SYSTEM
      )
    );
    settings.tapZoneActions = ReaderSettingsStore.normalizeTapZoneActions(
      await ReaderSettingsStore.getString(
        store,
        ReaderSettingsStore.KEY_TAP_ZONE_ACTIONS,
        AppStorage.get<string>(ReaderSettingsStore.KEY_TAP_ZONE_ACTIONS) || '3,3,3,3,1,2,2,2,2'
      )
    );
    settings.volumeTurnPage = await ReaderSettingsStore.getBoolean(
      store,
      ReaderSettingsStore.KEY_VOLUME_TURN_PAGE,
      AppStorage.get<boolean>(ReaderSettingsStore.KEY_VOLUME_TURN_PAGE) ?? false
    );
    settings.eyeTurnEnabled = await ReaderSettingsStore.getBoolean(
      store,
      ReaderSettingsStore.KEY_EYE_TURN_ENABLED,
      AppStorage.get<boolean>(ReaderSettingsStore.KEY_EYE_TURN_ENABLED) ?? false
    );
    settings.eyeTurnPortraitCalibration = await ReaderSettingsStore.getString(
      store, ReaderSettingsStore.KEY_EYE_TURN_PORTRAIT_CALIBRATION,
      AppStorage.get<string>(ReaderSettingsStore.KEY_EYE_TURN_PORTRAIT_CALIBRATION) || '');
    settings.eyeTurnLandscapeCalibration = await ReaderSettingsStore.getString(
      store, ReaderSettingsStore.KEY_EYE_TURN_LANDSCAPE_CALIBRATION,
      AppStorage.get<string>(ReaderSettingsStore.KEY_EYE_TURN_LANDSCAPE_CALIBRATION) || '');
    settings.eyeTurnPreviousEnabled = await ReaderSettingsStore.getBoolean(
      store,
      ReaderSettingsStore.KEY_EYE_TURN_PREVIOUS_ENABLED,
      AppStorage.get<boolean>(ReaderSettingsStore.KEY_EYE_TURN_PREVIOUS_ENABLED) ?? false
    );
    settings.eyeTurnNextEnabled = await ReaderSettingsStore.getBoolean(
      store,
      ReaderSettingsStore.KEY_EYE_TURN_NEXT_ENABLED,
      AppStorage.get<boolean>(ReaderSettingsStore.KEY_EYE_TURN_NEXT_ENABLED) ?? true
    );
    settings.eyeTurnPreviousDwellMs = await ReaderSettingsStore.getNumber(
      store, ReaderSettingsStore.KEY_EYE_TURN_PREVIOUS_DWELL_MS, 850, 'eyeTurnDwell');
    settings.eyeTurnNextDwellMs = await ReaderSettingsStore.getNumber(
      store, ReaderSettingsStore.KEY_EYE_TURN_NEXT_DWELL_MS, 650, 'eyeTurnDwell');
    const legacyKeepScreenOn = await ReaderSettingsStore.getBoolean(
      store,
      ReaderSettingsStore.KEY_KEEP_SCREEN_ON,
      AppStorage.get<boolean>(ReaderSettingsStore.KEY_KEEP_SCREEN_ON) ?? true
    );
    settings.screenTimeoutMinutes = await ReaderSettingsStore.getNumber(
      store,
      ReaderSettingsStore.KEY_SCREEN_TIMEOUT_MINUTES,
      legacyKeepScreenOn ?
        ReaderSettingsStore.SCREEN_TIMEOUT_ALWAYS_ON :
        ReaderSettingsStore.SCREEN_TIMEOUT_FOLLOW_SYSTEM,
      'screenTimeoutMinutes'
    );
    settings.keepScreenOn =
      settings.screenTimeoutMinutes !== ReaderSettingsStore.SCREEN_TIMEOUT_FOLLOW_SYSTEM;
    settings.extendToStatusBar = await ReaderSettingsStore.getBoolean(
      store,
      ReaderSettingsStore.KEY_EXTEND_TO_STATUS_BAR,
      AppStorage.get<boolean>(ReaderSettingsStore.KEY_EXTEND_TO_STATUS_BAR) ?? false
    );
    settings.preloadEnabled = await ReaderSettingsStore.getBoolean(
      store,
      ReaderSettingsStore.KEY_PRELOAD_ENABLED,
      true
    );
    settings.preloadChapterCount = await ReaderSettingsStore.getNumber(
      store,
      ReaderSettingsStore.KEY_PRELOAD_CHAPTER_COUNT,
      1,
      'preloadChapterCount'
    );
    settings.useTtsQuickAction = await ReaderSettingsStore.getBoolean(
      store,
      ReaderSettingsStore.KEY_USE_TTS_QUICK_ACTION,
      AppStorage.get<boolean>(ReaderSettingsStore.KEY_USE_TTS_QUICK_ACTION) ?? true
    );
    settings.useChapterQuickJump = await ReaderSettingsStore.getBoolean(
      store,
      ReaderSettingsStore.KEY_USE_CHAPTER_QUICK_JUMP,
      AppStorage.get<boolean>(ReaderSettingsStore.KEY_USE_CHAPTER_QUICK_JUMP) ?? true
    );
    settings.quickBookmarkEnabled = await ReaderSettingsStore.getBoolean(
      store,
      ReaderSettingsStore.KEY_QUICK_BOOKMARK_ENABLED,
      AppStorage.get<boolean>(ReaderSettingsStore.KEY_QUICK_BOOKMARK_ENABLED) ?? true
    );
    settings.readerHeaderEnabled = await ReaderSettingsStore.getBoolean(
      store, ReaderSettingsStore.KEY_HEADER_ENABLED, false);
    settings.readerHeaderContentMode = ReaderSettingsStore.normalizeHeaderContentMode(
      await ReaderSettingsStore.getString(store, ReaderSettingsStore.KEY_HEADER_CONTENT_MODE, 'chapter'));
    settings.readerFooterEnabled = await ReaderSettingsStore.getBoolean(
      store, ReaderSettingsStore.KEY_FOOTER_ENABLED, true);
    settings.readerFooterLeftMode = ReaderSettingsStore.normalizeFooterLeftMode(
      await ReaderSettingsStore.getString(store, ReaderSettingsStore.KEY_FOOTER_LEFT_MODE, 'chapter'));
    settings.readerFooterProgressMode = ReaderSettingsStore.normalizeFooterProgressMode(
      await ReaderSettingsStore.getString(store, ReaderSettingsStore.KEY_FOOTER_PROGRESS_MODE, 'page'));
    settings.readerFooterShowProgressBar = await ReaderSettingsStore.getBoolean(
      store, ReaderSettingsStore.KEY_FOOTER_SHOW_PROGRESS_BAR, false);
    settings.fontFamily = await ReaderSettingsStore.getString(store, ReaderSettingsStore.KEY_FONT_FAMILY, '');
    settings.fontFilePath = await ReaderSettingsStore.getString(store, ReaderSettingsStore.KEY_FONT_FILE_PATH, '');
    settings.fontSourceName = await ReaderSettingsStore.getString(store, ReaderSettingsStore.KEY_FONT_SOURCE_NAME, '系统默认');
    settings.fontMode = await ReaderSettingsStore.getString(store, ReaderSettingsStore.KEY_FONT_MODE, 'system');
    settings.systemFontFamily = await ReaderSettingsStore.getString(store, ReaderSettingsStore.KEY_SYSTEM_FONT_FAMILY, '');
    settings.customFontsRaw = await ReaderSettingsStore.getString(store, ReaderSettingsStore.KEY_CUSTOM_FONTS_RAW, '');
    settings.bodyFontMode = ReaderSettingsStore.normalizeFontMode(await ReaderSettingsStore.getString(store, ReaderSettingsStore.KEY_BODY_FONT_MODE, 'global'));
    settings.bodyFontFamily = await ReaderSettingsStore.getString(store, ReaderSettingsStore.KEY_BODY_FONT_FAMILY, '');
    settings.titleFontMode = ReaderSettingsStore.normalizeFontMode(await ReaderSettingsStore.getString(store, ReaderSettingsStore.KEY_TITLE_FONT_MODE, 'global'));
    settings.titleFontFamily = await ReaderSettingsStore.getString(store, ReaderSettingsStore.KEY_TITLE_FONT_FAMILY, '');
    settings.titleFontSize = await ReaderSettingsStore.getNumber(store, ReaderSettingsStore.KEY_TITLE_FONT_SIZE, 22, 'fontSize');
    settings.regexFontEnabled = await ReaderSettingsStore.getBoolean(store, ReaderSettingsStore.KEY_REGEX_FONT_ENABLED, false);
    settings.regexFontPattern = await ReaderSettingsStore.getString(store, ReaderSettingsStore.KEY_REGEX_FONT_PATTERN, '');
    settings.regexFontMode = ReaderSettingsStore.normalizeFontMode(await ReaderSettingsStore.getString(store, ReaderSettingsStore.KEY_REGEX_FONT_MODE, 'global'));
    settings.regexFontFamily = await ReaderSettingsStore.getString(store, ReaderSettingsStore.KEY_REGEX_FONT_FAMILY, '');
    settings.regexFontSize = await ReaderSettingsStore.getNumber(store, ReaderSettingsStore.KEY_REGEX_FONT_SIZE, 20, 'fontSize');
    settings.regexShadowColor = await ReaderSettingsStore.getString(store, ReaderSettingsStore.KEY_REGEX_SHADOW_COLOR, '');
    settings.regexFontRulesRaw = await ReaderSettingsStore.getString(store, ReaderSettingsStore.KEY_REGEX_FONT_RULES_RAW, '');
    ReaderSettingsStore.mergeStorageFontSettings(settings);
    ReaderSettingsStore.cachedSettings = ReaderSettingsStore.clone(settings);
    ReaderSettingsStore.cachedThemeId = activeThemeId;
    await ReaderSettingsStore.persistThemeProfile(store, activeThemeId, settings);
    await store.flush();
    return settings;
  }

  static async reload(context: Context): Promise<ReaderSettings> {
    await ReaderSettingsStore.waitForReaderFontStyleSaves();
    await ReaderSettingsStore.waitForLayoutElementSaves();
    ReaderSettingsStore.cachedSettings = null;
    ReaderSettingsStore.cachedThemeId = '';
    return await ReaderSettingsStore.load(context);
  }

  static async switchThemeProfile(context: Context, previousThemeId: string,
    nextThemeId: string): Promise<ReaderSettings> {
    const store = await preferences.getPreferences(context, ReaderSettingsStore.STORE_NAME);
    const previousId = ReaderSettingsStore.normalizeThemeProfileId(previousThemeId);
    const nextId = ReaderSettingsStore.normalizeThemeProfileId(nextThemeId);
    const current = ReaderSettingsStore.cachedSettings && ReaderSettingsStore.cachedThemeId === previousId ?
      ReaderSettingsStore.clone(ReaderSettingsStore.cachedSettings) : ReaderSettingsStore.fromStorage();
    await ReaderSettingsStore.persistThemeProfile(store, previousId, current);

    let next = await ReaderSettingsStore.loadThemeProfile(store, nextId);
    if (!next) {
      next = ReaderSettingsStore.clone(current);
      next.lightThemeIndex = ReaderThemeHelper.APP_THEME_INDEX;
      next.darkThemeIndex = ReaderThemeHelper.APP_THEME_INDEX;
      next.themeIndex = ReaderThemeHelper.APP_THEME_INDEX;
      await ReaderSettingsStore.persistThemeProfile(store, nextId, next);
    }
    ReaderSettingsStore.cachedSettings = ReaderSettingsStore.clone(next);
    ReaderSettingsStore.cachedThemeId = nextId;
    ReaderSettingsStore.applyToStorage(next);
    await store.flush();
    return ReaderSettingsStore.clone(next);
  }

  static async saveLayoutSettings(
    context: Context,
    fontSize: number,
    lineHeight: number,
    paragraphSpacing: number,
    marginLeft: number = 18,
    marginRight: number = 18,
    marginTop: number = 18,
    marginBottom: number = 18,
    letterSpacing: number = 0,
    textAlign: string = 'justify'
  ): Promise<void> {
    const settings = ReaderSettingsStore.cachedSettings || ReaderSettingsStore.fromStorage();
    settings.fontSize = ReaderSettingsStore.normalizeFontSize(fontSize);
    settings.letterSpacing = ReaderSettingsStore.normalizeLetterSpacing(letterSpacing);
    settings.textAlign = ReaderSettingsStore.normalizeTextAlign(textAlign);
    settings.lineHeight = ReaderSettingsStore.normalizeLineHeight(lineHeight);
    settings.paragraphSpacing = ReaderSettingsStore.normalizeParagraphSpacing(paragraphSpacing);
    settings.marginLeft = ReaderSettingsStore.normalizeHorizontalMargin(marginLeft);
    settings.marginRight = ReaderSettingsStore.normalizeHorizontalMargin(marginRight);
    settings.marginTop = ReaderSettingsStore.normalizeVerticalMargin(marginTop);
    settings.marginBottom = ReaderSettingsStore.normalizeVerticalMargin(marginBottom);
    ReaderSettingsStore.cachedSettings = ReaderSettingsStore.clone(settings);
    ReaderSettingsStore.applyLayoutToStorage(settings);
    const store = await preferences.getPreferences(context, ReaderSettingsStore.STORE_NAME);
    await store.put(ReaderSettingsStore.KEY_FONT_SIZE, settings.fontSize);
    await store.put(ReaderSettingsStore.KEY_LETTER_SPACING, settings.letterSpacing);
    await store.put(ReaderSettingsStore.KEY_TEXT_ALIGN, settings.textAlign);
    await store.put(ReaderSettingsStore.KEY_LINE_HEIGHT, settings.lineHeight);
    await store.put(ReaderSettingsStore.KEY_LINE_HEIGHT_MODE, 'spacing');
    await store.put(ReaderSettingsStore.KEY_PARAGRAPH_SPACING, settings.paragraphSpacing);
    await store.put(ReaderSettingsStore.KEY_MARGIN_LEFT, settings.marginLeft);
    await store.put(ReaderSettingsStore.KEY_MARGIN_RIGHT, settings.marginRight);
    await store.put(ReaderSettingsStore.KEY_MARGIN_TOP, settings.marginTop);
    await store.put(ReaderSettingsStore.KEY_MARGIN_BOTTOM, settings.marginBottom);
    await ReaderSettingsStore.persistActiveThemeProfile(store, settings);
    await store.flush();
  }

  static async saveThemeSettings(
    context: Context,
    lightThemeIndex: number,
    darkThemeIndex: number,
    lightCustomThemeBackgroundColor: string,
    lightCustomThemeTextColor: string,
    darkCustomThemeBackgroundColor: string,
    darkCustomThemeTextColor: string,
    currentDarkMode: boolean,
    customThemesRaw: string = ''
  ): Promise<void> {
    const settings = ReaderSettingsStore.cachedSettings || ReaderSettingsStore.fromStorage();
    settings.lightThemeIndex = ReaderSettingsStore.normalizeThemeIndex(lightThemeIndex);
    settings.darkThemeIndex = ReaderSettingsStore.normalizeThemeIndex(darkThemeIndex);
    settings.lightCustomThemeBackgroundColor = ReaderSettingsStore.normalizeColor(
      lightCustomThemeBackgroundColor,
      ReaderThemeHelper.LIGHT_CUSTOM_BACKGROUND_COLOR
    );
    settings.lightCustomThemeTextColor = ReaderSettingsStore.normalizeColor(
      lightCustomThemeTextColor,
      ReaderThemeHelper.LIGHT_CUSTOM_TEXT_COLOR
    );
    settings.darkCustomThemeBackgroundColor = ReaderSettingsStore.normalizeColor(
      darkCustomThemeBackgroundColor,
      ReaderThemeHelper.DARK_CUSTOM_BACKGROUND_COLOR
    );
    settings.darkCustomThemeTextColor = ReaderSettingsStore.normalizeColor(
      darkCustomThemeTextColor,
      ReaderThemeHelper.DARK_CUSTOM_TEXT_COLOR
    );
    settings.customThemesRaw = customThemesRaw || settings.customThemesRaw || '';
    settings.themeIndex = currentDarkMode ? settings.darkThemeIndex : settings.lightThemeIndex;
    ReaderSettingsStore.cachedSettings = ReaderSettingsStore.clone(settings);
    ReaderSettingsStore.applyThemeToStorage(settings);
    const store = await preferences.getPreferences(context, ReaderSettingsStore.STORE_NAME);
    await store.put(ReaderSettingsStore.KEY_THEME_INDEX, settings.themeIndex);
    await store.put(ReaderSettingsStore.KEY_LIGHT_THEME_INDEX, settings.lightThemeIndex);
    await store.put(ReaderSettingsStore.KEY_DARK_THEME_INDEX, settings.darkThemeIndex);
    await store.put(
      ReaderSettingsStore.KEY_LIGHT_CUSTOM_THEME_BACKGROUND_COLOR,
      settings.lightCustomThemeBackgroundColor
    );
    await store.put(ReaderSettingsStore.KEY_LIGHT_CUSTOM_THEME_TEXT_COLOR, settings.lightCustomThemeTextColor);
    await store.put(
      ReaderSettingsStore.KEY_DARK_CUSTOM_THEME_BACKGROUND_COLOR,
      settings.darkCustomThemeBackgroundColor
    );
    await store.put(ReaderSettingsStore.KEY_DARK_CUSTOM_THEME_TEXT_COLOR, settings.darkCustomThemeTextColor);
    await store.put(ReaderSettingsStore.KEY_CUSTOM_THEMES_RAW, settings.customThemesRaw);
    await ReaderSettingsStore.persistActiveThemeProfile(store, settings);
    await store.flush();
  }

  static async savePageTurnMode(context: Context, mode: number): Promise<void> {
    const settings = ReaderSettingsStore.cachedSettings || ReaderSettingsStore.fromStorage();
    settings.pageTurnMode = ReaderSettingsStore.normalizePageTurnMode(mode);
    ReaderSettingsStore.cachedSettings = ReaderSettingsStore.clone(settings);
    const store = await preferences.getPreferences(context, ReaderSettingsStore.STORE_NAME);
    await store.put(ReaderSettingsStore.KEY_PAGE_TURN_MODE, settings.pageTurnMode);
    await ReaderSettingsStore.persistActiveThemeProfile(store, settings);
    await store.flush();
  }

  static async saveReadingInteractionSettings(
    context: Context,
    volumeTurnPage: boolean,
    screenTimeoutMinutes: number,
    extendToStatusBar: boolean
  ): Promise<void> {
    const settings = ReaderSettingsStore.cachedSettings || ReaderSettingsStore.fromStorage();
    settings.volumeTurnPage = volumeTurnPage;
    settings.screenTimeoutMinutes = ReaderSettingsStore.normalizeScreenTimeoutMinutes(screenTimeoutMinutes);
    settings.keepScreenOn =
      settings.screenTimeoutMinutes !== ReaderSettingsStore.SCREEN_TIMEOUT_FOLLOW_SYSTEM;
    settings.extendToStatusBar = extendToStatusBar;
    ReaderSettingsStore.cachedSettings = ReaderSettingsStore.clone(settings);
    ReaderSettingsStore.applyInteractionToStorage(settings);
    const store = await preferences.getPreferences(context, ReaderSettingsStore.STORE_NAME);
    await store.put(ReaderSettingsStore.KEY_VOLUME_TURN_PAGE, settings.volumeTurnPage);
    await store.put(ReaderSettingsStore.KEY_SCREEN_TIMEOUT_MINUTES, settings.screenTimeoutMinutes);
    await store.put(ReaderSettingsStore.KEY_KEEP_SCREEN_ON, settings.keepScreenOn);
    await store.put(ReaderSettingsStore.KEY_EXTEND_TO_STATUS_BAR, settings.extendToStatusBar);
    await ReaderSettingsStore.persistActiveThemeProfile(store, settings);
    await store.flush();
  }

  static async saveEyeTurnSettings(
    context: Context,
    enabled: boolean,
    portraitCalibration: string,
    landscapeCalibration: string,
    previousEnabled: boolean,
    nextEnabled: boolean,
    previousDwellMs: number,
    nextDwellMs: number
  ): Promise<void> {
    const settings = ReaderSettingsStore.cachedSettings || ReaderSettingsStore.fromStorage();
    settings.eyeTurnEnabled = enabled;
    settings.eyeTurnPortraitCalibration = portraitCalibration || '';
    settings.eyeTurnLandscapeCalibration = landscapeCalibration || '';
    settings.eyeTurnPreviousEnabled = previousEnabled === true;
    settings.eyeTurnNextEnabled = nextEnabled !== false;
    settings.eyeTurnPreviousDwellMs = ReaderSettingsStore.normalizeEyeTurnDwell(previousDwellMs);
    settings.eyeTurnNextDwellMs = ReaderSettingsStore.normalizeEyeTurnDwell(nextDwellMs);
    ReaderSettingsStore.cachedSettings = ReaderSettingsStore.clone(settings);
    ReaderSettingsStore.applyEyeTurnToStorage(settings);
    const store = await preferences.getPreferences(context, ReaderSettingsStore.STORE_NAME);
    await store.put(ReaderSettingsStore.KEY_EYE_TURN_ENABLED, settings.eyeTurnEnabled);
    await store.put(ReaderSettingsStore.KEY_EYE_TURN_PORTRAIT_CALIBRATION,
      settings.eyeTurnPortraitCalibration);
    await store.put(ReaderSettingsStore.KEY_EYE_TURN_LANDSCAPE_CALIBRATION,
      settings.eyeTurnLandscapeCalibration);
    await store.put(ReaderSettingsStore.KEY_EYE_TURN_PREVIOUS_ENABLED,
      settings.eyeTurnPreviousEnabled);
    await store.put(ReaderSettingsStore.KEY_EYE_TURN_NEXT_ENABLED,
      settings.eyeTurnNextEnabled);
    await store.put(ReaderSettingsStore.KEY_EYE_TURN_PREVIOUS_DWELL_MS,
      settings.eyeTurnPreviousDwellMs);
    await store.put(ReaderSettingsStore.KEY_EYE_TURN_NEXT_DWELL_MS,
      settings.eyeTurnNextDwellMs);
    await ReaderSettingsStore.persistActiveThemeProfile(store, settings);
    await store.flush();
  }

  static async saveTapZoneActions(context: Context, actions: string): Promise<void> {
    const settings = ReaderSettingsStore.cachedSettings || ReaderSettingsStore.fromStorage();
    settings.tapZoneActions = ReaderSettingsStore.normalizeTapZoneActions(actions);
    ReaderSettingsStore.cachedSettings = ReaderSettingsStore.clone(settings);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_TAP_ZONE_ACTIONS, settings.tapZoneActions);
    const store = await preferences.getPreferences(context, ReaderSettingsStore.STORE_NAME);
    await store.put(ReaderSettingsStore.KEY_TAP_ZONE_ACTIONS, settings.tapZoneActions);
    await ReaderSettingsStore.persistActiveThemeProfile(store, settings);
    await store.flush();
  }

  static async savePreloadEnabled(context: Context, enabled: boolean): Promise<void> {
    const settings = ReaderSettingsStore.cachedSettings || ReaderSettingsStore.fromStorage();
    settings.preloadEnabled = enabled;
    ReaderSettingsStore.cachedSettings = ReaderSettingsStore.clone(settings);
    const store = await preferences.getPreferences(context, ReaderSettingsStore.STORE_NAME);
    await store.put(ReaderSettingsStore.KEY_PRELOAD_ENABLED, settings.preloadEnabled);
    await ReaderSettingsStore.persistActiveThemeProfile(store, settings);
    await store.flush();
  }

  static async savePreloadChapterCount(context: Context, count: number): Promise<void> {
    const settings = ReaderSettingsStore.cachedSettings || ReaderSettingsStore.fromStorage();
    settings.preloadChapterCount = ReaderSettingsStore.normalizePreloadChapterCount(count);
    ReaderSettingsStore.cachedSettings = ReaderSettingsStore.clone(settings);
    const store = await preferences.getPreferences(context, ReaderSettingsStore.STORE_NAME);
    await store.put(ReaderSettingsStore.KEY_PRELOAD_CHAPTER_COUNT, settings.preloadChapterCount);
    await ReaderSettingsStore.persistActiveThemeProfile(store, settings);
    await store.flush();
  }

  static async saveQuickBookmarkEnabled(context: Context, enabled: boolean): Promise<void> {
    const settings = ReaderSettingsStore.cachedSettings || ReaderSettingsStore.fromStorage();
    settings.quickBookmarkEnabled = enabled;
    ReaderSettingsStore.cachedSettings = ReaderSettingsStore.clone(settings);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_QUICK_BOOKMARK_ENABLED, enabled);
    const store = await preferences.getPreferences(context, ReaderSettingsStore.STORE_NAME);
    await store.put(ReaderSettingsStore.KEY_QUICK_BOOKMARK_ENABLED, enabled);
    await ReaderSettingsStore.persistActiveThemeProfile(store, settings);
    await store.flush();
  }

  static async saveFontSettings(
    context: Context,
    fontFamily: string,
    fontFilePath: string,
    fontSourceName: string,
    fontMode: string,
    systemFontFamily: string,
    customFontsRaw: string
  ): Promise<void> {
    const settings = ReaderSettingsStore.cachedSettings || ReaderSettingsStore.fromStorage();
    settings.fontFamily = fontFamily || '';
    settings.fontFilePath = fontFilePath || '';
    settings.fontSourceName = fontSourceName || '系统默认';
    settings.fontMode = fontMode || 'system';
    settings.systemFontFamily = systemFontFamily || '';
    settings.customFontsRaw = customFontsRaw || '';
    ReaderSettingsStore.cachedSettings = ReaderSettingsStore.clone(settings);
    const store = await preferences.getPreferences(context, ReaderSettingsStore.STORE_NAME);
    await store.put(ReaderSettingsStore.KEY_FONT_FAMILY, settings.fontFamily);
    await store.put(ReaderSettingsStore.KEY_FONT_FILE_PATH, settings.fontFilePath);
    await store.put(ReaderSettingsStore.KEY_FONT_SOURCE_NAME, settings.fontSourceName);
    await store.put(ReaderSettingsStore.KEY_FONT_MODE, settings.fontMode);
    await store.put(ReaderSettingsStore.KEY_SYSTEM_FONT_FAMILY, settings.systemFontFamily);
    await store.put(ReaderSettingsStore.KEY_CUSTOM_FONTS_RAW, settings.customFontsRaw);
    // Global font selection is device-local and must not schedule a cloud-sync
    // pass. Other reader-setting save paths continue to mark preference changes.
    await ReaderSettingsStore.persistThemeProfile(store, ReaderSettingsStore.activeThemeId(), settings);
    ReaderSettingsStore.cachedThemeId = ReaderSettingsStore.activeThemeId();
    await store.flush();
  }

  static async saveReaderFontStyleSettings(context: Context, settings: ReaderSettings): Promise<void> {
    const current = ReaderSettingsStore.cachedSettings || ReaderSettingsStore.fromStorage();
    current.fontSize = ReaderSettingsStore.normalizeFontSize(settings.fontSize || current.fontSize);
    current.bodyFontMode = ReaderSettingsStore.normalizeFontMode(settings.bodyFontMode);
    current.bodyFontFamily = settings.bodyFontFamily || '';
    current.titleFontMode = ReaderSettingsStore.normalizeFontMode(settings.titleFontMode);
    current.titleFontFamily = settings.titleFontFamily || '';
    current.titleFontSize = ReaderSettingsStore.normalizeFontSize(settings.titleFontSize);
    current.regexFontEnabled = settings.regexFontEnabled;
    current.regexFontPattern = settings.regexFontPattern || '';
    current.regexFontMode = ReaderSettingsStore.normalizeFontMode(settings.regexFontMode);
    current.regexFontFamily = settings.regexFontFamily || '';
    current.regexFontSize = ReaderSettingsStore.normalizeFontSize(settings.regexFontSize);
    current.regexShadowColor = settings.regexShadowColor || '';
    current.regexFontRulesRaw = settings.regexFontRulesRaw || '';
    ReaderSettingsStore.cachedSettings = ReaderSettingsStore.clone(current);
    ReaderSettingsStore.applyLayoutToStorage(current);
    ReaderSettingsStore.applyReaderFontStyleToStorage(current);
    const snapshot = ReaderSettingsStore.clone(current);
    await ReaderSettingsStore.enqueueReaderFontStyleSave(context, snapshot);
  }

  private static enqueueReaderFontStyleSave(context: Context, settings: ReaderSettings): Promise<void> {
    const themeId = ReaderSettingsStore.activeThemeId();
    const previous = ReaderSettingsStore.readerFontStyleSaveQueue.catch(() => {
    });
    const next = previous.then(async () => {
      await ReaderSettingsStore.persistReaderFontStyleSettings(context, settings, themeId);
    });
    ReaderSettingsStore.readerFontStyleSaveQueue = next;
    return next;
  }

  static async waitForReaderFontStyleSaves(): Promise<void> {
    try {
      await ReaderSettingsStore.readerFontStyleSaveQueue;
    } catch (e) {
      console.warn('等待阅读字体设置保存失败:', e);
    }
  }

  private static async persistReaderFontStyleSettings(context: Context, current: ReaderSettings,
    themeId: string): Promise<void> {
    const store = await preferences.getPreferences(context, ReaderSettingsStore.STORE_NAME);
    await store.put(ReaderSettingsStore.KEY_FONT_SIZE, current.fontSize);
    await store.put(ReaderSettingsStore.KEY_BODY_FONT_MODE, current.bodyFontMode);
    await store.put(ReaderSettingsStore.KEY_BODY_FONT_FAMILY, current.bodyFontFamily);
    await store.put(ReaderSettingsStore.KEY_TITLE_FONT_MODE, current.titleFontMode);
    await store.put(ReaderSettingsStore.KEY_TITLE_FONT_FAMILY, current.titleFontFamily);
    await store.put(ReaderSettingsStore.KEY_TITLE_FONT_SIZE, current.titleFontSize);
    await store.put(ReaderSettingsStore.KEY_REGEX_FONT_ENABLED, current.regexFontEnabled);
    await store.put(ReaderSettingsStore.KEY_REGEX_FONT_PATTERN, current.regexFontPattern);
    await store.put(ReaderSettingsStore.KEY_REGEX_FONT_MODE, current.regexFontMode);
    await store.put(ReaderSettingsStore.KEY_REGEX_FONT_FAMILY, current.regexFontFamily);
    await store.put(ReaderSettingsStore.KEY_REGEX_FONT_SIZE, current.regexFontSize);
    await store.put(ReaderSettingsStore.KEY_REGEX_SHADOW_COLOR, current.regexShadowColor);
    await store.put(ReaderSettingsStore.KEY_REGEX_FONT_RULES_RAW, current.regexFontRulesRaw);
    await ReaderSettingsStore.persistThemeProfile(store, themeId, current);
    await store.flush();
  }

  static saveLayoutElementSettings(context: Context, useTtsQuickAction: boolean,
    useChapterQuickJump: boolean): Promise<void> {
    const settings = ReaderSettingsStore.cachedSettings || ReaderSettingsStore.fromStorage();
    settings.useTtsQuickAction = useTtsQuickAction;
    settings.useChapterQuickJump = useChapterQuickJump;
    ReaderSettingsStore.cachedSettings = ReaderSettingsStore.clone(settings);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_USE_TTS_QUICK_ACTION, useTtsQuickAction);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_USE_CHAPTER_QUICK_JUMP, useChapterQuickJump);
    const snapshot = ReaderSettingsStore.clone(settings);
    const themeId = ReaderSettingsStore.activeThemeId();
    const previous = ReaderSettingsStore.layoutElementSaveQueue.catch(() => {
    });
    const next = previous.then(async () => {
      const store = await preferences.getPreferences(context, ReaderSettingsStore.STORE_NAME);
      await store.put(ReaderSettingsStore.KEY_USE_TTS_QUICK_ACTION, snapshot.useTtsQuickAction);
      await store.put(ReaderSettingsStore.KEY_USE_CHAPTER_QUICK_JUMP, snapshot.useChapterQuickJump);
      await ReaderSettingsStore.persistThemeProfile(store, themeId, snapshot);
      await store.flush();
    });
    ReaderSettingsStore.layoutElementSaveQueue = next;
    return next;
  }

  private static async waitForLayoutElementSaves(): Promise<void> {
    try {
      await ReaderSettingsStore.layoutElementSaveQueue;
    } catch (e) {
      console.warn('等待阅读布局元素设置保存失败:', e);
    }
  }

  static saveReaderChromeSettings(context: Context, headerEnabled: boolean,
    headerContentMode: string, footerEnabled: boolean, footerLeftMode: string,
    footerProgressMode: string, footerShowProgressBar: boolean): Promise<void> {
    const settings = ReaderSettingsStore.cachedSettings || ReaderSettingsStore.fromStorage();
    settings.readerHeaderEnabled = headerEnabled === true;
    settings.readerHeaderContentMode = ReaderSettingsStore.normalizeHeaderContentMode(headerContentMode);
    settings.readerFooterEnabled = footerEnabled !== false;
    settings.readerFooterLeftMode = ReaderSettingsStore.normalizeFooterLeftMode(footerLeftMode);
    settings.readerFooterProgressMode = ReaderSettingsStore.normalizeFooterProgressMode(footerProgressMode);
    settings.readerFooterShowProgressBar = footerShowProgressBar === true;
    const snapshot = ReaderSettingsStore.clone(settings);
    ReaderSettingsStore.cachedSettings = snapshot;
    ReaderSettingsStore.applyReaderChromeToStorage(snapshot);
    const themeId = ReaderSettingsStore.activeThemeId();
    const previous = ReaderSettingsStore.readerChromeSaveQueue.catch(() => {
    });
    const next = previous.then(async () => {
      const store = await preferences.getPreferences(context, ReaderSettingsStore.STORE_NAME);
      await store.put(ReaderSettingsStore.KEY_HEADER_ENABLED, snapshot.readerHeaderEnabled);
      await store.put(ReaderSettingsStore.KEY_HEADER_CONTENT_MODE, snapshot.readerHeaderContentMode);
      await store.put(ReaderSettingsStore.KEY_FOOTER_ENABLED, snapshot.readerFooterEnabled);
      await store.put(ReaderSettingsStore.KEY_FOOTER_LEFT_MODE, snapshot.readerFooterLeftMode);
      await store.put(ReaderSettingsStore.KEY_FOOTER_PROGRESS_MODE, snapshot.readerFooterProgressMode);
      await store.put(ReaderSettingsStore.KEY_FOOTER_SHOW_PROGRESS_BAR, snapshot.readerFooterShowProgressBar);
      await ReaderSettingsStore.persistThemeProfile(store, themeId, snapshot);
      await store.flush();
    });
    ReaderSettingsStore.readerChromeSaveQueue = next;
    return next;
  }

  static async savePageTurnAnimationType(context: Context, type: number): Promise<void> {
    const settings = ReaderSettingsStore.cachedSettings || ReaderSettingsStore.fromStorage();
    settings.pageTurnAnimationType = ReaderSettingsStore.normalizePageTurnAnimationType(type);
    ReaderSettingsStore.cachedSettings = ReaderSettingsStore.clone(settings);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_PAGE_TURN_ANIMATION_TYPE, settings.pageTurnAnimationType);
    AppStorage.setOrCreate(
      ReaderSettingsStore.KEY_PAGE_TURN_ANIMATION,
      settings.pageTurnAnimationType !== ReaderSettingsStore.PAGE_TURN_ANIMATION_NONE
    );
    const store = await preferences.getPreferences(context, ReaderSettingsStore.STORE_NAME);
    await store.put(ReaderSettingsStore.KEY_PAGE_TURN_ANIMATION_TYPE, settings.pageTurnAnimationType);
    await store.put(
      ReaderSettingsStore.KEY_PAGE_TURN_ANIMATION,
      settings.pageTurnAnimationType !== ReaderSettingsStore.PAGE_TURN_ANIMATION_NONE
    );
    await ReaderSettingsStore.persistActiveThemeProfile(store, settings);
    await store.flush();
  }

  static async saveLandscapeDoublePage(context: Context, enabled: boolean): Promise<void> {
    const settings = ReaderSettingsStore.cachedSettings || ReaderSettingsStore.fromStorage();
    settings.landscapeDoublePage = enabled;
    ReaderSettingsStore.cachedSettings = ReaderSettingsStore.clone(settings);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_LANDSCAPE_DOUBLE_PAGE, enabled);
    const store = await preferences.getPreferences(context, ReaderSettingsStore.STORE_NAME);
    await store.put(ReaderSettingsStore.KEY_LANDSCAPE_DOUBLE_PAGE, enabled);
    await ReaderSettingsStore.persistActiveThemeProfile(store, settings);
    await store.flush();
  }

  static async saveScreenOrientation(context: Context, orientation: string): Promise<void> {
    const settings = ReaderSettingsStore.cachedSettings || ReaderSettingsStore.fromStorage();
    settings.screenOrientation = ReaderSettingsStore.normalizeScreenOrientation(orientation);
    ReaderSettingsStore.cachedSettings = ReaderSettingsStore.clone(settings);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_SCREEN_ORIENTATION, settings.screenOrientation);
    const store = await preferences.getPreferences(context, ReaderSettingsStore.STORE_NAME);
    await store.put(ReaderSettingsStore.KEY_SCREEN_ORIENTATION, settings.screenOrientation);
    await ReaderSettingsStore.persistActiveThemeProfile(store, settings);
    await store.flush();
  }

  static async saveAll(context: Context, settings: ReaderSettings,
    currentDarkMode: boolean = false): Promise<void> {
    await ReaderSettingsStore.saveLayoutSettings(
      context,
      settings.fontSize,
      settings.lineHeight,
      settings.paragraphSpacing,
      settings.marginLeft,
      settings.marginRight,
      settings.marginTop,
      settings.marginBottom,
      settings.letterSpacing,
      settings.textAlign
    );
    await ReaderSettingsStore.saveThemeSettings(
      context,
      settings.lightThemeIndex,
      settings.darkThemeIndex,
      settings.lightCustomThemeBackgroundColor,
      settings.lightCustomThemeTextColor,
      settings.darkCustomThemeBackgroundColor,
      settings.darkCustomThemeTextColor,
      currentDarkMode,
      settings.customThemesRaw
    );
    await ReaderSettingsStore.savePageTurnMode(context, settings.pageTurnMode);
    await ReaderSettingsStore.savePageTurnAnimationType(context, settings.pageTurnAnimationType);
    await ReaderSettingsStore.saveLandscapeDoublePage(context, settings.landscapeDoublePage);
    await ReaderSettingsStore.saveScreenOrientation(context, settings.screenOrientation);
    await ReaderSettingsStore.saveReadingInteractionSettings(
      context,
      settings.volumeTurnPage,
      settings.screenTimeoutMinutes,
      settings.extendToStatusBar
    );
    await ReaderSettingsStore.saveEyeTurnSettings(
      context,
      settings.eyeTurnEnabled,
      settings.eyeTurnPortraitCalibration,
      settings.eyeTurnLandscapeCalibration,
      settings.eyeTurnPreviousEnabled,
      settings.eyeTurnNextEnabled,
      settings.eyeTurnPreviousDwellMs,
      settings.eyeTurnNextDwellMs
    );
    await ReaderSettingsStore.saveTapZoneActions(context, settings.tapZoneActions);
    await ReaderSettingsStore.savePreloadEnabled(context, settings.preloadEnabled);
    await ReaderSettingsStore.savePreloadChapterCount(context, settings.preloadChapterCount);
    await ReaderSettingsStore.saveQuickBookmarkEnabled(context, settings.quickBookmarkEnabled);
    await ReaderSettingsStore.saveFontSettings(
      context,
      settings.fontFamily,
      settings.fontFilePath,
      settings.fontSourceName,
      settings.fontMode,
      settings.systemFontFamily,
      settings.customFontsRaw
    );
    await ReaderSettingsStore.saveReaderFontStyleSettings(context, settings);
    await ReaderSettingsStore.saveLayoutElementSettings(
      context,
      settings.useTtsQuickAction,
      settings.useChapterQuickJump
    );
    await ReaderSettingsStore.saveReaderChromeSettings(
      context,
      settings.readerHeaderEnabled,
      settings.readerHeaderContentMode,
      settings.readerFooterEnabled,
      settings.readerFooterLeftMode,
      settings.readerFooterProgressMode,
      settings.readerFooterShowProgressBar
    );
    ReaderSettingsStore.applyToStorage(settings);
  }

  static applyToStorage(settings: ReaderSettings): void {
    const normalized = ReaderSettingsStore.clone(settings);
    ReaderSettingsStore.cachedSettings = normalized;
    ReaderSettingsStore.cachedThemeId = ReaderSettingsStore.activeThemeId();
    ReaderSettingsStore.applyLayoutToStorage(normalized);
    ReaderSettingsStore.applyThemeToStorage(normalized);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_PAGE_TURN_MODE, normalized.pageTurnMode);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_PAGE_TURN_ANIMATION_TYPE, normalized.pageTurnAnimationType);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_LANDSCAPE_DOUBLE_PAGE, normalized.landscapeDoublePage);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_SCREEN_ORIENTATION, normalized.screenOrientation);
    AppStorage.setOrCreate(
      ReaderSettingsStore.KEY_PAGE_TURN_ANIMATION,
      normalized.pageTurnAnimationType !== ReaderSettingsStore.PAGE_TURN_ANIMATION_NONE
    );
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_TAP_ZONE_ACTIONS, normalized.tapZoneActions);
    ReaderSettingsStore.applyInteractionToStorage(normalized);
    ReaderSettingsStore.applyEyeTurnToStorage(normalized);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_PRELOAD_ENABLED, normalized.preloadEnabled);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_PRELOAD_CHAPTER_COUNT, normalized.preloadChapterCount);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_USE_TTS_QUICK_ACTION, normalized.useTtsQuickAction);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_USE_CHAPTER_QUICK_JUMP, normalized.useChapterQuickJump);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_QUICK_BOOKMARK_ENABLED, normalized.quickBookmarkEnabled);
    ReaderSettingsStore.applyReaderChromeToStorage(normalized);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_FONT_FAMILY, normalized.fontFamily);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_FONT_FILE_PATH, normalized.fontFilePath);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_FONT_SOURCE_NAME, normalized.fontSourceName);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_FONT_MODE, normalized.fontMode);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_SYSTEM_FONT_FAMILY, normalized.systemFontFamily);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_CUSTOM_FONTS_RAW, normalized.customFontsRaw);
    ReaderSettingsStore.applyReaderFontStyleToStorage(normalized);
  }

  private static applyReaderFontStyleToStorage(settings: ReaderSettings): void {
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_BODY_FONT_MODE, settings.bodyFontMode);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_BODY_FONT_FAMILY, settings.bodyFontFamily);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_TITLE_FONT_MODE, settings.titleFontMode);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_TITLE_FONT_FAMILY, settings.titleFontFamily);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_TITLE_FONT_SIZE, settings.titleFontSize);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_REGEX_FONT_ENABLED, settings.regexFontEnabled);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_REGEX_FONT_PATTERN, settings.regexFontPattern);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_REGEX_FONT_MODE, settings.regexFontMode);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_REGEX_FONT_FAMILY, settings.regexFontFamily);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_REGEX_FONT_SIZE, settings.regexFontSize);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_REGEX_SHADOW_COLOR, settings.regexShadowColor);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_REGEX_FONT_RULES_RAW, settings.regexFontRulesRaw);
  }

  private static applyInteractionToStorage(settings: ReaderSettings): void {
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_VOLUME_TURN_PAGE, settings.volumeTurnPage);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_SCREEN_TIMEOUT_MINUTES, settings.screenTimeoutMinutes);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_KEEP_SCREEN_ON, settings.keepScreenOn);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_EXTEND_TO_STATUS_BAR, settings.extendToStatusBar);
  }

  private static applyReaderChromeToStorage(settings: ReaderSettings): void {
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_HEADER_ENABLED, settings.readerHeaderEnabled);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_HEADER_CONTENT_MODE, settings.readerHeaderContentMode);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_FOOTER_ENABLED, settings.readerFooterEnabled);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_FOOTER_LEFT_MODE, settings.readerFooterLeftMode);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_FOOTER_PROGRESS_MODE, settings.readerFooterProgressMode);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_FOOTER_SHOW_PROGRESS_BAR, settings.readerFooterShowProgressBar);
  }

  private static applyEyeTurnToStorage(settings: ReaderSettings): void {
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_EYE_TURN_ENABLED, settings.eyeTurnEnabled);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_EYE_TURN_PORTRAIT_CALIBRATION,
      settings.eyeTurnPortraitCalibration);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_EYE_TURN_LANDSCAPE_CALIBRATION,
      settings.eyeTurnLandscapeCalibration);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_EYE_TURN_PREVIOUS_ENABLED,
      settings.eyeTurnPreviousEnabled);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_EYE_TURN_NEXT_ENABLED,
      settings.eyeTurnNextEnabled);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_EYE_TURN_PREVIOUS_DWELL_MS,
      settings.eyeTurnPreviousDwellMs);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_EYE_TURN_NEXT_DWELL_MS,
      settings.eyeTurnNextDwellMs);
  }

  private static applyLayoutToStorage(settings: ReaderSettings): void {
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_FONT_SIZE, settings.fontSize);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_LETTER_SPACING, settings.letterSpacing);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_TEXT_ALIGN, settings.textAlign);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_LINE_HEIGHT, settings.lineHeight);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_LINE_HEIGHT_MODE, 'spacing');
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_PARAGRAPH_SPACING, settings.paragraphSpacing);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_MARGIN_LEFT, settings.marginLeft);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_MARGIN_RIGHT, settings.marginRight);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_MARGIN_TOP, settings.marginTop);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_MARGIN_BOTTOM, settings.marginBottom);
  }

  private static applyThemeToStorage(settings: ReaderSettings): void {
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_THEME_INDEX, settings.themeIndex);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_LIGHT_THEME_INDEX, settings.lightThemeIndex);
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_DARK_THEME_INDEX, settings.darkThemeIndex);
    AppStorage.setOrCreate(
      ReaderSettingsStore.KEY_LIGHT_CUSTOM_THEME_BACKGROUND_COLOR,
      settings.lightCustomThemeBackgroundColor
    );
    AppStorage.setOrCreate(
      ReaderSettingsStore.KEY_LIGHT_CUSTOM_THEME_TEXT_COLOR,
      settings.lightCustomThemeTextColor
    );
    AppStorage.setOrCreate(
      ReaderSettingsStore.KEY_DARK_CUSTOM_THEME_BACKGROUND_COLOR,
      settings.darkCustomThemeBackgroundColor
    );
    AppStorage.setOrCreate(
      ReaderSettingsStore.KEY_DARK_CUSTOM_THEME_TEXT_COLOR,
      settings.darkCustomThemeTextColor
    );
    AppStorage.setOrCreate(ReaderSettingsStore.KEY_CUSTOM_THEMES_RAW, settings.customThemesRaw);
  }

  private static activeThemeId(): string {
    return ReaderSettingsStore.normalizeThemeProfileId(
      AppStorage.get<string>('appThemeId') || 'classic-blue'
    );
  }

  private static normalizeThemeProfileId(themeId: string): string {
    const value = (themeId || '').trim().toLowerCase().replace(/[^a-z0-9_-]/g, '');
    return value || 'classic-blue';
  }

  private static themeProfileKey(themeId: string): string {
    return `${ReaderSettingsStore.THEME_PROFILE_PREFIX}${ReaderSettingsStore.normalizeThemeProfileId(themeId)}`;
  }

  private static async loadThemeProfile(store: preferences.Preferences,
    themeId: string): Promise<ReaderSettings | null> {
    const raw = await store.get(ReaderSettingsStore.themeProfileKey(themeId), '');
    if (typeof raw !== 'string' || !raw.trim()) {
      return null;
    }
    try {
      const parsed = JSON.parse(raw) as ReaderSettings;
      return ReaderSettingsStore.clone(parsed);
    } catch (e) {
      console.warn('读取主题阅读设置失败:', e);
      return null;
    }
  }

  private static async persistActiveThemeProfile(store: preferences.Preferences,
    settings: ReaderSettings): Promise<void> {
    await ReaderSettingsStore.persistThemeProfile(store, ReaderSettingsStore.activeThemeId(), settings);
    ReaderSettingsStore.cachedThemeId = ReaderSettingsStore.activeThemeId();
    CloudSyncChangeTracker.markPreferenceChanged();
  }

  private static async persistThemeProfile(store: preferences.Preferences, themeId: string,
    settings: ReaderSettings): Promise<void> {
    await store.put(ReaderSettingsStore.themeProfileKey(themeId), JSON.stringify(ReaderSettingsStore.clone(settings)));
  }

  private static async getNumber(
    store: preferences.Preferences,
    key: string,
    fallback: number,
    type: string,
    fontSize: number = 20,
    lineHeightMode: string = ''
  ): Promise<number> {
    const value = await store.get(key, fallback);
    if (typeof value === 'number') {
      return ReaderSettingsStore.normalizeNumber(value, type, fallback, fontSize, lineHeightMode);
    }
    if (typeof value === 'string') {
      const parsed = Number(value);
      if (!Number.isNaN(parsed)) {
        return ReaderSettingsStore.normalizeNumber(parsed, type, fallback, fontSize, lineHeightMode);
      }
    }
    return fallback;
  }

  private static async getBoolean(
    store: preferences.Preferences,
    key: string,
    fallback: boolean
  ): Promise<boolean> {
    const value = await store.get(key, fallback);
    if (typeof value === 'boolean') {
      return value;
    }
    if (typeof value === 'number') {
      return value !== 0;
    }
    if (typeof value === 'string') {
      return value === 'true' || value === '1';
    }
    return fallback;
  }

  private static async getString(
    store: preferences.Preferences,
    key: string,
    fallback: string
  ): Promise<string> {
    const value = await store.get(key, fallback);
    if (typeof value === 'string') {
      return value;
    }
    if (typeof value === 'number' || typeof value === 'boolean') {
      return String(value);
    }
    return fallback;
  }

  private static normalizeNumber(
    value: number,
    type: string,
    fallback: number,
    fontSize: number = 20,
    lineHeightMode: string = ''
  ): number {
    if (type === 'fontSize') {
      return ReaderSettingsStore.normalizeFontSize(value);
    }
    if (type === 'letterSpacing') {
      return ReaderSettingsStore.normalizeLetterSpacing(value);
    }
    if (type === 'lineHeight') {
      return ReaderSettingsStore.normalizeLineHeight(value);
    }
    if (type === 'legacyLineHeight') {
      return lineHeightMode === 'spacing' ?
        ReaderSettingsStore.normalizeLineHeight(value) :
        ReaderSettingsStore.normalizeLegacyLineHeight(value, fontSize);
    }
    if (type === 'paragraphSpacing') {
      return ReaderSettingsStore.normalizeParagraphSpacing(value);
    }
    if (type === 'horizontalMargin') {
      return ReaderSettingsStore.normalizeHorizontalMargin(value);
    }
    if (type === 'verticalMargin') {
      return ReaderSettingsStore.normalizeVerticalMargin(value);
    }
    if (type === 'themeIndex') {
      return ReaderSettingsStore.normalizeThemeIndex(value);
    }
    if (type === 'pageTurnMode') {
      return ReaderSettingsStore.normalizePageTurnMode(value);
    }
    if (type === 'pageTurnAnimationType') {
      return ReaderSettingsStore.normalizePageTurnAnimationType(value);
    }
    if (type === 'preloadChapterCount') {
      return ReaderSettingsStore.normalizePreloadChapterCount(value);
    }
    if (type === 'screenTimeoutMinutes') {
      return ReaderSettingsStore.normalizeScreenTimeoutMinutes(value);
    }
    if (type === 'eyeTurnDwell') {
      return ReaderSettingsStore.normalizeEyeTurnDwell(value);
    }
    return fallback;
  }

  private static normalizeEyeTurnDwell(value: number): number {
    return Math.max(400, Math.min(Math.round(value), 2000));
  }

  private static normalizeFontSize(fontSize: number): number {
    const value = Math.round(fontSize);
    return Math.max(14, Math.min(value, 50));
  }

  private static normalizeLineHeight(lineHeight: number): number {
    const value = Math.round(lineHeight);
    return Math.max(0, Math.min(value, 52));
  }

  private static normalizeLegacyLineHeight(lineHeight: number, fontSize: number): number {
    const value = Math.round(lineHeight);
    if (value >= 24) {
      return ReaderSettingsStore.normalizeLineHeight(value - ReaderSettingsStore.normalizeFontSize(fontSize));
    }
    return ReaderSettingsStore.normalizeLineHeight(value);
  }

  private static normalizeParagraphSpacing(paragraphSpacing: number): number {
    const value = Math.round(paragraphSpacing);
    return Math.max(0, Math.min(value, 32));
  }

  private static normalizeThemeIndex(themeIndex: number): number {
    return ReaderThemeHelper.normalizeIndex(themeIndex);
  }

  private static normalizeHorizontalMargin(margin: number): number {
    const value = Math.round(margin);
    return Math.max(0, Math.min(value, 80));
  }

  private static normalizeVerticalMargin(margin: number): number {
    const value = Math.round(margin);
    return Math.max(0, Math.min(value, 120));
  }

  private static normalizeColor(color: string, fallback: string): string {
    const trimmed = (color || '').trim();
    const normalized = trimmed.startsWith('#') ? trimmed : `#${trimmed}`;
    if (/^#[0-9a-fA-F]{6}$/.test(normalized)) {
      return normalized.toUpperCase();
    }
    const fallbackTrimmed = (fallback || '').trim();
    const normalizedFallback = fallbackTrimmed.startsWith('#') ? fallbackTrimmed : `#${fallbackTrimmed}`;
    return /^#[0-9a-fA-F]{6}$/.test(normalizedFallback) ? normalizedFallback.toUpperCase() : '#333333';
  }

  private static normalizePageTurnMode(mode: number): number {
    const value = Math.round(mode);
    return value === 0 || value === 2 || value === 3 ? value : 2;
  }

  private static normalizePageTurnAnimationType(type: number): number {
    const value = Math.round(type);
    if (value === ReaderSettingsStore.PAGE_TURN_ANIMATION_NONE ||
      value === ReaderSettingsStore.PAGE_TURN_ANIMATION_SLIDE ||
      value === ReaderSettingsStore.PAGE_TURN_ANIMATION_FADE ||
      value === ReaderSettingsStore.PAGE_TURN_ANIMATION_STACK ||
      value === ReaderSettingsStore.PAGE_TURN_ANIMATION_SIMULATION ||
      value === ReaderSettingsStore.PAGE_TURN_ANIMATION_3D) {
      return value;
    }
    return ReaderSettingsStore.PAGE_TURN_ANIMATION_SLIDE;
  }

  private static normalizePageTurnAnimationForMode(mode: number, type: number): number {
    const value = ReaderSettingsStore.normalizePageTurnAnimationType(type);
    // 仿真与 3D 仿真依赖横向页面的左右翻转，上下滑动模式下没有对应运动轨迹，统一降级为叠页。
    if (ReaderSettingsStore.normalizePageTurnMode(mode) === 0 &&
      (value === ReaderSettingsStore.PAGE_TURN_ANIMATION_SIMULATION ||
        value === ReaderSettingsStore.PAGE_TURN_ANIMATION_3D)) {
      return ReaderSettingsStore.PAGE_TURN_ANIMATION_STACK;
    }
    return value;
  }

  private static normalizePreloadChapterCount(count: number): number {
    const value = Math.round(count);
    return Math.max(1, Math.min(value, 10));
  }

  static normalizeScreenTimeoutMinutes(minutes: number): number {
    const value = Math.round(minutes);
    if (value === ReaderSettingsStore.SCREEN_TIMEOUT_ALWAYS_ON ||
      value === ReaderSettingsStore.SCREEN_TIMEOUT_FOLLOW_SYSTEM ||
      value === 1 || value === 5 || value === 10) {
      return value;
    }
    return ReaderSettingsStore.SCREEN_TIMEOUT_FOLLOW_SYSTEM;
  }

  static normalizeScreenOrientation(orientation: string): string {
    const value = (orientation || '').trim().toLowerCase();
    if (value === ReaderSettingsStore.SCREEN_ORIENTATION_PORTRAIT ||
      value === ReaderSettingsStore.SCREEN_ORIENTATION_LANDSCAPE) {
      return value;
    }
    return ReaderSettingsStore.SCREEN_ORIENTATION_SYSTEM;
  }

  private static normalizeTapZoneActions(actions: string): string {
    const fallback = [3, 3, 3, 3, 1, 2, 2, 2, 2];
    const parts = (actions || '').split(',');
    const result: number[] = [];
    for (let i = 0; i < 9; i++) {
      const parsed = Number(parts[i]);
      result.push(Number.isFinite(parsed) && parsed >= 0 && parsed <= 3 ? Math.round(parsed) : fallback[i]);
    }
    return result.join(',');
  }

  private static normalizeLetterSpacing(letterSpacing: number): number {
    const value = typeof letterSpacing === 'number' && Number.isFinite(letterSpacing) ?
      Math.round(letterSpacing) : 0;
    return Math.max(0, Math.min(value, 8));
  }

  private static normalizeTextAlign(textAlign: string): string {
    const value = (textAlign || '').trim().toLowerCase();
    return value === 'start' || value === 'end' || value === 'justify' ? value : 'justify';
  }

  private static normalizeHeaderContentMode(mode: string): string {
    const value = (mode || '').trim().toLowerCase();
    return value === 'book' || value === 'book_chapter' || value === 'none' ? value : 'chapter';
  }

  private static normalizeFooterLeftMode(mode: string): string {
    const value = (mode || '').trim().toLowerCase();
    return value === 'none' || value === 'title' ? value : 'chapter';
  }

  private static normalizeFooterProgressMode(mode: string): string {
    const value = (mode || '').trim().toLowerCase();
    return value === 'percentage' || value === 'chapter' || value === 'book' || value === 'none' ? value : 'page';
  }

  private static normalizeFontMode(mode: string): string {
    if (mode === 'system' || mode === 'custom') {
      return mode;
    }
    return 'global';
  }

  private static clone(source: ReaderSettings): ReaderSettings {
    const settings = new ReaderSettings();
    settings.fontSize = ReaderSettingsStore.normalizeFontSize(source.fontSize);
    settings.letterSpacing = ReaderSettingsStore.normalizeLetterSpacing(source.letterSpacing);
    settings.textAlign = ReaderSettingsStore.normalizeTextAlign(source.textAlign);
    settings.lineHeight = ReaderSettingsStore.normalizeLineHeight(source.lineHeight);
    settings.paragraphSpacing = ReaderSettingsStore.normalizeParagraphSpacing(source.paragraphSpacing);
    settings.marginLeft = ReaderSettingsStore.normalizeHorizontalMargin(source.marginLeft);
    settings.marginRight = ReaderSettingsStore.normalizeHorizontalMargin(source.marginRight);
    settings.marginTop = ReaderSettingsStore.normalizeVerticalMargin(source.marginTop);
    settings.marginBottom = ReaderSettingsStore.normalizeVerticalMargin(source.marginBottom);
    settings.themeIndex = ReaderSettingsStore.normalizeThemeIndex(source.themeIndex);
    settings.lightThemeIndex = ReaderSettingsStore.normalizeThemeIndex(source.lightThemeIndex);
    settings.darkThemeIndex = ReaderSettingsStore.normalizeThemeIndex(source.darkThemeIndex);
    settings.lightCustomThemeBackgroundColor = ReaderSettingsStore.normalizeColor(
      source.lightCustomThemeBackgroundColor,
      ReaderThemeHelper.LIGHT_CUSTOM_BACKGROUND_COLOR
    );
    settings.lightCustomThemeTextColor = ReaderSettingsStore.normalizeColor(
      source.lightCustomThemeTextColor,
      ReaderThemeHelper.LIGHT_CUSTOM_TEXT_COLOR
    );
    settings.darkCustomThemeBackgroundColor = ReaderSettingsStore.normalizeColor(
      source.darkCustomThemeBackgroundColor,
      ReaderThemeHelper.DARK_CUSTOM_BACKGROUND_COLOR
    );
    settings.darkCustomThemeTextColor = ReaderSettingsStore.normalizeColor(
      source.darkCustomThemeTextColor,
      ReaderThemeHelper.DARK_CUSTOM_TEXT_COLOR
    );
    settings.customThemesRaw = source.customThemesRaw || '';
    settings.pageTurnMode = ReaderSettingsStore.normalizePageTurnMode(source.pageTurnMode);
    settings.pageTurnAnimationType = ReaderSettingsStore.normalizePageTurnAnimationForMode(
      settings.pageTurnMode, source.pageTurnAnimationType);
    settings.landscapeDoublePage = source.landscapeDoublePage;
    settings.screenOrientation = ReaderSettingsStore.normalizeScreenOrientation(source.screenOrientation);
    settings.tapZoneActions = ReaderSettingsStore.normalizeTapZoneActions(source.tapZoneActions);
    settings.volumeTurnPage = source.volumeTurnPage;
    settings.eyeTurnEnabled = source.eyeTurnEnabled === true;
    settings.eyeTurnPortraitCalibration = source.eyeTurnPortraitCalibration || '';
    settings.eyeTurnLandscapeCalibration = source.eyeTurnLandscapeCalibration || '';
    settings.eyeTurnPreviousEnabled = source.eyeTurnPreviousEnabled === true;
    settings.eyeTurnNextEnabled = source.eyeTurnNextEnabled !== false;
    settings.eyeTurnPreviousDwellMs = ReaderSettingsStore.normalizeEyeTurnDwell(
      typeof source.eyeTurnPreviousDwellMs === 'number' ? source.eyeTurnPreviousDwellMs : 850);
    settings.eyeTurnNextDwellMs = ReaderSettingsStore.normalizeEyeTurnDwell(
      typeof source.eyeTurnNextDwellMs === 'number' ? source.eyeTurnNextDwellMs : 650);
    settings.screenTimeoutMinutes = ReaderSettingsStore.normalizeScreenTimeoutMinutes(
      typeof source.screenTimeoutMinutes === 'number' ?
        source.screenTimeoutMinutes :
        (source.keepScreenOn === false ?
          ReaderSettingsStore.SCREEN_TIMEOUT_FOLLOW_SYSTEM :
          ReaderSettingsStore.SCREEN_TIMEOUT_ALWAYS_ON)
    );
    settings.keepScreenOn =
      settings.screenTimeoutMinutes !== ReaderSettingsStore.SCREEN_TIMEOUT_FOLLOW_SYSTEM;
    settings.extendToStatusBar = source.extendToStatusBar;
    settings.preloadEnabled = source.preloadEnabled;
    settings.preloadChapterCount = ReaderSettingsStore.normalizePreloadChapterCount(source.preloadChapterCount);
    settings.useTtsQuickAction = typeof source.useTtsQuickAction === 'boolean' ? source.useTtsQuickAction :
      (AppStorage.get<boolean>(ReaderSettingsStore.KEY_USE_TTS_QUICK_ACTION) ?? true);
    settings.useChapterQuickJump = typeof source.useChapterQuickJump === 'boolean' ? source.useChapterQuickJump :
      (AppStorage.get<boolean>(ReaderSettingsStore.KEY_USE_CHAPTER_QUICK_JUMP) ?? true);
    settings.quickBookmarkEnabled = typeof source.quickBookmarkEnabled === 'boolean' ? source.quickBookmarkEnabled :
      (AppStorage.get<boolean>(ReaderSettingsStore.KEY_QUICK_BOOKMARK_ENABLED) ?? true);
    settings.readerHeaderEnabled = source.readerHeaderEnabled === true;
    settings.readerHeaderContentMode = ReaderSettingsStore.normalizeHeaderContentMode(source.readerHeaderContentMode);
    settings.readerFooterEnabled = source.readerFooterEnabled !== false;
    settings.readerFooterLeftMode = ReaderSettingsStore.normalizeFooterLeftMode(source.readerFooterLeftMode);
    settings.readerFooterProgressMode = ReaderSettingsStore.normalizeFooterProgressMode(source.readerFooterProgressMode);
    settings.readerFooterShowProgressBar = source.readerFooterShowProgressBar === true;
    settings.fontFamily = source.fontFamily || '';
    settings.fontFilePath = source.fontFilePath || '';
    settings.fontSourceName = source.fontSourceName || '系统默认';
    settings.fontMode = source.fontMode || 'system';
    settings.systemFontFamily = source.systemFontFamily || '';
    settings.customFontsRaw = source.customFontsRaw || '';
    settings.bodyFontMode = ReaderSettingsStore.normalizeFontMode(source.bodyFontMode);
    settings.bodyFontFamily = source.bodyFontFamily || '';
    settings.titleFontMode = ReaderSettingsStore.normalizeFontMode(source.titleFontMode);
    settings.titleFontFamily = source.titleFontFamily || '';
    settings.titleFontSize = ReaderSettingsStore.normalizeFontSize(source.titleFontSize || 22);
    settings.regexFontEnabled = source.regexFontEnabled;
    settings.regexFontPattern = source.regexFontPattern || '';
    settings.regexFontMode = ReaderSettingsStore.normalizeFontMode(source.regexFontMode);
    settings.regexFontFamily = source.regexFontFamily || '';
    settings.regexFontSize = ReaderSettingsStore.normalizeFontSize(source.regexFontSize || 20);
    settings.regexShadowColor = source.regexShadowColor || '';
    settings.regexFontRulesRaw = source.regexFontRulesRaw || '';
    return settings;
  }

  private static fromStorage(): ReaderSettings {
    const settings = new ReaderSettings();
    settings.fontSize = ReaderSettingsStore.normalizeFontSize(
      AppStorage.get<number>(ReaderSettingsStore.KEY_FONT_SIZE) ?? 20
    );
    settings.letterSpacing = ReaderSettingsStore.normalizeLetterSpacing(
      AppStorage.get<number>(ReaderSettingsStore.KEY_LETTER_SPACING) ?? 0);
    settings.textAlign = ReaderSettingsStore.normalizeTextAlign(
      AppStorage.get<string>(ReaderSettingsStore.KEY_TEXT_ALIGN) || 'justify');
    const storageLineHeight = AppStorage.get<number>(ReaderSettingsStore.KEY_LINE_HEIGHT) ?? 32;
    settings.lineHeight = AppStorage.get<string>(ReaderSettingsStore.KEY_LINE_HEIGHT_MODE) === 'spacing' ?
      ReaderSettingsStore.normalizeLineHeight(storageLineHeight) :
      ReaderSettingsStore.normalizeLegacyLineHeight(storageLineHeight, settings.fontSize);
    settings.paragraphSpacing = ReaderSettingsStore.normalizeParagraphSpacing(
      AppStorage.get<number>(ReaderSettingsStore.KEY_PARAGRAPH_SPACING) ?? 0
    );
    settings.marginLeft = ReaderSettingsStore.normalizeHorizontalMargin(
      AppStorage.get<number>(ReaderSettingsStore.KEY_MARGIN_LEFT) ?? 18);
    settings.marginRight = ReaderSettingsStore.normalizeHorizontalMargin(
      AppStorage.get<number>(ReaderSettingsStore.KEY_MARGIN_RIGHT) ?? 18);
    settings.marginTop = ReaderSettingsStore.normalizeVerticalMargin(
      AppStorage.get<number>(ReaderSettingsStore.KEY_MARGIN_TOP) ?? 18);
    settings.marginBottom = ReaderSettingsStore.normalizeVerticalMargin(
      AppStorage.get<number>(ReaderSettingsStore.KEY_MARGIN_BOTTOM) ?? 18);
    const legacyThemeIndex = ReaderSettingsStore.normalizeThemeIndex(
      AppStorage.get<number>(ReaderSettingsStore.KEY_THEME_INDEX) ?? 0
    );
    settings.themeIndex = legacyThemeIndex;
    settings.lightThemeIndex = ReaderSettingsStore.normalizeThemeIndex(
      AppStorage.get<number>(ReaderSettingsStore.KEY_LIGHT_THEME_INDEX) ?? legacyThemeIndex
    );
    settings.darkThemeIndex = ReaderSettingsStore.normalizeThemeIndex(
      AppStorage.get<number>(ReaderSettingsStore.KEY_DARK_THEME_INDEX) ?? legacyThemeIndex
    );
    settings.lightCustomThemeBackgroundColor = ReaderSettingsStore.normalizeColor(
      AppStorage.get<string>(ReaderSettingsStore.KEY_LIGHT_CUSTOM_THEME_BACKGROUND_COLOR) || '',
      ReaderThemeHelper.LIGHT_CUSTOM_BACKGROUND_COLOR
    );
    settings.lightCustomThemeTextColor = ReaderSettingsStore.normalizeColor(
      AppStorage.get<string>(ReaderSettingsStore.KEY_LIGHT_CUSTOM_THEME_TEXT_COLOR) || '',
      ReaderThemeHelper.LIGHT_CUSTOM_TEXT_COLOR
    );
    settings.darkCustomThemeBackgroundColor = ReaderSettingsStore.normalizeColor(
      AppStorage.get<string>(ReaderSettingsStore.KEY_DARK_CUSTOM_THEME_BACKGROUND_COLOR) || '',
      ReaderThemeHelper.DARK_CUSTOM_BACKGROUND_COLOR
    );
    settings.darkCustomThemeTextColor = ReaderSettingsStore.normalizeColor(
      AppStorage.get<string>(ReaderSettingsStore.KEY_DARK_CUSTOM_THEME_TEXT_COLOR) || '',
      ReaderThemeHelper.DARK_CUSTOM_TEXT_COLOR
    );
    settings.customThemesRaw = AppStorage.get<string>(ReaderSettingsStore.KEY_CUSTOM_THEMES_RAW) || '';
    settings.pageTurnMode = ReaderSettingsStore.normalizePageTurnMode(
      AppStorage.get<number>(ReaderSettingsStore.KEY_PAGE_TURN_MODE) ?? 2
    );
    const legacyPageTurnAnimation = AppStorage.get<boolean>(ReaderSettingsStore.KEY_PAGE_TURN_ANIMATION) ?? true;
    const storagePageTurnAnimationType = ReaderSettingsStore.normalizePageTurnAnimationType(
      AppStorage.get<number>(ReaderSettingsStore.KEY_PAGE_TURN_ANIMATION_TYPE) ??
        (legacyPageTurnAnimation ?
          ReaderSettingsStore.PAGE_TURN_ANIMATION_SLIDE :
          ReaderSettingsStore.PAGE_TURN_ANIMATION_NONE)
    );
    settings.pageTurnAnimationType = legacyPageTurnAnimation ?
      storagePageTurnAnimationType :
      ReaderSettingsStore.PAGE_TURN_ANIMATION_NONE;
    settings.pageTurnAnimationType = ReaderSettingsStore.normalizePageTurnAnimationForMode(
      settings.pageTurnMode, settings.pageTurnAnimationType);
    settings.landscapeDoublePage = AppStorage.get<boolean>(ReaderSettingsStore.KEY_LANDSCAPE_DOUBLE_PAGE) ?? false;
    settings.screenOrientation = ReaderSettingsStore.normalizeScreenOrientation(
      AppStorage.get<string>(ReaderSettingsStore.KEY_SCREEN_ORIENTATION) ||
        ReaderSettingsStore.SCREEN_ORIENTATION_SYSTEM);
    settings.tapZoneActions = ReaderSettingsStore.normalizeTapZoneActions(
      AppStorage.get<string>(ReaderSettingsStore.KEY_TAP_ZONE_ACTIONS) || ''
    );
    settings.volumeTurnPage = AppStorage.get<boolean>(ReaderSettingsStore.KEY_VOLUME_TURN_PAGE) ?? false;
    settings.eyeTurnEnabled = AppStorage.get<boolean>(ReaderSettingsStore.KEY_EYE_TURN_ENABLED) ?? false;
    settings.eyeTurnPortraitCalibration =
      AppStorage.get<string>(ReaderSettingsStore.KEY_EYE_TURN_PORTRAIT_CALIBRATION) || '';
    settings.eyeTurnLandscapeCalibration =
      AppStorage.get<string>(ReaderSettingsStore.KEY_EYE_TURN_LANDSCAPE_CALIBRATION) || '';
    settings.eyeTurnPreviousEnabled = AppStorage.get<boolean>(
      ReaderSettingsStore.KEY_EYE_TURN_PREVIOUS_ENABLED) ?? false;
    settings.eyeTurnNextEnabled = AppStorage.get<boolean>(
      ReaderSettingsStore.KEY_EYE_TURN_NEXT_ENABLED) ?? true;
    settings.eyeTurnPreviousDwellMs = ReaderSettingsStore.normalizeEyeTurnDwell(
      AppStorage.get<number>(ReaderSettingsStore.KEY_EYE_TURN_PREVIOUS_DWELL_MS) ?? 850);
    settings.eyeTurnNextDwellMs = ReaderSettingsStore.normalizeEyeTurnDwell(
      AppStorage.get<number>(ReaderSettingsStore.KEY_EYE_TURN_NEXT_DWELL_MS) ?? 650);
    const legacyKeepScreenOn = AppStorage.get<boolean>(ReaderSettingsStore.KEY_KEEP_SCREEN_ON) ?? true;
    settings.screenTimeoutMinutes = ReaderSettingsStore.normalizeScreenTimeoutMinutes(
      AppStorage.get<number>(ReaderSettingsStore.KEY_SCREEN_TIMEOUT_MINUTES) ??
        (legacyKeepScreenOn ?
          ReaderSettingsStore.SCREEN_TIMEOUT_ALWAYS_ON :
          ReaderSettingsStore.SCREEN_TIMEOUT_FOLLOW_SYSTEM)
    );
    settings.keepScreenOn =
      settings.screenTimeoutMinutes !== ReaderSettingsStore.SCREEN_TIMEOUT_FOLLOW_SYSTEM;
    settings.extendToStatusBar = AppStorage.get<boolean>(ReaderSettingsStore.KEY_EXTEND_TO_STATUS_BAR) ?? false;
    settings.preloadEnabled = AppStorage.get<boolean>(ReaderSettingsStore.KEY_PRELOAD_ENABLED) ?? true;
    settings.preloadChapterCount = ReaderSettingsStore.normalizePreloadChapterCount(
      AppStorage.get<number>(ReaderSettingsStore.KEY_PRELOAD_CHAPTER_COUNT) ?? 1
    );
    settings.useTtsQuickAction = AppStorage.get<boolean>(ReaderSettingsStore.KEY_USE_TTS_QUICK_ACTION) ?? true;
    settings.useChapterQuickJump = AppStorage.get<boolean>(ReaderSettingsStore.KEY_USE_CHAPTER_QUICK_JUMP) ?? true;
    settings.quickBookmarkEnabled = AppStorage.get<boolean>(ReaderSettingsStore.KEY_QUICK_BOOKMARK_ENABLED) ?? true;
    settings.readerHeaderEnabled = AppStorage.get<boolean>(ReaderSettingsStore.KEY_HEADER_ENABLED) ?? false;
    settings.readerHeaderContentMode = ReaderSettingsStore.normalizeHeaderContentMode(
      AppStorage.get<string>(ReaderSettingsStore.KEY_HEADER_CONTENT_MODE) || 'chapter');
    settings.readerFooterEnabled = AppStorage.get<boolean>(ReaderSettingsStore.KEY_FOOTER_ENABLED) ?? true;
    settings.readerFooterLeftMode = ReaderSettingsStore.normalizeFooterLeftMode(
      AppStorage.get<string>(ReaderSettingsStore.KEY_FOOTER_LEFT_MODE) || 'chapter');
    settings.readerFooterProgressMode = ReaderSettingsStore.normalizeFooterProgressMode(
      AppStorage.get<string>(ReaderSettingsStore.KEY_FOOTER_PROGRESS_MODE) || 'page');
    settings.readerFooterShowProgressBar = AppStorage.get<boolean>(ReaderSettingsStore.KEY_FOOTER_SHOW_PROGRESS_BAR) ?? false;
    settings.fontFamily = AppStorage.get<string>(ReaderSettingsStore.KEY_FONT_FAMILY) || '';
    settings.fontFilePath = AppStorage.get<string>(ReaderSettingsStore.KEY_FONT_FILE_PATH) || '';
    settings.fontSourceName = AppStorage.get<string>(ReaderSettingsStore.KEY_FONT_SOURCE_NAME) || '系统默认';
    settings.fontMode = AppStorage.get<string>(ReaderSettingsStore.KEY_FONT_MODE) || 'system';
    settings.systemFontFamily = AppStorage.get<string>(ReaderSettingsStore.KEY_SYSTEM_FONT_FAMILY) || '';
    settings.customFontsRaw = AppStorage.get<string>(ReaderSettingsStore.KEY_CUSTOM_FONTS_RAW) || '';
    settings.bodyFontMode = ReaderSettingsStore.normalizeFontMode(AppStorage.get<string>(ReaderSettingsStore.KEY_BODY_FONT_MODE) || 'global');
    settings.bodyFontFamily = AppStorage.get<string>(ReaderSettingsStore.KEY_BODY_FONT_FAMILY) || '';
    settings.titleFontMode = ReaderSettingsStore.normalizeFontMode(AppStorage.get<string>(ReaderSettingsStore.KEY_TITLE_FONT_MODE) || 'global');
    settings.titleFontFamily = AppStorage.get<string>(ReaderSettingsStore.KEY_TITLE_FONT_FAMILY) || '';
    settings.titleFontSize = ReaderSettingsStore.normalizeFontSize(AppStorage.get<number>(ReaderSettingsStore.KEY_TITLE_FONT_SIZE) ?? 22);
    settings.regexFontEnabled = AppStorage.get<boolean>(ReaderSettingsStore.KEY_REGEX_FONT_ENABLED) ?? false;
    settings.regexFontPattern = AppStorage.get<string>(ReaderSettingsStore.KEY_REGEX_FONT_PATTERN) || '';
    settings.regexFontMode = ReaderSettingsStore.normalizeFontMode(AppStorage.get<string>(ReaderSettingsStore.KEY_REGEX_FONT_MODE) || 'global');
    settings.regexFontFamily = AppStorage.get<string>(ReaderSettingsStore.KEY_REGEX_FONT_FAMILY) || '';
    settings.regexFontSize = ReaderSettingsStore.normalizeFontSize(AppStorage.get<number>(ReaderSettingsStore.KEY_REGEX_FONT_SIZE) ?? 20);
    settings.regexShadowColor = AppStorage.get<string>(ReaderSettingsStore.KEY_REGEX_SHADOW_COLOR) || '';
    settings.regexFontRulesRaw = AppStorage.get<string>(ReaderSettingsStore.KEY_REGEX_FONT_RULES_RAW) || '';
    return settings;
  }

  private static mergeStorageFontSettings(settings: ReaderSettings): void {
    const storageFontFilePath = AppStorage.get<string>(ReaderSettingsStore.KEY_FONT_FILE_PATH) || '';
    const storageCustomFontsRaw = AppStorage.get<string>(ReaderSettingsStore.KEY_CUSTOM_FONTS_RAW) || '';
    if (!settings.fontFilePath && storageFontFilePath) {
      settings.fontFamily = AppStorage.get<string>(ReaderSettingsStore.KEY_FONT_FAMILY) || '';
      settings.fontFilePath = storageFontFilePath;
      settings.fontSourceName = AppStorage.get<string>(ReaderSettingsStore.KEY_FONT_SOURCE_NAME) || '系统默认';
      settings.fontMode = AppStorage.get<string>(ReaderSettingsStore.KEY_FONT_MODE) || 'custom';
      settings.systemFontFamily = AppStorage.get<string>(ReaderSettingsStore.KEY_SYSTEM_FONT_FAMILY) || '';
    }
    if (!settings.customFontsRaw && storageCustomFontsRaw) {
      settings.customFontsRaw = storageCustomFontsRaw;
    }
  }
}
