import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { RecentReadShortcut } from '../utils/RecentReadShortcut';
import { ReaderFontBootstrap } from '../utils/ReaderFontBootstrap';
import { ReaderSystemFontHelper } from '../utils/ReaderSystemFontHelper';

@Entry
@Component
struct StartupPage {
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  private jumpTimer: number = -1;

  aboutToAppear(): void {
    hilog.info(0x0000, 'testTag', 'StartupTrace Startup aboutToAppear %{public}d', Date.now());
    if (this.jumpTimer >= 0) {
      return;
    }
    ReaderSystemFontHelper.applyToStorage(this.getUIContext());
    ReaderFontBootstrap.registerFromSettings(getContext(this), this.getUIContext(), 'startup-aboutToAppear');
    this.jumpTimer = setTimeout(() => {
      this.jumpTimer = -1;
      hilog.info(0x0000, 'testTag', 'StartupTrace replace Index %{public}d', Date.now());
      this.openStartupTarget().catch((e: Error) => {
        console.error('打开启动目标失败:', e);
      });
    }, 650);
  }

  aboutToDisappear(): void {
    if (this.jumpTimer >= 0) {
      clearTimeout(this.jumpTimer);
      this.jumpTimer = -1;
    }
  }

  async openStartupTarget(): Promise<void> {
    if (!RecentReadShortcut.isPending()) {
      await this.replaceToIndex();
      return;
    }
    try {
      const opened = await RecentReadShortcut.openPending(getContext(this), true);
      RecentReadShortcut.consume();
      if (!opened) {
        await this.replaceToIndex();
      }
    } catch (e) {
      RecentReadShortcut.consume();
      console.error('打开最近阅读快捷项失败:', e);
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
    return this.appDarkMode ? '#101113' : '#F5F5F5';
  }

  primaryTextColor(): string {
    return this.appDarkMode ? '#F2F3F5' : '#1F1F1F';
  }
}
