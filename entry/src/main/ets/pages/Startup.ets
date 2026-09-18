import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { RecentReadShortcut } from '../utils/RecentReadShortcut';
import { ReaderFontBootstrap } from '../utils/ReaderFontBootstrap';
import { ReaderSystemFontHelper } from '../utils/ReaderSystemFontHelper';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { LocalBookService } from '../core/book/LocalBookService';
import { ThemeStartupCover } from '../components/ThemeStartupCover';
import { ThemeIds } from '../theme/ThemeModels';
import { AppThemeSettingsStore } from '../utils/AppThemeSettingsStore';
import { HdsFeedback } from '../utils/HdsFeedback';

@Entry
@Component
struct StartupPage {
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('appThemeId') appThemeId: string = AppThemeSettingsStore.DEFAULT_THEME_ID;
  @StorageLink('appCustomLightStartupImagePath') customLightStartupImagePath: string = '';
  @StorageLink('appCustomDarkStartupImagePath') customDarkStartupImagePath: string = '';
  @StorageLink('appCustomLightStartupTitle') customLightStartupTitle: string = '开源轻页';
  @StorageLink('appCustomDarkStartupTitle') customDarkStartupTitle: string = '开源轻页';
  @StorageLink('appCustomLightStartupSubtitle') customLightStartupSubtitle: string = '';
  @StorageLink('appCustomDarkStartupSubtitle') customDarkStartupSubtitle: string = '';
  @StorageLink('pendingLocalBookImportNonce') @Watch('onPendingLocalBookImportChanged')
  pendingLocalBookImportNonce: number = 0;
  private jumpTimer: number = -1;
  private isOpeningTarget: boolean = false;

  aboutToAppear(): void {
    hilog.info(0x0000, 'testTag', 'StartupTrace Startup aboutToAppear %{public}d', Date.now());
    if (this.jumpTimer >= 0) {
      return;
    }
    ReaderSystemFontHelper.applyToStorage(this.getUIContext());
    ReaderFontBootstrap.registerFromSettings(getContext(this), this.getUIContext(), 'startup-aboutToAppear');
    const startupDelay = RecentReadShortcut.isPending() || this.hasPendingBookSourceImport() ||
      this.hasPendingLocalBookImport() || (ThemeRuntime.startupThemeId(this.appDarkMode) === ThemeIds.PLAIN_DEFAULT &&
        !this.customStartupImage()) ?
      0 : 720;
    this.jumpTimer = setTimeout(() => {
      this.jumpTimer = -1;
      hilog.info(0x0000, 'testTag', 'StartupTrace replace Index %{public}d', Date.now());
      this.openStartupTarget().catch((e: Error) => {
        console.error('打开启动目标失败:', e);
      });
    }, startupDelay);
  }

  aboutToDisappear(): void {
    if (this.jumpTimer >= 0) {
      clearTimeout(this.jumpTimer);
      this.jumpTimer = -1;
    }
  }

  onPendingLocalBookImportChanged(): void {
    this.scheduleOpenStartupTarget(0);
  }

  scheduleOpenStartupTarget(delay: number): void {
    if (this.jumpTimer >= 0) {
      clearTimeout(this.jumpTimer);
    }
    this.jumpTimer = setTimeout(() => {
      this.jumpTimer = -1;
      this.openStartupTarget().catch((e: Error) => {
        console.error('打开外部本地书籍失败:', e);
      });
    }, delay);
  }

  async openStartupTarget(): Promise<void> {
    if (this.isOpeningTarget) return;
    this.isOpeningTarget = true;
    try {
      await this.openStartupTargetInternal();
    } finally {
      this.isOpeningTarget = false;
      if (this.hasPendingLocalBookImport()) {
        this.scheduleOpenStartupTarget(0);
      }
    }
  }

  async openStartupTargetInternal(): Promise<void> {
    if (this.hasPendingLocalBookImport()) {
      await this.importAndOpenLocalBook();
      return;
    }
    if (this.hasPendingBookSourceImport()) {
      // Keep a real home route under the external-import page so Back returns to the app.
      await router.replaceUrl({ url: 'pages/Index' });
      await router.pushUrl({ url: 'pages/BookSource' });
      return;
    }
    if (!RecentReadShortcut.isPending()) {
      await this.replaceToIndex();
      return;
    }
    try {
      const opened = await RecentReadShortcut.openPending(getContext(this), true);
      if (!opened) {
        await this.replaceToIndex();
      }
    } catch (e) {
      console.error('打开最近阅读快捷项失败:', e);
      await this.replaceToIndex();
    }
  }

  hasPendingBookSourceImport(): boolean {
    return !!AppStorage.get<string>('pendingBookSourceImportUri');
  }

  hasPendingLocalBookImport(): boolean {
    return !!AppStorage.get<string>('pendingLocalBookImportUri');
  }

  async importAndOpenLocalBook(): Promise<void> {
    const uri = AppStorage.get<string>('pendingLocalBookImportUri') || '';
    const format = AppStorage.get<string>('pendingLocalBookImportFormat') || '';
    const sourceName = AppStorage.get<string>('pendingLocalBookImportName') || '';
    AppStorage.setOrCreate('pendingLocalBookImportUri', '');
    AppStorage.setOrCreate('pendingLocalBookImportFormat', '');
    AppStorage.setOrCreate('pendingLocalBookImportName', '');
    if (!uri) {
      await this.replaceToIndex();
      return;
    }
    try {
      const book = await LocalBookService.importExternalBook(getContext(this), uri, format, sourceName);
      const opened = await RecentReadShortcut.openBook(book.bookUrl, true);
      if (!opened) await this.replaceToIndex();
    } catch (e) {
      console.error('导入外部本地书籍失败:', e);
      const message = e instanceof Error ? e.message : String(e);
      HdsFeedback.showToast(`导入本地书籍失败: ${message}`);
      await this.replaceToIndex();
    }
  }

  async replaceToIndex(): Promise<void> {
    try {
      await router.replaceUrl({ url: 'pages/Index' });
    } catch (e) {
      console.error('跳转首页失败:', e);
    }
  }

  build() {
    Stack() {
      ThemeStartupCover({
        themeId: ThemeRuntime.startupThemeId(this.appDarkMode),
        darkMode: this.appDarkMode,
        compact: false,
        animated: true,
        customImagePath: this.customStartupImage(),
        titleOverride: this.customStartupTitle(),
        subtitleOverride: this.customStartupSubtitle(),
        explicitText: this.appThemeId === ThemeIds.CUSTOM
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  pageColor(): string {
    return ThemeRuntime.pageColor(this.appDarkMode);
  }

  customStartupImage(): string {
    if (this.appThemeId !== ThemeIds.CUSTOM) return '';
    return this.appDarkMode ? this.customDarkStartupImagePath : this.customLightStartupImagePath;
  }

  customStartupTitle(): string {
    return this.appDarkMode ? this.customDarkStartupTitle : this.customLightStartupTitle;
  }

  customStartupSubtitle(): string {
    return this.appDarkMode ? this.customDarkStartupSubtitle : this.customLightStartupSubtitle;
  }

  primaryTextColor(): string {
    return ThemeRuntime.primaryTextColor(this.appDarkMode);
  }
}
