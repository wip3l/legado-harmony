import { router } from '@kit.ArkUI';
import { Context } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { LengthMetrics } from '@ohos.arkui.node';
import picker from '@ohos.file.picker';
import fs from '@ohos.file.fs';
import { AppDatabase } from '../model/data/AppDatabase';
import { BookSource } from '../model/data/Book';
import { ImmersiveBackButton } from '../components/ImmersiveBackButton';
import { QuickJsRegressionIssueCategory, QuickJsRegressionItemResult, QuickJsRegressionProgress,
  QuickJsRegressionReport, QuickJsRegressionRunner, QuickJsRegressionStage, QuickJsRegressionStatus }
  from '../core/script/QuickJsRegressionRunner';
import { QuickJsRegressionArtifactSnapshot, QuickJsRegressionArtifactStore,
  QuickJsRegressionFixtureRecord } from '../core/script/QuickJsRegressionArtifacts';
import { QuickJsMigrationStore } from '../core/script/QuickJsMigrationStore';
import { QuickJsRuntimeMode } from '../core/script/QuickJsRuntimeStatus';
import { QuickJsShadowComparator } from '../core/script/QuickJsScriptRuntime';
import { QuickJsValidationCandidate, QuickJsValidationSeed, QuickJsValidationSnapshot,
  QuickJsValidationStore } from '../core/script/QuickJsValidationStore';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { syncSystemBars } from '../utils/SystemBars';
import { HdsFeedback } from '../utils/HdsFeedback';

class QuickJsCategoryStat {
  category: string = '';
  count: number = 0;

  constructor(category: string, count: number) {
    this.category = category;
    this.count = count;
  }
}

@Entry
@Component
struct QuickJsRegressionPage {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @StorageLink('quickJsValidationRevision') @Watch('onValidationRevisionChanged')
  quickJsValidationRevision: number = 0;
  @StorageLink('quickJsMigrationRevision') @Watch('onValidationRevisionChanged')
  quickJsMigrationRevision: number = 0;
  @State sources: BookSource[] = [];
  @State selectedSourceUrls: string[] = [];
  @State selectedStages: string[] = QuickJsRegressionStage.all();
  @State activeGroup: string = '__all__';
  @State searchText: string = '';
  @State isLoading: boolean = true;
  @State isRunning: boolean = false;
  @State progressCompleted: number = 0;
  @State progressTotal: number = 0;
  @State progressText: string = '';
  @State report: QuickJsRegressionReport = new QuickJsRegressionReport();
  @State resultFilter: string = 'issues';
  @State validationSnapshot: QuickJsValidationSnapshot = new QuickJsValidationSnapshot();
  @State artifactSnapshot: QuickJsRegressionArtifactSnapshot = new QuickJsRegressionArtifactSnapshot();
  @State migrationMode: string = QuickJsRuntimeMode.SHADOW;
  @State isExporting: boolean = false;
  private runner: QuickJsRegressionRunner = new QuickJsRegressionRunner();

  aboutToAppear(): void {
    this.syncBars();
    QuickJsValidationStore.initialize(getContext(this) as Context)
      .then((): void => this.refreshValidation()).catch((): void => {});
    QuickJsRegressionArtifactStore.initialize(getContext(this) as Context)
      .then((): void => this.refreshArtifacts()).catch((): void => {});
    this.loadSources();
  }

  onPageShow(): void { this.syncBars(); this.refreshValidation(); }

