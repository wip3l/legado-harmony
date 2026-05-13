import { router, promptAction } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { CookieStore } from '../core/http/CookieStore';
import { syncSystemBars } from '../utils/SystemBars';

@Entry
@Component
struct VerifyWebPage {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @State url: string = '';
  @State title: string = '网页验证';
  @State currentUrl: string = '';
  @State progress: number = 0;
  private controller: webview.WebviewController = new webview.WebviewController();

  aboutToAppear(): void {
    this.syncBars();
    const params = router.getParams() as Record<string, string>;
    this.url = params?.['url'] || AppStorage.get<string>('pendingVerificationUrl') || 'https://www.qidian.com';
    this.title = params?.['title'] || AppStorage.get<string>('pendingVerificationTitle') || '网页验证';
    this.currentUrl = this.url;
  }

  onPageShow(): void {
    this.syncBars();
  }

  build() {
    Column() {
      Row() {
        Text('<')
          .fontSize(24)
          .fontColor(this.primaryTextColor())
          .width(44)
          .height(56)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.finishVerify();
          })

        Column() {
          Text(this.title)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.primaryTextColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.currentUrl)
            .fontSize(11)
            .fontColor(this.subTextColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Text('完成')
          .fontSize(15)
          .fontColor('#007DFF')
          .width(56)
          .height(56)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.finishVerify();
          })
      }
      .width('100%')
      .height(56)
      .padding({ left: 4, right: 8 })
      .backgroundColor(this.cardColor())
      .alignItems(VerticalAlign.Center)

      if (this.progress > 0 && this.progress < 100) {
        Progress({ value: this.progress, total: 100, type: ProgressType.Linear })
          .width('100%')
          .height(2)
      }

      Web({ src: this.url, controller: this.controller })
        .width('100%')
        .layoutWeight(1)
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .onlineImageAccess(true)
        .imageAccess(true)
        .mixedMode(MixedMode.All)
        .onPageBegin((event?: OnPageBeginEvent) => {
          if (event?.url) this.currentUrl = event.url;
        })
        .onPageEnd((event?: OnPageEndEvent) => {
          if (event?.url) {
            this.currentUrl = event.url;
            this.saveCookies(event.url);
          }
        })
        .onProgressChange((event?: OnProgressChangeEvent) => {
          this.progress = event?.newProgress || 0;
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  finishVerify(): void {
    this.saveCookies(this.currentUrl || this.url);
    if (this.currentUrl && this.currentUrl !== this.url) {
      this.saveCookies(this.url);
      CookieStore.copyCookies(this.currentUrl, this.url);
    }
    AppStorage.setOrCreate('pendingVerificationUrl', '');
    AppStorage.setOrCreate('pendingVerificationTitle', '');
    AppStorage.setOrCreate('verificationCompletedAt', Date.now());
    promptAction.showToast({ message: '验证信息已保存，请重试搜索或刷新目录' });
    router.back();
  }

  saveCookies(url: string): void {
    if (!url) return;
    CookieStore.getCookie(url);
    CookieStore.saveAsync();
  }

  pageColor(): string {
    return this.appDarkMode ? '#101113' : '#F5F5F5';
  }

  cardColor(): string {
    return this.appDarkMode ? '#191B1F' : '#FFFFFF';
  }

  primaryTextColor(): string {
    return this.appDarkMode ? '#F2F3F5' : '#1F1F1F';
  }

  subTextColor(): string {
    return this.appDarkMode ? '#8A8F98' : '#888888';
  }

  syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, this.pageColor());
  }
}
