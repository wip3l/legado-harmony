import { router } from '@kit.ArkUI';
import { BookSource, SearchBook } from '../model/data/Book';
import { AppDatabase } from '../model/data/AppDatabase';
import { promptAction } from '@kit.ArkUI';
import deviceInfo from '@ohos.deviceInfo';
import { SearchCoordinator, SearchProgress } from '../core/book/SearchCoordinator';
import { SearchBookResultList } from '../components/book/SearchBookResultList';
import { syncSystemBars } from '../utils/SystemBars';
import { SearchBookShelfHelper } from '../utils/SearchBookShelfHelper';
import { SearchExploreSettings, SearchExploreSettingsStore } from '../utils/SearchExploreSettingsStore';
import { AppThemeSettingsStore } from '../utils/AppThemeSettingsStore';

@Entry
@Component
struct SearchPage {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('appLightButtonColor') appLightButtonColor: string = '#007DFF';
  @StorageLink('appDarkButtonColor') appDarkButtonColor: string = '#3F8CFF';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @State keyword: string = '';
  @State searchResults: SearchBook[] = [];
  @State shelfBookKeys: string[] = [];
  @State addingShelfBookKeys: string[] = [];
  @State isSearching: boolean = false;
  @State searchHistory: string[] = [];
  @State hotKeywords: string[] = ['斗破苍穹', '完美世界', '遮天', '凡人修仙传', '诛仙'];
  @State showResult: boolean = false;
  @State statusMessage: string = '';
  @State verificationUrl: string = '';
  @State verificationTitle: string = '';
  @State showSearchSettingsDialog: boolean = false;
  @State sourceGroups: string[] = [];
  @StorageLink('shelfUpdateTime') @Watch('onShelfChanged') shelfUpdateTime: number = 0;
  @StorageLink('searchExploreShowResultCover') searchExploreShowResultCover: boolean = true;
  @StorageLink('searchExploreUseBookshelfCoverGallery') searchExploreUseBookshelfCoverGallery: boolean = true;
  @StorageLink('searchExploreShowResultTags') searchExploreShowResultTags: boolean = true;
  @StorageLink('searchExplorePromptAddToShelfOnBack') searchExplorePromptAddToShelfOnBack: boolean = true;
  @StorageLink('searchExploreExactSearch') exactSearch: boolean = false;
  @StorageLink('searchExploreExactSearchMatchAuthor') exactSearchMatchAuthor: boolean = true;
  @StorageLink('searchExploreShowSearchProgress') showSearchProgress: boolean = true;
  @StorageLink('searchExploreSearchConcurrency') searchConcurrency: number = 8;
  @StorageLink('searchExploreSelectedSourceGroups') selectedSourceGroupsRaw: string = '';
  private shelfStatusVersion: number = 0;
  private shelfSyncRunning: boolean = false;
  private pendingShelfSyncBooks: SearchBook[] = [];
  private readonly NO_SOURCE_GROUPS_SELECTED: string = '__NO_SOURCE_GROUPS_SELECTED__';

  aboutToAppear() {
    this.syncBars();
    this.initPage();
  }

  onPageShow(): void {
    this.syncBars();
    this.refreshSearchShelfStatus();
  }

