import { router, promptAction } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { CookieStore } from '../core/http/CookieStore';
import { EncodedSourceUrl } from '../core/book/EncodedSourceUrl';
import { VerificationSupport } from '../core/http/VerificationSupport';
import { AppDatabase } from '../model/data/AppDatabase';
import { BookSource } from '../model/data/Book';
import { syncSystemBars } from '../utils/SystemBars';

@Entry
@Component
struct VerifyWebPage {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('appLightAccentColor') appLightAccentColor: string = '#007DFF';
  @StorageLink('appDarkAccentColor') appDarkAccentColor: string = '#4E9BFF';
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
    const initialUrl = params?.['url'] || AppStorage.get<string>('pendingVerificationUrl') || 'https://www.qidian.com';
    this.title = params?.['title'] || AppStorage.get<string>('pendingVerificationTitle') || '网页验证';
    if (VerificationSupport.isBookSourceLoginUrl(initialUrl)) {
      this.url = 'about:blank';
      this.currentUrl = '';
      this.resolveBookSourceLoginUrl(initialUrl).catch((e: Error) => {
        console.error('解析书源登录地址失败:', e);
      });
      return;
    }
    this.url = initialUrl;
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
          .fontColor(this.accentColor())
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
          .color(this.accentColor())
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
            this.syncDocumentCookies(event.url);
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

  async finishVerify(): Promise<void> {
    const verifyUrl = this.currentUrl || this.url;
    await this.syncDocumentCookiesAwait(verifyUrl);
    this.syncGuangYuDocumentCookies(verifyUrl);
    this.syncGuangYuDeviceCookie(verifyUrl);
    this.saveCookies(verifyUrl);
    if (this.currentUrl && this.currentUrl !== this.url) {
      this.saveCookies(this.url);
      CookieStore.copyCookies(this.currentUrl, this.url);
    }
    this.syncBookSourceLoginCookies();
    this.syncGuangYuCookies(verifyUrl);
    CookieStore.saveSync();
    const isGuangYu = this.isGuangYuVerify(verifyUrl);
    const verified = !isGuangYu || this.hasGuangYuToken();
    if (verified) {
      AppStorage.setOrCreate('pendingVerificationUrl', '');
      AppStorage.setOrCreate('pendingVerificationTitle', '');
      AppStorage.setOrCreate('pendingVerificationSourceUrl', '');
      AppStorage.setOrCreate('pendingVerificationLoginUrl', '');
      AppStorage.setOrCreate('verificationCompletedAt', Date.now());
      this.showToastSafely('验证信息已保存，请重试搜索或刷新目录');
      this.backSafely();
    } else {
      this.showToastSafely('未检测到登录态，请登录后再点完成');
    }
  }

  saveCookies(url: string): void {
    if (!url) return;
    CookieStore.getCookie(url);
    CookieStore.saveSync();
  }

