import { promptAction, router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { AppIconManager } from '../utils/AppIconManager';
import { AppIconSettingsStore } from '../utils/AppIconSettingsStore';
import { AppThemeSettings, AppThemeSettingsStore } from '../utils/AppThemeSettingsStore';
import { ReaderSettings, ReaderSettingsStore } from '../utils/ReaderSettingsStore';
import { ReaderFontBootstrap } from '../utils/ReaderFontBootstrap';
import { ReaderThemeHelper } from '../utils/ReaderThemeHelper';
import { syncSystemBars } from '../utils/SystemBars';
import { RecentReadCardUpdater } from '../utils/RecentReadCardUpdater';
import { ThemeTrialManager } from '../utils/ThemeTrialManager';
import { CustomThemeScheme, CustomThemeSchemeStore } from '../utils/CustomThemeSchemeStore';
import { BuiltinThemeRegistry } from '../theme/BuiltinThemeRegistry';
import { ImmersiveBackButton } from '../components/ImmersiveBackButton';
import { CollapsingHeader } from '../utils/CollapsingHeader';
import { ThemeStartupCover } from '../components/ThemeStartupCover';
import { ReaderThemeBackground } from '../components/ReaderThemeBackground';
import { TtsPanelThemeBackground } from '../components/TtsPanelThemeBackground';
import { ThemeAssetRegistry } from '../theme/ThemeAssetRegistry';
import { ThemeIds, ThemePack, ThemeRegexEmphasisModes, ThemeVariant } from '../theme/ThemeModels';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { AccountCommerceConfig } from '../account/AccountCommerceConfig';
import { AccountApiError, ThemeCatalogItem, ThemeCatalogResponse,
  ThemeEntitlement } from '../account/AccountCommerceModels';
import { AccountCommerceApi } from '../account/AccountCommerceApi';
import { AccountSessionStore } from '../account/AccountSessionStore';
import { CustomThemeQuota } from '../account/CustomThemeQuota';
import { MembershipCommerceService } from '../account/MembershipCommerceService';
import { HuaweiAccountService } from '../account/HuaweiAccountService';
import {
  ReaderRegexBubbleStyleResolver,
  ReaderRegexEmphasisContext,
  ReaderResolvedRegexEmphasis
} from '../model/reader/ReaderRegexFontRule';
import {
  ReaderCommentBubbleImage,
  ReaderCommentBubbleStyles,
  ReaderCommentBubblePainter
} from '../core/reader/ReaderCommentBubble';
import { StartupCoverTextStore } from '../utils/StartupCoverTextStore';
import { HdsFeedback } from '../utils/HdsFeedback';
import { AdaptiveSwitch } from '../components/AdaptiveSwitch';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { PageScaffold } from '../components/common/PageScaffold';
import { themeAuthorLine, ThemeExportDialog, ThemeImportDialog } from '../components/theme/ThemeShareDialogs';
import {
  ThemeExportOptions,
  ThemeExportPlan,
  ThemeExportResult,
  ThemeImportPreview,
  ThemePackageService
} from '../theme/share/ThemePackageService';

const STORE_COVER_MIN_HEIGHT = 170;
const STORE_COVER_MAX_HEIGHT = 340;
// Detail pager: the focused pane leaves its neighbours peeking in on both sides.
const STORE_PAGER_PANE_WIDTH_RATIO = 0.78;
const STORE_PAGER_PANE_MAX_WIDTH = 420;
const STORE_PAGE_FIXED_HEIGHT = 256;
const STORE_READER_PANE_LINE_HEIGHT = 17;
const STARTUP_COPY_STRIP_HEIGHT = 40;
const STORE_BOOK_COVER_RATIO = 46 / 64;

/**
 * One run of the reader preview's sample page; dialogue runs wear the theme's emphasis style and
 * comment runs are drawn as the theme's paragraph-comment pill.
 */
class ReaderPreviewSegment {
  text: string;
  emphasis: boolean;
  comment: boolean;

  constructor(text: string, emphasis: boolean = false, comment: boolean = false) {
    this.text = text;
    this.emphasis = emphasis;
    this.comment = comment;
  }
}

// Long enough to fill the tallest preview pane; the pane clips it at a whole line.
const READER_PREVIEW_SEGMENTS: ReaderPreviewSegment[] = [
  new ReaderPreviewSegment('\u3000\u3000雨停的时候，檐下还挂着水珠。她把灯芯拨亮了些，翻开那本旧书。'),
  new ReaderPreviewSegment('12', false, true),
  new ReaderPreviewSegment('\n\u3000\u3000纸页泛黄，墨迹却还清楚。窗外起了风，吹得帘子轻轻晃动，她没有抬头。\n\u3000\u3000'),
  new ReaderPreviewSegment('“长夜未尽，且慢慢读。”', true),
  new ReaderPreviewSegment('她轻声念道。\n\u3000\u3000远处传来更鼓，一声，又一声。灯花落了下来，书页翻过去，故事才刚刚开始。'),
  new ReaderPreviewSegment('8', false, true),
  new ReaderPreviewSegment('\n\u3000\u3000门外有人收了伞，在阶前跺了跺脚上的泥。\n\u3000\u3000'),
  new ReaderPreviewSegment('“这么晚了，还不歇息？”', true),
  new ReaderPreviewSegment('\n\u3000\u3000她合上书，指尖还压着方才读到的那一行，笑了笑：'),
  new ReaderPreviewSegment('“就差最后几页。”', true),
  new ReaderPreviewSegment('\n\u3000\u3000来人不再劝，只把一盏新茶搁在案角。茶烟细细地升起来，和灯影叠在一处，在墙上晃成一片淡淡的水纹。' +
    '\n\u3000\u3000夜更深了。巷口卖馄饨的担子早已收走，只剩一两声犬吠，隔着几重院墙传过来，又很快沉下去。\n\u3000\u3000'),
  new ReaderPreviewSegment('“你看这一句。”', true),
  new ReaderPreviewSegment('她忽然把书推过去，指给他看。那是一行极小的批注，墨色比正文浅些，像是很多年前，另一个同样不肯睡的人留下的。' +
    '\n\u3000\u3000他凑近看了许久，低声念出来：'),
  new ReaderPreviewSegment('“愿此夜长，愿此书不尽。”', true),
  new ReaderPreviewSegment('\n\u3000\u3000两人都没有再说话。灯芯爆了一声轻响，窗纸上映出第一线微白，天快要亮了。' +
    '\n\u3000\u3000她把书签夹回原处，将那盏已经凉透的茶端起来，慢慢喝完。新的一天，就从这一页之后开始。' +
    '\n\u3000\u3000很多年以后，她仍记得那个雨夜：一盏灯，一本书，一个不催她的人。' +
    '\n\u3000\u3000而那行小小的批注，她后来也照着写了一遍，留给下一个翻开这本书的人。')
];
const STORE_GRID_COVER_HEIGHT = 132;
const MY_THEME_THUMB_WIDTH = 108;
const MY_THEME_THUMB_COVER_HEIGHT = 76;

/** User choice from the "apply theme" prompt. */
class ThemeApplyChoice {
  applyLayout: boolean = false;
  applyCover: boolean = false;
  applyIcon: boolean = false;

  static preserve(): ThemeApplyChoice {
    return new ThemeApplyChoice();
  }
}

/** One theme the user can apply right away; customSchemeId is set for custom schemes. */
class ThemeSettingsRouteParams {
  themeId: string = '';
}

class ThemeListEntry {
  theme: ThemePack;
  customSchemeId: string;

  constructor(theme: ThemePack, customSchemeId: string = '') {
    this.theme = theme;
    this.customSchemeId = customSchemeId;
  }
}

@Entry
@Component
struct ThemeSettingsPage {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('appThemeId') appThemeId: string = AppThemeSettingsStore.DEFAULT_THEME_ID;
  @StorageLink('appIconId') appIconId: string = AppIconSettingsStore.DEFAULT_ICON_ID;
  @StorageLink('appThemeBookCoverEnabled') themeBookCoverEnabled: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageLink('appCustomBaseThemeId') customBaseThemeId: string = AppThemeSettingsStore.DEFAULT_THEME_ID;
  @StorageLink('appCustomLightAccentColor') customLightAccentColor: string = '#007DFF';
  @StorageLink('appCustomDarkAccentColor') customDarkAccentColor: string = '#4E9BFF';
  @StorageLink('appCustomLightButtonColor') customLightButtonColor: string = '#007DFF';
  @StorageLink('appCustomDarkButtonColor') customDarkButtonColor: string = '#3F8CFF';
  @StorageLink('appCustomLightReaderBackgroundColor') customLightReaderBackgroundColor: string = '#F7F1E3';
  @StorageLink('appCustomLightReaderTextColor') customLightReaderTextColor: string = '#2F261D';
  @StorageLink('appCustomLightReaderSubTextColor') customLightReaderSubTextColor: string = '#7A6F63';
  @StorageLink('appCustomLightReaderBackgroundAssetId') customLightReaderBackgroundAssetId: string = '';
  @StorageLink('appCustomLightReaderBackgroundImageFit') customLightReaderBackgroundImageFit: string = 'cover';
  @StorageLink('appCustomLightReaderContentTone') customLightReaderContentTone: string = 'light';
  @StorageLink('appCustomDarkReaderBackgroundColor') customDarkReaderBackgroundColor: string = '#1F2329';
  @StorageLink('appCustomDarkReaderTextColor') customDarkReaderTextColor: string = '#D8D8D8';
  @StorageLink('appCustomDarkReaderSubTextColor') customDarkReaderSubTextColor: string = '#9AA0A6';
  @StorageLink('appCustomDarkReaderBackgroundAssetId') customDarkReaderBackgroundAssetId: string = '';
  @StorageLink('appCustomDarkReaderBackgroundImageFit') customDarkReaderBackgroundImageFit: string = 'cover';
  @StorageLink('appCustomDarkReaderContentTone') customDarkReaderContentTone: string = 'dark';
  @StorageLink('readerLightThemeIndex') readerLightThemeIndex: number = 0;
  @StorageLink('readerDarkThemeIndex') readerDarkThemeIndex: number = 0;
  @StorageLink('accountLoggedIn') accountLoggedIn: boolean = false;
  @StorageLink('accountPoints') accountPoints: number = 0;
  @StorageLink('accountEntitlementsRevision') @Watch('refreshCustomSchemeLimit')
  accountEntitlementsRevision: number = 0;
  @StorageLink('themeTrialThemeId') trialThemeId: string = '';
  @StorageLink('themeTrialEndsAt') trialEndsAt: number = 0;
  @StorageLink('activeCustomThemeSchemeId') activeCustomSchemeId: string = '';
  @StorageLink('activeCustomThemeSchemeRevision') activeCustomSchemeRevision: number = 0;
  @StorageLink('customThemeSchemesRevision') @Watch('onCustomThemeSchemesRevisionChanged')
  customThemeSchemesRevision: number = 0;
  @StorageLink('startupCoverTextsRevision') startupCoverTextsRevision: number = 0;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @State headerCollapse: number = 0;
  private themeListScroller: Scroller = new Scroller();
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @State applyingThemeId: string = '';
  @State focusedThemeId: string = '';
  @State customSchemes: CustomThemeScheme[] = [];
  // 在主题排版页绑定过排版的方案：方案 ID → 排版摘要。卡片上显示它而不是预设排版。
  @State boundLayoutRevision: number = 0;
  private boundLayoutSummaries: Map<string, string> = new Map<string, string>();
  @State customSchemeLimit: number = CustomThemeQuota.current();
  @State addingCustomScheme: boolean = false;
  @State showThemeExportDialog: boolean = false;
  @State exportPlan: ThemeExportPlan = new ThemeExportPlan();
  @State showThemeImportDialog: boolean = false;
  @State importPreview: ThemeImportPreview = new ThemeImportPreview();
  @State preparingThemeImport: boolean = false;
  // 外部“用本应用打开”.qytheme 文件时由 EntryAbility 写入。
  @StorageLink('pendingThemeImportNonce') @Watch('onPendingThemeImport') pendingThemeImportNonce: number = 0;
  @State showCustomThemeActionMenu: boolean = false;
  @State showRenameCustomThemeDialog: boolean = false;
  @State showDeleteCustomThemeDialog: boolean = false;
  @State actionCustomSchemeId: string = '';
  @State renameCustomThemeName: string = '';
  @State contextMenuX: number = 24;
  @State contextMenuY: number = 120;
  @State contextViewportWidth: number = 360;
  @State contextViewportHeight: number = 720;
  @State showStartupTextDialog: boolean = false;
  @State startupTextThemeId: string = '';
  @State startupTextTitle: string = '';
  @State startupTextSubtitle: string = '';
  @State showThemeApplyDialog: boolean = false;
  @State applyDialogThemeName: string = '';
  // 排版开关打开、关闭时各自会得到的排版，提示随开关切换，数值取自实际要生效的设置。
  @State applyDialogLayoutOnHint: string = '';
  @State applyDialogLayoutOffHint: string = '';
  @State applyDialogHasCover: boolean = false;
  @State applyDialogApplyLayout: boolean = false;
  @State applyDialogApplyCover: boolean = false;
  @State applyDialogApplyIcon: boolean = true;
  private pendingApplyChoice: ((choice: ThemeApplyChoice | null) => void) | null = null;
  @State themeCatalog: ThemeCatalogItem[] = [];
  @State themeCatalogLoaded: boolean = false;
  // The last catalog request failed; prices stay hidden and the acquire buttons offer a retry.
  @State themeCatalogFailed: boolean = false;
  @State showThemeStore: boolean = false;
  @State storePageIndex: number = 0;
  /** Snapshot taken when the pager opens, so a purchase inside it does not reshuffle pages. */
  @State pagerEntries: ThemeListEntry[] = [];
  @State storeSwiperHeight: number = 0;
  /** Measured width of the detail page's split preview row; the same on every page. */
  @State storeRowWidth: number = 0;
  /** Same measurement for the "当前使用" card on the main list. */
  @State cardRowWidth: number = 0;
  private customSchemeRefreshSerial: number = 0;
  private commentBubbleImages: Map<string, ReaderCommentBubbleImage | null> =
    new Map<string, ReaderCommentBubbleImage | null>();

  aboutToAppear(): void {
    this.loadThemeSettings();
    this.refreshCustomSchemes();
    this.initializeAccount();
    this.refreshThemeCatalog();
    this.syncBars();
    const params = router.getParams() as ThemeSettingsRouteParams;
    if (params?.themeId === ThemeIds.OBSIDIAN_ARCHIVE) {
      this.openThemePager([new ThemeListEntry(BuiltinThemeRegistry.findById(params.themeId))], 0);
    }
    this.onPendingThemeImport();
  }

  aboutToDisappear(): void {
    if (this.showThemeImportDialog) {
      ThemePackageService.discardImport(this.importPreview);
    }
  }

  onPageShow(): void {
    this.refreshCustomSchemeLimit();
    ThemeTrialManager.stopIfExpired();
    AppIconManager.syncCurrentIcon(getContext(this)).catch((error: Error) => {
      console.warn('同步桌面图标失败:', error);
    });
    this.refreshCustomSchemes();
    this.syncBars();
  }

  onCustomThemeSchemesRevisionChanged(): void {
    this.refreshCustomSchemes();
  }

  refreshCustomSchemeLimit(): void {
    this.customSchemeLimit = CustomThemeQuota.current();
  }

  customSchemeAuthor(customSchemeId: string): string {
    if (!customSchemeId) return '';
    const scheme = CustomThemeSchemeStore.find(this.customSchemes, customSchemeId);
    return scheme ? scheme.author : '';
  }

  /** 主题分享 Beta 导出和导入都只对会员开放。 */
  async ensureThemeShareAccess(): Promise<boolean> {
    // 从外部打开主题包冷启动时，账号可能还没读完。
    await AccountSessionStore.load(getContext(this));
    if (ThemePackageService.isAvailable()) {
      return true;
    }
    const result = await promptAction.showDialog({
      title: '主题分享 Beta · 会员专享',
      message: '开通任一档会员后，可以把自定义主题导出为 .qytheme 主题包分享给好友，也可以导入别人分享的主题包。',
      buttons: [
        { text: '取消', color: this.subTextColor() },
        { text: '了解会员', color: this.accentColor() }
      ]
    });
    if (result.index === 1) {
      router.pushUrl({ url: 'pages/AccountCenter' });
    }
    return false;
  }

  async requestThemeExport(schemeId: string): Promise<void> {
    const scheme = CustomThemeSchemeStore.find(this.customSchemes, schemeId);
    if (!scheme || !(await this.ensureThemeShareAccess())) return;
    try {
      this.exportPlan = await ThemePackageService.planExport(getContext(this), scheme);
      this.showThemeExportDialog = true;
    } catch (e) {
      console.error('读取待导出主题失败:', e);
      HdsFeedback.showToast('读取主题失败，请稍后重试');
    }
  }

  async runThemeExport(options: ThemeExportOptions, share: boolean): Promise<void> {
    const scheme = CustomThemeSchemeStore.find(this.customSchemes, this.exportPlan.schemeId);
    if (!scheme) return;
    let result: ThemeExportResult | null = null;
    try {
      result = await ThemePackageService.buildPackage(getContext(this), scheme, options);
      if (share) {
        await ThemePackageService.share(getContext(this) as common.UIAbilityContext, result);
        this.showThemeExportDialog = false;
        // 分享面板异步读取文件，临时文件交给系统清理临时目录时一并删除。
        result = null;
      } else if (await ThemePackageService.saveToFile(getContext(this), result)) {
        this.showThemeExportDialog = false;
        HdsFeedback.showToast(`已导出「${result.fileName}」`);
      }
    } catch (e) {
      console.error('导出主题包失败:', e);
      HdsFeedback.showToast((e as Error).message || '导出失败，请稍后重试');
    } finally {
      ThemePackageService.discardExport(result);
    }
  }

  onPendingThemeImport(): void {
    const uri = AppStorage.get<string>('pendingThemeImportUri') || '';
    if (!uri) return;
    AppStorage.setOrCreate('pendingThemeImportUri', '');
    this.requestThemeImport(uri);
  }

  async requestThemeImport(sourceUri: string): Promise<void> {
    if (this.preparingThemeImport || this.showThemeImportDialog) return;
    if (!(await this.ensureThemeShareAccess())) return;
    this.preparingThemeImport = true;
    try {
      const uri = sourceUri || await ThemePackageService.pickPackage(getContext(this));
      if (!uri) return;
      this.importPreview = await ThemePackageService.prepareImport(getContext(this), uri);
      this.refreshCustomSchemeLimit();
      await this.refreshCustomSchemes();
      this.showThemeImportDialog = true;
    } catch (e) {
      console.error('读取主题包失败:', e);
      HdsFeedback.showToast((e as Error).message || '无法读取这个主题包');
    } finally {
      this.preparingThemeImport = false;
    }
  }

  closeThemeImport(): void {
    ThemePackageService.discardImport(this.importPreview);
    this.importPreview = new ThemeImportPreview();
    this.showThemeImportDialog = false;
  }

  async runThemeImport(replaceSchemeId: string): Promise<void> {
    try {
      const result = await ThemePackageService.commitImport(getContext(this), this.getUIContext(),
        this.importPreview, replaceSchemeId);
      this.importPreview = new ThemeImportPreview();
      this.showThemeImportDialog = false;
      await this.refreshCustomSchemes();
      let notice = `已导入「${result.scheme.name}」`;
      if (result.addedRules > 0) notice += `，追加 ${result.addedRules} 条强调规则`;
      if (result.missingFonts.length > 0) notice += `，${result.missingFonts.length} 款字体改用全局字体`;
      HdsFeedback.showToast(notice);
      const index = this.myThemeEntries().findIndex((entry: ThemeListEntry): boolean =>
        entry.customSchemeId === result.scheme.id);
      if (index >= 0) {
        this.openThemePager(this.myThemeEntries(), index);
      }
    } catch (e) {
      console.error('导入主题包失败:', e);
      HdsFeedback.showToast((e as Error).message || '导入失败，请稍后重试');
      // 写入失败时临时文件已清理，需要重新选择文件。
      this.importPreview = new ThemeImportPreview();
      this.showThemeImportDialog = false;
    }
  }

  onBackPress(): boolean {
    if (this.showThemeExportDialog) {
      this.showThemeExportDialog = false;
      return true;
    }
    if (this.showThemeImportDialog) {
      this.closeThemeImport();
      return true;
    }
    if (this.showThemeStore) {
      this.closeThemeStore();
      return true;
    }
    return false;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 列表铺满整页并从顶栏下方滚过去，上下留白由列表里的占位项提供。
      PageScaffold({ title: '主题', scrollable: false, edgeToEdge: true, externalCollapse: this.headerCollapse, content: () => {
        this.themeList()
      }, actions: () => {
        this.pointsBadge()
      } })

      if (this.showThemeStore) {
        this.themeStoreOverlay()
      }

      if (this.showCustomThemeActionMenu) {
        this.customThemeActionMenu()
      }
      if (this.showRenameCustomThemeDialog) {
        this.renameCustomThemeDialog()
      }
      if (this.showDeleteCustomThemeDialog) {
        this.deleteCustomThemeDialog()
      }
      if (this.showStartupTextDialog) {
        this.startupTextDialog()
      }
      if (this.showThemeApplyDialog) {
        this.themeApplyDialog()
      }
      if (this.showThemeExportDialog) {
        ThemeExportDialog({
          darkMode: this.appDarkMode,
          plan: this.exportPlan,
          onClose: () => {
            this.showThemeExportDialog = false;
          },
          onExport: (options: ThemeExportOptions, share: boolean): Promise<void> => this.runThemeExport(options, share)
        })
      }
      if (this.showThemeImportDialog) {
        ThemeImportDialog({
          darkMode: this.appDarkMode,
          preview: this.importPreview,
          schemes: this.customSchemes,
          limit: this.customSchemeLimit,
          activeSchemeId: this.appThemeId === ThemeIds.CUSTOM ? this.activeCustomSchemeId : '',
          onClose: () => this.closeThemeImport(),
          onImport: (replaceSchemeId: string): Promise<void> => this.runThemeImport(replaceSchemeId)
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      this.updateContextViewport(newValue);
    })
  }

  @Builder
  themeList() {
    List({ space: AppSpacing.LG, scroller: this.themeListScroller }) {
      // List padding is fixed to the viewport in ArkUI. Use real list items
      // for the safe-area gaps so they scroll away with the content.
      ListItem() {
        Row() {
        }
          .width('100%')
          .height(this.statusBarHeight + 58)
      }
      if (this.currentThemeEntries().length > 0) {
        ListItem() {
          this.sectionTitle('当前使用')
        }
      }
      // 单元素 ForEach：当前主题变化时靠 key 重建整张卡片。
      ForEach(this.currentThemeEntries(), (entry: ThemeListEntry) => {
        ListItem() {
          this.themeCard(entry.theme, entry.customSchemeId)
        }
      }, (entry: ThemeListEntry) => `current_${this.themeEntryKey(entry)}`)
      ListItem() {
        this.myThemesSectionTitle()
      }
      ListItem() {
        this.myThemesRow()
      }
      if (this.purchasedThemes().length > 0) {
        ListItem() {
          this.sectionTitle('已购主题')
        }
      }
      // 两列网格按行拆成列表项，跟着整页一起滚动。
      ForEach(this.themeRows(this.purchasedThemes()), (row: ThemePack[], rowIndex: number) => {
        ListItem() {
          this.themeGridRow(row, rowIndex, true)
        }
      }, (row: ThemePack[]) => `purchased_row_${row[0].id}_${this.accountEntitlementsRevision}`)
      if (this.moreThemes().length > 0) {
        ListItem() {
          this.sectionTitle('更多主题')
        }
      }
      ForEach(this.themeRows(this.moreThemes()), (row: ThemePack[], rowIndex: number) => {
        ListItem() {
          this.themeGridRow(row, rowIndex, false)
        }
      }, (row: ThemePack[]) => `more_row_${row[0].id}_${this.accountEntitlementsRevision}`)
      ListItem() {
        Row() {
        }
          .width('100%')
          .height(Math.max(20, this.navBarHeight + 8))
      }
    }
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .width('100%')
    .height('100%')
    // The list itself must own the system-safe-area expansion. Expanding
    // only its parent leaves the List viewport clipped to the safe area.
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .padding({
      left: AppSpacing.LG,
      right: AppSpacing.LG
    })
    .scrollBar(BarState.Off)
    .backgroundColor(this.pageColor())
    .onDidScroll((yOffset: number) => {
      this.headerCollapse = CollapsingHeader.next(this.headerCollapse, yOffset,
        this.themeListScroller.currentOffset().yOffset);
    })
    .onScrollStop(() => {
      const target = CollapsingHeader.settle(this.headerCollapse, this.themeListScroller.currentOffset().yOffset);
      if (target !== this.headerCollapse) {
        animateTo({ duration: 200, curve: Curve.FastOutSlowIn }, () => {
          this.headerCollapse = target;
        });
      }
    })
  }

  async initializeAccount(): Promise<void> {
    try {
      await HuaweiAccountService.initialize(getContext(this));
      if (AccountSessionStore.isLoggedIn() && AccountCommerceConfig.isServerConfigured()) {
        await HuaweiAccountService.refresh(getContext(this));
      }
    } catch (e) {
      console.warn('同步主题权益失败:', e);
    }
  }

  async refreshThemeCatalog(): Promise<void> {
    if (!AccountCommerceConfig.isServerConfigured()) {
      this.themeCatalogFailed = true;
      return;
    }
    this.themeCatalogFailed = false;
    try {
      const response: ThemeCatalogResponse = await AccountCommerceApi.fetchThemeCatalog();
      this.themeCatalog = response.themes || [];
      this.themeCatalogLoaded = true;
    } catch (e) {
      // Prices differ per theme, so nothing is shown or sold until the catalog
      // arrives; a previously loaded catalog stays in use.
      this.themeCatalogFailed = !this.themeCatalogLoaded;
      console.warn('同步主题目录失败:', e);
    }
  }

  async loadThemeSettings(): Promise<void> {
    try {
      const settings = await AppThemeSettingsStore.load(getContext(this));
      const theme = settings.themeId === ThemeIds.CUSTOM ?
        AppThemeSettingsStore.customTheme(settings, this.appDarkMode) :
        BuiltinThemeRegistry.findById(settings.themeId);
      if (settings.themeBookCoverEnabled && !this.themeHasBookCover(theme)) {
        settings.themeBookCoverEnabled = false;
        await AppThemeSettingsStore.save(getContext(this), settings);
      }
      AppThemeSettingsStore.applyToStorage(settings);
      this.appThemeId = settings.themeId;
      this.themeBookCoverEnabled = settings.themeBookCoverEnabled;
      const readerSettings = await ReaderSettingsStore.load(getContext(this));
      ReaderSettingsStore.applyToStorage(readerSettings);
    } catch (e) {
      console.warn('加载主题设置失败:', e);
    }
  }

  async refreshCustomSchemes(): Promise<void> {
    const serial = ++this.customSchemeRefreshSerial;
    try {
      const settings = await AppThemeSettingsStore.load(getContext(this));
      const schemes = await CustomThemeSchemeStore.load(getContext(this), settings);
      if (serial === this.customSchemeRefreshSerial) {
        this.customSchemes = schemes;
      }
      const summaries = new Map<string, string>();
      for (const scheme of schemes) {
        const profileId = ReaderSettingsStore.profileIdFor(ThemeIds.CUSTOM, scheme.id);
        if (!await ReaderSettingsStore.isTypographyBound(getContext(this), profileId)) continue;
        const profile = await ReaderSettingsStore.loadProfile(getContext(this), profileId);
        summaries.set(scheme.id, `绑定排版：字号 ${profile.fontSize} · 行距 ${profile.lineHeight} · ` +
          `边距 ${profile.marginLeft}/${profile.marginRight}`);
      }
      if (serial === this.customSchemeRefreshSerial) {
        this.boundLayoutSummaries = summaries;
        this.boundLayoutRevision++;
      }
    } catch (e) {
      console.warn('加载自定义主题方案失败:', e);
    }
  }

  themeLayoutSummary(theme: ThemePack, customSchemeId: string): string {
    const bound = this.boundLayoutRevision >= 0 && customSchemeId ?
      this.boundLayoutSummaries.get(customSchemeId) : undefined;
    return bound ?? `字号 ${theme.readerLayout.fontSize} · 行距 ${theme.readerLayout.lineHeight} · ` +
      `边距 ${theme.readerLayout.marginLeft}/${theme.readerLayout.marginRight}`;
  }

  async selectTheme(themeId: string, customSchemeId: string = '',
    askApplyOptions: boolean = true): Promise<void> {
    if (this.applyingThemeId) {
      return;
    }
    const customScheme = themeId === ThemeIds.CUSTOM ?
      CustomThemeSchemeStore.find(this.customSchemes, customSchemeId) : null;
    if (themeId === ThemeIds.CUSTOM && !customScheme) {
      return;
    }
    if (customScheme) {
      const unavailableStartupTheme = this.unavailableCustomStartupTheme(customScheme.settings);
      if (unavailableStartupTheme) {
        HdsFeedback.showToast(`方案使用的主题「${unavailableStartupTheme}」尚未获取或已过期`);
        return;
      }
    }
    if (ThemeTrialManager.isActive()) {
      ThemeTrialManager.stop(getContext(this) as common.UIAbilityContext);
      this.appThemeId = AppStorage.get<string>('appThemeId') || AppThemeSettingsStore.DEFAULT_THEME_ID;
      this.themeBookCoverEnabled = AppStorage.get<boolean>('appThemeBookCoverEnabled') || false;
    }
    if (themeId === this.appThemeId && themeId !== ThemeIds.CUSTOM) {
      return;
    }
    const accessible = await this.ensureThemeAccess(themeId);
    if (!accessible) {
      return;
    }
    this.applyingThemeId = customSchemeId || themeId;
    try {
      const theme = customScheme ? this.customTheme(customScheme) : BuiltinThemeRegistry.findById(themeId);
      const previous: AppThemeSettings = await AppThemeSettingsStore.load(getContext(this));
      // Applying a theme used to always overwrite the reader layout. Ask first so the
      // user decides whether the theme's typography and cover come along.
      const targetProfileId = ReaderSettingsStore.profileIdFor(themeId, customScheme ? customScheme.id : '');
      const typographyBound = customScheme ?
        await ReaderSettingsStore.isTypographyBound(getContext(this), targetProfileId) : false;
      const currentReader = await ReaderSettingsStore.load(getContext(this));
      const choice: ThemeApplyChoice | null = askApplyOptions ?
        await this.promptThemeApplyOptions(theme, previous, typographyBound,
          await ReaderSettingsStore.loadProfile(getContext(this), targetProfileId), currentReader) :
        ThemeApplyChoice.preserve();
      if (!choice) {
        return;
      }
      // 应用前记下当前档案：自定义方案之间切换时主题 ID 都是 custom，靠方案 ID 区分各自的排版。
      const previousProfileId = ReaderSettingsStore.activeProfileId();
      let settings: AppThemeSettings = AppThemeSettingsStore.activateTheme(themeId, previous);
      if (customScheme) {
        settings = AppThemeSettingsStore.applyCustomSnapshot(settings, customScheme.settings);
      }
      settings.themeBookCoverEnabled = choice.applyCover;
      settings.themeApplyLayoutEnabled = choice.applyLayout;
      AppThemeSettingsStore.applyToStorage(settings);
      await AppThemeSettingsStore.save(getContext(this), settings);
      if (customScheme) {
        await CustomThemeSchemeStore.setActiveScheme(getContext(this), customScheme);
        this.activeCustomSchemeId = customScheme.id;
        this.activeCustomSchemeRevision = customScheme.revision;
      }
      this.appThemeId = settings.themeId;
      this.themeBookCoverEnabled = settings.themeBookCoverEnabled;
      const readerSettings = await ReaderSettingsStore.switchThemeProfile(getContext(this), previousProfileId,
        ReaderSettingsStore.profileIdFor(settings.themeId, customScheme ? customScheme.id : ''));
      if (typographyBound) {
        // 绑定了排版的方案：开关打开即沿用绑定排版（档案里已经是它）；关闭则把应用前的排版带过来。
        if (askApplyOptions && !choice.applyLayout) {
          await ReaderSettingsStore.saveTypographyToProfile(getContext(this), targetProfileId, currentReader);
        }
      } else if (choice.applyLayout) {
        const layout = theme.readerLayout;
        await ReaderSettingsStore.saveLayoutSettings(getContext(this), layout.fontSize, layout.lineHeight,
          layout.paragraphSpacing, layout.marginLeft, layout.marginRight, layout.marginTop, layout.marginBottom,
          layout.letterSpacing, readerSettings.textAlign);
      }
      await ReaderSettingsStore.saveThemeSettings(getContext(this), ReaderThemeHelper.APP_THEME_INDEX,
        ReaderThemeHelper.APP_THEME_INDEX, readerSettings.lightCustomThemeBackgroundColor,
        readerSettings.lightCustomThemeTextColor, readerSettings.darkCustomThemeBackgroundColor,
        readerSettings.darkCustomThemeTextColor, this.appDarkMode, readerSettings.customThemesRaw);
      this.readerLightThemeIndex = ReaderThemeHelper.APP_THEME_INDEX;
      this.readerDarkThemeIndex = ReaderThemeHelper.APP_THEME_INDEX;
      this.focusedThemeId = '';
      ReaderFontBootstrap.applyApplicationFont(getContext(this), 'theme-settings');
      this.refreshRecentReadCard();
      this.syncBars();
      let iconNotice = '';
      if (choice.applyIcon) {
        if (!AppIconManager.isSupported()) {
          iconNotice = `；桌面图标未更换，${AppIconManager.UNSUPPORTED_MESSAGE}`;
        } else {
          try {
            await AppIconManager.applyIcon(getContext(this), AppIconManager.optionForTheme(theme.id));
          } catch (error) {
            console.warn('应用主题桌面图标失败:', error);
            iconNotice = '；桌面图标切换失败，可在图标设置中重试';
          }
        }
      }
      HdsFeedback.showToast((choice.applyLayout ? `已应用「${theme.name}」主题` :
        `已应用「${theme.name}」主题，排版保持不变`) + iconNotice);
    } catch (e) {
      console.error('应用主题失败:', e);
      HdsFeedback.showToast('应用主题失败，请稍后重试');
    } finally {
      this.applyingThemeId = '';
    }
  }

  promptThemeApplyOptions(theme: ThemePack, previous: AppThemeSettings, typographyBound: boolean,
    targetReader: ReaderSettings, currentReader: ReaderSettings): Promise<ThemeApplyChoice | null> {
    this.applyDialogThemeName = theme.name;
    const preset = theme.readerLayout;
    const presetSummary = this.layoutSummary(preset.fontSize, preset.lineHeight, preset.paragraphSpacing,
      preset.marginLeft, preset.marginRight);
    const targetSummary = this.layoutSummary(targetReader.fontSize, targetReader.lineHeight,
      targetReader.paragraphSpacing, targetReader.marginLeft, targetReader.marginRight);
    this.applyDialogHasCover = this.themeHasBookCover(theme);
    if (theme.id === ThemeIds.CUSTOM && typographyBound) {
      // 在主题排版页保存过排版的方案：打开（默认）用绑定排版，关闭则保留应用前的排版。
      this.applyDialogLayoutOnHint = `使用主题绑定的排版：${targetSummary}，含页眉页脚与阅读字体`;
      this.applyDialogLayoutOffHint = `保留当前排版：${this.layoutSummary(currentReader.fontSize,
        currentReader.lineHeight, currentReader.paragraphSpacing, currentReader.marginLeft,
        currentReader.marginRight)}，并替换主题绑定的排版`;
      this.applyDialogApplyLayout = true;
    } else {
      this.applyDialogLayoutOnHint = `重置为主题预设：${presetSummary}`;
      this.applyDialogLayoutOffHint = `沿用这套主题已有的排版：${targetSummary}`;
      // 自定义方案默认开启主题排版；内置主题沿用上次的选择。
      this.applyDialogApplyLayout = theme.id === ThemeIds.CUSTOM ? true : previous.themeApplyLayoutEnabled;
    }
    // 主题带封面时默认勾选“应用主题封面”，不再沿用上次的选择。
    this.applyDialogApplyCover = this.applyDialogHasCover;
    this.applyDialogApplyIcon = true;
    this.showThemeApplyDialog = true;
    return new Promise<ThemeApplyChoice | null>(
      (resolve: (choice: ThemeApplyChoice | null) => void) => {
        this.pendingApplyChoice = resolve;
      });
  }

  confirmThemeApply(): void {
    const choice = new ThemeApplyChoice();
    choice.applyLayout = this.applyDialogApplyLayout;
    choice.applyCover = this.applyDialogHasCover && this.applyDialogApplyCover;
    choice.applyIcon = this.applyDialogApplyIcon;
    const resolve = this.pendingApplyChoice;
    this.closeThemeApplyDialog();
    if (resolve) {
      resolve(choice);
    }
  }

  cancelThemeApply(): void {
    const resolve = this.pendingApplyChoice;
    this.closeThemeApplyDialog();
    if (resolve) {
      resolve(null);
    }
  }

  layoutSummary(fontSize: number, lineHeight: number, paragraphSpacing: number, marginLeft: number,
    marginRight: number): string {
    return `字号 ${fontSize} · 行距 ${lineHeight} · 段距 ${paragraphSpacing} · 边距 ${marginLeft}/${marginRight}`;
  }

  closeThemeApplyDialog(): void {
    this.showThemeApplyDialog = false;
    this.pendingApplyChoice = null;
    this.applyDialogThemeName = '';
    this.applyDialogLayoutOnHint = '';
    this.applyDialogLayoutOffHint = '';
    this.applyDialogHasCover = false;
  }

  async ensureThemeAccess(themeId: string): Promise<boolean> {
    if (themeId === ThemeIds.CUSTOM || this.hasThemeAccess(themeId)) {
      return true;
    }
    if (themeId === ThemeIds.OBSIDIAN_ARCHIVE) return this.claimExclusiveTheme();
    const offer = this.themeOffer(themeId);
    if (!offer) {
      if (this.themeCatalogLoaded) {
        HdsFeedback.showToast('该主题暂未上架');
      } else {
        HdsFeedback.showToast('主题价格尚未加载，请稍后重试');
        this.refreshThemeCatalog();
      }
      return false;
    }
    const pricePoints = offer.pricePoints;
    const validDays = offer.validDays;
    if (!this.accountLoggedIn) {
      const loginDialog = await promptAction.showDialog({
        title: '登录后获取主题',
        message: `该主题需要 ${pricePoints} 点，获取后有效 ${validDays} 天。首次登录免费送 300 点。`,
        buttons: [
          { text: '取消', color: this.subTextColor() },
          { text: '去登录', color: this.accentColor() }
        ]
      });
      if (loginDialog.index === 1) {
        router.pushUrl({ url: 'pages/AccountCenter' });
      }
      return false;
    }
    const theme = BuiltinThemeRegistry.findById(themeId);
    const confirm = await promptAction.showDialog({
      title: `获取「${theme.name}」`,
      message: `将扣除 ${pricePoints} 点，主题有效期为 ${validDays} 天。有效期内可在所有已登录终端使用。`,
      buttons: [
        { text: '取消', color: this.subTextColor() },
        { text: `确认 · ${pricePoints} 点`, color: this.accentColor() }
      ]
    });
    if (confirm.index !== 1) {
      return false;
    }
    try {
      await HuaweiAccountService.redeemTheme(getContext(this), themeId, pricePoints, validDays);
      HdsFeedback.showToast(`已获取「${theme.name}」，有效期 ${validDays} 天`);
      return true;
    } catch (e) {
      const error = e as AccountApiError;
      if (error.errorCode === 'THEME_OFFER_CHANGED') {
        await this.refreshThemeCatalog();
        HdsFeedback.showToast('主题价格或有效期已更新，请重新确认');
      } else if (error.errorCode === 'INSUFFICIENT_POINTS') {
        const recharge = await promptAction.showDialog({
          title: '点数不足',
          message: `当前有 ${this.accountPoints} 点，获取该主题需要 ${pricePoints} 点。`,
          buttons: [
            { text: '取消', color: this.subTextColor() },
            { text: '去充值', color: this.accentColor() }
          ]
        });
        if (recharge.index === 1) {
          router.pushUrl({ url: 'pages/AccountCenter' });
        }
      } else {
        HdsFeedback.showToast(error.message || '获取主题失败，请稍后重试');
      }
      return false;
    }
  }

  themeOffer(themeId: string): ThemeCatalogItem | null {
    for (let index = 0; index < this.themeCatalog.length; index++) {
      const offer = this.themeCatalog[index];
      if (offer && offer.themeId === themeId &&
        (offer.pricePoints > 0 || offer.acquisition === 'SUPER_CLAIM') && offer.validDays > 0) {
        return offer;
      }
    }
    return null;
  }

  async claimExclusiveTheme(): Promise<boolean> {
    if (!this.accountLoggedIn) {
      HdsFeedback.showToast('请登录终身超级会员账号后领取');
      router.pushUrl({ url: 'pages/AccountCenter' });
      return false;
    }
    try {
      await HuaweiAccountService.refresh(getContext(this));
      if (AccountSessionStore.activeMembershipSku() !== 'SUPER_LIFETIME') {
        HdsFeedback.showToast('「曜金藏书」仅供终身超级会员领取，不支持点数购买');
        router.pushUrl({ url: 'pages/AccountCenter' });
        return false;
      }
      if (AccountSessionStore.hasOwnedEntitlement(ThemeIds.OBSIDIAN_ARCHIVE)) return true;
      if (!this.themeOffer(ThemeIds.OBSIDIAN_ARCHIVE)) {
        await this.refreshThemeCatalog();
        if (!this.themeOffer(ThemeIds.OBSIDIAN_ARCHIVE)) {
          HdsFeedback.showToast('专属主题暂未开放领取，请稍后再试');
          return false;
        }
      }
      const choice = await promptAction.showDialog({
        title: '领取「曜金藏书」',
        message: '终身超级会员专属，不扣除点数。领取后有效一年，到期后可再次手动领取；有效期内不重复叠加。',
        buttons: [{ text: '取消', color: this.subTextColor() }, { text: '领取一年', color: this.accentColor() }]
      });
      if (choice.index !== 1) return false;
      await MembershipCommerceService.claimSuperTheme(getContext(this), ThemeIds.OBSIDIAN_ARCHIVE);
      HdsFeedback.showToast('已领取「曜金藏书」，有效一年');
      return AccountSessionStore.hasOwnedEntitlement(ThemeIds.OBSIDIAN_ARCHIVE);
    } catch (e) {
      HdsFeedback.showToast((e as Error).message || '领取失败，请稍后重试');
      return false;
    }
  }

  async setThemeBookCoverEnabled(enabled: boolean): Promise<void> {
    try {
      const settings = await AppThemeSettingsStore.load(getContext(this));
      settings.themeBookCoverEnabled = enabled;
      AppThemeSettingsStore.applyToStorage(settings);
      await AppThemeSettingsStore.save(getContext(this), settings);
      this.themeBookCoverEnabled = enabled;
      HdsFeedback.showToast(enabled ? '已启用主题封面与书籍边框' : '已恢复图书原封面');
    } catch (e) {
      console.error('保存主题封面设置失败:', e);
      HdsFeedback.showToast('保存主题封面设置失败');
    }
  }

  refreshRecentReadCard(): void {
    const context = getContext(this) as common.UIAbilityContext;
    RecentReadCardUpdater.reload(context).catch((e: Error) => {
      console.warn('主题切换后刷新最近阅读卡片失败:', e);
    });
  }

  customTheme(scheme: CustomThemeScheme): ThemePack {
    const theme = AppThemeSettingsStore.customTheme(scheme.settings, this.appDarkMode);
    theme.name = scheme.name;
    theme.description = '自由组合浅色与深色模式下的主题部件';
    return theme;
  }

  activeVariant(theme: ThemePack): ThemeVariant {
    return this.appDarkMode ? theme.dark : theme.light;
  }

  isSelected(theme: ThemePack, customSchemeId: string = ''): boolean {
    if (theme.id === ThemeIds.CUSTOM) {
      const scheme = CustomThemeSchemeStore.find(this.customSchemes, customSchemeId);
      return this.appThemeId === ThemeIds.CUSTOM && this.activeCustomSchemeId === customSchemeId &&
        !!scheme && scheme.revision === this.activeCustomSchemeRevision;
    }
    return theme.id === this.appThemeId;
  }

  pageColor(): string {
    return ThemeRuntime.pageColor(this.appDarkMode);
  }

  cardColor(): string {
    return ThemeRuntime.cardColor(this.appDarkMode);
  }

  titleBarSurfaceColor(): string {
    return ThemeRuntime.topBarColor(this.appDarkMode);
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

  @Builder
  sectionTitle(title: string) {
    Text(title)
      .fontSize(AppFontSize.BODY)
      .fontColor(this.subTextColor())
      .width('100%')
      .padding({ left: AppSpacing.XXS, top: AppSpacing.SM, bottom: 0 })
  }

  @Builder
  pointsBadge() {
    if (this.accountLoggedIn) {
      Text(`${this.accountPoints} 点`)
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.accentColor())
        .padding({ left: AppSpacing.MD, right: AppSpacing.MD, top: AppSpacing.XS, bottom: AppSpacing.XS })
        .borderRadius(ThemeRuntime.buttonRadius())
        .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
        .margin({ right: AppSpacing.LG })
        .accessibilityText(`当前 ${this.accountPoints} 点，打开账号中心`)
        .onClick(() => {
          router.pushUrl({ url: 'pages/AccountCenter' });
        })
    }
  }

  @Builder
  themeGridRow(row: ThemePack[], rowIndex: number, purchased: boolean) {
    Row({ space: AppSpacing.LG }) {
      this.themeGridCell(row[0], rowIndex * 2, purchased)
      if (row.length > 1) {
        this.themeGridCell(row[1], rowIndex * 2 + 1, purchased)
      } else {
        Row()
          .layoutWeight(1)
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  /** Grid thumbnail for one builtin theme; tapping opens its detail page. */
  @Builder
  themeGridCell(theme: ThemePack, index: number, purchased: boolean) {
    Column({ space: AppSpacing.MD }) {
      Stack() {
        ThemeStartupCover({
          themeId: theme.startup.styleId,
          darkMode: this.appDarkMode,
          compact: true,
          animated: false
        })
      }
      .width('100%')
      .height(STORE_GRID_COVER_HEIGHT)
      .borderRadius(theme.radius.medium)
      .clip(true)

      Row({ space: AppSpacing.SM }) {
        Text(theme.name)
          .fontSize(AppFontSize.BODY)
          .fontWeight(FontWeight.Bold)
          .fontFamily(theme.typography.appFontFamily)
          .fontColor(this.activeVariant(theme).colors.primaryTextColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        this.storeThemeStatusPill(theme)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .layoutWeight(1)
    .padding(AppSpacing.MD)
    .borderRadius(theme.radius.card)
    .backgroundColor(this.activeVariant(theme).colors.cardColor)
    .border({
      width: this.isSelected(theme) ? 2 : 1,
      color: this.isSelected(theme) ? this.activeVariant(theme).colors.accentColor :
        this.activeVariant(theme).colors.dividerColor
    })
    .accessibilityText(`查看「${theme.name}」主题详情`)
    .onClick(() => this.openThemePager(
      this.builtinEntries(purchased ? this.purchasedThemes() : this.moreThemes()), index))
  }

  /** Full-screen theme detail pager: one themed showcase page per swipe. */
  @Builder
  themeStoreOverlay() {
    Column() {
      this.themeStoreHeader()
      if (this.pagerEntries.length > 1) {
        Text('左右滑动浏览其他主题')
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
          .width('100%')
          .padding({ left: AppSpacing.XXL, top: AppSpacing.MD, bottom: AppSpacing.XXS })
      }
      this.themeStoreSwiper()
      this.storePageDots()
    }
    .width('100%')
    .height('100%')
    .padding({ bottom: Math.max(12, this.navBarHeight) })
    .backgroundColor(this.pageColor())
    .transition(TransitionEffect.translate({ y: 64 })
      .combine(TransitionEffect.opacity(0))
      .animation({ duration: 260, curve: Curve.Friction }))
  }

  @Builder
  themeStoreHeader() {
    Row() {
      ImmersiveBackButton({ iconColor: this.primaryTextColor(), darkMode: this.appDarkMode,
        buttonSize: 40, containerWidth: 40, containerHeight: 40,
        startInset: 0, materialScale: 0.83, compactLayout: true,
        accessibilityLabel: '返回主题设置', onBack: () => this.closeThemeStore() })
      Text('主题详情')
        .fontSize(AppFontSize.TITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)
        .margin({ left: AppSpacing.XXS })
      if (this.accountLoggedIn) {
        Text(`${this.accountPoints} 点`)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.accentColor())
          .padding({ left: AppSpacing.MD, right: AppSpacing.MD, top: AppSpacing.XS, bottom: AppSpacing.XS })
          .borderRadius(ThemeRuntime.buttonRadius())
          .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
      }
    }
    .width('100%')
    .height(56 + this.statusBarHeight)
    .padding({ top: this.statusBarHeight, left: AppSpacing.LG, right: AppSpacing.LG })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  themeStoreSwiper() {
    Swiper() {
      ForEach(this.pagerEntries, (entry: ThemeListEntry) => {
        // A vertical scroll is the safety net for viewports too short for the
        // fixed detail rows; the cover height normally keeps the page fitting.
        Scroll() {
          this.storeThemePage(entry.theme, entry.customSchemeId)
        }
        .width('100%')
        .height('100%')
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }, (entry: ThemeListEntry) => `pager_${this.themeEntryKey(entry)}`)
    }
    .index(this.storePageIndex)
    .indicator(false)
    .loop(false)
    .duration(300)
    .onChange((index: number) => {
      this.storePageIndex = index;
    })
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      const height = Number(newValue.height);
      if (Number.isFinite(height) && height > 0) {
        this.storeSwiperHeight = height;
      }
    })
    .width('100%')
    .layoutWeight(1)
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.MD, bottom: AppSpacing.SM })
  }

  @Builder
  storePageDots() {
    Row({ space: AppSpacing.SM }) {
      ForEach(this.pagerEntries, (_entry: ThemeListEntry, index: number) => {
        Row()
          .width(index === this.storePageIndex ? 16 : 6)
          .height(6)
          .borderRadius(3)
          .backgroundColor(index === this.storePageIndex ? this.accentColor() :
            (this.appDarkMode ? '#4DFFFFFF' : '#26000000'))
      }, (entry: ThemeListEntry) => `pager_dot_${entry.customSchemeId || entry.theme.id}`)
    }
    .justifyContent(FlexAlign.Center)
    .width('100%')
    .height(18)
  }

  /** One full detail page per theme: cover art, reader sample, pricing and actions. */
  @Builder
  storeThemePage(theme: ThemePack, customSchemeId: string = '') {
    Column({ space: AppSpacing.MD }) {
      this.themePreviewPanes(theme, customSchemeId, true)

      Row({ space: AppSpacing.MD }) {
        Image(AppIconManager.optionForTheme(theme.id).preview)
          .width(52)
          .height(52)
          .borderRadius(13)
          .objectFit(ImageFit.Cover)
          .draggable(false)
          .accessibilityText(`${theme.name}桌面图标预览`)
        Column({ space: AppSpacing.XXS }) {
          Text(theme.name)
            .fontSize(AppFontSize.SUBTITLE)
            .fontWeight(FontWeight.Bold)
            .fontFamily(theme.typography.appFontFamily)
            .fontColor(this.activeVariant(theme).colors.primaryTextColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(theme.description)
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.activeVariant(theme).colors.subTextColor)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        this.storeThemeStatusPill(theme, customSchemeId)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row({ space: AppSpacing.MD }) {
        Text(this.storeThemeCaption(theme))
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.activeVariant(theme).colors.accentColor)
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .alignItems(VerticalAlign.Center)

      this.storeNavInfoRow(theme, customSchemeId)
      this.storeThemeActions(theme, customSchemeId)
      if (this.customSchemeAuthor(customSchemeId)) {
        Text(themeAuthorLine(this.customSchemeAuthor(customSchemeId)))
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.activeVariant(theme).colors.subTextColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.End)
          .width('100%')
      }
    }
    .width('100%')
    .padding(AppSpacing.LG)
    .alignItems(HorizontalAlign.Start)
    .borderRadius(theme.radius.card)
    .backgroundColor(this.activeVariant(theme).colors.cardColor)
    .border({
      width: this.isSelected(theme, customSchemeId) ? 2 : 1,
      color: this.isSelected(theme, customSchemeId) ? this.activeVariant(theme).colors.accentColor :
        this.activeVariant(theme).colors.dividerColor
    })
  }

  /**
   * Preview strip shared by the detail pager and the "当前使用" card:
   * startup cover | reader page | player panel | book cover, all at the book
   * cover's height. On the "当前使用" card three pane widths fit the strip, so
   * four panes rest centred with both outer panes peeking in. In the detail
   * pager the strip is a carousel: one tall pane centred at a time, snapping
   * from pane to pane and starting on the startup cover.
   */
  @Builder
  themePreviewPanes(theme: ThemePack, customSchemeId: string, inPager: boolean) {
    Scroll() {
      Row({ space: AppSpacing.MD }) {
        Stack({ alignContent: Alignment.TopStart }) {
          ThemeStartupCover({
            themeId: theme.startup.styleId,
            darkMode: this.appDarkMode,
            // A pane on a phone is a scaled-down screen; the compact text
            // sizes keep the copy in proportion and inside the pane.
            compact: this.previewPaneWidth(theme, inPager) < 240,
            animated: false,
            customImagePath: this.customPreviewStartupImage(customSchemeId),
            titleOverride: this.customPreviewStartupTitle(customSchemeId),
            subtitleOverride: this.customPreviewStartupSubtitle(customSchemeId),
            explicitText: !!customSchemeId
          })
          this.storePaneLabel('启动封面')
          if (!inPager && theme.id !== ThemeIds.PLAIN_DEFAULT && theme.id !== ThemeIds.CUSTOM) {
            // The copy itself is the edit target: the hint sits right above it
            // and the whole strip, hint and copy, is tappable.
            Column() {
              Blank()
              Column() {
                Text('编辑启动文案')
                  .fontSize(AppFontSize.MICRO)
                  .fontColor('#F2FFFFFF')
                  .padding({ left: AppSpacing.SM, right: AppSpacing.SM, top: AppSpacing.XXS, bottom: AppSpacing.XXS })
                  .borderRadius(8)
                  .backgroundColor('#52000000')
                  .border({ width: 0.5, color: '#55FFFFFF' })
                // Leaves room for ThemeStartupCover's compact title and subtitle below the hint.
                Row()
                  .height(STARTUP_COPY_STRIP_HEIGHT)
              }
              .width('100%')
              .alignItems(HorizontalAlign.Center)
              .accessibilityText('编辑启动文案')
              .onClick(() => this.openStartupTextDialog(theme.id))
            }
            .width('100%')
            .height('100%')
            .hitTestBehavior(HitTestMode.Transparent)
          }
        }
        .width(this.previewPaneWidth(theme, inPager))
        .height(this.previewPaneHeight(inPager))
        .borderRadius(theme.radius.large)
        .clip(true)

        this.storeReaderPane(theme, inPager)
        this.storeTtsPane(theme, customSchemeId, inPager)
        if (this.themeHasBookCover(theme)) {
          this.storeBookCoverPane(theme, inPager)
        }
      }
      // Side padding lets the first and last pane come to rest in the centre too.
      .padding({ left: this.previewStripInset(theme, inPager), right: this.previewStripInset(theme, inPager) })
    }
    .width('100%')
    .height(this.previewPaneHeight(inPager))
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    // In the pager the strip rebounds at its ends instead of going quiet, so the
    // gesture stays with it and never falls through to the theme pager.
    .edgeEffect(inPager ? EdgeEffect.Spring : EdgeEffect.None, { alwaysEnabled: true })
    .scrollSnap({
      snapAlign: inPager ? ScrollSnapAlign.START : ScrollSnapAlign.NONE,
      snapPagination: this.previewPaneWidth(theme, inPager) + AppSpacing.MD
    })
    // Card strip only: half of the one pane (plus gap) that overflows, (width + gap) / 6 of the strip.
    .initialOffset({ xOffset: !inPager && this.themeHasBookCover(theme) ? '17%' : 0 })
    // Swipes on the strip only ever move the strip; themes change by swiping anywhere below it.
    .nestedScroll({ scrollForward: NestedScrollMode.SELF_ONLY, scrollBackward: NestedScrollMode.SELF_ONLY })
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      const width = Number(newValue.width);
      if (Number.isFinite(width) && width > 0) {
        if (inPager) {
          this.storeRowWidth = width;
        } else {
          this.cardRowWidth = width;
        }
      }
    })
  }

  @Builder
  storePaneLabel(label: string) {
    Text(label)
      .fontSize(AppFontSize.MICRO)
      .fontColor('#F2FFFFFF')
      .padding({ left: AppSpacing.SM, right: AppSpacing.SM, top: AppSpacing.XXS, bottom: AppSpacing.XXS })
      .borderRadius(8)
      .backgroundColor('#52000000')
      .margin(AppSpacing.SM)
      .hitTestBehavior(HitTestMode.None)
  }

  /** Last pane of the preview strip: the theme's book cover with its shelf frame. */
  @Builder
  storeBookCoverPane(theme: ThemePack, inPager: boolean) {
    Stack({ alignContent: Alignment.TopStart }) {
      Stack() {
        Stack() {
          Swiper() {
            ForEach(this.themeCoverSet(theme), (cover: ResourceStr, index: number) => {
              Image(cover)
                .width('100%')
                .height('100%')
                .objectFit(ImageFit.Fill)
                .draggable(false)
            }, (_cover: ResourceStr, index: number) => `store_${theme.id}_cover_${index}`)
          }
          .width('100%')
          .height('100%')
          .autoPlay(this.themeCoverSet(theme).length > 1)
          .interval(2800)
          .indicator(false)
          .loop(true)
          // Horizontal swipes belong to the preview strip; the covers only auto-play.
          .disableSwipe(true)
          Image(ThemeAssetRegistry.themeShelfFrame(theme.book.shelfFrameAssetId))
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Fill)
            .draggable(false)
            .hitTestBehavior(HitTestMode.None)
        }
        .width(this.storeBookCoverWidth(theme, inPager))
        .height(this.storeBookCoverWidth(theme, inPager) / STORE_BOOK_COVER_RATIO)
      }
      .width('100%')
      .height('100%')
      this.storePaneLabel('书籍封面')
    }
    .width(this.previewPaneWidth(theme, inPager))
    .height(this.previewPaneHeight(inPager))
    .borderRadius(theme.radius.large)
    .clip(true)
    .backgroundColor(this.activeVariant(theme).colors.inputColor)
  }

  /** Second pane of the preview strip: a scaled-down reader page on the theme's paper. */
  @Builder
  storeReaderPane(theme: ThemePack, inPager: boolean) {
    Stack({ alignContent: Alignment.TopStart }) {
      ReaderThemeBackground({
        surfaceColor: this.activeVariant(theme).reader.backgroundColor,
        backgroundAssetId: this.activeVariant(theme).reader.backgroundAssetId,
        compact: !inPager
      })
      Text() {
        ForEach(READER_PREVIEW_SEGMENTS, (segment: ReaderPreviewSegment) => {
          if (segment.comment) {
            Span('\u00A0')
            this.commentBubbleSpan(theme, segment.text, this.storeReaderPaneFontSize(inPager) * 0.85,
              this.activeVariant(theme).reader.contentTone === 'dark')
          } else if (!segment.emphasis) {
            Span(segment.text)
          } else if (this.themeHasRegexBubbleCap(theme)) {
            ContainerSpan() {
              ImageSpan(ThemeAssetRegistry.regexBubbleCap(this.activeVariant(theme).regexEmphasis.bubbleStyle))
                .width(this.storeReaderPaneFontSize(inPager))
                .height(this.storeReaderPaneFontSize(inPager))
                .objectFit(ImageFit.Contain)
                .verticalAlign(ImageSpanAlignment.CENTER)
              Span(segment.text)
                .fontColor(this.themeRegexPreview(theme).textColor)
                .textShadow(this.themeRegexPreviewShadow(theme))
              ImageSpan(ThemeAssetRegistry.regexBubbleCap(this.activeVariant(theme).regexEmphasis.bubbleStyle))
                .width(this.storeReaderPaneFontSize(inPager))
                .height(this.storeReaderPaneFontSize(inPager))
                .objectFit(ImageFit.Contain)
                .verticalAlign(ImageSpanAlignment.CENTER)
                .rotate({ angle: 180 })
            }
            .textBackgroundStyle(this.themeRegexPreviewBackground(theme))
          } else {
            ContainerSpan() {
              Span(segment.text)
                .fontColor(this.themeRegexPreview(theme).textColor)
                .textShadow(this.themeRegexPreviewShadow(theme))
            }
            .textBackgroundStyle(this.themeRegexPreviewBackground(theme))
          }
        }, (_segment: ReaderPreviewSegment, index: number) => `reader_preview_${theme.id}_${index}`)
      }
      .fontSize(this.storeReaderPaneFontSize(inPager))
      .lineHeight(this.storeReaderPaneLineHeight(inPager))
      .fontFamily(theme.typography.appFontFamily)
      .fontColor(this.activeVariant(theme).reader.textColor)
      .maxLines(this.storeReaderPaneLines(inPager))
      .textOverflow({ overflow: TextOverflow.Clip })
      .width('100%')
      .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: 32 })
      .hitTestBehavior(HitTestMode.None)
      this.storePaneLabel('阅读页')
    }
    .width(this.previewPaneWidth(theme, inPager))
    .height(this.previewPaneHeight(inPager))
    .borderRadius(theme.radius.large)
    .clip(true)
  }

  /** Third pane of the preview strip: a scaled-down TTS / audiobook player on the theme's panel background. */
  @Builder
  storeTtsPane(theme: ThemePack, customSchemeId: string, inPager: boolean) {
    Stack({ alignContent: Alignment.TopStart }) {
      TtsPanelThemeBackground({
        themeId: this.previewTtsPanelThemeId(theme, customSchemeId),
        darkMode: this.appDarkMode
      })
      Column({ space: AppSpacing.SM * this.storeTtsPaneScale(inPager) }) {
        Column({ space: AppSpacing.XS * this.storeTtsPaneScale(inPager) }) {
          Stack() {
            if (this.themeHasBookCover(theme)) {
              Image(ThemeAssetRegistry.themeBookCover(theme.book.coverAssetId))
                .height('100%')
                .aspectRatio(STORE_BOOK_COVER_RATIO)
                .borderRadius(theme.radius.small)
                .objectFit(ImageFit.Cover)
                .draggable(false)
            } else {
              Column()
                .height('100%')
                .aspectRatio(STORE_BOOK_COVER_RATIO)
                .borderRadius(theme.radius.small)
                .backgroundColor(this.activeVariant(theme).colors.accentColor)
            }
          }
          .width('100%')
          .layoutWeight(1)
          Row()
            .width('100%')
            .height(4 * this.storeTtsPaneScale(inPager))
            .borderRadius(4)
            .backgroundColor(this.withAlpha(this.activeVariant(theme).colors.primaryTextColor, '40'))
          Row()
            .width('70%')
            .height(4 * this.storeTtsPaneScale(inPager))
            .borderRadius(4)
            .backgroundColor(this.withAlpha(this.activeVariant(theme).colors.primaryTextColor, '26'))
        }
        .width('100%')
        .layoutWeight(1)
        .padding(AppSpacing.SM * this.storeTtsPaneScale(inPager))
        .alignItems(HorizontalAlign.Start)
        .borderRadius(theme.radius.medium)
        .backgroundColor(this.withAlpha(this.activeVariant(theme).colors.accentColor, '1F'))

        Stack({ alignContent: Alignment.Start }) {
          Row()
            .width('100%')
            .height(3 * this.storeTtsPaneScale(inPager))
            .borderRadius(3)
            .backgroundColor(this.withAlpha(this.activeVariant(theme).colors.primaryTextColor, '26'))
          Row()
            .width('42%')
            .height(3 * this.storeTtsPaneScale(inPager))
            .borderRadius(3)
            .backgroundColor(this.activeVariant(theme).colors.accentColor)
        }
        .width('100%')

        Row() {
          ForEach([0, 1, 2, 3, 4], (slot: number) => {
            Circle()
              .width((slot === 2 ? 18 : 11) * this.storeTtsPaneScale(inPager))
              .height((slot === 2 ? 18 : 11) * this.storeTtsPaneScale(inPager))
              .fill(slot === 2 ? this.activeVariant(theme).colors.buttonColor :
                this.withAlpha(this.activeVariant(theme).colors.primaryTextColor, '33'))
          }, (slot: number) => `tts_pane_control_${slot}`)
        }
        .width('100%')
        .height(18 * this.storeTtsPaneScale(inPager))
        .justifyContent(FlexAlign.SpaceBetween)
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .height('100%')
      .padding({
        left: AppSpacing.MD * this.storeTtsPaneScale(inPager),
        right: AppSpacing.MD * this.storeTtsPaneScale(inPager),
        top: 32,
        bottom: AppSpacing.LG * this.storeTtsPaneScale(inPager)
      })
      .hitTestBehavior(HitTestMode.None)
      this.storePaneLabel('朗读/有声书')
    }
    .width(this.previewPaneWidth(theme, inPager))
    .height(this.previewPaneHeight(inPager))
    .borderRadius(theme.radius.large)
    .clip(true)
  }

  /** Emphasis bubble sample beside a mock floating tab bar, plus the reader layout. */
  @Builder
  storeNavInfoRow(theme: ThemePack, customSchemeId: string = '') {
    Column({ space: AppSpacing.SM }) {
      Row({ space: AppSpacing.LG }) {
        Text() {
          ContainerSpan() {
            ImageSpan(ThemeAssetRegistry.regexBubbleCap(this.activeVariant(theme).regexEmphasis.bubbleStyle))
              .width(15)
              .height(15)
              .objectFit(ImageFit.Contain)
              .verticalAlign(ImageSpanAlignment.CENTER)
            Span('强调气泡')
              .fontSize(AppFontSize.BODY)
              .fontColor(this.themeRegexPreview(theme).textColor)
              .textShadow(this.themeRegexPreviewShadow(theme))
            ImageSpan(ThemeAssetRegistry.regexBubbleCap(this.activeVariant(theme).regexEmphasis.bubbleStyle))
              .width(15)
              .height(15)
              .objectFit(ImageFit.Contain)
              .verticalAlign(ImageSpanAlignment.CENTER)
              .rotate({ angle: 180 })
          }
          .textBackgroundStyle(this.themeRegexPreviewBackground(theme))
        }
        .maxLines(1)

        Text() {
          this.commentBubbleSpan(theme, '段评', AppFontSize.CAPTION, this.appDarkMode)
        }
        .maxLines(1)

        Row() {
          ForEach(['bookshelf', 'explore', 'search', 'mine'], (tabId: string) => {
            Image(ThemeAssetRegistry.navigationIcon(theme.navigation.iconPackId, tabId))
              .width(24)
              .height(24)
              .fillColor(this.activeVariant(theme).colors.accentColor)
              .draggable(false)
          }, (tabId: string) => `store_${theme.id}_${tabId}`)
        }
        .layoutWeight(1)
        .height(42)
        .justifyContent(FlexAlign.SpaceAround)
        .alignItems(VerticalAlign.Center)
        .borderRadius(21)
        .backgroundColor(this.activeVariant(theme).colors.inputColor)
        .border({ width: 1, color: this.activeVariant(theme).colors.dividerColor })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      Text(this.themeLayoutSummary(theme, customSchemeId))
        .fontSize(AppFontSize.MICRO)
        .fontColor(this.activeVariant(theme).colors.subTextColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  storeThemeActions(theme: ThemePack, customSchemeId: string = '') {
    if (theme.id === ThemeIds.CUSTOM) {
      Row({ space: AppSpacing.MD }) {
        Button('编辑主题', { type: ButtonType.Normal })
          .borderRadius(this.storeButtonRadius(theme))
          .height(40)
          .fontSize(AppFontSize.BODY)
          .fontColor(this.activeVariant(theme).colors.accentColor)
          .backgroundColor(this.activeVariant(theme).colors.inputColor)
          .layoutWeight(1)
          .onClick(() => {
            // The pager holds a snapshot of the scheme; close it so the edit is
            // not shown stale on return.
            this.closeThemeStore();
            router.pushUrl({
              url: 'pages/ThemeColorSettings',
              params: { schemeId: customSchemeId }
            });
          })
        Button(this.isSelected(theme, customSchemeId) ? '正在使用' : '应用主题', { type: ButtonType.Normal })
          .borderRadius(this.storeButtonRadius(theme))
          .height(40)
          .fontSize(AppFontSize.BODY)
          .fontColor(ThemeRuntime.onAccentColor(this.activeVariant(theme).colors.buttonColor))
          .backgroundColor(this.activeVariant(theme).colors.buttonColor)
          .layoutWeight(1)
          .enabled(!this.isSelected(theme, customSchemeId))
          .onClick(() => {
            this.selectTheme(theme.id, customSchemeId);
          })
      }
      .width('100%')
    } else if (this.isSelected(theme)) {
      Row() {
        Text(this.isTrialTheme(theme.id) ? '试用中 · 5分钟后自动恢复' : '正在使用该主题')
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.activeVariant(theme).colors.accentColor)
      }
      .width('100%')
      .height(40)
      .justifyContent(FlexAlign.Center)
      .borderRadius(this.storeButtonRadius(theme))
      .backgroundColor(this.activeVariant(theme).colors.inputColor)
    } else if (BuiltinThemeRegistry.isFree(theme.id) || AccountSessionStore.hasValidEntitlement(theme.id)) {
      Button('应用主题', { type: ButtonType.Normal })
        .borderRadius(this.storeButtonRadius(theme))
        .width('100%')
        .height(40)
        .fontSize(AppFontSize.BODY)
        .fontColor(ThemeRuntime.onAccentColor(this.activeVariant(theme).colors.buttonColor))
        .backgroundColor(this.activeVariant(theme).colors.buttonColor)
        .onClick(() => {
          this.selectTheme(theme.id);
        })
    } else {
      Row({ space: AppSpacing.MD }) {
        if (theme.id !== ThemeIds.OBSIDIAN_ARCHIVE) {
          this.storeTrialButton(theme)
        }
        this.storeAcquireButton(theme)
      }
      .width('100%')
    }
  }

  @Builder
  storeTrialButton(theme: ThemePack) {
    Button(this.isTrialTheme(theme.id) ? '结束试用' : '试用5分钟', { type: ButtonType.Normal })
      .borderRadius(this.storeButtonRadius(theme))
      .height(40)
      .fontSize(AppFontSize.BODY)
      .fontColor(this.activeVariant(theme).colors.accentColor)
      .backgroundColor(this.activeVariant(theme).colors.inputColor)
      .layoutWeight(1)
      .onClick(() => {
        if (this.isTrialTheme(theme.id)) {
          this.stopThemeTrial();
        } else {
          this.startThemeTrial(theme);
        }
      })
  }

  @Builder
  storeAcquireButton(theme: ThemePack) {
    Button(this.acquireButtonLabel(theme.id, '获取'), { type: ButtonType.Normal })
      .borderRadius(this.storeButtonRadius(theme))
      .height(40)
      .fontSize(AppFontSize.BODY)
      .fontColor(ThemeRuntime.onAccentColor(this.activeVariant(theme).colors.buttonColor))
      .backgroundColor(this.activeVariant(theme).colors.buttonColor)
      .layoutWeight(1)
      .enabled(this.acquireButtonEnabled(theme.id))
      .onClick(() => this.onAcquireButtonTap(theme.id))
  }

  @Builder
  storeThemeStatusPill(theme: ThemePack, customSchemeId: string = '') {
    if (this.applyingThemeId === (customSchemeId || theme.id) && !this.isSelected(theme, customSchemeId) &&
      !this.isTrialTheme(theme.id)) {
      Text('应用中')
        .fontSize(AppFontSize.MICRO)
        .fontColor(this.activeVariant(theme).colors.accentColor)
    } else if (this.isTrialTheme(theme.id) || this.isSelected(theme, customSchemeId)) {
      Text(this.isTrialTheme(theme.id) ? '试用中' : '使用中')
        .fontSize(AppFontSize.MICRO)
        .fontColor(ThemeRuntime.onAccentColor(this.activeVariant(theme).colors.accentColor))
        .padding({ left: AppSpacing.SM, right: AppSpacing.SM, top: AppSpacing.XXS, bottom: AppSpacing.XXS })
        .borderRadius(10)
        .backgroundColor(this.activeVariant(theme).colors.accentColor)
    } else if (theme.id === ThemeIds.CUSTOM) {
      Text(this.isCustomSchemePending(theme, customSchemeId) ? '待应用' : '自定义')
        .fontSize(AppFontSize.MICRO)
        .fontColor(this.activeVariant(theme).colors.accentColor)
        .padding({ left: AppSpacing.SM, right: AppSpacing.SM, top: AppSpacing.XXS, bottom: AppSpacing.XXS })
        .borderRadius(10)
        .backgroundColor(this.activeVariant(theme).colors.inputColor)
    } else if (BuiltinThemeRegistry.isFree(theme.id) || AccountSessionStore.hasValidEntitlement(theme.id)) {
      Text(BuiltinThemeRegistry.isFree(theme.id) ? '免费' : '已购')
        .fontSize(AppFontSize.MICRO)
        .fontColor(this.activeVariant(theme).colors.accentColor)
        .padding({ left: AppSpacing.SM, right: AppSpacing.SM, top: AppSpacing.XXS, bottom: AppSpacing.XXS })
        .borderRadius(10)
        .backgroundColor(this.activeVariant(theme).colors.inputColor)
    } else {
      Text(this.storeThemePriceLabel(theme.id))
        .fontSize(AppFontSize.MICRO)
        .fontColor(this.activeVariant(theme).colors.subTextColor)
        .padding({ left: AppSpacing.SM, right: AppSpacing.SM, top: AppSpacing.XXS, bottom: AppSpacing.XXS })
        .borderRadius(10)
        .backgroundColor(this.activeVariant(theme).colors.inputColor)
    }
  }

  @Builder
  myThemesSectionTitle() {
    Row({ space: AppSpacing.MD }) {
      Text('默认与自定义')
        .fontSize(AppFontSize.BODY)
        .fontColor(this.subTextColor())
        .layoutWeight(1)
      Text(`方案 ${this.customSchemes.length}/${this.customSchemeLimit}`)
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor())
      Row({ space: AppSpacing.XXS }) {
        SymbolGlyph($r('sys.symbol.square_and_arrow_down'))
          .fontSize(14)
          .fontColor([this.accentColor()])
        Text(this.preparingThemeImport ? '读取中' : '导入')
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.accentColor())
      }
      .padding({ left: AppSpacing.SM, right: AppSpacing.SM, top: AppSpacing.XXS, bottom: AppSpacing.XXS })
      .borderRadius(12)
      .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
      .accessibilityText('导入主题包')
      .onClick(() => this.requestThemeImport(''))
    }
    .width('100%')
    .padding({ left: AppSpacing.XXS, right: AppSpacing.XXS, top: AppSpacing.SM, bottom: 0 })
    .alignItems(VerticalAlign.Center)
  }

  /** Horizontal strip of the default theme and custom schemes, plus the "new scheme" tile. */
  @Builder
  myThemesRow() {
    Scroll() {
      Row({ space: AppSpacing.MD }) {
        ForEach(this.myThemeEntries(), (entry: ThemeListEntry, index: number) => {
          this.myThemeThumb(entry.theme, entry.customSchemeId, index)
        }, (entry: ThemeListEntry) => `mine_${this.themeEntryKey(entry)}`)
        this.addSchemeTile()
      }
      .alignItems(VerticalAlign.Top)
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .width('100%')
    .align(Alignment.TopStart)
  }

  @Builder
  myThemeThumb(theme: ThemePack, customSchemeId: string, index: number) {
    Column({ space: AppSpacing.SM }) {
      Stack() {
        ThemeStartupCover({
          themeId: theme.startup.styleId,
          darkMode: this.appDarkMode,
          compact: true,
          animated: false,
          customImagePath: this.customPreviewStartupImage(customSchemeId),
          titleOverride: this.customPreviewStartupTitle(customSchemeId),
          subtitleOverride: this.customPreviewStartupSubtitle(customSchemeId),
          explicitText: !!customSchemeId
        })
      }
      .width('100%')
      .height(MY_THEME_THUMB_COVER_HEIGHT)
      .borderRadius(theme.radius.medium)
      .clip(true)

      Text(theme.name)
        .fontSize(AppFontSize.CAPTION)
        .fontWeight(FontWeight.Medium)
        .fontFamily(theme.typography.appFontFamily)
        .fontColor(this.activeVariant(theme).colors.primaryTextColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Text(this.myThemeThumbStatus(theme, customSchemeId))
        .fontSize(AppFontSize.MICRO)
        .fontColor(this.isSelected(theme, customSchemeId) || this.isCustomSchemePending(theme, customSchemeId) ?
          this.activeVariant(theme).colors.accentColor : this.activeVariant(theme).colors.subTextColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .width(MY_THEME_THUMB_WIDTH)
    .padding(AppSpacing.SM)
    .alignItems(HorizontalAlign.Start)
    .borderRadius(theme.radius.card)
    .backgroundColor(this.activeVariant(theme).colors.cardColor)
    .border({
      width: this.isSelected(theme, customSchemeId) ? 2 : 1,
      color: this.isSelected(theme, customSchemeId) ? this.activeVariant(theme).colors.accentColor :
        this.activeVariant(theme).colors.dividerColor
    })
    .accessibilityText(`查看「${theme.name}」主题详情`)
    .gesture(
      LongPressGesture({ repeat: false })
        .onAction((event: GestureEvent) => {
          if (customSchemeId) {
            this.openCustomThemeActions(customSchemeId, event);
          }
        })
    )
    .onClick(() => this.openThemePager(this.myThemeEntries(), index))
  }

  @Builder
  addSchemeTile() {
    // Mirrors myThemeThumb's structure (cover box + two text lines) so both end up the same height.
    Column({ space: AppSpacing.SM }) {
      Stack() {
        SymbolGlyph($r('sys.symbol.plus'))
          .fontSize(24)
          .fontColor([this.canAddCustomScheme() ? this.accentColor() : this.subTextColor()])
      }
      .width('100%')
      .height(MY_THEME_THUMB_COVER_HEIGHT)
      .borderRadius(ThemeRuntime.mediumRadius())
      .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))

      Text('新建方案')
        .fontSize(AppFontSize.CAPTION)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.canAddCustomScheme() ? this.primaryTextColor() : this.subTextColor())
        .maxLines(1)
        .width('100%')
      Text(this.canAddCustomScheme() ?
        `还可添加 ${this.customSchemeLimit - this.customSchemes.length} 套` :
        (this.addingCustomScheme ? '正在添加' : '已达上限'))
        .fontSize(AppFontSize.MICRO)
        .fontColor(this.subTextColor())
        .maxLines(1)
        .width('100%')
    }
    .width(MY_THEME_THUMB_WIDTH)
    .padding(AppSpacing.SM)
    .alignItems(HorizontalAlign.Start)
    .borderRadius(ThemeRuntime.cardRadius())
    .backgroundColor(this.cardColor())
    .border({ width: 1, color: ThemeRuntime.dividerColor(this.appDarkMode) })
    .accessibilityText('新建自定义主题方案')
    .onClick(() => {
      this.addCustomScheme();
    })
  }

  canAddCustomScheme(): boolean {
    return !this.addingCustomScheme && this.customSchemes.length < this.customSchemeLimit;
  }

  myThemeThumbStatus(theme: ThemePack, customSchemeId: string): string {
    if (this.isSelected(theme, customSchemeId)) return '使用中';
    if (this.isCustomSchemePending(theme, customSchemeId)) return '有改动 · 待应用';
    if (theme.id === ThemeIds.CUSTOM) return '自定义';
    return this.themeAccessLabel(theme.id);
  }

  /**
   * The theme running right now: the trial theme while a trial is active,
   * otherwise the applied builtin theme or custom scheme. Empty until the
   * active custom scheme has loaded.
   */
  currentThemeEntries(): ThemeListEntry[] {
    if (this.appThemeId === ThemeIds.CUSTOM) {
      const scheme = CustomThemeSchemeStore.find(this.customSchemes, this.activeCustomSchemeId);
      return scheme ? [new ThemeListEntry(this.customTheme(scheme), scheme.id)] : [];
    }
    return [new ThemeListEntry(BuiltinThemeRegistry.findById(this.appThemeId))];
  }

  myThemeEntries(): ThemeListEntry[] {
    const entries: ThemeListEntry[] = [
      new ThemeListEntry(BuiltinThemeRegistry.findById(ThemeIds.PLAIN_DEFAULT))
    ];
    for (const scheme of this.customSchemes) {
      entries.push(new ThemeListEntry(this.customTheme(scheme), scheme.id));
    }
    return entries;
  }

  themeEntryKey(entry: ThemeListEntry): string {
    const scheme = CustomThemeSchemeStore.find(this.customSchemes, entry.customSchemeId);
    return `${entry.theme.id}_${entry.customSchemeId}_${scheme ? scheme.revision : 0}_` +
      `${this.appDarkMode ? 'dark' : 'light'}_${this.accountEntitlementsRevision}`;
  }

  async addCustomScheme(): Promise<void> {
    if (this.addingCustomScheme) return;
    this.addingCustomScheme = true;
    try {
      const settings = await AppThemeSettingsStore.load(getContext(this));
      const added = await CustomThemeSchemeStore.add(getContext(this), settings);
      if (!added) {
        this.refreshCustomSchemeLimit();
        HdsFeedback.showToast(`当前权益最多可创建 ${this.customSchemeLimit} 套自定义主题，已有方案保留`);
        return;
      }
      await this.refreshCustomSchemes();
      HdsFeedback.showToast(`已添加「${added.name}」`);
    } catch (e) {
      console.error('添加自定义主题方案失败:', e);
      HdsFeedback.showToast('添加方案失败，请稍后重试');
    } finally {
      this.addingCustomScheme = false;
    }
  }

  @Builder
  customThemeActionMenu() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.appDarkMode ? '#52000000' : '#26FFFFFF')
        .backdropBlur(ThemeRuntime.glassBlur('popover', 18))
        .onClick(() => this.closeCustomThemeActions())
      Column() {
        this.contextActionItem($r('sys.symbol.paintpalette'), '编辑', this.primaryTextColor(), () => {
          const schemeId = this.actionCustomSchemeId;
          this.closeCustomThemeActions();
          router.pushUrl({
            url: 'pages/ThemeColorSettings',
            params: { schemeId: schemeId }
          });
        })
        this.contextActionItem($r('sys.symbol.textformat'), '设置排版', this.primaryTextColor(), () => {
          const schemeId = this.actionCustomSchemeId;
          this.closeCustomThemeActions();
          router.pushUrl({
            url: 'pages/ThemeTypographySettings',
            params: { schemeId: schemeId }
          });
        })
        this.contextActionItem($r('sys.symbol.square_and_pencil'), '重命名', this.primaryTextColor(), () => {
          const scheme = this.actionCustomScheme();
          if (!scheme) return;
          this.renameCustomThemeName = scheme.name;
          this.showCustomThemeActionMenu = false;
          this.showRenameCustomThemeDialog = true;
        })
        this.contextActionItem($r('sys.symbol.share'), '分享主题包', this.primaryTextColor(), () => {
          const schemeId = this.actionCustomSchemeId;
          this.closeCustomThemeActions();
          this.requestThemeExport(schemeId);
        })
        this.contextActionItem($r('sys.symbol.trash'), '删除', ThemeRuntime.dangerColor(this.appDarkMode), () => {
          this.showCustomThemeActionMenu = false;
          this.requestDeleteCustomTheme(this.actionCustomSchemeId);
        })
      }
      .width(148)
      .padding({ top: AppSpacing.SM, bottom: AppSpacing.SM })
      .backgroundColor(ThemeRuntime.glassPanelColor(this.appDarkMode, '', 'panel'))
      .borderRadius(ThemeRuntime.glassCornerRadius(14, 'panel'))
      .backdropBlur(ThemeRuntime.glassBlur('panel', 22))
      .border({
        width: ThemeRuntime.glassBorderWidth('panel'),
        color: ThemeRuntime.glassBorderColor(this.appDarkMode, 'panel')
      })
      .shadow({
        radius: ThemeRuntime.glassShadowRadius('panel'),
        color: ThemeRuntime.glassShadowColor(this.appDarkMode, 'panel'),
        offsetX: ThemeRuntime.glassShadowOffsetX('panel'),
        offsetY: ThemeRuntime.glassShadowOffsetY('panel')
      })
      .position({
        x: this.contextMenuLeft(148),
        y: this.contextMenuTop(246)
      })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  contextActionItem(icon: Resource, label: string, color: string, action: () => void) {
    Row({ space: AppSpacing.MD }) {
      SymbolGlyph(icon)
        .fontSize(18)
        .fontColor([color])
        .width(24)
      Text(label)
        .fontSize(AppFontSize.BODY_LARGE)
        .fontColor(color)
        .layoutWeight(1)
    }
    .width('100%')
    .height(46)
    .padding({ left: AppSpacing.LG, right: AppSpacing.LG })
    .alignItems(VerticalAlign.Center)
    .onClick(action)
  }

  @Builder
  renameCustomThemeDialog() {
    Column() {
      Column({ space: AppSpacing.XL }) {
        Text('重命名自定义主题')
          .fontSize(AppFontSize.SUBTITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())
        TextInput({ placeholder: '输入方案名称', text: this.renameCustomThemeName })
          .width('100%')
          .height(42)
          .fontColor(this.primaryTextColor())
          .placeholderColor(this.subTextColor())
          .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
          .borderRadius(ThemeRuntime.mediumRadius())
          .onChange((value: string) => {
            this.renameCustomThemeName = value;
          })
        Row({ space: AppSpacing.LG }) {
          Button('取消', { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(42)
            .borderRadius(ThemeRuntime.buttonRadius())
            .backgroundColor(this.cardColor())
            .fontColor(this.primaryTextColor())
            .onClick(() => this.closeRenameCustomThemeDialog())
          Button('保存', { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(42)
            .borderRadius(ThemeRuntime.buttonRadius())
            .backgroundColor(this.accentColor())
            .fontColor(ThemeRuntime.onAccentColor(this.accentColor()))
            .enabled(!!this.renameCustomThemeName.trim())
            .onClick(() => this.renameCustomTheme())
        }
        .width('100%')
      }
      .width('calc(100% - 48vp)')
      .constraintSize({ maxWidth: 360 })
      .padding(AppSpacing.XXL)
      .borderRadius(ThemeRuntime.glassCornerRadius(18, 'panel'))
      .backgroundColor(ThemeRuntime.glassPanelColor(this.appDarkMode, '', 'panel'))
      .backdropBlur(ThemeRuntime.glassBlur('panel', 22))
      .border({
        width: ThemeRuntime.glassBorderWidth('panel'),
        color: ThemeRuntime.glassBorderColor(this.appDarkMode, 'panel')
      })
      .shadow({
        radius: ThemeRuntime.glassShadowRadius('panel'),
        color: ThemeRuntime.glassShadowColor(this.appDarkMode, 'panel'),
        offsetX: ThemeRuntime.glassShadowOffsetX('panel'),
        offsetY: ThemeRuntime.glassShadowOffsetY('panel')
      })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(this.appDarkMode ? '#76000000' : '#52000000')
    .backdropBlur(ThemeRuntime.glassBlur('popover', 18))
  }

  @Builder
  deleteCustomThemeDialog() {
    Column() {
      Column({ space: AppSpacing.LG }) {
        Text('删除自定义主题')
          .fontSize(AppFontSize.SUBTITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())
        Text(`确定删除「${this.actionCustomScheme()?.name || '该方案'}」吗？此操作无法撤销。`)
          .fontSize(AppFontSize.BODY)
          .fontColor(this.subTextColor())
          .width('100%')
        Row({ space: AppSpacing.LG }) {
          Button('取消', { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(42)
            .borderRadius(ThemeRuntime.buttonRadius())
            .backgroundColor(this.cardColor())
            .fontColor(this.primaryTextColor())
            .onClick(() => this.closeDeleteCustomThemeDialog())
          Button('删除', { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(42)
            .borderRadius(ThemeRuntime.buttonRadius())
            .backgroundColor(ThemeRuntime.dangerColor(this.appDarkMode))
            .fontColor(ThemeRuntime.onAccentColor(ThemeRuntime.dangerColor(this.appDarkMode)))
            .onClick(() => this.confirmDeleteCustomTheme())
        }
        .width('100%')
      }
      .width('calc(100% - 48vp)')
      .constraintSize({ maxWidth: 360 })
      .padding(AppSpacing.XXL)
      .borderRadius(ThemeRuntime.glassCornerRadius(18, 'panel'))
      .backgroundColor(ThemeRuntime.glassPanelColor(this.appDarkMode, '', 'panel'))
      .backdropBlur(ThemeRuntime.glassBlur('panel', 22))
      .border({
        width: ThemeRuntime.glassBorderWidth('panel'),
        color: ThemeRuntime.glassBorderColor(this.appDarkMode, 'panel')
      })
      .shadow({
        radius: ThemeRuntime.glassShadowRadius('panel'),
        color: ThemeRuntime.glassShadowColor(this.appDarkMode, 'panel'),
        offsetX: ThemeRuntime.glassShadowOffsetX('panel'),
        offsetY: ThemeRuntime.glassShadowOffsetY('panel')
      })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(this.appDarkMode ? '#76000000' : '#52000000')
    .backdropBlur(ThemeRuntime.glassBlur('popover', 18))
  }

  @Builder
  startupTextDialog() {
    Column() {
      Column({ space: AppSpacing.LG }) {
        Text(`编辑「${BuiltinThemeRegistry.findById(this.startupTextThemeId).name}」启动文案`)
          .fontSize(AppFontSize.SUBTITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())
        Column({ space: AppSpacing.SM }) {
          Text('主标题')
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.subTextColor())
            .width('100%')
          TextInput({ placeholder: '可留空', text: this.startupTextTitle })
            .width('100%')
            .height(42)
            .maxLength(24)
            .fontColor(this.primaryTextColor())
            .placeholderColor(this.subTextColor())
            .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
            .borderRadius(ThemeRuntime.mediumRadius())
            .onChange((value: string) => {
              this.startupTextTitle = value;
            })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        Column({ space: AppSpacing.SM }) {
          Text('副标题')
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.subTextColor())
            .width('100%')
          TextInput({ placeholder: '可留空', text: this.startupTextSubtitle })
            .width('100%')
            .height(42)
            .maxLength(48)
            .fontColor(this.primaryTextColor())
            .placeholderColor(this.subTextColor())
            .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
            .borderRadius(ThemeRuntime.mediumRadius())
            .onChange((value: string) => {
              this.startupTextSubtitle = value;
            })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        Button('恢复默认文案', { type: ButtonType.Normal })
          .height(34)
          .borderRadius(ThemeRuntime.buttonRadius())
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.accentColor())
          .backgroundColor(ThemeRuntime.inputColor(this.appDarkMode))
          .onClick(() => {
            this.startupTextTitle = '开源轻页';
            this.startupTextSubtitle = StartupCoverTextStore.defaultSubtitle(this.startupTextThemeId);
          })
        Row({ space: AppSpacing.LG }) {
          Button('取消', { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(42)
            .borderRadius(ThemeRuntime.buttonRadius())
            .backgroundColor(this.cardColor())
            .fontColor(this.primaryTextColor())
            .onClick(() => this.closeStartupTextDialog())
          Button('保存', { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(42)
            .borderRadius(ThemeRuntime.buttonRadius())
            .backgroundColor(this.accentColor())
            .fontColor(ThemeRuntime.onAccentColor(this.accentColor()))
            .onClick(() => this.saveStartupText())
        }
        .width('100%')
      }
      .width('calc(100% - 48vp)')
      .constraintSize({ maxWidth: 360 })
      .padding(AppSpacing.XXL)
      .borderRadius(ThemeRuntime.glassCornerRadius(18, 'panel'))
      .backgroundColor(ThemeRuntime.glassPanelColor(this.appDarkMode, '', 'panel'))
      .backdropBlur(ThemeRuntime.glassBlur('panel', 22))
      .border({
        width: ThemeRuntime.glassBorderWidth('panel'),
        color: ThemeRuntime.glassBorderColor(this.appDarkMode, 'panel')
      })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(this.appDarkMode ? '#76000000' : '#52000000')
    .backdropBlur(ThemeRuntime.glassBlur('popover', 18))
  }

  @Builder
  themeApplyDialog() {
    Column() {
      Column({ space: AppSpacing.LG }) {
        Text(`应用「${this.applyDialogThemeName}」`)
          .fontSize(AppFontSize.SUBTITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())
        Text('选择要随主题一起应用的内容，关闭的选项会保留当前设置。')
          .fontSize(AppFontSize.BODY)
          .fontColor(this.subTextColor())
          .width('100%')
        this.themeApplyToggleRow('layout')
        if (this.applyDialogHasCover) {
          this.themeApplyToggleRow('cover')
        }
        this.themeApplyToggleRow('icon')
        Row({ space: AppSpacing.LG }) {
          Button('取消', { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(42)
            .borderRadius(ThemeRuntime.buttonRadius())
            .backgroundColor(this.cardColor())
            .fontColor(this.primaryTextColor())
            .onClick(() => this.cancelThemeApply())
          Button('应用', { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(42)
            .borderRadius(ThemeRuntime.buttonRadius())
            .backgroundColor(this.accentColor())
            .fontColor(ThemeRuntime.onAccentColor(this.accentColor()))
            .onClick(() => this.confirmThemeApply())
        }
        .width('100%')
      }
      .width('calc(100% - 48vp)')
      .constraintSize({ maxWidth: 360 })
      .padding(AppSpacing.XXL)
      .borderRadius(ThemeRuntime.glassCornerRadius(18, 'panel'))
      .backgroundColor(ThemeRuntime.glassPanelColor(this.appDarkMode, '', 'panel'))
      .backdropBlur(ThemeRuntime.glassBlur('panel', 22))
      .border({
        width: ThemeRuntime.glassBorderWidth('panel'),
        color: ThemeRuntime.glassBorderColor(this.appDarkMode, 'panel')
      })
      .shadow({
        radius: ThemeRuntime.glassShadowRadius('panel'),
        color: ThemeRuntime.glassShadowColor(this.appDarkMode, 'panel'),
        offsetX: ThemeRuntime.glassShadowOffsetX('panel'),
        offsetY: ThemeRuntime.glassShadowOffsetY('panel')
      })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(this.appDarkMode ? '#76000000' : '#52000000')
    .backdropBlur(ThemeRuntime.glassBlur('popover', 18))
  }

  @Builder
  themeApplyToggleRow(category: string) {
    Row({ space: AppSpacing.LG }) {
      Column({ space: AppSpacing.XXS }) {
        Text(category === 'layout' ? '应用主题排版' : category === 'cover' ? '应用主题封面' : '应用主题图标')
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.primaryTextColor())
        Text(category === 'layout' ? (this.applyDialogApplyLayout ? this.applyDialogLayoutOnHint :
          this.applyDialogLayoutOffHint) : category === 'cover' ?
          '书架使用主题封面与配套书籍边框' : AppIconManager.isSupported() ?
          '桌面图标同步更换为主题图标' : AppIconManager.UNSUPPORTED_MESSAGE)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      AdaptiveSwitch({
        isOn: category === 'layout' ? this.applyDialogApplyLayout :
          category === 'cover' ? this.applyDialogApplyCover : this.applyDialogApplyIcon,
        onChange: (enabled: boolean) => {
          if (category === 'layout') {
            this.applyDialogApplyLayout = enabled;
          } else if (category === 'cover') {
            this.applyDialogApplyCover = enabled;
          } else {
            this.applyDialogApplyIcon = enabled;
          }
        }
      })
    }
    .width('100%')
    .padding({ top: AppSpacing.XXS, bottom: AppSpacing.XXS })
    .alignItems(VerticalAlign.Center)
  }

  openStartupTextDialog(themeId: string): void {
    if (themeId === ThemeIds.PLAIN_DEFAULT || themeId === ThemeIds.CUSTOM) return;
    this.startupTextThemeId = themeId;
    this.startupTextTitle = StartupCoverTextStore.title(themeId, '开源轻页');
    this.startupTextSubtitle = StartupCoverTextStore.subtitle(
      themeId, StartupCoverTextStore.defaultSubtitle(themeId));
    this.showStartupTextDialog = true;
  }

  closeStartupTextDialog(): void {
    this.showStartupTextDialog = false;
    this.startupTextThemeId = '';
    this.startupTextTitle = '';
    this.startupTextSubtitle = '';
  }

  async saveStartupText(): Promise<void> {
    if (!this.startupTextThemeId) return;
    try {
      await StartupCoverTextStore.update(getContext(this), this.startupTextThemeId,
        this.startupTextTitle, this.startupTextSubtitle);
      this.closeStartupTextDialog();
      HdsFeedback.showToast('启动文案已更新');
    } catch (e) {
      console.error('保存启动文案失败:', e);
      HdsFeedback.showToast('保存启动文案失败，请重试');
    }
  }

  openCustomThemeActions(schemeId: string, event?: GestureEvent): void {
    const finger = event && event.fingerList.length > 0 ? event.fingerList[0] : undefined;
    if (finger) {
      this.contextMenuX = finger.globalX;
      this.contextMenuY = finger.globalY;
    }
    this.actionCustomSchemeId = schemeId;
    this.showCustomThemeActionMenu = true;
  }

  closeCustomThemeActions(): void {
    this.showCustomThemeActionMenu = false;
    this.actionCustomSchemeId = '';
  }

  actionCustomScheme(): CustomThemeScheme | null {
    return CustomThemeSchemeStore.find(this.customSchemes, this.actionCustomSchemeId);
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
    if (below + menuHeight <= this.contextViewportHeight - 12) return below;
    return Math.max(this.statusBarHeight + 8, this.contextMenuY - menuHeight - 12);
  }

  closeRenameCustomThemeDialog(): void {
    this.showRenameCustomThemeDialog = false;
    this.renameCustomThemeName = '';
    this.actionCustomSchemeId = '';
  }

  async renameCustomTheme(): Promise<void> {
    const scheme = this.actionCustomScheme();
    const name = this.renameCustomThemeName.trim();
    if (!scheme || !name) return;
    try {
      const settings = await AppThemeSettingsStore.load(getContext(this));
      const renamed = await CustomThemeSchemeStore.rename(getContext(this), settings, scheme.id, name);
      if (!renamed) {
        HdsFeedback.showToast('名称为空、重复或方案不存在');
        return;
      }
      this.closeRenameCustomThemeDialog();
      await this.refreshCustomSchemes();
      HdsFeedback.showToast('自定义主题已重命名');
    } catch (e) {
      console.error('重命名自定义主题失败:', e);
      HdsFeedback.showToast('重命名失败，请稍后重试');
    }
  }

  requestDeleteCustomTheme(schemeId: string): void {
    if (this.customSchemes.length <= 1) {
      this.closeCustomThemeActions();
      HdsFeedback.showToast('至少需要保留一套自定义主题');
      return;
    }
    this.actionCustomSchemeId = schemeId;
    this.showDeleteCustomThemeDialog = true;
  }

  closeDeleteCustomThemeDialog(): void {
    this.showDeleteCustomThemeDialog = false;
    this.actionCustomSchemeId = '';
  }

  async confirmDeleteCustomTheme(): Promise<void> {
    const schemeId = this.actionCustomSchemeId;
    this.showDeleteCustomThemeDialog = false;
    await this.deleteCustomThemeScheme(schemeId);
  }

  async deleteCustomThemeScheme(schemeId: string): Promise<void> {
    const scheme = CustomThemeSchemeStore.find(this.customSchemes, schemeId);
    if (!scheme) return;
    if (this.customSchemes.length <= 1) {
      HdsFeedback.showToast('至少需要保留一套自定义主题');
      return;
    }
    try {
      if (this.appThemeId === ThemeIds.CUSTOM && this.activeCustomSchemeId === schemeId) {
        await this.selectTheme(ThemeIds.PLAIN_DEFAULT, '', false);
        if (this.appThemeId === ThemeIds.CUSTOM) {
          return;
        }
      }
      const settings = await AppThemeSettingsStore.load(getContext(this));
      const deleted = await CustomThemeSchemeStore.delete(getContext(this), settings, schemeId);
      if (!deleted) {
        HdsFeedback.showToast('删除失败，至少需要保留一套方案');
        return;
      }
      this.actionCustomSchemeId = '';
      await this.refreshCustomSchemes();
      await ThemePackageService.cleanupImportedFiles(getContext(this));
      HdsFeedback.showToast(`已删除「${scheme.name}」`);
    } catch (e) {
      console.error('删除自定义主题失败:', e);
      HdsFeedback.showToast('删除失败，请稍后重试');
    }
  }

  @Builder
  themeBookCoverSetting(theme: ThemePack) {
    Row({ space: AppSpacing.LG }) {
      Stack() {
        Swiper() {
          ForEach(this.themeCoverSet(theme), (cover: ResourceStr, index: number) => {
            Image(cover)
              .width(42)
              .height(58)
              .objectFit(ImageFit.Fill)
              .draggable(false)
          }, (_cover: ResourceStr, index: number) => `active_cover_${index}`)
        }
        .width(42)
        .height(58)
        .autoPlay(this.themeCoverSet(theme).length > 1)
        .interval(2800)
        .indicator(false)
        .loop(true)
        Image(ThemeAssetRegistry.themeShelfFrame(theme.book.shelfFrameAssetId))
          .width(42)
          .height(58)
          .objectFit(ImageFit.Fill)
          .draggable(false)
      }
      .width(42)
      .height(58)

      Column({ space: AppSpacing.XS }) {
        Text('主题书籍封面')
          .fontSize(AppFontSize.BODY_LARGE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.activeVariant(theme).colors.primaryTextColor)
        Text(this.themeBookCoverEnabled ? '书架已使用主题封面和配套边框' : '保留每本书原有封面')
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.activeVariant(theme).colors.subTextColor)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      AdaptiveSwitch({
        isOn: this.themeBookCoverEnabled,
        switchEnabled: !this.isTrialTheme(theme.id),
        onChange: (enabled: boolean) => {
          this.setThemeBookCoverEnabled(enabled);
        }
      })
    }
    .width('100%')
    .padding(AppSpacing.LG)
    .alignItems(VerticalAlign.Center)
    .borderRadius(theme.radius.medium)
    .backgroundColor(this.activeVariant(theme).colors.inputColor)
  }

  @Builder
  themeCard(theme: ThemePack, customSchemeId: string = '') {
    Column({ space: AppSpacing.LG }) {
      Row({ space: AppSpacing.MD }) {
        Image(AppIconManager.optionById(this.appIconId).preview)
          .width(52)
          .height(52)
          .borderRadius(13)
          .objectFit(ImageFit.Cover)
          .draggable(false)
          .accessibilityText('当前桌面图标')

        Column({ space: AppSpacing.XXS }) {
          Text(theme.name)
            .fontSize(AppFontSize.SUBTITLE)
            .fontWeight(FontWeight.Bold)
            .fontFamily(theme.typography.appFontFamily)
            .fontColor(this.activeVariant(theme).colors.primaryTextColor)
          Text(theme.description)
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.activeVariant(theme).colors.subTextColor)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        if (this.isTrialTheme(theme.id)) {
          Text('试用中')
            .fontSize(AppFontSize.CAPTION)
            .fontColor(ThemeRuntime.onAccentColor(this.activeVariant(theme).colors.accentColor))
            .padding({ left: AppSpacing.MD, right: AppSpacing.MD, top: AppSpacing.XS, bottom: AppSpacing.XS })
            .borderRadius(12)
            .backgroundColor(this.activeVariant(theme).colors.accentColor)
        } else if (this.isSelected(theme, customSchemeId)) {
          Text('已启用')
            .fontSize(AppFontSize.CAPTION)
            .fontColor(ThemeRuntime.onAccentColor(this.activeVariant(theme).colors.accentColor))
            .padding({ left: AppSpacing.MD, right: AppSpacing.MD, top: AppSpacing.XS, bottom: AppSpacing.XS })
            .borderRadius(12)
            .backgroundColor(this.activeVariant(theme).colors.accentColor)
        } else if (this.applyingThemeId === (customSchemeId || theme.id)) {
          Text('应用中')
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.activeVariant(theme).colors.accentColor)
        } else if (this.isCustomSchemePending(theme, customSchemeId)) {
          Text('待应用')
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.activeVariant(theme).colors.accentColor)
            .padding({ left: AppSpacing.MD, right: AppSpacing.MD, top: AppSpacing.XS, bottom: AppSpacing.XS })
            .borderRadius(12)
            .backgroundColor(this.activeVariant(theme).colors.inputColor)
        } else if (theme.id !== ThemeIds.CUSTOM) {
          Text(this.themeAccessLabel(theme.id))
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.hasThemeAccess(theme.id) ?
              this.activeVariant(theme).colors.accentColor : this.activeVariant(theme).colors.subTextColor)
            .padding({ left: AppSpacing.MD, right: AppSpacing.MD, top: AppSpacing.XS, bottom: AppSpacing.XS })
            .borderRadius(11)
            .backgroundColor(this.activeVariant(theme).colors.inputColor)
        }
      }
      .width('100%')

      this.themeVisualPreview(theme, customSchemeId)
      if (this.isSelected(theme, customSchemeId) && this.themeHasBookCover(theme)) {
        this.themeBookCoverSetting(theme)
      }
      if (theme.id === ThemeIds.CUSTOM) {
        Row() {
          Text('浅色 / 深色可分别组合全部主题部件')
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.activeVariant(theme).colors.subTextColor)
            .layoutWeight(1)
          Button('编辑主题')
            .height(32)
            .fontSize(AppFontSize.CAPTION)
            .fontColor(ThemeRuntime.onAccentColor(this.activeVariant(theme).colors.buttonColor))
            .backgroundColor(this.activeVariant(theme).colors.buttonColor)
            .onClick(() => {
              router.pushUrl({
                url: 'pages/ThemeColorSettings',
                params: { schemeId: customSchemeId }
              });
            })
        }
        .width('100%')
      }
      if ((this.focusedThemeId === theme.id || this.isTrialTheme(theme.id)) &&
        this.isThemeTrialCandidate(theme.id)) {
        Row({ space: AppSpacing.MD }) {
          Button(this.isTrialTheme(theme.id) ? '结束试用' : '试用5分钟')
            .height(34)
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.activeVariant(theme).colors.accentColor)
            .backgroundColor(this.activeVariant(theme).colors.inputColor)
            .layoutWeight(1)
            .onClick(() => {
              if (this.isTrialTheme(theme.id)) {
                this.stopThemeTrial();
              } else {
                this.startThemeTrial(theme);
              }
            })
          Button(this.acquireButtonLabel(theme.id, '获取主题'))
            .height(34)
            .fontSize(AppFontSize.CAPTION)
            .fontColor(ThemeRuntime.onAccentColor(this.activeVariant(theme).colors.buttonColor))
            .backgroundColor(this.activeVariant(theme).colors.buttonColor)
            .layoutWeight(1)
            .enabled(this.acquireButtonEnabled(theme.id))
            .onClick(() => this.onAcquireButtonTap(theme.id))
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(AppSpacing.LG)
    .borderRadius(theme.radius.card)
    .backgroundColor(this.activeVariant(theme).colors.cardColor)
    .border({
      width: this.isThemeCardHighlighted(theme, customSchemeId) ? 2 : 1,
      color: this.isThemeCardHighlighted(theme, customSchemeId) ? this.activeVariant(theme).colors.accentColor :
        this.activeVariant(theme).colors.dividerColor
    })
    .gesture(
      LongPressGesture({ repeat: false })
        .onAction((event: GestureEvent) => {
          if (customSchemeId) {
            this.openCustomThemeActions(customSchemeId, event);
          }
        })
    )
    .onClick(() => {
      this.handleThemeCardClick(theme, customSchemeId);
    })
  }

  hasThemeAccess(themeId: string): boolean {
    if (themeId === ThemeIds.OBSIDIAN_ARCHIVE) return AccountSessionStore.hasOwnedEntitlement(themeId);
    return BuiltinThemeRegistry.isFree(themeId) ||
      (themeId === this.appThemeId && !this.isTrialTheme(themeId)) ||
      AccountSessionStore.hasValidEntitlement(themeId);
  }

  unavailableCustomStartupTheme(settings: AppThemeSettings): string {
    const usesExclusive = settings.customBaseThemeId === ThemeIds.OBSIDIAN_ARCHIVE ||
      (JSON.stringify(settings.customLightSources) || '').includes(ThemeIds.OBSIDIAN_ARCHIVE) ||
      (JSON.stringify(settings.customDarkSources) || '').includes(ThemeIds.OBSIDIAN_ARCHIVE);
    if (usesExclusive && !AccountSessionStore.hasOwnedEntitlement(ThemeIds.OBSIDIAN_ARCHIVE)) {
      return BuiltinThemeRegistry.findById(ThemeIds.OBSIDIAN_ARCHIVE).name;
    }
    const lightThemeId = settings.customLightSources.startupThemeId;
    if (!BuiltinThemeRegistry.isFree(lightThemeId) &&
      !AccountSessionStore.hasValidEntitlement(lightThemeId)) {
      return BuiltinThemeRegistry.findById(lightThemeId).name;
    }
    const darkThemeId = settings.customDarkSources.startupThemeId;
    if (!BuiltinThemeRegistry.isFree(darkThemeId) &&
      !AccountSessionStore.hasValidEntitlement(darkThemeId)) {
      return BuiltinThemeRegistry.findById(darkThemeId).name;
    }
    return '';
  }

  isTrialTheme(themeId: string): boolean {
    return this.trialThemeId === themeId && this.trialEndsAt > Date.now() &&
      ThemeTrialManager.isActive(themeId);
  }

  isThemeTrialCandidate(themeId: string): boolean {
    return themeId !== ThemeIds.CUSTOM && themeId !== ThemeIds.OBSIDIAN_ARCHIVE && !BuiltinThemeRegistry.isFree(themeId) &&
      !AccountSessionStore.hasValidEntitlement(themeId);
  }

  isThemeCardHighlighted(theme: ThemePack, customSchemeId: string = ''): boolean {
    return this.isSelected(theme, customSchemeId) || this.focusedThemeId === (customSchemeId || theme.id);
  }

  isCustomSchemePending(theme: ThemePack, customSchemeId: string): boolean {
    return theme.id === ThemeIds.CUSTOM && this.appThemeId === ThemeIds.CUSTOM &&
      this.activeCustomSchemeId === customSchemeId && !this.isSelected(theme, customSchemeId);
  }

  handleThemeCardClick(theme: ThemePack, customSchemeId: string = ''): void {
    if (this.isThemeTrialCandidate(theme.id)) {
      this.focusedThemeId = theme.id;
      return;
    }
    this.focusedThemeId = '';
    this.selectTheme(theme.id, customSchemeId);
  }

  async startThemeTrial(theme: ThemePack): Promise<void> {
    if (this.applyingThemeId) {
      return;
    }
    this.applyingThemeId = theme.id;
    try {
      await ThemeTrialManager.start(getContext(this) as common.UIAbilityContext, theme.id);
      this.appThemeId = theme.id;
      this.themeBookCoverEnabled = !!theme.book.coverAssetId;
      this.focusedThemeId = theme.id;
      this.syncBars();
      HdsFeedback.showToast(`「${theme.name}」已开始试用，5分钟后自动恢复`);
    } catch (e) {
      console.error('启动主题试用失败:', e);
      HdsFeedback.showToast('主题试用启动失败，请稍后重试');
    } finally {
      this.applyingThemeId = '';
    }
  }

  stopThemeTrial(): void {
    ThemeTrialManager.stop(getContext(this) as common.UIAbilityContext);
    this.appThemeId = AppStorage.get<string>('appThemeId') || AppThemeSettingsStore.DEFAULT_THEME_ID;
    this.themeBookCoverEnabled = AppStorage.get<boolean>('appThemeBookCoverEnabled') || false;
    this.syncBars();
  }

  async acquireTheme(themeId: string): Promise<void> {
    if (ThemeTrialManager.isActive()) {
      this.stopThemeTrial();
    }
    await this.selectTheme(themeId);
  }

  /** Only themes with a live (unexpired) purchase entitlement belong here. */
  purchasedThemes(): ThemePack[] {
    const themes: ThemePack[] = [];
    for (const theme of BuiltinThemeRegistry.all()) {
      if (AccountSessionStore.hasValidEntitlement(theme.id)) {
        themes.push(theme);
      }
    }
    return themes;
  }

  /** Opens the full-screen detail pager over the given themes, starting at index. */
  openThemePager(entries: ThemeListEntry[], index: number): void {
    if (entries.length === 0) {
      return;
    }
    this.focusedThemeId = '';
    this.pagerEntries = entries;
    this.storePageIndex = Math.max(0, Math.min(index, entries.length - 1));
    this.showThemeStore = true;
  }

  closeThemeStore(): void {
    this.showThemeStore = false;
    this.focusedThemeId = '';
  }

  /** Paid themes the user has no live entitlement for; the free default theme is never listed. */
  moreThemes(): ThemePack[] {
    const themes: ThemePack[] = [];
    for (const theme of BuiltinThemeRegistry.all()) {
      if (!BuiltinThemeRegistry.isFree(theme.id) && !AccountSessionStore.hasValidEntitlement(theme.id)) {
        themes.push(theme);
      }
    }
    return themes;
  }

  /** Themes chunked two per row for the grids on the main list. */
  themeRows(themes: ThemePack[]): ThemePack[][] {
    const rows: ThemePack[][] = [];
    for (let index = 0; index < themes.length; index += 2) {
      rows.push(themes.slice(index, index + 2));
    }
    return rows;
  }

  builtinEntries(themes: ThemePack[]): ThemeListEntry[] {
    const entries: ThemeListEntry[] = [];
    for (const theme of themes) {
      entries.push(new ThemeListEntry(theme));
    }
    return entries;
  }

  /** Panes take whatever the swipe page has left after its fixed detail rows. */
  storeCoverHeight(): number {
    const swiper = this.storeSwiperHeight > 0 ? this.storeSwiperHeight : 630;
    return Math.max(STORE_COVER_MIN_HEIGHT, swiper - STORE_PAGE_FIXED_HEIGHT);
  }

  previewRowWidth(inPager: boolean): number {
    const measured = inPager ? this.storeRowWidth : this.cardRowWidth;
    return measured > 0 ? measured : 320;
  }

  /**
   * Height shared by all preview panes. On the card it is exactly the book
   * cover's height when the cover fills one of three panes edge to edge; in
   * the detail pager the panes grow to fill the page. Themes without a book
   * cover use the same height so the pager does not jump between pages.
   */
  previewPaneHeight(inPager: boolean): number {
    if (inPager) return this.storeCoverHeight();
    const paneWidth = (this.previewRowWidth(inPager) - 2 * AppSpacing.MD) / 3;
    return Math.max(80, Math.min(STORE_COVER_MAX_HEIGHT, paneWidth / STORE_BOOK_COVER_RATIO));
  }

  previewPaneWidth(_theme: ThemePack, inPager: boolean): number {
    if (!inPager) return (this.previewRowWidth(inPager) - 2 * AppSpacing.MD) / 3;
    return Math.min(this.previewPaneHeight(inPager) * STORE_BOOK_COVER_RATIO,
      this.previewRowWidth(inPager) * STORE_PAGER_PANE_WIDTH_RATIO, STORE_PAGER_PANE_MAX_WIDTH);
  }

  previewStripInset(theme: ThemePack, inPager: boolean): number {
    return inPager ? Math.max(0, (this.previewRowWidth(inPager) - this.previewPaneWidth(theme, inPager)) / 2) : 0;
  }

  /** The cover keeps its own proportions inside a pane that may be taller than it. */
  storeBookCoverWidth(theme: ThemePack, inPager: boolean): number {
    return Math.min(this.previewPaneWidth(theme, inPager), this.previewPaneHeight(inPager) * STORE_BOOK_COVER_RATIO);
  }

  storeReaderPaneFontSize(inPager: boolean): number {
    return inPager ? 14 : 10;
  }

  storeReaderPaneLineHeight(inPager: boolean): number {
    return inPager ? 24 : STORE_READER_PANE_LINE_HEIGHT;
  }

  themeHasRegexBubbleCap(theme: ThemePack): boolean {
    return ThemeAssetRegistry.hasRegexBubbleCap(this.activeVariant(theme).regexEmphasis.bubbleStyle);
  }

  /** The player mock is drawn for the small card pane and doubled for the pager's large one. */
  storeTtsPaneScale(inPager: boolean): number {
    return inPager ? 2 : 1;
  }

  /** A custom scheme shows the panel background of the theme picked as its panel source. */
  previewTtsPanelThemeId(theme: ThemePack, customSchemeId: string): string {
    if (theme.id !== ThemeIds.CUSTOM) return theme.id;
    const scheme = CustomThemeSchemeStore.find(this.customSchemes, customSchemeId);
    if (!scheme) return ThemeRuntime.ttsPanelThemeId(this.appDarkMode);
    const sources = this.appDarkMode ? scheme.settings.customDarkSources : scheme.settings.customLightSources;
    return sources.ttsPanelThemeId || sources.readerThemeId;
  }

  withAlpha(color: string, alphaHex: string): string {
    return /^#[0-9A-Fa-f]{6}$/.test(color) ? `#${alphaHex}${color.substring(1)}` : color;
  }

  /** Whole body lines that fit the reader pane below its label, so no line is cut in half. */
  storeReaderPaneLines(inPager: boolean): number {
    return Math.max(3,
      Math.floor((this.previewPaneHeight(inPager) - 32 - AppSpacing.LG) / this.storeReaderPaneLineHeight(inPager)));
  }

  /** The theme's own button radius, floored so sharp-cornered themes still read as rounded. */
  storeButtonRadius(theme: ThemePack): number {
    return Math.max(8, theme.radius.button);
  }

  /** Price text for a paid theme; never a guessed price while the catalog is missing. */
  storeThemePriceLabel(themeId: string): string {
    if (themeId === ThemeIds.OBSIDIAN_ARCHIVE) return '终身超级会员专属';
    const offer = this.themeOffer(themeId);
    if (offer) return `${offer.pricePoints}点`;
    if (this.themeCatalogLoaded) return '暂未上架';
    return this.themeCatalogFailed ? '价格加载失败' : '价格加载中';
  }

  acquireButtonLabel(themeId: string, action: string): string {
    if (themeId === ThemeIds.OBSIDIAN_ARCHIVE) {
      return AccountSessionStore.hasOwnedEntitlement(themeId) ? '已领取 · 应用主题' :
        (AccountSessionStore.activeMembershipSku() === 'SUPER_LIFETIME' ? '领取一年' : '终身超级会员专属');
    }
    const offer = this.themeOffer(themeId);
    if (offer) return `${action} · ${offer.pricePoints}点`;
    if (this.themeCatalogLoaded) return '暂未上架';
    return this.themeCatalogFailed ? '重新加载价格' : '价格加载中…';
  }

  /** Greyed out until the price is known; after a failed load the button becomes the retry. */
  acquireButtonEnabled(themeId: string): boolean {
    if (themeId === ThemeIds.OBSIDIAN_ARCHIVE) return !this.applyingThemeId;
    return this.themeCatalogLoaded ? !!this.themeOffer(themeId) : this.themeCatalogFailed;
  }

  onAcquireButtonTap(themeId: string): void {
    if (themeId === ThemeIds.OBSIDIAN_ARCHIVE || this.themeCatalogLoaded) {
      this.acquireTheme(themeId);
    } else {
      this.refreshThemeCatalog();
    }
  }

  storeThemeCaption(theme: ThemePack): string {
    if (theme.id === ThemeIds.OBSIDIAN_ARCHIVE) {
      const owned = AccountSessionStore.entitlement(theme.id);
      return AccountSessionStore.hasOwnedEntitlement(theme.id) && owned ?
        `已领取 · 有效至 ${this.formatDate(owned.expiresAt)}` : '终身超级会员手动领取 · 每次一年 · 不售卖';
    }
    if (theme.id === ThemeIds.CUSTOM) {
      return '自定义方案';
    }
    if (BuiltinThemeRegistry.isFree(theme.id)) {
      return '免费使用';
    }
    const entitlement = AccountSessionStore.entitlement(theme.id);
    if (AccountSessionStore.hasMemberThemeAccess(theme.id)) return '会员免费使用';
    if (entitlement && entitlement.expiresAt > Date.now()) {
      return `有效至 ${this.formatDate(entitlement.expiresAt)}`;
    }
    const offer = this.themeOffer(theme.id);
    if (!offer) {
      return this.storeThemePriceLabel(theme.id);
    }
    return `${offer.pricePoints}点 · 有效期${offer.validDays}天`;
  }

  themeHasBookCover(theme: ThemePack): boolean {
    return !!theme.book.coverAssetId && this.themeCoverSet(theme).length > 0;
  }

  themeAccessLabel(themeId: string): string {
    if (themeId === ThemeIds.OBSIDIAN_ARCHIVE && !AccountSessionStore.hasOwnedEntitlement(themeId)) {
      return '终身超级会员专属 · 领取一年';
    }
    if (AccountSessionStore.hasMemberThemeAccess(themeId)) return '会员免费';
    if (BuiltinThemeRegistry.isFree(themeId)) {
      return '免费';
    }
    const entitlement: ThemeEntitlement | null = AccountSessionStore.entitlement(themeId);
    if (entitlement && entitlement.expiresAt > Date.now()) {
      return `有效至 ${this.formatDate(entitlement.expiresAt)}`;
    }
    return this.themeOffer(themeId) ? `${this.themeOffer(themeId)?.pricePoints}点 / 1年` :
      this.storeThemePriceLabel(themeId);
  }

  formatDate(timestamp: number): string {
    const date = new Date(timestamp);
    const month = `${date.getMonth() + 1}`.padStart(2, '0');
    const day = `${date.getDate()}`.padStart(2, '0');
    return `${date.getFullYear()}-${month}-${day}`;
  }

  @Builder
  themeVisualPreview(theme: ThemePack, customSchemeId: string = '') {
    this.themePreviewPanes(theme, customSchemeId, false)
    this.storeNavInfoRow(theme, customSchemeId)
  }

  customPreviewStartupImage(customSchemeId: string): string {
    const scheme = CustomThemeSchemeStore.find(this.customSchemes, customSchemeId);
    if (!scheme) return '';
    return this.appDarkMode ? scheme.settings.customDarkStartupImagePath :
      scheme.settings.customLightStartupImagePath;
  }

  customPreviewStartupTitle(customSchemeId: string): string {
    const scheme = CustomThemeSchemeStore.find(this.customSchemes, customSchemeId);
    if (!scheme) return '';
    return this.appDarkMode ? scheme.settings.customDarkStartupTitle :
      scheme.settings.customLightStartupTitle;
  }

  customPreviewStartupSubtitle(customSchemeId: string): string {
    const scheme = CustomThemeSchemeStore.find(this.customSchemes, customSchemeId);
    if (!scheme) return '';
    return this.appDarkMode ? scheme.settings.customDarkStartupSubtitle :
      scheme.settings.customLightStartupSubtitle;
  }

  /** The theme's emphasis bubble in bubble form, as the reader paints paragraph-comment / 本章说 pills. */
  themeCommentPreview(theme: ThemePack): ReaderResolvedRegexEmphasis {
    return ReaderRegexBubbleStyleResolver.resolve(null,
      this.themeEmphasisContext(theme, ThemeRegexEmphasisModes.BUBBLE), false);
  }

  /** The reader's comment bubble with its label baked in, cached per look, label and size. */
  commentBubbleImage(theme: ThemePack, label: string, fontSizeVp: number, dark: boolean): ReaderCommentBubbleImage | null {
    const style = ReaderCommentBubbleStyles.resolve(this.themeCommentPreview(theme).bubbleStyleId, dark);
    const pxPerVp = this.getUIContext().vp2px(1);
    const key = `${style.identity()}_${label}_${fontSizeVp}_${pxPerVp}`;
    const cached = this.commentBubbleImages.get(key);
    if (cached !== undefined) return cached;
    const rendered = ReaderCommentBubblePainter.renderLabel(style, label, fontSizeVp * pxPerVp);
    this.commentBubbleImages.set(key, rendered);
    return rendered;
  }

  commentBubbleImageWidth(image: ReaderCommentBubbleImage | null): number {
    return image ? this.getUIContext().px2vp(image.width) : 0;
  }

  commentBubbleImageHeight(image: ReaderCommentBubbleImage | null): number {
    return image ? this.getUIContext().px2vp(image.height) : 0;
  }

  @Builder
  commentBubbleSpan(theme: ThemePack, label: string, fontSizeVp: number, dark: boolean) {
    if (this.commentBubbleImage(theme, label, fontSizeVp, dark)) {
      ImageSpan((this.commentBubbleImage(theme, label, fontSizeVp, dark) as ReaderCommentBubbleImage).pixelMap)
        .width(this.commentBubbleImageWidth(this.commentBubbleImage(theme, label, fontSizeVp, dark)))
        .height(this.commentBubbleImageHeight(this.commentBubbleImage(theme, label, fontSizeVp, dark)))
        .objectFit(ImageFit.Contain)
        .verticalAlign(ImageSpanAlignment.CENTER)
    }
  }

  themeEmphasisContext(theme: ThemePack, mode: string): ReaderRegexEmphasisContext {
    const variant = this.activeVariant(theme);
    const context = new ReaderRegexEmphasisContext();
    context.inheritedMode = mode;
    context.inheritedBubbleStyleId = variant.regexEmphasis.bubbleStyle;
    context.inheritedColor = variant.regexEmphasis.emphasisColor;
    context.inheritedTextColor = variant.regexEmphasis.emphasisTextColor;
    context.accentColor = variant.colors.accentColor;
    context.surfaceColor = variant.reader.backgroundColor;
    context.normalTextColor = variant.reader.textColor;
    context.darkMode = variant.reader.contentTone === 'dark';
    return context;
  }

  themeRegexPreview(theme: ThemePack): ReaderResolvedRegexEmphasis {
    // Theme cards must preview the theme itself even before it is purchased.
    // Runtime entitlement checks are still enforced in the reader and the
    // regex-font settings page.
    return ReaderRegexBubbleStyleResolver.resolve(null,
      this.themeEmphasisContext(theme, this.activeVariant(theme).regexEmphasis.emphasisMode), false);
  }

  themeCoverSet(theme: ThemePack): ResourceStr[] {
    return ThemeAssetRegistry.themeBookCovers(theme.book.coverAssetId);
  }

  themeRegexPreviewBackground(theme: ThemePack): TextBackgroundStyle {
    const style = this.themeRegexPreview(theme);
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

  themeRegexPreviewShadow(theme: ThemePack): ShadowOptions | ShadowOptions[] {
    const style = this.themeRegexPreview(theme);
    if (style.textShadows.length > 0) return style.textShadows;
    return {
      radius: style.textShadowRadius,
      color: style.textShadowColor,
      offsetX: style.textShadowOffsetX,
      offsetY: style.textShadowOffsetY
    };
  }

  themeRegexPreviewDecoration(theme: ThemePack): DecorationStyleInterface {
    const style = this.themeRegexPreview(theme);
    if (!style.decorationEnabled) return { type: TextDecorationType.None };
    return {
      type: TextDecorationType.Underline,
      color: style.decorationColor,
      style: this.themeRegexDecorationStyle(style.decorationStyleId)
    };
  }

  themeRegexDecorationStyle(styleId: string): TextDecorationStyle {
    if (styleId === 'double') return TextDecorationStyle.DOUBLE;
    if (styleId === 'dotted') return TextDecorationStyle.DOTTED;
    if (styleId === 'dashed') return TextDecorationStyle.DASHED;
    if (styleId === 'wavy') return TextDecorationStyle.WAVY;
    return TextDecorationStyle.SOLID;
  }

}
