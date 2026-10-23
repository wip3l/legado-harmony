import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { PageScaffold } from '../components/common/PageScaffold';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { AppFontSize } from '../theme/AppFontSize';
import { syncSystemBars } from '../utils/SystemBars';
import { HdsFeedback } from '../utils/HdsFeedback';
import { ComicTextRecognizer } from '../core/reader/ComicTextRecognizer';
import { ComicTextGeometry, ComicTextResult } from '../core/reader/ComicTextTypes';
import { ComicChineseConverter } from '../core/reader/ComicChineseConverter';
import { ComicTextRequests } from '../core/reader/ComicTextRequests';
import { ReaderComicSuperResolutionAccess } from '../core/reader/ReaderComicSuperResolution';

interface ComicTextParams {
  requestId: string;
}

/** 当前页 OCR 全文与繁→简文本预览；图上改写见阅读页文字层。不把识别成功等同于翻译成功。 */
@Entry
@Component
struct ComicTextPage {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @State private loading: boolean = false;
  @State private status: string = '';
  @State private failure: string = '';
  @State private original: string = '';
  @State private simplified: string = '';
  @State private showSimplified: boolean = false;
  @State private converting: boolean = false;
  private source: string = '';
  private generation: number = 0;
  private visible: boolean = false;

  aboutToAppear(): void {
    const params = router.getParams() as ComicTextParams;
    if (!this.source && params && typeof params.requestId === 'string') {
      this.source = ComicTextRequests.take(params.requestId);
    }
  }

  onPageShow(): void {
    this.visible = true;
    syncSystemBars(getContext(this), this.appDarkMode, ThemeRuntime.pageColor(this.appDarkMode));
    if (!this.original && !this.loading && !this.failure) this.recognize(false);
  }

  onPageHide(): void {
    this.cancel();
    this.visible = false;
  }

  aboutToDisappear(): void {
    this.cancel();
    this.visible = false;
  }

  private cancel(): void {
    this.generation++;
    this.loading = false;
    this.converting = false;
  }

  private async recognize(force: boolean): Promise<void> {
    if (this.loading) return;
    if (!this.source) {
      this.failure = '没有可识别的图片，请返回漫画后重试';
      return;
    }
    const ticket = ++this.generation;
    this.loading = true;
    this.failure = '';
    this.status = '正在准备图片…';
    this.original = '';
    this.simplified = '';
    this.showSimplified = false;
    const active = (): boolean => this.visible && ticket === this.generation;
    try {
      const result: ComicTextResult = await ComicTextRecognizer.recognize(
        getContext(this) as common.UIAbilityContext, this.source, active,
        (done: number, total: number): void => {
          if (active()) this.status = `正在识别 ${Math.min(done + 1, total)} / ${total}…`;
        }, force);
      if (!active()) return;
      this.original = ComicTextGeometry.text(result);
      this.status = this.original ? `识别到 ${result.regions.length} 行文字` : '未识别到文字，可返回对照原图或重新识别';
    } catch (error) {
      if (!active()) return;
      const message = (error as Error).message || '';
      this.failure = message === ComicTextRecognizer.CANCELLED ? '已取消识别' :
        '识别未完成，请检查图片是否可读取后重试';
      if (!ComicTextRecognizer.supported()) this.failure = '当前设备不支持系统文字识别';
      this.status = '';
    } finally {
      if (active()) this.loading = false;
    }
  }

  private async simplify(): Promise<void> {
    if (!this.original || this.converting) return;
    if (ComicChineseConverter.access() !== ReaderComicSuperResolutionAccess.READY) {
      HdsFeedback.showToast('繁→简为会员专享');
      router.pushUrl({ url: 'pages/AccountCenter' }).catch((_: Error): void => {});
      return;
    }
    if (this.simplified) {
      this.showSimplified = true;
      return;
    }
    const ticket = this.generation;
    this.converting = true;
    try {
      const converter = await ComicChineseConverter.load(getContext(this) as common.UIAbilityContext);
      if (!this.visible || ticket !== this.generation) return;
      this.simplified = converter.convert(this.original);
      this.showSimplified = true;
    } catch (_) {
      if (this.visible && ticket === this.generation) HdsFeedback.showToast('简繁字典加载失败，请重试');
    } finally {
      if (this.visible && ticket === this.generation) this.converting = false;
    }
  }

  private async copyText(): Promise<void> {
    const value = this.showSimplified ? this.simplified : this.original;
    if (!value) return;
    try {
      await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, value));
      HdsFeedback.showToast('已复制');
    } catch (_) {
      HdsFeedback.showToast('复制失败，请重试');
    }
  }

  build() {
    Stack() {
      PageScaffold({ title: '漫画文字', content: () => { this.pageContent() } })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeRuntime.pageColor(this.appDarkMode))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  pageContent() {
    Column({ space: 16 }) {
      Text('在本机识别中文、日文、英文和韩文。繁→简为会员专享，仅转换中文；外语翻译尚未开放。')
        .fontSize(AppFontSize.CAPTION)
        .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
        .width('100%')
      if (this.loading) {
        LoadingProgress().width(32).height(32)
        Text(this.status).fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
        Button('取消识别').onClick(() => {
          this.cancel();
          this.status = '已取消识别';
        })
      } else {
        Text(this.failure || this.status)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
        if (this.original) {
          Row({ space: 12 }) {
            Button('原文').enabled(!this.converting).onClick(() => { this.showSimplified = false; })
            Button(this.converting ? '转换中…' : '繁→简')
              .enabled(!this.converting).onClick(() => { this.simplify(); })
            Button('复制').enabled(!this.converting).onClick(() => { this.copyText(); })
          }
          Text(this.showSimplified ? '简体文本' : '识别原文')
            .fontSize(AppFontSize.CAPTION)
            .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
          Text(this.showSimplified ? this.simplified : this.original)
            .fontSize(AppFontSize.BODY)
            .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
            .copyOption(CopyOptions.LocalDevice)
            .width('100%')
            .padding(16)
            .backgroundColor(ThemeRuntime.cardColor(this.appDarkMode))
            .borderRadius(ThemeRuntime.cardRadius())
        }
        Button('重新识别').enabled(!this.converting).onClick(() => { this.recognize(true); })
        Text('这里列出识别出的全部文字。在漫画画面设置里打开「本书繁→简」，对白会直接在图上改写成简体。竖排、特殊字体的文字与顺序请对照原图。')
          .fontSize(AppFontSize.CAPTION)
          .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
          .width('100%')
      }
    }
    .width('100%')
    .padding(16)
  }
}
