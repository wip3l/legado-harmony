import { AbilityConstant, UIAbility, Want, Configuration, ConfigurationConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { RecentReadShortcut, RECENT_READ_SHORTCUT_ACTION, OPEN_BOOK_SHORTCUT_ACTION } from '../utils/RecentReadShortcut';
import { CoverGalleryStore } from '../utils/CoverGalleryStore';
import { BookshelfDisplaySettingsStore } from '../utils/BookshelfDisplaySettingsStore';
import { SearchExploreSettingsStore } from '../utils/SearchExploreSettingsStore';
import { ReaderSettingsStore } from '../utils/ReaderSettingsStore';
import { AppThemeSettingsStore } from '../utils/AppThemeSettingsStore';
import { GlassSettingsStore } from '../utils/GlassSettingsStore';
import { AppThemeModeStore } from '../utils/AppThemeModeStore';
import { AppIconSettingsStore } from '../utils/AppIconSettingsStore';
import { ReaderFontBootstrap } from '../utils/ReaderFontBootstrap';
import { ReaderSystemFontHelper } from '../utils/ReaderSystemFontHelper';
import { TtsSettingsStore } from '../utils/TtsSettingsStore';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import fs from '@ohos.file.fs';
import { util } from '@kit.ArkTS';

export default class EntryAbility extends UIAbility {
  private appliedColorMode: number = -1;
  private themeBootstrapPromise: Promise<void> = Promise.resolve();
  private mainWindowStage: window.WindowStage | null = null;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onCreate');
    AppStorage.setOrCreate('startupT0', Date.now());
    AppStorage.setOrCreate('appCacheDir', this.context.cacheDir);
    AppStorage.setOrCreate('appFilesDir', this.context.filesDir);
    AppStorage.setOrCreate('pendingBookSourceImportUri', '');
    AppStorage.setOrCreate('pendingBookSourceImportNonce', 0);
    AppStorage.setOrCreate('pendingLocalBookImportUri', '');
    AppStorage.setOrCreate('pendingLocalBookImportNonce', 0);
    AppStorage.setOrCreate('pendingLocalBookImportFormat', '');
    AppStorage.setOrCreate('pendingLocalBookImportName', '');
    hilog.info(0x0000, 'testTag', 'StartupTrace onCreate %{public}d', Date.now());
    PersistentStorage.persistProp('appThemeMode', 'system');
    AppThemeModeStore.load(this.context).then((mode: string) => {
      AppThemeModeStore.applyToStorage(mode);
      this.applyThemeColorMode(mode, this.context.config);
    }).catch((e: Error) => {
      hilog.warn(0x0000, 'testTag', 'Sync app theme mode failed: %{public}s', JSON.stringify(e));
      this.syncSystemColorMode(this.context.config);
    });
    AppStorage.setOrCreate('readerSystemFontFamily', ReaderSystemFontHelper.FALLBACK_SYSTEM_FONT_FAMILY);
    AppStorage.setOrCreate('readerActiveFontFamily', '');
    AppStorage.setOrCreate('readerFontRegistered', false);
    PersistentStorage.persistProp('readerPageTurnMode', 1);
    PersistentStorage.persistProp('readerPreloadEnabled', true);
    PersistentStorage.persistProp('readerPreloadChapterCount', 1);
    PersistentStorage.persistProp('fullTextCacheCancelNonce', 0);
    PersistentStorage.persistProp('fullTextCacheCancelSignal', '');
    PersistentStorage.persistProp('readerBodyFontMode', 'global');
    PersistentStorage.persistProp('readerBodyFontFamily', '');
    PersistentStorage.persistProp('readerTitleFontMode', 'global');
    PersistentStorage.persistProp('readerTitleFontFamily', '');
    PersistentStorage.persistProp('readerTitleFontSize', 22);
    PersistentStorage.persistProp('readerRegexFontEnabled', false);
    PersistentStorage.persistProp('readerRegexFontPattern', '');
    PersistentStorage.persistProp('readerRegexFontMode', 'global');
    PersistentStorage.persistProp('readerRegexFontFamily', '');
    PersistentStorage.persistProp('readerRegexFontSize', 20);
    PersistentStorage.persistProp('readerRegexShadowColor', '');
    PersistentStorage.persistProp('readerRegexFontRulesRaw', '');
    if (AppStorage.get<number>('statusBarHeight') === undefined) {
      AppStorage.setOrCreate('statusBarHeight', 32);
    }
    if (AppStorage.get<number>('navBarHeight') === undefined) {
      AppStorage.setOrCreate('navBarHeight', 0);
    }
    PersistentStorage.persistProp('bookshelfSortMode', 'recentRead');
    PersistentStorage.persistProp('ttsPerson', 0);
    PersistentStorage.persistProp('ttsOnline', 1);
    PersistentStorage.persistProp('ttsStyle', '');
    PersistentStorage.persistProp('ttsLanguage', 'zh-CN');
    PersistentStorage.persistProp('ttsSpeed', 1);
    PersistentStorage.persistProp('ttsInstalledVoiceKeys', '');
    PersistentStorage.persistProp('ttsCustomVoiceId', '');
    PersistentStorage.persistProp('ttsCustomVoices', '');
    PersistentStorage.persistProp('ttsOfflineSdkModeMigrated', false);
    if (!AppStorage.get<boolean>('ttsOfflineSdkModeMigrated')) {
      if (AppStorage.get<number>('ttsOnline') === 0 &&
        (AppStorage.get<number>('ttsPerson') ?? 0) === 0 &&
        !(AppStorage.get<string>('ttsStyle') || '') &&
        ((AppStorage.get<string>('ttsLanguage') || 'zh-CN') === 'zh-CN')) {
        AppStorage.setOrCreate('ttsOnline', 1);
      }
      AppStorage.setOrCreate('ttsOfflineSdkModeMigrated', true);
    }
    PersistentStorage.persistProp('readerPageTurnAnimation', true);
    PersistentStorage.persistProp('readerPageTurnAnimationType', 1);
    PersistentStorage.persistProp('readerVolumeTurnPage', false);
    PersistentStorage.persistProp('readerKeepScreenOn', true);
    PersistentStorage.persistProp('readerExtendToStatusBar', false);
    PersistentStorage.persistProp('bookshelfShowTags', true);
    PersistentStorage.persistProp('bookshelfShowSource', true);
    PersistentStorage.persistProp('bookshelfShowIntro', true);
    PersistentStorage.persistProp('bookshelfShowFullIntro', false);
    PersistentStorage.persistProp('bookshelfShowProgressBar', false);
    PersistentStorage.persistProp('bookshelfShowLastReadTime', true);
    PersistentStorage.persistProp('bookshelfShowLastReadChapter', false);
    PersistentStorage.persistProp('bookshelfLayoutMode', 'compact');
    PersistentStorage.persistProp('bookshelfCoverAlbums', '');
    PersistentStorage.persistProp('bookshelfLightCoverAlbumId', '');
    PersistentStorage.persistProp('bookshelfDarkCoverAlbumId', '');
    PersistentStorage.persistProp('bookshelfCoverApplyScope', 'all');
    PersistentStorage.persistProp('bookshelfCoverTargetBooks', '');
    PersistentStorage.persistProp('bookshelfIgnoreSourceCover', false);
    PersistentStorage.persistProp('bookshelfCoverMode', 'sequence');
    PersistentStorage.persistProp('searchExploreShowResultCover', true);
    PersistentStorage.persistProp('searchExploreUseBookshelfCoverGallery', false);
    PersistentStorage.persistProp('searchExploreShowResultTags', true);
    PersistentStorage.persistProp('searchExplorePromptAddToShelfOnBack', true);
    PersistentStorage.persistProp('searchExploreExactSearch', false);
    PersistentStorage.persistProp('searchExploreExactSearchMatchAuthor', true);
    PersistentStorage.persistProp('searchExploreShowSearchProgress', true);
    PersistentStorage.persistProp('searchExploreSearchConcurrency', 8);
    PersistentStorage.persistProp('searchExploreSelectedSourceGroups', '');
    PersistentStorage.persistProp('searchExploreSourceSort', '');
    PersistentStorage.persistProp('appLightAccentColor', '#007DFF');
    PersistentStorage.persistProp('appDarkAccentColor', '#4E9BFF');
    PersistentStorage.persistProp('appLightButtonColor', '#007DFF');
    PersistentStorage.persistProp('appDarkButtonColor', '#3F8CFF');
    PersistentStorage.persistProp('appIconId', AppIconSettingsStore.DEFAULT_ICON_ID);
    PersistentStorage.persistProp('explorePlatform', '番茄');
    PersistentStorage.persistProp('exploreSourceUrl', '');
    CoverGalleryStore.load(this.context).then((snapshot) => {
      CoverGalleryStore.applyToStorage(snapshot);
      return CoverGalleryStore.save(this.context, snapshot);
    }).catch((e: Error) => {
      hilog.warn(0x0000, 'testTag', 'Sync cover gallery settings failed: %{public}s', JSON.stringify(e));
    });
    BookshelfDisplaySettingsStore.load(this.context).then((settings) => {
      BookshelfDisplaySettingsStore.applyToStorage(settings);
    }).catch((e: Error) => {
      hilog.warn(0x0000, 'testTag', 'Sync bookshelf display settings failed: %{public}s', JSON.stringify(e));
    });
    SearchExploreSettingsStore.load(this.context).then((settings) => {
      SearchExploreSettingsStore.applyToStorage(settings);
    }).catch((e: Error) => {
      hilog.warn(0x0000, 'testTag', 'Sync search explore settings failed: %{public}s', JSON.stringify(e));
    });
    TtsSettingsStore.load(this.context).then((settings) => {
      TtsSettingsStore.applyToStorage(settings);
    }).catch((e: Error) => {
      hilog.warn(0x0000, 'testTag', 'Sync tts settings failed: %{public}s', JSON.stringify(e));
    });
    this.themeBootstrapPromise = AppThemeSettingsStore.load(this.context).then((settings) => {
      AppThemeSettingsStore.applyToStorage(settings);
      return GlassSettingsStore.load(this.context);
    }).then((settings) => {
      GlassSettingsStore.applyToStorage(settings);
    }).catch((e: Error) => {
      hilog.warn(0x0000, 'testTag', 'Sync app theme settings failed: %{public}s', JSON.stringify(e));
    }).then(() => {
      return ReaderSettingsStore.load(this.context);
    }).then((settings) => {
      ReaderSettingsStore.applyToStorage(settings);
    }).catch((e: Error) => {
      hilog.warn(0x0000, 'testTag', 'Sync reader settings failed: %{public}s', JSON.stringify(e));
    });
    AppIconSettingsStore.load(this.context).then((settings) => {
      AppIconSettingsStore.applyToStorage(settings);
    }).catch((e: Error) => {
      hilog.warn(0x0000, 'testTag', 'Sync app icon settings failed: %{public}s', JSON.stringify(e));
    });
    this.handleLaunchWant(want);
  }

  onDestroy(): void {
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    this.mainWindowStage = windowStage;
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onWindowStageCreate');
    hilog.info(0x0000, 'testTag', 'StartupTrace onWindowStageCreate %{public}d', Date.now());

    this.themeBootstrapPromise.then(() => {
      return ReaderFontBootstrap.registerFromSettings(this.context, null, 'ability-onWindowStageCreate');
    }).finally(() => {
      this.loadStartupContent(windowStage);
    });
  }

  private loadStartupContent(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Startup', (err) => {
      if (err.code) {
        hilog.error(0x0000, 'testTag', 'Failed to load content: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(0x0000, 'testTag', 'StartupTrace Startup content loaded %{public}d', Date.now());
      this.syncStartupWindow(windowStage);
    });
  }

  onWindowStageDestroy(): void {
    this.mainWindowStage = null;
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onForeground');
    this.syncSystemColorMode(this.context.config);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, 'testTag', 'Ability onNewWant %{public}s', JSON.stringify(launchParam));
    const launchTarget = this.handleLaunchWant(want);
    if (launchTarget && this.mainWindowStage) {
      const targetUrl = launchTarget === 'bookSource' ? 'pages/BookSource' : 'pages/Startup';
      this.mainWindowStage.getMainWindow().then((mainWindow: window.Window) => {
        const appRouter = mainWindow.getUIContext().getRouter();
        const state = appRouter.getState();
        if (this.routeMatches(state.name, state.path, targetUrl)) {
          return Promise.resolve();
        }
        return appRouter.pushUrl({ url: targetUrl });
      }).catch((e: Error) => {
        hilog.warn(0x0000, 'testTag', 'Open external file failed: %{public}s', JSON.stringify(e));
      });
    }
  }

  onBackground(): void {
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onBackground');
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    this.syncSystemColorMode(newConfig);
  }

  private syncSystemColorMode(config: Configuration): void {
    const mode = AppStorage.get<string>('appThemeMode') || 'system';
    this.applyThemeColorMode(mode, config);
  }

  private applyThemeColorMode(mode: string, config: Configuration): void {
    const normalizedMode = AppThemeModeStore.normalizeMode(mode);
    AppStorage.setOrCreate('appThemeMode', normalizedMode);
    if (normalizedMode === 'dark') {
      AppStorage.setOrCreate('appDarkMode', true);
      this.setApplicationColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
      return;
    }
    if (normalizedMode === 'light') {
      AppStorage.setOrCreate('appDarkMode', false);
      this.setApplicationColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
      return;
    }
    this.setApplicationColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    AppStorage.setOrCreate('appDarkMode', config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
  }

  private setApplicationColorMode(colorMode: number): void {
    if (this.appliedColorMode === colorMode) {
      return;
    }
    this.appliedColorMode = colorMode;
    this.context.getApplicationContext().setColorMode(colorMode);
  }

  private handleLaunchWant(want: Want): string {
    hilog.info(0x0000, 'testTag',
      'Launch want action=%{public}s type=%{public}s uri=%{private}s params=%{public}s',
      want.action || '', want.type || '', want.uri || '', this.wantParameterKeys(want));
    const externalUri = this.externalFileUri(want);
    const externalName = this.externalFileNameHint(want, externalUri);
    const externalFormat = externalUri ? this.externalFileFormat(want, externalUri, externalName) : '';
    if (externalUri && externalFormat === 'json') {
      AppStorage.setOrCreate('pendingBookSourceImportUri', externalUri);
      const nonce = AppStorage.get<number>('pendingBookSourceImportNonce') || 0;
      AppStorage.setOrCreate('pendingBookSourceImportNonce', nonce + 1);
      return 'bookSource';
    }
    if (externalUri && (externalFormat === 'txt' || externalFormat === 'epub')) {
      AppStorage.setOrCreate('pendingLocalBookImportUri', externalUri);
      AppStorage.setOrCreate('pendingLocalBookImportFormat', externalFormat);
      AppStorage.setOrCreate('pendingLocalBookImportName', externalName);
      const nonce = AppStorage.get<number>('pendingLocalBookImportNonce') || 0;
      AppStorage.setOrCreate('pendingLocalBookImportNonce', nonce + 1);
      return 'localBook';
    }
    const params = this.getLaunchParams(want);
    if (params['cacheAction'] === 'cancelFullTextCache') {
      const nonce = Date.now();
      AppStorage.setOrCreate('fullTextCacheCancelSignal', JSON.stringify({
        nonce: nonce,
        taskKey: params['cacheTaskKey'] || '',
        bookUrl: params['bookUrl'] || ''
      }));
      AppStorage.setOrCreate('fullTextCacheCancelNonce', nonce);
      return '';
    }
    const action = params['shortcutAction'];
    if (action === RECENT_READ_SHORTCUT_ACTION) {
      RecentReadShortcut.request();
      return '';
    }
    if (action === OPEN_BOOK_SHORTCUT_ACTION) {
      const bookUrl = params['bookUrl'];
      if (bookUrl) {
        RecentReadShortcut.requestBook(bookUrl);
      }
    }
    return '';
  }

  private externalFileFormat(want: Want, uri: string, fileNameHint: string): string {
    const uriExtension = this.externalFileExtension(uri);
    const nameExtension = this.externalFileExtension(fileNameHint);
    const extension = this.isSupportedExternalExtension(uriExtension) ? uriExtension : nameExtension;
    if (this.isSupportedExternalExtension(extension)) return extension;
    const type = (want.type || '').toLowerCase();
    if (type === 'application/json' || type === 'text/json' || type === 'application/x-json' ||
      type === 'general.json') return 'json';
    if (type === 'general.epub' || type === 'application/epub+zip' ||
      type === 'application/x-epub+zip') return 'epub';
    const sniffed = this.sniffExternalFileFormat(uri);
    if (sniffed) return sniffed;
    if (type === 'general.plain-text' || type === 'text/plain' || type === 'general.text') return 'txt';
    return '';
  }

  private externalFileUri(want: Want): string {
    const directUri = this.externalFileUriFromValue(want.uri);
    if (directUri) return directUri;
    const parameters = want.parameters;
    if (!parameters) return '';
    const preferredKeys = ['ability.params.stream', 'ohos.extra.param.key.stream', 'uri', 'fileUri', 'shareUri'];
    for (const key of preferredKeys) {
      const preferredUri = this.externalFileUriFromValue(parameters[key]);
      if (preferredUri) return preferredUri;
    }
    for (const key of Object.keys(parameters)) {
      const candidate = this.externalFileUriFromValue(parameters[key]);
      if (candidate) return candidate;
    }
    return '';
  }

  private externalFileUriFromValue(value: Object | undefined): string {
    if (typeof value === 'string') {
      const text = value.trim();
      if (this.isExternalFileUri(text)) return text;
      if ((text.startsWith('[') && text.endsWith(']')) || (text.startsWith('{') && text.endsWith('}'))) {
        try {
          return this.externalFileUriFromValue(JSON.parse(text) as Object);
        } catch (_) {
        }
      }
      return '';
    }
    if (Array.isArray(value)) {
      const items = value as Object[];
      for (let i = 0; i < items.length; i++) {
        const item: Object = items[i];
        const candidate = this.externalFileUriFromValue(item);
        if (candidate) return candidate;
      }
      return '';
    }
    if (value && typeof value === 'object') {
      const record = value as Record<string, Object>;
      for (const key of Object.keys(record)) {
        const candidate = this.externalFileUriFromValue(record[key]);
        if (candidate) return candidate;
      }
    }
    return '';
  }

  private isExternalFileUri(value: string): boolean {
    const lower = value.toLowerCase();
    return lower.startsWith('file://') || lower.startsWith('datashare://') ||
      lower.startsWith('content://') || value.startsWith('/');
  }

  private externalFileNameHint(want: Want, uri: string): string {
    const uriExtension = this.externalFileExtension(uri);
    if (this.isSupportedExternalExtension(uriExtension)) return this.externalFileName(uri);
    const parameters = want.parameters;
    if (!parameters) return '';
    const preferredKeys = ['fileName', 'filename', 'displayName', 'name', 'title',
      'ohos.extra.param.key.contentTitle'];
    for (const key of preferredKeys) {
      const hint = this.externalFileNameFromValue(parameters[key]);
      if (hint) return hint;
    }
    for (const key of Object.keys(parameters)) {
      const hint = this.externalFileNameFromValue(parameters[key]);
      if (hint) return hint;
    }
    return '';
  }

  private externalFileNameFromValue(value: Object | undefined): string {
    if (typeof value === 'string') {
      const text = value.trim();
      return this.isSupportedExternalExtension(this.externalFileExtension(text)) ?
        this.externalFileName(text) : '';
    }
    if (Array.isArray(value)) {
      const items = value as Object[];
      for (let i = 0; i < items.length; i++) {
        const item: Object = items[i];
        const hint = this.externalFileNameFromValue(item);
        if (hint) return hint;
      }
    }
    return '';
  }

  private sniffExternalFileFormat(uri: string): string {
    let file: fs.File | null = null;
    try {
      file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      const buffer = new ArrayBuffer(8192);
      const readLength = fs.readSync(file.fd, buffer, { offset: 0, length: buffer.byteLength });
      if (readLength >= 4) {
        const bytes = new Uint8Array(buffer, 0, readLength);
        if (bytes[0] === 0x50 && bytes[1] === 0x4B &&
          ((bytes[2] === 0x03 && bytes[3] === 0x04) || (bytes[2] === 0x05 && bytes[3] === 0x06))) {
          return 'epub';
        }
        const text = util.TextDecoder.create('utf-8').decodeWithStream(bytes, { stream: false })
          .replace(/^\uFEFF/, '').trim();
        if (text.startsWith('{') || text.startsWith('[')) return 'json';
        return 'txt';
      }
    } catch (e) {
      hilog.warn(0x0000, 'testTag', 'Sniff external file failed: %{public}s', JSON.stringify(e));
    } finally {
      if (file) {
        try {
          fs.closeSync(file);
        } catch (_) {
        }
      }
    }
    return '';
  }

  private isSupportedExternalExtension(extension: string): boolean {
    return extension === 'json' || extension === 'txt' || extension === 'epub';
  }

  private externalFileName(uriOrName: string): string {
    const clean = uriOrName.split('?')[0].split('#')[0];
    let decoded = clean;
    try {
      decoded = decodeURIComponent(clean);
    } catch (_) {
    }
    return decoded.substring(Math.max(decoded.lastIndexOf('/'), decoded.lastIndexOf('\\')) + 1);
  }

  private externalFileExtension(uri: string): string {
    const cleanUri = uri.split('?')[0].split('#')[0];
    let decoded = cleanUri;
    try {
      decoded = decodeURIComponent(cleanUri);
    } catch (_) {
    }
    const fileName = decoded.substring(decoded.lastIndexOf('/') + 1).toLowerCase();
    const dot = fileName.lastIndexOf('.');
    return dot >= 0 ? fileName.substring(dot + 1) : '';
  }

  private wantParameterKeys(want: Want): string {
    return want.parameters ? Object.keys(want.parameters).join(',') : '';
  }

  private routeMatches(name: string, path: string, targetUrl: string): boolean {
    const targetName = targetUrl.substring(targetUrl.lastIndexOf('/') + 1);
    return name === targetName || path === targetUrl || path.endsWith(`/${targetName}`);
  }

  private getLaunchParams(want: Want): Record<string, string> {
    const result: Record<string, string> = {};
    const parameters = want.parameters;
    if (!parameters) {
      return result;
    }

    const shortcutAction = parameters['shortcutAction'];
    if (typeof shortcutAction === 'string') {
      result['shortcutAction'] = shortcutAction;
    }
    const bookUrl = parameters['bookUrl'];
    if (typeof bookUrl === 'string') {
      result['bookUrl'] = bookUrl;
    }
    const cacheAction = parameters['cacheAction'];
    if (typeof cacheAction === 'string') {
      result['cacheAction'] = cacheAction;
    }
    const cacheTaskKey = parameters['cacheTaskKey'];
    if (typeof cacheTaskKey === 'string') {
      result['cacheTaskKey'] = cacheTaskKey;
    }

    const cardParams = parameters['params'];
    if (typeof cardParams === 'string') {
      try {
        const parsed = JSON.parse(cardParams) as Record<string, Object>;
        const parsedAction = parsed['shortcutAction'];
        if (typeof parsedAction === 'string') {
          result['shortcutAction'] = parsedAction;
        }
        const parsedBookUrl = parsed['bookUrl'];
        if (typeof parsedBookUrl === 'string') {
          result['bookUrl'] = parsedBookUrl;
        }
        const parsedCacheAction = parsed['cacheAction'];
        if (typeof parsedCacheAction === 'string') {
          result['cacheAction'] = parsedCacheAction;
        }
        const parsedCacheTaskKey = parsed['cacheTaskKey'];
        if (typeof parsedCacheTaskKey === 'string') {
          result['cacheTaskKey'] = parsedCacheTaskKey;
        }
      } catch (e) {
        hilog.warn(0x0000, 'testTag', 'Parse card params failed: %{public}s', JSON.stringify(e));
      }
    }
    return result;
  }

  private syncStartupWindow(windowStage: window.WindowStage): void {
    setTimeout(() => {
      windowStage.getMainWindow().then((mainWindow) => {
        const darkMode = AppStorage.get<boolean>('appDarkMode') || false;
        const bg = ThemeRuntime.pageColor(darkMode);
        mainWindow.setWindowBackgroundColor(bg);
        mainWindow.setWindowLayoutFullScreen(true);
        mainWindow.setWindowSystemBarEnable(['navigation', 'status']);
        mainWindow.setWindowSystemBarProperties({
          statusBarColor: '#00000000',
          isStatusBarLightIcon: darkMode,
          statusBarContentColor: ThemeRuntime.primaryTextColor(darkMode),
          navigationBarColor: bg,
          isNavigationBarLightIcon: darkMode,
          navigationBarContentColor: ThemeRuntime.primaryTextColor(darkMode)
        });
      }).catch((err: Error) => {
        hilog.warn(0x0000, 'testTag', 'Startup window sync failed: %{public}s', JSON.stringify(err));
      });
    }, 0);
  }

}