  async initPage() {
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      const keywords = await db.getSearchKeywords();
      this.searchHistory = keywords.map(k => k.keyword);
      await this.loadSourceGroups(db);
      console.log('页面初始化完成');
    } catch (e) {
      console.error('初始化失败:', e);
    }
  }

  build() {
    Stack() {
      Column() {
        // 搜索栏
        Row() {
          Row() {
            TextInput({ placeholder: '搜索书籍', text: this.keyword })
              .layoutWeight(1)
              .height(40)
              .backgroundColor('#00000000')
              .fontColor(this.primaryTextColor())
              .placeholderColor(this.subTextColor())
              .padding({ left: 16, right: 4 })
              .onChange((value: string) => {
                this.keyword = value;
              })

            this.searchSettingIcon()
          }
          .layoutWeight(1)
          .height(40)
          .borderRadius(20)
          .backgroundColor(this.glassCardColor())
          .border({ width: 1, color: this.glassBorderColor() })
          .shadow({ radius: 8, color: this.glassShadowColor(), offsetX: 0, offsetY: 3 })
          .alignItems(VerticalAlign.Center)

        Button('搜索')
          .height(36)
          .fontSize(14)
          .margin({ left: 8 })
          .borderRadius(18)
          .backgroundColor(this.buttonColor())
          .fontColor('#FFFFFF')
          .onClick(() => {
            this.hideKeyboard();
            console.log('搜索按钮被点击, keyword:', this.keyword);
            promptAction.showToast({ message: `搜索: ${this.keyword}` });
            this.doSearch();
          })
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .backgroundColor(this.pageColor())
      .alignItems(VerticalAlign.Center)

      // 状态消息
      if (this.statusMessage) {
        Row() {
          Text(this.statusMessage)
            .fontSize(14)
            .fontColor(this.secondaryTextColor())
            .layoutWeight(1)
            .textAlign(TextAlign.Center)

          if (this.verificationUrl) {
            Button('去验证')
              .height(28)
              .fontSize(12)
              .borderRadius(14)
              .backgroundColor(this.buttonColor())
              .fontColor('#FFFFFF')
              .margin({ right: 12 })
              .onClick(() => {
                this.openVerification();
              })
          }
        }
        .width('100%')
        .height(40)
        .backgroundColor(this.statusMessageColor())
        .alignItems(VerticalAlign.Center)
      }

      // 内容区域
      if (this.showResult && this.searchResults.length > 0) {
        SearchBookResultList({
          books: this.searchResults,
          shelfBookKeys: this.shelfBookKeys,
          busyBookKeys: this.addingShelfBookKeys,
          showLoadingMore: this.isSearching,
          showResultCover: this.searchExploreShowResultCover,
          useBookshelfCoverGallery: this.searchExploreUseBookshelfCoverGallery,
          showResultTags: this.searchExploreShowResultTags,
          pageColor: this.pageColor(),
          cardColor: this.cardColor(),
          primaryTextColor: this.primaryTextColor(),
          secondaryTextColor: this.secondaryTextColor(),
          subTextColor: this.subTextColor(),
          bottomPadding: this.searchResultBottomInset(),
          onOpenBook: (book: SearchBook) => {
            this.openSearchBookDetail(book);
          },
          onToggleShelf: (book: SearchBook) => {
            this.toggleSearchBookShelf(book);
          }
        })
      } else if (this.isSearching) {
        Column() {
          LoadingProgress()
            .width(40)
            .height(40)
          Text('搜索中...')
            .fontSize(14)
            .fontColor(this.subTextColor())
            .margin({ top: 8 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.showResult && this.searchResults.length === 0) {
        Column() {
          Text('未找到相关书籍')
            .fontSize(16)
            .fontColor(this.subTextColor())
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        // 搜索历史和热门搜索
        Column() {
          if (this.searchHistory.length > 0) {
            Column() {
              Text('搜索历史')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.primaryTextColor())
                .width('100%')

              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.searchHistory, (keyword: string) => {
                  Text(keyword)
                    .fontSize(14)
                    .fontColor(this.secondaryTextColor())
                    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                    .backgroundColor(this.cardColor())
                    .borderRadius(16)
                    .margin({ right: 8, bottom: 8 })
                    .onClick(() => {
                      this.keyword = keyword;
                      this.doSearch();
                    })
                })
              }
              .width('100%')
              .margin({ top: 12 })
            }
            .width('100%')
            .padding(16)
            .backgroundColor(this.cardColor())
            .borderRadius(8)
            .margin({ left: 16, right: 16, top: 16 })
          }

          Column() {
            Text('热门搜索')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.primaryTextColor())
              .width('100%')

            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.hotKeywords, (keyword: string) => {
                Text(keyword)
                  .fontSize(14)
                  .fontColor(this.secondaryTextColor())
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .backgroundColor(this.cardColor())
                  .borderRadius(16)
                  .margin({ right: 8, bottom: 8 })
                  .onClick(() => {
                    this.keyword = keyword;
                    this.doSearch();
                  })
              })
            }
            .width('100%')
            .margin({ top: 12 })
          }
          .width('100%')
          .padding(16)
          .backgroundColor(this.cardColor())
          .borderRadius(8)
          .margin({ left: 16, right: 16, top: 16 })
        }
        .width('100%')
        .height('100%')
      }
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.statusBarHeight, bottom: this.navBarHeight })
      .backgroundColor(this.pageColor())
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])

      if (this.showSearchSettingsDialog) {
        this.searchSettingsDialog()
      }
    }
    .width('100%')
    .height('100%')
  }

  async doSearch() {
    console.log('doSearch 方法被调用');

    if (!this.keyword || this.keyword.trim() === '') {
      promptAction.showToast({ message: '请输入搜索关键词' });
      return;
    }

    this.isSearching = true;
    this.showResult = true;
    this.statusMessage = '正在搜索...';
    this.searchResults = [];
    this.verificationUrl = '';

    try {
      const db = AppDatabase.getInstance();
      const coordinator = new SearchCoordinator(SearchExploreSettingsStore.getSearchConcurrency());
      const keyword = this.keyword.trim();
      const allBooks = await coordinator.search(keyword, (progress: SearchProgress) => {
        this.searchResults = progress.results;
        if (this.showSearchProgress) {
          this.statusMessage = progress.status;
        }
        this.verificationUrl = progress.verificationUrl || AppStorage.get<string>('pendingVerificationUrl') || '';
        this.verificationTitle = progress.verificationTitle || AppStorage.get<string>('pendingVerificationTitle') || '网页验证';
        this.requestSearchShelfStatusSync(progress.results);
        if (progress.finished) {
          this.isSearching = false;
        }
      }, {
        exactMatch: this.exactSearch,
        exactMatchAuthor: this.exactSearchMatchAuthor,
        sourceGroups: this.searchSourceGroups()
      });

      const verifyUrl = this.verificationUrl || AppStorage.get<string>('pendingVerificationUrl') || '';
      this.statusMessage = verifyUrl ? `搜索完成，共找到 ${allBooks.length} 本书；有书源需要网页验证` :
        allBooks.length > 0 ? `搜索完成，共找到 ${allBooks.length} 本书` : '搜索完成，未找到相关书籍';
      console.log('搜索完成, 总结果:', allBooks.length);

      // 保存搜索历史
      await db.saveSearchKeyword(keyword);
      const keywords = await db.getSearchKeywords();
      this.searchHistory = keywords.map(k => k.keyword);
    } catch (e) {
      console.error('搜索失败:', e);
      this.statusMessage = '搜索失败';
    } finally {
      this.isSearching = false;
    }
  }

  hideKeyboard(): void {
    try {
      this.getUIContext().getFocusController().clearFocus();
    } catch (e) {
    }
  }

  onShelfChanged(): void {
    this.refreshSearchShelfStatus();
  }

  refreshSearchShelfStatus(): void {
    if (this.searchResults.length > 0) {
      this.requestSearchShelfStatusSync(this.searchResults);
    }
  }

  requestSearchShelfStatusSync(books: SearchBook[]): void {
    this.pendingShelfSyncBooks = books;
    if (!this.shelfSyncRunning) {
      this.drainSearchShelfStatusSync();
    }
  }

  async drainSearchShelfStatusSync(): Promise<void> {
    this.shelfSyncRunning = true;
    while (this.pendingShelfSyncBooks.length > 0) {
      const books = this.pendingShelfSyncBooks;
      this.pendingShelfSyncBooks = [];
      await this.syncSearchShelfStatus(books);
    }
    this.shelfSyncRunning = false;
  }

  async syncSearchShelfStatus(books: SearchBook[]): Promise<void> {
    try {
      const version = this.shelfStatusVersion;
      const keys = await SearchBookShelfHelper.syncShelfKeys(getContext(this), books);
      if (version === this.shelfStatusVersion) {
        this.shelfBookKeys = keys;
      }
    } catch (e) {
      console.error('同步搜索书架状态失败:', e);
    }
  }

  isSearchBookInShelf(book: SearchBook): boolean {
    return SearchBookShelfHelper.isInShelf(book, this.shelfBookKeys);
  }

  isSearchBookJoiningShelf(book: SearchBook): boolean {
    return SearchBookShelfHelper.isBusy(book, this.addingShelfBookKeys);
  }

  async toggleSearchBookShelf(searchBook: SearchBook): Promise<void> {
    if (this.isSearchBookJoiningShelf(searchBook)) {
      return;
    }

    if (this.isSearchBookInShelf(searchBook)) {
      await this.removeSearchBookFromShelf(searchBook);
    } else {
      await this.addSearchBookToShelf(searchBook);
    }
  }

  async addSearchBookToShelf(searchBook: SearchBook): Promise<void> {
    const searchKey = SearchBookShelfHelper.keyOf(searchBook);
    this.markSearchBookJoining(searchKey);
    try {
      const change = await SearchBookShelfHelper.addToShelf(getContext(this), searchBook);
      this.markSearchBookInShelf(change.shelfKey || change.requestKey);
    } catch (e) {
      console.error('加入书架失败:', e);
      promptAction.showToast({ message: '加入书架失败' });
    } finally {
      this.unmarkSearchBookJoining(searchKey);
    }
  }

  async removeSearchBookFromShelf(searchBook: SearchBook): Promise<void> {
    try {
      const change = await SearchBookShelfHelper.removeFromShelf(getContext(this), searchBook);
      this.shelfStatusVersion++;
      this.shelfBookKeys = SearchBookShelfHelper.withoutKey(this.shelfBookKeys, change.requestKey);
    } catch (e) {
      console.error('移出书架失败:', e);
      promptAction.showToast({ message: '移出书架失败' });
    }
  }

  markSearchBookInShelf(bookKey: string): void {
    const next = SearchBookShelfHelper.withAddedKey(this.shelfBookKeys, bookKey);
    if (next !== this.shelfBookKeys) {
      this.shelfStatusVersion++;
      this.shelfBookKeys = next;
    }
  }

  markSearchBookJoining(bookKey: string): void {
    const next = SearchBookShelfHelper.withAddedKey(this.addingShelfBookKeys, bookKey);
    if (next !== this.addingShelfBookKeys) {
      this.addingShelfBookKeys = next;
    }
  }

  unmarkSearchBookJoining(bookKey: string): void {
    const next = SearchBookShelfHelper.withoutKey(this.addingShelfBookKeys, bookKey);
    if (next !== this.addingShelfBookKeys) {
      this.addingShelfBookKeys = next;
    }
  }

  openSearchBookDetail(book: SearchBook) {
    router.pushUrl({
      url: 'pages/SearchBookDetail',
      params: {
        bookUrl: book.bookUrl,
        tocUrl: book.tocUrl,
        origin: book.origin,
        originName: book.originName,
        name: book.name,
        author: book.author,
        kind: book.kind,
        coverUrl: book.coverUrl,
        intro: book.intro,
        latestChapterTitle: book.latestChapterTitle,
        wordCount: book.wordCount,
        promptAddToShelfOnBack: this.searchExplorePromptAddToShelfOnBack ? 'true' : 'false'
      }
    });
  }

  async loadSourceGroups(db: AppDatabase = AppDatabase.getInstance()): Promise<void> {
    const sources = await db.getAllBookSources();
    const groups: string[] = [];
    for (const source of sources) {
      const group = this.normalizeSourceGroup(source);
      if (!groups.includes(group)) {
        groups.push(group);
      }
    }
    this.sourceGroups = groups.sort((a: string, b: string) => a.localeCompare(b));
    if (!this.isAllSourceGroupsSelected() && !this.isNoSourceGroupsSelected()) {
      this.saveSelectedSourceGroups(this.selectedSourceGroups().filter((group: string) => this.sourceGroups.includes(group)));
    }
  }

  normalizeSourceGroup(source: BookSource): string {
    const group = (source.bookSourceGroup || '').trim();
    return group || '未分组';
  }

  isAllSourceGroupsSelected(): boolean {
    const selectedGroups = this.selectedSourceGroups();
    return !this.isNoSourceGroupsSelected() &&
      (this.selectedSourceGroupsRaw.trim() === '' || selectedGroups.length >= this.sourceGroups.length);
  }

  isNoSourceGroupsSelected(): boolean {
    return this.selectedSourceGroupsRaw.trim() === this.NO_SOURCE_GROUPS_SELECTED;
  }

  isSourceGroupSelected(group: string): boolean {
    return !this.isNoSourceGroupsSelected() &&
      (this.isAllSourceGroupsSelected() || this.selectedSourceGroups().includes(group));
  }

  setSourceGroupSelected(group: string, selected: boolean): void {
    const selectedGroups = this.isAllSourceGroupsSelected() ? this.sourceGroups : this.selectedSourceGroups();
    if (selected) {
      if (!selectedGroups.includes(group)) {
        this.saveSelectedSourceGroups(selectedGroups.concat([group]));
      }
      return;
    }
    this.saveSelectedSourceGroups(selectedGroups.filter((item: string) => item !== group));
  }

  searchSourceGroupSummary(): string {
    if (this.isAllSourceGroupsSelected()) {
      return '全部书源';
    }
    if (this.isNoSourceGroupsSelected()) {
      return '未选择书源';
    }
    return `已选 ${this.selectedSourceGroups().length} 个分组`;
  }

  selectedSourceGroups(): string[] {
    const raw = this.selectedSourceGroupsRaw.trim();
    if (!raw || raw === this.NO_SOURCE_GROUPS_SELECTED) {
      return [];
    }
    return raw.split('\n').map((group: string) => group.trim()).filter((group: string) => group);
  }

  searchSourceGroups(): string[] {
    if (this.isNoSourceGroupsSelected()) {
      return [this.NO_SOURCE_GROUPS_SELECTED];
    }
    return this.isAllSourceGroupsSelected() ? [] : this.selectedSourceGroups();
  }

  saveSelectedSourceGroups(groups: string[]): void {
    const normalized: string[] = [];
    for (const group of groups) {
      const value = (group || '').trim();
      if (value && !normalized.includes(value)) {
        normalized.push(value);
      }
    }
    this.selectedSourceGroupsRaw = normalized.length > 0 ? normalized.join('\n') : this.NO_SOURCE_GROUPS_SELECTED;
    if (normalized.length >= this.sourceGroups.length) {
      this.selectedSourceGroupsRaw = '';
    }
    this.saveSearchExploreSettings();
  }

  saveAllSourceGroupsSelected(selected: boolean): void {
    this.selectedSourceGroupsRaw = selected ? '' : this.NO_SOURCE_GROUPS_SELECTED;
    this.saveSearchExploreSettings();
  }

  saveSearchExploreSettings(): void {
    SearchExploreSettingsStore.load(getContext(this)).then((settings: SearchExploreSettings) => {
      settings.showResultCover = this.searchExploreShowResultCover;
      settings.useBookshelfCoverGallery = this.searchExploreUseBookshelfCoverGallery;
      settings.showResultTags = this.searchExploreShowResultTags;
      settings.promptAddToShelfOnBack = this.searchExplorePromptAddToShelfOnBack;
      settings.exactSearch = this.exactSearch;
      settings.exactSearchMatchAuthor = this.exactSearchMatchAuthor;
      settings.showSearchProgress = this.showSearchProgress;
      settings.searchConcurrency = this.searchConcurrency;
      settings.selectedSourceGroupsRaw = this.selectedSourceGroupsRaw;
      settings.sourceSortRaw = AppStorage.get<string>('searchExploreSourceSort') || '';
      SearchExploreSettingsStore.applyToStorage(settings);
      return SearchExploreSettingsStore.save(getContext(this), settings);
    }).catch((e: Error) => {
      console.warn('保存搜索设置失败:', e);
    });
  }

  @Builder
  searchSettingsDialog() {
    Column() {
      Column() {
        Text('搜索设置')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ bottom: 16 })

        this.switchSettingRow('精准搜索', this.exactSearch, (checked: boolean) => {
          this.exactSearch = checked;
          this.saveSearchExploreSettings();
        })

        this.switchSettingRow('匹配作者', this.exactSearchMatchAuthor, (checked: boolean) => {
          this.exactSearchMatchAuthor = checked;
          this.saveSearchExploreSettings();
        })

        this.switchSettingRow('显示搜索进度', this.showSearchProgress, (checked: boolean) => {
          this.showSearchProgress = checked;
          this.saveSearchExploreSettings();
        })

        this.numberSettingRow('搜索并发数', this.searchConcurrency, 1, 32, (value: number) => {
          this.searchConcurrency = value;
          this.saveSearchExploreSettings();
        })

        Row() {
          Text('搜索书源设置')
            .fontSize(15)
            .fontColor(this.primaryTextColor())
            .layoutWeight(1)

          Text(this.searchSourceGroupSummary())
            .fontSize(13)
            .fontColor(this.subTextColor())
        }
        .width('100%')
        .height(42)
        .alignItems(VerticalAlign.Center)
        .margin({ top: 8 })

        Row() {
          Toggle({ type: ToggleType.Checkbox, isOn: this.isAllSourceGroupsSelected() })
            .selectedColor(this.buttonColor())
            .onChange((isOn: boolean) => {
              this.saveAllSourceGroupsSelected(isOn);
            })
          Text('全部书源')
            .fontSize(14)
            .fontColor(this.secondaryTextColor())
            .margin({ left: 8 })
            .layoutWeight(1)
        }
        .width('100%')
        .height(38)
        .alignItems(VerticalAlign.Center)

        Scroll() {
          Column() {
            ForEach(this.sourceGroups, (group: string) => {
              Row() {
                Toggle({ type: ToggleType.Checkbox, isOn: this.isSourceGroupSelected(group) })
                  .selectedColor(this.buttonColor())
                  .onChange((isOn: boolean) => {
                    if (this.isAllSourceGroupsSelected() && !isOn) {
                      this.saveSelectedSourceGroups(this.sourceGroups.filter((item: string) => item !== group));
                      return;
                    }
                    this.setSourceGroupSelected(group, isOn);
                  })
                Text(group)
                  .fontSize(14)
                  .fontColor(this.secondaryTextColor())
                  .margin({ left: 8 })
                  .layoutWeight(1)
              }
              .width('100%')
              .height(36)
              .alignItems(VerticalAlign.Center)
            })
          }
          .width('100%')
        }
        .width('100%')
        .constraintSize({ maxHeight: 180 })
        .margin({ top: 4 })

        Button('完成')
          .width('100%')
          .height(44)
          .margin({ top: 16 })
          .backgroundColor(this.buttonColor())
          .fontColor('#FFFFFF')
          .onClick(() => {
            this.showSearchSettingsDialog = false;
          })
      }
      .width('88%')
      .padding(24)
      .backgroundColor(this.cardColor())
      .borderRadius(12)
      .onClick(() => {
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#80000000')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.showSearchSettingsDialog = false;
    })
  }

  @Builder
  searchSettingIcon() {
    Text('⋮')
      .fontSize(24)
      .fontColor(this.buttonColor())
      .fontWeight(FontWeight.Medium)
      .width(36)
      .height(36)
      .textAlign(TextAlign.Center)
      .backgroundColor(this.buttonBackgroundColor())
      .borderRadius(18)
      .margin({ right: 2 })
      .onClick(() => {
        this.hideKeyboard();
        this.loadSourceGroups().catch((e: Error) => {
          console.warn('加载搜索书源分组失败:', e);
        });
        this.showSearchSettingsDialog = true;
      })
  }


  @Builder
  switchSettingRow(title: string, checked: boolean, onChange: (checked: boolean) => void) {
    Row() {
      Text(title)
        .fontSize(15)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: checked })
        .selectedColor(this.buttonColor())
        .onChange(onChange)
    }
    .width('100%')
    .height(42)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  numberSettingRow(title: string, value: number, minValue: number, maxValue: number, onChange: (value: number) => void) {
    Row() {
      Text(title)
        .fontSize(15)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)

      Row() {
        Text('−')
          .fontSize(18)
          .fontColor(this.primaryTextColor())
          .width(30)
          .height(30)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            onChange(Math.max(minValue, value - 1));
          })
        Text(`${value}`)
          .fontSize(15)
          .fontColor(this.primaryTextColor())
          .width(42)
          .textAlign(TextAlign.Center)
        Text('+')
          .fontSize(18)
          .fontColor(this.primaryTextColor())
          .width(30)
          .height(30)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            onChange(Math.min(maxValue, value + 1));
          })
      }
      .height(30)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(42)
    .alignItems(VerticalAlign.Center)
  }
  openVerification(): void {
    const url = this.verificationUrl || AppStorage.get<string>('pendingVerificationUrl') || '';
    if (!url) {
      promptAction.showToast({ message: '暂无需要验证的网页' });
      return;
    }
    router.pushUrl({
      url: 'pages/VerifyWeb',
      params: {
        url: url,
        title: this.verificationTitle || '网页验证'
      }
    });
  }

  pageColor(): string {
    return this.appDarkMode ? '#101113' : '#F5F5F5';
  }

  cardColor(): string {
    return this.appDarkMode ? '#191B1F' : '#FFFFFF';
  }

  glassCardColor(): string {
    return this.appDarkMode ? '#191B1F' : '#FFFFFF';
  }

  glassBorderColor(): string {
    return this.appDarkMode ? '#262A31' : '#FFFFFF';
  }

  glassShadowColor(): string {
    return '#00000000';
  }

  inputColor(): string {
    return this.appDarkMode ? '#24272D' : '#F5F5F5';
  }

  primaryTextColor(): string {
    return this.appDarkMode ? '#F2F3F5' : '#1F1F1F';
  }

  secondaryTextColor(): string {
    return this.appDarkMode ? '#C6CBD2' : '#666666';
  }

  subTextColor(): string {
    return this.appDarkMode ? '#8A8F98' : '#999999';
  }

  statusMessageColor(): string {
    return this.appDarkMode ? '#14251B' : '#E8F5E9';
  }

  buttonColor(): string {
    return this.appDarkMode ? this.appDarkButtonColor : this.appLightButtonColor;
  }

  buttonBackgroundColor(): string {
    const normalized = AppThemeSettingsStore.normalizeColor(this.buttonColor(), AppThemeSettingsStore.DEFAULT_LIGHT_BUTTON_COLOR);
    return `#${this.appDarkMode ? '33' : '1A'}${normalized.substring(1)}`;
  }

  searchResultBottomInset(): number {
    const comfortableGap = 20;
    if (deviceInfo.sdkApiVersion < 23) {
      return comfortableGap;
    }
    const floatingTabHeight = 56;
    return floatingTabHeight + Math.max(this.navBarHeight, 8) + comfortableGap;
  }

  syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, this.pageColor());
  }
}
