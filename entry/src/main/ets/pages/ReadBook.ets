import { router, window } from '@kit.ArkUI';
import { inputConsumer, KeyCode, Action, KeyEvent } from '@kit.InputKit';
import { Book, BookChapter } from '../model/data/Book';
import { AppDatabase } from '../model/data/AppDatabase';
import { ReadBookEngine } from '../core/book/ReadBookEngine';

@Entry
@Component
struct ReadBookPage {
  @State bookUrl: string = '';
  @State book: Book | null = null;
  @State chapters: BookChapter[] = [];
  @State currentChapterIndex: number = 0;
  @State content: string = '';
  @State isLoading: boolean = false;
  @State showMenu: boolean = false;
  @State showToc: boolean = false;
  @State showSettings: boolean = false;
  @State loadStatus: string = '';
  @State verificationUrl: string = '';
  @State verificationTitle: string = '网页验证';
  @State contentPages: string[] = [];
  @State currentPageIndex: number = 0;
  @State pageViewWidth: number = 0;
  @State pageViewHeight: number = 0;
  @State statusBarSafeHeight: number = 0;
  private pendingRestorePageIndex: number = -1;
  private pendingRestoreScrollOffset: number = -1;
  private currentScrollOffset: number = 0;
  private contentScroller: Scroller = new Scroller();
  @State pageTransitionX: number = 0;
  @State pageTransitionOpacity: number = 1;
  @State pageFlipOffsetX: number = 0;
  @State pageFlipAngle: number = 0;
  @State pageFlipShadeOpacity: number = 0;
  private isPageTurning: boolean = false;
  private isAutoLoadingScrollChapter: boolean = false;
  private suppressScrollReachStart: boolean = false;
  @StorageLink('readerFontSize') @Watch('onReadLayoutChanged') readerFontSize: number = 20;
  @StorageLink('readerLineHeight') @Watch('onReadLayoutChanged') readerLineHeight: number = 32;
  @StorageLink('readerParagraphSpacing') @Watch('onReadLayoutChanged') readerParagraphSpacing: number = 10;
  @StorageLink('readerThemeIndex') @Watch('onReaderThemeChanged') readerThemeIndex: number = 0;
  @StorageLink('readerPageTurnMode') readerPageTurnMode: number = 1;
  @StorageLink('readerTapTurnPage') readerTapTurnPage: boolean = true;
  @StorageLink('readerVolumeTurnPage') @Watch('onReaderVolumeTurnPageChanged') readerVolumeTurnPage: boolean = false;
  @StorageLink('readerKeepScreenOn') readerKeepScreenOn: boolean = true;
  @StorageLink('readerExtendToStatusBar') @Watch('onReaderExtendToStatusBarChanged') readerExtendToStatusBar: boolean = false;
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  private themeBackgrounds: string[] = ['#F6F0E5', '#F5F5F5', '#E8F1EA', '#1F1F1F'];
  private themeTextColors: string[] = ['#2F261D', '#333333', '#26352A', '#D8D8D8'];
  private volumeUpCallback?: (event: KeyEvent) => void;
  private volumeDownCallback?: (event: KeyEvent) => void;

  aboutToAppear() {
    this.enterReaderImmersive();
    this.updateVolumeKeySubscription();
    const params = router.getParams() as Record<string, string>;
    if (params && params['bookUrl']) {
      this.bookUrl = params['bookUrl'];
      this.loadBook();
    }
  }

  aboutToDisappear() {
    this.saveReadingProgress();
    this.unregisterVolumeKeyTurn();
    this.exitReaderImmersive();
  }

