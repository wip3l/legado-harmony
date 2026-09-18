import { router, window } from '@kit.ArkUI';
import { Context } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import picker from '@ohos.file.picker';
import fs from '@ohos.file.fs';
import pasteboard from '@ohos.pasteboard';
import { Book, BookChapter, BookSource, SearchBook } from '../model/data/Book';
import { AppDatabase } from '../model/data/AppDatabase';
import { SearchCoordinator } from '../core/book/SearchCoordinator';
import { ExploreCoordinator, ExploreEntry } from '../core/book/ExploreCoordinator';
import { WebBookService } from '../core/book/WebBookService';
import { SourceRuntimeStage } from '../core/book/BookSourceRuntimeRouter';
import { BookSourceDebugContext, BookSourceDebugSession, BookSourceDebugStep,
  BookSourceDebugNetworkTrace, BookSourceDebugRuleTrace, BookSourceDebugLog,
  BookSourceDebugRedactor } from '../core/book/BookSourceDebugModels';
import { ImmersiveBackButton } from '../components/ImmersiveBackButton';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { syncSystemBars } from '../utils/SystemBars';
import { HdsFeedback } from '../utils/HdsFeedback';

class BookSourceDebugExportReport {
  reportVersion: number = 1;
  exportedAt: string = '';
  sourceUrl: string = '';
  sourceName: string = '';
  stage: string = '';
  session: BookSourceDebugSession = new BookSourceDebugSession();
}

class BookSourceDebugClipboardReport {
  sourceName: string = '';
  sourceUrl: string = '';
  stage: string = '';
  status: string = '';
  session: BookSourceDebugSession = new BookSourceDebugSession();
  content: string = '';
}

@Entry
@Component
struct BookSourceDebugPage {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @State source: BookSource = new BookSource();
  @State sourceUrl: string = '';
  @State keyword: string = '';
  @State stage: string = 'full';
  @State running: boolean = false;
  @State status: string = '准备就绪';
  @State session: BookSourceDebugSession = new BookSourceDebugSession();
  @State keyboardInset: number = 0;
  @State exporting: boolean = false;
  @State debugContent: string = '';
  @State debugSearchLinks: string[] = [];
  @State debugExploreLinks: string[] = [];
  private coordinator: SearchCoordinator | null = null;
  private initialized: boolean = false;
  private keyboardWindow: window.Window | null = null;
  private keyboardAvoidAreaCallback: (data: window.AvoidAreaOptions) => void =
    (data: window.AvoidAreaOptions): void => {
      if (data.type === window.AvoidAreaType.TYPE_KEYBOARD) {
        this.keyboardInset = this.keyboardAvoidAreaHeight(data.area);
      }
    };

  aboutToAppear(): void {
    this.syncBars();
    this.registerKeyboardAvoidance();
    if (this.initialized) return;
    this.initialized = true;
    const params = router.getParams() as Record<string, string>;
    this.sourceUrl = params && params['bookSourceUrl'] ? params['bookSourceUrl'] : '';
    const draft = AppStorage.get<string>('bookSourceDebugDraftJson') || '';
    if (draft) {
      try {
        const draftSource = JSON.parse(draft) as BookSource;
        if (draftSource.bookSourceUrl === this.sourceUrl) this.source = draftSource;
      } catch (_) {
      }
    }
    this.loadSource();
  }

  onPageShow(): void {
    this.syncBars();
    this.registerKeyboardAvoidance();
  }

