import { promptAction, router } from '@kit.ArkUI';
import { ImmersiveBackButton } from '../components/ImmersiveBackButton';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { Book } from '../model/data/Book';
import { ReaderReplaceRule, ReaderReplaceRuleCheck, ReaderReplaceRuleStore } from '../utils/ReaderReplaceRuleStore';
import { syncSystemBars } from '../utils/SystemBars';
import { ResponsiveManagerListLayout } from '../utils/ResponsiveManagerListLayout';

@Entry
@Component
struct ReaderReplaceRulesPage {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
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

  aboutToAppear(): void {
    this.loadPreviewContext();
    this.loadRules();
    this.syncBars();
  }

  onPageShow(): void {
    this.syncBars();
  }

  onBackPress(): boolean {
    if (this.selectionMode) {
      this.exitRuleSelectionMode();
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

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        this.titleBar()
        if (this.editing) {
          this.editorView()
        } else {
          this.managerView()
        }
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.statusBarHeight, bottom: this.navBarHeight })
      .backgroundColor(this.pageColor())

      if (!this.editing && !this.selectionMode) {
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(25)
            .fontColor([this.accentColor()])
        }
        .width(52)
        .height(52)
        .margin({ right: 22, bottom: this.navBarHeight + 22 })
        .backgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode, this.cardColor(), 'button'))
        .backdropBlur(ThemeRuntime.glassBlur('button', 12))
        .border({ width: ThemeRuntime.glassBorderWidth('button'), color: ThemeRuntime.glassBorderColor(this.appDarkMode, 'button') })
        .shadow({ radius: ThemeRuntime.glassShadowRadius('button'), color: ThemeRuntime.glassShadowColor(this.appDarkMode, 'button'), offsetX: ThemeRuntime.glassShadowOffsetX('button'), offsetY: ThemeRuntime.glassShadowOffsetY('button') })
        .accessibilityText('新增替换净化规则')
        .onClick(() => this.openNewRule())
      }

      if (this.showRuleActionDialog) {
        this.ruleActionDialog()
      }
    }
    .width('100%')
    .height('100%')
    .onAreaChange((_oldValue: Area, newValue: Area) => this.updateContextViewport(newValue))
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
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)
      if (!this.editing) {
        Text(this.selectionMode ? '取消' : '选择')
          .fontSize(15)
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
    .height(56)
    .backgroundColor(this.cardColor())
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  managerView() {
    Column() {
      if (this.previewMode) {
        this.currentChapterPreviewCard()
      }
      TextInput({ placeholder: '搜索规则名称或匹配内容', text: this.query })
        .height(44)
        .fontSize(14)
        .fontColor(this.primaryTextColor())
        .placeholderColor(this.subTextColor())
        .backgroundColor(this.inputColor())
        .borderRadius(22)
        .padding({ left: 16, right: 16 })
        .margin({ left: 16, right: 16, top: 12, bottom: 10 })
        .onChange((value: string) => this.query = value)

      if (this.selectionMode) {
        this.ruleSelectionHeader()
      }

      if (this.filteredRules().length === 0) {
        Column({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.arrow_left_arrow_right'))
            .fontSize(36)
            .fontColor([this.subTextColor()])
          Text(this.query ? '没有匹配的规则' : '暂无替换净化规则')
            .fontSize(15)
            .fontColor(this.secondaryTextColor())
          Text(this.query ? '尝试更换搜索词' : '点击右下角添加规则')
            .fontSize(13)
            .fontColor(this.subTextColor())
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 10 }) {
          ForEach(this.filteredRules(), (rule: ReaderReplaceRule) => {
            ListItem() {
              this.ruleCard(rule)
            }
            .swipeAction(this.selectionMode ? {} : {
              start: {
                builder: () => {
                  this.ruleEnableSwipeAction(rule)
                },
                actionAreaDistance: 64,
                onAction: () => this.setRuleEnabled(rule.id, !rule.enabled)
              },
              end: {
                builder: () => {
                  this.ruleDeleteSwipeAction(rule)
                },
                actionAreaDistance: 64,
                onAction: () => this.confirmDelete(rule)
              },
              edgeEffect: SwipeEdgeEffect.Spring
            })
          }, (rule: ReaderReplaceRule) =>
            `${rule.id}_${rule.enabled ? '1' : '0'}_${this.selectionMode ? 'select' : 'normal'}`)

          ListItem() {
            Column().height(84)
          }
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ left: 16, right: 16 })
        .lanes(ResponsiveManagerListLayout.laneCount(this.contextViewportWidth),
          ResponsiveManagerListLayout.gutter(this.contextViewportWidth))
      }

      if (this.selectionMode) {
        this.ruleBatchBar()
      }
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  ruleCard(rule: ReaderReplaceRule) {
    Row() {
      if (this.selectionMode) {
        Toggle({ type: ToggleType.Checkbox, isOn: this.isRuleSelected(rule.id) })
          .selectedColor(this.buttonColor())
          .margin({ right: 12 })
          .onChange((selected: boolean) => this.setRuleSelected(rule.id, selected))
      }

      Column({ space: 5 }) {
        Text(rule.name || '未命名规则')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.primaryTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(rule.pattern || '未填写匹配规则')
          .fontSize(13)
          .fontColor(this.secondaryTextColor())
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(this.ruleScopeSummary(rule))
          .fontSize(12)
          .fontColor(this.subTextColor())

        if (this.previewMode) {
          Text(this.ruleEffectLabel(rule))
            .fontSize(12)
            .fontColor(this.ruleEffectColor(rule))
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      SymbolGlyph(rule.enabled ? $r('sys.symbol.checkmark_circle') : $r('sys.symbol.minus_circle'))
        .fontSize(20)
        .fontColor([rule.enabled ? this.accentColor() : this.subTextColor()])
        .margin({ left: 12 })
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.cardColor())
    .borderRadius(14)
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
        this.toggleRuleSelected(rule.id);
      } else {
        this.openEditRule(rule);
      }
    })
  }

  @Builder
  currentChapterPreviewCard() {
    Column({ space: 8 }) {
      Row() {
        Column({ space: 3 }) {
          Text('当前章节生效检查')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.primaryTextColor())
          Text(this.previewTitle || '当前章节')
            .fontSize(12)
            .fontColor(this.subTextColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Text(this.previewSummaryText())
          .fontSize(12)
          .fontColor(this.previewEffectiveCount() > 0 ? '#1E8E3E' : this.subTextColor())
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.previewChanged()) {
        Column({ space: 3 }) {
          Text('替换前').fontSize(11).fontColor(this.subTextColor()).width('100%')
          Text(this.previewBeforeExcerpt())
            .fontSize(12)
            .fontColor(this.secondaryTextColor())
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Text('替换后').fontSize(11).fontColor(this.subTextColor()).width('100%').margin({ top: 3 })
          Text(this.previewAfterExcerpt())
            .fontSize(12)
            .fontColor(this.primaryTextColor())
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        .width('100%')
        .padding(10)
        .borderRadius(10)
        .backgroundColor(this.inputColor())
      } else {
        Text(this.rules.length === 0 ? '尚未配置规则，可点击右下角新增。' :
          '当前规则未改变本章内容；可查看每条规则下方的检查状态。')
          .fontSize(12)
          .fontColor(this.secondaryTextColor())
          .width('100%')
      }
    }
    .width('calc(100% - 32vp)')
    .padding(14)
    .margin({ left: 16, right: 16, top: 12 })
    .borderRadius(14)
    .backgroundColor(this.cardColor())
    .border({ width: ThemeRuntime.glassBorderWidth(), color: ThemeRuntime.glassBorderColor(this.appDarkMode) })
  }

  loadPreviewContext(): void {
    const params = router.getParams() as Record<string, string>;
    if (!params || params['previewCurrentChapter'] !== 'true') return;
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

  ruleEffectCheck(rule: ReaderReplaceRule): ReaderReplaceRuleCheck {
    return ReaderReplaceRuleStore.checkRule(
      rule, this.previewBook, this.previewTitle, this.previewContent);
  }

  ruleEffectLabel(rule: ReaderReplaceRule): string {
    return this.ruleEffectCheck(rule).label;
  }

  ruleEffectColor(rule: ReaderReplaceRule): string {
    const state = this.ruleEffectCheck(rule).state;
    if (state === 'effective') return '#1E8E3E';
    if (state === 'invalid') return '#E53935';
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
        .fontSize(20)
        .fontColor(this.accentColor())
        .width(28)
        .textAlign(TextAlign.Center)
        .onClick(() => this.toggleAllVisibleRules())
      Text(`已选择 ${this.selectedRuleIds.length}/${this.filteredRules().length}`)
        .fontSize(14)
        .fontColor(this.subTextColor())
        .margin({ left: 8 })
        .layoutWeight(1)
      Text(this.areAllVisibleRulesSelected() ? '取消全选' : '全选')
        .fontSize(14)
        .fontColor(this.accentColor())
        .onClick(() => this.toggleAllVisibleRules())
    }
    .width('100%')
    .height(42)
    .padding({ left: 16, right: 16 })
  }

  @Builder
  ruleBatchBar() {
    Row() {
      Button('启用')
        .layoutWeight(1)
        .height(42)
        .enabled(this.selectedRuleIds.length > 0 && !this.isBatchOperating)
        .backgroundColor(this.buttonColor())
        .fontColor('#FFFFFF')
        .onClick(() => this.batchSetRulesEnabled(true))
      Button('禁用')
        .layoutWeight(1)
        .height(42)
        .margin({ left: 8 })
        .enabled(this.selectedRuleIds.length > 0 && !this.isBatchOperating)
        .backgroundColor(this.inputColor())
        .fontColor(this.primaryTextColor())
        .onClick(() => this.batchSetRulesEnabled(false))
      Button('删除')
        .layoutWeight(1)
        .height(42)
        .margin({ left: 8 })
        .enabled(this.selectedRuleIds.length > 0 && !this.isBatchOperating)
        .backgroundColor('#E53935')
        .fontColor('#FFFFFF')
        .onClick(() => this.batchDeleteRules())
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 12 })
    .backgroundColor(this.cardColor())
  }

  @Builder
  editorView() {
    Scroll() {
      Column({ space: 12 }) {
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

        Row({ space: 8 }) {
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

        Row({ space: 12 }) {
          Button('取消', { type: ButtonType.Capsule })
            .layoutWeight(1)
            .height(44)
            .fontColor(this.primaryTextColor())
            .backgroundColor(this.inputColor())
            .onClick(() => this.closeEditor())
          Button('保存', { type: ButtonType.Capsule })
            .layoutWeight(1)
            .height(44)
            .fontColor('#FFFFFF')
            .backgroundColor(this.buttonColor())
            .onClick(() => this.saveDraft())
        }
        .width('100%')
        .margin({ top: 8, bottom: 28 })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14 })
    }
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
    Column({ space: 6 }) {
      Text(label).fontSize(13).fontColor(this.subTextColor()).width('100%')
      TextInput({ placeholder: placeholder, text: value })
        .type(inputType)
        .width('100%')
        .height(46)
        .fontSize(15)
        .fontColor(this.primaryTextColor())
        .placeholderColor(this.subTextColor())
        .backgroundColor(this.inputColor())
        .borderRadius(12)
        .onChange(onChange)
    }
    .width('100%')
  }

  @Builder
  textAreaField(label: string, value: string, placeholder: string, onChange: (value: string) => void) {
    Column({ space: 6 }) {
      Text(label).fontSize(13).fontColor(this.subTextColor()).width('100%')
      TextArea({ placeholder: placeholder, text: value })
        .width('100%')
        .height(86)
        .fontSize(14)
        .fontColor(this.primaryTextColor())
        .placeholderColor(this.subTextColor())
        .backgroundColor(this.inputColor())
        .borderRadius(12)
        .padding(12)
        .onChange(onChange)
    }
    .width('100%')
  }

  @Builder
  titleOptionChip() {
    Button({ type: ButtonType.Capsule, stateEffect: true }) {
      Row({ space: 5 }) {
        if (this.draftApplyToTitle) {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(14)
            .fontColor([this.accentColor()])
        }
        Text('标题')
          .fontSize(13)
          .fontColor(this.draftApplyToTitle ? this.accentColor() : this.secondaryTextColor())
      }
    }
    .height(36)
    .padding({ left: 12, right: 12 })
    .backgroundColor(this.draftApplyToTitle ? ThemeRuntime.accentSurfaceColor(this.appDarkMode) : this.inputColor())
    .borderRadius(18)
    .onClick(() => {
      this.draftApplyToTitle = !this.draftApplyToTitle;
    })
  }

  @Builder
  contentOptionChip() {
    Button({ type: ButtonType.Capsule, stateEffect: true }) {
      Row({ space: 5 }) {
        if (this.draftApplyToContent) {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(14)
            .fontColor([this.accentColor()])
        }
        Text('正文')
          .fontSize(13)
          .fontColor(this.draftApplyToContent ? this.accentColor() : this.secondaryTextColor())
      }
    }
    .height(36)
    .padding({ left: 12, right: 12 })
    .backgroundColor(this.draftApplyToContent ? ThemeRuntime.accentSurfaceColor(this.appDarkMode) : this.inputColor())
    .borderRadius(18)
    .onClick(() => {
      this.draftApplyToContent = !this.draftApplyToContent;
    })
  }

  @Builder
  regexOptionChip() {
    Button({ type: ButtonType.Capsule, stateEffect: true }) {
      Row({ space: 5 }) {
        if (this.draftIsRegex) {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(14)
            .fontColor([this.accentColor()])
        }
        Text('使用正则')
          .fontSize(13)
          .fontColor(this.draftIsRegex ? this.accentColor() : this.secondaryTextColor())
      }
    }
    .height(36)
    .padding({ left: 12, right: 12 })
    .backgroundColor(this.draftIsRegex ? ThemeRuntime.accentSurfaceColor(this.appDarkMode) : this.inputColor())
    .borderRadius(18)
    .onClick(() => {
      this.draftIsRegex = !this.draftIsRegex;
    })
  }

  @Builder
  ruleEnableSwipeAction(rule: ReaderReplaceRule) {
    Column({ space: 4 }) {
      SymbolGlyph(rule.enabled ? $r('sys.symbol.minus_circle') : $r('sys.symbol.checkmark_circle'))
        .fontSize(22)
        .fontColor(['#FFFFFF'])
      Text(rule.enabled ? '禁用' : '启用')
        .fontSize(11)
        .fontColor('#FFFFFF')
    }
    .width(72)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(rule.enabled ? '#F39C3D' : '#1E8E3E')
    .onClick(() => this.setRuleEnabled(rule.id, !rule.enabled))
  }

  @Builder
  ruleDeleteSwipeAction(rule: ReaderReplaceRule) {
    Column({ space: 4 }) {
      SymbolGlyph($r('sys.symbol.trash'))
        .fontSize(22)
        .fontColor(['#FFFFFF'])
      Text('删除')
        .fontSize(11)
        .fontColor('#FFFFFF')
    }
    .width(72)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#E53935')
    .onClick(() => this.confirmDelete(rule))
  }

  @Builder
  ruleActionDialog() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.appDarkMode ? '#52000000' : '#26FFFFFF')
        .backdropBlur(ThemeRuntime.glassBlur('popover', 18))
        .onClick(() => this.closeRuleActions())
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
        this.contextActionItem($r('sys.symbol.trash'), '删除', '#E53935', () => {
          const rule = this.actionRule();
          this.closeRuleActions();
          if (rule) this.confirmDelete(rule);
        })
      }
      .width(158)
      .padding({ top: 6, bottom: 6 })
      .backgroundColor(ThemeRuntime.glassPanelColor(this.appDarkMode, '', 'panel'))
      .borderRadius(ThemeRuntime.glassCornerRadius(14, 'panel'))
      .backdropBlur(ThemeRuntime.glassBlur('panel', 22))
      .border({ width: ThemeRuntime.glassBorderWidth('panel'), color: ThemeRuntime.glassBorderColor(this.appDarkMode, 'panel') })
      .shadow({ radius: ThemeRuntime.glassShadowRadius('panel'), color: ThemeRuntime.glassShadowColor(this.appDarkMode, 'panel'), offsetX: ThemeRuntime.glassShadowOffsetX('panel'), offsetY: ThemeRuntime.glassShadowOffsetY('panel') })
      .position({ x: this.contextMenuLeft(158), y: this.contextMenuTop(188) })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  contextActionItem(icon: Resource, label: string, color: string, action: () => void) {
    Row({ space: 10 }) {
      SymbolGlyph(icon)
        .fontSize(18)
        .fontColor([color])
        .width(24)
      Text(label)
        .fontSize(15)
        .fontColor(color)
        .layoutWeight(1)
    }
    .width('100%')
    .height(44)
    .padding({ left: 12, right: 12 })
    .alignItems(VerticalAlign.Center)
    .onClick(action)
  }

  filteredRules(): ReaderReplaceRule[] {
    const keyword = (this.query || '').trim().toLowerCase();
    if (!keyword) {
      return this.rules;
    }
    return this.rules.filter((rule: ReaderReplaceRule) =>
      `${rule.name}\n${rule.pattern}`.toLowerCase().includes(keyword));
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
      promptAction.showToast({ message: `已${enabled ? '启用' : '禁用'} ${count} 条规则` });
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
      buttons: [{ text: '取消', color: this.secondaryTextColor() }, { text: '删除', color: '#E53935' }]
    });
    if (result.index !== 1) return;
    this.isBatchOperating = true;
    try {
      const next = this.rules.filter((rule: ReaderReplaceRule) => !this.selectedRuleIds.includes(rule.id));
      await ReaderReplaceRuleStore.save(getContext(this), next);
      this.rules = next;
      this.exitRuleSelectionMode();
      promptAction.showToast({ message: `已删除 ${count} 条规则` });
    } finally {
      this.isBatchOperating = false;
    }
  }

  openNewRule(): void {
    this.draft = ReaderReplaceRuleStore.newRule();
    this.draftApplyToTitle = this.draft.applyToTitle;
    this.draftApplyToContent = this.draft.applyToContent;
    this.draftIsRegex = this.draft.isRegex;
    this.timeoutDraft = '3000';
    this.editing = true;
  }

  openEditRule(rule: ReaderReplaceRule): void {
    this.draft = ReaderReplaceRuleStore.cloneRule(rule);
    this.draftApplyToTitle = this.draft.applyToTitle;
    this.draftApplyToContent = this.draft.applyToContent;
    this.draftIsRegex = this.draft.isRegex;
    this.timeoutDraft = `${this.draft.timeoutMs}`;
    this.editing = true;
  }

  closeEditor(): void {
    this.editing = false;
  }

  refreshDraft(): void {
    this.draft = ReaderReplaceRuleStore.cloneRule(this.draft);
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

  contextMenuLeft(menuWidth: number): number {
    return Math.max(12, Math.min(this.contextMenuX - 18, this.contextViewportWidth - menuWidth - 12));
  }

  contextMenuTop(menuHeight: number): number {
    const below = this.contextMenuY + 12;
    if (below + menuHeight <= this.contextViewportHeight - this.navBarHeight - 12) return below;
    return Math.max(this.statusBarHeight + 8, this.contextMenuY - menuHeight - 12);
  }

  async saveDraft(): Promise<void> {
    const pattern = (this.draft.pattern || '').trim();
    if (!pattern) {
      promptAction.showToast({ message: '请填写匹配规则' });
      return;
    }
    if (!this.draftApplyToTitle && !this.draftApplyToContent) {
      promptAction.showToast({ message: '请至少选择标题或正文' });
      return;
    }
    if (this.draftIsRegex) {
      try {
        new RegExp(pattern, 'g');
      } catch (_) {
        promptAction.showToast({ message: '正则表达式无效' });
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
    promptAction.showToast({ message: '规则已保存' });
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
      buttons: [{ text: '取消', color: this.secondaryTextColor() }, { text: '删除', color: '#E53935' }]
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