  aboutToDisappear(): void { this.runner.cancel(); }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Scroll() {
        Column({ space: 12 }) {
          this.explanationCard()
          this.stageCard()
          this.sourceCard()
          this.actionCard()
          if (this.validationSnapshot.candidates.length > 0) this.validationCard()
          if (this.artifactSnapshot.fixtures.length > 0) this.artifactCard()
          if (this.report.completedCandidates > 0 || this.report.error) this.reportCard()
        }
        .width('100%')
        .padding({ top: 68 + this.statusBarHeight, bottom: 32 + this.navBarHeight })
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
  explanationCard() {
    Column({ space: 6 }) {
      Text('本地只读回归')
        .fontSize(16).fontWeight(FontWeight.Medium).fontColor(this.primaryTextColor())
      Text('从所选书源提取安全纯表达式，以数值、文本和 JSON 三组固定输入对比 Legacy 与 TaskPool QuickJS。不会发起网络请求，也不会读取或修改 Cookie、登录信息和书源变量。')
        .fontSize(12).fontColor(this.subTextColor()).lineHeight(19)
    }
    .width('calc(100% - 24vp)').padding(16).borderRadius(16)
    .backgroundColor(this.cardColor()).alignItems(HorizontalAlign.Start)
  }

  @Builder
  stageCard() {
    Column({ space: 10 }) {
      Text('执行阶段').fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.primaryTextColor())
        .width('100%')
      Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(8) } }) {
        ForEach(QuickJsRegressionStage.all(), (stage: string) => {
          Button(QuickJsRegressionStage.label(stage))
            .type(ButtonType.Capsule)
            .fontSize(13)
            .fontColor(this.selectedStages.includes(stage) ? '#FFFFFF' : this.primaryTextColor())
            .backgroundColor(this.selectedStages.includes(stage) ? this.accentColor() : this.softColor())
            .height(34)
            .padding({ left: 16, right: 16 })
            .onClick((): void => this.toggleStage(stage))
        }, (stage: string): string => stage)
      }.width('100%')
    }
    .width('calc(100% - 24vp)').padding(16).borderRadius(16)
    .backgroundColor(this.cardColor()).alignItems(HorizontalAlign.Start)
  }

  @Builder
  sourceCard() {
    Column({ space: 10 }) {
      Row() {
        Text(`书源（已选 ${this.selectedSourceUrls.length}）`)
          .fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.primaryTextColor())
        Blank()
        Text('选择当前')
          .fontSize(13).fontColor(this.accentColor()).padding(8)
          .onClick((): void => this.selectVisibleSources())
        Text('清空')
          .fontSize(13).fontColor(this.subTextColor()).padding(8)
          .onClick((): void => { if (!this.isRunning) this.selectedSourceUrls = []; })
      }.width('100%')

      TextInput({ text: this.searchText, placeholder: '搜索书源名称或地址' })
        .height(42).fontSize(14).fontColor(this.primaryTextColor())
        .placeholderColor(this.subTextColor()).backgroundColor(this.softColor())
        .borderRadius(12).padding({ left: 12, right: 12 })
        .onChange((value: string): void => { this.searchText = value; })

      Scroll() {
        Row({ space: 8 }) {
          this.groupChip('__all__', '全部')
          ForEach(this.groups(), (group: string) => this.groupChip(group, group),
            (group: string): string => group)
        }.padding({ right: 8 })
      }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')

      if (this.isLoading) {
        Row() { LoadingProgress().width(28).height(28) }.height(160).justifyContent(FlexAlign.Center).width('100%')
      } else if (this.visibleSources().length === 0) {
        Text('没有匹配的书源').fontSize(14).fontColor(this.subTextColor())
          .height(120).width('100%').textAlign(TextAlign.Center)
      } else {
        List({ space: 0 }) {
          ForEach(this.visibleSources(), (source: BookSource) => {
            ListItem() { this.sourceRow(source) }
          }, (source: BookSource): string => source.bookSourceUrl)
        }
        .height(280).width('100%').scrollBar(BarState.Auto)
        if (this.filteredSources().length > 100) {
          Text(`当前仅显示前 100 个匹配项，共 ${this.filteredSources().length} 个；可通过搜索缩小范围`)
            .fontSize(11).fontColor(this.subTextColor()).width('100%')
        }
      }
    }
    .width('calc(100% - 24vp)').padding(16).borderRadius(16)
    .backgroundColor(this.cardColor()).alignItems(HorizontalAlign.Start)
  }

  @Builder
  groupChip(group: string, label: string) {
    Button(label)
      .type(ButtonType.Capsule).height(32).fontSize(12)
      .fontColor(this.activeGroup === group ? '#FFFFFF' : this.primaryTextColor())
      .backgroundColor(this.activeGroup === group ? this.accentColor() : this.softColor())
      .padding({ left: 14, right: 14 })
      .onClick((): void => { this.activeGroup = group; })
  }

  @Builder
  sourceRow(source: BookSource) {
    Row({ space: 10 }) {
      Toggle({ type: ToggleType.Checkbox, isOn: this.selectedSourceUrls.includes(source.bookSourceUrl) })
        .selectedColor(this.accentColor()).hitTestBehavior(HitTestMode.None)
      Column({ space: 3 }) {
        Text(source.bookSourceName || source.bookSourceUrl)
          .fontSize(14).fontColor(this.primaryTextColor()).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(source.bookSourceGroup || source.bookSourceUrl)
          .fontSize(11).fontColor(this.subTextColor()).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
    }
    .width('100%').height(58).padding({ left: 4, right: 4 })
    .border({ width: { bottom: 0.5 }, color: this.dividerColor() })
    .onClick((): void => this.toggleSource(source.bookSourceUrl))
  }

  @Builder
  actionCard() {
    Column({ space: 10 }) {
      if (this.isRunning) {
        Row() {
          Text(this.progressText || '正在准备…').fontSize(13).fontColor(this.primaryTextColor()).layoutWeight(1)
          Text(`${this.progressCompleted}/${this.progressTotal}`).fontSize(12).fontColor(this.subTextColor())
        }.width('100%')
        Progress({ value: this.progressCompleted, total: Math.max(1, this.progressTotal), type: ProgressType.Linear })
          .color(this.accentColor()).width('100%')
      }
      Button(this.isRunning ? '停止测试' : '开始回归测试')
        .type(ButtonType.Capsule).height(44).width('100%').fontSize(15)
        .fontColor('#FFFFFF').backgroundColor(this.isRunning ? '#D44848' : this.accentColor())
        .onClick((): void => { if (this.isRunning) this.runner.cancel(); else this.startRegression(); })
      Text('单次最多测试 50 个书源、300 个候选表达式；超出部分会在报告中标记。')
        .fontSize(11).fontColor(this.subTextColor()).width('100%')
    }
    .width('calc(100% - 24vp)').padding(16).borderRadius(16)
    .backgroundColor(this.cardColor()).alignItems(HorizontalAlign.Start)
  }

  @Builder
  validationCard() {
    Column({ space: 10 }) {
      Row() {
        Text('真实影子验证').fontSize(16).fontWeight(FontWeight.Medium).fontColor(this.primaryTextColor())
        Blank()
        Text(this.validationSnapshot.active ? '验证进行中' :
          (this.migrationMode === QuickJsRuntimeMode.CANARY ? '灰度接管中' : '未运行'))
          .fontSize(12)
          .fontColor(this.validationSnapshot.active ? '#20A464' : this.subTextColor())
      }.width('100%')
      Row() {
        this.statItem('待验证', this.pendingValidationCount(), '#E89725')
        this.statItem('灰度合格', this.qualifiedValidationCount(), '#20A464')
        this.statItem('存在问题', this.validationIssueCount(), '#E84040')
        this.statItem('仅离线', this.offlineOnlyValidationCount(), this.subTextColor())
      }.width('100%')
      Text(this.validationSnapshot.active ?
        '请返回应用正常搜索、浏览发现、打开详情、目录和正文。匹配的表达式会用真实上下文后台对比，旧引擎结果仍然生效。' :
        `离线一致项需累计 ${QuickJsValidationStore.REAL_MATCH_THRESHOLD} 次真实一致且零差异、零失败，才能进入灰度接管。`)
        .fontSize(12).fontColor(this.subTextColor()).lineHeight(19).width('100%')
      Row({ space: 10 }) {
        Button(this.validationSnapshot.active ? '停止真实验证' : '开始真实验证')
          .type(ButtonType.Capsule).height(42).layoutWeight(1).fontSize(14)
          .fontColor('#FFFFFF')
          .backgroundColor(this.validationSnapshot.active ? '#D44848' : this.accentColor())
          .enabled(this.validationSnapshot.active || this.routableValidationCount() > 0)
          .onClick((): void => { this.toggleRealValidation().catch((): void => {}); })
        Button(this.migrationMode === QuickJsRuntimeMode.CANARY ? '已开启灰度' : '开启灰度接管')
          .type(ButtonType.Capsule).height(42).layoutWeight(1).fontSize(14)
          .fontColor(this.qualifiedValidationCount() > 0 ? '#FFFFFF' : this.subTextColor())
          .backgroundColor(this.qualifiedValidationCount() > 0 ? '#20A464' : this.softColor())
          .enabled(this.qualifiedValidationCount() > 0 && this.migrationMode !== QuickJsRuntimeMode.CANARY)
          .onClick((): void => { this.enableCanary().catch((): void => {}); })
      }.width('100%')
      if (this.validationCandidatesForDisplay().length > 0) {
        List({ space: 6 }) {
          ForEach(this.validationCandidatesForDisplay(), (item: QuickJsValidationCandidate) => {
            ListItem() { this.validationCandidateRow(item) }
          }, (item: QuickJsValidationCandidate): string =>
            `${item.sourceUrl}-${item.stage}-${item.field}-${item.fingerprint}`)
        }
        .height(Math.min(280, this.validationCandidatesForDisplay().length * 66))
        .width('100%').scrollBar(BarState.Auto)
      }
    }
    .width('calc(100% - 24vp)').padding(16).borderRadius(16)
    .backgroundColor(this.cardColor()).alignItems(HorizontalAlign.Start)
  }

  @Builder
  validationCandidateRow(item: QuickJsValidationCandidate) {
    Row({ space: 10 }) {
      Column({ space: 3 }) {
        Text(`${item.sourceName} · ${QuickJsRegressionStage.label(item.stage)} · ${item.field}`)
          .fontSize(13).fontColor(this.primaryTextColor()).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(item.routable ?
          `${item.fingerprint} · 一致 ${item.realMatches} / ${QuickJsValidationStore.REAL_MATCH_THRESHOLD}` :
          `${item.fingerprint} · 当前同步表达式不参与接管`)
          .fontSize(11).fontColor(this.subTextColor()).maxLines(1)
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Text(this.validationCandidateStatus(item)).fontSize(11)
        .fontColor(this.validationCandidateColor(item))
    }
    .width('100%').height(60).padding({ left: 10, right: 10 })
    .borderRadius(10).backgroundColor(this.softColor())
  }

  @Builder
  artifactCard() {
    Column({ space: 10 }) {
      Row() {
        Text('兼容性问题夹具').fontSize(16).fontWeight(FontWeight.Medium).fontColor(this.primaryTextColor())
        Blank()
        Text(`${this.unresolvedArtifactCount()} 待处理 · ${this.resolvedArtifactCount()} 已修复`)
          .fontSize(12).fontColor(this.subTextColor())
      }.width('100%')
      if (this.artifactCategoryStats().length > 0) {
        Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(8) } }) {
          ForEach(this.artifactCategoryStats(), (item: QuickJsCategoryStat) => {
            Text(`${QuickJsRegressionIssueCategory.label(item.category)} ${item.count}`)
              .fontSize(11).fontColor(this.issueCategoryColor(item.category))
              .padding({ left: 10, right: 10, top: 6, bottom: 6 })
              .borderRadius(12).backgroundColor(this.softColor())
          }, (item: QuickJsCategoryStat): string => item.category)
        }.width('100%')
      } else {
        Text('已保存的问题用例均已通过复测').fontSize(12).fontColor('#20A464').width('100%')
      }
      if (this.unresolvedArtifactsForDisplay().length > 0) {
        List({ space: 6 }) {
          ForEach(this.unresolvedArtifactsForDisplay(), (item: QuickJsRegressionFixtureRecord) => {
            ListItem() {
              Row({ space: 8 }) {
                Column({ space: 3 }) {
                  Text(`${item.sourceName} · ${QuickJsRegressionStage.label(item.stage)} · ${item.field}`)
                    .fontSize(12).fontColor(this.primaryTextColor()).maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(`${item.fingerprint}${item.fixture ? ` · ${item.fixture}` : ''}`)
                    .fontSize(10).fontColor(this.subTextColor()).maxLines(1)
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                Text(QuickJsRegressionIssueCategory.label(item.errorCategory))
                  .fontSize(10).fontColor(this.issueCategoryColor(item.errorCategory))
              }
              .width('100%').height(52).padding({ left: 10, right: 10 })
              .borderRadius(10).backgroundColor(this.softColor())
            }
          }, (item: QuickJsRegressionFixtureRecord): string =>
            `${item.sourceUrl}-${item.stage}-${item.field}-${item.fingerprint}`)
        }.height(Math.min(244, this.unresolvedArtifactsForDisplay().length * 58)).width('100%')
          .scrollBar(BarState.Auto)
      }
      Row({ space: 10 }) {
        Button(this.isRunning ? '正在复测…' : `重跑问题用例 (${this.unresolvedArtifactCount()})`)
          .type(ButtonType.Capsule).height(42).layoutWeight(1).fontSize(13)
          .fontColor(this.unresolvedArtifactCount() > 0 && !this.isRunning ? '#FFFFFF' : this.subTextColor())
          .backgroundColor(this.unresolvedArtifactCount() > 0 && !this.isRunning ? this.accentColor() : this.softColor())
          .enabled(this.unresolvedArtifactCount() > 0 && !this.isRunning)
          .onClick((): void => { this.rerunIssueFixtures().catch((): void => {}); })
        Button(this.isExporting ? '正在导出…' : '导出脱敏报告')
          .type(ButtonType.Capsule).height(42).layoutWeight(1).fontSize(13)
          .fontColor(!this.isExporting ? this.primaryTextColor() : this.subTextColor())
          .backgroundColor(this.softColor()).enabled(!this.isExporting)
          .onClick((): void => { this.exportRegressionReport().catch((): void => {}); })
      }.width('100%')
      Text('精确脚本仅保存在应用私有目录，用于后续版本复测；导出文件会移除 Cookie、URL 参数、原始结果和脚本文本字面量。')
        .fontSize(11).fontColor(this.subTextColor()).lineHeight(17).width('100%')
    }
    .width('calc(100% - 24vp)').padding(16).borderRadius(16)
    .backgroundColor(this.cardColor()).alignItems(HorizontalAlign.Start)
  }

  @Builder
  reportCard() {
    Column({ space: 10 }) {
      Row() {
        Text('回归报告').fontSize(16).fontWeight(FontWeight.Medium).fontColor(this.primaryTextColor())
        Blank()
        if (this.report.elapsedMs > 0) {
          Text(`${this.report.elapsedMs} ms`).fontSize(12).fontColor(this.subTextColor())
        }
      }.width('100%')
      if (this.report.error) {
        Text(this.report.error).fontSize(13).fontColor('#E84040').width('100%')
      } else {
        Row() {
          this.statItem('一致', this.report.matchCount, '#20A464')
          this.statItem('差异', this.report.mismatchCount, '#E89725')
          this.statItem('失败', this.report.failureCount, '#E84040')
          this.statItem('退出迁移', this.report.excludedCount, this.subTextColor())
        }.width('100%')
        if (this.report.truncatedCount > 0) {
          Text(`另有 ${this.report.truncatedCount} 个候选因数量上限未测试`)
            .fontSize(11).fontColor(this.subTextColor()).width('100%')
        }
        if (this.currentReportCategoryStats().length > 0) {
          Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(8) } }) {
            ForEach(this.currentReportCategoryStats(), (item: QuickJsCategoryStat) => {
              Text(`${QuickJsRegressionIssueCategory.label(item.category)} ${item.count}`)
                .fontSize(11).fontColor(this.issueCategoryColor(item.category))
                .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                .borderRadius(12).backgroundColor(this.softColor())
            }, (item: QuickJsCategoryStat): string => item.category)
          }.width('100%')
        }
        Row({ space: 8 }) {
          this.filterChip('issues', '仅问题')
          this.filterChip('all', '全部结果')
        }.width('100%')
        if (this.visibleResults().length === 0) {
          Text(this.resultFilter === 'issues' ? '没有发现差异或执行失败' : '暂无结果')
            .fontSize(13).fontColor(this.subTextColor()).height(90).width('100%').textAlign(TextAlign.Center)
        } else {
          List({ space: 8 }) {
            ForEach(this.visibleResults(), (item: QuickJsRegressionItemResult, index: number) => {
              ListItem() { this.resultRow(item) }
            }, (item: QuickJsRegressionItemResult, index: number): string =>
              `${item.sourceUrl}-${item.stage}-${item.field}-${item.fingerprint}-${index}`)
          }.height(Math.min(360, this.visibleResults().length * 112)).width('100%').scrollBar(BarState.Auto)
        }
      }
    }
    .width('calc(100% - 24vp)').padding(16).borderRadius(16)
    .backgroundColor(this.cardColor()).alignItems(HorizontalAlign.Start)
  }

  @Builder
  statItem(label: string, value: number, color: string) {
    Column({ space: 3 }) {
      Text(`${value}`).fontSize(19).fontWeight(FontWeight.Bold).fontColor(color)
      Text(label).fontSize(11).fontColor(this.subTextColor())
    }.layoutWeight(1)
  }

  @Builder
  filterChip(filter: string, label: string) {
    Button(label).type(ButtonType.Capsule).height(30).fontSize(12)
      .fontColor(this.resultFilter === filter ? '#FFFFFF' : this.primaryTextColor())
      .backgroundColor(this.resultFilter === filter ? this.accentColor() : this.softColor())
      .onClick((): void => { this.resultFilter = filter; })
  }

  @Builder
  resultRow(item: QuickJsRegressionItemResult) {
    Column({ space: 4 }) {
      Row() {
        Text(`${QuickJsRegressionStage.label(item.stage)} · ${item.field}`)
          .fontSize(13).fontWeight(FontWeight.Medium).fontColor(this.primaryTextColor()).layoutWeight(1)
        Text(this.resultStatusLabel(item)).fontSize(11).fontColor(this.resultStatusColor(item))
      }.width('100%')
      Text(`${item.sourceName} · ${item.fingerprint}${item.fixture ? ` · ${item.fixture}` : ''}`)
        .fontSize(11).fontColor(this.subTextColor()).maxLines(1)
      Text(item.expressionPreview)
        .fontSize(11).fontColor(this.subTextColor()).maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (item.status === QuickJsRegressionStatus.MISMATCH) {
        Text(`Legacy: ${item.legacyPreview}  |  QuickJS: ${item.quickPreview}`)
          .fontSize(11).fontColor(this.subTextColor()).maxLines(2)
      } else if (item.error) {
        Text(item.error).fontSize(11).fontColor('#E84040').maxLines(2)
      }
      if (item.errorCategory && item.errorCategory !== QuickJsRegressionIssueCategory.NONE) {
        Text(`分类：${QuickJsRegressionIssueCategory.label(item.errorCategory)}`)
          .fontSize(10).fontColor(this.issueCategoryColor(item.errorCategory))
      }
    }.width('100%').padding(10).borderRadius(10).backgroundColor(this.softColor())
      .alignItems(HorizontalAlign.Start)
  }

  @Builder
  titleBar() {
    Row() {
      ImmersiveBackButton({ iconColor: this.primaryTextColor(), darkMode: this.appDarkMode,
        buttonSize: 40, containerWidth: 56, materialScale: 0.83, compactLayout: true,
        onBack: () => router.back() })
      Text('书源脚本回归测试').fontSize(20).fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor()).layoutWeight(1)
    }
    .width('100%').height(56 + this.statusBarHeight).padding({ top: this.statusBarHeight })
    .backgroundColor(ThemeRuntime.topBarColor(this.appDarkMode)).backdropBlur(ThemeRuntime.topBarBlur())
    .alignItems(VerticalAlign.Center)
  }

  private async loadSources(): Promise<void> {
    this.isLoading = true;
    try { this.sources = await AppDatabase.getInstance().getBookSourceSummaries(); }
    catch (_) { this.sources = []; }
    this.isLoading = false;
  }

  private async startRegression(): Promise<void> {
    if (this.selectedSourceUrls.length === 0) {
      HdsFeedback.showToast('请至少选择一个书源'); return;
    }
    if (this.selectedStages.length === 0) {
      HdsFeedback.showToast('请至少选择一个执行阶段'); return;
    }
    const selectedUrls = this.selectedSourceUrls.slice(0, 50);
    const selectedSources: BookSource[] = [];
    this.isRunning = true;
    this.report = new QuickJsRegressionReport();
    this.progressCompleted = 0;
    this.progressTotal = 0;
    this.progressText = '正在加载完整书源规则…';
    try {
      for (const url of selectedUrls) {
        const source = await AppDatabase.getInstance().getBookSource(url);
        if (source) selectedSources.push(source);
      }
      const report = await this.runner.run(selectedSources, this.selectedStages,
        (progress: QuickJsRegressionProgress): void => {
          this.progressCompleted = progress.completed;
          this.progressTotal = progress.total;
          this.progressText = `${progress.sourceName} · ${progress.field}`;
        });
      this.report = report;
      if (!report.error && report.items.length > 0) {
        await this.saveRegressionForValidation(report);
        await QuickJsRegressionArtifactStore.mergeReport(getContext(this) as Context, report);
        this.refreshArtifacts();
      }
      if (report.totalCandidates === 0 && !report.error) {
        HdsFeedback.showToast('所选范围没有符合安全边界的表达式');
      }
    } catch (error) {
      const failed = new QuickJsRegressionReport();
      failed.error = error instanceof Error ? error.message : String(error || '回归测试失败');
      this.report = failed;
    } finally {
      this.isRunning = false;
      this.progressText = '';
    }
  }

  private filteredSources(): BookSource[] {
    const keyword = this.searchText.trim().toLowerCase();
    return this.sources.filter((source: BookSource): boolean => {
      if (this.activeGroup !== '__all__' && source.bookSourceGroup !== this.activeGroup) return false;
      if (!keyword) return true;
      return `${source.bookSourceName}\n${source.bookSourceUrl}`.toLowerCase().includes(keyword);
    });
  }

  private visibleSources(): BookSource[] { return this.filteredSources().slice(0, 100); }

  private groups(): string[] {
    const values: string[] = [];
    for (const source of this.sources) {
      const group = (source.bookSourceGroup || '').trim();
      if (group && !values.includes(group)) values.push(group);
    }
    return values.sort((a: string, b: string): number => a.localeCompare(b));
  }

  private selectVisibleSources(): void {
    if (this.isRunning) return;
    const selected = this.selectedSourceUrls.slice();
    let truncated = false;
    for (const source of this.filteredSources()) {
      if (selected.includes(source.bookSourceUrl)) continue;
      if (selected.length >= 50) { truncated = true; break; }
      selected.push(source.bookSourceUrl);
    }
    this.selectedSourceUrls = selected;
    if (truncated) HdsFeedback.showToast('单次最多选择 50 个书源');
  }

  private toggleSource(url: string): void {
    if (this.isRunning) return;
    if (this.selectedSourceUrls.includes(url)) {
      this.selectedSourceUrls = this.selectedSourceUrls.filter((value: string): boolean => value !== url);
      return;
    }
    if (this.selectedSourceUrls.length >= 50) {
      HdsFeedback.showToast('单次最多选择 50 个书源');
      return;
    }
    this.selectedSourceUrls = [...this.selectedSourceUrls, url];
  }

  private toggleStage(stage: string): void {
    if (this.isRunning) return;
    this.selectedStages = this.selectedStages.includes(stage) ?
      this.selectedStages.filter((value: string): boolean => value !== stage) :
      [...this.selectedStages, stage];
  }

  private visibleResults(): QuickJsRegressionItemResult[] {
    const values = this.resultFilter === 'issues' ?
      this.report.items.filter((item: QuickJsRegressionItemResult): boolean =>
        item.status !== QuickJsRegressionStatus.MATCH &&
        item.status !== QuickJsRegressionStatus.EXCLUDED) : this.report.items;
    return values.slice(0, 100);
  }

  private async rerunIssueFixtures(): Promise<void> {
    const cases = QuickJsRegressionArtifactStore.replayCases();
    if (cases.length === 0) {
      HdsFeedback.showToast('当前没有待复测的问题用例');
      return;
    }
    this.isRunning = true;
    this.report = new QuickJsRegressionReport();
    this.progressCompleted = 0;
    this.progressTotal = cases.length;
    this.progressText = '正在加载问题夹具…';
    try {
      const report = await this.runner.rerun(cases, (progress: QuickJsRegressionProgress): void => {
        this.progressCompleted = progress.completed;
        this.progressTotal = progress.total;
        this.progressText = `${progress.sourceName} · ${progress.field}`;
      });
      this.report = report;
      if (!report.error && report.items.length > 0) {
        await QuickJsRegressionArtifactStore.mergeReport(getContext(this) as Context, report);
        await this.removeExcludedValidationCandidates(report);
        this.refreshArtifacts();
      }
      if (!report.error) {
        HdsFeedback.showToast(`复测完成：${report.matchCount} 个已通过，${report.excludedCount} 个退出迁移，` + `${report.mismatchCount + report.failureCount} 个仍有问题`);
      }
    } catch (error) {
      const failed = new QuickJsRegressionReport();
      failed.error = error instanceof Error ? error.message : String(error || '问题用例复测失败');
      this.report = failed;
    } finally {
      this.isRunning = false;
      this.progressText = '';
    }
  }

  private async removeExcludedValidationCandidates(report: QuickJsRegressionReport): Promise<void> {
    const seeds: QuickJsValidationSeed[] = [];
    for (const item of report.items) {
      if (item.status !== QuickJsRegressionStatus.EXCLUDED) continue;
      const seed = new QuickJsValidationSeed();
      seed.sourceUrl = item.sourceUrl;
      seed.sourceName = item.sourceName;
      seed.stage = item.stage;
      seed.field = item.field;
      seed.fingerprint = item.fingerprint;
      seeds.push(seed);
    }
    if (seeds.length === 0) return;
    await QuickJsValidationStore.removeRegressionCandidates(getContext(this) as Context, seeds);
    this.refreshValidation();
  }

  private async exportRegressionReport(): Promise<void> {
    let file: fs.File | null = null;
    this.isExporting = true;
    try {
      await QuickJsRegressionArtifactStore.initialize(getContext(this) as Context);
      const options: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
      options.newFileNames = [`quickjs_regression_${this.exportTimestamp()}.json`];
      options.fileSuffixChoices = ['JSON 文件|.json'];
      const result = await new picker.DocumentViewPicker(getContext(this)).save(options);
      if (!result || result.length === 0) return;
      const json = QuickJsRegressionArtifactStore.buildExportJson(this.report);
      const bytes = new util.TextEncoder().encodeInto(json);
      file = await fs.open(result[0], fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      await fs.write(file.fd, bytes.buffer, { offset: 0, length: bytes.byteLength });
      await fs.close(file);
      file = null;
      HdsFeedback.showToast('脱敏回归报告已导出');
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error || '未知错误');
      HdsFeedback.showToast(`导出失败：${message}`);
    } finally {
      if (file) {
        try { await fs.close(file); } catch (_) {}
      }
      this.isExporting = false;
    }
  }

  private exportTimestamp(): string {
    const now = new Date();
    const pad = (value: number): string => value.toString().padStart(2, '0');
    return `${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}_` +
      `${pad(now.getHours())}${pad(now.getMinutes())}`;
  }

  private refreshArtifacts(): void {
    this.artifactSnapshot = QuickJsRegressionArtifactStore.snapshot();
  }

  private unresolvedArtifactCount(): number {
    return this.artifactSnapshot.fixtures.filter(
      (item: QuickJsRegressionFixtureRecord): boolean => !item.resolved).length;
  }

  private resolvedArtifactCount(): number {
    return this.artifactSnapshot.fixtures.filter(
      (item: QuickJsRegressionFixtureRecord): boolean => item.resolved).length;
  }

  private unresolvedArtifactsForDisplay(): QuickJsRegressionFixtureRecord[] {
    return this.artifactSnapshot.fixtures.filter(
      (item: QuickJsRegressionFixtureRecord): boolean => !item.resolved).slice(0, 12);
  }

  private artifactCategoryStats(): QuickJsCategoryStat[] {
    const counts: Record<string, number> = {};
    for (const item of this.artifactSnapshot.fixtures) {
      if (item.resolved) continue;
      const category = item.errorCategory || QuickJsRegressionIssueCategory.RUNTIME;
      counts[category] = (counts[category] || 0) + 1;
    }
    const result: QuickJsCategoryStat[] = [];
    for (const category of Object.keys(counts)) {
      result.push(new QuickJsCategoryStat(category, counts[category]));
    }
    return result.sort((a: QuickJsCategoryStat, b: QuickJsCategoryStat): number => b.count - a.count);
  }

  private currentReportCategoryStats(): QuickJsCategoryStat[] {
    const counts: Record<string, number> = {};
    for (const item of this.report.items) {
      if (!item.errorCategory || item.errorCategory === QuickJsRegressionIssueCategory.NONE) continue;
      counts[item.errorCategory] = (counts[item.errorCategory] || 0) + 1;
    }
    const result: QuickJsCategoryStat[] = [];
    for (const category of Object.keys(counts)) {
      result.push(new QuickJsCategoryStat(category, counts[category]));
    }
    return result.sort((a: QuickJsCategoryStat, b: QuickJsCategoryStat): number => b.count - a.count);
  }

  private issueCategoryColor(category: string): string {
    if (category === QuickJsRegressionIssueCategory.SEMANTIC_MISMATCH) return '#E89725';
    if (category === QuickJsRegressionIssueCategory.UNSUPPORTED ||
      category === QuickJsRegressionIssueCategory.MISSING_BINDING) return '#8A6BC2';
    if (category === QuickJsRegressionIssueCategory.TIMEOUT ||
      category === QuickJsRegressionIssueCategory.RESOURCE_LIMIT) return '#D44848';
    return '#E84040';
  }

  private async saveRegressionForValidation(report: QuickJsRegressionReport): Promise<void> {
    const seeds: QuickJsValidationSeed[] = [];
    for (const item of report.items) {
      const seed = new QuickJsValidationSeed();
      seed.sourceUrl = item.sourceUrl;
      seed.sourceName = item.sourceName;
      seed.stage = item.stage;
      seed.field = item.field;
      seed.fingerprint = item.fingerprint;
      seed.offlineStatus = item.status;
      seed.routable = item.routable;
      seeds.push(seed);
    }
    await QuickJsValidationStore.saveRegression(getContext(this) as Context, seeds);
    this.refreshValidation();
  }

  private async toggleRealValidation(): Promise<void> {
    const context = getContext(this) as Context;
    if (this.validationSnapshot.active) {
      await QuickJsValidationStore.stop(context);
      this.refreshValidation();
      return;
    }
    await QuickJsMigrationStore.setMode(context, QuickJsRuntimeMode.SHADOW);
    QuickJsShadowComparator.resetSampling();
    if (!await QuickJsValidationStore.start(context)) {
      HdsFeedback.showToast('没有离线回归一致的候选表达式');
      return;
    }
    this.refreshValidation();
    HdsFeedback.showToast('真实影子验证已开始，请正常搜索或阅读所选书源');
  }

  private async enableCanary(): Promise<void> {
    if (this.qualifiedValidationCount() <= 0) return;
    const context = getContext(this) as Context;
    await QuickJsValidationStore.stop(context);
    await QuickJsMigrationStore.setMode(context, QuickJsRuntimeMode.CANARY);
    this.refreshValidation();
    HdsFeedback.showToast('已开启灰度接管，异常会自动回退旧引擎');
  }

  private refreshValidation(): void {
    this.validationSnapshot = QuickJsValidationStore.snapshot();
    this.migrationMode = QuickJsMigrationStore.snapshot().mode;
  }

  private onValidationRevisionChanged(): void { this.refreshValidation(); }

  private qualifiedValidationCount(): number {
    return this.validationSnapshot.candidates.filter((item: QuickJsValidationCandidate): boolean =>
      this.isValidationQualified(item) && QuickJsMigrationStore.isCanaryEligible(item.fingerprint)).length;
  }

  private pendingValidationCount(): number {
    return this.validationSnapshot.candidates.filter((item: QuickJsValidationCandidate): boolean =>
      this.canValidateCandidate(item) && !this.isValidationQualified(item) && !this.hasValidationIssue(item)).length;
  }

  private validationIssueCount(): number {
    return this.validationSnapshot.candidates.filter((item: QuickJsValidationCandidate): boolean =>
      item.offlineStatus !== QuickJsRegressionStatus.MATCH ||
      (this.canValidateCandidate(item) && this.hasValidationIssue(item))).length;
  }

  private offlineOnlyValidationCount(): number {
    return this.validationSnapshot.candidates.filter((item: QuickJsValidationCandidate): boolean =>
      item.offlineStatus === QuickJsRegressionStatus.MATCH && !item.routable).length;
  }

  private routableValidationCount(): number {
    return this.validationSnapshot.candidates.filter((item: QuickJsValidationCandidate): boolean =>
      this.canValidateCandidate(item)).length;
  }

  private validationCandidatesForDisplay(): QuickJsValidationCandidate[] {
    return this.validationSnapshot.candidates.slice().sort(
      (a: QuickJsValidationCandidate, b: QuickJsValidationCandidate): number =>
        this.validationCandidateRank(a) - this.validationCandidateRank(b)).slice(0, 30);
  }

  private validationCandidateRank(item: QuickJsValidationCandidate): number {
    if (this.isValidationQualified(item)) return 0;
    if (this.canValidateCandidate(item) && !this.hasValidationIssue(item)) return 1;
    if (item.offlineStatus !== QuickJsRegressionStatus.MATCH || this.hasValidationIssue(item)) return 2;
    return 3;
  }

  private validationCandidateStatus(item: QuickJsValidationCandidate): string {
    if (item.offlineStatus === QuickJsRegressionStatus.MISMATCH) return '离线差异';
    if (item.offlineStatus !== QuickJsRegressionStatus.MATCH) return '离线失败';
    if (!item.routable) return '仅离线通过';
    if (item.realMismatches > 0) return '真实差异';
    if (item.realFailures > 0) return '真实失败';
    if (this.isValidationQualified(item)) return '灰度合格';
    if (item.realMatches > 0) return `${item.realMatches}/${QuickJsValidationStore.REAL_MATCH_THRESHOLD}`;
    return '待验证';
  }

  private validationCandidateColor(item: QuickJsValidationCandidate): string {
    if (item.offlineStatus !== QuickJsRegressionStatus.MATCH || this.hasValidationIssue(item)) return '#E84040';
    if (!item.routable) return this.subTextColor();
    if (this.isValidationQualified(item)) return '#20A464';
    return '#E89725';
  }

  private canValidateCandidate(item: QuickJsValidationCandidate): boolean {
    return item.offlineStatus === QuickJsRegressionStatus.MATCH && item.routable;
  }

  private hasValidationIssue(item: QuickJsValidationCandidate): boolean {
    return item.realMismatches > 0 || item.realFailures > 0;
  }

  private isValidationQualified(item: QuickJsValidationCandidate): boolean {
    return this.canValidateCandidate(item) && item.realMatches >= QuickJsValidationStore.REAL_MATCH_THRESHOLD &&
      !this.hasValidationIssue(item);
  }

  private statusLabel(status: string): string {
    if (status === QuickJsRegressionStatus.MATCH) return '一致';
    if (status === QuickJsRegressionStatus.MISMATCH) return '差异';
    return '失败';
  }

  private statusColor(status: string): string {
    if (status === QuickJsRegressionStatus.MATCH) return '#20A464';
    if (status === QuickJsRegressionStatus.MISMATCH) return '#E89725';
    return '#E84040';
  }

  private resultStatusLabel(item: QuickJsRegressionItemResult): string {
    if (item.status === QuickJsRegressionStatus.EXCLUDED) return '退出迁移';
    if (item.status === QuickJsRegressionStatus.MATCH && !item.routable) return '一致·仅离线';
    return this.statusLabel(item.status);
  }

  private resultStatusColor(item: QuickJsRegressionItemResult): string {
    if (item.status === QuickJsRegressionStatus.EXCLUDED) return this.subTextColor();
    if (item.status === QuickJsRegressionStatus.MATCH && !item.routable) return this.subTextColor();
    return this.statusColor(item.status);
  }

  private syncBars(): void { syncSystemBars(getContext(this), this.appDarkMode, this.pageColor()); }
  private pageColor(): string { return ThemeRuntime.pageColor(this.appDarkMode); }
  private cardColor(): string { return ThemeRuntime.cardColor(this.appDarkMode); }
  private primaryTextColor(): string { return ThemeRuntime.primaryTextColor(this.appDarkMode); }
  private subTextColor(): string { return ThemeRuntime.subTextColor(this.appDarkMode); }
  private accentColor(): string { return ThemeRuntime.accentColor(this.appDarkMode); }
  private softColor(): string { return this.appDarkMode ? '#24FFFFFF' : '#0D000000'; }
  private dividerColor(): string { return this.appDarkMode ? '#20FFFFFF' : '#12000000'; }
}
