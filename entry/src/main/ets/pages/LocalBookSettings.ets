import { router, promptAction } from '@kit.ArkUI';
import { syncSystemBars } from '../utils/SystemBars';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { LocalBookScanResult, LocalBookService } from '../core/book/LocalBookService';
import { AppDatabase } from '../model/data/AppDatabase';
import { Book } from '../model/data/Book';
import { ImmersiveBackButton } from '../components/ImmersiveBackButton';

@Entry
@Component
struct LocalBookSettingsPage {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('appLightButtonColor') appLightButtonColor: string = '#007DFF';
  @StorageLink('appDarkButtonColor') appDarkButtonColor: string = '#3F8CFF';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
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
    Column() {
      this.titleBar()
      Column({ space: 12 }) {
        Row() {
          Text(`已添加书籍（${this.books.length}）`)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.primaryTextColor())
            .layoutWeight(1)
        }
        .width('100%')

        if (this.books.length === 0) {
          Column({ space: 6 }) {
            Text('暂无已添加书籍')
              .fontSize(15)
              .fontColor(this.primaryTextColor())
            Text('点击下方按钮选择 TXT 或 EPUB 文件')
              .fontSize(13)
              .fontColor(this.subTextColor())
          }
          .width('100%')
          .padding({ top: 22, bottom: 22 })
        } else {
          List({ space: 8 }) {
            ForEach(this.books, (book: Book) => {
              ListItem() {
                this.bookItem(book)
              }
            }, (book: Book) => book.bookUrl)
          }
          .width('100%')
          .layoutWeight(1)
        }

        Text('选择 TXT 或 EPUB 文件导入书架')
          .fontSize(15)
          .fontColor(this.primaryTextColor())
        Text('支持一次选择多个文件，导入后文件会复制到应用内部存储，不依赖原文件位置。')
          .fontSize(13)
          .fontColor(this.subTextColor())
        Button(this.isScanning ? '正在导入' : '选择书籍文件')
          .width('100%')
          .height(44)
          .backgroundColor(this.buttonColor())
          .fontColor('#FFFFFF')
          .enabled(!this.isScanning)
          .onClick(() => {
            this.addBooks();
          })
        if (this.statusText) {
          Text(this.statusText)
            .fontSize(13)
            .fontColor(this.subTextColor())
            .width('100%')
            .margin({ top: 8 })
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 24, bottom: 32 })
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.statusBarHeight, bottom: this.navBarHeight })
    .backgroundColor(this.pageColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  @Builder
  bookItem(book: Book) {
    Row() {
      Column({ space: 5 }) {
        Text(book.name || '未命名书籍')
          .fontSize(16)
          .fontColor(this.primaryTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(book.author ? `${book.author} · ${book.totalChapterNum}章` : `${book.totalChapterNum}章`)
          .fontSize(12)
          .fontColor(this.subTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Text(book.type === LocalBookService.TYPE_EPUB ? 'EPUB' : 'TXT')
        .fontSize(11)
        .fontColor(this.subTextColor())
        .margin({ left: 10 })
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .backgroundColor(this.cardColor())
    .borderRadius(8)
  }

  async loadBooks(): Promise<void> {
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      this.books = (await db.getAllBooks()).filter((book: Book) => LocalBookService.isLocalBook(book));
    } catch (e) {
      console.error('加载已添加本地书籍失败:', e);
      this.books = [];
    }
  }

  @Builder
  titleBar() {
    Row() {
      ImmersiveBackButton({ iconColor: this.primaryTextColor(), darkMode: this.appDarkMode,
        onBack: () => router.back() })
      Text('添加书籍')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)
    }
    .width('100%')
    .height(56)
    .backgroundColor(this.cardColor())
    .alignItems(VerticalAlign.Center)
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
      await this.loadBooks();
    } catch (e) {
      console.error('添加本地书籍失败:', e);
      this.statusText = '导入失败，请重新选择文件';
      promptAction.showToast({ message: '导入失败' });
    } finally {
      this.isScanning = false;
    }
  }

  finishImport(result: LocalBookScanResult): void {
    const failed = result.failed > 0 ? `，${result.failed}本失败` : '';
    this.statusText = `导入完成：成功${result.imported}本${failed}`;
    AppStorage.setOrCreate('shelfUpdateTime', Date.now());
    promptAction.showToast({ message: this.statusText });
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
