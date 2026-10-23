import { syncSystemBars } from '../utils/SystemBars';
import { SearchExploreSettings, SearchExploreSettingsStore } from '../utils/SearchExploreSettingsStore';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { PageScaffold } from '../components/common/PageScaffold';
import { SettingRow, SettingSwitchRow } from '../components/common/SettingRow';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';

@Entry
@Component
struct SearchExploreSettingsPage {
  @StorageLink('searchExploreShowResultCover') searchExploreShowResultCover: boolean = true;
  @StorageLink('searchExploreShowResultCoverBackground') searchExploreShowResultCoverBackground: boolean = true;
  @StorageLink('searchExploreUseBookshelfCoverGallery') searchExploreUseBookshelfCoverGallery: boolean = false;
  @StorageLink('searchExploreShowResultTags') searchExploreShowResultTags: boolean = true;
  @StorageLink('searchExploreAggregateResults') searchExploreAggregateResults: boolean = true;
  @StorageLink('searchExplorePromptAddToShelfOnBack') searchExplorePromptAddToShelfOnBack: boolean = true;
  @StorageLink('searchExploreExactSearch') searchExploreExactSearch: boolean = false;
  @StorageLink('searchExploreExactSearchMatchAuthor') searchExploreExactSearchMatchAuthor: boolean = true;
  @StorageLink('searchExploreShowSearchProgress') searchExploreShowSearchProgress: boolean = true;
  @StorageLink('searchExploreSearchConcurrency') searchExploreSearchConcurrency: number = 6;
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageLink('appLightButtonColor') appLightButtonColor: string = '#007DFF';
  @StorageLink('appDarkButtonColor') appDarkButtonColor: string = '#3F8CFF';

  aboutToAppear(): void {
    this.reloadSettings();
    this.syncBars();
  }

  onPageShow(): void {
    this.reloadSettings();
    this.syncBars();
  }

