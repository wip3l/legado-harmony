import { router, promptAction } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { CookieStore } from '../core/http/CookieStore';
import { EncodedSourceUrl } from '../core/book/EncodedSourceUrl';
import { syncSystemBars } from '../utils/SystemBars';

@Entry
@Component
struct VerifyWebPage {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @State url: string = '';
  @State title: string = '网页验证';
  @State currentUrl: string = '';
  @State progress: number = 0;
  private controller: webview.WebviewController = new webview.WebviewController();
  private readonly mobileUserAgent: string =
    'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
  private readonly guangYuHosts: string[] = [
    'https://v1.gyks.cf',
    'https://v2.gyks.cf',
    'https://v3.gyks.cf',
    'https://v4.gyks.cf',
    'https://v5.gyks.cf',
    'https://v6.gyks.cf',
    'https://v7.gyks.cf'
  ];

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
        .userAgent(this.mobileUserAgent)
        .onPageBegin((event?: OnPageBeginEvent) => {
          if (event?.url) this.currentUrl = event.url;
        })
        .onPageEnd((event?: OnPageEndEvent) => {
          if (event?.url) {
            this.currentUrl = event.url;
            this.saveCookies(event.url);
            this.syncGuangYuDocumentCookies(event.url);
            this.syncGuangYuDeviceCookie(event.url);
          }
        })
        .onProgressChange((event?: OnProgressChangeEvent) => {
          this.progress = event?.newProgress || 0;
        })
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.statusBarHeight, bottom: this.navBarHeight })
    .backgroundColor(this.pageColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  finishVerify(): void {
    this.syncGuangYuDocumentCookies(this.currentUrl || this.url);
    this.syncGuangYuDeviceCookie(this.currentUrl || this.url);
    this.saveCookies(this.currentUrl || this.url);
    if (this.currentUrl && this.currentUrl !== this.url) {
      this.saveCookies(this.url);
      CookieStore.copyCookies(this.currentUrl, this.url);
    }
    this.syncGuangYuCookies(this.currentUrl || this.url);
    const isGuangYu = this.isGuangYuVerify(this.currentUrl || this.url);
    const verified = !isGuangYu || this.hasGuangYuToken();
    if (verified) {
      AppStorage.setOrCreate('pendingVerificationUrl', '');
      AppStorage.setOrCreate('pendingVerificationTitle', '');
      AppStorage.setOrCreate('verificationCompletedAt', Date.now());
      promptAction.showToast({ message: '验证信息已保存，请重试搜索或刷新目录' });
      router.back();
    } else {
      promptAction.showToast({ message: '未检测到登录态，请登录后再点完成' });
    }
  }

  saveCookies(url: string): void {
    if (!url) return;
    CookieStore.getCookie(url);
    CookieStore.saveAsync();
  }

  syncGuangYuCookies(sourceUrl: string): void {
    if (!this.isGuangYuVerify(sourceUrl)) {
      return;
    }
    let fromUrl = sourceUrl || this.url;
    if (!fromUrl || !CookieStore.getCookie(fromUrl)) {
      for (const host of this.guangYuHosts) {
        const cookie = CookieStore.getCookie(host);
        if (cookie) {
          fromUrl = host;
          break;
        }
      }
    }
    if (!fromUrl || !CookieStore.getCookie(fromUrl)) {
      return;
    }
    for (const host of this.guangYuHosts) {
      CookieStore.copyCookies(fromUrl, host);
      CookieStore.copyCookies(fromUrl, `${host}/login`);
      CookieStore.copyCookies(fromUrl, `${host}/user`);
      CookieStore.copyCookies(fromUrl, `${host}/content`);
    }
    EncodedSourceUrl.syncCookiesAcrossHosts(fromUrl);
    CookieStore.saveAsync();
  }

  syncGuangYuDeviceCookie(sourceUrl: string): void {
    if (!this.isGuangYuVerify(sourceUrl)) {
      return;
    }
    this.controller.runJavaScript('localStorage.getItem("deviceId") || ""')
      .then((value: string) => {
        const deviceId = this.cleanJsString(value);
        if (!deviceId) return;
        for (const host of this.guangYuHosts) {
          CookieStore.setCookies(host, `deviceId=${deviceId}; Path=/`);
          CookieStore.setCookies(`${host}/login`, `deviceId=${deviceId}; Path=/`);
          CookieStore.setCookies(`${host}/user`, `deviceId=${deviceId}; Path=/`);
          CookieStore.setCookies(`${host}/content`, `deviceId=${deviceId}; Path=/`);
        }
        CookieStore.saveAsync();
      })
      .catch(() => {
      });
  }

  syncGuangYuDocumentCookies(sourceUrl: string): void {
    if (!this.isGuangYuVerify(sourceUrl)) {
      return;
    }
    this.controller.runJavaScript('document.cookie || ""')
      .then((value: string) => {
        const cookies = this.cleanJsString(value);
        if (!cookies) return;
        const pairs = cookies.split(';').map((item: string) => item.trim()).filter((item: string) => item.includes('='));
        for (const host of this.guangYuHosts) {
          for (const pair of pairs) {
            CookieStore.setCookies(host, pair);
            CookieStore.setCookies(`${host}/login`, pair);
            CookieStore.setCookies(`${host}/user`, pair);
            CookieStore.setCookies(`${host}/content`, pair);
          }
        }
        CookieStore.saveAsync();
      })
      .catch(() => {
      });
  }

  isGuangYuVerify(url: string): boolean {
    return (this.title || '').includes('光遇') || (url || '').includes('gyks.cf') || (this.url || '').includes('gyks.cf');
  }

  hasGuangYuToken(): boolean {
    const urls: string[] = [];
    if (this.currentUrl) urls.push(this.currentUrl);
    if (this.url) urls.push(this.url);
    for (const host of this.guangYuHosts) {
      urls.push(host);
      urls.push(`${host}/login`);
      urls.push(`${host}/user`);
      urls.push(`${host}/content`);
    }
    for (const url of urls) {
      if (this.cookieValue(CookieStore.getCookie(url), 'qttoken')) {
        return true;
      }
    }
    return false;
  }

  cookieValue(cookie: string, name: string): string {
    if (!cookie) return '';
    for (const item of cookie.split(';')) {
      const pair = item.trim();
      const eq = pair.indexOf('=');
      if (eq <= 0) continue;
      if (pair.substring(0, eq).trim() === name) return pair.substring(eq + 1).trim();
    }
    return '';
  }

  cleanJsString(value: string): string {
    let result = (value || '').trim();
    if ((result.startsWith('"') && result.endsWith('"')) || (result.startsWith("'") && result.endsWith("'"))) {
      result = result.substring(1, result.length - 1);
    }
    return result.trim();
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