  onPageHide(): void {
    if (this.running) this.coordinator?.cancel();
    this.unregisterKeyboardAvoidance();
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Scroll() {
        Column({ space: 12 }) {
          this.sourceCard()
          this.inputCard()
          this.resultCard()
        }
        .width('100%')
        .padding({ top: 68 + this.statusBarHeight, bottom: 32 + this.navBarHeight + this.keyboardInset })
      }
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .width('100%')
      .height('100%')
      this.titleBar()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  titleBar() {
    Row() {
      ImmersiveBackButton({ iconColor: this.primaryTextColor(), darkMode: this.appDarkMode,
        buttonSize: 40, containerWidth: 56, materialScale: 0.83, compactLayout: true,
        onBack: () => router.back() })
      Text('书源调试').fontSize(20).fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor()).layoutWeight(1)
      Text('导出报告').fontSize(14).fontColor(this.accentColor())
        .width(88)
        .height(56)
        .textAlign(TextAlign.Center)
        .margin({ right: 12 })
        .opacity(this.hasDebugReport() ? 1 : 0.45)
        .onClick(() => this.exportDebugReport())
    }
    .width('100%').height(56 + this.statusBarHeight).padding({ top: this.statusBarHeight })
    .backgroundColor(ThemeRuntime.topBarColor(this.appDarkMode))
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  sourceCard() {
    Column({ space: 5 }) {
      Text(this.source.bookSourceName || '正在加载书源').fontSize(17).fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor()).width('100%')
      Text(this.source.bookSourceUrl || this.sourceUrl || '未指定书源')
        .fontSize(12).fontColor(this.subTextColor()).width('100%').maxLines(2)
      Text(`状态：${this.status}`).fontSize(13).fontColor(this.running ? '#E89725' : this.accentColor())
        .width('100%')
    }
    .width('calc(100% - 24vp)').padding(16).borderRadius(16).backgroundColor(this.cardColor())
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  inputCard() {
    Column({ space: 10 }) {
      Text('调试阶段').fontSize(16).fontWeight(FontWeight.Medium)
        .fontColor(this.primaryTextColor()).width('100%')
      Text('默认执行全链路：搜索 → 发现 → 详情 → 目录 → 正文')
        .fontSize(13).fontColor(this.subTextColor()).width('100%')
      TextInput({ text: this.keyword, placeholder: this.stageInputPlaceholder() })
        .height(44).width('100%').fontColor(this.primaryTextColor())
        .backgroundColor(this.inputColor()).onChange((value: string) => this.keyword = value)
      Row({ space: 10 }) {
        Button(this.running ? '取消调试' : '开始调试', { type: ButtonType.Capsule })
          .layoutWeight(1).height(44).enabled(this.running || !!this.source.bookSourceUrl)
          .backgroundColor(this.accentColor()).fontColor('#FFFFFF').onClick(() => this.runDebug())
        Button('清空', { type: ButtonType.Capsule }).height(44).width(82)
          .backgroundColor(this.inputColor()).fontColor(this.primaryTextColor())
          .onClick(() => this.clearDebugResult())
      }.width('100%')
    }
    .width('calc(100% - 24vp)').padding(16).borderRadius(16).backgroundColor(this.cardColor())
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  resultCard() {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        Text('执行明细').fontSize(16).fontWeight(FontWeight.Medium)
          .fontColor(this.primaryTextColor()).layoutWeight(1)
        if (this.hasDebugReport() || this.debugContent.length > 0) {
          Button('复制调试内容', { type: ButtonType.Capsule })
            .height(34).fontSize(12).backgroundColor(this.inputColor()).fontColor(this.primaryTextColor())
            .onClick(() => this.copyDebugReport())
        }
      }.width('100%')
      if (this.debugContent.length > 0) {
        Row({ space: 10 }) {
          Text(`正文内容（${this.debugContent.length} 字符）`).fontSize(13)
            .fontColor(this.subTextColor()).layoutWeight(1)
          Button('复制正文', { type: ButtonType.Capsule })
            .height(34).fontSize(12).backgroundColor(this.accentColor()).fontColor('#FFFFFF')
            .onClick(() => this.copyDebugContent())
        }.width('100%')
      }
      if (this.debugSearchLinks.length > 0) {
        Text('搜索链接（点击填入）').fontSize(13).fontWeight(FontWeight.Medium)
          .fontColor(this.primaryTextColor()).width('100%')
        ForEach(this.debugSearchLinks, (url: string) => {
          this.debugLinkItem(url, SourceRuntimeStage.SEARCH)
        }, (url: string) => `search_${url}`)
      }
      if (this.debugExploreLinks.length > 0) {
        Text('发现链接（点击填入）').fontSize(13).fontWeight(FontWeight.Medium)
          .fontColor(this.primaryTextColor()).width('100%')
        ForEach(this.debugExploreLinks, (url: string) => {
          this.debugLinkItem(url, SourceRuntimeStage.EXPLORE)
        }, (url: string) => `explore_${url}`)
      }
      if (this.session.steps.length === 0 && this.session.logs.length === 0) {
        Text('运行后显示请求、规则匹配和错误详情').fontSize(13).fontColor(this.subTextColor()).width('100%')
      }
      ForEach(this.session.steps, (step: BookSourceDebugStep) => {
        this.stepView(step)
      }, (step: BookSourceDebugStep) => `${step.stage}_${step.startedAt}`)
      ForEach(this.session.logs, (log: BookSourceDebugLog) => {
        Text(`[${log.level}] ${log.message}`).fontSize(12).fontColor(this.subTextColor()).width('100%')
          .textSelectable(TextSelectableMode.SELECTABLE_FOCUSABLE)
          .copyOption(CopyOptions.LocalDevice)
      }, (log: BookSourceDebugLog) => `${log.timestamp}_${log.message}`)
    }
    .width('calc(100% - 24vp)').padding(16).borderRadius(16).backgroundColor(this.cardColor())
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  stepView(step: BookSourceDebugStep) {
    Column({ space: 8 }) {
      Row() {
      Text(step.name).fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.primaryTextColor())
          .layoutWeight(1)
        Text(`${step.status} · ${step.elapsedMs}ms`).fontSize(12)
          .fontColor(step.status === 'passed' ? '#20A464' : '#E84040')
      }.width('100%')
      if (step.error) Text(`错误：${step.error}`).fontSize(12).fontColor('#E84040').width('100%')
        .textSelectable(TextSelectableMode.SELECTABLE_FOCUSABLE)
        .copyOption(CopyOptions.LocalDevice)
      ForEach(step.requests, (item: BookSourceDebugNetworkTrace) => {
        Text(`${item.method} ${item.url}\nHTTP ${item.statusCode} · ${item.responseBytes} 字符 · ${item.elapsedMs}ms${item.error ? `\n${item.error}` : ''}`)
          .fontSize(12).fontColor(this.subTextColor()).width('100%')
          .textSelectable(TextSelectableMode.SELECTABLE_FOCUSABLE)
          .copyOption(CopyOptions.LocalDevice)
        if (item.bodyPreview) {
          Text(`响应预览：${item.bodyPreview}`).fontSize(11).fontColor(this.subTextColor())
            .width('100%').maxLines(8)
            .textSelectable(TextSelectableMode.SELECTABLE_FOCUSABLE)
            .copyOption(CopyOptions.LocalDevice)
        }
      }, (item: BookSourceDebugNetworkTrace) => `${item.method}_${item.url}_${item.elapsedMs}`)
      ForEach(step.rules, (item: BookSourceDebugRuleTrace) => {
        Text(`${item.field} [${item.ruleType}] 匹配 ${item.matchedCount}/${item.inputCount} · ${item.elapsedMs}ms\n规则：${item.rule}${item.error ? `\n${item.error}` : ''}${item.outputPreview ? `\n结果：${item.outputPreview}` : ''}`)
          .fontSize(12).fontColor(this.subTextColor()).width('100%')
          .textSelectable(TextSelectableMode.SELECTABLE_FOCUSABLE)
          .copyOption(CopyOptions.LocalDevice)
      }, (item: BookSourceDebugRuleTrace) => `${item.field}_${item.elapsedMs}`)
      ForEach(Object.keys(step.outputs), (key: string) => {
        Text(`${key}：${step.outputs[key]}`).fontSize(
          key.indexOf('正文替换净化前') >= 0 || key.indexOf('正文替换净化后') >= 0 ? 11 : 12)
          .fontColor(this.subTextColor()).width('100%')
          .maxLines(key.indexOf('正文替换净化前') >= 0 || key.indexOf('正文替换净化后') >= 0 ? 14 : 4)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textSelectable(TextSelectableMode.SELECTABLE_FOCUSABLE)
          .copyOption(CopyOptions.LocalDevice)
      }, (key: string) => key)
    }
    .width('100%').padding(12).borderRadius(10).backgroundColor(this.inputColor())
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  debugLinkItem(url: string, stage: string) {
    Text(url).fontSize(11).fontColor(this.accentColor()).width('100%')
      .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
      .onClick(() => this.fillDebugLink(url, stage))
      .textSelectable(TextSelectableMode.SELECTABLE_FOCUSABLE)
      .copyOption(CopyOptions.LocalDevice)
      .padding({ top: 4, bottom: 4 })
  }

  private async loadSource(): Promise<void> {
    if (!this.sourceUrl) return;
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this) as Context);
      const source = await db.getBookSource(this.sourceUrl);
      const draft = AppStorage.get<string>('bookSourceDebugDraftJson') || '';
      if (draft) {
        try {
          const draftSource = JSON.parse(draft) as BookSource;
          if (draftSource.bookSourceUrl === this.sourceUrl) {
            this.source = draftSource;
            return;
          }
        } catch (_) {
        }
      }
      if (source) this.source = source;
      else this.status = '找不到书源';
    } catch (_) {
      this.status = '加载书源失败';
    }
  }

  private async runDebug(): Promise<void> {
    if (this.running) {
      this.coordinator?.cancel();
      this.status = '正在取消';
      return;
    }
    if (!this.source.bookSourceUrl) return;
    this.running = true;
    this.status = '执行中';
    this.debugContent = '';
    this.debugSearchLinks = [];
    this.debugExploreLinks = [];
    const debug = new BookSourceDebugContext(this.source.bookSourceUrl, this.source.bookSourceName, this.stage);
    this.session = debug.session;
    try {
      if (this.stage === SourceRuntimeStage.SEARCH) {
        this.coordinator = new SearchCoordinator(1);
        await this.coordinator.search(this.keyword.trim(), (progress) => {
          this.status = progress.status;
          this.collectDebugLinks(debug.session);
        }, { targetSources: [this.source], validationOnly: false, maxResultsPerSource: 5,
          maxTotalResults: 5, debugContext: debug, onSourceComplete: async (_source, result) => {
            debug.addLog(result.validationStatus === BookSource.VALIDATION_PASSED ? 'info' : 'error',
              result.reason || `返回 ${result.books.length} 本书`);
          } });
      } else if (this.stage === SourceRuntimeStage.EXPLORE) {
        await this.runExploreDebug(debug);
      } else if (this.stage === SourceRuntimeStage.BOOK_INFO) {
        await this.runBookInfoDebug(debug);
      } else if (this.stage === SourceRuntimeStage.TOC) {
        await this.runTocDebug(debug);
      } else if (this.stage === SourceRuntimeStage.CONTENT) {
        await this.runContentDebug(debug);
      } else {
        await this.runFullDebug(debug);
      }
      this.collectDebugLinks(debug.session);
      debug.finish(this.session.steps.some((step: BookSourceDebugStep): boolean => step.status === 'passed') ? 'passed' : 'failed');
      this.publishSession(debug);
    } catch (error) {
      debug.addLog('error', error instanceof Error ? error.message : String(error));
      debug.finish('failed');
      this.collectDebugLinks(debug.session);
      this.publishSession(debug);
      this.status = '执行失败';
    } finally {
      this.running = false;
      this.coordinator = null;
    }
  }

  private async runExploreDebug(debug: BookSourceDebugContext): Promise<void> {
    debug.beginStep(SourceRuntimeStage.EXPLORE, '发现分类');
    const coordinator = new ExploreCoordinator();
    const entries = await coordinator.getEntries('', this.source.bookSourceUrl, debug);
    debug.setOutput('entryCount', String(entries.length));
    debug.finishStep(entries.length > 0 ? 'passed' : 'failed', coordinator.getNoticeMessage());
    if (entries.length === 0) return;
    debug.beginStep(SourceRuntimeStage.EXPLORE, `发现列表：${entries[0].title}`);
    const books = await coordinator.explore(entries[0], 1, 5, debug);
    debug.setOutput('resultCount', String(books.length));
    debug.finishStep(books.length > 0 ? 'passed' : 'failed', coordinator.getNoticeMessage());
  }

  private createDebugBook(): Book {
    const book = new Book();
    book.bookUrl = this.keyword.trim();
    book.tocUrl = this.keyword.trim();
    book.origin = this.source.bookSourceUrl;
    book.originName = this.source.bookSourceName;
    return book;
  }

  private async runBookInfoDebug(debug: BookSourceDebugContext): Promise<void> {
    const book = this.createDebugBook();
    debug.beginStep(SourceRuntimeStage.BOOK_INFO, '书籍详情');
    const result = await new WebBookService().getBookInfo(this.source, book, debug);
    debug.setOutput('name', result.name);
    debug.setOutput('author', result.author);
    debug.setOutput('updateTime', result.updateTime);
    debug.setOutput('tocUrl', result.tocUrl);
    debug.finishStep(result.name || result.tocUrl ? 'passed' : 'failed', result.name ? '' : '详情规则没有提取出书名');
  }

  private async runTocDebug(debug: BookSourceDebugContext): Promise<void> {
    const book = this.createDebugBook();
    debug.beginStep(SourceRuntimeStage.TOC, '书籍目录');
    const chapters = await new WebBookService().getChapterList(this.source, book, 32, false, debug);
    debug.setOutput('chapterCount', String(chapters.length));
    if (chapters.length > 0) {
      debug.setOutput('firstChapter', chapters[0].title);
      debug.setOutput('firstChapterUrl', chapters[0].url);
    }
    debug.finishStep(chapters.length > 0 ? 'passed' : 'failed', chapters.length > 0 ? '' : '目录规则没有提取出章节');
  }

  private async runContentDebug(debug: BookSourceDebugContext): Promise<void> {
    const book = this.createDebugBook();
    const chapter = new BookChapter();
    chapter.url = this.keyword.trim();
    chapter.bookUrl = book.bookUrl;
    chapter.title = '调试章节';
    debug.beginStep(SourceRuntimeStage.CONTENT, '章节正文');
    debug.setOutput('正文替换净化规则', this.source.contentRule.replaceRegex || '未配置');
    const content = await new WebBookService().getContent(this.source, book, chapter, null, debug);
    this.debugContent = content;
    debug.setOutput('contentLength', String(content.length));
    debug.finishStep(content.length > 0 ? 'passed' : 'failed', content.length > 0 ? '' : '正文规则返回空结果');
  }

  private async runFullDebug(debug: BookSourceDebugContext): Promise<void> {
    let candidates: SearchBook[] = [];
    const searchCoordinator = new SearchCoordinator(1);
    candidates = await searchCoordinator.search(this.keyword.trim(), (progress) => {
      this.status = progress.status;
      this.collectDebugLinks(debug.session);
    }, { targetSources: [this.source], maxResultsPerSource: 1, maxTotalResults: 1,
      debugContext: debug });
    if (candidates.length === 0 && !this.source.enabledExplore) {
      debug.addLog('error', '该书源未启用发现，完整链路无法自动取得候选书');
      return;
    }
    if (candidates.length > 0) {
      debug.addLog('info', `搜索阶段取得 ${candidates.length} 本候选书`);
    }
    if (candidates.length === 0) {
    const coordinator = new ExploreCoordinator();
    debug.beginStep(SourceRuntimeStage.EXPLORE, '发现分类');
    const entries = await coordinator.getEntries('', this.source.bookSourceUrl, debug);
    debug.setOutput('entryCount', String(entries.length));
    debug.finishStep(entries.length > 0 ? 'passed' : 'failed', coordinator.getNoticeMessage());
    if (entries.length === 0) return;
    debug.beginStep(SourceRuntimeStage.EXPLORE, `发现列表：${entries[0].title}`);
    candidates = await coordinator.explore(entries[0], 1, 1, debug);
    debug.setOutput('resultCount', String(candidates.length));
    debug.finishStep(candidates.length > 0 ? 'passed' : 'failed', coordinator.getNoticeMessage());
    if (candidates.length === 0) return;
    }
    const book = this.searchBookToBook(candidates[0]);
    debug.beginStep(SourceRuntimeStage.BOOK_INFO, '书籍详情');
    const service = new WebBookService();
    const fullBook = await service.getBookInfo(this.source, book, debug);
    debug.setOutput('name', fullBook.name);
    debug.finishStep(fullBook.name || fullBook.tocUrl ? 'passed' : 'failed',
      fullBook.name || fullBook.tocUrl ? '' : '详情未提取出书籍信息');
    debug.beginStep(SourceRuntimeStage.TOC, '书籍目录');
    const chapters = await service.getChapterList(this.source, fullBook, 32, false, debug);
    debug.setOutput('chapterCount', String(chapters.length));
    debug.finishStep(chapters.length > 0 ? 'passed' : 'failed', chapters.length > 0 ? '' : '目录为空');
    if (chapters.length === 0) return;
    debug.beginStep(SourceRuntimeStage.CONTENT, '章节正文');
    debug.setOutput('正文替换净化规则', this.source.contentRule.replaceRegex || '未配置');
    const content = await service.getContent(this.source, fullBook, chapters[0], null, debug);
    this.debugContent = content;
    debug.setOutput('contentLength', String(content.length));
    debug.finishStep(content.length > 0 ? 'passed' : 'failed', content.length > 0 ? '' : '正文为空');
  }

  private searchBookToBook(item: SearchBook): Book {
    const book = new Book();
    book.bookUrl = item.bookUrl;
    book.tocUrl = item.tocUrl;
    book.origin = item.origin;
    book.originName = item.originName;
    book.name = item.name;
    book.author = item.author;
    book.variable = item.variable;
    return book;
  }

  private syncBars(): void { syncSystemBars(getContext(this) as Context, this.appDarkMode); }

  private collectDebugLinks(session: BookSourceDebugSession): void {
    const searchLinks: string[] = [];
    const exploreLinks: string[] = [];
    for (const step of session.steps) {
      const target = step.stage === SourceRuntimeStage.SEARCH ? searchLinks :
        (step.stage === SourceRuntimeStage.EXPLORE ? exploreLinks : null);
      if (!target) continue;
      for (const request of step.requests) {
        const url = (request.finalUrl || request.url || '').trim();
        if (!url || target.includes(url)) continue;
        target.push(url);
        if (target.length >= 8) break;
      }
    }
    this.debugSearchLinks = searchLinks;
    this.debugExploreLinks = exploreLinks;
  }

  private clearDebugResult(): void {
    this.session = new BookSourceDebugSession();
    this.debugContent = '';
    this.debugSearchLinks = [];
    this.debugExploreLinks = [];
    this.status = '准备就绪';
  }

  private fillDebugLink(url: string, stage: string): void {
    this.keyword = url;
    this.status = `已填入${stage === SourceRuntimeStage.EXPLORE ? '发现' : '搜索'}链接`;
  }

  private async copyDebugContent(): Promise<void> {
    if (this.debugContent.length === 0) {
      HdsFeedback.showToast('暂无可复制的正文内容');
      return;
    }
    const maxCopyLength = 200000;
    const text = this.debugContent.substring(0, maxCopyLength);
    await this.writeClipboardText(text, this.debugContent.length > maxCopyLength ?
      '正文已复制（已截取前 20 万字符）' : '正文已复制');
  }

  private async copyDebugReport(): Promise<void> {
    if (!this.hasDebugReport() && this.debugContent.length === 0) {
      HdsFeedback.showToast('暂无可复制的调试内容');
      return;
    }
    const report = new BookSourceDebugClipboardReport();
    report.sourceName = this.source.bookSourceName;
    report.sourceUrl = this.source.bookSourceUrl || this.sourceUrl;
    report.stage = this.stage;
    report.status = this.status;
    report.session = this.session;
    report.content = this.debugContent;
    const serialized = JSON.stringify(report, null, 2);
    const maxCopyLength = 200000;
    const text = serialized.substring(0, maxCopyLength);
    await this.writeClipboardText(text, serialized.length > maxCopyLength ?
      '调试内容已复制（已截取前 20 万字符）' : '调试内容已复制');
  }

  private async writeClipboardText(text: string, successMessage: string): Promise<void> {
    try {
      const board = pasteboard.getSystemPasteboard();
      await board.setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text));
      HdsFeedback.showToast(successMessage);
    } catch (error) {
      console.error('复制调试内容失败:', error);
      HdsFeedback.showToast('复制失败，请稍后重试');
    }
  }
  private publishSession(debug: BookSourceDebugContext): void {
    this.session = JSON.parse(JSON.stringify(debug.session)) as BookSourceDebugSession;
  }
  private hasDebugReport(): boolean {
    return this.session.steps.length > 0 || this.session.logs.length > 0;
  }

  private async exportDebugReport(): Promise<void> {
    if (!this.hasDebugReport()) {
      HdsFeedback.showToast('请先运行一次调试');
      return;
    }
    if (this.exporting) return;
    let file: fs.File | null = null;
    this.exporting = true;
    try {
      const options: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
      options.newFileNames = [`legado_book_source_debug_${this.exportTimestamp()}.json`];
      options.fileSuffixChoices = ['JSON 文件|.json'];
      const result = await new picker.DocumentViewPicker(getContext(this)).save(options);
      if (!result || result.length === 0) return;
      const session = JSON.parse(JSON.stringify(this.session)) as BookSourceDebugSession;
      session.sourceUrl = BookSourceDebugRedactor.url(session.sourceUrl);
      session.sourceName = BookSourceDebugRedactor.url(session.sourceName || session.sourceUrl);
      const report = new BookSourceDebugExportReport();
      report.exportedAt = new Date().toISOString();
      report.sourceUrl = BookSourceDebugRedactor.url(this.source.bookSourceUrl || this.sourceUrl);
      report.sourceName = this.source.bookSourceName || BookSourceDebugRedactor.url(session.sourceName);
      report.stage = this.stage;
      report.session = session;
      const json = JSON.stringify(report, null, 2);
      const bytes = new util.TextEncoder().encodeInto(json);
      file = await fs.open(result[0], fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      await fs.write(file.fd, bytes.buffer, { offset: 0, length: bytes.byteLength });
      await fs.close(file);
      file = null;
      HdsFeedback.showToast('调试报告已导出');
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error || '未知错误');
      HdsFeedback.showToast(`导出失败：${message}`);
    } finally {
      if (file) {
        try { await fs.close(file); } catch (_) {}
      }
      this.exporting = false;
    }
  }

  private exportTimestamp(): string {
    const now = new Date();
    const pad = (value: number): string => value.toString().padStart(2, '0');
    return `${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}_` +
      `${pad(now.getHours())}${pad(now.getMinutes())}${pad(now.getSeconds())}`;
  }

  private registerKeyboardAvoidance(): void {
    window.getLastWindow(getContext(this)).then((mainWindow: window.Window): void => {
      if (this.keyboardWindow === mainWindow) {
        this.refreshKeyboardInset(mainWindow);
        return;
      }
      if (this.keyboardWindow) {
        try { this.keyboardWindow.off('avoidAreaChange', this.keyboardAvoidAreaCallback); } catch (_) {}
      }
      this.keyboardWindow = mainWindow;
      mainWindow.on('avoidAreaChange', this.keyboardAvoidAreaCallback);
      this.refreshKeyboardInset(mainWindow);
    }).catch((error: Error): void => {
      console.warn('注册调试页键盘避让监听失败:', error.message);
    });
  }

  private unregisterKeyboardAvoidance(): void {
    if (this.keyboardWindow) {
      try { this.keyboardWindow.off('avoidAreaChange', this.keyboardAvoidAreaCallback); } catch (_) {}
    }
    this.keyboardWindow = null;
    this.keyboardInset = 0;
  }

  private refreshKeyboardInset(mainWindow: window.Window): void {
    try {
      const area = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_KEYBOARD);
      this.keyboardInset = this.keyboardAvoidAreaHeight(area);
    } catch (_) {
      this.keyboardInset = 0;
    }
  }

  private keyboardAvoidAreaHeight(area: window.AvoidArea): number {
    return px2vp(Math.max(0, area.bottomRect.height));
  }

  private pageColor(): string { return ThemeRuntime.pageColor(this.appDarkMode); }
  private cardColor(): string { return ThemeRuntime.glassPanelColor(this.appDarkMode, '', 'panel'); }
  private inputColor(): string { return this.appDarkMode ? '#252525' : '#F2F3F5'; }
  private primaryTextColor(): string { return this.appDarkMode ? '#F5F5F5' : '#1F2329'; }
  private subTextColor(): string { return this.appDarkMode ? '#B8B8B8' : '#697586'; }
  private accentColor(): string { return ThemeRuntime.accentColor(this.appDarkMode); }
  private stageInputPlaceholder(): string {
    if (this.stage === SourceRuntimeStage.SEARCH || this.stage === 'full') return '输入测试关键词';
    if (this.stage === SourceRuntimeStage.EXPLORE) return '输入关键词（发现阶段将使用第一个分类）';
    if (this.stage === SourceRuntimeStage.CONTENT) return '输入章节 URL';
    return '输入书籍或目录 URL';
  }
}
