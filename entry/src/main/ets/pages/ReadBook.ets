import { router, window } from '@kit.ArkUI';
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
  @State contentPages: string[] = [];
  @State currentPageIndex: number = 0;
  @State pageViewWidth: number = 0;
  @State pageViewHeight: number = 0;
  @State statusBarSafeHeight: number = 0;
  @StorageLink('readerFontSize') @Watch('onReadLayoutChanged') readerFontSize: number = 20;
  @StorageLink('readerLineHeight') @Watch('onReadLayoutChanged') readerLineHeight: number = 32;
  @StorageLink('readerParagraphSpacing') @Watch('onReadLayoutChanged') readerParagraphSpacing: number = 10;
  @StorageLink('readerThemeIndex') readerThemeIndex: number = 0;
  @StorageLink('readerPageTurnMode') readerPageTurnMode: number = 0;
  @StorageLink('readerTapTurnPage') readerTapTurnPage: boolean = true;
  @StorageLink('readerVolumeTurnPage') readerVolumeTurnPage: boolean = false;
  @StorageLink('readerKeepScreenOn') readerKeepScreenOn: boolean = true;
  @StorageLink('readerExtendToStatusBar') @Watch('onReaderExtendToStatusBarChanged') readerExtendToStatusBar: boolean = false;
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  private themeBackgrounds: string[] = ['#F6F0E5', '#F5F5F5', '#E8F1EA', '#1F1F1F'];
  private themeTextColors: string[] = ['#2F261D', '#333333', '#26352A', '#D8D8D8'];

  aboutToAppear() {
    this.enterReaderImmersive();
    const params = router.getParams() as Record<string, string>;
    if (params && params['bookUrl']) {
      this.bookUrl = params['bookUrl'];
      this.loadBook();
    }
  }

  aboutToDisappear() {
    this.exitReaderImmersive();
  }

  enterReaderImmersive() {
    window.getLastWindow(getContext(this)).then((mainWindow: window.Window) => {
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
      mainWindow.setWindowLayoutFullScreen(false);
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

      const engine = ReadBookEngine.get();
      await engine.openBook(this.book);
      this.chapters = engine.chapters;
      this.currentChapterIndex = engine.curIdx;
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
        this.content = this.buildBookPreview();
        this.isLoading = false;
      }
    } catch (e) {
      console.error('重试获取目录失败:', e);
      this.content = this.buildBookPreview();
      this.isLoading = false;
    }
  }

  async loadContent() {
    if (this.chapters.length === 0) {
      this.content = this.buildBookPreview();
      this.isLoading = false;
      return;
    }
    
    this.isLoading = true;
    this.loadStatus = '正在加载章节内容...';
    try {
      const engine = ReadBookEngine.get();
      const body = await engine.loadContent(this.currentChapterIndex);
      if (body) {
        this.content = body;
      } else {
        const c = this.chapters[this.currentChapterIndex];
        this.content = c ? `${c.title}\n\n章节内容加载失败，请稍后重试或尝试换源。` : '加载失败';
      }
      this.currentPageIndex = 0;
      this.paginateContent();
    } catch (e) {
      console.error('加载内容失败:', e);
    } finally {
      this.isLoading = false;
      this.loadStatus = '';
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
            Scroll() {
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

            this.readerBottomInfoBar()
          }
          .width('100%')
          .height('100%')
        } else {
          Column() {
            Column() {
              Text(this.getCurrentPageText())
                .fontSize(this.readerFontSize)
                .lineHeight(this.readerLineHeight)
                .fontColor(this.getTextColor())
                .padding({ left: 18, right: 18, top: 18, bottom: 18 })
                .width('100%')
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Start)
            .alignItems(HorizontalAlign.Start)
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
              .onClick(() => {
                router.back();
              })

            Text(this.book?.name || '')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            // 重试按钮
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
                    .onClick(() => {
                      this.currentChapterIndex = index;
                      this.showToc = false;
                      this.showMenu = false;
                      this.loadContent();
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
  }

  onReaderExtendToStatusBarChanged(): void {
    this.enterReaderImmersive();
    this.paginateContent();
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
              .onActionEnd((event: GestureEvent) => {
                if (this.readerPageTurnMode !== 1 || this.showToc || this.showSettings || this.chapters.length === 0) {
                  return;
                }
                if (event.offsetX < -50) {
                  this.turnNext();
                } else if (event.offsetX > 50) {
                  this.turnPrev();
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
    this.paginateContent();
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
      this.currentPageIndex = 0;
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
    if (this.currentPageIndex >= this.contentPages.length) {
      this.currentPageIndex = Math.max(0, this.contentPages.length - 1);
    }
  }

  async turnNext() {
    if (this.readerPageTurnMode !== 0 && this.currentPageIndex < this.contentPages.length - 1) {
      this.currentPageIndex++;
      return;
    }
    await this.loadNextChapter();
  }

  async turnPrev() {
    if (this.readerPageTurnMode !== 0 && this.currentPageIndex > 0) {
      this.currentPageIndex--;
      return;
    }
    await this.loadPrevChapter();
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
      text += '\n\n⚠ 当前书源暂未解析出目录，可以尝试点击标题栏的「重试」按钮重新获取，或在书源管理中为该书源补充目录规则。';
    }
    return text;
  }

  async loadNextChapter() {
    if (this.currentChapterIndex < this.chapters.length - 1) {
      this.currentChapterIndex++;
      this.currentPageIndex = 0;
      await this.loadContent();
    }
  }

  async loadPrevChapter() {
    if (this.currentChapterIndex > 0) {
      this.currentChapterIndex--;
      this.currentPageIndex = 0;
      await this.loadContent();
      this.currentPageIndex = Math.max(0, this.contentPages.length - 1);
    }
  }
}
