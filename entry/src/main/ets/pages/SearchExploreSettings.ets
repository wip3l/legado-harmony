import { router } from '@kit.ArkUI';
import { syncSystemBars } from '../utils/SystemBars';
import { SearchExploreSettings, SearchExploreSettingsStore } from '../utils/SearchExploreSettingsStore';
import { BookSource } from '../model/data/Book';
import { AppDatabase } from '../model/data/AppDatabase';

@Entry
@Component
struct SearchExploreSettingsPage {
  @StorageLink('searchExploreShowResultCover') searchExploreShowResultCover: boolean = true;
  @StorageLink('searchExploreUseBookshelfCoverGallery') searchExploreUseBookshelfCoverGallery: boolean = true;
  @StorageLink('searchExploreShowResultTags') searchExploreShowResultTags: boolean = true;
  @StorageLink('searchExplorePromptAddToShelfOnBack') searchExplorePromptAddToShelfOnBack: boolean = true;
  @StorageLink('searchExploreExactSearch') searchExploreExactSearch: boolean = false;
  @StorageLink('searchExploreExactSearchMatchAuthor') searchExploreExactSearchMatchAuthor: boolean = true;
  @StorageLink('searchExploreShowSearchProgress') searchExploreShowSearchProgress: boolean = true;
  @StorageLink('searchExploreSearchConcurrency') searchExploreSearchConcurrency: number = 8;
  @StorageLink('searchExploreSelectedSourceGroups') searchExploreSelectedSourceGroups: string = '';
  @StorageLink('searchExploreSourceSort') searchExploreSourceSort: string = '';
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('appLightButtonColor') appLightButtonColor: string = '#007DFF';
  @StorageLink('appDarkButtonColor') appDarkButtonColor: string = '#3F8CFF';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @State sourceGroups: string[] = [];
  private readonly NO_SOURCE_GROUPS_SELECTED: string = '__NO_SOURCE_GROUPS_SELECTED__';

  aboutToAppear(): void {
    this.reloadSettings();
    this.loadSourceGroups();
    this.syncBars();
  }

  onPageShow(): void {
    this.reloadSettings();
    this.loadSourceGroups();
    this.syncBars();
  }

