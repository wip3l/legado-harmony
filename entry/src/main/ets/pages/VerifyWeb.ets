import { router, promptAction } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { CookieStore } from '../core/http/CookieStore';
import { VerificationSupport } from '../core/http/VerificationSupport';
import { AppDatabase } from '../model/data/AppDatabase';
import { BookSource } from '../model/data/Book';
import { ReadBookEngine } from '../core/book/ReadBookEngine';
import { BookSourceRuntimeSnapshotStore } from '../core/book/BookSourceRuntimeSnapshot';
import { syncSystemBars } from '../utils/SystemBars';
import { ImmersiveBackButton } from '../components/ImmersiveBackButton';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { HdsFeedback } from '../utils/HdsFeedback';

/**
 * Restricted bridge used only by HTML passed to java.showBrowser(). Remote pages do not receive
 * the login runtime object: only navigation, user feedback and same-origin cookie operations are
 * exposed, so enabling this bridge cannot reach files, processes, reflection or arbitrary hosts.
 * Source-variable access is additionally restricted to pages opened by a book-source browser
 * payload (java.showBrowser preload session) whose origin matches the payload URL, so an ordinary
 * verification page can never read or rewrite book-source variables.
 */
class BookSourceBrowserJavaBridge {
  private readonly activeProvider: () => boolean;
  private readonly currentUrlProvider: () => string;
  private readonly navigate: (url: string, title: string) => void;
  private readonly variableAccessProvider: () => boolean;
  private readonly variableGetter: () => string;
  private readonly variableSetter: (value: string) => void;

  constructor(activeProvider: () => boolean, currentUrlProvider: () => string,
    navigate: (url: string, title: string) => void, variableAccessProvider: () => boolean = (): boolean => false,
    variableGetter: () => string = (): string => '', variableSetter: (value: string) => void = (_: string): void => {}) {
    this.activeProvider = activeProvider;
    this.currentUrlProvider = currentUrlProvider;
    this.navigate = navigate;
    this.variableAccessProvider = variableAccessProvider;
    this.variableGetter = variableGetter;
    this.variableSetter = variableSetter;
  }

  toast(message: string): void {
    this.showToast(String(message || ''));
  }

  longToast(message: string): void {
    this.showToast(String(message || ''));
  }

  getVariable(): string {
    if (!this.variableAccessProvider()) return '';
    return this.variableGetter();
  }

  putVariable(value: string): boolean {
    if (!this.variableAccessProvider()) return false;
    this.variableSetter(String(value ?? ''));
    return true;
  }

  reLoginView(_refresh: boolean = false): boolean {
    // The payload page may ask the host to refresh its login view; the reader app re-reads the
    // persisted source variable when the verification page closes, so this is a no-op here.
    return this.variableAccessProvider();
  }

  startBrowser(url: string, title: string): void {
    this.openTarget(url, title);
  }

  startBrowserDp(url: string, title: string): void {
    this.openTarget(url, title);
  }

  open(url: string): void {
    this.openTarget(url, '');
  }

  openUrl(url: string): void {
    this.openTarget(url, '');
  }

  getCookie(url: string): string {
    if (!this.activeProvider()) return '';
    const target = this.sameOriginTarget(url);
    return target ? CookieStore.getCookie(target) : '';
  }

  setCookie(url: string, value: string): boolean {
    if (!this.activeProvider()) return false;
    const target = this.sameOriginTarget(url);
    const cookie = String(value || '');
    if (!target || !cookie || cookie.length > 16 * 1024) return false;
    CookieStore.setCookies(target, cookie);
    CookieStore.saveAsync();
    return true;
  }

  removeCookie(url: string, name: string): boolean {
    if (!this.activeProvider()) return false;
    const target = this.sameOriginTarget(url);
    if (!target) return false;
    CookieStore.removeCookie(target, String(name || '') || undefined);
    return true;
  }

  private openTarget(url: string, title: string): void {
    if (!this.activeProvider()) return;
    const target = String(url || '').trim();
    if (!/^https?:\/\//i.test(target)) {
      this.showToast('网页请求打开的地址不受支持');
      return;
    }
    this.navigate(target, String(title || ''));
  }

  private sameOriginTarget(url: string): string {
    const current = this.currentUrlProvider() || '';
    const target = String(url || '').trim() || current;
    const currentOrigin = this.originOf(current);
    const targetOrigin = this.originOf(target);
    return currentOrigin && currentOrigin === targetOrigin ? target : '';
  }