  enterReaderImmersive() {
    window.getLastWindow(getContext(this)).then((mainWindow: window.Window) => {
      const bg = this.getBackgroundColor();
      mainWindow.setWindowBackgroundColor(bg);
      mainWindow.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        isStatusBarLightIcon: this.appDarkMode || this.readerThemeIndex === 3,
        statusBarContentColor: (this.appDarkMode || this.readerThemeIndex === 3) ? '#D8D8D8' : '#2F261D',
        navigationBarColor: bg,
        isNavigationBarLightIcon: this.appDarkMode || this.readerThemeIndex === 3,
        navigationBarContentColor: (this.appDarkMode || this.readerThemeIndex === 3) ? '#D8D8D8' : '#2F261D'
      });
      if (this.readerExtendToStatusBar) {
        mainWindow.setWindowLayoutFullScreen(true);
        mainWindow.setWindowSystemBarEnable(['navigation']);
        this.updateStatusBarSafeHeight(mainWindow);
      } else {
        mainWindow.setWindowLayoutFullScreen(true);
        mainWindow.setWindowSystemBarEnable(['navigation', 'status']);
        this.updateStatusBarSafeHeight(mainWindow);
      }
    }).catch((err: Error) => {
      console.error('进入阅读沉浸模式失败:', err);
    });
  }

  exitReaderImmersive() {
    window.getLastWindow(getContext(this)).then((mainWindow: window.Window) => {
      mainWindow.setWindowLayoutFullScreen(true);
      mainWindow.setWindowSystemBarEnable(['navigation', 'status']);
      this.statusBarSafeHeight = 0;
    }).catch((err: Error) => {
      console.error('退出阅读沉浸模式失败:', err);
    });
  }

  updateStatusBarSafeHeight(mainWindow: window.Window): void {
    try {
      const avoidArea = mainWindow.getWindowAvoidAreaIgnoringVisibility(window.AvoidAreaType.TYPE_SYSTEM);
      const topHeight = px2vp(Math.max(0, avoidArea.topRect.height));
      this.statusBarSafeHeight = topHeight > 0 ? topHeight : 32;
    } catch (err) {
      console.error('获取状态栏安全区失败:', err);
      this.statusBarSafeHeight = 32;
    }
  }

  async loadBook() {
    this.isLoading = true;
    this.loadStatus = '正在加载...';
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      
      this.book = await db.getBook(this.bookUrl);
      if (!this.book) {
        this.content = '书籍不存在，请先从搜索结果加入书架。';
        this.isLoading = false;
        return;
      }
      await this.markBookRecentlyRead();

      const engine = ReadBookEngine.get();
      await engine.openBook(this.book);
      this.chapters = engine.chapters;
      this.currentChapterIndex = this.clampChapterIndex(engine.curIdx);
      if (this.readerPageTurnMode === 0) {
        this.pendingRestoreScrollOffset = Math.max(0, engine.curPos);
      } else {
        this.pendingRestorePageIndex = Math.max(0, engine.curPos);
      }
      this.readerThemeIndex = Math.max(0, Math.min(this.readerThemeIndex, this.themeBackgrounds.length - 1));

      if (this.chapters.length > 0) {
        await this.loadContent();
      } else if (this.book.origin !== 'local' && this.book.origin) {
        this.content = `《${this.book.name}》\n\n作者：${this.book.author || '未知'}\n来源：${this.book.originName || this.book.origin}\n\n正在尝试解析目录...`;
        this.loadStatus = '正在获取目录...';
        await this.retryFetchChapters();
      } else {
        this.content = this.buildBookPreview();
        this.isLoading = false;
      }
    } catch (e) {
      console.error('加载书籍失败:', e);
      this.content = '加载失败,请重试';
      this.isLoading = false;
    } finally {
      this.updatePendingVerification();
    }
  }

  async retryFetchChapters() {
    try {
      const engine = ReadBookEngine.get();
      await engine.refreshToc();
      this.chapters = engine.chapters;
      if (this.chapters.length > 0) {
        this.loadStatus = '';
        await this.loadContent();
      } else {
        this.updatePendingVerification();
        this.content = this.buildBookPreview();
        this.isLoading = false;
      }
    } catch (e) {
      console.error('重试获取目录失败:', e);
      this.updatePendingVerification();
      this.content = this.buildBookPreview();
      this.isLoading = false;
    }
  }

  async loadContent(silent: boolean = false) {
    if (this.chapters.length === 0) {
      this.content = this.buildBookPreview();
      this.isLoading = false;
      return;
    }
    
    const engine = ReadBookEngine.get();
    const showLoading = !silent && !engine.hasCachedContent(this.currentChapterIndex);
    if (showLoading) {
      this.isLoading = true;
      this.loadStatus = '正在加载章节内容...';
    }
    try {
      const body = await engine.loadContent(this.currentChapterIndex);
      if (body) {
        this.content = body;
      } else {
        this.updatePendingVerification();
        const c = this.chapters[this.currentChapterIndex];
        this.content = this.verificationUrl ? `${c ? c.title : '当前章节'}\n\n该书源需要先完成网页验证。请点击阅读菜单里的「验证」，完成后返回并重试。` :
          (c ? `${c.title}\n\n章节内容加载失败，请稍后重试或尝试换源。` : '加载失败');
      }
      this.paginateContent();
      this.preloadReaderContent();
    } catch (e) {
      console.error('加载内容失败:', e);
    } finally {
      if (showLoading) {
        this.isLoading = false;
        this.loadStatus = '';
      }
      this.updatePendingVerification();
    }
  }

  build() {
    Stack() {
      Column() {
        if (this.isLoading) {
          Column() {
            LoadingProgress()
              .width(40)
              .height(40)
            Text(this.loadStatus || '加载中...')
              .fontSize(14)
              .fontColor('#999')
              .margin({ top: 8 })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        } else if (this.readerPageTurnMode === 0) {
          Column() {
            Scroll(this.contentScroller) {
            Column() {
              Text(this.content)
                .fontSize(this.readerFontSize)
                .lineHeight(this.readerLineHeight)
                .fontColor(this.getTextColor())
                .padding({ left: 18, right: 18, top: 18, bottom: 24 + this.readerParagraphSpacing })
            }
            .width('100%')
            }
            .width('100%')
            .layoutWeight(1)
            .scrollBar(BarState.Off)
            .onScroll((xOffset: number, yOffset: number) => {
              this.currentScrollOffset = Math.max(0, yOffset);
            })
            .onScrollStop(() => {
              this.saveReadingProgress();
            })
            .onReachEnd(() => {
              this.loadNextChapterOnScrollEnd();
            })
            .onReachStart(() => {
              this.loadPrevChapterOnScrollStart();
            })

            this.readerBottomInfoBar()
          }
          .width('100%')
          .height('100%')
        } else {
          Column() {
            Stack() {
              Column() {
                Text(this.getCurrentPageText())
                  .fontSize(this.readerFontSize)
                  .lineHeight(this.readerLineHeight)
                  .fontColor(this.getTextColor())
                  .padding({ left: 18, right: 18, top: 18, bottom: 18 })
                  .width('100%')
              }
              .width('100%')
              .height('100%')
              .justifyContent(FlexAlign.Start)
              .alignItems(HorizontalAlign.Start)
              .translate({ x: this.pageTransitionX + this.pageFlipOffsetX })
              .opacity(this.pageTransitionOpacity)
              .rotate({
                x: 0,
                y: 1,
                z: 0,
                centerX: this.pageFlipOffsetX < 0 ? '0%' : '100%',
                centerY: '50%',
                perspective: 900,
                angle: `${this.pageFlipAngle}deg`
              })
              .shadow({
                radius: Math.abs(this.pageFlipOffsetX) > 1 ? 24 : 0,
                color: this.appDarkMode ? '#66000000' : '#26000000',
                offsetX: this.pageFlipOffsetX < 0 ? 12 : -12,
                offsetY: 0
              })

              if (this.readerPageTurnMode === 1 && this.pageFlipShadeOpacity > 0) {
                Blank()
                  .width('100%')
                  .height('100%')
                  .backgroundColor(this.pageFlipOffsetX < 0 ? '#000000' : '#FFFFFF')
                  .opacity(this.pageFlipShadeOpacity)
              }
            }
            .width('100%')
            .layoutWeight(1)
            .clip(true)
            .onAreaChange((oldValue: Area, newValue: Area) => {
              this.pageViewWidth = Number(newValue.width);
              this.pageViewHeight = Number(newValue.height);
              this.paginateContent();
            })

            this.readerBottomInfoBar()
          }
          .width('100%')
          .height('100%')
        }
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.getReaderTopSafePadding() })
      .backgroundColor(this.getBackgroundColor())
      .onClick(() => {
        if (this.showToc || this.showSettings) {
          return;
        }
        if (this.showMenu) {
          this.hideReaderPanels();
          return;
        }
        if (this.readerPageTurnMode === 0) {
          this.showMenu = true;
        }
      })
      .gesture(
        PanGesture({ direction: PanDirection.Horizontal })
          .onActionUpdate((event: GestureEvent) => {
            if (this.readerPageTurnMode !== 1 || this.showMenu || this.showToc || this.showSettings || this.chapters.length === 0) {
              return;
            }
            this.updateSlidePageEffect(event.offsetX);
          })
          .onActionEnd((event: GestureEvent) => {
            if (this.showMenu && !this.showToc && !this.showSettings) {
              this.hideReaderPanels();
              return;
            }
            if (this.readerPageTurnMode !== 1 || this.showToc || this.showSettings || this.chapters.length === 0) {
              return;
            }
            if (event.offsetX < -50) {
              this.turnNext();
            } else if (event.offsetX > 50) {
              this.turnPrev();
            } else {
              this.resetSlidePageEffect();
            }
          })
      )

      if (this.readerPageTurnMode !== 0 && !this.showMenu && !this.showToc && !this.showSettings) {
        this.readerTapLayer()
      }

      if (this.showMenu && !this.showToc && !this.showSettings) {
        this.menuDismissLayer()
      }

      if (this.showMenu) {
        Column() {
          Row() {
            Text('<')
              .fontSize(24)
              .width(40)
              .height(56)
              .textAlign(TextAlign.Center)
              .onClick(async () => {
                await this.saveReadingProgress();
                router.back();
              })

            Text(this.book?.name || '')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            // 重试按钮
            if (this.verificationUrl) {
              Button('验证')
                .height(36)
                .fontSize(14)
                .margin({ right: 8 })
                .onClick(() => {
                  this.openVerificationPage();
                })
            }

            if (this.chapters.length === 0 && this.book?.origin !== 'local') {
              Button('重试')
                .height(36)
                .fontSize(14)
                .onClick(() => {
                  this.hideReaderPanels();
                  this.retryFetchChapters();
                })
            }
          }
          .width('100%')
          .height(this.getTopOverlayHeight())
          .padding({ left: 16, right: 16, top: this.getTopControlSafePadding() })
          .backgroundColor('#66FFFFFF')
          .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .position({ x: 0, y: 0 })
      }

      if (this.showMenu && this.chapters.length > 0) {
        Column() {
          Row() {
            Text(this.getChapterTitle())
              .fontSize(14)
              .fontColor('#666')
              .layoutWeight(1)

            Text(`${this.currentChapterIndex + 1}/${this.chapters.length}`)
              .fontSize(14)
              .fontColor('#999')
          }
          .width('100%')
          .padding({ left: 16, right: 16 })

          Row() {
            Button('上一章')
              .fontSize(14)
              .layoutWeight(1)
              .margin({ right: 8 })
              .onClick(() => {
                this.turnPrev();
                this.hideReaderPanels();
              })

            Button('目录')
              .fontSize(14)
              .layoutWeight(1)
              .margin({ right: 8 })
              .onClick(() => {
                this.showToc = true;
                this.showMenu = false;
              })

            Button('下一章')
              .fontSize(14)
              .layoutWeight(1)
              .onClick(() => {
                this.turnNext();
                this.hideReaderPanels();
              })
          }
          .width('100%')
          .margin({ top: 16 })

          Row() {
            Button('设置')
              .fontSize(14)
              .layoutWeight(1)
              .margin({ right: 8 })
              .onClick(() => {
                this.showSettings = true;
                this.showMenu = false;
              })

            Button('刷新目录')
              .fontSize(14)
              .layoutWeight(1)
              .onClick(() => {
                this.hideReaderPanels();
                this.retryFetchChapters();
              })
          }
          .width('100%')
          .margin({ top: 10 })
        }
        .width('100%')
        .padding(16)
        .backgroundColor('#66FFFFFF')
        .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
        .position({ x: 0, y: '100%' })
        .translate({ y: '-100%' })
      }

      if (this.showToc) {
        Row() {
          Column() {
            Row() {
              Text('目录')
                .fontSize(20)
                .fontWeight(FontWeight.Bold)
                .layoutWeight(1)
              Button('关闭')
                .height(34)
                .fontSize(13)
                .borderRadius(17)
                .onClick(() => {
                  this.showToc = false;
                })
            }
            .width('100%')
            .height(this.getTopOverlayHeight())
            .padding({ left: 16, right: 16, top: this.getTopControlSafePadding() })

            List({ space: 2 }) {
              ForEach(this.chapters, (chapter: BookChapter, index: number) => {
                ListItem() {
                  Text(chapter.title)
                    .fontSize(15)
                    .fontColor(index === this.currentChapterIndex ? '#007DFF' : '#333333')
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')
                    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
                    .backgroundColor(index === this.currentChapterIndex ? '#11007DFF' : '#00000000')
                    .onClick(async () => {
                      this.currentChapterIndex = index;
                      this.currentPageIndex = 0;
                      this.pendingRestorePageIndex = 0;
                      this.currentScrollOffset = 0;
                      this.pendingRestoreScrollOffset = 0;
                      this.showToc = false;
                      this.showMenu = false;
                      await this.loadContent();
                      await this.saveReadingProgress();
                    })
                }
              })
            }
            .layoutWeight(1)
            .width('100%')
          }
          .width('82%')
          .height('100%')
          .backgroundColor('#FAFAFA')

          Blank()
            .layoutWeight(1)
            .height('100%')
            .onClick(() => {
              this.showToc = false;
            })
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
      }

      if (this.showSettings) {
        Column({ space: 14 }) {
          Row() {
            Text('阅读设置')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .layoutWeight(1)
            Button('完成')
              .height(34)
              .fontSize(13)
              .borderRadius(17)
              .onClick(() => {
                this.showSettings = false;
                this.saveReadConfig();
                this.hideReaderPanels();
              })
          }
          .width('100%')

          Row() {
            Text('字号')
              .fontSize(15)
              .layoutWeight(1)
            Button('-')
              .width(44)
              .height(36)
              .onClick(() => {
                this.readerFontSize = Math.max(16, this.readerFontSize - 1);
                this.readerLineHeight = Math.max(24, this.readerLineHeight - 1);
              })
            Text(`${this.readerFontSize}`)
              .fontSize(15)
              .width(48)
              .textAlign(TextAlign.Center)
            Button('+')
              .width(44)
              .height(36)
              .onClick(() => {
                this.readerFontSize = Math.min(30, this.readerFontSize + 1);
                this.readerLineHeight = Math.min(52, this.readerLineHeight + 1);
              })
          }
          .width('100%')

          Row() {
            Text('行距')
              .fontSize(15)
              .layoutWeight(1)
            Button('-')
              .width(44)
              .height(36)
              .onClick(() => {
                this.readerLineHeight = Math.max(24, this.readerLineHeight - 2);
              })
            Text(`${this.readerLineHeight}`)
              .fontSize(15)
              .width(48)
              .textAlign(TextAlign.Center)
            Button('+')
              .width(44)
              .height(36)
              .onClick(() => {
                this.readerLineHeight = Math.min(52, this.readerLineHeight + 2);
              })
          }
          .width('100%')

          Row({ space: 8 }) {
            this.pageTurnModeButton('滚动', 0)
            this.pageTurnModeButton('滑动', 1)
            this.pageTurnModeButton('点击', 2)
          }
          .width('100%')

          Row({ space: 10 }) {
            ForEach(this.themeBackgrounds, (bg: string, index: number) => {
              Text('')
                .width(42)
                .height(42)
                .borderRadius(21)
                .backgroundColor(bg)
                .border({
                  width: this.readerThemeIndex === index ? 3 : 1,
                  color: this.readerThemeIndex === index ? '#007DFF' : '#22000000'
                })
                .onClick(() => {
                  this.readerThemeIndex = index;
                })
            })
          }
          .width('100%')

          Row() {
            Column() {
              Text('正文扩展至状态栏')
                .fontSize(15)
                .fontColor('#333333')
              Text('开启后正文阅读区域会延伸到顶部状态栏安全区')
                .fontSize(12)
                .fontColor('#777777')
                .margin({ top: 4 })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            Toggle({ type: ToggleType.Switch, isOn: this.readerExtendToStatusBar })
              .onChange((checked: boolean) => {
                this.readerExtendToStatusBar = checked;
              })
          }
          .width('100%')
          .constraintSize({ minHeight: 56 })
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 18, bottom: 24 })
        .backgroundColor('#66FFFFFF')
        .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
        .position({ x: 0, y: '100%' })
        .translate({ y: '-100%' })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.getBackgroundColor())
    .expandSafeArea([SafeAreaType.SYSTEM], this.getReaderSafeAreaEdges())
  }

  getChapterTitle(): string {
    if (this.chapters.length === 0) return '暂无目录';
    const chapter = this.chapters[this.currentChapterIndex];
    return chapter ? chapter.title : '';
  }

  updatePendingVerification(): void {
    this.verificationUrl = AppStorage.get<string>('pendingVerificationUrl') || '';
    this.verificationTitle = AppStorage.get<string>('pendingVerificationTitle') || '网页验证';
  }

  openVerificationPage(): void {
    const url = this.verificationUrl || AppStorage.get<string>('pendingVerificationUrl') || '';
    if (!url) return;
    router.pushUrl({
      url: 'pages/VerifyWeb',
      params: {
        url: url,
        title: this.verificationTitle || '网页验证'
      }
    });
  }

  getProgressText(): string {
    if (this.chapters.length === 0) return '';
    if (this.readerPageTurnMode === 0 || this.contentPages.length === 0) {
      return `${this.currentChapterIndex + 1}/${this.chapters.length}`;
    }
    return `${this.currentChapterIndex + 1}/${this.chapters.length} · ${this.currentPageIndex + 1}/${this.contentPages.length}`;
  }

  getChapterInfoText(): string {
    if (this.chapters.length === 0) {
      return this.book?.name || '暂无目录';
    }
    return `${this.currentChapterIndex + 1}/${this.chapters.length} ${this.getChapterTitle()}`;
  }

  getPageInfoText(): string {
    if (this.readerPageTurnMode === 0 || this.contentPages.length === 0) {
      return '1/1';
    }
    return `${this.currentPageIndex + 1}/${this.contentPages.length}`;
  }

  getCurrentPageText(): string {
    if (this.contentPages.length === 0) {
      return this.content;
    }
    const pageIndex = Math.max(0, Math.min(this.currentPageIndex, this.contentPages.length - 1));
    return this.contentPages[pageIndex];
  }

  getBackgroundColor(): string {
    const index = this.appDarkMode ? 3 : this.readerThemeIndex;
    return this.themeBackgrounds[index] || this.themeBackgrounds[0];
  }

  getTextColor(): string {
    const index = this.appDarkMode ? 3 : this.readerThemeIndex;
    return this.themeTextColors[index] || this.themeTextColors[0];
  }

  getSubTextColor(): string {
    return (this.appDarkMode || this.readerThemeIndex === 3) ? '#888888' : '#7A6F63';
  }

  getReaderSafeAreaEdges(): SafeAreaEdge[] {
    return this.readerExtendToStatusBar ? [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM] : [SafeAreaEdge.BOTTOM];
  }

  getReaderTopSafePadding(): number {
    return this.readerExtendToStatusBar ? 0 : this.statusBarSafeHeight;
  }

  getTopControlSafePadding(): number {
    return Math.max(this.statusBarSafeHeight, 32);
  }

  getTopOverlayHeight(): number {
    return 56 + this.getTopControlSafePadding();
  }

  onReadLayoutChanged(): void {
    this.paginateContent();
    this.saveReadingProgress();
  }

  onReaderExtendToStatusBarChanged(): void {
    this.enterReaderImmersive();
    this.paginateContent();
    this.saveReadingProgress();
  }

  onReaderThemeChanged(): void {
    this.enterReaderImmersive();
    this.paginateContent();
    this.saveReadingProgress();
  }

  onReaderVolumeTurnPageChanged(): void {
    this.updateVolumeKeySubscription();
  }

  updateVolumeKeySubscription(): void {
    this.unregisterVolumeKeyTurn();
    if (!this.readerVolumeTurnPage) {
      return;
    }
    this.registerVolumeKeyTurn();
  }

  registerVolumeKeyTurn(): void {
    this.volumeUpCallback = (_event: KeyEvent) => {
      this.handleVolumeKeyTurn(-1);
    };
    this.volumeDownCallback = (_event: KeyEvent) => {
      this.handleVolumeKeyTurn(1);
    };
    try {
      inputConsumer.on('keyPressed', {
        key: KeyCode.KEYCODE_VOLUME_UP,
        action: Action.DOWN,
        isRepeat: false
      }, this.volumeUpCallback);
      inputConsumer.on('keyPressed', {
        key: KeyCode.KEYCODE_VOLUME_DOWN,
        action: Action.DOWN,
        isRepeat: false
      }, this.volumeDownCallback);
    } catch (err) {
      console.error('注册音量键翻页失败:', err);
      this.volumeUpCallback = undefined;
      this.volumeDownCallback = undefined;
    }
  }

  unregisterVolumeKeyTurn(): void {
    try {
      if (this.volumeUpCallback) {
        inputConsumer.off('keyPressed', this.volumeUpCallback);
      }
      if (this.volumeDownCallback) {
        inputConsumer.off('keyPressed', this.volumeDownCallback);
      }
    } catch (err) {
      console.error('取消音量键翻页失败:', err);
    }
    this.volumeUpCallback = undefined;
    this.volumeDownCallback = undefined;
  }

  handleVolumeKeyTurn(direction: number): void {
    if (!this.readerVolumeTurnPage || this.showMenu || this.showToc || this.showSettings || this.isLoading || this.chapters.length === 0) {
      return;
    }
    if (this.readerPageTurnMode === 0) {
      this.contentScroller.scrollPage({ next: direction > 0, animation: true });
      setTimeout(() => {
        this.saveReadingProgress();
      }, 260);
      return;
    }
    if (direction > 0) {
      this.turnNext();
    } else {
      this.turnPrev();
    }
  }

  clampChapterIndex(index: number): number {
    if (this.chapters.length === 0) return 0;
    return Math.max(0, Math.min(index, this.chapters.length - 1));
  }

  restorePendingPageIndex(): void {
    if (this.pendingRestorePageIndex < 0) {
      return;
    }
    const maxPage = Math.max(0, this.contentPages.length - 1);
    this.currentPageIndex = Math.max(0, Math.min(this.pendingRestorePageIndex, maxPage));
    this.pendingRestorePageIndex = -1;
  }

  canSaveReadingProgress(): boolean {
    return this.readerPageTurnMode === 0 || (this.pageViewWidth > 0 && this.pageViewHeight > 0 && this.contentPages.length > 0);
  }

  restorePendingScrollOffset(): void {
    if (this.pendingRestoreScrollOffset < 0) {
      return;
    }
    const yOffset = Math.max(0, this.pendingRestoreScrollOffset);
    this.currentScrollOffset = yOffset;
    this.pendingRestoreScrollOffset = -1;
    setTimeout(() => {
      this.contentScroller.scrollTo({ xOffset: 0, yOffset: yOffset });
    }, 0);
  }

  async saveReadingProgress() {
    if (!this.book || this.chapters.length === 0) {
      return;
    }
    if (!this.canSaveReadingProgress()) {
      return;
    }
    const engine = ReadBookEngine.get();
    const chapterIndex = this.clampChapterIndex(this.currentChapterIndex);
    const pageIndex = this.readerPageTurnMode === 0 ? Math.max(0, Math.round(this.currentScrollOffset)) : Math.max(0, Math.min(this.currentPageIndex, Math.max(0, this.contentPages.length - 1)));
    this.currentChapterIndex = chapterIndex;
    if (this.readerPageTurnMode !== 0) {
      this.currentPageIndex = pageIndex;
    }
    this.book.durChapterIndex = chapterIndex;
    this.book.durChapterPos = pageIndex;
    this.book.durChapterTitle = this.getChapterTitle();
    this.book.durChapterTime = Date.now();
    this.book.putVariable('lastReadTime', `${this.book.durChapterTime}`);
    engine.curIdx = chapterIndex;
    engine.curPos = pageIndex;
    engine.book = this.book;
    try {
      const db = AppDatabase.getInstance();
      await db.updateBook(this.book);
      AppStorage.setOrCreate('shelfUpdateTime', Date.now());
    } catch (e) {
      console.error('保存阅读进度失败:', e);
    }
  }

  async markBookRecentlyRead() {
    if (!this.book) {
      return;
    }
    this.book.putVariable('lastReadTime', `${Date.now()}`);
    try {
      const db = AppDatabase.getInstance();
      await db.updateBook(this.book);
      AppStorage.setOrCreate('shelfUpdateTime', Date.now());
    } catch (e) {
      console.error('更新最近阅读时间失败:', e);
    }
  }

  async saveReadConfig() {
    if (!this.book) return;
    this.book.setPageAnim(this.readerThemeIndex);
    try {
      const db = AppDatabase.getInstance();
      await db.updateBook(this.book);
    } catch (e) {
      console.error('保存阅读设置失败:', e);
    }
  }

  @Builder
  readerBottomInfoBar() {
    Row() {
      Text(this.getChapterInfoText())
        .fontSize(12)
        .fontColor(this.getSubTextColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)

      Text(this.getPageInfoText())
        .fontSize(12)
        .fontColor(this.getSubTextColor())
        .textAlign(TextAlign.End)
        .margin({ left: 12 })
    }
    .width('100%')
    .height(44)
    .padding({ left: 18, right: 18, top: 4, bottom: 0 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.getBackgroundColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  @Builder
  readerTapLayer() {
    Column() {
      if (this.readerPageTurnMode === 2 && this.readerTapTurnPage) {
        Blank()
          .width('100%')
          .layoutWeight(3)
          .onClick(() => {
            this.turnPrev();
          })

        Row() {
          Blank()
            .height('100%')
            .layoutWeight(1)
            .onClick(() => {
              this.turnPrev();
            })
          Blank()
            .height('100%')
            .layoutWeight(1)
            .onClick(() => {
              this.showMenu = true;
            })
          Blank()
            .height('100%')
            .layoutWeight(1)
            .onClick(() => {
              this.turnNext();
            })
        }
        .width('100%')
        .layoutWeight(4)

        Blank()
          .width('100%')
          .layoutWeight(3)
          .onClick(() => {
            this.turnNext();
          })
      } else {
        Blank()
          .width('100%')
          .height('100%')
          .onClick(() => {
            this.showMenu = true;
          })
          .gesture(
            PanGesture({ direction: PanDirection.Horizontal })
              .onActionUpdate((event: GestureEvent) => {
                if (this.readerPageTurnMode !== 1 || this.showToc || this.showSettings || this.chapters.length === 0) {
                  return;
                }
                this.updateSlidePageEffect(event.offsetX);
              })
              .onActionEnd((event: GestureEvent) => {
                if (this.readerPageTurnMode !== 1 || this.showToc || this.showSettings || this.chapters.length === 0) {
                  return;
                }
                if (event.offsetX < -50) {
                  this.turnNext();
                } else if (event.offsetX > 50) {
                  this.turnPrev();
                } else {
                  this.resetSlidePageEffect();
                }
              })
          )
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
  }

  @Builder
  pageTurnModeButton(title: string, mode: number) {
    Text(title)
      .fontSize(13)
      .fontColor(this.readerPageTurnMode === mode ? '#FFFFFF' : '#333333')
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .height(36)
      .borderRadius(18)
      .backgroundColor(this.readerPageTurnMode === mode ? '#007DFF' : '#EEF0F3')
      .onClick(() => {
        this.switchPageTurnMode(mode);
      })
  }

  switchPageTurnMode(mode: number) {
    if (this.readerPageTurnMode === mode) {
      return;
    }
    this.readerPageTurnMode = mode;
    this.currentPageIndex = 0;
    this.currentScrollOffset = 0;
    this.pendingRestorePageIndex = 0;
    this.pendingRestoreScrollOffset = 0;
    this.paginateContent();
    this.saveReadingProgress();
  }

  @Builder
  menuDismissLayer() {
    Blank()
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        this.hideReaderPanels();
      })
      .gesture(
        PanGesture({ direction: PanDirection.Horizontal })
          .onActionStart(() => {
            this.hideReaderPanels();
          })
      )
  }

  hideReaderPanels() {
    this.showMenu = false;
    this.showSettings = false;
  }

  paginateContent() {
    if (!this.content || this.pageViewWidth <= 0 || this.pageViewHeight <= 0) {
      this.contentPages = this.content ? [this.content] : [];
      if (this.readerPageTurnMode === 0) {
        this.currentPageIndex = 0;
        this.restorePendingScrollOffset();
      }
      return;
    }

    if (this.readerPageTurnMode === 0) {
      this.contentPages = this.content ? [this.content] : [];
      this.currentPageIndex = 0;
      this.restorePendingScrollOffset();
      return;
    }

    const horizontalPadding = 36;
    const verticalPadding = 36 + Math.ceil(Math.max(1, this.readerLineHeight) * 0.35);
    const availableWidth = Math.max(1, this.pageViewWidth - horizontalPadding);
    const availableHeight = Math.max(1, this.pageViewHeight - verticalPadding);
    const charsPerLine = Math.max(8, Math.floor(availableWidth / Math.max(1, this.readerFontSize)));
    const linesPerPage = Math.max(1, Math.floor(availableHeight / Math.max(1, this.readerLineHeight)));
    const charsPerPage = Math.max(60, charsPerLine * linesPerPage);
    const source = this.content.replace(/\r\n/g, '\n').replace(/\n{3,}/g, '\n\n');
    const pages: string[] = [];
    let start = 0;

    while (start < source.length) {
      let end = Math.min(source.length, start + charsPerPage);
      if (end < source.length) {
        const newline = source.lastIndexOf('\n', end);
        const sentence = Math.max(
          source.lastIndexOf('。', end),
          source.lastIndexOf('！', end),
          source.lastIndexOf('？', end)
        );
        if (newline > start + Math.floor(charsPerPage * 0.65)) {
          end = newline + 1;
        } else if (sentence > start + Math.floor(charsPerPage * 0.75)) {
          end = sentence + 1;
        }
      }
      pages.push(source.substring(start, end).trim());
      start = end;
    }

    this.contentPages = pages.length > 0 ? pages : [this.content];
    this.restorePendingPageIndex();
    if (this.currentPageIndex >= this.contentPages.length) {
      this.currentPageIndex = Math.max(0, this.contentPages.length - 1);
    }
  }

  async turnNext() {
    this.preloadReaderContent();
    await this.runPageTurnAnimation(1, this.readerPageTurnMode === 1 ? 'slide' : 'tap');
  }

  async turnPrev() {
    this.preloadReaderContent();
    await this.runPageTurnAnimation(-1, this.readerPageTurnMode === 1 ? 'slide' : 'tap');
  }

  preloadReaderContent(): void {
    if (this.chapters.length === 0) {
      return;
    }
    const engine = ReadBookEngine.get();
    engine.preloadAround(this.currentChapterIndex, 2, 1);
  }

  async loadNextChapterOnScrollEnd(): Promise<void> {
    if (this.readerPageTurnMode !== 0 || this.isLoading || this.isAutoLoadingScrollChapter) {
      return;
    }
    if (this.currentChapterIndex >= this.chapters.length - 1) {
      return;
    }
    this.isAutoLoadingScrollChapter = true;
    try {
      await this.saveReadingProgress();
      this.suppressScrollReachStart = true;
      await this.loadNextChapter();
      setTimeout(() => {
        this.contentScroller.scrollTo({ xOffset: 0, yOffset: 0 });
      }, 0);
    } finally {
      setTimeout(() => {
        this.isAutoLoadingScrollChapter = false;
        this.suppressScrollReachStart = false;
      }, 350);
    }
  }

  async loadPrevChapterOnScrollStart(): Promise<void> {
    if (this.readerPageTurnMode !== 0 || this.isLoading || this.isAutoLoadingScrollChapter || this.suppressScrollReachStart) {
      return;
    }
    if (this.currentChapterIndex <= 0) {
      return;
    }
    this.isAutoLoadingScrollChapter = true;
    try {
      await this.saveReadingProgress();
      await this.loadPrevChapter();
      setTimeout(() => {
        this.contentScroller.scrollTo({ xOffset: 0, yOffset: Number.MAX_SAFE_INTEGER });
      }, 0);
    } finally {
      setTimeout(() => {
        this.isAutoLoadingScrollChapter = false;
      }, 350);
    }
  }

  canTurnPage(direction: number): boolean {
    if (this.readerPageTurnMode === 0 || this.chapters.length === 0) {
      return false;
    }
    if (direction > 0) {
      return this.currentPageIndex < this.contentPages.length - 1 || this.currentChapterIndex < this.chapters.length - 1;
    }
    return this.currentPageIndex > 0 || this.currentChapterIndex > 0;
  }

  async applyPageTurn(direction: number): Promise<void> {
    if (direction > 0) {
      if (this.currentPageIndex < this.contentPages.length - 1) {
        this.currentPageIndex++;
        if (this.contentPages.length - this.currentPageIndex <= 3) {
          this.preloadReaderContent();
        }
        await this.saveReadingProgress();
      } else {
        await this.loadNextChapter();
      }
      return;
    }

    if (this.currentPageIndex > 0) {
      this.currentPageIndex--;
      if (this.currentPageIndex <= 2) {
        this.preloadReaderContent();
      }
      await this.saveReadingProgress();
    } else {
      await this.loadPrevChapter();
    }
  }

  async runPageTurnAnimation(direction: number, style: string): Promise<void> {
    if (this.isPageTurning || !this.canTurnPage(direction)) {
      this.resetSlidePageEffect();
      return;
    }

    this.isPageTurning = true;
    if (style === 'slide') {
      await this.runSlidePageTurn(direction);
    } else {
      await this.runTapPageTurn(direction);
    }
  }

  async runTapPageTurn(direction: number): Promise<void> {
    animateTo({ duration: 110, curve: Curve.EaseOut }, () => {
      this.pageTransitionX = direction > 0 ? -44 : 44;
      this.pageTransitionOpacity = 0.12;
    });
    setTimeout(async () => {
      await this.applyPageTurn(direction);
      this.pageTransitionX = direction > 0 ? 44 : -44;
      this.pageTransitionOpacity = 0.12;
      animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
        this.pageTransitionX = 0;
        this.pageTransitionOpacity = 1;
      });
      setTimeout(() => {
        this.isPageTurning = false;
      }, 190);
    }, 115);
  }

  async runSlidePageTurn(direction: number): Promise<void> {
    const width = this.getPageTurnWidth();
    animateTo({ duration: 150, curve: Curve.EaseIn }, () => {
      this.pageFlipOffsetX = direction > 0 ? -width : width;
      this.pageFlipAngle = direction > 0 ? -28 : 28;
      this.pageTransitionOpacity = 0.22;
      this.pageFlipShadeOpacity = 0.32;
    });
    setTimeout(async () => {
      await this.applyPageTurn(direction);
      this.pageFlipOffsetX = direction > 0 ? width * 0.2 : -width * 0.2;
      this.pageFlipAngle = direction > 0 ? 12 : -12;
      this.pageTransitionOpacity = 0.58;
      this.pageFlipShadeOpacity = 0.12;
      animateTo({ duration: 190, curve: Curve.EaseOut }, () => {
        this.pageFlipOffsetX = 0;
        this.pageFlipAngle = 0;
        this.pageTransitionOpacity = 1;
        this.pageFlipShadeOpacity = 0;
      });
      setTimeout(() => {
        this.isPageTurning = false;
      }, 200);
    }, 155);
  }

  updateSlidePageEffect(offsetX: number): void {
    if (this.isPageTurning) {
      return;
    }
    const width = this.getPageTurnWidth();
    const clamped = Math.max(-width * 0.68, Math.min(width * 0.68, offsetX));
    const progress = Math.min(1, Math.abs(clamped) / width);
    this.pageFlipOffsetX = clamped;
    this.pageFlipAngle = (clamped < 0 ? -1 : 1) * Math.min(24, progress * 34);
    this.pageTransitionOpacity = 1 - progress * 0.16;
    this.pageFlipShadeOpacity = progress * 0.28;
  }

  resetSlidePageEffect(): void {
    animateTo({ duration: 160, curve: Curve.EaseOut }, () => {
      this.pageFlipOffsetX = 0;
      this.pageFlipAngle = 0;
      this.pageTransitionOpacity = 1;
      this.pageFlipShadeOpacity = 0;
    });
  }

  getPageTurnWidth(): number {
    return Math.max(1, this.pageViewWidth > 0 ? this.pageViewWidth : 360);
  }

  buildBookPreview(): string {
    if (!this.book) return '';

    let text = `${this.book.name}\n\n作者：${this.book.author || '未知'}\n来源：${this.book.originName || this.book.origin}`;
    if (this.book.latestChapterTitle) {
      text += `\n最新章节：${this.book.latestChapterTitle}`;
    }
    if (this.book.intro) {
      text += `\n\n简介：${this.book.intro}`;
    }
    if (this.book.origin !== 'local') {
      this.updatePendingVerification();
      if (this.verificationUrl) {
        text += '\n\n当前书源需要先完成网页验证。请点击标题栏的「验证」按钮，完成后返回并点击「重试」。';
      } else {
        text += '\n\n当前书源暂未解析出目录，可以尝试点击标题栏的「重试」按钮重新获取，或在书源管理中为该书源补充目录规则。';
      }
    }
    return text;
  }

  async loadNextChapter() {
    if (this.currentChapterIndex < this.chapters.length - 1) {
      this.currentChapterIndex++;
      this.currentPageIndex = 0;
      this.pendingRestorePageIndex = 0;
      this.currentScrollOffset = 0;
      this.pendingRestoreScrollOffset = 0;
      await this.loadContent(true);
      await this.saveReadingProgress();
    }
  }

  async loadPrevChapter() {
    if (this.currentChapterIndex > 0) {
      this.currentChapterIndex--;
      this.pendingRestorePageIndex = Number.MAX_SAFE_INTEGER;
      this.currentScrollOffset = 0;
      this.pendingRestoreScrollOffset = 0;
      await this.loadContent(true);
      await this.saveReadingProgress();
    }
  }
}