  async resolveBookSourceLoginUrl(url: string): Promise<void> {
    const bookSourceUrl = VerificationSupport.getBookSourceUrlFromLoginUrl(url);
    if (!bookSourceUrl) return;
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      const source = await db.getBookSource(bookSourceUrl);
      if (source && this.isShushanSource(source)) {
        await this.replaceToBookSourceEdit(bookSourceUrl);
        return;
      }
      const loginUrl = source ? VerificationSupport.resolveBookSourceLoginUrl(source) : '';
      if (source && loginUrl) {
        this.url = loginUrl;
        this.currentUrl = loginUrl;
        this.title = `${source.bookSourceName || '书源'} 登录`;
        AppStorage.setOrCreate('pendingVerificationSourceUrl', source.bookSourceUrl || '');
        AppStorage.setOrCreate('pendingVerificationLoginUrl', loginUrl);
        return;
      }
    } catch (e) {
      console.error('解析书源登录地址失败:', e);
    }
    await this.replaceToBookSourceEdit(bookSourceUrl);
  }

  backSafely(): void {
    try {
      router.back();
    } catch (e) {
      console.error('退出网页验证页失败:', e);
    }
  }

  showToastSafely(message: string): void {
    try {
      promptAction.showToast({ message: message });
    } catch (e) {
      console.error('显示网页验证提示失败:', e);
    }
  }

  async replaceToBookSourceEdit(bookSourceUrl: string): Promise<void> {
    try {
      await router.replaceUrl({
        url: 'pages/BookSourceEdit',
        params: {
          bookSourceUrl: bookSourceUrl
        }
      });
    } catch (e) {
      console.error('跳转书源编辑页失败:', e);
    }
  }

  isShushanSource(source: BookSource): boolean {
    const raw = `${source.bookSourceUrl || ''}\n${source.searchUrl || ''}\n${source.exploreUrl || ''}\n` +
      `${source.loginUrl || ''}\n${source.jsLib || ''}\n${source.header || ''}`;
    return raw.includes('vossc.com') || raw.includes('SHUSAN_READ_2025');
  }

  syncBookSourceLoginCookies(): void {
    const sourceUrl = AppStorage.get<string>('pendingVerificationSourceUrl') || '';
    const loginUrl = AppStorage.get<string>('pendingVerificationLoginUrl') || this.url;
    if (!sourceUrl || !loginUrl) return;
    VerificationSupport.syncLoginCookiesToSourceHosts(sourceUrl, loginUrl, this.currentUrl || this.url);
  }

  syncDocumentCookies(sourceUrl: string): void {
    this.syncDocumentCookiesAwait(sourceUrl).catch(() => {
    });
  }

  async syncDocumentCookiesAwait(sourceUrl: string): Promise<void> {
    if (!sourceUrl || !this.shouldSyncDocumentCookies(sourceUrl)) {
      return;
    }
    try {
      const value = await this.controller.runJavaScript('document.cookie || ""');
      const cookies = this.cleanJsString(value);
      if (!cookies) return;
      const pairs = cookies.split(';').map((item: string) => item.trim()).filter((item: string) => item.includes('='));
      if (pairs.length === 0) return;
      const targets = this.documentCookieTargets(sourceUrl);
      for (const target of targets) {
        for (const pair of pairs) {
          CookieStore.setCookies(target, pair);
          CookieStore.setCookies(target, `${pair}; Path=/`);
        }
      }
      CookieStore.saveSync();
    } catch (_) {
    }
  }

  shouldSyncDocumentCookies(url: string): boolean {
    const sourceUrl = AppStorage.get<string>('pendingVerificationSourceUrl') || '';
    const loginUrl = AppStorage.get<string>('pendingVerificationLoginUrl') || this.url;
    const raw = `${url || ''}\n${this.url || ''}\n${this.currentUrl || ''}\n${sourceUrl}\n${loginUrl}`.toLowerCase();
    return raw.includes('chaoxing.com') || raw.includes('fanqienovel.com') || raw.includes('snssdk.com') ||
      raw.includes('fqnovel.com');
  }

  documentCookieTargets(url: string): string[] {
    const sourceUrl = AppStorage.get<string>('pendingVerificationSourceUrl') || '';
    const loginUrl = AppStorage.get<string>('pendingVerificationLoginUrl') || this.url;
    const raw = `${url || ''}\n${this.url || ''}\n${this.currentUrl || ''}\n${sourceUrl}\n${loginUrl}`.toLowerCase();
    const targets: string[] = [
      url,
      this.currentUrl,
      this.url,
      sourceUrl,
      loginUrl,
      this.originOf(url),
      this.originOf(this.currentUrl),
      this.originOf(this.url),
      this.originOf(sourceUrl),
      this.originOf(loginUrl)
    ];
    if (raw.includes('chaoxing.com')) {
      targets.push('https://chaoxing.com');
      targets.push('https://qikan.chaoxing.com');
      targets.push('https://fxlogin.chaoxing.com');
      targets.push('https://passport2.chaoxing.com');
      targets.push('https://i.chaoxing.com');
    }
    if (raw.includes('fanqienovel.com') || raw.includes('snssdk.com') || raw.includes('fqnovel.com')) {
      targets.push('https://fanqienovel.com');
      targets.push('https://novel.snssdk.com');
      targets.push('https://api5-normal-sinfonlineb.fqnovel.com');
    }
    return targets.filter((item: string, index: number, array: string[]) => {
      return this.isHttpUrl(item) && array.indexOf(item) === index;
    });
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

  originOf(url: string): string {
    const match = (url || '').match(/^(https?:\/\/[^/:?#]+(?::\d+)?)/i);
    return match ? match[1] : '';
  }

  isHttpUrl(url: string): boolean {
    return (url || '').startsWith('http://') || (url || '').startsWith('https://');
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

  accentColor(): string {
    return this.appDarkMode ? this.appDarkAccentColor : this.appLightAccentColor;
  }

  syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, this.pageColor());
  }
}
