import { promptAction, router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { RecentReadShortcut } from '../utils/RecentReadShortcut';
import { ReaderFontBootstrap } from '../utils/ReaderFontBootstrap';
import { ReaderSystemFontHelper } from '../utils/ReaderSystemFontHelper';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { LocalBookService } from '../core/book/LocalBookService';

@Entry
@Component
struct StartupPage {
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
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
      this.hasPendingLocalBookImport() ? 0 : 650;
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
      await router.replaceUrl({ url: 'pages/BookSource' });
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
      promptAction.showToast({ message: `导入本地书籍失败: ${message}` });
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
    Column() {
      Row() {
        Text('书架')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())
          .layoutWeight(1)
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)

      Column({ space: 10 }) {
        this.placeholderCard(0.92)
        this.placeholderCard(0.78)
        this.placeholderCard(0.86)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.statusBarHeight })
    .backgroundColor(this.pageColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  @Builder
  placeholderCard(widthRatio: number) {
    Row() {
      Column()
        .width(56)
        .height(72)
        .borderRadius(6)
        .backgroundColor(this.appDarkMode ? '#24272D' : '#E6E9EE')

      Column({ space: 8 }) {
        Column()
          .width(`${Math.floor(widthRatio * 100)}%`)
          .height(16)
          .borderRadius(8)
          .backgroundColor(this.appDarkMode ? '#24272D' : '#E2E5EA')
        Column()
          .width('48%')
          .height(12)
          .borderRadius(6)
          .backgroundColor(this.appDarkMode ? '#202329' : '#ECEEF2')
        Column()
          .width('34%')
          .height(12)
          .borderRadius(6)
          .backgroundColor(this.appDarkMode ? '#202329' : '#ECEEF2')
      }
      .layoutWeight(1)
      .margin({ left: 12 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(12)
    .borderRadius(8)
    .backgroundColor(this.appDarkMode ? '#191B1F' : '#FFFFFF')
  }

  pageColor(): string {
    return ThemeRuntime.pageColor(this.appDarkMode);
  }

  primaryTextColor(): string {
    return ThemeRuntime.primaryTextColor(this.appDarkMode);
  }
}
