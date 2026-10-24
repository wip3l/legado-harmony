import { promptAction, router } from '@kit.ArkUI';
import { ImmersiveBackButton } from '../components/ImmersiveBackButton';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { Book, HttpClient, JavaRegexCompat, ReplaceRuleImport } from '@legado/sourceengine';
import { ReaderReplaceRule, ReaderReplaceRuleCheck, ReaderReplaceRuleStore } from '../utils/ReaderReplaceRuleStore';
import { syncSystemBars } from '../utils/SystemBars';
import { ResponsiveManagerListLayout } from '../utils/ResponsiveManagerListLayout';
import { FormDraftStore } from '../utils/FormDraftStore';
import deviceInfo from '@ohos.deviceInfo';
import { HdsListItem, HdsSwipeActionOptions } from '@kit.UIDesignKit';
import { SymbolGlyphModifier } from '@kit.ArkUI';
import picker from '@ohos.file.picker';
import fs from '@ohos.file.fs';
import { util } from '@kit.ArkTS';
import { HdsFeedback } from '../utils/HdsFeedback';
import { SystemDialogSession } from '../utils/SystemDialogSession';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { CollapsingHeader } from '../utils/CollapsingHeader';
import { ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';
import { ImmersiveMaterialSurface } from '../components/ImmersiveMaterialSurface';
import { PopupMenuAction, PopupMenuHeader } from '../components/common/PopupMenuAction';

const REPLACE_RULE_IMPORT_FILE_LIMIT_BYTES: number = 5 * 1024 * 1024;
const REPLACE_RULE_IMPORT_TIMEOUT_MS: number = 20000;

class ReplaceRuleFormDraft {
  ruleJson: string = '';
  timeoutDraft: string = '3000';
  applyToTitle: boolean = true;
  applyToContent: boolean = true;
  isRegex: boolean = true;
}

@Entry
@Component
struct ReaderReplaceRulesPage {
  @StorageProp('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  @State headerCollapse: number = 0;
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @State rules: ReaderReplaceRule[] = [];
  @State query: string = '';
  @State editing: boolean = false;
  @State draft: ReaderReplaceRule = ReaderReplaceRuleStore.newRule();
  @State timeoutDraft: string = '3000';
  @State draftApplyToTitle: boolean = true;
  @State draftApplyToContent: boolean = true;
  @State draftIsRegex: boolean = true;
  @State showRuleActionDialog: boolean = false;
  @State showRuleMoreDialog: boolean = false;
  @State showAddRuleDialog: boolean = false;
  private importUrlDialogSession: SystemDialogSession = new SystemDialogSession();
  private importingDialogSession: SystemDialogSession = new SystemDialogSession();
  @State @Watch('onSystemDialogFlagChanged') showImportUrlDialog: boolean = false;
  @State importUrl: string = '';
  @State @Watch('syncIsImporting') isImporting: boolean = false;
  @State actionRuleId: number = 0;
  @State contextMenuX: number = 16;
  @State contextMenuY: number = 96;
  @State contextViewportWidth: number = 360;
  @State contextViewportHeight: number = 720;
  @State selectionMode: boolean = false;
  @State selectedRuleIds: number[] = [];
  @State isBatchOperating: boolean = false;
  @State previewMode: boolean = false;
  @State previewTitle: string = '';
  @State previewContent: string = '';
  private previewBook: Book | null = null;
  private ruleSelectionAreas: Map<number, number[]> = new Map<number, number[]>();
  private ruleDragVisited: Set<number> = new Set<number>();
  private ruleDragSelectValue: boolean = true;
  private ruleListScroller: Scroller = new Scroller();
  private ruleSelectionDragging: boolean = false;
  private ruleSelectionLastX: number = 0;
  private ruleSelectionLastY: number = 0;
  private ruleSelectionAutoScrollId: number = -1;
  private ruleSelectionAutoDirection: number = 0;
  private ruleSelectionViewportTop: number = 0;
  private ruleSelectionViewportBottom: number = 0;
  private ruleFirstVisibleIndex: number = 0;
  private ruleLastVisibleIndex: number = 0;
  private ruleSelectionSuppressClickUntil: number = 0;

  aboutToAppear(): void {
    this.loadPreviewContext();
    this.loadRules();
    this.restorePersistentRuleFormDraft();
    this.syncBars();
  }

  onPageShow(): void {
    this.syncBars();
  }

  onPageHide(): void {
    this.stopRuleSelectionAutoScroll();
    this.persistRuleFormDraftNow();
  }

  onBackPress(): boolean {
    if (this.showRuleMoreDialog) {
      this.showRuleMoreDialog = false;
      return true;
    }
    if (this.selectionMode) {
      this.exitRuleSelectionMode();
      return true;
    }    if (this.showAddRuleDialog) {
      this.showAddRuleDialog = false;
      return true;
    }
    if (this.showRuleActionDialog) {
      this.closeRuleActions();
      return true;
    }
    if (this.editing) {
      this.closeEditor();
      return true;
    }
    return false;
  }

  async loadRules(): Promise<void> {
    this.rules = await ReaderReplaceRuleStore.load(getContext(this), true);
  }

  async importRulesFromFile(): Promise<void> {
    try {
      const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = ['JSON|.json', '文本|.txt'];
      const result: Array<string> = await new picker.DocumentViewPicker(getContext(this)).select(options);
      if (!result || result.length === 0) return;
      this.isImporting = true;
      const content = await this.readRuleTextFile(result[0]);
      await this.importRulesFromJson(content);
    } catch (e) {
      console.error('从文件导入替换规则失败:', e);
      HdsFeedback.showToast(`导入失败: ${this.importErrorMessage(e as Object)}`);
    } finally {
      this.isImporting = false;
    }
  }

  async importRulesFromUrl(): Promise<void> {
    const url = this.importUrl.trim();
    if (!url) {
      HdsFeedback.showToast('请输入URL');
      return;
    }
    try {
      this.isImporting = true;
      const response = await new HttpClient(REPLACE_RULE_IMPORT_TIMEOUT_MS).execute({
        url: url,
        method: 'GET',
        headers: { 'Accept': 'application/json,text/plain,*/*' },
        connectTimeout: REPLACE_RULE_IMPORT_TIMEOUT_MS,
        readTimeout: REPLACE_RULE_IMPORT_TIMEOUT_MS,
        maxResponseBytes: REPLACE_RULE_IMPORT_FILE_LIMIT_BYTES
      });
      if (!response.success || !response.body) {
        throw new Error(response.error || `HTTP ${response.statusCode}`);
      }
      await this.importRulesFromJson(response.body);
      this.showImportUrlDialog = false;
      this.importUrl = '';
    } catch (e) {
      console.error('从URL导入替换规则失败:', e);
      HdsFeedback.showToast(`导入失败: ${this.importErrorMessage(e as Object)}`);
    } finally {
      this.isImporting = false;
    }
  }

  async importRulesFromJson(raw: string): Promise<void> {
    const result = ReplaceRuleImport.parse(raw);
    if (ReplaceRuleImport.needsConfirm(result)) {
      this.isImporting = false;
      const confirmed = await promptAction.showDialog({
        title: ReplaceRuleImport.confirmTitle(result),
        message: ReplaceRuleImport.confirmMessage(result),
        buttons: [
          { text: '取消', color: this.secondaryTextColor() },
          { text: '转换导入', color: this.accentColor() }
        ]
      });
      if (confirmed.index !== 1) {
        HdsFeedback.showToast('已取消导入');
        return;
      }
      this.isImporting = true;
    }
    const next = this.rules.map((rule: ReaderReplaceRule) => ReaderReplaceRuleStore.cloneRule(rule));
    const usedIds = new Set<number>(next.map((rule: ReaderReplaceRule) => rule.id));
    let nextId = Date.now();
    let importedCount = 0;
    for (const entry of result.rules) {
      const imported = ReaderReplaceRuleStore.fromImportEntry(entry);
      if (!imported.pattern.trim()) continue;
      // 只有 id 与匹配规则都相同的条目才算更新同一条规则，避免不同来源的文件用小 id 互相覆盖。
      const existingIndex = next.findIndex((rule: ReaderReplaceRule) =>
        rule.id === imported.id && rule.pattern === imported.pattern);
      if (existingIndex >= 0) {
        next[existingIndex] = imported;
      } else {
        while (usedIds.has(imported.id) || imported.id <= 0) imported.id = nextId++;
        usedIds.add(imported.id);
        next.push(imported);
      }
      importedCount++;
    }
    if (importedCount === 0) {
      throw new Error('未找到有效的替换净化规则');
    }
    await ReaderReplaceRuleStore.save(getContext(this), next);
    this.rules = await ReaderReplaceRuleStore.load(getContext(this), true);
    this.selectedRuleIds = [];
    const source = result.formatLabel === '本应用' ? '' : `（来源：${result.formatLabel}）`;
    const skipped = result.skipped > 0 ? `，跳过 ${result.skipped} 条无匹配规则` : '';
    const contentScope = result.ignoredContentScope > 0 ?
      `，${result.ignoredContentScope} 条正文范围条件已忽略` : '';
    HdsFeedback.showToast(`已导入 ${importedCount} 条替换规则${source}${skipped}${contentScope}`);
  }

  async readRuleTextFile(uri: string): Promise<string> {
    let file: fs.File | null = null;
    try {
      const stat = await fs.stat(uri);
      if (stat.size <= 0) return '';
      if (stat.size > REPLACE_RULE_IMPORT_FILE_LIMIT_BYTES) {
        throw new Error('文件过大，请选择 5MB 以内的规则文件');
      }
      file = await fs.open(uri, fs.OpenMode.READ_ONLY);
      const buffer = new ArrayBuffer(stat.size);
      await fs.read(file.fd, buffer, { offset: 0, length: stat.size });
      return util.TextDecoder.create('utf-8')
        .decodeWithStream(new Uint8Array(buffer), { stream: false })
        .replace(/^\uFEFF/, '');
    } finally {
      if (file) await fs.close(file);
    }
  }

  async exportRules(): Promise<void> {
    if (!this.selectionMode) {
      HdsFeedback.showToast('请先进入选择模式');
      return;
    }
    const selected = this.rules.filter((rule: ReaderReplaceRule) => this.selectedRuleIds.includes(rule.id));
    if (selected.length === 0) {
      HdsFeedback.showToast('请先选择规则');
      return;
    }
    let file: fs.File | null = null;
    try {
      const options: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
      options.newFileNames = [`qingye-replace-rules-${this.exportTimestamp()}.json`];
      options.fileSuffixChoices = ['JSON 文件|.json'];
      const result = await new picker.DocumentViewPicker(getContext(this)).save(options);
      if (!result || result.length === 0) return;
      const json = JSON.stringify(selected, null, 2);
      const bytes = new util.TextEncoder().encodeInto(json);
      file = await fs.open(result[0], fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      await fs.write(file.fd, bytes.buffer, { offset: 0, length: bytes.byteLength });
      await fs.close(file);
      file = null;
      HdsFeedback.showToast(`已导出 ${selected.length} 条替换规则`);
    } catch (e) {
      console.error('导出替换规则失败:', e);
      HdsFeedback.showToast(`导出失败: ${this.importErrorMessage(e as Object)}`);
    } finally {
      if (file) {
        try { await fs.close(file); } catch (_) {}
      }
    }
  }

  exportTimestamp(): string {
    const date = new Date();
    const pad = (value: number): string => value < 10 ? `0${value}` : `${value}`;
    return `${date.getFullYear()}${pad(date.getMonth() + 1)}${pad(date.getDate())}-` +
      `${pad(date.getHours())}${pad(date.getMinutes())}`;
  }

  importErrorMessage(error: Object): string {
    if (error instanceof Error && error.message) return error.message;
    const message = String((error as Record<string, Object>)?.['message'] || '').trim();
    return message || String(error || '未知错误');
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        // 顶栏随列表上滑跟手收起、下滑展开，与其他二级页面一致。
        Column() {
          this.titleBar()
        }
        .width('100%')
        .height(56 + this.statusBarHeight - (this.editing ? 0 : this.headerCollapse))
        .clip(true)
        .opacity(CollapsingHeader.contentOpacity((this.editing ? 0 : this.headerCollapse)))
        .hitTestBehavior(CollapsingHeader.acceptsTouch((this.editing ? 0 : this.headerCollapse)) ? HitTestMode.Default : HitTestMode.None)
        if (this.editing) {
          this.editorView()
        } else {
          this.managerView()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.pageColor())

      if (!this.editing && !this.selectionMode && !this.isImporting) {
        Stack() {
          ImmersiveMaterialSurface({
            surfaceWidth: 52,
            surfaceHeight: 52,
            darkMode: this.appDarkMode,
            fallbackColor: this.cardColor(),
            glowColor: `#40${this.accentColor().substring(1)}`
          }) {
            SymbolGlyph($r('sys.symbol.plus'))
              .fontSize(25)
              .fontColor([this.accentColor()])
          }
        }
        .width(52)
        .height(52)
        .margin({ right: AppSpacing.XXL, bottom: this.navBarHeight + 22 })
        .accessibilityText('新增替换净化规则')
        .accessibilityRole(AccessibilityRoleType.BUTTON)
        .onClick(() => this.showAddRuleDialog = true)
        .bindPopup(this.showAddRuleDialog, ImmersiveMaterialRuntime.popupMenuOptions(this.immersiveLightLevel, (): void => {
          this.addRuleDropdown()
        }, Placement.TopRight, this.appDarkMode, this.accentColor(), () => {
          this.showAddRuleDialog = false;
        }))
      }

      Column()
        .width(1)
        .height(1)
        .position({ x: this.contextMenuX, y: this.contextMenuY })
        .hitTestBehavior(HitTestMode.None)
        .bindPopup(this.showRuleActionDialog, ImmersiveMaterialRuntime.popupMenuOptions(this.immersiveLightLevel, (): void => {
          this.ruleActionDialog()
        }, Placement.BottomLeft, this.appDarkMode, this.accentColor(), () => {
          this.showRuleActionDialog = false;
        }))

    }
    .width('100%')
    .height('100%')
    .onAreaChange((_oldValue: Area, newValue: Area) => this.updateContextViewport(newValue))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  titleBar() {
    Row() {
      ImmersiveBackButton({
        iconColor: this.primaryTextColor(),
        darkMode: this.appDarkMode,
        buttonSize: 40,
        containerWidth: 56,
        materialScale: 0.83,
        compactLayout: true,
        onBack: () => {
          if (this.editing) {
            this.closeEditor();
          } else if (this.selectionMode) {
            this.exitRuleSelectionMode();
          } else {
            router.back();
          }
        }
      })
      Text(this.editing ? (this.draft.name ? '编辑替换规则' : '新增替换规则') :
        (this.previewMode ? '替换净化配置' : '替换净化'))
        .fontSize(AppFontSize.TITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)
      if (!this.editing) {
        Text(this.selectionMode ? '取消' : '选择')
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.primaryTextColor())
          .width(52)
          .height(56)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            if (this.selectionMode) {
              this.exitRuleSelectionMode();
            } else {
              this.enterEmptyRuleSelectionMode();
            }
          })
      }
    }
    .width('100%')
    .height(56 + this.statusBarHeight)
    // Keep the action text aligned with the content/search field right edge.
    .padding({ right: AppSpacing.XL, top: this.statusBarHeight })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  addRuleDropdown() {
    Scroll() {
      Column() {
        this.ruleAddActionItem($r('sys.symbol.plus'), '新建规则', () => {
          this.showAddRuleDialog = false;
          this.openNewRule();
        })
        this.ruleAddActionItem($r('sys.symbol.arrow_right_up_and_square'), '从 URL 导入', () => {
          this.showAddRuleDialog = false;
          this.importUrl = '';
          this.openImportUrlDialog();
        })
        this.ruleAddActionItem($r('sys.symbol.download'), '从文件导入', () => {
          this.showAddRuleDialog = false;
          this.importRulesFromFile();
        })

      }
      .width('100%')
    }
    .width(188)
    .constraintSize({ maxHeight: ImmersiveMaterialRuntime.popupMenuMaxHeight() })
    .scrollBar(BarState.Off)
    .padding(ImmersiveMaterialRuntime.POPUP_MENU_PADDING)
  }

  @Builder
  ruleAddActionItem(icon: Resource, label: string, action: () => void) {
    PopupMenuAction(icon, label, this.primaryTextColor(), action)
  }

  onSystemDialogFlagChanged(): void {
    if (!this.showImportUrlDialog) this.importUrlDialogSession.close(this.getUIContext());
  }

  openImportUrlDialog(): void {
    this.showImportUrlDialog = true;
    this.importUrlDialogSession.open(this.getUIContext(), (): void => {
      this.importUrlDialogContent();
    }, {
      autoCancel: true,
      maskColor: ThemeRuntime.scrimColor(this.appDarkMode),
      warnTag: '显示URL导入弹窗失败:'
    });
  }

  @Builder
  importUrlDialogContent() {
    Column() {
      Text('从 URL 导入替换规则')
        .fontSize(AppFontSize.SUBTITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ bottom: AppSpacing.XL })

      TextInput({ placeholder: '规则 URL（兼容阅读/YueDu 导出）', text: this.importUrl })
        .width('100%')
        .height(48)
        .borderRadius(ThemeRuntime.mediumRadius())
        .backgroundColor(this.inputColor())
        .fontColor(this.primaryTextColor())
        .placeholderColor(this.subTextColor())
        .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
        .margin({ bottom: AppSpacing.XL })
        .onChange((value: string) => this.importUrl = value)

      Row({ space: AppSpacing.MD }) {
        Button('取消')
          .layoutWeight(1)
          .height(44)
          .backgroundColor(this.inputColor())
          .fontColor(this.primaryTextColor())
          .onClick(() => {
            this.showImportUrlDialog = false;
            this.importUrl = '';
          })
        Button('导入')
          .layoutWeight(1)
          .height(44)
          .backgroundColor(this.buttonColor())
          .fontColor(ThemeRuntime.onAccentColor())
          .enabled(!this.isImporting)
          .onClick(() => this.importRulesFromUrl())
      }
      .width('100%')
    }    .constraintSize({ maxWidth: 420 })
    .padding(AppSpacing.XXXL)
  }


  @Builder
  importingOverlay() {
    Column() {
      LoadingProgress()
        .width(46)
        .height(46)
        .color(this.accentColor())
      Text('正在导入替换规则...')
        .fontSize(AppFontSize.BODY_LARGE)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .margin({ top: AppSpacing.LG })
      Text('请稍候')
        .fontSize(AppFontSize.BODY)
        .fontColor(this.subTextColor())
        .margin({ top: AppSpacing.SM })
    }
    .width('100%')
    .padding({ left: AppSpacing.XXXL, right: AppSpacing.XXXL, top: AppSpacing.XXXL, bottom: AppSpacing.XXXL })
    .alignItems(HorizontalAlign.Center)
  }

  syncIsImporting(): void {
    this.importingDialogSession.sync(this.getUIContext(), this.isImporting, (): void => {
      this.importingOverlay();
    }, {
      autoCancel: false,
      maskColor: ThemeRuntime.scrimColor(this.appDarkMode),
      warnTag: '显示导入进度弹窗失败:'
    });
  }

  @Builder
  managerView() {
    Column() {
      if (this.previewMode) {
        this.currentChapterPreviewCard()
      }
      TextInput({ placeholder: '搜索规则名称或匹配内容', text: this.query })
        .height(44)
        .fontSize(AppFontSize.BODY)
        .fontColor(this.primaryTextColor())
        .placeholderColor(this.subTextColor())
        .backgroundColor(this.inputColor())
        .borderRadius(22)
        .padding({ left: AppSpacing.XL, right: AppSpacing.XL })
        .margin({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG, bottom: AppSpacing.MD })
        .onChange((value: string) => this.query = value)

      if (this.selectionMode) {
        this.ruleSelectionHeader()
      }

      if (this.filteredRules().length === 0) {
        Column({ space: AppSpacing.MD }) {
          SymbolGlyph($r('sys.symbol.arrow_left_arrow_right'))
            .fontSize(36)
            .fontColor([this.subTextColor()])
          Text(this.query ? '没有匹配的规则' : '暂无替换净化规则')
            .fontSize(AppFontSize.BODY_LARGE)
            .fontColor(this.secondaryTextColor())
          Text(this.query ? '尝试更换搜索词' : '点击右下角添加规则')
            .fontSize(AppFontSize.BODY)
            .fontColor(this.subTextColor())
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: AppSpacing.MD, scroller: this.ruleListScroller }) {
          ForEach(this.filteredRules(), (rule: ReaderReplaceRule) => {
            if (deviceInfo.sdkApiVersion >= 26) {
              HdsListItem({
                customItemBuilder: () => {
                  this.ruleCard(rule)
                },
                swipeActionOptions: this.ruleSwipeActions(rule)
              })
              } else {
                ListItem() {
                  this.ruleCard(rule)
                }
                .swipeAction({
                  end: {
                    builder: () => {
                      this.ruleFallbackSwipeActions(rule)
                    },
                    actionAreaDistance: 128,
                    onAction: () => this.confirmDelete(rule)
                  },
                  edgeEffect: SwipeEdgeEffect.Spring
                })
            }
          }, (rule: ReaderReplaceRule) =>
            `${rule.id}_${rule.enabled ? '1' : '0'}_${this.selectionMode ? 'select' : 'normal'}`)

          // 底部避让 spacer 必须按 lanes 列数复制占满整行，否则多列时最后一行卡片没有底部避让。
          ForEach(this.ruleListSpacerKeys(), (_spacerKey: string) => {
            ListItem() {
              Column().height(84)
            }
          }, (spacerKey: string) => spacerKey)
        }
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .layoutWeight(1)
        .width('100%')
        .padding({ left: AppSpacing.XL, right: AppSpacing.XL })
        .clip(true)
        .lanes(ResponsiveManagerListLayout.laneCount(this.contextViewportWidth),
          ResponsiveManagerListLayout.gutter(this.contextViewportWidth))
        .onScrollIndex((start: number, end: number) => {
          this.ruleFirstVisibleIndex = start;
          this.ruleLastVisibleIndex = end;
        })
        .onAreaChange((_oldValue: Area, area: Area) => {
          this.ruleSelectionViewportTop = Number(area.globalPosition.y);
          this.ruleSelectionViewportBottom = this.ruleSelectionViewportTop + Number(area.height);
        })
        .onDidScroll((yOffset: number) => {
          this.headerCollapse = CollapsingHeader.next(this.headerCollapse, yOffset,
            this.ruleListScroller.currentOffset().yOffset);
        })
        .onScrollStop(() => {
          const target = CollapsingHeader.settle(this.headerCollapse, this.ruleListScroller.currentOffset().yOffset);
          if (target !== this.headerCollapse) {
            animateTo({ duration: 200, curve: Curve.FastOutSlowIn }, () => {
              this.headerCollapse = target;
            });
          }
        })
      }

      if (this.selectionMode) {
        this.ruleBatchBar()
      }
    }
    .width('100%')
    .layoutWeight(1)
  }

  private ruleSwipeActions(rule: ReaderReplaceRule): HdsSwipeActionOptions {
    return { icons: [
      {
        icon: new SymbolGlyphModifier(rule.enabled ? $r('sys.symbol.minus_circle') : $r('sys.symbol.checkmark_circle')),
        backgroundColor: this.buttonColor(),
        iconOptions: { accessibilityText: rule.enabled ? '禁用规则' : '启用规则' },
        onAction: () => this.setRuleEnabled(rule.id, !rule.enabled)
      },
      { icon: new SymbolGlyphModifier($r('sys.symbol.trash')), backgroundColor: ThemeRuntime.dangerColor(this.appDarkMode), iconOptions: { accessibilityText: '删除规则' }, onAction: () => this.confirmDelete(rule) }
    ] };
  }

  @Builder
  ruleFallbackSwipeActions(rule: ReaderReplaceRule) {
    Row() {
      this.ruleEnableSwipeAction(rule)
      this.ruleDeleteSwipeAction(rule)
    }
    .height('100%')
  }

  @Builder
  ruleCard(rule: ReaderReplaceRule) {
    Row() {
      if (this.selectionMode) {
        this.ruleSelectionSafeArea(rule)
      }

      Column({ space: AppSpacing.XS }) {
        Text(rule.name || '未命名规则')
          .fontSize(AppFontSize.BODY_LARGE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.primaryTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(rule.pattern || '未填写匹配规则')
          .fontSize(AppFontSize.BODY)
          .fontColor(this.secondaryTextColor())
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(this.ruleScopeSummary(rule))
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())

        if (this.previewMode) {
          Text(this.ruleEffectLabel(rule))
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.ruleEffectColor(rule))
        }

        if (this.ruleCompatibilityNotes(rule).length > 0) {
          Text(`已按 Android 正则转换：${this.ruleCompatibilityNotes(rule).join('；')}`)
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.subTextColor())
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Column() {
        Text(rule.enabled ? '已启用' : '已禁用')
          .fontSize(AppFontSize.CAPTION)
          .fontColor(rule.enabled ? ThemeRuntime.successColor(this.appDarkMode) : this.subTextColor())
      }
      .alignItems(HorizontalAlign.End)
      .margin({ left: AppSpacing.LG })
    }
    .width('100%')
    .padding(AppSpacing.LG)
    .backgroundColor(this.cardColor())
    .borderRadius(ThemeRuntime.cardRadius())
    .border({ width: ThemeRuntime.glassBorderWidth(), color: ThemeRuntime.glassBorderColor(this.appDarkMode) })
    .opacity(rule.enabled ? 1 : 0.5)
    .gesture(
      LongPressGesture({ repeat: false })
        .onAction((event: GestureEvent) => {
          if (!this.selectionMode && !this.isBatchOperating) this.openRuleActions(rule, event);
        })
    )
    .onClick(() => {
      if (this.selectionMode) {
        if (Date.now() < this.ruleSelectionSuppressClickUntil) return;
        this.toggleRuleSelected(rule.id);
      } else {
        this.openEditRule(rule);
      }
    })
  }

  @Builder
  currentChapterPreviewCard() {
    Column({ space: AppSpacing.MD }) {
      Row() {
        Column({ space: AppSpacing.XXS }) {
          Text('当前章节生效检查')
            .fontSize(AppFontSize.BODY_LARGE)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.primaryTextColor())
          Text(this.previewTitle || '当前章节')
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.subTextColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Text(this.previewSummaryText())
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.previewEffectiveCount() > 0 ? ThemeRuntime.successColor(this.appDarkMode) : this.subTextColor())
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.previewChanged()) {
        Column({ space: AppSpacing.XXS }) {
          Text('替换前').fontSize(AppFontSize.CAPTION).fontColor(this.subTextColor()).width('100%')
          Text(this.previewBeforeExcerpt())
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.secondaryTextColor())
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Text('替换后').fontSize(AppFontSize.CAPTION).fontColor(this.subTextColor()).width('100%').margin({ top: AppSpacing.XXS })
          Text(this.previewAfterExcerpt())
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.primaryTextColor())
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        .width('100%')
        .padding(AppSpacing.MD)
        .borderRadius(ThemeRuntime.mediumRadius())
        .backgroundColor(this.inputColor())
      } else {
        Text(this.rules.length === 0 ? '尚未配置规则，可点击右下角新增。' :
          '当前规则未改变本章内容；可查看每条规则下方的检查状态。')
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.secondaryTextColor())
          .width('100%')
      }
    }
    .width('calc(100% - 32vp)')
    .padding(AppSpacing.LG)
    .margin({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .backgroundColor(this.cardColor())
    .border({ width: ThemeRuntime.glassBorderWidth(), color: ThemeRuntime.glassBorderColor(this.appDarkMode) })
  }

  loadPreviewContext(): void {
    const params = router.getParams() as Record<string, string>;
    if (!params) return;
    if (params['previewCurrentChapter'] === 'true') {
      const book = new Book();
      book.name = AppStorage.get<string>('readerReplacePreviewBookName') || '';
      book.author = AppStorage.get<string>('readerReplacePreviewBookAuthor') || '';
      book.originName = AppStorage.get<string>('readerReplacePreviewBookOriginName') || '';
      book.origin = AppStorage.get<string>('readerReplacePreviewBookOrigin') || '';
      book.bookUrl = AppStorage.get<string>('readerReplacePreviewBookUrl') || '';
      this.previewBook = book;
      this.previewTitle = AppStorage.get<string>('readerReplacePreviewTitle') || '';
      this.previewContent = AppStorage.get<string>('readerReplacePreviewContent') || '';
      this.previewMode = true;
    }
    if (params['prefillReplacePattern'] === 'true') {
      this.openPrefilledNewRule();
    }
  }

  openPrefilledNewRule(): void {
    const pattern = (AppStorage.get<string>('readerReplaceRulePrefillPattern') || '').trim();
    // 预填内容只消费一次，避免之后正常进入本页时误带出旧选中文本。
    AppStorage.setOrCreate('readerReplaceRulePrefillPattern', '');
    if (!pattern) return;
    this.openNewRule();
    this.draft.pattern = pattern;
    // 长按选中的是纯文本，默认按字面匹配；需要正则时由用户在编辑器里手动开启。
    this.draft.isRegex = false;
    this.draftIsRegex = false;
    this.saveRuleFormDraft();
  }

  ruleEffectCheck(rule: ReaderReplaceRule): ReaderReplaceRuleCheck {
    return ReaderReplaceRuleStore.checkRule(
      rule, this.previewBook, this.previewTitle, this.previewContent);
  }

  ruleEffectLabel(rule: ReaderReplaceRule): string {
    return this.ruleEffectCheck(rule).label;
  }

  ruleCompatibilityNotes(rule: ReaderReplaceRule): string[] {
    return rule.isRegex ? JavaRegexCompat.notes(rule.pattern) : [];
  }

  ruleEffectColor(rule: ReaderReplaceRule): string {
    const state = this.ruleEffectCheck(rule).state;
    if (state === 'effective') return ThemeRuntime.successColor(this.appDarkMode);
    if (state === 'invalid') return ThemeRuntime.dangerColor(this.appDarkMode);
    if (state === 'matched') return '#D17A00';
    return this.subTextColor();
  }

  previewEffectiveCount(): number {
    return this.rules.filter((rule: ReaderReplaceRule) =>
      this.ruleEffectCheck(rule).state === 'effective').length;
  }

  previewInvalidCount(): number {
    return this.rules.filter((rule: ReaderReplaceRule) =>
      this.ruleEffectCheck(rule).state === 'invalid').length;
  }

  previewSummaryText(): string {
    const effective = this.previewEffectiveCount();
    const invalid = this.previewInvalidCount();
    return `${effective} 条生效${invalid > 0 ? ` · ${invalid} 条无效` : ''}`;
  }

  previewChanged(): boolean {
    return this.previewBeforeText() !== this.previewAfterText();
  }

  previewBeforeText(): string {
    return `${this.previewTitle}\n${this.previewContent}`.trim();
  }

  previewAfterText(): string {
    const title = ReaderReplaceRuleStore.applyTitle(this.previewTitle, this.rules, this.previewBook);
    const content = ReaderReplaceRuleStore.applyContent(this.previewContent, this.rules, this.previewBook);
    return `${title}\n${content}`.trim();
  }

  previewBeforeExcerpt(): string {
    return this.previewExcerpt(this.previewBeforeText());
  }

  previewAfterExcerpt(): string {
    return this.previewExcerpt(this.previewAfterText());
  }

  previewExcerpt(value: string): string {
    return (value || '').replace(/\s+/g, ' ').trim().substring(0, 360) || '（空内容）';
  }

  @Builder
  ruleSelectionHeader() {
    Row() {
      Text(this.areAllVisibleRulesSelected() ? '☑' : '☐')
        .fontSize(AppFontSize.TITLE)
        .fontColor(this.accentColor())
        .width(28)
        .textAlign(TextAlign.Center)
        .onClick(() => this.toggleAllVisibleRules())
      Text(`已选择 ${this.selectedRuleIds.length}/${this.filteredRules().length}`)
        .fontSize(AppFontSize.BODY)
        .fontColor(this.subTextColor())
        .margin({ left: AppSpacing.MD })
        .layoutWeight(1)
      Text(this.areAllVisibleRulesSelected() ? '取消全选' : '全选')
        .fontSize(AppFontSize.BODY)
        .fontColor(this.accentColor())
        .onClick(() => this.toggleAllVisibleRules())
    }
    .width('100%')
    .height(42)
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL })
  }

  @Builder
  ruleBatchBar() {
    Row() {
      Button('启用')
        .layoutWeight(1)
        .height(42)
        .enabled(this.selectedRuleIds.length > 0 && !this.isBatchOperating)
        .backgroundColor(this.buttonColor())
        .fontColor(ThemeRuntime.onAccentColor())
        .onClick(() => this.batchSetRulesEnabled(true))
      Button('禁用')
        .layoutWeight(1)
        .height(42)
        .margin({ left: AppSpacing.MD })
        .enabled(this.selectedRuleIds.length > 0 && !this.isBatchOperating)
        .backgroundColor(this.inputColor())
        .fontColor(this.primaryTextColor())
        .onClick(() => this.batchSetRulesEnabled(false))
      Button('删除')
        .layoutWeight(1)
        .height(42)
        .margin({ left: AppSpacing.MD })
        .enabled(this.selectedRuleIds.length > 0 && !this.isBatchOperating)
        .backgroundColor(ThemeRuntime.dangerColor(this.appDarkMode))
        .fontColor(ThemeRuntime.onAccentColor())
        .onClick(() => this.batchDeleteRules())
      Button('更多')
        .layoutWeight(1)
        .height(42)
        .margin({ left: AppSpacing.MD })
        .enabled(!this.isBatchOperating)
        .backgroundColor(this.inputColor())
        .fontColor(this.primaryTextColor())
        .onClick(() => this.showRuleMoreDialog = true)
        .bindPopup(this.showRuleMoreDialog, ImmersiveMaterialRuntime.popupMenuOptions(this.immersiveLightLevel, (): void => {
          this.ruleBatchMorePopupMenu()
        }, Placement.TopRight, this.appDarkMode, this.accentColor(), () => {
          this.showRuleMoreDialog = false;
        }))
    }
    .width('100%')
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.MD, bottom: AppSpacing.LG })
    .backgroundColor(this.cardColor())
  }

  @Builder
  ruleBatchMorePopupMenu() {
    Scroll() {
      Column() {
        PopupMenuHeader(`已选择 ${this.selectedRuleIds.length} 条规则`, this.subTextColor())
        this.ruleAddActionItem($r('sys.symbol.download'), '导出 JSON', () => {
          this.showRuleMoreDialog = false;
          this.exportRules();
        })
      }
      .width('100%')
    }
    .width(188)
    .constraintSize({ maxHeight: ImmersiveMaterialRuntime.popupMenuMaxHeight() })
    .scrollBar(BarState.Off)
    .padding(ImmersiveMaterialRuntime.POPUP_MENU_PADDING)
  }

  @Builder
  editorView() {
    Scroll() {
      Column({ space: AppSpacing.LG }) {
        this.inputField('规则名称', this.draft.name, '例如：去除章节末广告', (value: string) => {
          this.draft.name = value;
          this.refreshDraft();
        })
        this.textAreaField('匹配规则', this.draft.pattern, '输入文本或正则表达式', (value: string) => {
          this.draft.pattern = value;
          this.refreshDraft();
        })
        this.textAreaField('替换为', this.draft.replacement, '留空表示删除匹配内容', (value: string) => {
          this.draft.replacement = value;
          this.refreshDraft();
        })

        Row({ space: AppSpacing.MD }) {
          this.titleOptionChip()
          this.contentOptionChip()
          Blank()
          this.regexOptionChip()
        }
        .width('100%')

        this.textAreaField('特定范围', this.draft.scope, '书名、作者、书源或地址；留空表示全部', (value: string) => {
          this.draft.scope = value;
          this.refreshDraft();
        })
        this.textAreaField('排除范围', this.draft.excludeScope, '多个范围使用逗号或换行分隔', (value: string) => {
          this.draft.excludeScope = value;
          this.refreshDraft();
        })
        this.inputField('超时 (ms)', this.timeoutDraft, '3000', (value: string) => {
          this.timeoutDraft = value.replace(/[^0-9]/g, '').substring(0, 5);
        }, InputType.Number)

        Row({ space: AppSpacing.LG }) {
          Button('取消', { type: ButtonType.Capsule })
            .layoutWeight(1)
            .height(44)
            .fontColor(this.primaryTextColor())
            .backgroundColor(this.inputColor())
            .onClick(() => this.closeEditor())
          Button('保存', { type: ButtonType.Capsule })
            .layoutWeight(1)
            .height(44)
            .fontColor(ThemeRuntime.onAccentColor())
            .backgroundColor(this.buttonColor())
            .onClick(() => this.saveDraft())
        }
        .width('100%')
        .margin({ top: AppSpacing.MD, bottom: 28 })
      }
      .width('100%')
      .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG })
    }
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .layoutWeight(1)
    .width('100%')
  }

  @Builder
  inputField(
    label: string,
    value: string,
    placeholder: string,
    onChange: (value: string) => void,
    inputType: InputType = InputType.Normal
  ) {
    Column({ space: AppSpacing.SM }) {
      Text(label).fontSize(AppFontSize.BODY).fontColor(this.subTextColor()).width('100%')
      TextInput({ placeholder: placeholder, text: value })
        .type(inputType)
        .width('100%')
        .height(46)
        .fontSize(AppFontSize.BODY_LARGE)
        .fontColor(this.primaryTextColor())
        .placeholderColor(this.subTextColor())
        .backgroundColor(this.inputColor())
        .borderRadius(ThemeRuntime.mediumRadius())
        .onChange((nextValue: string) => {
          onChange(nextValue);
          this.saveRuleFormDraft();
        })
    }
    .width('100%')
  }

  @Builder
  textAreaField(label: string, value: string, placeholder: string, onChange: (value: string) => void) {
    Column({ space: AppSpacing.SM }) {
      Text(label).fontSize(AppFontSize.BODY).fontColor(this.subTextColor()).width('100%')
      TextArea({ placeholder: placeholder, text: value })
        .width('100%')
        .height(86)
        .fontSize(AppFontSize.BODY)
        .fontColor(this.primaryTextColor())
        .placeholderColor(this.subTextColor())
        .backgroundColor(this.inputColor())
        .borderRadius(ThemeRuntime.mediumRadius())
        .padding(AppSpacing.LG)
        .onChange((nextValue: string) => {
          onChange(nextValue);
          this.saveRuleFormDraft();
        })
    }
    .width('100%')
  }

  @Builder
  titleOptionChip() {
    Button({ type: ButtonType.Capsule, stateEffect: true }) {
      Row({ space: AppSpacing.XS }) {
        if (this.draftApplyToTitle) {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(14)
            .fontColor([this.accentColor()])
        }
        Text('标题')
          .fontSize(AppFontSize.BODY)
          .fontColor(this.draftApplyToTitle ? this.accentColor() : this.secondaryTextColor())
      }
    }
    .height(36)
    .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
    .backgroundColor(this.draftApplyToTitle ? ThemeRuntime.accentSurfaceColor(this.appDarkMode) : this.inputColor())
    .borderRadius(18)
    .onClick(() => {
      this.draftApplyToTitle = !this.draftApplyToTitle;
      this.saveRuleFormDraft();
    })
  }

  @Builder
  contentOptionChip() {
    Button({ type: ButtonType.Capsule, stateEffect: true }) {
      Row({ space: AppSpacing.XS }) {
        if (this.draftApplyToContent) {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(14)
            .fontColor([this.accentColor()])
        }
        Text('正文')
          .fontSize(AppFontSize.BODY)
          .fontColor(this.draftApplyToContent ? this.accentColor() : this.secondaryTextColor())
      }
    }
    .height(36)
    .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
    .backgroundColor(this.draftApplyToContent ? ThemeRuntime.accentSurfaceColor(this.appDarkMode) : this.inputColor())
    .borderRadius(18)
    .onClick(() => {
      this.draftApplyToContent = !this.draftApplyToContent;
      this.saveRuleFormDraft();
    })
  }

  @Builder
  regexOptionChip() {
    Button({ type: ButtonType.Capsule, stateEffect: true }) {
      Row({ space: AppSpacing.XS }) {
        if (this.draftIsRegex) {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(14)
            .fontColor([this.accentColor()])
        }
        Text('使用正则')
          .fontSize(AppFontSize.BODY)
          .fontColor(this.draftIsRegex ? this.accentColor() : this.secondaryTextColor())
      }
    }
    .height(36)
    .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
    .backgroundColor(this.draftIsRegex ? ThemeRuntime.accentSurfaceColor(this.appDarkMode) : this.inputColor())
    .borderRadius(18)
    .onClick(() => {
      this.draftIsRegex = !this.draftIsRegex;
    })
  }

  @Builder
  ruleEnableSwipeAction(rule: ReaderReplaceRule) {
    Column({ space: AppSpacing.XS }) {
      SymbolGlyph(rule.enabled ? $r('sys.symbol.minus_circle') : $r('sys.symbol.checkmark_circle'))
        .fontSize(22)
        .fontColor(['#FFFFFF'])
      Text(rule.enabled ? '禁用' : '启用')
        .fontSize(AppFontSize.CAPTION)
        .fontColor('#FFFFFF')
    }
    .width(64)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(this.buttonColor())
    .onClick(() => this.setRuleEnabled(rule.id, !rule.enabled))
  }

  @Builder
  ruleDeleteSwipeAction(rule: ReaderReplaceRule) {
    Column({ space: AppSpacing.XS }) {
      SymbolGlyph($r('sys.symbol.trash'))
        .fontSize(22)
        .fontColor(['#FFFFFF'])
      Text('删除')
        .fontSize(AppFontSize.CAPTION)
        .fontColor('#FFFFFF')
    }
    .width(64)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(ThemeRuntime.dangerColor(this.appDarkMode))
    .onClick(() => this.confirmDelete(rule))
  }

  @Builder
  ruleActionDialog() {
    Scroll() {
      Column() {
        this.contextActionItem($r('sys.symbol.square_and_pencil'), '修改', this.primaryTextColor(), () => {
          const rule = this.actionRule();
          this.closeRuleActions();
          if (rule) this.openEditRule(rule);
        })
        this.contextActionItem(this.actionRuleEnabled() ? $r('sys.symbol.minus_circle') :
          $r('sys.symbol.checkmark_circle'), this.actionRuleEnabled() ? '禁用' : '启用', this.primaryTextColor(),
          () => {
            const rule = this.actionRule();
            this.closeRuleActions();
            if (rule) this.setRuleEnabled(rule.id, !rule.enabled);
          })
        this.contextActionItem($r('sys.symbol.list_bullet'), '多选', this.primaryTextColor(), () => {
          const rule = this.actionRule();
          this.closeRuleActions();
          if (rule) this.enterRuleSelectionMode(rule.id);
        })
        this.contextActionItem($r('sys.symbol.trash'), '删除', ThemeRuntime.dangerColor(this.appDarkMode), () => {
          const rule = this.actionRule();
          this.closeRuleActions();
          if (rule) this.confirmDelete(rule);
        })

      }
      .width('100%')
    }
    .width(188)
    .constraintSize({ maxHeight: ImmersiveMaterialRuntime.popupMenuMaxHeight() })
    .scrollBar(BarState.Off)
    .padding(ImmersiveMaterialRuntime.POPUP_MENU_PADDING)
  }

  @Builder
  contextActionItem(icon: Resource, label: string, color: string, action: () => void) {
    PopupMenuAction(icon, label, color, action)
  }

  filteredRules(): ReaderReplaceRule[] {
    const keyword = (this.query || '').trim().toLowerCase();
    if (!keyword) {
      return this.rules;
    }
    return this.rules.filter((rule: ReaderReplaceRule) =>
      `${rule.name}\n${rule.pattern}`.toLowerCase().includes(keyword));
  }

  // List.lanes 的列数；底部避让 spacer 按列数复制，保证多列时占满一整行。
  ruleListSpacerKeys(): string[] {
    const laneCount = ResponsiveManagerListLayout.laneCount(this.contextViewportWidth);
    const keys: string[] = [];
    for (let i = 0; i < laneCount; i++) {
      keys.push(`rule_list_spacer_${i}`);
    }
    return keys;
  }

  ruleScopeSummary(rule: ReaderReplaceRule): string {
    const targets: string[] = [];
    if (rule.applyToTitle) targets.push('标题');
    if (rule.applyToContent) targets.push('正文');
    const mode = rule.isRegex ? '正则' : '文本';
    return `${targets.join('、') || '未选择范围'} · ${mode}${rule.scope ? ' · 限定书籍' : ''}`;
  }

  enterRuleSelectionMode(ruleId: number): void {
    this.closeRuleActions();
    this.selectionMode = true;
    this.selectedRuleIds = [ruleId];
  }

  enterEmptyRuleSelectionMode(): void {
    this.closeRuleActions();
    this.selectionMode = true;
    this.selectedRuleIds = [];
  }

  exitRuleSelectionMode(): void {
    this.stopRuleSelectionAutoScroll();
    this.selectionMode = false;
    this.selectedRuleIds = [];
  }

  isRuleSelected(ruleId: number): boolean {
    return this.selectedRuleIds.includes(ruleId);
  }

  setRuleSelected(ruleId: number, selected: boolean): void {
    if (selected) {
      if (!this.selectedRuleIds.includes(ruleId)) {
        this.selectedRuleIds = this.selectedRuleIds.concat([ruleId]);
      }
    } else {
      this.selectedRuleIds = this.selectedRuleIds.filter((id: number) => id !== ruleId);
    }
  }

  toggleRuleSelected(ruleId: number): void {
    this.setRuleSelected(ruleId, !this.isRuleSelected(ruleId));
  }

  areAllVisibleRulesSelected(): boolean {
    const visible = this.filteredRules();
    return visible.length > 0 && visible.every((rule: ReaderReplaceRule) => this.isRuleSelected(rule.id));
  }

  toggleAllVisibleRules(): void {
    const visible = this.filteredRules();
    if (this.areAllVisibleRulesSelected()) {
      const visibleIds = visible.map((rule: ReaderReplaceRule) => rule.id);
      this.selectedRuleIds = this.selectedRuleIds.filter((id: number) => !visibleIds.includes(id));
      return;
    }
    const ids = this.selectedRuleIds.slice();
    for (const rule of visible) {
      if (!ids.includes(rule.id)) ids.push(rule.id);
    }
    this.selectedRuleIds = ids;
  }

  async batchSetRulesEnabled(enabled: boolean): Promise<void> {
    if (this.selectedRuleIds.length === 0 || this.isBatchOperating) return;
    this.isBatchOperating = true;
    const count = this.selectedRuleIds.length;
    try {
      const next = this.rules.map((rule: ReaderReplaceRule) => {
        const copy = ReaderReplaceRuleStore.cloneRule(rule);
        if (this.selectedRuleIds.includes(copy.id)) copy.enabled = enabled;
        return copy;
      });
      await ReaderReplaceRuleStore.save(getContext(this), next);
      this.rules = next;
      HdsFeedback.showToast(`已${enabled ? '启用' : '禁用'} ${count} 条规则`);
    } finally {
      this.isBatchOperating = false;
    }
  }

  async batchDeleteRules(): Promise<void> {
    if (this.selectedRuleIds.length === 0 || this.isBatchOperating) return;
    const count = this.selectedRuleIds.length;
    const result = await promptAction.showDialog({
      title: '删除规则',
      message: `确定删除已选择的 ${count} 条规则吗？`,
      buttons: [{ text: '取消', color: this.secondaryTextColor() }, { text: '删除', color: ThemeRuntime.dangerColor(this.appDarkMode) }]
    });
    if (result.index !== 1) return;
    this.isBatchOperating = true;
    try {
      const next = this.rules.filter((rule: ReaderReplaceRule) => !this.selectedRuleIds.includes(rule.id));
      await ReaderReplaceRuleStore.save(getContext(this), next);
      this.rules = next;
      this.exitRuleSelectionMode();
      HdsFeedback.showToast(`已删除 ${count} 条规则`);
    } finally {
      this.isBatchOperating = false;
    }
  }

  openNewRule(): void {
    FormDraftStore.removePersistent(getContext(this), 'replace_rule:edit');
    this.draft = ReaderReplaceRuleStore.newRule();
    this.draftApplyToTitle = this.draft.applyToTitle;
    this.draftApplyToContent = this.draft.applyToContent;
    this.draftIsRegex = this.draft.isRegex;
    this.timeoutDraft = '3000';
    this.editing = true;
    this.saveRuleFormDraft();
  }

  openEditRule(rule: ReaderReplaceRule): void {
    FormDraftStore.removePersistent(getContext(this), 'replace_rule:edit');
    this.draft = ReaderReplaceRuleStore.cloneRule(rule);
    this.draftApplyToTitle = this.draft.applyToTitle;
    this.draftApplyToContent = this.draft.applyToContent;
    this.draftIsRegex = this.draft.isRegex;
    this.timeoutDraft = `${this.draft.timeoutMs}`;
    this.editing = true;
    this.saveRuleFormDraft();
  }

  closeEditor(): void {
    this.editing = false;
    FormDraftStore.removePersistent(getContext(this), 'replace_rule:edit');
  }

  refreshDraft(): void {
    this.draft = ReaderReplaceRuleStore.cloneRule(this.draft);
    this.saveRuleFormDraft();
  }

  restoreRuleFormDraft(rawValue: string = ''): void {
    const raw = rawValue || FormDraftStore.get('replace_rule:edit');
    if (!raw) return;
    try {
      const form = JSON.parse(raw) as ReplaceRuleFormDraft;
      this.draft = JSON.parse(form.ruleJson) as ReaderReplaceRule;
      this.timeoutDraft = form.timeoutDraft;
      this.draftApplyToTitle = form.applyToTitle;
      this.draftApplyToContent = form.applyToContent;
      this.draftIsRegex = form.isRegex;
      this.editing = true;
    } catch (_) {
      FormDraftStore.removePersistent(getContext(this), 'replace_rule:edit');
    }
  }

  async restorePersistentRuleFormDraft(): Promise<void> {
    const raw = await FormDraftStore.load(getContext(this), 'replace_rule:edit');
    this.restoreRuleFormDraft(raw);
  }

  saveRuleFormDraft(): void {
    if (!this.editing) return;
    const form = new ReplaceRuleFormDraft();
    form.ruleJson = JSON.stringify(this.draft);
    form.timeoutDraft = this.timeoutDraft;
    form.applyToTitle = this.draftApplyToTitle;
    form.applyToContent = this.draftApplyToContent;
    form.isRegex = this.draftIsRegex;
    FormDraftStore.persistSoon(getContext(this), 'replace_rule:edit', JSON.stringify(form));
  }

  persistRuleFormDraftNow(): void {
    if (!this.editing) return;
    const form = new ReplaceRuleFormDraft();
    form.ruleJson = JSON.stringify(this.draft);
    form.timeoutDraft = this.timeoutDraft;
    form.applyToTitle = this.draftApplyToTitle;
    form.applyToContent = this.draftApplyToContent;
    form.isRegex = this.draftIsRegex;
    FormDraftStore.persist(getContext(this), 'replace_rule:edit', JSON.stringify(form));
  }

  openRuleActions(rule: ReaderReplaceRule, event?: GestureEvent): void {
    const finger = event && event.fingerList.length > 0 ? event.fingerList[0] : undefined;
    if (finger) {
      this.contextMenuX = finger.globalX;
      this.contextMenuY = finger.globalY;
    }
    this.actionRuleId = rule.id;
    this.showRuleActionDialog = true;
  }

  rememberRuleSelectionArea(ruleId: number, area: Area): void {
    const position = area.globalPosition;
    this.ruleSelectionAreas.set(ruleId, [Number(position.x), Number(position.y),
      Number(position.x) + Number(area.width), Number(position.y) + Number(area.height)]);
  }

  @Builder
  ruleSelectionSafeArea(rule: ReaderReplaceRule) {
    Stack({ alignContent: Alignment.Center }) {
      Toggle({ type: ToggleType.Checkbox, isOn: this.isRuleSelected(rule.id) })
        .selectedColor(this.buttonColor())
        .hitTestBehavior(HitTestMode.None)
    }
    .width(56)
    .height(68)
    .margin({ left: -10, right: AppSpacing.XXS })
    .priorityGesture(
      GestureGroup(GestureMode.Exclusive,
        PanGesture({ direction: PanDirection.Vertical, distance: 2 })
          .onActionStart((event: GestureEvent) => this.beginRuleSlideSelection(event))
          .onActionUpdate((event: GestureEvent) => this.updateRuleSlideSelection(event))
          .onActionEnd(() => this.endRuleSlideSelection())
          .onActionCancel(() => this.endRuleSlideSelection()),
        TapGesture().onAction(() => {
          if (!this.isBatchOperating) {
            this.ruleSelectionSuppressClickUntil = Date.now() + 240;
            this.toggleRuleSelected(rule.id);
          }
        })
      ),
      GestureMask.IgnoreInternal
    )
  }

  beginRuleSlideSelection(event: GestureEvent): void {
    if (!this.selectionMode || this.isBatchOperating) return;
    this.ruleDragVisited.clear();
    const ruleId = this.ruleAtGesture(event);
    if (ruleId <= 0) return;
    this.ruleSelectionDragging = true;
    this.captureRuleSelectionPoint(event);
    this.ruleDragSelectValue = !this.isRuleSelected(ruleId);
    this.applyRuleSlideSelection(ruleId);
    this.updateRuleSelectionAutoScroll();
  }

  updateRuleSlideSelection(event: GestureEvent): void {
    if (!this.selectionMode || this.isBatchOperating) return;
    this.captureRuleSelectionPoint(event);
    this.applyRuleSlideSelection(this.ruleAtGesture(event));
    this.updateRuleSelectionAutoScroll();
  }

  endRuleSlideSelection(): void {
    this.ruleSelectionSuppressClickUntil = Date.now() + 240;
    this.ruleSelectionDragging = false;
    this.ruleDragVisited.clear();
    this.stopRuleSelectionAutoScroll();
  }

  ruleAtGesture(event: GestureEvent): number {
    const finger = event.fingerList.length > 0 ? event.fingerList[0] : undefined;
    if (!finger) return 0;
    return this.ruleAtPoint(finger.globalX, finger.globalY);
  }

  ruleAtPoint(globalX: number, globalY: number): number {
    for (const rule of this.filteredRules()) {
      const area = this.ruleSelectionAreas.get(rule.id);
      if (area && globalX >= area[0] && globalX <= area[2] &&
        globalY >= area[1] && globalY <= area[3]) return rule.id;
    }
    return 0;
  }

  applyRuleSlideSelection(ruleId: number): void {
    if (ruleId <= 0 || this.ruleDragVisited.has(ruleId)) return;
    this.ruleDragVisited.add(ruleId);
    this.setRuleSelected(ruleId, this.ruleDragSelectValue);
  }

  captureRuleSelectionPoint(event: GestureEvent): void {
    const finger = event.fingerList.length > 0 ? event.fingerList[0] : undefined;
    if (!finger) return;
    this.ruleSelectionLastX = finger.globalX;
    this.ruleSelectionLastY = finger.globalY;
  }

  updateRuleSelectionAutoScroll(): void {
    if (!this.ruleSelectionDragging || this.ruleSelectionViewportBottom <= this.ruleSelectionViewportTop) {
      this.stopRuleSelectionAutoScroll();
      return;
    }
    const edgeSize = 72;
    let direction = 0;
    if (this.ruleSelectionLastY <= this.ruleSelectionViewportTop + edgeSize) direction = -1;
    if (this.ruleSelectionLastY >= this.ruleSelectionViewportBottom - edgeSize) direction = 1;
    if (direction === this.ruleSelectionAutoDirection && this.ruleSelectionAutoScrollId >= 0) return;
    this.stopRuleSelectionAutoScroll();
    if (direction === 0 || this.ruleSelectionReachedBoundary(direction)) return;
    this.ruleSelectionAutoDirection = direction;
    this.ruleSelectionAutoScrollId = setInterval(() => {
      if (!this.ruleSelectionDragging || this.ruleSelectionReachedBoundary(direction)) {
        this.stopRuleSelectionAutoScroll();
        return;
      }
      this.ruleListScroller.scrollBy(0, direction * 12);
      setTimeout(() => {
        if (!this.ruleSelectionDragging) return;
        this.applyRuleSlideSelection(this.ruleAtPoint(
          this.ruleSelectionLastX, this.ruleSelectionLastY));
      }, 0);
    }, 24);
  }

  ruleSelectionReachedBoundary(direction: number): boolean {
    if (direction < 0) return this.ruleFirstVisibleIndex <= 0;
    return this.ruleLastVisibleIndex >= this.filteredRules().length - 1;
  }

  stopRuleSelectionAutoScroll(): void {
    if (this.ruleSelectionAutoScrollId >= 0) {
      clearInterval(this.ruleSelectionAutoScrollId);
      this.ruleSelectionAutoScrollId = -1;
    }
    this.ruleSelectionAutoDirection = 0;
  }

  closeRuleActions(): void {
    this.showRuleActionDialog = false;
    this.actionRuleId = 0;
  }

  actionRule(): ReaderReplaceRule | undefined {
    return this.rules.find((rule: ReaderReplaceRule) => rule.id === this.actionRuleId);
  }

  actionRuleEnabled(): boolean {
    const rule = this.actionRule();
    return rule ? rule.enabled : false;
  }

  updateContextViewport(area: Area): void {
    const width = Number(area.width);
    const height = Number(area.height);
    if (Number.isFinite(width) && width > 0) this.contextViewportWidth = width;
    if (Number.isFinite(height) && height > 0) this.contextViewportHeight = height;
  }

  async saveDraft(): Promise<void> {
    const pattern = (this.draft.pattern || '').trim();
    if (!pattern) {
      HdsFeedback.showToast('请填写匹配规则');
      return;
    }
    if (!this.draftApplyToTitle && !this.draftApplyToContent) {
      HdsFeedback.showToast('请至少选择标题或正文');
      return;
    }
    if (this.draftIsRegex) {
      try {
        JavaRegexCompat.compile(pattern, 'g');
      } catch (error) {
        const reason = error instanceof Error ? error.message : String(error);
        HdsFeedback.showToast(`正则表达式无效：${reason}`);
        return;
      }
    }
    this.draft.pattern = pattern;
    this.draft.name = (this.draft.name || '').trim() || pattern.substring(0, 24);
    this.draft.group = (this.draft.group || '').trim() || '默认';
    this.draft.applyToTitle = this.draftApplyToTitle;
    this.draft.applyToContent = this.draftApplyToContent;
    this.draft.isRegex = this.draftIsRegex;
    const timeout = Number(this.timeoutDraft);
    this.draft.timeoutMs = Number.isNaN(timeout) ? 3000 : Math.max(100, Math.min(Math.round(timeout), 10000));
    const next = this.rules.filter((rule: ReaderReplaceRule) => rule.id !== this.draft.id);
    next.push(ReaderReplaceRuleStore.cloneRule(this.draft));
    await ReaderReplaceRuleStore.save(getContext(this), next);
    this.rules = await ReaderReplaceRuleStore.load(getContext(this), true);
    this.editing = false;
    FormDraftStore.removePersistent(getContext(this), 'replace_rule:edit');
    HdsFeedback.showToast('规则已保存');
  }

  async setRuleEnabled(id: number, enabled: boolean): Promise<void> {
    const next = this.rules.map((rule: ReaderReplaceRule) => {
      const copy = ReaderReplaceRuleStore.cloneRule(rule);
      if (copy.id === id) copy.enabled = enabled;
      return copy;
    });
    await ReaderReplaceRuleStore.save(getContext(this), next);
    this.rules = next;
  }

  async confirmDelete(rule: ReaderReplaceRule): Promise<void> {
    const result = await promptAction.showDialog({
      title: '删除规则',
      message: `确定删除“${rule.name || '未命名规则'}”吗？`,
      buttons: [{ text: '取消', color: this.secondaryTextColor() }, { text: '删除', color: ThemeRuntime.dangerColor(this.appDarkMode) }]
    });
    if (result.index !== 1) return;
    const next = this.rules.filter((item: ReaderReplaceRule) => item.id !== rule.id);
    await ReaderReplaceRuleStore.save(getContext(this), next);
    this.rules = next;
  }

  syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, this.pageColor());
  }

  pageColor(): string { return ThemeRuntime.pageColor(this.appDarkMode); }
  cardColor(): string { return ThemeRuntime.cardColor(this.appDarkMode); }
  inputColor(): string { return ThemeRuntime.inputColor(this.appDarkMode); }
  primaryTextColor(): string { return ThemeRuntime.primaryTextColor(this.appDarkMode); }
  secondaryTextColor(): string { return ThemeRuntime.subTextColor(this.appDarkMode); }
  subTextColor(): string { return ThemeRuntime.subTextColor(this.appDarkMode); }
  accentColor(): string { return ThemeRuntime.accentColor(this.appDarkMode); }
  buttonColor(): string { return ThemeRuntime.buttonColor(this.appDarkMode); }
}