  private originOf(url: string): string {
    const match = String(url || '').match(/^(https?:\/\/[^\/:?#]+(?::\d+)?)/i);
    return match ? String(match[1] || '').toLowerCase() : '';
  }

  private showToast(message: string): void {
    if (!this.activeProvider() || !message) return;
    try {
      HdsFeedback.showToast(message.substring(0, 4000));
    } catch (_) {}
  }
}

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
  @State requireLoginCookie: boolean = false;
  private readerCommentMode: boolean = false;
  private controller: webview.WebviewController = new webview.WebviewController();
  private browserAwaitToken: string = '';
  private browserAwaitCompleted: boolean = false;
  private browserPayloadToken: string = '';
  private browserPayloadHtml: string = '';
  private browserPayloadBaseUrl: string = '';
  private browserPayloadInjectJs: string = '';
  private browserPayloadLoaded: boolean = false;
  private browserSourceUrl: string = '';
  private browserSourceVariable: string = '';
  private browserVariableDirty: boolean = false;
  private onlineBookSourceImportPending: boolean = false;
  private fanqieAppLaunchNoticeShown: boolean = false;
  private readonly browserJavaBridge: BookSourceBrowserJavaBridge = new BookSourceBrowserJavaBridge(
    (): boolean => !!this.browserPayloadToken,
    (): string => this.currentUrl || this.browserPayloadBaseUrl || this.url,
    (url: string, title: string): void => this.openBridgeUrl(url, title),
    (): boolean => this.canAccessBrowserSourceVariable(),
    (): string => this.browserSourceVariable,
    (value: string): void => this.storeBrowserSourceVariable(value));
  private readonly mobileUserAgent: string =
    'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
  aboutToAppear(): void {
    this.syncBars();
    const params = router.getParams() as Record<string, string>;
    const initialUrl = params?.['url'] || AppStorage.get<string>('pendingVerificationUrl') || 'about:blank';
    this.title = params?.['title'] || AppStorage.get<string>('pendingVerificationTitle') || '网页验证';
    this.requireLoginCookie = params?.['requireLoginCookie'] === 'true';
    this.readerCommentMode = params?.['readerCommentMode'] === 'true';
    this.browserAwaitToken = params?.['bookSourceBrowserAwaitToken'] || '';
    this.browserPayloadToken = params?.['bookSourceBrowserPayloadToken'] || '';
    if (this.browserPayloadToken && this.browserPayloadToken ===
      (AppStorage.get<string>('bookSourceBrowserPayloadToken') || '')) {
      this.browserPayloadHtml = AppStorage.get<string>('bookSourceBrowserPayloadHtml') || '';
      this.browserPayloadBaseUrl = AppStorage.get<string>('bookSourceBrowserPayloadBaseUrl') || initialUrl;
      this.browserPayloadInjectJs = AppStorage.get<string>('bookSourceBrowserPayloadInjectJs') || '';
      this.browserSourceVariable = params?.['bookSourceVariable'] || '';
      this.browserSourceUrl = AppStorage.get<string>('pendingVerificationSourceUrl') || '';
      // A payload without HTML is a plain preload session: the page itself must load, the script
      // rides along on every page load.
      this.url = !this.browserPayloadHtml && this.isHttpUrl(this.browserPayloadBaseUrl) ?
        this.browserPayloadBaseUrl : 'about:blank';
      this.currentUrl = this.browserPayloadBaseUrl || initialUrl;
      return;
    }
    if (this.browserAwaitToken) {
      this.url = initialUrl;
      this.currentUrl = initialUrl;
      return;
    }
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

  onBackPress(): boolean {
    if (!this.browserAwaitToken) return false;
    this.finishBrowserAwait();
    return true;
  }

  aboutToDisappear(): void {
    if (this.browserAwaitToken && !this.browserAwaitCompleted) {
      this.publishBrowserAwaitResult('', '网页操作已取消');
    }
    if (this.browserVariableDirty) {
      this.persistBrowserSourceVariable();
    }
  }

  build() {
    Column() {
      Row() {
        ImmersiveBackButton({ iconColor: this.primaryTextColor(), darkMode: this.appDarkMode,
          onBack: () => this.finishVerify() })

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
      .padding({ right: 8 })
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
        .userAgent(this.browserUserAgent())
        .javaScriptProxy({
          object: this.browserJavaBridge,
          name: 'java',
          methodList: [
            'toast', 'longToast', 'startBrowser', 'startBrowserDp', 'open', 'openUrl',
            'getCookie', 'setCookie', 'removeCookie', 'getVariable', 'putVariable', 'reLoginView'
          ],
          controller: this.controller
        })
        .onControllerAttached(() => {
          this.loadBrowserPayload();
        })
        .onLoadIntercept((event?: OnLoadInterceptEvent): boolean => {
          return this.handleBrowserLoadIntercept(event);
        })
        .onPageBegin((event?: OnPageBeginEvent) => {
          if (event?.url) this.currentUrl = event.url;
        })
        .onPageEnd((event?: OnPageEndEvent) => {
          if (event?.url) {
            this.currentUrl = event.url;
            if (!this.readerCommentMode) {
              this.saveCookies(event.url);
              this.syncDocumentCookies(event.url);
            }
          }
          if (!this.readerCommentMode) this.injectBrowserPayloadScript();
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
    if (this.readerCommentMode) {
      this.backSafely();
      return;
    }
    if (this.browserAwaitToken) {
      await this.finishBrowserAwait();
      return;
    }
    if (this.browserPayloadToken) {
      this.saveCookies(this.currentUrl || this.browserPayloadBaseUrl);
      CookieStore.saveSync();
      const variableSaved = this.browserVariableDirty;
      await this.persistBrowserSourceVariable();
      if (variableSaved) {
        this.showToastSafely('登录信息已保存到书源');
      } else if (this.requireLoginCookie && !this.hasEffectiveBookSourceLoginCookie()) {
        this.showToastSafely('未检测到有效登录 Cookie，请正常登录后再点完成');
      }
      this.backSafely();
      return;
    }
    const verifyUrl = this.currentUrl || this.url;
    await this.syncDocumentCookiesAwait(verifyUrl);
    this.saveCookies(verifyUrl);
    if (this.currentUrl && this.currentUrl !== this.url) {
      this.saveCookies(this.url);
      CookieStore.copyCookies(this.currentUrl, this.url);
    }
    this.syncBookSourceLoginCookies();
    CookieStore.saveSync();
    const verified = this.requireLoginCookie ? this.hasEffectiveBookSourceLoginCookie() :
      true;
    if (verified) {
      AppStorage.setOrCreate('pendingVerificationUrl', '');
      AppStorage.setOrCreate('pendingVerificationTitle', '');
      AppStorage.setOrCreate('pendingVerificationSourceUrl', '');
      AppStorage.setOrCreate('pendingVerificationLoginUrl', '');
      AppStorage.setOrCreate('verificationCompletedAt', Date.now());
      this.showToastSafely('验证信息已保存，请重试搜索或刷新目录');
      this.backSafely();
    } else {
      this.showToastSafely('未检测到有效登录 Cookie，请正常登录后再点完成');
    }
  }

  browserUserAgent(): string {
    // Keep verification pages consistent with the device form factor. Native-app launch links
    // exposed by Fanqie's mobile page are filtered in handleBrowserLoadIntercept(), while its
    // normal HTTPS page, passport requests and session cookies remain inside ArkWeb.
    return this.mobileUserAgent;
  }

  loadBrowserPayload(): void {
    if (this.browserPayloadLoaded || !this.browserPayloadHtml) return;
    this.browserPayloadLoaded = true;
    try {
      const baseUrl = this.browserPayloadBaseUrl && /^https?:\/\//i.test(this.browserPayloadBaseUrl) ?
        this.browserPayloadBaseUrl : undefined;
      this.controller.loadData(this.browserPayloadHtml, 'text/html', 'UTF-8', baseUrl, baseUrl);
    } catch (error) {
      console.error('加载书源网页内容失败:', error);
      this.showToastSafely('加载书源网页内容失败');
    } finally {
      AppStorage.setOrCreate('bookSourceBrowserPayloadToken', '');
      AppStorage.setOrCreate('bookSourceBrowserPayloadHtml', '');
      AppStorage.setOrCreate('bookSourceBrowserPayloadBaseUrl', '');
      AppStorage.setOrCreate('bookSourceBrowserPayloadInjectJs', '');
    }
  }

  injectBrowserPayloadScript(): void {
    if (!this.browserPayloadInjectJs) return;
    // Preload semantics match Android Legado: the script re-runs on every finished page load so
    // login pages that navigate (login -> account) always redefine their save-back hook.
    const shim = '(function(){try{var b=window.java;}' +
      'catch(e){return;}if(!b)return;' +
      'window.source={' +
      'getVariable:function(){try{return String(b.getVariable()||"");}catch(e){return "";}},' +
      'setVariable:function(v){try{return b.putVariable(String(v));}catch(e){return false;}},' +
      'putVariable:function(v){try{return b.putVariable(String(v));}catch(e){return false;}}};})();';
    this.controller.runJavaScript(`${shim}\n${this.browserPayloadInjectJs}`).catch((error: Object): void => {
      console.warn('注入书源网页脚本失败:', error);
    });
  }

  /** Same-origin book-source payload session only; see the bridge class comment. */
  canAccessBrowserSourceVariable(): boolean {
    if (!this.browserPayloadToken || !this.browserPayloadBaseUrl) return false;
    const current = this.currentUrl || this.browserPayloadBaseUrl;
    return this.originOf(current) !== '' && this.originOf(current) === this.originOf(this.browserPayloadBaseUrl);
  }

  storeBrowserSourceVariable(value: string): void {
    const next = String(value ?? '');
    if (!next || next === this.browserSourceVariable) return;
    this.browserSourceVariable = next;
    this.browserVariableDirty = true;
  }

  async persistBrowserSourceVariable(): Promise<void> {
    if (!this.browserVariableDirty || !this.browserSourceUrl) return;
    this.browserVariableDirty = false;
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      const source = await db.getBookSource(this.browserSourceUrl);
      if (!source) return;
      source.variable = this.browserSourceVariable;
      await db.updateBookSourceLoginRuntime(source.bookSourceUrl, source.variable,
        source.loginHeader, source.loginInfo);
      // The reading session and the runtime snapshot cache hold their own copies of the source;
      // refresh both so the freshly saved token is used without reopening the book.
      const engineSource = ReadBookEngine.get().source;
      if (engineSource && engineSource.bookSourceUrl === this.browserSourceUrl) {
        engineSource.variable = this.browserSourceVariable;
        BookSourceRuntimeSnapshotStore.invalidate(this.browserSourceUrl);
      }
    } catch (e) {
      console.error('保存书源网页登录变量失败:', e);
    }
  }

  handleBrowserLoadIntercept(event?: OnLoadInterceptEvent): boolean {
    let requestUrl = '';
    try {
      requestUrl = event?.data.getRequestUrl() || '';
    } catch (_) {}
    if (this.shouldBlockFanqieAppLaunch(requestUrl)) {
      if (!this.fanqieAppLaunchNoticeShown) {
        this.fanqieAppLaunchNoticeShown = true;
        this.showToastSafely('已阻止打开客户端，请继续使用网页登录');
      }
      return true;
    }
    const importUrl = this.parseOnlineBookSourceImportUrl(requestUrl);
    if (!importUrl) return false;
    if (!this.onlineBookSourceImportPending) {
      this.onlineBookSourceImportPending = true;
      this.confirmOnlineBookSourceImport(importUrl).catch((error: Object): void => {
        this.onlineBookSourceImportPending = false;
        const message = error instanceof Error ? error.message : String(error || '');
        this.showToastSafely(message ? `打开书源更新失败：${message}` : '打开书源更新失败');
      });
    }
    return true;
  }

  shouldBlockFanqieAppLaunch(requestUrl: string): boolean {
    const target = String(requestUrl || '').trim();
    if (!target || !this.isFanqieBrowserSession()) return false;
    if (/^(?:sslocal|snssdk\d*|dragon\d*|intent|market|appmarket|hap):\/\//i.test(target)) {
      return true;
    }
    // These HTTPS links are application-launch intermediaries, not web login endpoints. Block
    // only during a Fanqie browser-await session so ordinary verification pages are unaffected.
    return /^https?:\/\/(?:fqnovel\.ugurl\.cn|zlink\.toutiao\.com)(?:[\/:?#]|$)/i.test(target) ||
      /^https?:\/\/reading\.snssdk\.com\/z\//i.test(target);
  }

  isFanqieBrowserSession(): boolean {
    const targets = `${this.url}\n${this.currentUrl}\n` +
      `${AppStorage.get<string>('pendingVerificationLoginUrl') || ''}`;
    return /https?:\/\/(?:[^\/?#]+\.)?fanqienovel\.com(?:[\/:?#]|$)/i.test(targets);
  }

  parseOnlineBookSourceImportUrl(raw: string): string {
    const value = String(raw || '').trim();
    const supported = /^yuedu:\/\/booksource\/importonline(?:[/?#]|$)/i.test(value) ||
      /^legado:\/\/import\/booksource(?:[/?#]|$)/i.test(value);
    if (!supported || value.length > 32 * 1024) return '';
    const match = value.match(/[?&]src=([^&#]*)/i);
    if (!match || !match[1]) return '';
    let target = match[1].replace(/\+/g, '%20');
    try {
      target = decodeURIComponent(target);
    } catch (_) {
      return '';
    }
    // Some update pages encode an already encoded link once more before constructing the scheme.
    if (!/^https?:\/\//i.test(target) && /%[0-9a-f]{2}/i.test(target)) {
      try {
        target = decodeURIComponent(target);
      } catch (_) {}
    }
    return /^https?:\/\//i.test(target) && target.length <= 16 * 1024 ? target : '';
  }

  async confirmOnlineBookSourceImport(importUrl: string): Promise<void> {
    const hostMatch = importUrl.match(/^https?:\/\/([^/?#]+)/i);
    const host = hostMatch && hostMatch[1] ? hostMatch[1] : '远程服务器';
    const result = await promptAction.showDialog({
      title: '更新书源',
      message: `将从 ${host} 下载并更新书源。现有书源变量、登录状态和本地设置会保留。`,
      buttons: [
        { text: '取消', color: this.subTextColor() },
        { text: '更新', color: this.accentColor() }
      ]
    });
    if (result.index !== 1) {
      this.onlineBookSourceImportPending = false;
      return;
    }
    AppStorage.setOrCreate('pendingBookSourceImportUrl', importUrl);
    const nonce = AppStorage.get<number>('pendingBookSourceImportNonce') || 0;
    AppStorage.setOrCreate('pendingBookSourceImportNonce', nonce + 1);
    if (this.browserAwaitToken) {
      this.browserAwaitCompleted = true;
      this.publishBrowserAwaitResult('', '');
    }
    this.showToastSafely('正在下载并更新书源…');
    this.backSafely();
  }

  openBridgeUrl(url: string, title: string): void {
    if (title) this.title = title;
    this.currentUrl = url;
    try {
      this.controller.loadUrl(url);
    } catch (error) {
      console.warn('书源网页桥接打开地址失败:', error);
      this.showToastSafely('打开网页失败');
    }
  }

  async finishBrowserAwait(): Promise<void> {
    if (!this.browserAwaitToken || this.browserAwaitCompleted) return;
    this.browserAwaitCompleted = true;
    try {
      const verifyUrl = this.currentUrl || this.url;
      await this.syncDocumentCookiesAwait(verifyUrl);
      this.saveCookies(verifyUrl);
      if (this.url && verifyUrl !== this.url) {
        this.saveCookies(this.url);
        CookieStore.copyCookies(verifyUrl, this.url);
      }
      this.syncBookSourceLoginCookies();
      CookieStore.saveSync();
      const raw = await this.controller.runJavaScript(this.browserAwaitResultScript());
      const body = this.normalizeBrowserScriptResult(raw);
      if (body.length > 2 * 1024 * 1024) {
        this.publishBrowserAwaitResult('', '网页返回内容超过2MB');
      } else {
        this.publishBrowserAwaitResult(body, '');
      }
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      this.publishBrowserAwaitResult('', `读取网页结果失败：${message}`);
    }
    this.backSafely();
  }

  normalizeBrowserScriptResult(raw: string): string {
    const value = String(raw || '');
    if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
      try {
        return String(JSON.parse(value));
      } catch (_) {}
    }
    return value;
  }

  browserAwaitResultScript(): string {
    // ArkWeb presents <select> with a native picker. On some devices its visible value is committed
    // before the page's change listener has refreshed the hidden result nodes used by Legado source
    // setting pages. Reconcile those nodes from the live controls immediately before serializing the
    // document. This is deliberately idempotent and does not dispatch events, so pages with network
    // or toggle side effects are not executed a second time.
    return `(function(){try{` +
      `const active=document.activeElement;if(active&&typeof active.blur==='function')active.blur();` +
      `if(typeof globalThis.updateHiddenSettings==='function'){try{globalThis.updateHiddenSettings();}catch(e){}}` +
      `const controls=document.querySelectorAll('input,select,textarea');` +
      `for(const control of controls){const id=String(control.id||'');if(!id)continue;` +
      `let value='';if(control.type==='checkbox'||control.type==='radio')value=control.checked?'true':'false';` +
      `else value=String(control.value??'');` +
      `const ids=[id+'Value'];if(/Switch$/.test(id))ids.push(id.replace(/Switch$/,'Value'));` +
      `for(const resultId of ids){const result=document.getElementById(resultId);` +
      `if(result)result.textContent=value;}` +
      `if(control.tagName==='SELECT'){for(const option of control.options){` +
      `if(option.selected)option.setAttribute('selected','selected');else option.removeAttribute('selected');}}` +
      `else if(control.type==='checkbox'||control.type==='radio'){` +
      `if(control.checked)control.setAttribute('checked','checked');else control.removeAttribute('checked');}` +
      `else control.setAttribute('value',value);}` +
      `}catch(e){}` +
      `return document.documentElement?document.documentElement.outerHTML:` +
      `(document.body?document.body.innerHTML:'');})()`;
  }

  publishBrowserAwaitResult(body: string, error: string): void {
    if (!this.browserAwaitToken) return;
    AppStorage.setOrCreate('bookSourceBrowserAwaitResultBody', body || '');
    AppStorage.setOrCreate('bookSourceBrowserAwaitResultError', error || '');
    AppStorage.setOrCreate('bookSourceBrowserAwaitResultToken', this.browserAwaitToken);
  }

  hasEffectiveBookSourceLoginCookie(): boolean {
    const sourceUrl = AppStorage.get<string>('pendingVerificationSourceUrl') || '';
    const loginUrl = AppStorage.get<string>('pendingVerificationLoginUrl') || this.url;
    const urls = [
      this.currentUrl,
      this.url,
      loginUrl,
      sourceUrl,
      this.originOf(this.currentUrl),
      this.originOf(this.url),
      this.originOf(loginUrl),
      this.originOf(sourceUrl)
    ];
    for (const url of urls) {
      if (url && VerificationSupport.hasEffectiveLoginCookie(CookieStore.getCookie(url))) {
        return true;
      }
    }
    return false;
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
      const loginUrl = source ? VerificationSupport.resolveBookSourceLoginUrl(source) : '';
      if (source && loginUrl) {
        this.url = loginUrl;
        this.currentUrl = loginUrl;
        this.title = `${source.bookSourceName || '书源'} 登录`;
        AppStorage.setOrCreate('pendingVerificationSourceUrl', source.bookSourceUrl || '');
        AppStorage.setOrCreate('pendingVerificationLoginUrl', loginUrl);
        setTimeout(() => {
          try {
            this.controller.loadUrl(loginUrl);
          } catch (e) {
            console.warn('主动加载书源登录地址失败，将由 Web 组件状态刷新:', e);
          }
        }, 0);
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
      HdsFeedback.showToast(message);
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
    return this.isHttpUrl(url);
  }

  documentCookieTargets(url: string): string[] {
    const currentHost = this.hostOf(url);
    const targets: string[] = [
      url,
      this.originOf(url)
    ];
    return targets.filter((item: string, index: number, array: string[]) => {
      return this.isHttpUrl(item) && this.hostOf(item) === currentHost && array.indexOf(item) === index;
    });
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
    return ThemeRuntime.pageColor(this.appDarkMode);
  }

  hostOf(url: string): string {
    const match = (url || '').match(/^https?:\/\/([^/:?#]+)/i);
    return match && match[1] ? match[1].toLowerCase() : '';
  }

  cardColor(): string {
    return ThemeRuntime.cardColor(this.appDarkMode);
  }

  primaryTextColor(): string {
    return ThemeRuntime.primaryTextColor(this.appDarkMode);
  }

  subTextColor(): string {
    return ThemeRuntime.subTextColor(this.appDarkMode);
  }

  accentColor(): string {
    return ThemeRuntime.accentColor(this.appDarkMode);
  }

  syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, this.pageColor());
  }
}
