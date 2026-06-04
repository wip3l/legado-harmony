import { router, window, promptAction, MeasureOptions } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { inputConsumer, KeyCode, Action, KeyEvent } from '@kit.InputKit';
import graphicsText from '@ohos.graphics.text';
import { Book, BookChapter } from '../model/data/Book';
import { AppDatabase } from '../model/data/AppDatabase';
import { ReadBookEngine } from '../core/book/ReadBookEngine';
import { RecentReadShortcut } from '../utils/RecentReadShortcut';
import { RecentReadCardUpdater } from '../utils/RecentReadCardUpdater';
import { SystemTtsReader, TtsChunk } from '../utils/SystemTtsReader';

interface ReadTextSlice {
  text: string;
  start: number;
  end: number;
  highlighted: boolean;
  key: string;
}

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
  @State currentPageText: string = '';
  @State pageRenderVersion: number = 0;
  @State pageViewWidth: number = 0;
  @State pageViewHeight: number = 0;
  @State statusBarSafeHeight: number = 0;
  @State isTtsSpeaking: boolean = false;
  @State ttsDisplayText: string = '';
  @State ttsHighlightStart: number = -1;
  @State ttsHighlightEnd: number = -1;
  private pendingRestorePageIndex: number = -1;
  private pendingRestoreScrollOffset: number = -1;
  private currentScrollOffset: number = 0;
  private contentScroller: Scroller = new Scroller();
  private ttsReader: SystemTtsReader = new SystemTtsReader();
  private ttsAutoContinue: boolean = false;
  private ttsReadToken: number = 0;
  private ttsTextStartOffset: number = 0;
  private ttsAutoTurningPage: boolean = false;
  private ttsPendingTargetPageIndex: number = -1;
  private ttsPendingHighlightChunk: TtsChunk | null = null;
  private contentPageStarts: number[] = [];
  private contentPageEnds: number[] = [];
  private pagedContentText: string = '';
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
  @StorageLink('launchShortcutNonce') @Watch('onLaunchShortcutChanged') launchShortcutNonce: number = 0;
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
    this.stopTtsReading();
    this.ttsReader.shutdown();
    this.saveReadingProgress();
    this.unregisterVolumeKeyTurn();
    this.exitReaderImmersive();
  }

  onLaunchShortcutChanged(): void {
    this.openPendingShortcut();
  }

  async openPendingShortcut(): Promise<void> {
    if (!RecentReadShortcut.isPending()) {
      return;
    }
    await this.saveReadingProgress();
    try {
      await RecentReadShortcut.openPending(getContext(this));
      RecentReadShortcut.consume();
    } catch (e) {
      RecentReadShortcut.consume();
      console.error('打开最近阅读快捷项失败:', e);
    }
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
        this.chapters = [...engine.chapters];
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
              this.readingText(this.getPagedSourceText(), 24 + this.readerParagraphSpacing + this.getReaderContentBottomReserve())
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
                if (this.hasActiveTtsHighlight(this.currentPageText || this.getCurrentPageText())) {
                  this.readingText(this.currentPageText || this.getCurrentPageText(), 18 + this.getReaderContentBottomReserve())
                } else if (this.pageRenderVersion % 2 === 0) {
                  Text(this.currentPageText || this.getCurrentPageText())
                    .fontSize(this.readerFontSize)
                    .lineHeight(this.readerLineHeight)
                    .fontColor(this.getTextColor())
                    .padding({ left: 18, right: 18, top: 18, bottom: 18 + this.getReaderContentBottomReserve() })
                    .width('100%')
                } else {
                  Text(this.currentPageText || this.getCurrentPageText())
                    .fontSize(this.readerFontSize)
                    .lineHeight(this.readerLineHeight)
                    .fontColor(this.getTextColor())
                    .padding({ left: 18, right: 18, top: 18, bottom: 18 + this.getReaderContentBottomReserve() })
                    .width('100%')
                }
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
          .backgroundColor(this.readerSolidPanelColor())
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

            Button(this.isTtsSpeaking ? '停止朗读' : '朗读')
              .fontSize(14)
              .layoutWeight(1)
              .margin({ right: 8 })
              .onClick(() => {
                this.toggleTtsReading();
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
        .backgroundColor(this.readerSolidPanelColor())
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
                  Row({ space: 8 }) {
                    Text(chapter.title)
                      .fontSize(15)
                      .fontColor(this.getTocTitleColor(chapter, index))
                      .maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .layoutWeight(1)

                    if (chapter.cacheDate > 0) {
                      Text('已缓存')
                        .fontSize(11)
                        .fontColor(this.readerThemeIndex === 3 || this.appDarkMode ? '#7CC7A0' : '#1F8F55')
                        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                        .backgroundColor(this.readerThemeIndex === 3 || this.appDarkMode ? '#24382F' : '#E6F4EC')
                        .borderRadius(4)
                    }
                  }
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
          .backgroundColor(this.readerSolidPanelColor())

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
        .backgroundColor(this.readerSolidPanelColor())
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

  syncCurrentPageText(): void {
    this.currentPageText = this.getCurrentPageText();
    this.pageRenderVersion++;
  }

  getCurrentPageStartOffset(): number {
    return this.getPageStartOffset(this.currentPageIndex);
  }

  getPageStartOffset(pageIndex: number): number {
    if (this.contentPageStarts.length === 0) {
      return 0;
    }
    const index = Math.max(0, Math.min(pageIndex, this.contentPageStarts.length - 1));
    return Math.max(0, this.contentPageStarts[index]);
  }

  getPageEndOffset(pageIndex: number): number {
    if (this.contentPageEnds.length === 0) {
      return this.content.length;
    }
    const index = Math.max(0, Math.min(pageIndex, this.contentPageEnds.length - 1));
    return Math.max(this.getPageStartOffset(index), this.contentPageEnds[index]);
  }

  findPageIndexByOffset(offset: number): number {
    if (this.contentPageStarts.length === 0) {
      return Math.max(0, Math.min(this.currentPageIndex, Math.max(0, this.contentPages.length - 1)));
    }
    const sourceLength = this.pagedContentText ? this.pagedContentText.length : this.content.length;
    const clampedOffset = Math.max(0, Math.min(offset, Math.max(0, sourceLength - 1)));
    for (let i = 0; i < this.contentPageStarts.length; i++) {
      if (clampedOffset >= this.contentPageStarts[i] && clampedOffset < this.contentPageEnds[i]) {
        return i;
      }
      if (i < this.contentPageStarts.length - 1 &&
        clampedOffset >= this.contentPageEnds[i] && clampedOffset < this.contentPageStarts[i + 1]) {
        return i + 1;
      }
    }
    return Math.max(0, this.contentPageStarts.length - 1);
  }

  getBackgroundColor(): string {
    const index = this.appDarkMode ? 3 : this.readerThemeIndex;
    return this.themeBackgrounds[index] || this.themeBackgrounds[0];
  }

  getTextColor(): string {
    const index = this.appDarkMode ? 3 : this.readerThemeIndex;
    return this.themeTextColors[index] || this.themeTextColors[0];
  }

  getTocTitleColor(chapter: BookChapter, index: number): string {
    if (index === this.currentChapterIndex) {
      return '#007DFF';
    }
    if (chapter.cacheDate > 0) {
      return (this.appDarkMode || this.readerThemeIndex === 3) ? '#DDEFE5' : '#244B35';
    }
    return (this.appDarkMode || this.readerThemeIndex === 3) ? '#B8BDC7' : '#333333';
  }

  getSubTextColor(): string {
    return (this.appDarkMode || this.readerThemeIndex === 3) ? '#888888' : '#7A6F63';
  }

  readerGlassPanelColor(): string {
    return this.readerSolidPanelColor();
  }

  readerSolidPanelColor(): string {
    return (this.appDarkMode || this.readerThemeIndex === 3) ? '#191B1F' : '#FFFFFF';
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

  getReaderContentBottomReserve(): number {
    return Math.ceil(Math.max(12, this.readerLineHeight * 0.75));
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
    this.syncCurrentPageText();
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
      RecentReadCardUpdater.reload(getContext(this) as common.UIAbilityContext);
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
      RecentReadCardUpdater.reload(getContext(this) as common.UIAbilityContext);
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
    this.stopTtsReading();
    this.readerPageTurnMode = mode;
    this.currentPageIndex = 0;
    this.currentScrollOffset = 0;
    this.pendingRestorePageIndex = 0;
    this.pendingRestoreScrollOffset = 0;
    this.paginateContent();
    this.saveReadingProgress();
  }

  async toggleTtsReading(): Promise<void> {
    if (this.isTtsSpeaking) {
      this.stopTtsReading();
      promptAction.showToast({ message: '已停止朗读' });
      return;
    }
    await this.startTtsReadingFromCurrentPosition(true);
  }

  async startTtsReadingFromCurrentPosition(showToast: boolean): Promise<void> {
    const text = this.getTtsReadingText();
    if (!text) {
      this.finishTtsReading();
      if (showToast) {
        promptAction.showToast({ message: '当前没有可朗读内容' });
      }
      return;
    }
    const token = ++this.ttsReadToken;
    this.ttsAutoContinue = true;
    this.ttsDisplayText = this.getCurrentPageText();
    this.ttsHighlightStart = -1;
    this.ttsHighlightEnd = -1;
    try {
      await this.ttsReader.start(text, {
        onFinished: () => {
          this.continueTtsReading(token);
        },
        onError: (message: string) => {
          if (token !== this.ttsReadToken) {
            return;
          }
          this.finishTtsReading();
          promptAction.showToast({ message: message || '系统朗读失败' });
        },
        onChunkStart: (chunk: TtsChunk) => {
          if (token !== this.ttsReadToken) {
            return;
          }
          this.followTtsChunk(chunk);
        }
      });
      this.isTtsSpeaking = true;
      if (showToast) {
        promptAction.showToast({ message: this.readerPageTurnMode === 0 ? '开始连续朗读' : '开始连续朗读' });
      }
    } catch (error) {
      if (token !== this.ttsReadToken) {
        return;
      }
      this.finishTtsReading();
      promptAction.showToast({ message: '当前系统不支持朗读或 TTS 初始化失败' });
      console.error('启动系统 TTS 失败:', error);
    }
  }

  stopTtsReading(userCancelled: boolean = true): void {
    if (userCancelled) {
      this.ttsAutoContinue = false;
      this.ttsReadToken++;
    }
    this.ttsAutoTurningPage = false;
    this.ttsPendingTargetPageIndex = -1;
    this.ttsPendingHighlightChunk = null;
    if (!this.isTtsSpeaking && !this.ttsReader.isSpeaking()) {
      this.clearTtsHighlight();
      return;
    }
    this.ttsReader.stop();
    this.isTtsSpeaking = false;
    this.clearTtsHighlight();
  }

  async continueTtsReading(token: number): Promise<void> {
    if (token !== this.ttsReadToken || !this.ttsAutoContinue) {
      return;
    }
    const advanced = await this.advanceTtsReadingTarget();
    if (token !== this.ttsReadToken || !this.ttsAutoContinue) {
      return;
    }
    if (!advanced) {
      this.finishTtsReading();
      return;
    }
    await this.startTtsReadingFromCurrentPosition(false);
  }

  async advanceTtsReadingTarget(): Promise<boolean> {
    if (this.chapters.length === 0) {
      return false;
    }
    if (this.readerPageTurnMode === 0) {
      if (this.currentChapterIndex >= this.chapters.length - 1) {
        return false;
      }
      await this.loadNextChapter();
      setTimeout(() => {
        this.contentScroller.scrollTo({ xOffset: 0, yOffset: 0 });
      }, 0);
      return true;
    }

    if (this.currentPageIndex < this.contentPages.length - 1) {
      await this.runTtsPageTurnAnimation(1);
      return true;
    }
    if (this.currentChapterIndex < this.chapters.length - 1) {
      await this.runTtsPageTurnAnimation(1);
      return true;
    }
    return false;
  }

  finishTtsReading(): void {
    this.ttsAutoContinue = false;
    this.isTtsSpeaking = false;
    this.clearTtsHighlight();
  }

  clearTtsHighlight(): void {
    this.ttsDisplayText = '';
    this.ttsHighlightStart = -1;
    this.ttsHighlightEnd = -1;
    this.ttsTextStartOffset = 0;
  }

  getTtsReadingText(): string {
    if (this.readerPageTurnMode !== 0) {
      const start = this.getCurrentPageStartOffset();
      this.ttsTextStartOffset = start;
      const source = this.pagedContentText || this.getPagedSourceText();
      return source.substring(start);
    }
    this.ttsTextStartOffset = 0;
    return this.getPagedSourceText();
  }

  normalizeReaderText(text: string): string {
    return (text || '')
      .replace(/\r\n/g, '\n')
      .replace(/\n{3,}/g, '\n\n')
      .trim();
  }

  getPagedSourceText(): string {
    const title = this.getChapterTitle().trim();
    const sourceBody = this.stripDuplicatedChapterTitle(this.normalizeChapterBody(this.content || ''), title);
    const body = this.buildIndentedChapterBody(sourceBody);
    if (!title) {
      return body;
    }
    return `${title}\n\n${body}`;
  }

  normalizeChapterBody(text: string): string {
    return (text || '')
      .replace(/\r\n/g, '\n')
      .replace(/\n{3,}/g, '\n\n')
      .trim();
  }

  buildIndentedChapterBody(text: string): string {
    const normalized = this.normalizeChapterBody(text);
    if (!normalized) {
      return '';
    }
    return normalized
      .split('\n')
      .map((line: string) => this.indentReaderLine(line))
      .join('\n');
  }

  indentReaderLine(line: string): string {
    if (!line || line.trim().length === 0) {
      return line;
    }
    if (line.startsWith('　　')) {
      return line;
    }
    return `　　${line.replace(/^[　\s]+/g, '')}`;
  }

  stripDuplicatedChapterTitle(body: string, title: string): string {
    if (!body || !title) {
      return body;
    }
    const lines = body.split('\n');
    const firstLine = (lines[0] || '').replace(/^[　\s]+/g, '').trim();
    if (firstLine !== title) {
      return body;
    }
    return lines.slice(1).join('\n').replace(/^\n+/, '').trim();
  }

  isReaderTrimChar(value: string): boolean {
    return value === ' ' || value === '\t' || value === '\n' || value === '\r';
  }

  pushReaderPage(source: string, rawStart: number, rawEnd: number, pages: string[], starts: number[], ends: number[]): void {
    let pageStart = Math.max(0, Math.min(rawStart, source.length));
    let pageEnd = Math.max(pageStart, Math.min(rawEnd, source.length));
    while (pageStart < pageEnd && this.isReaderTrimChar(source.charAt(pageStart))) {
      pageStart++;
    }
    while (pageEnd > pageStart && this.isReaderTrimChar(source.charAt(pageEnd - 1))) {
      pageEnd--;
    }
    const pageText = source.substring(pageStart, pageEnd);
    if (!pageText) {
      return;
    }
    pages.push(pageText);
    starts.push(pageStart);
    ends.push(pageEnd);
  }

  findMeasuredPageEnd(source: string, start: number, availableWidth: number, availableHeight: number): number {
    let safeStart = Math.max(0, Math.min(start, source.length));
    while (safeStart < source.length && this.isReaderTrimChar(source.charAt(safeStart))) {
      safeStart++;
    }
    if (safeStart >= source.length) {
      return source.length;
    }

    const paragraphEnd = this.findParagraphLayoutPageEnd(source, safeStart, availableWidth, availableHeight);
    if (paragraphEnd > safeStart) {
      return paragraphEnd;
    }

    let low = safeStart + 1;
    let high = source.length;
    let best = low;
    while (low <= high) {
      const mid = Math.floor((low + high) / 2);
      const candidate = source.substring(safeStart, mid);
      if (this.measureReaderTextHeight(candidate, availableWidth) <= availableHeight) {
        best = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }

    const end = this.chooseReaderPageBreak(source, safeStart, best);
    return Math.max(safeStart + 1, end);
  }

  findParagraphLayoutPageEnd(source: string, start: number, availableWidth: number, availableHeight: number): number {
    const windowEnd = Math.min(source.length, start + this.getReaderLayoutWindowSize(availableWidth, availableHeight));
    const layoutText = source.substring(start, windowEnd);
    if (!layoutText) {
      return -1;
    }

    try {
      const fontSizePx = this.toMeasurePx(this.readerFontSize);
      const lineHeightPx = this.toMeasurePx(Math.max(this.readerLineHeight, this.readerFontSize));
      const textStyle: graphicsText.TextStyle = {
        fontSize: fontSizePx,
        fontWeight: graphicsText.FontWeight.W400,
        lineHeightMinimum: lineHeightPx,
        lineHeightMaximum: lineHeightPx,
        halfLeading: true,
        heightOnly: false,
        locale: 'zh-Hans'
      };
      const paragraphStyle: graphicsText.ParagraphStyle = {
        textStyle: textStyle,
        align: graphicsText.TextAlign.START,
        textDirection: graphicsText.TextDirection.LTR,
        wordBreak: graphicsText.WordBreak.BREAK_ALL,
        breakStrategy: graphicsText.BreakStrategy.GREEDY,
        trailingSpaceOptimized: true,
        includeFontPadding: false
      };
      const builder = new graphicsText.ParagraphBuilder(paragraphStyle, graphicsText.FontCollection.getGlobalInstance());
      builder.pushStyle(textStyle);
      builder.addText(layoutText);
      builder.popStyle();
      const paragraph = builder.build();
      paragraph.layoutSync(this.toMeasurePx(availableWidth));
      const metrics = paragraph.getLineMetrics();
      if (metrics.length === 0) {
        return -1;
      }

      const safeHeight = Math.max(1, availableHeight - 1);
      let end = -1;
      for (let i = 0; i < metrics.length; i++) {
        const metric = metrics[i];
        if (metric.topHeight + metric.height > safeHeight) {
          break;
        }
        end = Math.max(end, metric.endIndex);
      }

      if (end <= 0) {
        const firstRange = paragraph.getActualTextRange(0, true);
        end = Math.max(1, firstRange.end);
      }
      if (end >= layoutText.length && windowEnd < source.length) {
        return -1;
      }
      return Math.max(start + 1, Math.min(source.length, start + end));
    } catch (error) {
      console.error('官方段落布局分页失败，回退到文本测量分页:', error);
      return -1;
    }
  }

  getReaderLayoutWindowSize(availableWidth: number, availableHeight: number): number {
    const charsPerLine = Math.max(8, Math.floor(availableWidth / Math.max(1, this.readerFontSize * 0.95)));
    const visibleLines = Math.max(1, Math.ceil(availableHeight / Math.max(1, this.readerLineHeight)));
    return Math.min(12000, Math.max(800, charsPerLine * (visibleLines + 6) * 2));
  }

  measureReaderTextHeight(text: string, availableWidth: number): number {
    if (!text) {
      return 0;
    }
    const options: MeasureOptions = {
      textContent: text,
      constraintWidth: Math.max(1, availableWidth),
      fontSize: this.readerFontSize,
      lineHeight: this.readerLineHeight,
      fontWeight: FontWeight.Normal,
      textAlign: TextAlign.Start,
      wordBreak: WordBreak.BREAK_ALL
    };
    try {
      const size = this.getUIContext().getMeasureUtils().measureTextSize(options);
      const height = Number(size.height);
      if (height > 0) {
        return height;
      }
    } catch (error) {
      console.error('测量阅读文本高度失败:', error);
    }
    const charsPerLine = Math.max(8, Math.floor(availableWidth / Math.max(1, this.readerFontSize * 1.08)));
    const lines = Math.max(1, Math.ceil(text.length / charsPerLine));
    return this.toMeasurePx(lines * Math.max(1, this.readerLineHeight));
  }

  toMeasurePx(value: number): number {
    try {
      return Math.max(1, vp2px(value));
    } catch (_) {
      return Math.max(1, value);
    }
  }

  chooseReaderPageBreak(source: string, start: number, best: number): number {
    if (best >= source.length) {
      return source.length;
    }
    const minBreak = start + Math.max(24, Math.floor((best - start) * 0.96));
    let newline = source.lastIndexOf('\n', best);
    if (newline >= minBreak) {
      return newline + 1;
    }
    let sentence = Math.max(
      source.lastIndexOf('。', best),
      source.lastIndexOf('！', best),
      source.lastIndexOf('？', best),
      source.lastIndexOf('；', best),
      source.lastIndexOf(';', best)
    );
    if (sentence >= minBreak) {
      return sentence + 1;
    }
    return best;
  }

  followTtsChunk(chunk: TtsChunk): void {
    if (this.readerPageTurnMode === 0) {
      this.ttsDisplayText = this.getPagedSourceText();
      this.ttsHighlightStart = chunk.start;
      this.ttsHighlightEnd = chunk.end;
      return;
    }

    const absoluteStart = this.ttsTextStartOffset + chunk.start;
    const absoluteEnd = this.ttsTextStartOffset + chunk.end;
    const currentPageEnd = this.getPageEndOffset(this.currentPageIndex);
    const targetOffset = absoluteEnd > currentPageEnd ? absoluteEnd - 1 : absoluteStart;
    const pageIndex = this.findPageIndexByOffset(targetOffset);
    if (pageIndex !== this.currentPageIndex) {
      this.animateTtsToPage(pageIndex, chunk);
      return;
    }
    this.updateTtsChunkHighlight(chunk, pageIndex);
  }

  updateTtsChunkHighlight(chunk: TtsChunk, pageIndex: number): void {
    const absoluteStart = this.ttsTextStartOffset + chunk.start;
    const absoluteEnd = this.ttsTextStartOffset + chunk.end;
    const pageStart = this.getPageStartOffset(pageIndex);
    const pageEnd = this.getPageEndOffset(pageIndex);
    const pageText = this.getCurrentPageText();
    this.ttsDisplayText = pageText;
    this.ttsHighlightStart = Math.max(0, Math.min(absoluteStart - pageStart, pageText.length));
    this.ttsHighlightEnd = Math.max(this.ttsHighlightStart, Math.min(absoluteEnd, pageEnd) - pageStart);
  }

  animateTtsToPage(targetPageIndex: number, chunk: TtsChunk): void {
    const target = Math.max(0, Math.min(targetPageIndex, Math.max(0, this.contentPages.length - 1)));
    if (target <= this.currentPageIndex) {
      this.updateTtsChunkHighlight(chunk, this.currentPageIndex);
      return;
    }
    this.ttsPendingTargetPageIndex = Math.max(this.ttsPendingTargetPageIndex, target);
    this.ttsPendingHighlightChunk = chunk;
    if (this.ttsAutoTurningPage) {
      return;
    }
    this.runPendingTtsPageTurn();
  }

  async runPendingTtsPageTurn(): Promise<void> {
    this.ttsAutoTurningPage = true;
    try {
      while (this.isTtsSpeaking && this.ttsAutoContinue &&
        this.ttsPendingTargetPageIndex > this.currentPageIndex && this.canTurnPage(1)) {
        await this.runTtsPageTurnAnimation(1);
      }
      if (this.isTtsSpeaking && this.ttsPendingHighlightChunk) {
        this.updateTtsChunkHighlight(this.ttsPendingHighlightChunk, this.currentPageIndex);
      }
    } finally {
      this.ttsAutoTurningPage = false;
      this.ttsPendingTargetPageIndex = -1;
      this.ttsPendingHighlightChunk = null;
    }
  }

  async runTtsPageTurnAnimation(direction: number): Promise<void> {
    if (this.isPageTurning || !this.canTurnPage(direction)) {
      return;
    }
    this.isPageTurning = true;
    if (this.readerPageTurnMode === 1) {
      await this.runTtsSlidePageTurn(direction);
    } else {
      await this.runTtsTapPageTurn(direction);
    }
  }

  async runTtsTapPageTurn(direction: number): Promise<void> {
    animateTo({ duration: 110, curve: Curve.EaseOut }, () => {
      this.pageTransitionX = direction > 0 ? -44 : 44;
      this.pageTransitionOpacity = 0.12;
    });
    await this.delay(115);
    await this.applyTtsPageTurn(direction);
    this.pageTransitionX = direction > 0 ? 44 : -44;
    this.pageTransitionOpacity = 0.12;
    animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
      this.pageTransitionX = 0;
      this.pageTransitionOpacity = 1;
    });
    await this.delay(190);
    this.isPageTurning = false;
  }

  async runTtsSlidePageTurn(direction: number): Promise<void> {
    const width = this.getPageTurnWidth();
    animateTo({ duration: 150, curve: Curve.EaseIn }, () => {
      this.pageFlipOffsetX = direction > 0 ? -width : width;
      this.pageFlipAngle = direction > 0 ? -28 : 28;
      this.pageTransitionOpacity = 0.22;
      this.pageFlipShadeOpacity = 0.32;
    });
    await this.delay(155);
    await this.applyTtsPageTurn(direction);
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
    await this.delay(200);
    this.isPageTurning = false;
  }

  async applyTtsPageTurn(direction: number): Promise<void> {
    if (direction > 0) {
      if (this.currentPageIndex < this.contentPages.length - 1) {
        this.currentPageIndex++;
        this.syncCurrentPageText();
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
      this.syncCurrentPageText();
      await this.saveReadingProgress();
    } else {
      await this.loadPrevChapter();
    }
  }

  delay(ms: number): Promise<void> {
    return new Promise<void>((resolve) => {
      setTimeout(() => resolve(), ms);
    });
  }

  @Builder
  readingText(text: string, bottomPadding: number) {
    if (this.hasActiveTtsHighlight(text)) {
      Text() {
        ForEach(this.getReadingTextSlices(text), (slice: ReadTextSlice) => {
          Span(slice.text)
            .fontColor(slice.highlighted ? this.getTtsHighlightTextColor() : this.getTextColor())
            .textBackgroundStyle(slice.highlighted ? {
              color: this.getTtsHighlightColor(),
              radius: 4
            } : {})
        }, (slice: ReadTextSlice) => slice.key)
      }
      .fontSize(this.readerFontSize)
      .lineHeight(this.readerLineHeight)
      .fontColor(this.getTextColor())
      .padding({ left: 18, right: 18, top: 18, bottom: bottomPadding })
      .width('100%')
    } else {
      Text(this.getReadingRenderText(text))
        .fontSize(this.readerFontSize)
        .lineHeight(this.readerLineHeight)
        .fontColor(this.getTextColor())
        .padding({ left: 18, right: 18, top: 18, bottom: bottomPadding })
        .width('100%')
    }
  }

  getReadingTextSlices(text: string): ReadTextSlice[] {
    const displayText = this.getReadingRenderText(text);
    const start = this.ttsHighlightStart;
    const end = this.ttsHighlightEnd;
    if (!this.isTtsSpeaking || !this.ttsDisplayText || start < 0 || end <= start || displayText !== this.ttsDisplayText) {
      return [{
        text: displayText,
        start: 0,
        end: displayText.length,
        highlighted: false,
        key: `plain_${this.buildTextSliceKey(displayText)}`
      }];
    }
    const clampedStart = Math.max(0, Math.min(start, displayText.length));
    const clampedEnd = Math.max(clampedStart, Math.min(end, displayText.length));
    const slices: ReadTextSlice[] = [];
    if (clampedStart > 0) {
      slices.push({
        text: displayText.substring(0, clampedStart),
        start: 0,
        end: clampedStart,
        highlighted: false,
        key: `before_${clampedStart}_${this.buildTextSliceKey(displayText.substring(0, clampedStart))}`
      });
    }
    const highlightedText = displayText.substring(clampedStart, clampedEnd);
    slices.push({
      text: highlightedText,
      start: clampedStart,
      end: clampedEnd,
      highlighted: true,
      key: `highlight_${clampedStart}_${clampedEnd}_${this.buildTextSliceKey(highlightedText)}`
    });
    if (clampedEnd < displayText.length) {
      const afterText = displayText.substring(clampedEnd);
      slices.push({
        text: afterText,
        start: clampedEnd,
        end: displayText.length,
        highlighted: false,
        key: `after_${clampedEnd}_${this.buildTextSliceKey(afterText)}`
      });
    }
    return slices;
  }

  hasActiveTtsHighlight(text: string): boolean {
    const displayText = this.getReadingRenderText(text);
    return this.isTtsSpeaking && !!this.ttsDisplayText &&
      this.ttsHighlightStart >= 0 && this.ttsHighlightEnd > this.ttsHighlightStart &&
      displayText === this.ttsDisplayText;
  }

  getReadingRenderText(text: string): string {
    const normalized = (text || '')
      .replace(/\r\n/g, '\n')
      .replace(/\n{3,}/g, '\n\n')
      .trim();
    if (this.isTtsSpeaking && this.ttsDisplayText && normalized === this.ttsDisplayText) {
      return this.ttsDisplayText;
    }
    return text || '';
  }

  buildTextSliceKey(text: string): string {
    const value = text || '';
    const first = value.substring(0, Math.min(12, value.length));
    const last = value.substring(Math.max(0, value.length - 12));
    return `${value.length}_${this.hashText(first + last)}`;
  }

  hashText(text: string): number {
    let hash = 0;
    for (let i = 0; i < text.length; i++) {
      hash = ((hash * 31) + text.charCodeAt(i)) & 0x7fffffff;
    }
    return hash;
  }

  getTtsHighlightColor(): string {
    return this.readerThemeIndex === 3 || this.appDarkMode ? '#5A4A24' : '#FFE58A';
  }

  getTtsHighlightTextColor(): string {
    return this.readerThemeIndex === 3 || this.appDarkMode ? '#FFF4BF' : '#2F261D';
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
      this.pagedContentText = this.content || '';
      this.contentPageStarts = this.content ? [0] : [];
      this.contentPageEnds = this.content ? [this.content.length] : [];
      if (this.readerPageTurnMode === 0) {
        this.currentPageIndex = 0;
        this.restorePendingScrollOffset();
      }
      this.syncCurrentPageText();
      return;
    }

    if (this.readerPageTurnMode === 0) {
      this.contentPages = this.content ? [this.content] : [];
      this.pagedContentText = this.content || '';
      this.contentPageStarts = this.content ? [0] : [];
      this.contentPageEnds = this.content ? [this.content.length] : [];
      this.currentPageIndex = 0;
      this.restorePendingScrollOffset();
      this.syncCurrentPageText();
      return;
    }

    const horizontalPadding = 36;
    const verticalPadding = 36 + this.getReaderContentBottomReserve() + Math.ceil(Math.max(1, this.readerLineHeight) * 0.35);
    const availableWidth = Math.max(1, this.pageViewWidth - horizontalPadding);
    const availableHeight = Math.max(1, this.pageViewHeight - verticalPadding);
    const measuredAvailableHeight = this.toMeasurePx(availableHeight);
    const source = this.getPagedSourceText();
    this.pagedContentText = source;
    const pages: string[] = [];
    const starts: number[] = [];
    const ends: number[] = [];
    let cursor = 0;

    while (cursor < source.length) {
      const end = this.findMeasuredPageEnd(source, cursor, availableWidth, measuredAvailableHeight);
      if (end <= cursor) {
        break;
      }
      this.pushReaderPage(source, cursor, end, pages, starts, ends);
      cursor = end;
    }

    this.contentPages = pages.length > 0 ? pages : [this.content];
    this.contentPageStarts = starts.length > 0 ? starts : [0];
    this.contentPageEnds = ends.length > 0 ? ends : [this.pagedContentText.length];
    this.restorePendingPageIndex();
    if (this.currentPageIndex >= this.contentPages.length) {
      this.currentPageIndex = Math.max(0, this.contentPages.length - 1);
    }
    this.syncCurrentPageText();
  }

  async turnNext() {
    if (this.isTtsSpeaking || this.ttsReader.isSpeaking()) {
      this.stopTtsReading();
    }
    this.preloadReaderContent();
    await this.runPageTurnAnimation(1, this.readerPageTurnMode === 1 ? 'slide' : 'tap');
  }

  async turnPrev() {
    if (this.isTtsSpeaking || this.ttsReader.isSpeaking()) {
      this.stopTtsReading();
    }
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
    this.stopTtsReading();
    if (direction > 0) {
      if (this.currentPageIndex < this.contentPages.length - 1) {
        this.currentPageIndex++;
        this.syncCurrentPageText();
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
      this.syncCurrentPageText();
      if (this.currentPageIndex <= 2) {
        this.preloadReaderContent();
      }
      await this.saveReadingProgress();
    } else {
      await this.loadPrevChapter();
    }
  }

  async runPageTurnAnimation(direction: number, style: string): Promise<void> {
    if (this.ttsAutoTurningPage || this.isPageTurning || !this.canTurnPage(direction)) {
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
