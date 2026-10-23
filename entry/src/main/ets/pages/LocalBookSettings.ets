import { syncSystemBars } from '../utils/SystemBars';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { LocalBookScanResult, LocalBookService } from '../core/book/LocalBookService';
import { AppDatabase } from '../model/data/AppDatabase';
import { Book } from '@legado/sourceengine';
import { HdsFeedback } from '../utils/HdsFeedback';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { PageScaffold } from '../components/common/PageScaffold';
import { CollapsingHeader } from '../utils/CollapsingHeader';
import { CloudAutoSync } from '../account/CloudAutoSync';

@Entry
@Component
struct LocalBookSettingsPage {
  @State headerCollapse: number = 0;
  private headerScroller: Scroller = new Scroller();
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageLink('appLightButtonColor') appLightButtonColor: string = '#007DFF';
  @StorageLink('appDarkButtonColor') appDarkButtonColor: string = '#3F8CFF';
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @State isScanning: boolean = false;
  @State statusText: string = '';
  @State books: Book[] = [];

  aboutToAppear(): void {
    this.loadBooks();
    this.syncBars();
  }

  onPageShow(): void {
    this.loadBooks();
    this.syncBars();
  }

  build() {
    Stack() {
      PageScaffold({ title: '添加书籍', scrollable: false, externalCollapse: this.headerCollapse, content: () => {
        this.pageContent()
      } })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  pageContent() {
    Column({ space: AppSpacing.LG }) {
      Row() {
        Text(`已添加书籍（${this.books.length}）`)
          .fontSize(AppFontSize.BODY_LARGE)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())
          .layoutWeight(1)
      }
      .width('100%')

      if (this.books.length === 0) {
        Column({ space: AppSpacing.SM }) {
          Text('暂无已添加书籍')
            .fontSize(AppFontSize.BODY_LARGE)
            .fontColor(this.primaryTextColor())
          Text('点击下方按钮选择 TXT 或 EPUB 文件')
            .fontSize(AppFontSize.BODY)
            .fontColor(this.subTextColor())
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ scroller: this.headerScroller, space: AppSpacing.MD }) {
          ForEach(this.books, (book: Book) => {
            ListItem() {
              this.bookItem(book)
            }
          }, (book: Book) => book.bookUrl)
        }
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .width('100%')
        .layoutWeight(1)
        .clip(true)
        .onDidScroll((yOffset: number) => {
          this.headerCollapse = CollapsingHeader.next(this.headerCollapse, yOffset,
            this.headerScroller.currentOffset().yOffset);
        })
        .onScrollStop(() => {
          const target = CollapsingHeader.settle(this.headerCollapse, this.headerScroller.currentOffset().yOffset);
          if (target !== this.headerCollapse) {
            animateTo({ duration: 200, curve: Curve.FastOutSlowIn }, () => {
              this.headerCollapse = target;
            });
          }
        })
      }

      Text('选择 TXT 或 EPUB 文件导入书架')
        .fontSize(AppFontSize.BODY_LARGE)
        .fontColor(this.primaryTextColor())
      Text('支持一次选择多个文件，导入后文件会复制到应用内部存储，不依赖原文件位置。')
        .fontSize(AppFontSize.BODY)
        .fontColor(this.subTextColor())
      Button(this.isScanning ? '正在导入' : '选择书籍文件')
        .width('100%')
        .height(44)
        .backgroundColor(this.buttonColor())
        .fontColor(ThemeRuntime.onAccentColor())
        .enabled(!this.isScanning)
        .onClick(() => {
          this.addBooks();
        })
      if (this.statusText) {
        Text(this.statusText)
          .fontSize(AppFontSize.BODY)
          .fontColor(this.subTextColor())
          .width('100%')
          .margin({ top: AppSpacing.MD })
      }
    }
    .width('100%')
    .layoutWeight(1)
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.XXXL, bottom: 32 + this.navBarHeight })
  }

  @Builder
  bookItem(book: Book) {
    Row() {
      Column({ space: AppSpacing.XS }) {
        Text(book.name || '未命名书籍')
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.primaryTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(book.author ? `${book.author} · ${book.totalChapterNum}章` : `${book.totalChapterNum}章`)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Text(LocalBookService.formatOf(book).toUpperCase())
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor())
        .margin({ left: AppSpacing.MD })
    }
    .width('100%')
    .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.LG, bottom: AppSpacing.LG })
    .backgroundColor(this.cardColor())
    .borderRadius(ThemeRuntime.cardRadius())
  }

  async loadBooks(): Promise<void> {
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      this.books = (await db.getAllBooks()).filter((book: Book) => LocalBookService.isPhysicalLocalBook(book));
    } catch (e) {
      console.error('加载已添加本地书籍失败:', e);
      this.books = [];
    }
  }

  async addBooks(): Promise<void> {
    if (this.isScanning) return;
    try {
      const selected = await LocalBookService.chooseBookFiles(getContext(this));
      if (selected.length === 0) return;
      this.isScanning = true;
      this.statusText = `正在导入${selected.length}本书...`;
      const result = await LocalBookService.importSelectedFiles(getContext(this), selected);
      this.finishImport(result);
      CloudAutoSync.schedule(getContext(this));
      await this.loadBooks();
    } catch (e) {
      console.error('添加本地书籍失败:', e);
      this.statusText = '导入失败，请重新选择文件';
      HdsFeedback.showToast('导入失败');
    } finally {
      this.isScanning = false;
    }
  }

  finishImport(result: LocalBookScanResult): void {
    const failed = result.failed > 0 ? `，${result.failed}本失败` : '';
    this.statusText = `导入完成：成功${result.imported}本${failed}`;
    AppStorage.setOrCreate('shelfUpdateTime', Date.now());
    HdsFeedback.showToast(this.statusText);
  }

  pageColor(): string {
    return ThemeRuntime.pageColor(this.appDarkMode);
  }

  cardColor(): string {
    return ThemeRuntime.cardColor(this.appDarkMode);
  }

  primaryTextColor(): string {
    return ThemeRuntime.primaryTextColor(this.appDarkMode);
  }

  subTextColor(): string {
    return ThemeRuntime.subTextColor(this.appDarkMode);
  }

  buttonColor(): string {
    return ThemeRuntime.buttonColor(this.appDarkMode);
  }

  syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, this.pageColor());
  }
}