  build() {
    Column() {
      this.titleBar()

      Scroll() {
        Column() {
          this.sectionTitle('结果展示')
          this.switchItem('显示结果封面', '开启后搜索和发现结果展示书籍封面',
            this.searchExploreShowResultCover, (value: boolean) => {
              this.searchExploreShowResultCover = value;
              this.onSettingChanged();
            })
          if (this.searchExploreShowResultCover) {
            this.switchItem('使用书架图集', '开启后结果列表封面使用书架封面设置的浅色/深色图集',
              this.searchExploreUseBookshelfCoverGallery, (value: boolean) => {
                this.searchExploreUseBookshelfCoverGallery = value;
                this.onSettingChanged();
              })
          }
          this.switchItem('显示结果标签', '开启后搜索和发现结果展示书籍标签',
            this.searchExploreShowResultTags, (value: boolean) => {
              this.searchExploreShowResultTags = value;
              this.onSettingChanged();
            })

          this.sectionTitle('书架提示')
          this.switchItem('返回提示加入书架', '从搜索或发现详情点击阅读后，返回时询问是否加入书架',
            this.searchExplorePromptAddToShelfOnBack, (value: boolean) => {
              this.searchExplorePromptAddToShelfOnBack = value;
              this.onSettingChanged();
            })

          this.sectionTitle('搜索设置')
          this.switchItem('精准搜索', '开启后仅保留书名与关键词完全匹配的搜索结果',
            this.searchExploreExactSearch, (value: boolean) => {
              this.searchExploreExactSearch = value;
              this.onSettingChanged();
            })
          this.switchItem('匹配作者', '精准搜索开启时，关键词同时匹配作者',
            this.searchExploreExactSearchMatchAuthor, (value: boolean) => {
              this.searchExploreExactSearchMatchAuthor = value;
              this.onSettingChanged();
            })
          this.switchItem('显示搜索进度', '开启后搜索过程中显示已搜索书源数量和结果数量',
            this.searchExploreShowSearchProgress, (value: boolean) => {
              this.searchExploreShowSearchProgress = value;
              this.onSettingChanged();
            })
          this.numberSettingItem('搜索并发数', '控制书籍检索、书源校验和换源同时并发请求的数量',
            this.searchExploreSearchConcurrency, 1, 32, (value: number) => {
              this.searchExploreSearchConcurrency = SearchExploreSettingsStore.normalizeSearchConcurrency(value);
              this.onSettingChanged();
            })
          this.sourceGroupSettings()

          this.sectionTitle('发现设置')
          this.navItem('书源排序', '调整发现页书源下拉列表顺序', 'pages/ExploreSourceSort')
        }
        .width('100%')
        .padding({ bottom: 32 })
      }
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.statusBarHeight, bottom: this.navBarHeight })
    .backgroundColor(this.pageColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  async reloadSettings(): Promise<void> {
    try {
      const settings = await SearchExploreSettingsStore.load(getContext(this));
      this.searchExploreShowResultCover = settings.showResultCover;
      this.searchExploreUseBookshelfCoverGallery = settings.useBookshelfCoverGallery;
      this.searchExploreShowResultTags = settings.showResultTags;
      this.searchExplorePromptAddToShelfOnBack = settings.promptAddToShelfOnBack;
      this.searchExploreExactSearch = settings.exactSearch;
      this.searchExploreExactSearchMatchAuthor = settings.exactSearchMatchAuthor;
      this.searchExploreShowSearchProgress = settings.showSearchProgress;
      this.searchExploreSearchConcurrency = settings.searchConcurrency;
      this.searchExploreSelectedSourceGroups = settings.selectedSourceGroupsRaw;
      this.searchExploreSourceSort = settings.sourceSortRaw;
    } catch (e) {
      console.warn('重新加载搜索/发现配置失败:', e);
    }
  }

  async loadSourceGroups(): Promise<void> {
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
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
        this.saveSelectedSourceGroups(this.selectedSourceGroups()
          .filter((group: string) => this.sourceGroups.includes(group)), false);
      }
    } catch (e) {
      console.warn('加载搜索书源分组失败:', e);
    }
  }

  onSettingChanged(): void {
    SearchExploreSettingsStore.load(getContext(this)).then((settings: SearchExploreSettings) => {
      settings.showResultCover = this.searchExploreShowResultCover;
      settings.useBookshelfCoverGallery = this.searchExploreUseBookshelfCoverGallery;
      settings.showResultTags = this.searchExploreShowResultTags;
      settings.promptAddToShelfOnBack = this.searchExplorePromptAddToShelfOnBack;
      settings.exactSearch = this.searchExploreExactSearch;
      settings.exactSearchMatchAuthor = this.searchExploreExactSearchMatchAuthor;
      settings.showSearchProgress = this.searchExploreShowSearchProgress;
      settings.searchConcurrency = SearchExploreSettingsStore.normalizeSearchConcurrency(this.searchExploreSearchConcurrency);
      settings.selectedSourceGroupsRaw = this.searchExploreSelectedSourceGroups;
      settings.sourceSortRaw = this.searchExploreSourceSort;
      SearchExploreSettingsStore.applyToStorage(settings);
      return SearchExploreSettingsStore.save(getContext(this), settings);
    }).catch((e: Error) => {
      console.warn('保存搜索/发现配置失败:', e);
    });
  }

  normalizeSourceGroup(source: BookSource): string {
    const group = (source.bookSourceGroup || '').trim();
    return group || '未分组';
  }

  selectedSourceGroups(): string[] {
    const raw = this.searchExploreSelectedSourceGroups.trim();
    if (!raw || raw === this.NO_SOURCE_GROUPS_SELECTED) {
      return [];
    }
    return raw.split('\n')
      .map((group: string) => group.trim())
      .filter((group: string) => group);
  }

  isAllSourceGroupsSelected(): boolean {
    const selectedGroups = this.selectedSourceGroups();
    return !this.isNoSourceGroupsSelected() &&
      (this.searchExploreSelectedSourceGroups.trim() === '' || selectedGroups.length >= this.sourceGroups.length);
  }

  isNoSourceGroupsSelected(): boolean {
    return this.searchExploreSelectedSourceGroups.trim() === this.NO_SOURCE_GROUPS_SELECTED;
  }

  isSourceGroupSelected(group: string): boolean {
    return !this.isNoSourceGroupsSelected() &&
      (this.isAllSourceGroupsSelected() || this.selectedSourceGroups().includes(group));
  }

  setSourceGroupSelected(group: string, selected: boolean): void {
    const selectedGroups = this.isAllSourceGroupsSelected() ? this.sourceGroups : this.selectedSourceGroups();
    if (selected) {
      if (!selectedGroups.includes(group)) {
        this.saveSelectedSourceGroups(selectedGroups.concat([group]), true);
      }
      return;
    }
    this.saveSelectedSourceGroups(selectedGroups.filter((item: string) => item !== group), true);
  }

  saveSelectedSourceGroups(groups: string[], shouldSave: boolean = true): void {
    const normalized: string[] = [];
    for (const group of groups) {
      const value = (group || '').trim();
      if (value && !normalized.includes(value)) {
        normalized.push(value);
      }
    }
    this.searchExploreSelectedSourceGroups = normalized.length > 0 ? normalized.join('\n') : this.NO_SOURCE_GROUPS_SELECTED;
    if (normalized.length >= this.sourceGroups.length) {
      this.searchExploreSelectedSourceGroups = '';
    }
    if (shouldSave) {
      this.onSettingChanged();
    }
  }

  saveAllSourceGroupsSelected(selected: boolean): void {
    this.searchExploreSelectedSourceGroups = selected ? '' : this.NO_SOURCE_GROUPS_SELECTED;
    this.onSettingChanged();
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

  pageColor(): string {
    return this.appDarkMode ? '#101113' : '#F5F5F5';
  }

  cardColor(): string {
    return this.appDarkMode ? '#191B1F' : '#FFFFFF';
  }

  primaryTextColor(): string {
    return this.appDarkMode ? '#F2F3F5' : '#1F1F1F';
  }

  subTextColor(): string {
    return this.appDarkMode ? '#8A8F98' : '#888';
  }

  buttonColor(): string {
    return this.appDarkMode ? this.appDarkButtonColor : this.appLightButtonColor;
  }

  syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, this.pageColor());
  }

  @Builder
  titleBar() {
    Row() {
      Text('<')
        .fontSize(24)
        .fontColor(this.primaryTextColor())
        .width(40)
        .height(56)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          router.back();
        })
      Text('搜索/发现配置')
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

  @Builder
  sectionTitle(title: string) {
    Text(title)
      .fontSize(13)
      .fontColor(this.subTextColor())
      .width('100%')
      .padding({ left: 16, right: 16, top: 20, bottom: 8 })
  }

  @Builder
  switchItem(title: string, desc: string, value: boolean, onChange: (value: boolean) => void) {
    Row() {
      Column() {
        Text(title)
          .fontSize(16)
          .fontColor(this.primaryTextColor())
        Text(desc)
          .fontSize(12)
          .fontColor(this.subTextColor())
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Toggle({ type: ToggleType.Switch, isOn: value })
        .selectedColor(this.buttonColor())
        .onChange((checked: boolean) => {
          onChange(checked);
        })
    }
    .width('100%')
    .constraintSize({ minHeight: 64 })
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .backgroundColor(this.cardColor())
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  numberSettingItem(title: string, desc: string, value: number, minValue: number, maxValue: number, onChange: (value: number) => void) {
    Row() {
      Column() {
        Text(title)
          .fontSize(16)
          .fontColor(this.primaryTextColor())
        Text(desc)
          .fontSize(12)
          .fontColor(this.subTextColor())
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Row() {
        Text('−')
          .fontSize(18)
          .fontColor(this.primaryTextColor())
          .width(30)
          .height(30)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            onChange(Math.max(minValue, this.searchExploreSearchConcurrency - 1));
          })

        Text(`${this.searchExploreSearchConcurrency}`)
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
            onChange(Math.min(maxValue, this.searchExploreSearchConcurrency + 1));
          })
      }
      .height(30)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .constraintSize({ minHeight: 64 })
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .backgroundColor(this.cardColor())
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  navItem(title: string, desc: string, url: string) {
    Row() {
      Column() {
        Text(title)
          .fontSize(16)
          .fontColor(this.primaryTextColor())
        Text(desc)
          .fontSize(12)
          .fontColor(this.subTextColor())
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Text('>')
        .fontSize(18)
        .fontColor(this.subTextColor())
    }
    .width('100%')
    .height(64)
    .padding({ left: 16, right: 16 })
    .backgroundColor(this.cardColor())
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      router.pushUrl({ url: url });
    })
  }

  @Builder
  sourceGroupSettings() {
    Column() {
      Row() {
        Column() {
          Text('搜索书源设置')
            .fontSize(16)
            .fontColor(this.primaryTextColor())
          Text(this.searchSourceGroupSummary())
            .fontSize(12)
            .fontColor(this.subTextColor())
            .margin({ top: 4 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })

      Row() {
        Toggle({ type: ToggleType.Checkbox, isOn: this.isAllSourceGroupsSelected() })
          .selectedColor(this.buttonColor())
          .onChange((isOn: boolean) => {
            this.saveAllSourceGroupsSelected(isOn);
          })
        Text('全部书源')
          .fontSize(14)
          .fontColor(this.primaryTextColor())
          .margin({ left: 8 })
          .layoutWeight(1)
      }
      .width('100%')
      .height(42)
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)

      ForEach(this.sourceGroups, (group: string) => {
        Row() {
          Toggle({ type: ToggleType.Checkbox, isOn: this.isSourceGroupSelected(group) })
            .selectedColor(this.buttonColor())
            .onChange((isOn: boolean) => {
              if (this.isAllSourceGroupsSelected() && !isOn) {
                this.saveSelectedSourceGroups(this.sourceGroups.filter((item: string) => item !== group), true);
                return;
              }
              this.setSourceGroupSelected(group, isOn);
            })
          Text(group)
            .fontSize(14)
            .fontColor(this.primaryTextColor())
            .margin({ left: 8 })
            .layoutWeight(1)
        }
        .width('100%')
        .height(40)
        .padding({ left: 16, right: 16 })
        .alignItems(VerticalAlign.Center)
      })
    }
    .width('100%')
    .backgroundColor(this.cardColor())
  }
}
