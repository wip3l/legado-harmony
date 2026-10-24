import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { PageScaffold } from '../components/common/PageScaffold';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { AppFontSize } from '../theme/AppFontSize';
import { syncSystemBars } from '../utils/SystemBars';
import { HdsFeedback } from '../utils/HdsFeedback';
import { ComicTextRequests } from '../core/reader/ComicTextRequests';
import { ComicColorizer } from '@legado/aiengine';
import { ReaderComicImageExport } from '../core/reader/ReaderComicImageExport';

interface ComicColorParams {
  requestId: string;
}

@Entry
@Component
struct ComicColorPage {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageProp('accountMembershipSku') @Watch('refreshAccess') membershipSku: string = '';
  @State private memberAllowed: boolean = false;
  @State private source: string = '';
  @State private result: string = '';
  @State private status: string = '点击开始，在本机生成本页彩色预览';
  @State private loading: boolean = false;
  @State private exporting: boolean = false;
  @State private showOriginal: boolean = true;
  @State private imageRatio: number = 0.7;
  private generation: number = 0;
  private visible: boolean = false;
  private accessTimer: number = -1;

  private refreshAccess(): void {
    this.memberAllowed = ComicColorizer.memberAllowed();
    if (!this.source || !ComicColorizer.supported()) return;
    if (!this.memberAllowed) {
      if (this.loading) this.cancel();
      this.result = '';
      this.showOriginal = true;
      this.status = ComicColorizer.MEMBER_REQUIRED;
    } else if (this.status === ComicColorizer.MEMBER_REQUIRED) {
      this.status = '点击开始，在本机生成本页彩色预览';
    }
  }

  private stopAccessWatch(): void {
    if (this.accessTimer >= 0) clearInterval(this.accessTimer);
    this.accessTimer = -1;
  }

  aboutToAppear(): void {
    const params = router.getParams() as ComicColorParams;
    if (!this.source && params && typeof params.requestId === 'string') {
      this.source = ComicTextRequests.take(params.requestId);
    }
    if (!this.source) this.status = '没有可着色的图片，请返回漫画后重试';
    else if (!ComicColorizer.supported()) this.status = '当前设备不支持本地着色引擎';
  }

  onPageShow(): void {
    this.visible = true;
    this.refreshAccess();
    this.stopAccessWatch();
    // Expiry can pass without an account storage event while this page remains open.
    this.accessTimer = setInterval((): void => this.refreshAccess(), 1000);
    syncSystemBars(getContext(this), this.appDarkMode, ThemeRuntime.pageColor(this.appDarkMode));
  }

  onPageHide(): void {
    this.visible = false;
    this.stopAccessWatch();
    this.cancel();
  }

  aboutToDisappear(): void {
    this.visible = false;
    this.stopAccessWatch();
    this.cancel();
  }

  private cancel(): void {
    this.generation++;
    if (this.loading) this.status = '已取消着色';
    this.loading = false;
  }

  private async start(): Promise<void> {
    this.refreshAccess();
    if (!this.memberAllowed) return;
    if (this.loading || !this.source || !ComicColorizer.supported()) return;
    const ticket = ++this.generation;
    const active = (): boolean => this.visible && ticket === this.generation;
    this.loading = true;
    this.status = '正在排队…';
    try {
      const result = await ComicColorizer.colorize(getContext(this), this.source, active,
        (status: string): void => { if (active()) this.status = status; });
      if (!active()) return;
      this.result = result.uri;
      this.showOriginal = false;
      this.status = result.cached ? '已读取本地着色缓存' :
        `本机着色完成 · 总用时 ${(result.elapsedMs / 1000).toFixed(1)} 秒 · 模型计算 ${(result.inferenceMs / 1000).toFixed(1)} 秒`;
    } catch (error) {
      if (active()) this.status = (error as Error).message || '着色未完成，请重试';
    } finally {
      if (active()) this.loading = false;
    }
  }

  private async exportResult(share: boolean): Promise<void> {
    this.refreshAccess();
    if (!this.memberAllowed) return;
    if (!this.result || this.exporting) return;
    this.exporting = true;
    try {
      const context = getContext(this) as common.UIAbilityContext;
      if (share) await ReaderComicImageExport.share(context, this.result);
      else if (await ReaderComicImageExport.saveToAlbum(context, this.result)) HdsFeedback.showToast('彩色页面已保存');
    } catch (_) {
      HdsFeedback.showToast('导出未完成，请重试');
    } finally {
      this.exporting = false;
    }
  }

  build() {
    Stack() {
      PageScaffold({ title: '本页着色', collapsible: false, content: () => { this.pageContent() } })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeRuntime.pageColor(this.appDarkMode))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  pageContent() {
    Column({ space: 16 }) {
      Text('借助AI为黑白漫画着色，图片不上传，原图保留。适合黑白单页漫画，颜色由 AI 推测，可能与原作不同。')
        .fontSize(AppFontSize.CAPTION)
        .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
        .width('100%')
      Text(this.status)
        .fontSize(AppFontSize.CAPTION)
        .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
        .width('100%')
      if (this.loading) {
        LoadingProgress().width(32).height(32)
        Button('取消着色').onClick(() => { this.cancel(); })
      } else if (this.source && ComicColorizer.supported() && !this.memberAllowed) {
        Button('开通会员').onClick(() => { router.pushUrl({ url: 'pages/AccountCenter' }); })
      } else if (!this.result) {
        Button('开始本地着色')
          .enabled(!!this.source && this.memberAllowed && ComicColorizer.supported())
          .onClick(() => { this.start(); })
      }
      if (this.result) {
        Row({ space: 12 }) {
          Button('原图').onClick(() => { this.showOriginal = true; })
          Button('彩色').onClick(() => { this.showOriginal = false; })
        }
        Text(this.showOriginal ? '原图' : '彩色预览')
          .fontSize(AppFontSize.CAPTION)
          .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
        Row({ space: 12 }) {
          Button('保存彩色图').enabled(!this.exporting).onClick(() => { this.exportResult(false); })
          Button('分享彩色图').enabled(!this.exporting).onClick(() => { this.exportResult(true); })
        }
      }
      if (this.source) {
        Image(this.showOriginal || !this.result ? this.source : this.result)
          .width('100%')
          .aspectRatio(this.imageRatio)
          .objectFit(ImageFit.Contain)
          .onComplete((event) => {
            if (event && event.width > 0 && event.height > 0) this.imageRatio = event.width / event.height;
          })
          .borderRadius(8)
      }
    }
    .width('100%')
    .padding(16)
  }
}
