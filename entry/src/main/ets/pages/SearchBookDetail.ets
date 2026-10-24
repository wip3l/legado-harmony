import { router, uiMaterial } from '@kit.ArkUI';
import { motion } from '@kit.MultimodalAwarenessKit';
import deviceInfo from '@ohos.deviceInfo';
import { Book, SearchBook, BookChapter, BookFieldSanitizer, BookTypeSupport, BookUrlResolver } from '@legado/sourceengine';
import { AppDatabase } from '../model/data/AppDatabase';
import { WebBookService } from '../core/book/WebBookService';
import { syncSystemBars } from '../utils/SystemBars';
import { BookDisplayHelper } from '../utils/BookDisplayHelper';
import { CollapsingHeader } from '../utils/CollapsingHeader';
import { StatusBarScrim } from '../components/common/StatusBarScrim';
import { GlassTagModifier, ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';
import { BookIdentity } from '../utils/BookIdentity';
import { CoverUrlNormalizer } from '../utils/CoverUrlNormalizer';
import { ImmersiveBackButton } from '../components/ImmersiveBackButton';
import { ImmersiveReadButton, IMMERSIVE_READ_BUTTON_WIDTH } from '../components/ImmersiveReadButton';
import { BookCover } from '../components/book/BookCover';
import { SearchExplorePendingBook } from '../utils/SearchExplorePendingBook';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { SearchBookShelfHelper } from '../utils/SearchBookShelfHelper';
import { BookSourceStageRuntimeHost } from '../components/BookSourceStageRuntimeHost';
import { BookChangeSourceDialog } from '../components/BookChangeSourceDialog';
import { BookCatalogSheet } from '../components/BookCatalogSheet';
import { WebBookFetchRuntimeHost } from '../components/WebBookFetchRuntimeHost';
import { LocalBookService } from '../core/book/LocalBookService';
import { HdsFeedback } from '../utils/HdsFeedback';
import { VideoBookPlayer } from '../utils/VideoBookPlayer';
import { SystemDialogSession } from '../utils/SystemDialogSession';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';

@Entry
@Component
struct SearchBookDetailPage {
  @StorageProp('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  /** 顶栏底色与书名渐显所需的滚动距离。 */
  static readonly TITLE_FADE_DISTANCE: number = 120;
  /** 封面氛围背景的高度。 */
  static readonly AMBIENT_HEIGHT: number = 460;
  /** 简介收起时显示的行数。 */
  static readonly INTRO_COLLAPSED_LINES: number = 6;
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageLink('appLightAccentColor') appLightAccentColor: string = '#007DFF';
  @StorageLink('appDarkAccentColor') appDarkAccentColor: string = '#4E9BFF';
  @StorageLink('appLightButtonColor') appLightButtonColor: string = '#007DFF';
  @StorageLink('appDarkButtonColor') appDarkButtonColor: string = '#3F8CFF';
  @StorageLink('searchExploreUseBookshelfCoverGallery') searchExploreUseBookshelfCoverGallery: boolean = false;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @State bookUrl: string = '';
  @State tocUrl: string = '';
  @State origin: string = '';
  @State originName: string = '';
  @State name: string = '';
  @State author: string = '';
  @State kind: string = '';
  @State status: string = '';
  @State coverUrl: string = '';
  @State intro: string = '';
  @State latestChapterTitle: string = '';
  @State totalChapterNum: number = 0;
  @State wordCount: string = '';
  @State updateTime: string = '';
  @State bookType: number = 0;
  private bookVariable: string = '';
  private autoStartRead: boolean = false;
  private autoStartReadTriggered: boolean = false;
  private readerBookUrl: string = '';
  @State openingReader: boolean = false;
  @State readButtonOnLeft: boolean = false;
  @State readButtonBarWidth: number = 0;
  private holdingHandSubscribed: boolean = false;
  private holdingHandCallback: (status: motion.HoldingHandStatus) => void =
    (status: motion.HoldingHandStatus): void => this.onHoldingHandChanged(status);
  @State isInShelf: boolean = false;
  @State isSaving: boolean = false;
  @State isLoadingBookInfo: boolean = false;
  @State bookInfoRenderVersion: number = 0;
  private hasLoadedBookInfo: boolean = false;
  private resolvedBookInfo: Book | null = null;
  private bookInfoPromise: Promise<Book | null> | null = null;
  private bookInfoRetryTimerId: number = -1;
  private bookInfoRetryCount: number = 0;
  private shelfCheckPromise: Promise<void> | null = null;
  private shelfCheckKey: string = '';
  private shelfCheckVersion: number = -1;
  @State promptAddToShelfOnBackFromResult: boolean = false;
  @State promptAddToShelfAfterRead: boolean = false;
  @State pendingAddToShelfBookUrl: string = '';
  @State showAddToShelfOnBackDialog: boolean = false;
  private addToShelfOnBackDialogSession: SystemDialogSession = new SystemDialogSession();
  private changeSourceDialogSession: SystemDialogSession = new SystemDialogSession();
  @State @Watch('syncChangeSourceDialog') showChangeSourcePanel: boolean = false;
  @State changeSourceTarget: Book | null = null;
  @State showCatalogSheet: boolean = false;
  /** 正文滚动距离：顶栏底色与书名随之渐显。 */
  @State detailScrollY: number = 0;
  @State headerCollapse: number = 0;
  @State introExpanded: boolean = true;
  /** 头部封面已加载完成的地址；氛围背景只对它显示，读系统缓存而不再发第二次网络请求。 */
  @State readyCoverUrl: ResourceStr = '';
  private detailScroller: Scroller = new Scroller();
  private openingCatalogChapter: boolean = false;
  private authorSearchDialogBuilder: CustomBuilder | undefined = undefined;
  private authorSearchDialogId: number = -1;
  private changeSourceDialogBuilder: CustomBuilder | undefined = undefined;
  private changeSourceDialogId: number = -1;
  @StorageLink('searchExplorePromptAddToShelfOnBack') searchExplorePromptAddToShelfOnBack: boolean = true;

  aboutToAppear() {
    this.syncBars();
    this.bookInfoRetryCount = 0;
    const params = router.getParams() as Record<string, string>;
    if (params) {
      // Heal result caches produced by older builds that joined every matching descendant URL.
      // Keeping this at the detail boundary also prevents malformed values from becoming shelf IDs.
      this.bookUrl = BookUrlResolver.scalar(params['bookUrl'] || '');
      this.tocUrl = BookUrlResolver.scalar(params['tocUrl'] || '');
      this.origin = params['origin'] || '';
      this.originName = params['originName'] || '';
      this.name = params['name'] || '';
      this.author = params['author'] || '';
      this.kind = params['kind'] || '';
      this.status = params['status'] || '';
      this.coverUrl = params['coverUrl'] || '';
      this.intro = BookFieldSanitizer.clean(params['intro'] || '');
      this.latestChapterTitle = params['latestChapterTitle'] || '';
      this.wordCount = params['wordCount'] || '';
      this.updateTime = params['updateTime'] || '';
      this.bookType = Number(params['type'] || 0) || 0;
      this.bookVariable = params['variable'] || '';
      this.promptAddToShelfOnBackFromResult = params['promptAddToShelfOnBack'] === 'true';
      this.autoStartRead = params['autoStartRead'] === 'true';
      this.readerBookUrl = params['readerBookUrl'] || '';
      // Both operations initialize/read the same AppDatabase instance. Starting them at the
      // same time can make getBookSource() observe the store before initialization has completed,
      // leaving the detail page with an empty intro until the reader opens the book again.
      // Serialize the source-detail request behind the shelf check so the first page visit uses
      // the same initialized database path as the reader.
      this.checkShelf().then((): void => {
        this.loadBookInfo();
        this.triggerAutoStartRead();
      });
    }
  }

  onPageShow(): void {
    this.startHoldingHandTracking();
    this.syncBars();
    this.checkShelf().then(() => {
      if (this.shouldPromptAddToShelfOnBack()) {
        this.showAddToShelfOnBackPrompt();
      }
    });
    this.refreshChapterCount();
    // Some source runtimes need one UI turn after the detail route is mounted (especially when the
    // hidden Web transport is still attaching). Do not keep an empty first response cached forever.
    if (!this.intro && !this.isLoadingBookInfo && this.bookUrl && this.origin) {
      this.scheduleBookInfoRetry();
    }
  }

  aboutToDisappear(): void {
    this.stopHoldingHandTracking();
    if (this.bookInfoRetryTimerId >= 0) {
      clearTimeout(this.bookInfoRetryTimerId);
      this.bookInfoRetryTimerId = -1;
    }
  }

  onPageHide(): void {
    this.stopHoldingHandTracking();
  }

  private startHoldingHandTracking(): void {
    if (this.holdingHandSubscribed || deviceInfo.sdkApiVersion < 20 ||
      !canIUse('SystemCapability.MultimodalAwareness.Motion')) return;
    try {
      this.holdingHandSubscribed = true;
      motion.on('holdingHandChanged', this.holdingHandCallback);
    } catch (error) {
      this.holdingHandSubscribed = false;
      this.readButtonOnLeft = false;
      // 系统能力存在也可能不支持当前机型；保留右下角的常规阅读入口。
      console.warn('握姿感知不可用，阅读按钮保持右侧:', error);
    }
  }

  private stopHoldingHandTracking(): void {
    if (!this.holdingHandSubscribed) return;
    this.holdingHandSubscribed = false;
    try {
      // 仅移除本页回调，不影响系统底栏或其他页面的握姿订阅。
      motion.off('holdingHandChanged', this.holdingHandCallback);
    } catch (error) {
      console.warn('释放书籍详情握姿监听失败:', error);
    }
  }

  private onHoldingHandChanged(status: motion.HoldingHandStatus): void {
    if (!this.holdingHandSubscribed) return;
    // 双手、未握持、未知状态沿用上次位置，不让按钮在放下手机时突然跳回。
    if (status !== motion.HoldingHandStatus.LEFT_HAND_HELD &&
      status !== motion.HoldingHandStatus.RIGHT_HAND_HELD) return;
    const onLeft = status === motion.HoldingHandStatus.LEFT_HAND_HELD;
    if (onLeft === this.readButtonOnLeft) return;
    this.getUIContext().animateTo({ duration: 280, curve: Curve.Friction }, (): void => {
      this.readButtonOnLeft = onLeft;
    });
  }

  private readButtonOffsetX(): number {
    return this.readButtonOnLeft ?
      -Math.max(0, this.readButtonBarWidth - IMMERSIVE_READ_BUTTON_WIDTH - AppSpacing.XL * 2) : 0;
  }

  build() {
    Stack() {
      WebBookFetchRuntimeHost()
      this.ambientBackdrop()

      Column() {
        Scroll(this.detailScroller) {
          Column() {
            this.detailHero()

            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.getTags(), (tag: string, index: number) => {
                this.tagChip(tag, index)
              })

              if (this.wordCount) {
                Text(this.wordCount)
                  .fontSize(AppFontSize.BODY)
                  .fontColor(this.secondaryTextColor())
                  .padding({ left: AppSpacing.MD, right: AppSpacing.MD, top: AppSpacing.XS, bottom: AppSpacing.XS })
                  .attributeModifier(this.neutralTagModifier())
                  .margin({ right: AppSpacing.MD, bottom: AppSpacing.MD })
              }

              if (this.updateTime) {
                Text(`更新：${this.updateTime}`)
                  .fontSize(AppFontSize.BODY)
                  .fontColor(this.secondaryTextColor())
                  .padding({ left: AppSpacing.MD, right: AppSpacing.MD, top: AppSpacing.XS, bottom: AppSpacing.XS })
                  .attributeModifier(this.neutralTagModifier())
                  .margin({ right: AppSpacing.MD, bottom: AppSpacing.MD })
              }
            }
            .width('100%')
            .margin({ top: AppSpacing.XL })

            Divider()
              .strokeWidth(0.5)
              .color(ThemeRuntime.hairlineColor(this.appDarkMode))
              .margin({ top: AppSpacing.XS })

            Row() {
              this.detailShelfAction()
              this.detailActionItem($r('sys.symbol.list_bullet'),
                BookTypeSupport.isVideo(this.detailTypeProbe()) ? '选集' : '目录', () => {
                  this.openChapterList();
                })
              this.detailActionItem($r('sys.symbol.arrow_left_arrow_right'), '换源', () => {
                this.showChangeSourcePrompt();
              })
              this.detailActionItem($r('sys.symbol.person'), '同作者', () => {
                this.showAuthorSearchPrompt();
              })
            }
            .width('100%')
            .padding({ top: AppSpacing.LG, bottom: AppSpacing.LG })

            Divider()
              .strokeWidth(0.5)
              .color(ThemeRuntime.hairlineColor(this.appDarkMode))

            this.detailChapterRow()
            this.detailIntro()
          }
          .width('100%')
          .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: 64 + this.statusBarHeight,
            bottom: 96 + this.navBarHeight })
        }
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        // 内容不足一屏时贴顶，Scroll 默认会把它竖直居中。
        .align(Alignment.Top)
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .onDidScroll((_xOffset: number, yOffset: number) => {
          this.headerCollapse = CollapsingHeader.next(this.headerCollapse, yOffset,
            this.detailScroller.currentOffset().yOffset);
          // 只在跨过渐显区间时更新，滚动中不逐帧刷新整页。
          const offset = Math.max(0, Math.min(SearchBookDetailPage.TITLE_FADE_DISTANCE, this.detailScroller.currentOffset().yOffset));
          if (Math.abs(offset - this.detailScrollY) >= 4 || offset === 0 || offset === SearchBookDetailPage.TITLE_FADE_DISTANCE) {
            this.detailScrollY = offset;
          }
        })
        .onScrollStop(() => {
          const target = CollapsingHeader.settle(this.headerCollapse, this.detailScroller.currentOffset().yOffset);
          if (target !== this.headerCollapse) {
            animateTo({ duration: 200, curve: Curve.FastOutSlowIn }, () => {
              this.headerCollapse = target;
            });
          }
        })
      }
      .width('100%')
      .height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      StatusBarScrim({ statusBarHeight: this.statusBarHeight, pageColor: this.pageColor(),
        scrimOpacity: CollapsingHeader.scrimOpacity(this.headerCollapse) })
        .width('100%')
        .position({ x: 0, y: 0 })

      this.titleBar()

      Row() {
        ImmersiveReadButton({
          label: BookTypeSupport.isVideo(this.detailTypeProbe()) ? '开始观看' :
            (BookTypeSupport.isAudio(this.detailTypeProbe()) ? '开始听书' : '开始阅读'),
          icon: BookTypeSupport.isVideo(this.detailTypeProbe()) || BookTypeSupport.isAudio(this.detailTypeProbe()) ?
            $r('sys.symbol.play_fill') : $r('sys.symbol.book'),
          darkMode: this.appDarkMode,
          accentColor: this.accentColor(),
          busy: this.isSaving || this.openingReader || this.openingCatalogChapter,
          onRead: (): void => {
            this.startRead();
          }
        })
          .translate({ x: this.readButtonOffsetX() })
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .padding({ right: AppSpacing.XL, bottom: AppSpacing.XL + this.navBarHeight })
      // 锚定整页底边，再上移自身高度；align 不会改变 Row 在父 Stack 中的默认居中位置。
      .position({ x: 0, y: '100%' })
      .translate({ y: '-100%' })
      .hitTestBehavior(HitTestMode.Transparent)
      .onAreaChange((_oldArea: Area, newArea: Area): void => {
        this.readButtonBarWidth = Number(newArea.width);
      })

      BookSourceStageRuntimeHost()
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .bindSheet($$this.showCatalogSheet, this.catalogSheet(), this.catalogSheetOptions())
  }

  /** 换源：系统对话框，API 26+ 是沉浸光感表面。 */
  @Builder
  changeSourceDialogContent() {
    BookChangeSourceDialog({
      targetBook: this.changeSourceTarget,
      onSwitched: (switched: Book): void => {
        this.applySwitchedSource(switched);
      },
      onClosed: (): void => {
        this.showChangeSourcePanel = false;
        this.changeSourceTarget = null;
      }
    })
  }

  syncChangeSourceDialog(): void {
    this.changeSourceDialogSession.sync(this.getUIContext(), this.showChangeSourcePanel, (): void => {
      this.changeSourceDialogContent();
    }, {
      autoCancel: false,
      maskColor: ThemeRuntime.scrimColor(this.appDarkMode),
      warnTag: '显示换源弹窗失败:'
    });
  }

  /** 半模态只管理尺寸和关闭；底板由 BookCatalogSheet 复用正文 ReaderMaterialPanel，避免双层材质。 */
  catalogSheetOptions(): SheetOptions {
    const options: SheetOptions = {
      detents: ['67%', SheetSize.LARGE],
      dragBar: false,
      showClose: false,
      backgroundColor: Color.Transparent,
      blurStyle: BlurStyle.NONE,
      borderWidth: 0,
      radius: { topLeft: 28, topRight: 28, bottomLeft: 28, bottomRight: 28 },
      shadow: { radius: 0, color: Color.Transparent },
      scrollSizeMode: ScrollSizeMode.CONTINUOUS,
      onDisappear: () => {
        this.showCatalogSheet = false;
      }
    };
    if (ImmersiveMaterialRuntime.supportsHds()) options.systemMaterial = uiMaterial.Material.empty;
    return options;
  }

  @Builder
  catalogSheet() {
    BookCatalogSheet({
      book: this.buildCurrentBook(),
      onChapterSelected: (chapter: BookChapter): void => {
        this.openChapterFromCatalog(chapter);
      },
      onLoaded: (count: number): void => {
        this.totalChapterNum = count;
      },
      onClose: (): void => {
        this.showCatalogSheet = false;
      }
    })
  }

  @Builder
  titleBar() {
    Stack({ alignContent: Alignment.TopStart }) {
      Row() {
        ImmersiveBackButton({ iconColor: this.primaryTextColor(), darkMode: this.appDarkMode,
          onBack: () => this.handleBack() })

        Text(this.titleBarProgress() > 0.6 ? (this.name || this.detailPageTitle()) : this.detailPageTitle())
          .fontSize(AppFontSize.TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .width('100%')
      .height(56 + this.statusBarHeight)
      .padding({ right: AppSpacing.XL, top: this.statusBarHeight })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(56 + this.statusBarHeight - this.headerCollapse)
    .clip(true)
    .opacity(CollapsingHeader.contentOpacity(this.headerCollapse))
    .hitTestBehavior(CollapsingHeader.acceptsTouch(this.headerCollapse) ? HitTestMode.Default : HitTestMode.None)
    .accessibilityLevel(CollapsingHeader.acceptsTouch(this.headerCollapse) ? 'auto' : 'no-hide-descendants')
    .position({ x: 0, y: 0 })
  }

  titleBarProgress(): number {
    return Math.min(1, this.detailScrollY / SearchBookDetailPage.TITLE_FADE_DISTANCE);
  }

  detailPageTitle(): string {
    return BookTypeSupport.isVideo(this.detailTypeProbe()) ? '剧集详情' : '书籍详情';
  }

  /**
   * 封面氛围背景：封面低分辨率模糊铺在顶部，上面盖一层“透明 → 页面底色”的渐变，渐变底部是不透明的页面色、
   * 正好对齐图片底边，所以图片底部自然消失、没有硬边。页面底色层与渐变层始终不透明，滚动时只淡化图片这一层。
   * 封面等头部封面加载完成后再显示，读系统缓存，不再发第二次网络请求。
   */
  @Builder
  ambientBackdrop() {
    Stack({ alignContent: Alignment.Top }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.pageColor())

      if (this.readyCoverUrl) {
        Image(this.readyCoverUrl)
          .width('100%')
          .height(SearchBookDetailPage.AMBIENT_HEIGHT)
          .objectFit(ImageFit.Cover)
          .sourceSize({ width: 96, height: 128 })
          .blur(48)
          .opacity((this.appDarkMode ? 0.5 : 0.62) * (1 - this.titleBarProgress() * 0.4))
      }

      Column()
        .width('100%')
        .height(SearchBookDetailPage.AMBIENT_HEIGHT)
        .linearGradient({
          direction: GradientDirection.Bottom,
          colors: [
            // 顶部也叠一层淡淡的页面色，保证作者、书源等次要文字在封面色上看得清。
            [`#40${this.pageColor().substring(1)}`, 0],
            [`#33${this.pageColor().substring(1)}`, 0.3],
            [`#A6${this.pageColor().substring(1)}`, 0.68],
            [this.pageColor(), 1]
          ]
        })
    }
    .width('100%')
    .height('100%')
    .clip(true)
    .hitTestBehavior(HitTestMode.None)
    .accessibilityLevel('no')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  /** 头部：封面、书名、作者与书源直接放在氛围背景上，不再套卡片。 */
  @Builder
  detailHero() {
    Row({ space: AppSpacing.XL }) {
      Stack() {
        this.coverView(104, 140)
      }
      // 投影按外层形状绘制，不给圆角会是直角矩形的影子，在封面四角露出来。
      .borderRadius(8)
      .shadow({ radius: 16, color: this.appDarkMode ? '#66000000' : '#33000000', offsetX: 0, offsetY: 6 })

      Column() {
        Text(this.name || '未知书名')
          .fontSize(AppFontSize.HEADLINE)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Row({ space: AppSpacing.XXS }) {
          Text(this.author || '作者未知')
            .fontSize(AppFontSize.BODY_LARGE)
            .fontColor(this.secondaryTextColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .flexShrink(1)
          if (this.author) {
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(14)
              .fontColor([this.subTextColor()])
          }
        }
        .alignItems(VerticalAlign.Center)
        .margin({ top: AppSpacing.MD })
        .onClick(() => {
          if (this.author) {
            this.showAuthorSearchPrompt();
          }
        })

        if (this.originName || this.origin) {
          Row({ space: AppSpacing.XS }) {
            SymbolGlyph($r('sys.symbol.arrow_left_arrow_right'))
              .fontSize(13)
              .fontColor([this.subTextColor()])
            Text(this.originName || this.origin)
              .fontSize(AppFontSize.BODY)
              .fontColor(this.subTextColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .flexShrink(1)
          }
          .alignItems(VerticalAlign.Center)
          .margin({ top: AppSpacing.SM })
          .accessibilityText(`书源${this.originName || this.origin}，换源`)
          .onClick(() => {
            this.showChangeSourcePrompt();
          })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ top: AppSpacing.LG })
    .alignItems(VerticalAlign.Center)
  }

  /** 书架操作直接读取 isInShelf，加入或移出后同步刷新按钮。 */
  @Builder
  detailShelfAction() {
    Column({ space: AppSpacing.SM }) {
      SymbolGlyph(this.isInShelf ? $r('sys.symbol.bookshelf_badge_checkmark_fill') : $r('sys.symbol.bookshelf'))
        .fontSize(24)
        .fontColor([this.isInShelf ? this.accentColor() : this.primaryTextColor()])
      Text(this.isSaving ? (this.isInShelf ? '移出中' : '加入中') : (this.isInShelf ? '移出书架' : '加入书架'))
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.isInShelf ? this.accentColor() : this.secondaryTextColor())
        .maxLines(1)
    }
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
    .accessibilityText(this.isInShelf ? '移出书架' : '加入书架')
    .onClick(() => {
      if (this.isSaving) return;
      if (this.isInShelf) {
        this.removeFromShelf();
      } else {
        this.addToShelf();
      }
    })
  }

  @Builder
  detailActionItem(icon: Resource, label: string, onTap: () => void) {
    Column({ space: AppSpacing.SM }) {
      SymbolGlyph(icon)
        .fontSize(24)
        .fontColor([this.primaryTextColor()])
      Text(label)
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.secondaryTextColor())
        .maxLines(1)
    }
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
    .accessibilityText(label)
    .onClick(() => onTap())
  }

  /** 目录入口：“最新 · 章节名”，右侧总章数；目录是章节列表的唯一入口，没有最新章节名时也保留。 */
  @Builder
  detailChapterRow() {
    Row({ space: AppSpacing.SM }) {
      Text() {
        Span(BookTypeSupport.isVideo(this.detailTypeProbe()) ? '选集' : '最新')
          .fontColor(this.secondaryTextColor())
        Span(' · ')
          .fontColor(this.subTextColor())
        Span(this.latestChapterTitle || '点击查看完整章节列表')
          .fontColor(this.primaryTextColor())
      }
      .fontSize(AppFontSize.BODY_LARGE)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .layoutWeight(1)

      if (this.totalChapterNum > 0) {
        Text(`共 ${this.totalChapterNum} ${BookTypeSupport.isVideo(this.detailTypeProbe()) ||
          BookTypeSupport.isAudio(this.detailTypeProbe()) ? '集' : '章'}`)
          .fontSize(AppFontSize.BODY)
          .fontColor(this.subTextColor())
      }
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(14)
        .fontColor([this.subTextColor()])
    }
    .width('100%')
    .height(52)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.openChapterList();
    })
  }

  @Builder
  detailIntro() {
    Column({ space: AppSpacing.SM }) {
      Row({ space: AppSpacing.SM }) {
        SymbolGlyph($r('sys.symbol.doc_text'))
          .fontSize(16)
          .fontColor([this.subTextColor()])
        Text('简介')
          .fontSize(AppFontSize.BODY_LARGE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.primaryTextColor())
      }
      .alignItems(VerticalAlign.Center)

      Text(this.intro || (this.isLoadingBookInfo ? '简介加载中...' : '暂无简介'))
        .fontSize(AppFontSize.BODY_LARGE)
        .fontColor(this.secondaryTextColor())
        .lineHeight(26)
        .maxLines(this.introExpanded ? 1000 : SearchBookDetailPage.INTRO_COLLAPSED_LINES)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .copyOption(CopyOptions.LocalDevice)
        .width('100%')
        .id(`book_detail_intro_${this.bookInfoRenderVersion}`)
        .onClick(() => {
          if (this.introIsLong()) {
            this.introExpanded = !this.introExpanded;
          }
        })

      if (this.introIsLong()) {
        Text(this.introExpanded ? '收起' : '展开全部')
          .fontSize(AppFontSize.BODY)
          .fontColor(this.accentColor())
          .padding({ top: AppSpacing.XS, bottom: AppSpacing.XS })
          .onClick(() => {
            this.introExpanded = !this.introExpanded;
          })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: AppSpacing.MD })
  }

  /** 粗略按字数判断简介是否超过收起时的行数，避免为测量文字再做一次布局。 */
  introIsLong(): boolean {
    const text = this.intro || '';
    return text.length > 120 || text.split('\n').length > SearchBookDetailPage.INTRO_COLLAPSED_LINES;
  }

  onBackPress(): boolean {
    if (this.shouldPromptAddToShelfOnBack()) {
      this.showAddToShelfOnBackPrompt();
      return true;
    }
    return false;
  }

  async checkShelf(): Promise<void> {
    const key = BookIdentity.keyOfUrl(this.bookUrl, this.origin);
    const version = AppStorage.get<number>('shelfUpdateTime') || 0;
    if (this.shelfCheckPromise) return this.shelfCheckPromise;
    if (key && key === this.shelfCheckKey && version === this.shelfCheckVersion) return;
    const task = this.performShelfCheck();
    this.shelfCheckPromise = task;
    try {
      await task;
      this.shelfCheckKey = BookIdentity.keyOfUrl(this.bookUrl, this.origin);
      this.shelfCheckVersion = AppStorage.get<number>('shelfUpdateTime') || 0;
    } finally {
      if (this.shelfCheckPromise === task) this.shelfCheckPromise = null;
    }
  }

  private async performShelfCheck(): Promise<void> {
    if (!this.bookUrl || this.bookUrl.trim() === '') {
      this.isInShelf = false;
      return;
    }

    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      const existing = await db.getBook(this.bookUrl) ||
        await this.findShelfBookByKey(BookIdentity.keyOfUrl(this.bookUrl, this.origin));
      if (existing) {
        const nextCoverUrl = CoverUrlNormalizer.prefer(this.coverUrl, existing.coverUrl);
        if (nextCoverUrl && existing.coverUrl !== nextCoverUrl) {
          existing.coverUrl = nextCoverUrl;
          await db.updateBook(existing, true, 'detail_check_cover_update');
          AppStorage.setOrCreate('shelfUpdateTime', Date.now());
        }
      }
      if (existing) {
        this.syncStateFromBook(existing);
      }
      this.isInShelf = existing !== null && !SearchExplorePendingBook.isPendingAddToShelf(existing);
    } catch (e) {
      console.error('检查书架失败:', e);
      this.isInShelf = false;
    }
  }

  async removeFromShelf(): Promise<void> {
    if (this.isSaving || !this.isInShelf) return;
    this.isSaving = true;
    try {
      const book = new SearchBook();
      book.bookUrl = this.bookUrl;
      book.origin = this.origin;
      await SearchBookShelfHelper.removeFromShelf(getContext(this), book);
      this.isInShelf = false;
      this.promptAddToShelfAfterRead = false;
      this.pendingAddToShelfBookUrl = '';
      this.shelfCheckKey = '';
      this.shelfCheckVersion = -1;
    } catch (e) {
      console.error('移出书架失败:', e);
      HdsFeedback.showToast('移出书架失败');
    } finally {
      this.isSaving = false;
    }
  }

  async addToShelf(): Promise<boolean> {
    if (!this.bookUrl) {
      HdsFeedback.showToast('书籍地址为空');
      return false;
    }

    this.isSaving = true;
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      const requestKey = BookIdentity.keyOfUrl(this.bookUrl, this.origin);
      const existing = await db.getBook(this.bookUrl) || await this.findShelfBookByKey(requestKey);
      if (existing) {
        const nextCoverUrl = CoverUrlNormalizer.prefer(this.coverUrl, existing.coverUrl);
        if (nextCoverUrl && existing.coverUrl !== nextCoverUrl) {
          existing.coverUrl = nextCoverUrl;
        }
        existing.kind = BookFieldSanitizer.prefer(this.kind, existing.kind);
        existing.status = BookFieldSanitizer.prefer(this.status, existing.status);
        existing.intro = BookFieldSanitizer.prefer(this.intro, existing.intro);
        existing.latestChapterTitle = BookFieldSanitizer.prefer(this.latestChapterTitle, existing.latestChapterTitle);
        existing.wordCount = BookFieldSanitizer.prefer(this.wordCount, existing.wordCount);
        existing.updateTime = BookFieldSanitizer.prefer(this.updateTime, existing.updateTime);
        SearchExplorePendingBook.clearPendingAddToShelf(existing);
        await db.updateBook(existing, true, 'explicit_add_existing');
        AppStorage.setOrCreate('shelfUpdateTime', Date.now());
        this.syncStateFromBook(existing);
        this.isInShelf = true;
        this.promptAddToShelfAfterRead = false;
        this.pendingAddToShelfBookUrl = '';
        return true;
      }

      const book = new Book();
      book.bookUrl = this.bookUrl;
      book.tocUrl = this.tocUrl;
      book.origin = this.origin;
      book.originName = this.originName;
      book.name = this.name;
      book.author = this.author;
      book.kind = BookFieldSanitizer.clean(this.kind);
      book.status = BookFieldSanitizer.clean(this.status);
      book.coverUrl = CoverUrlNormalizer.normalize(this.coverUrl);
      book.intro = BookFieldSanitizer.clean(this.intro);
      book.latestChapterTitle = BookFieldSanitizer.clean(this.latestChapterTitle);
      book.wordCount = BookFieldSanitizer.clean(this.wordCount);
      book.updateTime = BookFieldSanitizer.clean(this.updateTime);
      book.group = -2147483645;
      book.type = this.bookType;
      book.variable = this.bookVariable;
      BookTypeSupport.applyBookType(book);
      book.canUpdate = true;
      book.lastCheckTime = Date.now();
      book.latestChapterTime = Date.now();
      const fallbackCoverUrl = book.coverUrl;
      const fullBook = await this.resolveBookInfo();
      if (fullBook) {
        book.bookUrl = fullBook.bookUrl || book.bookUrl;
        book.tocUrl = fullBook.tocUrl || book.tocUrl;
        book.name = fullBook.name || book.name;
        book.author = fullBook.author || book.author;
        book.kind = BookFieldSanitizer.prefer(fullBook.kind, book.kind);
        book.status = BookFieldSanitizer.prefer(fullBook.status, book.status);
        book.coverUrl = CoverUrlNormalizer.prefer(fallbackCoverUrl, fullBook.coverUrl || book.coverUrl);
        book.intro = BookFieldSanitizer.prefer(fullBook.intro, book.intro);
        book.latestChapterTitle = BookFieldSanitizer.prefer(fullBook.latestChapterTitle, book.latestChapterTitle);
        book.updateTime = BookFieldSanitizer.prefer(fullBook.updateTime, book.updateTime);
        book.wordCount = BookFieldSanitizer.prefer(fullBook.wordCount, book.wordCount);
        book.variable = fullBook.variable || book.variable;
        book.type = fullBook.type || book.type;
      }

      const resolvedExisting = await this.findShelfBookByKey(BookIdentity.keyOfBook(book));
      if (resolvedExisting) {
        const nextCoverUrl = CoverUrlNormalizer.prefer(book.coverUrl, resolvedExisting.coverUrl);
        if (nextCoverUrl && resolvedExisting.coverUrl !== nextCoverUrl) {
          resolvedExisting.coverUrl = nextCoverUrl;
        }
        resolvedExisting.kind = BookFieldSanitizer.prefer(book.kind, resolvedExisting.kind);
        resolvedExisting.status = BookFieldSanitizer.prefer(book.status, resolvedExisting.status);
        resolvedExisting.intro = BookFieldSanitizer.prefer(book.intro, resolvedExisting.intro);
        resolvedExisting.latestChapterTitle = BookFieldSanitizer.prefer(book.latestChapterTitle, resolvedExisting.latestChapterTitle);
        resolvedExisting.updateTime = BookFieldSanitizer.prefer(book.updateTime, resolvedExisting.updateTime);
        resolvedExisting.wordCount = BookFieldSanitizer.prefer(book.wordCount, resolvedExisting.wordCount);
        SearchExplorePendingBook.clearPendingAddToShelf(resolvedExisting);
        await db.updateBook(resolvedExisting, true, 'explicit_add_resolved_existing');
        AppStorage.setOrCreate('shelfUpdateTime', Date.now());
        this.syncStateFromBook(resolvedExisting);
        this.isInShelf = true;
        this.promptAddToShelfAfterRead = false;
        this.pendingAddToShelfBookUrl = '';
        return true;
      }

      SearchExplorePendingBook.clearPendingAddToShelf(book);
      await db.insertBook(book, 'explicit_add_from_detail');
      this.syncStateFromBook(book);

      this.isInShelf = true;
      this.promptAddToShelfAfterRead = false;
      this.pendingAddToShelfBookUrl = '';
      this.isSaving = false;
      AppStorage.setOrCreate('shelfUpdateTime', Date.now());
      HdsFeedback.showToast('已加入书架');
      return true;
    } catch (e) {
      console.error('加入书架失败:', e);
      HdsFeedback.showToast('加入书架失败');
      return false;
    } finally {
      this.isSaving = false;
    }
  }

  async loadBookInfo(): Promise<void> {
    try {
      const fullBook = await this.resolveBookInfo();
      if (fullBook) this.syncStateFromBook(fullBook);
      if (!this.intro) this.scheduleBookInfoRetry();
    } catch (e) {
      console.warn('加载书籍详情失败:', e);
      this.scheduleBookInfoRetry();
    }
  }

  private scheduleBookInfoRetry(): void {
    if (this.intro || !this.bookUrl || !this.origin || this.bookInfoRetryCount >= 4) return;
    if (this.bookInfoRetryTimerId >= 0) return;
    const retry = this.bookInfoRetryCount++;
    const delay = retry === 0 ? 500 : (retry === 1 ? 1200 : (retry === 2 ? 2500 : 5000));
    this.bookInfoRetryTimerId = setTimeout((): void => {
      this.bookInfoRetryTimerId = -1;
      if (this.intro || !this.bookUrl || !this.origin || this.isLoadingBookInfo) return;
      // WebBookService returns the original Book instance when a request or rule yields no fields. Clear
      // that incomplete cache so the next attempt can observe a newly attached runtime/session.
      this.resolvedBookInfo = null;
      this.hasLoadedBookInfo = false;
      this.loadBookInfo();
    }, delay);
  }

  private async resolveBookInfo(): Promise<Book | null> {
    if (this.resolvedBookInfo) return this.resolvedBookInfo;
    if (this.bookInfoPromise) return this.bookInfoPromise;
    if (this.hasLoadedBookInfo || !this.bookUrl || !this.origin) return null;
    this.hasLoadedBookInfo = true;
    this.isLoadingBookInfo = true;
    const task = this.fetchBookInfo();
    this.bookInfoPromise = task;
    try {
      const fullBook = await task;
      if (fullBook) {
        fullBook.lastCheckTime = Date.now();
        this.resolvedBookInfo = fullBook;
        this.syncStateFromBook(fullBook);
      }
      return fullBook;
    } finally {
      if (this.bookInfoPromise === task) this.bookInfoPromise = null;
      this.isLoadingBookInfo = false;
    }
  }

  private async fetchBookInfo(): Promise<Book | null> {
    const db = AppDatabase.getInstance();
    await db.initWithContext(getContext(this));
    const source = await db.getBookSource(this.origin);
    if (!source) return null;
    const book = this.buildCurrentBook();
    BookTypeSupport.applyBookType(book, source);
    return new WebBookService().getBookInfo(source, book);
  }

  private buildCurrentBook(): Book {
    const book = new Book();
    book.bookUrl = this.bookUrl;
    book.tocUrl = this.tocUrl;
    book.origin = this.origin;
    book.originName = this.originName;
    book.name = this.name;
    book.author = this.author;
    book.kind = BookFieldSanitizer.clean(this.kind);
    book.status = BookFieldSanitizer.clean(this.status);
    book.coverUrl = CoverUrlNormalizer.normalize(this.coverUrl);
    book.intro = BookFieldSanitizer.clean(this.intro);
    book.latestChapterTitle = BookFieldSanitizer.clean(this.latestChapterTitle);
    book.wordCount = BookFieldSanitizer.clean(this.wordCount);
    book.updateTime = BookFieldSanitizer.clean(this.updateTime);
    book.type = this.bookType;
    book.variable = this.bookVariable;
    return book;
  }

  handleBack(): void {
    if (this.shouldPromptAddToShelfOnBack()) {
      this.showAddToShelfOnBackPrompt();
      return;
    }
    router.back();
  }

  showAuthorSearchPrompt(): void {
    if (!this.author.trim()) return;
    // 与“点数使用说明”相同的系统自定义对话框：表面材质由系统提供，API 26+ 即沉浸光感效果。
    this.authorSearchDialogBuilder = (): void => {
      this.authorSearchDialogContent();
    };
    this.getUIContext().getPromptAction().openCustomDialog({
      builder: this.authorSearchDialogBuilder,
      autoCancel: true,
      alignment: DialogAlignment.Center,
      maskColor: ThemeRuntime.scrimColor(this.appDarkMode)
    }).then((dialogId: number) => {
      this.authorSearchDialogId = dialogId;
    }).catch((error: Error) => {
      console.warn('显示作者检索确认失败:', error);
    });
  }

  closeAuthorSearchDialog(): void {
    if (this.authorSearchDialogId >= 0) {
      this.getUIContext().getPromptAction().closeCustomDialog(this.authorSearchDialogId);
      this.authorSearchDialogId = -1;
    }
  }

  confirmAuthorSearch(): void {
    this.closeAuthorSearchDialog();
    const author = this.author.trim();
    if (!author) return;
    const nonce = AppStorage.get<number>('globalSearchPendingNonce') || 0;
    AppStorage.setOrCreate('globalSearchPendingKeyword', author);
    AppStorage.setOrCreate('globalSearchPendingNonce', nonce + 1);
    // 详情页可能叠在聚合结果页之上，直接回退到主页再切搜索Tab，保证发起搜索的页面可见。
    router.back({ url: 'pages/Index' });
  }

  showChangeSourcePrompt(): void {
    if (!this.bookUrl || !this.origin) {
      HdsFeedback.showToast('书籍信息不完整，暂时无法换源');
      return;
    }
    if (LocalBookService.isLocalBook(this.detailTargetBook())) {
      HdsFeedback.showToast('本地书籍无需换源');
      return;
    }
    this.changeSourceDialogBuilder = (): void => {
      this.changeSourceConfirmDialogContent();
    };
    this.getUIContext().getPromptAction().openCustomDialog({
      builder: this.changeSourceDialogBuilder,
      autoCancel: true,
      alignment: DialogAlignment.Center,
      maskColor: ThemeRuntime.scrimColor(this.appDarkMode)
    }).then((dialogId: number) => {
      this.changeSourceDialogId = dialogId;
    }).catch((error: Error) => {
      console.warn('显示换源确认失败:', error);
    });
  }

  closeChangeSourceDialog(): void {
    if (this.changeSourceDialogId >= 0) {
      this.getUIContext().getPromptAction().closeCustomDialog(this.changeSourceDialogId);
      this.changeSourceDialogId = -1;
    }
  }

  detailTargetBook(): Book {
    const resolved = this.resolvedBookInfo;
    if (resolved) return resolved;
    return this.buildCurrentBook();
  }

  confirmChangeSource(): void {
    this.closeChangeSourceDialog();
    // 打开面板前固化目标书籍，避免面板打开期间详情信息加载完成导致目标被替换。
    this.changeSourceTarget = this.detailTargetBook();
    this.showChangeSourcePanel = true;
  }

  applySwitchedSource(switched: Book): void {
    const previousBookUrl = this.bookUrl;
    // 旧书源解析缓存全部作废，后续加入书架/阅读都会按新书源重新拉取。
    this.resolvedBookInfo = null;
    this.bookInfoPromise = null;
    this.hasLoadedBookInfo = false;
    this.syncStateFromBook(switched);
    if (this.pendingAddToShelfBookUrl && this.pendingAddToShelfBookUrl === previousBookUrl) {
      this.pendingAddToShelfBookUrl = switched.bookUrl;
    }
    this.totalChapterNum = switched.totalChapterNum > 0 ? switched.totalChapterNum : 0;
    this.checkShelf();
  }

  shouldPromptAddToShelfOnBack(): boolean {
    return this.promptAddToShelfOnBackFromResult && this.searchExplorePromptAddToShelfOnBack &&
      this.promptAddToShelfAfterRead && !this.isSaving && !this.showAddToShelfOnBackDialog &&
      !!this.bookUrl && this.bookUrl === this.pendingAddToShelfBookUrl;
  }

  showAddToShelfOnBackPrompt(): void {
    if (this.showAddToShelfOnBackDialog) return;
    this.showAddToShelfOnBackDialog = true;
    // 蒙层点击原本走“不加入”清理流程而非普通关闭，因此禁用 autoCancel，仅由按钮触发。
    this.addToShelfOnBackDialogSession.open(this.getUIContext(),
      (): void => {
        this.addToShelfOnBackDialogContent();
      }, {
        autoCancel: false,
        maskColor: ThemeRuntime.scrimColor(this.appDarkMode),
        warnTag: '显示加入书架确认失败:'
      });
  }

  closeAddToShelfOnBackDialog(): void {
    this.showAddToShelfOnBackDialog = false;
    this.addToShelfOnBackDialogSession.close(this.getUIContext());
  }

  dismissAddToShelfOnBackPrompt(): void {
    this.closeAddToShelfOnBackDialog();
    this.removePendingReadBook().finally(() => {
      router.back();
    });
  }

  async removePendingReadBook(): Promise<void> {
    if (!this.pendingAddToShelfBookUrl) {
      return;
    }
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      const pendingBook = await db.getBook(this.pendingAddToShelfBookUrl);
      if (SearchExplorePendingBook.isPendingAddToShelf(pendingBook)) {
        await db.deleteBook(this.pendingAddToShelfBookUrl, 'temporary_read_declined');
        AppStorage.setOrCreate('shelfUpdateTime', Date.now());
      }
    } catch (e) {
      console.error('移除临时阅读书籍失败:', e);
    }
    this.promptAddToShelfAfterRead = false;
    this.pendingAddToShelfBookUrl = '';
    this.isInShelf = false;
  }

  async keepPendingReadBookInShelf(): Promise<boolean> {
    if (!this.pendingAddToShelfBookUrl) {
      return await this.addToShelf();
    }
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      const pendingBook = await db.getBook(this.pendingAddToShelfBookUrl);
      if (pendingBook) {
        SearchExplorePendingBook.clearPendingAddToShelf(pendingBook);
        await db.updateBook(pendingBook, true, 'temporary_read_kept');
        this.syncStateFromBook(pendingBook);
        this.isInShelf = true;
        this.promptAddToShelfAfterRead = false;
        this.pendingAddToShelfBookUrl = '';
        AppStorage.setOrCreate('shelfUpdateTime', Date.now());
        HdsFeedback.showToast('已加入书架');
        return true;
      }
    } catch (e) {
      console.error('加入书架失败:', e);
      HdsFeedback.showToast('加入书架失败');
      return false;
    }
    return await this.addToShelf();
  }

  async confirmAddToShelfOnBack(): Promise<void> {
    this.closeAddToShelfOnBackDialog();
    const ok = await this.keepPendingReadBookInShelf();
    if (ok) {
      router.back();
    }
  }

  async prepareBookForReading(): Promise<boolean> {
    if (!this.bookUrl) {
      HdsFeedback.showToast('书籍地址为空');
      return false;
    }

    this.isSaving = true;
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      const requestKey = BookIdentity.keyOfUrl(this.bookUrl, this.origin);
      const existing = await db.getBook(this.bookUrl) || await this.findShelfBookByKey(requestKey, true);
      if (existing) {
        let bookChanged = false;
        const knownCategory = BookTypeSupport.mediaCategoryOf(this.detailTypeProbe());
        const inferredType = this.bookType || BookTypeSupport.typeFromVariable(this.bookVariable);
        if (knownCategory === BookTypeSupport.CATEGORY_NOVEL && inferredType && existing.type !== inferredType) {
          existing.type = inferredType;
          bookChanged = true;
        }
        const nextCoverUrl = CoverUrlNormalizer.prefer(this.coverUrl, existing.coverUrl);
        if (nextCoverUrl && existing.coverUrl !== nextCoverUrl) {
          existing.coverUrl = nextCoverUrl;
          bookChanged = true;
        }
        if (this.mergeResolvedDetailIntoBook(existing)) {
          bookChanged = true;
        }
        const typeBefore = existing.type;
        const variableBefore = existing.variable;
        this.ensureMediaCategory(existing, knownCategory);
        if (existing.type !== typeBefore || existing.variable !== variableBefore) {
          bookChanged = true;
        }
        if (bookChanged) {
          await db.updateBook(existing, true, 'prepare_read_update_existing');
          AppStorage.setOrCreate('shelfUpdateTime', Date.now());
        }
        this.syncStateFromBook(existing);
        if (SearchExplorePendingBook.isPendingAddToShelf(existing)) {
          this.isInShelf = false;
          this.promptAddToShelfAfterRead = this.promptAddToShelfOnBackFromResult;
          this.pendingAddToShelfBookUrl = existing.bookUrl;
        } else {
          this.isInShelf = true;
          this.promptAddToShelfAfterRead = false;
          this.pendingAddToShelfBookUrl = '';
        }
        return true;
      }

      const book = await this.buildBookForShelf();
      const resolvedExisting = await this.findShelfBookByKey(BookIdentity.keyOfBook(book), true);
      if (resolvedExisting) {
        const resolvedTypeBefore = resolvedExisting.type;
        const resolvedVariableBefore = resolvedExisting.variable;
        const resolvedMerged = this.mergeResolvedDetailIntoBook(resolvedExisting);
        this.ensureMediaCategory(resolvedExisting, BookTypeSupport.mediaCategoryOf(book));
        if (resolvedMerged || resolvedExisting.type !== resolvedTypeBefore ||
          resolvedExisting.variable !== resolvedVariableBefore) {
          await db.updateBook(resolvedExisting, true, 'prepare_read_update_resolved');
          AppStorage.setOrCreate('shelfUpdateTime', Date.now());
        }
        this.syncStateFromBook(resolvedExisting);
        if (SearchExplorePendingBook.isPendingAddToShelf(resolvedExisting)) {
          this.isInShelf = false;
          this.promptAddToShelfAfterRead = this.promptAddToShelfOnBackFromResult;
          this.pendingAddToShelfBookUrl = resolvedExisting.bookUrl;
        } else {
          this.isInShelf = true;
          this.promptAddToShelfAfterRead = false;
          this.pendingAddToShelfBookUrl = '';
        }
        return true;
      }
      SearchExplorePendingBook.markPendingAddToShelf(book);
      await db.insertBook(book, 'temporary_read_insert');
      this.syncStateFromBook(book);
      this.isInShelf = false;
      this.promptAddToShelfAfterRead = this.promptAddToShelfOnBackFromResult;
      this.pendingAddToShelfBookUrl = book.bookUrl;
      AppStorage.setOrCreate('shelfUpdateTime', Date.now());
      return true;
    } catch (e) {
      console.error('准备阅读失败:', e);
      HdsFeedback.showToast('打开阅读失败');
      return false;
    } finally {
      this.isSaving = false;
    }
  }

  private mergeResolvedDetailIntoBook(book: Book): boolean {
    let changed = false;
    const kind = BookFieldSanitizer.prefer(this.kind, book.kind);
    const status = BookFieldSanitizer.prefer(this.status, book.status);
    const intro = BookFieldSanitizer.prefer(this.intro, book.intro);
    const latestChapterTitle = BookFieldSanitizer.prefer(this.latestChapterTitle, book.latestChapterTitle);
    const wordCount = BookFieldSanitizer.prefer(this.wordCount, book.wordCount);
    const updateTime = BookFieldSanitizer.prefer(this.updateTime, book.updateTime);
    if (kind !== book.kind) {
      book.kind = kind;
      changed = true;
    }
    if (status !== book.status) {
      book.status = status;
      changed = true;
    }
    if (intro !== book.intro) {
      book.intro = intro;
      changed = true;
    }
    if (latestChapterTitle !== book.latestChapterTitle) {
      book.latestChapterTitle = latestChapterTitle;
      changed = true;
    }
    if (wordCount !== book.wordCount) {
      book.wordCount = wordCount;
      changed = true;
    }
    if (updateTime !== book.updateTime) {
      book.updateTime = updateTime;
      changed = true;
    }
    if (this.tocUrl && this.tocUrl !== book.tocUrl) {
      book.tocUrl = this.tocUrl;
      changed = true;
    }
    if (this.bookVariable && this.bookVariable !== book.variable) {
      book.variable = this.bookVariable;
      changed = true;
    }
    return changed;
  }

  async buildBookForShelf(): Promise<Book> {
    const book = new Book();
    book.bookUrl = this.bookUrl;
    book.tocUrl = this.tocUrl;
    book.origin = this.origin;
    book.originName = this.originName;
    book.name = this.name;
    book.author = this.author;
    book.kind = BookFieldSanitizer.clean(this.kind);
    book.status = BookFieldSanitizer.clean(this.status);
    book.coverUrl = CoverUrlNormalizer.normalize(this.coverUrl);
    book.intro = BookFieldSanitizer.clean(this.intro);
    book.latestChapterTitle = BookFieldSanitizer.clean(this.latestChapterTitle);
    book.wordCount = BookFieldSanitizer.clean(this.wordCount);
    book.group = -2147483645;
    book.type = this.bookType;
    book.variable = this.bookVariable;
    BookTypeSupport.applyBookType(book);
    book.canUpdate = true;
    book.lastCheckTime = Date.now();
    book.latestChapterTime = Date.now();
    const fallbackCoverUrl = book.coverUrl;
    const fullBook = await this.resolveBookInfo();
    if (fullBook) {
      book.bookUrl = fullBook.bookUrl || book.bookUrl;
      book.tocUrl = fullBook.tocUrl || book.tocUrl;
      book.name = fullBook.name || book.name;
      book.author = fullBook.author || book.author;
      book.kind = BookFieldSanitizer.prefer(fullBook.kind, book.kind);
      book.status = BookFieldSanitizer.prefer(fullBook.status, book.status);
      book.coverUrl = CoverUrlNormalizer.prefer(fallbackCoverUrl, fullBook.coverUrl || book.coverUrl);
      book.intro = BookFieldSanitizer.prefer(fullBook.intro, book.intro);
      book.latestChapterTitle = BookFieldSanitizer.prefer(fullBook.latestChapterTitle, book.latestChapterTitle);
      book.updateTime = BookFieldSanitizer.prefer(fullBook.updateTime, book.updateTime);
      book.wordCount = BookFieldSanitizer.prefer(fullBook.wordCount, book.wordCount);
      book.variable = fullBook.variable || book.variable;
      book.type = fullBook.type || book.type;
    }
    // 类型以书源详情为准；是有声/漫画/视频时在 variable 里写入 tab，阅读页据此转到听书/漫画/播放页。
    this.ensureMediaCategory(book, BookTypeSupport.mediaCategoryOf(book));
    return book;
  }

  /**
   * 让书籍记录与已知类型一致：有声/漫画补类型标记位，并在 variable 里写入 tab
   * （阅读页按 variable 的 tab 优先定类型）；视频在 variable 里写入 tab=video。小说不做处理。
   */
  private ensureMediaCategory(target: Book, category: string): void {
    let tab = '';
    let bit = 0;
    if (category === BookTypeSupport.CATEGORY_AUDIO) {
      tab = 'audio';
      bit = BookTypeSupport.AUDIO;
    } else if (category === BookTypeSupport.CATEGORY_COMIC) {
      tab = 'comic';
      bit = BookTypeSupport.IMAGE;
    } else if (category === BookTypeSupport.CATEGORY_VIDEO) {
      tab = 'video';
    }
    if (!tab) return;
    if (bit) {
      target.type = (target.type & ~(BookTypeSupport.TEXT | BookTypeSupport.AUDIO | BookTypeSupport.IMAGE)) | bit;
    }
    if (BookTypeSupport.typeFromVariable(target.variable) !== bit || category === BookTypeSupport.CATEGORY_VIDEO) {
      const merged = SearchBookDetailPage.mergeVariableTab(target.variable, tab);
      if (merged) target.variable = merged;
    }
  }

  @Builder
  addToShelfOnBackDialogContent() {
    Column({ space: AppSpacing.LG }) {
      Text('加入书架')
        .fontSize(AppFontSize.SUBTITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .width('100%')

      Text(`是否将《${this.name || '这本书'}》加入书架？`)
        .fontSize(AppFontSize.BODY)
        .fontColor(this.secondaryTextColor())
        .width('100%')

      Row({ space: AppSpacing.MD }) {
        Button('不加入')
          .layoutWeight(1)
          .height(42)
          .fontSize(AppFontSize.BODY_LARGE)
          .backgroundColor(this.inputColor())
          .fontColor(this.primaryTextColor())
          .onClick(() => {
            this.dismissAddToShelfOnBackPrompt();
          })

        Button('加入书架')
          .layoutWeight(1)
          .height(42)
          .fontSize(AppFontSize.BODY_LARGE)
          .backgroundColor(this.buttonColor())
          .fontColor(ThemeRuntime.onAccentColor())
          .onClick(() => {
            this.confirmAddToShelfOnBack();
          })
      }
      .width('100%')
      .margin({ top: AppSpacing.XS })
    }
    .padding(AppSpacing.XXXL)
  }

  @Builder
  authorSearchDialogContent() {
    Column({ space: AppSpacing.LG }) {
      Text('作者检索')
        .fontSize(AppFontSize.SUBTITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .width('100%')

      Text(`是否以作者“${this.author}”为关键词发起搜索？`)
        .fontSize(AppFontSize.BODY)
        .fontColor(this.secondaryTextColor())
        .width('100%')

      Row({ space: AppSpacing.MD }) {
        Button('取消')
          .layoutWeight(1)
          .height(42)
          .fontSize(AppFontSize.BODY_LARGE)
          .backgroundColor(this.inputColor())
          .fontColor(this.primaryTextColor())
          .onClick(() => {
            this.closeAuthorSearchDialog();
          })

        Button('搜索')
          .layoutWeight(1)
          .height(42)
          .fontSize(AppFontSize.BODY_LARGE)
          .backgroundColor(this.buttonColor())
          .fontColor(ThemeRuntime.onAccentColor())
          .onClick(() => {
            this.confirmAuthorSearch();
          })
      }
      .width('100%')
      .margin({ top: AppSpacing.XS })
    }
    .padding(AppSpacing.XXXL)
  }

  @Builder
  changeSourceConfirmDialogContent() {
    Column({ space: AppSpacing.LG }) {
      Text('换源')
        .fontSize(AppFontSize.SUBTITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .width('100%')

      Text(`是否为《${this.name || '这本书'}》搜索可切换的书源？`)
        .fontSize(AppFontSize.BODY)
        .fontColor(this.secondaryTextColor())
        .width('100%')

      Row({ space: AppSpacing.MD }) {
        Button('取消')
          .layoutWeight(1)
          .height(42)
          .fontSize(AppFontSize.BODY_LARGE)
          .backgroundColor(this.inputColor())
          .fontColor(this.primaryTextColor())
          .onClick(() => {
            this.closeChangeSourceDialog();
          })

        Button('换源')
          .layoutWeight(1)
          .height(42)
          .fontSize(AppFontSize.BODY_LARGE)
          .backgroundColor(this.buttonColor())
          .fontColor(ThemeRuntime.onAccentColor())
          .onClick(() => {
            this.confirmChangeSource();
          })
      }
      .width('100%')
      .margin({ top: AppSpacing.XS })
    }
    .padding(AppSpacing.XXXL)
  }

  async findShelfBookByKey(bookKey: string, includePending: boolean = false): Promise<Book | null> {
    return SearchBookShelfHelper.findShelfBookByKey(bookKey, includePending);
  }

  syncStateFromBook(book: Book): void {
    this.bookUrl = book.bookUrl || this.bookUrl;
    this.tocUrl = book.tocUrl || this.tocUrl;
    this.origin = book.origin || this.origin;
    this.originName = book.originName || this.originName;
    this.name = book.name || this.name;
    this.author = book.author || this.author;
    this.kind = book.kind || this.kind;
    this.status = book.status || this.status;
    this.coverUrl = CoverUrlNormalizer.prefer(book.coverUrl, this.coverUrl);
    this.intro = book.intro || this.intro;
    this.latestChapterTitle = book.latestChapterTitle || this.latestChapterTitle;
    this.wordCount = book.wordCount || this.wordCount;
    this.updateTime = book.updateTime || this.updateTime;
    this.bookType = book.type || this.bookType;
    this.bookVariable = book.variable || this.bookVariable;
    this.bookInfoRenderVersion++;
  }

  /** 在 variable 里补上 tab，保留其余字段（目录等规则可能依赖它们）；不是 JSON 对象时返回空串。 */
  private static mergeVariableTab(variable: string, tab: string): string {
    try {
      const record = (variable ? JSON.parse(variable) : {}) as Record<string, Object>;
      if (record === null || typeof record !== 'object' || Array.isArray(record)) return '';
      record['tab'] = tab;
      return JSON.stringify(record);
    } catch (_) {
      return '';
    }
  }

  detailTypeProbe(): Book {
    const book = new Book();
    book.origin = this.origin;
    book.originName = this.originName;
    book.kind = this.kind;
    book.type = this.bookType;
    book.variable = this.bookVariable;
    return book;
  }

  /**
   * The catalog card shows a chapter count that only exists after the catalog has been fetched at
   * least once. Prefer the stored column and fall back to counting the cached chapter rows.
   */
  private async refreshChapterCount(): Promise<void> {
    if (!this.bookUrl) return;
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      const book = await db.getBook(this.bookUrl);
      const stored = book ? book.totalChapterNum : 0;
      this.totalChapterNum = stored > 0 ? stored : await db.getBookChapterCount(this.bookUrl);
    } catch (e) {
      console.warn('读取章节总数失败:', e);
    }
  }

  openChapterList(): void {
    if (!this.bookUrl || !this.origin) {
      HdsFeedback.showToast('书籍信息不完整，暂时无法查看目录');
      return;
    }
    this.showCatalogSheet = true;
  }

  /**
   * 目录面板里点中某一章。先走与"开始阅读"相同的入库流程（未上架时写临时阅读书并保留
   * 返回时的加入书架提示），再把进度指到该章。
   */
  async openChapterFromCatalog(chapter: BookChapter): Promise<void> {
    if (this.openingCatalogChapter || chapter.index < 0) return;
    this.openingCatalogChapter = true;
    try {
      const ok = await this.prepareBookForReading();
      if (!ok) return;
      const db = AppDatabase.getInstance();
      const book = await db.getBook(this.bookUrl);
      if (!book) {
        HdsFeedback.showToast('打开章节失败');
        return;
      }
      // The reader derives its opening chapter from durChapterIndex alone (see
      // ReadBookEngine.openBookFresh / applyLatestReadingProgress). durChapterPos must be reset
      // too: savedReaderProgressOffset only matches on chapter, so a stale page would land
      // somewhere inside the target chapter.
      book.durChapterIndex = chapter.index;
      book.durChapterPos = 0;
      book.durChapterTitle = chapter.title;
      await db.updateBook(book, true, 'open_chapter_from_catalog_sheet');
      this.showCatalogSheet = false;
      if (BookTypeSupport.isVideo(book)) {
        // 视频类书籍没有阅读形态，点哪一集就直接播放哪一集。
        await VideoBookPlayer.open(book.bookUrl, chapter.index);
        return;
      }
      await router.pushUrl({
        url: 'pages/ReadBook',
        params: { bookUrl: book.bookUrl }
      });
    } catch (e) {
      console.error('打开章节失败:', e);
      HdsFeedback.showToast('打开章节失败');
    } finally {
      this.openingCatalogChapter = false;
    }
  }

  async startRead(): Promise<void> {
    if (this.openingReader || this.isSaving || this.openingCatalogChapter) return;
    this.openingReader = true;
    try {
      const ok = await this.prepareBookForReading();
      if (!ok) return;

      if (BookTypeSupport.isVideo(this.detailTypeProbe())) {
        await this.startWatch();
        return;
      }

      // 从目录进入详情后，继续阅读同一本书直接回到原阅读页，保留分页和当前位置。
      if (this.readerBookUrl && this.readerBookUrl === this.bookUrl &&
        !BookTypeSupport.isAudio(this.detailTypeProbe())) {
        router.back();
        return;
      }

      await router.pushUrl({
        url: BookTypeSupport.isAudio(this.detailTypeProbe()) ? 'pages/AudioBook' : 'pages/ReadBook',
        params: { bookUrl: this.bookUrl }
      });
    } catch (error) {
      console.error('打开阅读失败:', error);
      HdsFeedback.showToast('打开阅读失败');
    } finally {
      this.openingReader = false;
    }
  }

  /** 视频类书籍：进入播放页，接着上次看到的那一集；选集由播放页自己加载。 */
  async startWatch(): Promise<void> {
    try {
      await VideoBookPlayer.open(this.bookUrl);
    } catch (e) {
      console.warn('打开播放页失败:', e);
      HdsFeedback.showToast('打开播放页失败');
    }
  }

  triggerAutoStartRead(): void {
    if (!this.autoStartRead || this.autoStartReadTriggered || !this.bookUrl) return;
    this.autoStartReadTriggered = true;
    // Let the detail page mount before preparing the transient reader record and routing to ReadBook.
    setTimeout((): void => {
      this.startRead();
    }, 0);
  }

  getTags(): string[] {
    return BookDisplayHelper.splitTags(this.kind, this.status);
  }

  /** 字数、更新时间这类中性信息标签：同样的沉浸光感胶囊，用输入框底色染色。 */
  neutralTagModifier(): GlassTagModifier {
    return new GlassTagModifier(this.appDarkMode);
  }

  @Builder
  tagChip(tag: string, index: number) {
    Text(tag)
      .fontSize(AppFontSize.BODY)
      .fontColor(BookDisplayHelper.getTagTextColor(index, this.appDarkMode))
      .padding({ left: AppSpacing.MD, right: AppSpacing.MD, top: AppSpacing.XS, bottom: AppSpacing.XS })
      .attributeModifier(BookDisplayHelper.getGlassTagModifier(index, this.appDarkMode))
      .margin({ right: AppSpacing.MD, bottom: AppSpacing.MD })
  }

  @Builder
  coverView(width: number, height: number) {
    BookCover({
      bookUrl: this.bookUrl, origin: this.origin, coverUrl: this.coverUrl, name: this.name, author: this.author,
      useBookshelfCover: this.searchExploreUseBookshelfCoverGallery,
      placeholderColor: this.accentColor(), cornerRadius: 8,
      onReadyCover: (url: ResourceStr): void => { this.readyCoverUrl = url; }
    })
      .width(width)
      .height(height)
  }

  pageColor(): string {
    return ThemeRuntime.pageColor(this.appDarkMode);
  }

  cardColor(): string {
    return ThemeRuntime.cardColor(this.appDarkMode);
  }

  inputColor(): string {
    return ThemeRuntime.inputColor(this.appDarkMode);
  }

  primaryTextColor(): string {
    return ThemeRuntime.primaryTextColor(this.appDarkMode);
  }

  secondaryTextColor(): string {
    return ThemeRuntime.subTextColor(this.appDarkMode);
  }

  subTextColor(): string {
    return ThemeRuntime.subTextColor(this.appDarkMode);
  }

  buttonColor(): string {
    return ThemeRuntime.buttonColor(this.appDarkMode);
  }

  accentColor(): string {
    return ThemeRuntime.accentColor(this.appDarkMode);
  }

  syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, this.pageColor());
  }
}
