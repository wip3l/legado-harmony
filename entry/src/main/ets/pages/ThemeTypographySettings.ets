import { promptAction, router } from '@kit.ArkUI';
import { syncSystemBars } from '../utils/SystemBars';
import { ReaderSettings, ReaderSettingsStore } from '../utils/ReaderSettingsStore';
import { ThemeTypographyDraft } from '../utils/ThemeTypographyDraft';
import { AppThemeSettingsStore } from '../utils/AppThemeSettingsStore';
import { CustomThemeScheme, CustomThemeSchemeStore } from '../utils/CustomThemeSchemeStore';
import { ReaderThemeHelper, ReaderThemeItem } from '../utils/ReaderThemeHelper';
import { ReaderFontHelper, ReaderFontItem } from '../utils/ReaderFontHelper';
import { ReaderFontBootstrap } from '../utils/ReaderFontBootstrap';
import { ReaderSystemFontHelper } from '../utils/ReaderSystemFontHelper';
import { ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';
import { HdsFeedback } from '../utils/HdsFeedback';
import { ThemeIds, ThemePack, ThemeVariant } from '../theme/ThemeModels';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { ReaderThemeBackground } from '../components/ReaderThemeBackground';
import { ImmersiveMaterialSurface } from '../components/ImmersiveMaterialSurface';
import {
  ReaderHeaderFooterEditor,
  ReaderTypographyField,
  ReaderTypographyStepper
} from '../components/reader/ReaderLayoutSettings';
import { ReaderInfoBarRow } from '../components/reader/ReaderInfoBar';
import { PageScaffold } from '../components/common/PageScaffold';
import { SettingNavRow, SettingRow, SettingSwitchRow } from '../components/common/SettingRow';
import {
  ReaderInfoBarConfig,
  ReaderInfoBarContext,
  ReaderInfoBarText,
  ReaderInfoProgressBar
} from '../core/reader/ReaderInfoBarModel';
import { ReaderInfoBarClock } from '../core/reader/ReaderInfoBarClock';
import { ReaderParagraphIndent } from '../core/reader/ReaderParagraphIndent';
import {
  ReaderRegexBubbleStyleResolver,
  ReaderRegexEmphasisContext,
  ReaderRegexFontCodec,
  ReaderRegexFontRule,
  ReaderRegexLegacySettings,
  ReaderResolvedRegexEmphasis
} from '../model/reader/ReaderRegexFontRule';

class ThemeTypographyFontItem {
  familyName: string = '';
  filePath: string = '';
  sourceName: string = '';
}

class ThemeTypographyFontData {
  fonts: ThemeTypographyFontItem[] = [];
}

/** 示例正文里的一段文字；rule 为命中的强调规则下标，-1 表示普通正文。 */
class TypographyPreviewSlice {
  text: string = '';
  rule: number = -1;
  key: string = '';
}

/** 一页能放下多少正文：标题的行数、完整显示的段落数，以及最后一段截到第几行（0 表示不截）。 */
class TypographyPreviewFit {
  titleLines: number = 0;
  paragraphCount: number = 0;
  lastLines: number = 0;
}

const TOOLBAR_CONTROL_HEIGHT: number = 40;
const MODE_SWITCH_WIDTH: number = 152;
const MODE_SWITCH_INSET: number = 4;
const FULL_PREVIEW_BUTTON_WIDTH: number = 112;
const PREVIEW_BOOK_NAME: string = '长街灯火';
const PREVIEW_AUTHOR: string = '佚名';
const PREVIEW_CHAPTER_TITLE: string = '第一章 风起';
const PREVIEW_PARAGRAPHS: string[] = [
  '入秋以后，城南的风总是来得比别处早一些。傍晚时分，长街两侧的灯笼次第亮起，卖桂花糕的老人推着木车，慢慢从巷口拐了出来。',
  '林晚把书摊收到一半，抬头便看见对面茶楼的二楼窗口还亮着。那扇窗已经空了整整三年，如今却有人坐在那里，像是在等什么。',
  '“姑娘，这本旧书还卖吗？”一个清朗的声音在摊前响起。',
  '她低头一看，来人手里拿着的是一册蓝布封面的游记，边角早已磨得发白。那是父亲留下的书，她从没打算卖给任何人。',
  '“不卖。”林晚伸手把书接了回来，“这本只是摆着，算不得货。”',
  '那人也不恼，只笑着点了点头，目光落在书脊上那行褪了色的小字上，停了很久。',
  '风从街口灌进来，吹得纸页沙沙作响。远处的钟楼敲过七下，雾气顺着河面一点点漫上石阶，把灯火揉成一团团温暖的光晕。',
  '“三年前，有人在这里托我带一句话。”他终于开口，声音压得很低，“他说，等桂花开第二遍的时候，书会自己找到回家的路。”',
  '林晚的手指微微一顿。她想起父亲临行前的那个夜晚，也是这样的风，这样的灯，还有那句当时怎么也听不懂的叮嘱。',
  '她没有再说话，只是把那册游记轻轻放回了摊上最显眼的位置。',
  '夜色渐深，长街上的行人一点点散去。茶楼的窗口依旧亮着，像一盏不肯熄灭的灯，静静守着这条街上所有尚未讲完的故事。',
  '而故事，往往就是从这样一个平常的夜晚开始的。'
];

/**
 * 自定义主题的排版页：上方用这套主题的阅读背景、配色和强调样式模拟一页真实正文，
 * 下方是正文排版的全部选项（含阅读字体的下级设置）。修改只改草稿，保存后写进该主题的阅读档案，
 * 之后切换到这套主题时排版随之生效。
 */
@Entry
@Component
struct ThemeTypographySettingsPage {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @StorageProp('readerFontFamily') readerFontFamily: string = '';
  @StorageProp('readerSystemFontFamily') readerSystemFontFamily: string = '';
  @StorageProp('readerFontMode') readerFontMode: string = 'device';
  @StorageProp('readerFontSourceName') readerFontSourceName: string = '系统默认';
  @StorageProp('readerCustomFontsRaw') readerCustomFontsRaw: string = '';
  @State draft: ReaderSettings = new ReaderSettings();
  @State headerEnabled: boolean = false;
  @State footerEnabled: boolean = true;
  @State infoBarConfig: string = '';
  @State loaded: boolean = false;
  @State dirty: boolean = false;
  @State saving: boolean = false;
  @State schemeName: string = '';
  @State activeScheme: boolean = false;
  @State typographyBound: boolean = false;
  @State previewDark: boolean = false;
  @State fullPreview: boolean = false;
  @State viewportWidth: number = 0;
  @State viewportHeight: number = 0;
  @State stepperKey: number = 0;
  @State previewRules: ReaderRegexFontRule[] = [];
  @State previewRevision: number = 0;
  @State windowFit: TypographyPreviewFit = new TypographyPreviewFit();
  @State fullFit: TypographyPreviewFit = new TypographyPreviewFit();
  private schemeId: string = '';
  private profileId: string = '';
  private themePack: ThemePack | null = null;
  private fontDraftRevision: number = -1;
  private leaving: boolean = false;
  private fullPreviewHintShown: boolean = false;
  private timeText: string = ReaderInfoBarClock.timeText();
  private batteryPercent: number = ReaderInfoBarClock.batteryPercent();

  aboutToAppear(): void {
    this.previewDark = this.appDarkMode;
    this.loadDraft();
    this.syncBars();
  }

  onPageShow(): void {
    this.syncBars();
    this.pullFontDraft();
  }

  onBackPress(): boolean {
    if (this.fullPreview) {
      this.closeFullPreview();
      return true;
    }
    this.requestClose();
    return true;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      PageScaffold({ title: '主题排版', scrollable: false, collapsible: false, onBack: () => this.requestClose(),
        content: () => {
          this.pageContent()
        }, actions: () => {
          this.titleActions()
        } })

      if (this.fullPreview) {
        this.fullPreviewOverlay()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      const width = Number(newValue.width);
      const height = Number(newValue.height);
      if (width > 0 && height > 0 && (Math.abs(width - this.viewportWidth) >= 1 ||
        Math.abs(height - this.viewportHeight) >= 1)) {
        this.viewportWidth = width;
        this.viewportHeight = height;
        this.refreshPreview();
      }
    })
  }

  @Builder
  titleActions() {
    Text(this.saving ? '保存中' : '保存')
      .fontSize(AppFontSize.BODY_LARGE)
      .fontColor(this.loaded && !this.saving ? this.accentColor() : this.subTextColor())
      .width(60)
      .height(56)
      .textAlign(TextAlign.Center)
      .accessibilityText('保存主题排版')
      .onClick(() => {
        this.save();
      })
  }

  @Builder
  pageContent() {
    Column() {
      this.previewWindow()
      this.previewToolbar()
      Scroll() {
        Column() {
          this.settingsContent()
        }
        .width('100%')
        .padding({ bottom: AppSpacing.XXL + this.navBarHeight })
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.TopStart)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }
    .width('100%')
    .height('100%')
  }

  // ---------- 预览 ----------

  @Builder
  previewWindow() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.loaded) {
        this.previewPage(false)
      }
    }
    .width(this.previewWindowWidth())
    .height(this.windowHeight())
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(this.previewTheme().backgroundColor)
    .border({ width: 0.5, color: ThemeRuntime.hairlineColor(this.appDarkMode) })
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.XS })
    .onClick(() => this.openFullPreview())
    .accessibilityText('正文预览，轻触全屏查看')
  }

  @Builder
  previewToolbar() {
    Row({ space: AppSpacing.MD }) {
      this.previewModeSwitch()

      Blank()
        .layoutWeight(1)

      ImmersiveMaterialSurface({
        surfaceWidth: FULL_PREVIEW_BUTTON_WIDTH,
        surfaceHeight: TOOLBAR_CONTROL_HEIGHT,
        darkMode: this.appDarkMode,
        fallbackColor: this.cardColor(),
        glowColor: this.accentGlowColor()
      }) {
        Row({ space: AppSpacing.XS }) {
          SymbolGlyph($r('sys.symbol.arrow_up_left_and_arrow_down_right'))
            .fontSize(16)
            .fontColor([this.accentColor()])
          Text('全屏预览')
            .fontSize(AppFontSize.BODY)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.accentColor())
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .accessibilityText('全屏预览')
        .onClick(() => this.openFullPreview())
      }
    }
    .width('100%')
    .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.MD, bottom: AppSpacing.XS })
    .alignItems(VerticalAlign.Center)
  }

  /**
   * 浅色/深色预览切换：沉浸光感胶囊底板上两段等宽选项，选中项下面垫一块滑动的强调色底。
   * 选中状态在 builder 里直接读 previewDark，不经参数按值传入，点按后立即刷新。
   */
  @Builder
  previewModeSwitch() {
    ImmersiveMaterialSurface({
      surfaceWidth: MODE_SWITCH_WIDTH,
      surfaceHeight: TOOLBAR_CONTROL_HEIGHT,
      darkMode: this.appDarkMode,
      fallbackColor: this.cardColor(),
      glowColor: this.accentGlowColor()
    }) {
      Stack({ alignContent: Alignment.Start }) {
        Row()
          .width(this.modeOptionWidth() - MODE_SWITCH_INSET * 2)
          .height(TOOLBAR_CONTROL_HEIGHT - MODE_SWITCH_INSET * 2)
          .borderRadius((TOOLBAR_CONTROL_HEIGHT - MODE_SWITCH_INSET * 2) / 2)
          .backgroundColor(ThemeRuntime.accentSurfaceColor(this.appDarkMode))
          .translate({ x: MODE_SWITCH_INSET + (this.previewDark ? this.modeOptionWidth() : 0) })
          .animation({ duration: 280, curve: Curve.Friction })
          .hitTestBehavior(HitTestMode.None)
        Row() {
          this.previewModeOption(false)
          this.previewModeOption(true)
        }
        .width('100%')
        .height('100%')
      }
      .width('100%')
      .height('100%')
    }
  }

  @Builder
  previewModeOption(dark: boolean) {
    Row({ space: AppSpacing.XS }) {
      SymbolGlyph(dark ? $r('sys.symbol.moon') : $r('sys.symbol.sun_max'))
        .fontSize(15)
        .fontColor([this.previewDark === dark ? this.accentColor() : this.subTextColor()])
      Text(dark ? '深色' : '浅色')
        .fontSize(AppFontSize.BODY)
        .fontWeight(this.previewDark === dark ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.previewDark === dark ? this.accentColor() : this.subTextColor())
        .animation({ duration: 180, curve: Curve.Friction })
    }
    .width(this.modeOptionWidth())
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .accessibilityText(dark ? '预览深色模式' : '预览浅色模式')
    .accessibilitySelected(this.previewDark === dark)
    .onClick(() => this.setPreviewDark(dark))
  }

  modeOptionWidth(): number {
    return MODE_SWITCH_WIDTH / 2;
  }

  accentGlowColor(): string {
    return `#40${this.accentColor().substring(1)}`;
  }

  @Builder
  fullPreviewOverlay() {
    Stack({ alignContent: Alignment.TopStart }) {
      this.previewPage(true)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.previewTheme().backgroundColor)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.FastOutSlowIn }))
    .accessibilityText('全屏正文预览，轻触任意位置返回')
    .onClick(() => this.closeFullPreview())
  }

  /** 一页正文：背景、页眉、标题与段落、页脚。full 为 true 时按整屏（含状态栏与导航条）排布。 */
  @Builder
  previewPage(full: boolean) {
    ReaderThemeBackground({
      surfaceColor: this.previewTheme().backgroundColor,
      backgroundAssetId: this.previewTheme().backgroundAssetId,
      compact: !full
    })

    if (this.headerVisible()) {
      Column({ space: 3 }) {
        Row() {
          ReaderInfoBarRow({
            leftText: this.infoSlotText(this.infoConfig().headerLeft),
            centerText: this.infoSlotText(this.infoConfig().headerCenter),
            rightText: this.infoSlotText(this.infoConfig().headerRight),
            leftBattery: this.infoSlotBattery(this.infoConfig().headerLeft),
            centerBattery: this.infoSlotBattery(this.infoConfig().headerCenter),
            rightBattery: this.infoSlotBattery(this.infoConfig().headerRight),
            textSize: this.infoConfig().headerFontSize,
            textColor: this.infoConfig().textColor(true, this.previewTheme().subTextColor),
            textOpacity: this.infoConfig().headerOpacity / 100
          })
        }
        .width('100%')
        .height(this.infoConfig().headerLineHeight())
        .alignItems(VerticalAlign.Center)

        if (this.infoConfig().progressBar === ReaderInfoProgressBar.HEADER) {
          this.infoAccentLine(true)
        } else if (this.infoConfig().headerDivider) {
          this.infoAccentLine(false)
        }
      }
      .width('100%')
      .padding({
        top: this.statusInset(full) + this.headerTopGap(),
        left: this.infoSidePadding(true, true),
        right: this.infoSidePadding(true, false)
      })
    }

    Column() {
      if (this.fitFor(full).titleLines > 0) {
        Text(PREVIEW_CHAPTER_TITLE)
          .fontSize(this.draft.titleFontSize)
          .fontWeight(600)
          .fontFamily(this.titleFontFamily())
          .fontColor(this.previewTheme().textColor)
          .letterSpacing(this.draft.letterSpacing)
          .lineHeight(`${this.titleLineBox()}vp`)
          .maxLines(this.fitFor(full).titleLines)
          .width('100%')
          .margin({ bottom: this.draft.paragraphSpacing })
      }
      ForEach(this.visibleParagraphIndexes(full), (index: number) => {
        this.previewParagraph(index, this.paragraphMaxLines(full, index))
      }, (index: number) => `paragraph_${index}_${this.paragraphMaxLines(full, index)}`)
    }
    .width('100%')
    .height(Math.max(0, this.bodyLimit(full) - this.bodyTop(full)))
    .padding({ left: this.draft.marginLeft, right: this.draft.marginRight })
    .margin({ top: this.bodyTop(full) })
    .clip(true)
    .alignItems(HorizontalAlign.Start)

    if (this.footerEnabled) {
      Column({ space: 3 }) {
        if (this.infoConfig().progressBar === ReaderInfoProgressBar.FOOTER) {
          this.infoAccentLine(true)
        } else if (this.infoConfig().footerDivider) {
          this.infoAccentLine(false)
        }
        ReaderInfoBarRow({
          leftText: this.infoSlotText(this.infoConfig().footerLeft),
          centerText: this.infoSlotText(this.infoConfig().footerCenter),
          rightText: this.infoSlotText(this.infoConfig().footerRight),
          leftBattery: this.infoSlotBattery(this.infoConfig().footerLeft),
          centerBattery: this.infoSlotBattery(this.infoConfig().footerCenter),
          rightBattery: this.infoSlotBattery(this.infoConfig().footerRight),
          textSize: this.infoConfig().footerFontSize,
          textColor: this.infoConfig().textColor(false, this.previewTheme().subTextColor),
          textOpacity: this.infoConfig().footerOpacity / 100
        })
      }
      .width('100%')
      .padding({ left: this.infoSidePadding(false, true), right: this.infoSidePadding(false, false) })
      .position({ left: 0, bottom: this.footerBottomInset(full) })
    }
  }

  @Builder
  previewParagraph(index: number, maxLines: number) {
    Text() {
      ForEach(this.paragraphSlices(index), (slice: TypographyPreviewSlice) => {
        if (slice.rule < 0) {
          Span(slice.text)
        } else {
          Span(slice.text)
            .fontSize(this.ruleAt(slice.rule).fontSize)
            .fontFamily(this.styledFontFamily(this.ruleAt(slice.rule).fontMode, this.ruleAt(slice.rule).fontFamily))
            .fontColor(this.ruleEmphasis(slice.rule).textColor)
            .textBackgroundStyle(this.ruleBackground(slice.rule))
            .textShadow(this.ruleShadow(slice.rule))
            .decoration(this.ruleDecoration(slice.rule))
        }
      }, (slice: TypographyPreviewSlice) => slice.key)
    }
    .fontSize(this.draft.fontSize)
    .fontWeight(this.draft.fontWeight)
    .fontFamily(this.bodyFontFamily())
    .fontColor(this.previewTheme().textColor)
    .letterSpacing(this.draft.letterSpacing)
    .lineHeight(`${this.bodyLineBox()}vp`)
    .textAlign(this.textAlignValue())
    .maxLines(maxLines > 0 ? maxLines : 1000)
    .textOverflow({ overflow: TextOverflow.Clip })
    .width('100%')
    .margin({ bottom: this.draft.paragraphSpacing })
  }

  @Builder
  infoAccentLine(progress: boolean) {
    if (progress) {
      Progress({ value: 22, total: 100, type: ProgressType.Linear })
        .width('100%')
        .height(2)
        .color(this.previewVariant().colors.accentColor)
        .backgroundColor(this.previewTrackColor())
    } else {
      Row()
        .width('100%')
        .height(0.5)
        .backgroundColor(this.previewTheme().subTextColor)
        .opacity(0.35)
    }
  }

  // ---------- 设置 ----------

  @Builder
  settingsContent() {
    Column({ space: AppSpacing.XS }) {
      Text(this.schemeName ? `「${this.schemeName}」` : '自定义主题')
        .fontSize(AppFontSize.BODY_LARGE)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.primaryTextColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Text(this.statusText())
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.dirty ? this.accentColor() : this.subTextColor())
        .width('100%')
    }
    .width('100%')
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG })

    if (this.loaded) {
      this.sectionTitle('正文排版')
      Column() {
        ForEach([this.stepperKey], (key: number) => {
          Row() {
            ReaderTypographyStepper({
              initialValues: this.typographyValues(),
              dark: this.appDarkMode,
              textColor: this.primaryTextColor(),
              subTextColor: this.subTextColor(),
              accentColor: this.accentColor(),
              inputColor: ThemeRuntime.inputColor(this.appDarkMode),
              menuColor: ThemeRuntime.dropdownPanelColor(this.appDarkMode),
              onChange: (values: number[]): void => this.applyTypographyValues(values)
            })
          }
          .width('calc(100% - 32vp)')
          .margin({ left: AppSpacing.XL, right: AppSpacing.XL })
          .border({ width: { bottom: 0.5 }, color: this.dividerColor() })
        }, (key: number) => `typography_stepper_${key}`)
        this.selectItem('段首缩进', '正文每段首行的缩进字符数', this.indentOptions(),
          ReaderParagraphIndent.normalize(this.draft.paragraphIndent), (index: number) => {
            this.draft.paragraphIndent = ReaderParagraphIndent.normalize(index);
            this.onDraftChanged();
          }, 'theme_typography_indent_select')
        this.selectItem('正文对齐方式', '正文段落的水平对齐', this.alignOptions(), this.alignIndex(),
          (index: number) => {
            this.draft.textAlign = this.alignValues()[Math.max(0, Math.min(index, 2))];
            this.onDraftChanged();
          }, 'theme_typography_align_select')
        SettingSwitchRow({
          title: '正文扩展至状态栏',
          description: '隐藏状态栏，正文延伸到屏幕顶部',
          isOn: this.draft.extendToStatusBar,
          showDivider: false,
          onChange: (value: boolean) => {
            this.draft.extendToStatusBar = value;
            this.onDraftChanged();
          }
        })
      }
      .width('calc(100% - 24vp)')
      .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
      .borderRadius(ThemeRuntime.cardRadius())
      .clip(true)
      .backgroundColor(this.cardColor())

      this.sectionTitle('页眉页脚')
      Column() {
        ReaderHeaderFooterEditor({
          dark: this.appDarkMode,
          textColor: this.primaryTextColor(),
          subTextColor: this.subTextColor(),
          accentColor: this.accentColor(),
          switchColor: ThemeRuntime.buttonColor(this.appDarkMode),
          menuColor: ThemeRuntime.dropdownPanelColor(this.appDarkMode),
          cardStyle: true,
          dividerColor: this.dividerColor(),
          readerHeaderEnabled: $headerEnabled,
          readerFooterEnabled: $footerEnabled,
          readerInfoBarConfig: $infoBarConfig,
          onChanged: (_headerEnabled: boolean, _footerEnabled: boolean, _infoBarConfig: string): void => {
            this.onDraftChanged();
          }
        })
      }
      .width('calc(100% - 24vp)')
      .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
      .borderRadius(ThemeRuntime.cardRadius())
      .clip(true)
      .backgroundColor(this.cardColor())

      this.sectionTitle('阅读字体')
      Column() {
        SettingNavRow({
          title: '正文与标题字体',
          description: `正文 ${this.draft.fontSize} · 标题 ${this.draft.titleFontSize} · 正则强调与气泡`,
          value: this.fontModeLabel(this.draft.bodyFontMode, this.draft.bodyFontFamily),
          showDivider: false,
          onTap: () => this.openFontSettings()
        })
      }
      .width('calc(100% - 24vp)')
      .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
      .borderRadius(ThemeRuntime.cardRadius())
      .clip(true)
      .backgroundColor(this.cardColor())

      this.sectionTitle('快捷操作')
      Column() {
        if (!this.activeScheme) {
          SettingNavRow({
            title: '套用当前阅读排版',
            description: '把正在使用的排版和字体复制到这套主题',
            onTap: () => this.copyCurrentTypography()
          })
        }
        SettingNavRow({
          title: '恢复默认排版',
          description: '字号、间距、边距与页眉页脚恢复默认，字体和强调规则保留',
          showDivider: false,
          onTap: () => this.resetLayout()
        })
      }
      .width('calc(100% - 24vp)')
      .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
      .borderRadius(ThemeRuntime.cardRadius())
      .clip(true)
      .backgroundColor(this.cardColor())

      Text('排版保存后与这套主题绑定：之后切换到它时，字号、间距、边距、页眉页脚和阅读字体会一起生效；' +
        '在阅读页里继续调整，也会记在这套主题上。全局字体与内容替换规则仍是全应用共用的设置。')
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor())
        .lineHeight(18)
        .width('100%')
        .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.LG })
    }
  }

  @Builder
  sectionTitle(title: string) {
    Text(title)
      .fontSize(AppFontSize.BODY)
      .fontColor(this.subTextColor())
      .width('100%')
      .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.XXL, bottom: AppSpacing.MD })
  }

  @Builder
  selectItem(title: string, desc: string, options: SelectOption[], selected: number,
    onSelect: (index: number) => void, controlId: string) {
    SettingRow({ title: title, description: desc }) {
      Select(options)
        .id(controlId)
        .selected(selected)
        .value(selected >= 0 && selected < options.length ? options[selected].value : '')
        .font({ size: AppFontSize.BODY })
        .fontColor(this.subTextColor())
        .backgroundColor(Color.Transparent)
        .arrowPosition(ArrowPosition.END)
        .padding({ left: 0, right: 0 })
        .borderRadius(16)
        .border({ width: 0 })
        .optionBgColor(Color.Transparent)
        .divider(null)
        .optionFontColor(this.primaryTextColor())
        .selectedOptionFontColor(this.accentColor())
        .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.appDarkMode))
        .menuBackgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode))
        .menuBackgroundBlurStyle(BlurStyle.NONE)
        .attributeModifier(ImmersiveMaterialRuntime.selectMenuModifier())
        .onSelect((index: number) => onSelect(index))
    }
  }

  // ---------- 数据 ----------

  async loadDraft(): Promise<void> {
    try {
      const params = router.getParams() as Record<string, Object> | undefined;
      this.schemeId = params && typeof params['schemeId'] === 'string' ? (params['schemeId'] as string).trim() : '';
      const themeSettings = await AppThemeSettingsStore.load(getContext(this));
      const schemes = await CustomThemeSchemeStore.load(getContext(this), themeSettings);
      const scheme: CustomThemeScheme | null = CustomThemeSchemeStore.find(schemes, this.schemeId);
      if (!scheme) {
        HdsFeedback.showToast('这套自定义主题已不存在');
        this.leave();
        return;
      }
      this.schemeName = scheme.name;
      this.themePack = AppThemeSettingsStore.customTheme(scheme.settings, this.appDarkMode);
      this.profileId = ReaderSettingsStore.profileIdFor(ThemeIds.CUSTOM, scheme.id);
      this.activeScheme = this.profileId === ReaderSettingsStore.activeProfileId();
      this.typographyBound = await ReaderSettingsStore.isTypographyBound(getContext(this), this.profileId);
      const profile = await ReaderSettingsStore.loadProfile(getContext(this), this.profileId);
      this.applyDraft(ThemeTypographySettingsPage.copySettings(profile));
      this.loaded = true;
      this.refreshPreview();
    } catch (e) {
      console.warn('读取主题排版失败:', e);
      HdsFeedback.showToast('读取主题排版失败，请稍后重试');
    }
  }

  applyDraft(settings: ReaderSettings): void {
    this.draft = settings;
    this.headerEnabled = settings.readerHeaderEnabled;
    this.footerEnabled = settings.readerFooterEnabled;
    this.infoBarConfig = settings.readerInfoBarConfig;
    this.stepperKey++;
  }

  /** 把页眉页脚的三项状态合回草稿，得到完整的待保存设置。 */
  draftSnapshot(): ReaderSettings {
    const settings = ThemeTypographySettingsPage.copySettings(this.draft);
    settings.readerHeaderEnabled = this.headerEnabled;
    settings.readerFooterEnabled = this.footerEnabled;
    settings.readerInfoBarConfig = this.infoBarConfig;
    return settings;
  }

  static copySettings(source: ReaderSettings): ReaderSettings {
    return JSON.parse(JSON.stringify(source)) as ReaderSettings;
  }

  onDraftChanged(): void {
    this.dirty = true;
    this.refreshPreview();
  }

  typographyValues(): number[] {
    const values: number[] = new Array<number>(ReaderTypographyField.COUNT).fill(0);
    values[ReaderTypographyField.FONT_SIZE] = this.draft.fontSize;
    values[ReaderTypographyField.FONT_WEIGHT] = this.draft.fontWeight;
    values[ReaderTypographyField.LETTER_SPACING] = this.draft.letterSpacing;
    values[ReaderTypographyField.LINE_HEIGHT] = this.draft.lineHeight;
    values[ReaderTypographyField.PARAGRAPH_SPACING] = this.draft.paragraphSpacing;
    values[ReaderTypographyField.MARGIN_LEFT] = this.draft.marginLeft;
    values[ReaderTypographyField.MARGIN_RIGHT] = this.draft.marginRight;
    values[ReaderTypographyField.MARGIN_TOP] = this.draft.marginTop;
    values[ReaderTypographyField.MARGIN_BOTTOM] = this.draft.marginBottom;
    values[ReaderTypographyField.COMMENT_BUBBLE_SIZE] = this.draft.commentBubbleSize;
    return values;
  }

  applyTypographyValues(values: number[]): void {
    if (values.length < ReaderTypographyField.COUNT) return;
    this.draft.fontSize = values[ReaderTypographyField.FONT_SIZE];
    this.draft.fontWeight = values[ReaderTypographyField.FONT_WEIGHT];
    this.draft.letterSpacing = values[ReaderTypographyField.LETTER_SPACING];
    this.draft.lineHeight = values[ReaderTypographyField.LINE_HEIGHT];
    this.draft.paragraphSpacing = values[ReaderTypographyField.PARAGRAPH_SPACING];
    this.draft.marginLeft = values[ReaderTypographyField.MARGIN_LEFT];
    this.draft.marginRight = values[ReaderTypographyField.MARGIN_RIGHT];
    this.draft.marginTop = values[ReaderTypographyField.MARGIN_TOP];
    this.draft.marginBottom = values[ReaderTypographyField.MARGIN_BOTTOM];
    this.draft.commentBubbleSize = values[ReaderTypographyField.COMMENT_BUBBLE_SIZE];
    this.onDraftChanged();
  }

  openFontSettings(): void {
    if (!this.loaded) return;
    ThemeTypographyDraft.begin(this.draftSnapshot());
    this.fontDraftRevision = ThemeTypographyDraft.revision();
    const params: Record<string, Object> = {};
    params[ThemeTypographyDraft.DRAFT_PARAM] = true;
    router.pushUrl({ url: 'pages/ReaderFontSettings', params: params });
  }

  /** 从阅读字体页回来时，取回它在草稿里改过的字体与强调规则。 */
  pullFontDraft(): void {
    const fontDraft = ThemeTypographyDraft.current();
    if (!fontDraft || this.fontDraftRevision < 0) return;
    if (ThemeTypographyDraft.revision() !== this.fontDraftRevision) {
      const next = this.draftSnapshot();
      next.fontSize = fontDraft.fontSize;
      next.bodyFontMode = fontDraft.bodyFontMode;
      next.bodyFontFamily = fontDraft.bodyFontFamily;
      next.titleFontMode = fontDraft.titleFontMode;
      next.titleFontFamily = fontDraft.titleFontFamily;
      next.titleFontSize = fontDraft.titleFontSize;
      next.regexFontEnabled = fontDraft.regexFontEnabled;
      next.regexFontPattern = fontDraft.regexFontPattern;
      next.regexFontMode = fontDraft.regexFontMode;
      next.regexFontFamily = fontDraft.regexFontFamily;
      next.regexFontSize = fontDraft.regexFontSize;
      next.regexShadowColor = fontDraft.regexShadowColor;
      next.regexFontRulesRaw = fontDraft.regexFontRulesRaw;
      this.applyDraft(next);
      this.onDraftChanged();
    }
    ThemeTypographyDraft.end();
    this.fontDraftRevision = -1;
  }

  async copyCurrentTypography(): Promise<void> {
    try {
      const current = await ReaderSettingsStore.load(getContext(this));
      const next = this.draftSnapshot();
      ReaderSettingsStore.copyTypography(current, next);
      this.applyDraft(next);
      this.onDraftChanged();
      HdsFeedback.showToast('已套用当前阅读排版，保存后生效');
    } catch (e) {
      console.warn('读取当前阅读排版失败:', e);
      HdsFeedback.showToast('读取当前阅读排版失败');
    }
  }

  resetLayout(): void {
    const defaults = new ReaderSettings();
    const next = this.draftSnapshot();
    next.fontSize = defaults.fontSize;
    next.fontWeight = defaults.fontWeight;
    next.letterSpacing = defaults.letterSpacing;
    next.textAlign = defaults.textAlign;
    next.lineHeight = defaults.lineHeight;
    next.paragraphSpacing = defaults.paragraphSpacing;
    next.paragraphIndent = defaults.paragraphIndent;
    next.marginLeft = defaults.marginLeft;
    next.marginRight = defaults.marginRight;
    next.marginTop = defaults.marginTop;
    next.marginBottom = defaults.marginBottom;
    next.commentBubbleSize = defaults.commentBubbleSize;
    next.extendToStatusBar = defaults.extendToStatusBar;
    next.titleFontSize = defaults.titleFontSize;
    next.readerHeaderEnabled = defaults.readerHeaderEnabled;
    next.readerFooterEnabled = defaults.readerFooterEnabled;
    next.readerInfoBarConfig = new ReaderInfoBarConfig().serialize();
    this.applyDraft(next);
    this.onDraftChanged();
    HdsFeedback.showToast('已恢复默认排版，保存后生效');
  }

  async save(): Promise<void> {
    if (!this.loaded || this.saving) return;
    this.saving = true;
    try {
      await ReaderSettingsStore.saveTypographyToProfile(getContext(this), this.profileId, this.draftSnapshot());
      this.dirty = false;
      this.typographyBound = true;
      HdsFeedback.showToast(this.activeScheme ? '主题排版已保存并生效' :
        `已保存，切换到「${this.schemeName}」时排版一起生效`);
      this.leave();
    } catch (e) {
      console.error('保存主题排版失败:', e);
      HdsFeedback.showToast('保存失败，请稍后重试');
    } finally {
      this.saving = false;
    }
  }

  async requestClose(): Promise<void> {
    if (this.leaving) return;
    if (this.dirty && !await this.confirmDiscard()) return;
    this.leave();
  }

  async confirmDiscard(): Promise<boolean> {
    try {
      const result = await promptAction.showDialog({
        title: '放弃本次修改？',
        message: '主题排版还没有保存，返回后修改不会生效。',
        buttons: [{ text: '继续编辑', color: this.subTextColor() },
          { text: '放弃', color: ThemeRuntime.dangerColor(this.appDarkMode) }]
      });
      return result.index === 1;
    } catch (e) {
      console.warn('显示放弃修改确认失败:', e);
      return true;
    }
  }

  leave(): void {
    if (this.leaving) return;
    this.leaving = true;
    ThemeTypographyDraft.end();
    router.back();
  }

  statusText(): string {
    if (!this.loaded) return '正在读取排版…';
    if (this.dirty) return this.activeScheme ? '有未保存的修改 · 保存后立即生效' : '有未保存的修改 · 保存后与主题绑定';
    if (this.activeScheme) return '正在使用 · 这里的排版就是当前阅读排版';
    return this.typographyBound ? '已绑定排版 · 切换到这套主题时一起生效' : '尚未单独设置 · 保存后与主题绑定';
  }

  openFullPreview(): void {
    if (!this.loaded) return;
    this.timeText = ReaderInfoBarClock.timeText();
    this.batteryPercent = ReaderInfoBarClock.batteryPercent();
    this.fullPreview = true;
    syncSystemBars(getContext(this), this.previewTheme().contentTone === 'dark', this.previewTheme().backgroundColor);
    if (!this.fullPreviewHintShown) {
      this.fullPreviewHintShown = true;
      HdsFeedback.showToast('轻触任意位置返回');
    }
  }

  closeFullPreview(): void {
    this.fullPreview = false;
    this.syncBars();
  }

  setPreviewDark(dark: boolean): void {
    if (this.previewDark === dark) return;
    this.previewDark = dark;
    this.refreshPreview();
  }

  // ---------- 预览排布 ----------

  refreshPreview(): void {
    if (!this.loaded) return;
    this.previewRules = this.decodeRules();
    this.previewRevision++;
    this.windowFit = this.computeFit(false);
    this.fullFit = this.computeFit(true);
  }

  fitFor(full: boolean): TypographyPreviewFit {
    return full ? this.fullFit : this.windowFit;
  }

  previewWindowWidth(): number {
    return Math.max(0, this.pageWidth() - AppSpacing.LG * 2);
  }

  /** 整屏预览的宽度就是阅读页宽度；预览窗是收在卡片里的同一页，左右各窄一点。 */
  pageWidth(): number {
    return this.viewportWidth > 0 ? this.viewportWidth : 360;
  }

  windowHeight(): number {
    const height = this.viewportHeight > 0 ? this.viewportHeight : 760;
    return Math.round(Math.max(240, Math.min(400, height * 0.42)));
  }

  pageHeight(full: boolean): number {
    return full ? (this.viewportHeight > 0 ? this.viewportHeight : 760) : this.windowHeight();
  }

  contentWidth(full: boolean): number {
    const width = full ? this.pageWidth() : this.previewWindowWidth();
    return Math.max(40, width - this.draft.marginLeft - this.draft.marginRight);
  }

  statusInset(full: boolean): number {
    return full && !this.draft.extendToStatusBar ? this.statusBarHeight : 0;
  }

  infoConfig(): ReaderInfoBarConfig {
    return ReaderInfoBarConfig.parse(this.infoBarConfig) ?? new ReaderInfoBarConfig();
  }

  headerVisible(): boolean {
    return this.headerEnabled && this.infoConfig().headerVisible();
  }

  headerTopGap(): number {
    return (this.draft.extendToStatusBar ? 8 : 0) + this.infoConfig().headerOffset;
  }

  bodyTop(full: boolean): number {
    let top = this.statusInset(full) + Math.max(0, this.draft.marginTop);
    if (this.headerVisible()) {
      top += this.infoConfig().headerLineHeight() + this.infoConfig().headerExtraHeight() +
        Math.min(4, Math.max(0, this.draft.marginTop)) + this.headerTopGap();
    }
    return top;
  }

  footerBottomInset(full: boolean): number {
    return (full ? this.navBarHeight : 0) + 6 + this.infoConfig().footerOffset;
  }

  footerBlockHeight(): number {
    return this.infoConfig().footerFontSize * 1.35 + this.infoConfig().footerExtraHeight() + 3;
  }

  bodyLimit(full: boolean): number {
    const guard = this.footerEnabled ? this.footerBlockHeight() + this.footerBottomInset(full) + 4 :
      (full ? this.navBarHeight : 0);
    return this.pageHeight(full) - Math.max(0, this.draft.marginBottom) - guard;
  }

  infoSidePadding(header: boolean, left: boolean): number {
    return this.infoConfig().sidePadding(header, left, this.draft.marginLeft, this.draft.marginRight,
      this.fullPreview ? this.pageWidth() : this.previewWindowWidth());
  }

  /** 与阅读页相同：行高 = 字号换算后的高度 + 行距。 */
  bodyLineBox(): number {
    return this.fontLineBox(this.draft.fontSize);
  }

  titleLineBox(): number {
    return this.fontLineBox(this.draft.titleFontSize);
  }

  fontLineBox(fontSize: number): number {
    let size = fontSize;
    try {
      size = this.getUIContext().px2vp(this.getUIContext().fp2px(fontSize));
    } catch (_) {
      size = fontSize;
    }
    return Math.max(1, size + Math.max(0, this.draft.lineHeight));
  }

  paragraphText(index: number): string {
    return `${'　'.repeat(ReaderParagraphIndent.normalize(this.draft.paragraphIndent))}${PREVIEW_PARAGRAPHS[index]}`;
  }

  measureLines(text: string, fontSize: number, fontWeight: number, fontFamily: string, lineBox: number,
    width: number): number {
    try {
      const size = this.getUIContext().getMeasureUtils().measureTextSize({
        textContent: text,
        constraintWidth: width,
        fontSize: fontSize,
        fontWeight: fontWeight,
        fontFamily: fontFamily,
        letterSpacing: this.draft.letterSpacing,
        lineHeight: `${lineBox}vp`
      });
      const height = this.getUIContext().px2vp(Number(size.height));
      return Math.max(1, Math.round(height / lineBox));
    } catch (e) {
      const perLine = Math.max(1, Math.floor(width / Math.max(1, fontSize + this.draft.letterSpacing)));
      return Math.max(1, Math.ceil(text.length / perLine));
    }
  }

  /** 按阅读页的规则逐段排下去，最后一段截在整行处，不出现半行。 */
  computeFit(full: boolean): TypographyPreviewFit {
    const fit = new TypographyPreviewFit();
    const available = this.bodyLimit(full) - this.bodyTop(full);
    const width = this.contentWidth(full);
    if (available <= 0) return fit;
    const titleBox = this.titleLineBox();
    const titleLines = this.measureLines(PREVIEW_CHAPTER_TITLE, this.draft.titleFontSize, 600,
      this.titleFontFamily(), titleBox, width);
    fit.titleLines = Math.min(titleLines, Math.floor(available / titleBox));
    if (fit.titleLines < titleLines) return fit;
    let y = titleLines * titleBox + Math.max(0, this.draft.paragraphSpacing);
    const lineBox = this.bodyLineBox();
    const family = this.bodyFontFamily();
    for (let index = 0; index < PREVIEW_PARAGRAPHS.length; index++) {
      const lines = this.measureLines(this.paragraphText(index), this.draft.fontSize, this.draft.fontWeight,
        family, lineBox, width);
      if (y + lines * lineBox <= available + 0.5) {
        fit.paragraphCount = index + 1;
        y += lines * lineBox + Math.max(0, this.draft.paragraphSpacing);
        continue;
      }
      const remaining = Math.floor((available - y + 0.5) / lineBox);
      if (remaining > 0) {
        fit.paragraphCount = index + 1;
        fit.lastLines = remaining;
      }
      break;
    }
    return fit;
  }

  visibleParagraphIndexes(full: boolean): number[] {
    const result: number[] = [];
    for (let index = 0; index < this.fitFor(full).paragraphCount; index++) {
      result.push(index);
    }
    return result;
  }

  paragraphMaxLines(full: boolean, index: number): number {
    const fit = this.fitFor(full);
    return index === fit.paragraphCount - 1 ? fit.lastLines : 0;
  }

  textAlignValue(): TextAlign {
    if (this.draft.textAlign === 'start') return TextAlign.Start;
    if (this.draft.textAlign === 'end') return TextAlign.End;
    return TextAlign.JUSTIFY;
  }

  // ---------- 强调规则 ----------

  decodeRules(): ReaderRegexFontRule[] {
    if (!this.draft.regexFontEnabled) return [];
    const legacy = new ReaderRegexLegacySettings();
    legacy.pattern = this.draft.regexFontPattern;
    legacy.fontMode = this.draft.regexFontMode;
    legacy.fontFamily = this.draft.regexFontFamily;
    legacy.fontSize = this.draft.regexFontSize;
    legacy.shadowColor = this.draft.regexShadowColor;
    return ReaderRegexFontCodec.decode(this.draft.regexFontRulesRaw, legacy)
      .filter((rule: ReaderRegexFontRule): boolean => !!(rule.pattern || '').trim());
  }

  ruleAt(index: number): ReaderRegexFontRule {
    return index >= 0 && index < this.previewRules.length ? this.previewRules[index] : new ReaderRegexFontRule();
  }

  /** 每个字符归第一条命中它的规则，与阅读页的规则顺序一致。 */
  paragraphSlices(index: number): TypographyPreviewSlice[] {
    const text = this.paragraphText(index);
    const owners: number[] = new Array<number>(text.length).fill(-1);
    for (let ruleIndex = 0; ruleIndex < this.previewRules.length; ruleIndex++) {
      try {
        const regex = new RegExp(this.previewRules[ruleIndex].pattern, 'g');
        let match = regex.exec(text);
        let guard = 0;
        while (match && guard < 200) {
          guard++;
          const start = match.index;
          const end = Math.min(text.length, start + (match[0] || '').length);
          if (end <= start) {
            regex.lastIndex = start + 1;
          } else {
            for (let position = start; position < end; position++) {
              if (owners[position] < 0) owners[position] = ruleIndex;
            }
          }
          if (regex.lastIndex >= text.length) break;
          match = regex.exec(text);
        }
      } catch (_) {
        // 无效的表达式在阅读页同样不生效。
      }
    }
    const slices: TypographyPreviewSlice[] = [];
    let start = 0;
    for (let position = 1; position <= text.length; position++) {
      if (position === text.length || owners[position] !== owners[start]) {
        const slice = new TypographyPreviewSlice();
        slice.text = text.substring(start, position);
        slice.rule = owners[start];
        slice.key = `${index}_${start}_${position}_${slice.rule}_${this.previewRevision}`;
        slices.push(slice);
        start = position;
      }
    }
    return slices;
  }

  emphasisContext(): ReaderRegexEmphasisContext {
    const variant = this.previewVariant();
    const context = new ReaderRegexEmphasisContext();
    context.inheritedMode = variant.regexEmphasis.emphasisMode;
    context.inheritedBubbleStyleId = variant.regexEmphasis.bubbleStyle;
    context.inheritedColor = variant.regexEmphasis.emphasisColor;
    context.inheritedTextColor = variant.regexEmphasis.emphasisTextColor;
    context.accentColor = variant.colors.accentColor;
    context.surfaceColor = this.previewTheme().backgroundColor;
    context.normalTextColor = this.previewTheme().textColor;
    context.darkMode = this.previewDark;
    return context;
  }

  ruleEmphasis(index: number): ReaderResolvedRegexEmphasis {
    return ReaderRegexBubbleStyleResolver.resolve(this.ruleAt(index), this.emphasisContext());
  }

  ruleBackground(index: number): TextBackgroundStyle {
    const style = this.ruleEmphasis(index);
    if (!style.backgroundEnabled) return {};
    return {
      color: style.backgroundColor,
      radius: {
        topLeft: style.radiusTopLeft,
        topRight: style.radiusTopRight,
        bottomLeft: style.radiusBottomLeft,
        bottomRight: style.radiusBottomRight
      }
    };
  }

  ruleShadow(index: number): ShadowOptions | ShadowOptions[] {
    const style = this.ruleEmphasis(index);
    if (style.textShadows.length > 0) return style.textShadows;
    return {
      radius: style.textShadowRadius,
      color: style.textShadowColor,
      offsetX: style.textShadowOffsetX,
      offsetY: style.textShadowOffsetY
    };
  }

  ruleDecoration(index: number): DecorationStyleInterface {
    const style = this.ruleEmphasis(index);
    if (!style.decorationEnabled) return { type: TextDecorationType.None };
    let decorationStyle = TextDecorationStyle.SOLID;
    if (style.decorationStyleId === 'double') decorationStyle = TextDecorationStyle.DOUBLE;
    else if (style.decorationStyleId === 'dotted') decorationStyle = TextDecorationStyle.DOTTED;
    else if (style.decorationStyleId === 'dashed') decorationStyle = TextDecorationStyle.DASHED;
    else if (style.decorationStyleId === 'wavy') decorationStyle = TextDecorationStyle.WAVY;
    return { type: TextDecorationType.Underline, color: style.decorationColor, style: decorationStyle };
  }

  // ---------- 页眉页脚示例内容 ----------

  infoContext(): ReaderInfoBarContext {
    const context = new ReaderInfoBarContext();
    context.bookName = PREVIEW_BOOK_NAME;
    context.author = PREVIEW_AUTHOR;
    context.chapterTitle = PREVIEW_CHAPTER_TITLE;
    context.chapterIndex = 0;
    context.chapterCount = 36;
    context.pageIndex = 1;
    context.pageCount = 9;
    context.timeText = this.timeText;
    context.batteryPercent = this.batteryPercent >= 0 ? this.batteryPercent : 80;
    return context;
  }

  infoSlotText(item: string): string {
    return ReaderInfoBarText.leading(item, this.infoContext());
  }

  infoSlotBattery(item: string): number {
    return ReaderInfoBarText.battery(item, this.infoContext());
  }

  // ---------- 字体 ----------

  customFonts(): ThemeTypographyFontItem[] {
    const raw = (this.readerCustomFontsRaw || '').trim();
    if (!raw) return [];
    try {
      const parsed = JSON.parse(raw) as ThemeTypographyFontData | ThemeTypographyFontItem[];
      const source = Array.isArray(parsed) ? parsed as ThemeTypographyFontItem[] :
        ((parsed as ThemeTypographyFontData).fonts || []);
      return source.filter((item: ThemeTypographyFontItem): boolean =>
        !!item && !!item.familyName && ReaderFontHelper.fontFileExists(item.filePath));
    } catch (_) {
      return [];
    }
  }

  globalFontFamily(): string {
    return this.readerFontFamily || ReaderFontBootstrap.defaultFontFamily(this.readerFontMode, this.systemFontFamily());
  }

  systemFontFamily(): string {
    return this.readerSystemFontFamily || ReaderSystemFontHelper.currentFromStorage(this.getUIContext()) || '';
  }

  styledFontFamily(mode: string, family: string): string {
    if (mode === 'system') return this.systemFontFamily();
    if (mode === 'custom' && family) {
      for (const font of this.customFonts()) {
        const stable = font.filePath ? ReaderFontHelper.normalizeFontFamily(font.filePath) : font.familyName;
        if (font.familyName === family || stable === family) {
          const item = new ReaderFontItem();
          item.familyName = font.familyName || stable;
          item.filePath = font.filePath;
          item.sourceName = ReaderFontHelper.resolveDisplayName(font.sourceName, font.filePath);
          const result = ReaderFontHelper.registerFont(this.getUIContext(), item);
          return result.registered ? result.familyName : (stable || family);
        }
      }
      return family;
    }
    return this.globalFontFamily();
  }

  bodyFontFamily(): string {
    return this.styledFontFamily(this.draft.bodyFontMode, this.draft.bodyFontFamily);
  }

  titleFontFamily(): string {
    if (this.draft.titleFontMode === 'global' && !this.draft.titleFontFamily) return this.globalFontFamily();
    return this.styledFontFamily(this.draft.titleFontMode, this.draft.titleFontFamily);
  }

  fontModeLabel(mode: string, family: string): string {
    if (mode === 'system') return '系统字体';
    if (mode === 'custom' && family) {
      for (const font of this.customFonts()) {
        const stable = font.filePath ? ReaderFontHelper.normalizeFontFamily(font.filePath) : font.familyName;
        if (font.familyName === family || stable === family) {
          return ReaderFontHelper.resolveDisplayName(font.sourceName || font.familyName, font.filePath);
        }
      }
      return '自定义字体';
    }
    return '跟随全局字体';
  }

  // ---------- 配色 ----------

  previewVariant(): ThemeVariant {
    const pack = this.themePack;
    if (!pack) return this.previewDark ? new ThemePack().dark : new ThemePack().light;
    return this.previewDark ? pack.dark : pack.light;
  }

  /** 档案里的阅读背景跟随主题时用这套主题的阅读配色，否则用档案选的预设背景。 */
  previewTheme(): ReaderThemeItem {
    const index = this.previewDark ? this.draft.darkThemeIndex : this.draft.lightThemeIndex;
    if (ReaderThemeHelper.normalizeIndex(index) !== ReaderThemeHelper.APP_THEME_INDEX) {
      return ReaderThemeHelper.themeAt(this.previewDark, index,
        this.previewDark ? this.draft.darkCustomThemeBackgroundColor : this.draft.lightCustomThemeBackgroundColor,
        this.previewDark ? this.draft.darkCustomThemeTextColor : this.draft.lightCustomThemeTextColor);
    }
    const reader = this.previewVariant().reader;
    const item = new ReaderThemeItem();
    item.name = '应用主题';
    item.backgroundColor = reader.backgroundColor;
    item.textColor = reader.textColor;
    item.subTextColor = reader.subTextColor;
    item.backgroundAssetId = reader.backgroundAssetId;
    item.backgroundImageFit = reader.backgroundImageFit;
    item.contentTone = reader.contentTone || (this.previewDark ? 'dark' : 'light');
    return item;
  }

  previewTrackColor(): string {
    return this.previewTheme().contentTone === 'dark' ? '#33FFFFFF' : '#1F000000';
  }

  indentOptions(): SelectOption[] {
    return [{ value: '0字符' }, { value: '1字符' }, { value: '2字符' }, { value: '3字符' }, { value: '4字符' }];
  }

  alignOptions(): SelectOption[] {
    return [{ value: '两端对齐' }, { value: '左对齐' }, { value: '右对齐' }];
  }

  alignValues(): string[] {
    return ['justify', 'start', 'end'];
  }

  alignIndex(): number {
    return Math.max(0, this.alignValues().indexOf(this.draft.textAlign));
  }

  pageColor(): string {
    return ThemeRuntime.pageColor(this.appDarkMode);
  }

  cardColor(): string {
    return ThemeRuntime.cardColor(this.appDarkMode);
  }

  dividerColor(): string {
    return ThemeRuntime.hairlineColor(this.appDarkMode);
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
