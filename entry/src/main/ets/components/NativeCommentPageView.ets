import { webview } from '@kit.ArkWeb';
import { NativeCommentPage } from '@legado/sourceengine';

/** Dedicated offline Web: never reuse the remote comment Web or its navigation bridge. */
@Component
export struct NativeCommentPageView {
  @Prop @Watch('pageChanged') page: NativeCommentPage = new NativeCommentPage();
  @State loading: boolean = true;
  @State error: string = '';
  private controller: webview.WebviewController = new webview.WebviewController();
  private timer: number = -1;
  private readyTimer: number = -1;
  private attached: boolean = false;
  private serial: number = 0;

  private pageChanged(): void { this.load(); }

  aboutToDisappear(): void {
    this.attached = false;
    this.serial++;
    this.clearTimer();
    try { this.controller.stop(); } catch (_) { }
  }

  private clearTimer(): void {
    if (this.timer >= 0) clearTimeout(this.timer);
    this.timer = -1;
    if (this.readyTimer >= 0) clearTimeout(this.readyTimer);
    this.readyTimer = -1;
  }

  private scheduleReady(): void {
    if (!this.attached || this.error) return;
    if (this.readyTimer >= 0) clearTimeout(this.readyTimer);
    const serial = this.serial;
    this.readyTimer = setTimeout((): void => {
      this.readyTimer = -1;
      this.controller.runJavaScript(`window.__NATIVE_PAGE_READY__ === true && window.__NATIVE_PAGE_GENERATION__ === ${serial}`)
        .then((ready: string): void => {
          if (!this.attached || serial !== this.serial || this.error) return;
          if (ready === 'true') { this.clearTimer(); this.loading = false; }
          else this.scheduleReady();
        }).catch((): void => {
          if (this.attached && serial === this.serial && !this.error) this.scheduleReady();
        });
    }, 100);
  }

  private fail(message: string): void {
    this.clearTimer();
    this.serial++;
    this.attached = false;
    this.error = message;
    try { this.controller.stop(); } catch (_) { }
    // The error branch unmounts Web instead of leaving a failed document attached to the panel.
  }

  private retry(): void {
    this.attached = false;
    this.controller = new webview.WebviewController();
    this.loading = true;
    this.error = '';
  }

  private load(): void {
    if (!this.attached) return;
    this.serial++;
    this.clearTimer();
    this.loading = true;
    this.error = '';
    try {
      const document = NativeCommentPage.document(this.page, this.serial);
      this.timer = setTimeout((): void => {
        this.fail('评论页渲染超过 15 秒');
      }, 15000);
      this.controller.loadData(document, 'text/html', 'UTF-8', 'about:blank', 'about:blank');
      this.scheduleReady();
    } catch (error) {
      this.fail(error instanceof Error ? error.message : '评论页渲染失败');
    }
  }

  build() {
    Column() {
      Text(this.page.title).fontSize(18).maxLines(2).padding(12).width('100%')
      Stack() {
        if (!this.error) {
        Web({ src: 'about:blank', controller: this.controller, incognitoMode: true,
          renderMode: RenderMode.SYNC_RENDER })
          .width('100%').height('100%')
          .javaScriptAccess(true)
          .blockNetwork(true)
          .fileAccess(false)
          .domStorageAccess(false)
          .databaseAccess(false)
          .geolocationAccess(false)
          .onlineImageAccess(false)
          .multiWindowAccess(false)
          .allowWindowOpenMethod(false)
          .onPermissionRequest((event: OnPermissionRequestEvent): void => event.request.deny())
          .onShowFileSelector((event: OnShowFileSelectorEvent): boolean => {
            event.result.handleFileList([]);
            return true;
          })
          .onAlert((event: OnAlertEvent): boolean => { event.result.handleCancel(); return true; })
          .onConfirm((event: OnConfirmEvent): boolean => { event.result.handleCancel(); return true; })
          .onPrompt((event: OnPromptEvent): boolean => { event.result.handleCancel(); return true; })
          .onOverrideUrlLoading((request: WebResourceRequest): boolean => {
            return !['about:blank', 'about:srcdoc'].includes(request.getRequestUrl());
          })
          .onLoadIntercept((event?: OnLoadInterceptEvent): boolean => {
            return !!event?.data && !['about:blank', 'about:srcdoc'].includes(event.data.getRequestUrl());
          })
          .onInterceptRequest((event?: OnInterceptRequestEvent): WebResourceResponse | null => {
            const url = event?.request?.getRequestUrl() || '';
            if (url === 'about:blank' || url === 'about:srcdoc' || /^data:image\//i.test(url)) return null;
            const response = new WebResourceResponse();
            response.setResponseData('');
            response.setResponseCode(403);
            response.setReasonMessage('Offline page');
            return response;
          })
          .onControllerAttached((): void => { this.attached = true; this.load(); })
          .onPageEnd((): void => this.scheduleReady())
          .onErrorReceive((event: OnErrorReceiveEvent): void => {
            if (event.request.isMainFrame()) this.fail('评论页渲染失败');
          })
        }
        if (this.loading || this.error) {
          Column({ space: 12 }) {
            if (!this.error) { LoadingProgress().width(32).height(32) }
            Text(this.error || '评论页面加载中…')
            if (this.error) { Button('重试').onClick((): void => this.retry()) }
          }.width('100%').height('100%').justifyContent(FlexAlign.Center).backgroundColor('#FFFFFF')
        }
      }.layoutWeight(1).width('100%')
    }.width('100%').height('100%').backgroundColor('#FFFFFF')
  }
}