  build() {
    Stack() {
      PageScaffold({ title: '搜索/发现配置', content: () => {
        this.pageContent()
      } })
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  pageContent() {
    this.sectionTitle('结果展示')
    Column() {
      SettingSwitchRow({
        title: '显示结果封面',
        description: '在搜索和发现结果中显示封面',
        isOn: this.searchExploreShowResultCover,
        onChange: (value: boolean) => {
          this.searchExploreShowResultCover = value;
          this.onSettingChanged();
        }
      })
      if (this.searchExploreShowResultCover) {
        SettingSwitchRow({
          title: '使用书架封面',
          description: '搜索、发现及书籍详情沿用书架的封面来源、适用范围和展示方式',
          isOn: this.searchExploreUseBookshelfCoverGallery,
          onChange: (value: boolean) => {
            this.searchExploreUseBookshelfCoverGallery = value;
            this.onSettingChanged();
          }
        })
      }
      SettingSwitchRow({
        title: '封面模糊背景',
        description: '在搜索和发现结果列表中显示封面模糊背景',
        isOn: this.searchExploreShowResultCoverBackground,
        onChange: (value: boolean) => {
          this.searchExploreShowResultCoverBackground = value;
          this.onSettingChanged();
        }
      })
      SettingSwitchRow({
        title: '显示结果标签',
        description: '在搜索和发现结果中显示标签',
        isOn: this.searchExploreShowResultTags,
        showDivider: false,
        onChange: (value: boolean) => {
          this.searchExploreShowResultTags = value;
          this.onSettingChanged();
        }
      })
    }
    .width('calc(100% - 24vp)')
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(this.cardColor())

    this.sectionTitle('书架提示')
    Column() {
      SettingSwitchRow({
        title: '返回提示加入书架',
        description: '从搜索或发现试读后，返回时询问是否加入书架',
        isOn: this.searchExplorePromptAddToShelfOnBack,
        showDivider: false,
        onChange: (value: boolean) => {
          this.searchExplorePromptAddToShelfOnBack = value;
          this.onSettingChanged();
        }
      })
    }
    .width('calc(100% - 24vp)')
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(this.cardColor())

    this.sectionTitle('搜索设置')
    Column() {
      SettingSwitchRow({
        title: '精准搜索',
        description: '只保留书名与关键词完全一致的结果',
        isOn: this.searchExploreExactSearch,
        onChange: (value: boolean) => {
          this.searchExploreExactSearch = value;
          this.onSettingChanged();
        }
      })
      SettingSwitchRow({
        title: '匹配作者',
        description: '精准搜索时，关键词也可匹配作者',
        isOn: this.searchExploreExactSearchMatchAuthor,
        onChange: (value: boolean) => {
          this.searchExploreExactSearchMatchAuthor = value;
          this.onSettingChanged();
        }
      })
      SettingSwitchRow({
        title: '显示搜索进度',
        description: '搜索时显示已搜书源数和结果数',
        isOn: this.searchExploreShowSearchProgress,
        onChange: (value: boolean) => {
          this.searchExploreShowSearchProgress = value;
          this.onSettingChanged();
        }
      })
      SettingSwitchRow({
        title: '聚合同名结果',
        description: '同名书合并为一条，点开查看各书源结果',
        isOn: this.searchExploreAggregateResults,
        onChange: (value: boolean) => {
          this.searchExploreAggregateResults = value;
          this.onSettingChanged();
        }
      })
      SettingRow({ title: '搜索并发数', description: '同时请求的书源数，搜书、换源、找封面和搜索校验共用',
        showDivider: false }) {
        this.concurrencyStepper()
      }
    }
    .width('calc(100% - 24vp)')
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(this.cardColor())
  }

  async reloadSettings(): Promise<void> {
    try {
      const settings = await SearchExploreSettingsStore.load(getContext(this));
      this.searchExploreShowResultCover = settings.showResultCover;
      this.searchExploreShowResultCoverBackground = settings.showResultCoverBackground;
      this.searchExploreUseBookshelfCoverGallery = settings.useBookshelfCoverGallery;
      this.searchExploreShowResultTags = settings.showResultTags;
      this.searchExploreAggregateResults = settings.aggregateSearchResults;
      this.searchExplorePromptAddToShelfOnBack = settings.promptAddToShelfOnBack;
      this.searchExploreExactSearch = settings.exactSearch;
      this.searchExploreExactSearchMatchAuthor = settings.exactSearchMatchAuthor;
      this.searchExploreShowSearchProgress = settings.showSearchProgress;
      this.searchExploreSearchConcurrency = settings.searchConcurrency;
    } catch (e) {
      console.warn('重新加载搜索/发现配置失败:', e);
    }
  }

  setSearchConcurrency(value: number): void {
    this.searchExploreSearchConcurrency = SearchExploreSettingsStore.normalizeSearchConcurrency(value);
    this.onSettingChanged();
  }

  onSettingChanged(): void {
    SearchExploreSettingsStore.load(getContext(this)).then((settings: SearchExploreSettings) => {
      settings.showResultCover = this.searchExploreShowResultCover;
      settings.showResultCoverBackground = this.searchExploreShowResultCoverBackground;
      settings.useBookshelfCoverGallery = this.searchExploreUseBookshelfCoverGallery;
      settings.showResultTags = this.searchExploreShowResultTags;
      settings.aggregateSearchResults = this.searchExploreAggregateResults;
      settings.promptAddToShelfOnBack = this.searchExplorePromptAddToShelfOnBack;
      settings.exactSearch = this.searchExploreExactSearch;
      settings.exactSearchMatchAuthor = this.searchExploreExactSearchMatchAuthor;
      settings.showSearchProgress = this.searchExploreShowSearchProgress;
      settings.searchConcurrency = SearchExploreSettingsStore.normalizeSearchConcurrency(this.searchExploreSearchConcurrency);
      SearchExploreSettingsStore.applyToStorage(settings);
      return SearchExploreSettingsStore.save(getContext(this), settings);
    }).catch((e: Error) => {
      console.warn('保存搜索/发现配置失败:', e);
    });
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

  @Builder
  sectionTitle(title: string) {
    Text(title)
      .fontSize(AppFontSize.BODY)
      .fontColor(this.subTextColor())
      .width('100%')
      .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.XXL, bottom: AppSpacing.MD })
  }

  @Builder
  concurrencyStepper() {
    Row() {
      Text('−')
        .fontSize(AppFontSize.SUBTITLE)
        .fontColor(this.primaryTextColor())
        .width(30)
        .height(30)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.setSearchConcurrency(this.searchExploreSearchConcurrency - 1);
        })

      Text(`${this.searchExploreSearchConcurrency}`)
        .fontSize(AppFontSize.BODY_LARGE)
        .fontColor(this.primaryTextColor())
        .width(42)
        .textAlign(TextAlign.Center)

      Text('+')
        .fontSize(AppFontSize.SUBTITLE)
        .fontColor(this.primaryTextColor())
        .width(30)
        .height(30)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.setSearchConcurrency(this.searchExploreSearchConcurrency + 1);
        })
    }
    .height(30)
    .alignItems(VerticalAlign.Center)
  }

}
