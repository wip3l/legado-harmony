import { router } from '@kit.ArkUI';
import { syncSystemBars } from '../utils/SystemBars';
import { SearchExploreSettings, SearchExploreSettingsStore } from '../utils/SearchExploreSettingsStore';

@Entry
@Component
struct SearchExploreSettingsPage {
  @StorageLink('searchExploreShowResultCover') searchExploreShowResultCover: boolean = true;
  @StorageLink('searchExploreShowResultTags') searchExploreShowResultTags: boolean = true;
  @StorageLink('searchExplorePromptAddToShelfOnBack') searchExplorePromptAddToShelfOnBack: boolean = true;
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;

  aboutToAppear(): void {
    this.reloadSettings();
    this.syncBars();
  }

  onPageShow(): void {
    this.reloadSettings();
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
      this.searchExploreShowResultTags = settings.showResultTags;
      this.searchExplorePromptAddToShelfOnBack = settings.promptAddToShelfOnBack;
    } catch (e) {
      console.warn('重新加载搜索/发现配置失败:', e);
    }
  }

  onSettingChanged(): void {
    const settings = new SearchExploreSettings();
    settings.showResultCover = this.searchExploreShowResultCover;
    settings.showResultTags = this.searchExploreShowResultTags;
    settings.promptAddToShelfOnBack = this.searchExplorePromptAddToShelfOnBack;
    SearchExploreSettingsStore.applyToStorage(settings);
    SearchExploreSettingsStore.save(getContext(this), settings).catch((e: Error) => {
      console.warn('保存搜索/发现配置失败:', e);
    });
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
}
