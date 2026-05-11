import { router } from '@kit.ArkUI';
import { ConfigurationConstant } from '@kit.AbilityKit';

@Entry
@Component
struct SettingsPage {
  @StorageLink('appThemeMode') appThemeMode: string = 'system';
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('readerFontSize') readerFontSize: number = 20;
  @StorageLink('readerLineHeight') readerLineHeight: number = 32;
  @StorageLink('readerParagraphSpacing') readerParagraphSpacing: number = 10;
  @StorageLink('readerThemeIndex') readerThemeIndex: number = 0;
  @StorageLink('readerPageTurnMode') readerPageTurnMode: number = 0;
  @StorageLink('readerTapTurnPage') readerTapTurnPage: boolean = true;
  @StorageLink('readerVolumeTurnPage') readerVolumeTurnPage: boolean = false;
  @StorageLink('readerKeepScreenOn') readerKeepScreenOn: boolean = true;
  @StorageLink('readerExtendToStatusBar') readerExtendToStatusBar: boolean = false;

  private themes: string[] = ['#F7F1E3', '#FFFFFF', '#E9F3E5', '#1F2329'];
  private themeNames: string[] = ['米黄', '素白', '青绿', '夜间'];

  aboutToAppear() {
    this.applyThemeMode(this.appThemeMode);
  }

  build() {
    Column() {
      this.titleBar()

      Scroll() {
        Column() {
          this.sectionTitle('App 配色')
          this.appThemeOptions()

          this.sectionTitle('排版')
          this.valueSlider('字号', `${this.readerFontSize}sp`, this.readerFontSize, 14, 30, 1, (value: number) => {
            this.readerFontSize = Math.round(value);
          })
          this.valueSlider('行距', `${this.readerLineHeight}px`, this.readerLineHeight, 24, 52, 1, (value: number) => {
            this.readerLineHeight = Math.round(value);
          })
          this.valueSlider('段落间距', `${this.readerParagraphSpacing}px`, this.readerParagraphSpacing, 0, 32, 1, (value: number) => {
            this.readerParagraphSpacing = Math.round(value);
          })

          this.sectionTitle('阅读背景')
          Row() {
            ForEach(this.themes, (color: string, index: number) => {
              Column() {
                Text('')
                  .width(44)
                  .height(44)
                  .borderRadius(22)
                  .backgroundColor(color)
                  .border({
                    width: this.readerThemeIndex === index ? 3 : 1,
                    color: this.readerThemeIndex === index ? '#007DFF' : '#22000000'
                  })
                Text(this.themeNames[index])
                  .fontSize(12)
                  .fontColor(this.subTextColor())
                  .margin({ top: 6 })
              }
              .margin({ right: 18 })
              .onClick(() => {
                this.readerThemeIndex = index;
              })
            })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 16 })
          .backgroundColor(this.cardColor())

          this.sectionTitle('翻页方式')
          this.pageTurnOptions()
          this.switchItem('点击区域翻页', '开启后点击阅读页左右区域切换上一章/下一章', this.readerTapTurnPage, (value: boolean) => {
            this.readerTapTurnPage = value;
          })
          this.switchItem('音量键翻页', '预留给设备音量键翻页能力，后续接入系统按键事件', this.readerVolumeTurnPage, (value: boolean) => {
            this.readerVolumeTurnPage = value;
          })
          this.switchItem('阅读时保持屏幕常亮', '进入阅读页后尽量避免自动息屏', this.readerKeepScreenOn, (value: boolean) => {
            this.readerKeepScreenOn = value;
          })
          this.switchItem('正文扩展至状态栏', '开启后正文阅读区域会延伸到顶部状态栏安全区', this.readerExtendToStatusBar, (value: boolean) => {
            this.readerExtendToStatusBar = value;
          })

          this.sectionTitle('预览')
          Column() {
            Text('第一章 风起')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.previewTitleColor())
              .width('100%')
              .margin({ bottom: 12 })

            Text('这是一段阅读设置预览文字。调整字号、行距、段落间距、背景与翻页方式后，可以在这里感受阅读页的大致观感。')
              .fontSize(this.readerFontSize)
              .fontColor(this.previewTextColor())
              .lineHeight(this.readerLineHeight)
              .padding({ bottom: this.readerParagraphSpacing })

            Text(`当前翻页：${this.pageTurnModeText()}`)
              .fontSize(12)
              .fontColor(this.previewSubTextColor())
              .width('100%')
              .margin({ top: 10 })
          }
          .width('100%')
          .padding(18)
          .backgroundColor(this.previewBackgroundColor())
          .borderRadius(10)
          .margin({ left: 16, right: 16, top: 12, bottom: 32 })
        }
        .width('100%')
      }
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageColor())
  }

  applyThemeMode(mode: string) {
    this.appThemeMode = mode;
    if (mode === 'dark') {
      this.appDarkMode = true;
      getContext(this).getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    } else if (mode === 'light') {
      this.appDarkMode = false;
      getContext(this).getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
    } else {
      getContext(this).getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    }
  }

  pageTurnModeText(): string {
    if (this.readerPageTurnMode === 1) return '滑动翻章';
    if (this.readerPageTurnMode === 2) return '点击翻章';
    return '滚动阅读';
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

  previewBackgroundColor(): string {
    return this.themes[this.readerThemeIndex] || this.themes[0];
  }

  previewTitleColor(): string {
    return this.readerThemeIndex === 3 ? '#E8EAED' : '#1F1F1F';
  }

  previewTextColor(): string {
    return this.readerThemeIndex === 3 ? '#DADCE0' : '#333333';
  }

  previewSubTextColor(): string {
    return this.readerThemeIndex === 3 ? '#9AA0A6' : '#776B5F';
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

      Text('阅读设置')
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
  appThemeOptions() {
    Row({ space: 8 }) {
      Text('跟随系统')
        .fontSize(14)
        .fontColor(this.appThemeMode === 'system' ? '#FFFFFF' : this.primaryTextColor())
        .textAlign(TextAlign.Center)
        .layoutWeight(1)
        .height(38)
        .borderRadius(19)
        .backgroundColor(this.appThemeMode === 'system' ? '#007DFF' : (this.appDarkMode ? '#24272D' : '#F0F2F5'))
        .onClick(() => {
          this.applyThemeMode('system');
        })
      Text('浅色')
        .fontSize(14)
        .fontColor(this.appThemeMode === 'light' ? '#FFFFFF' : this.primaryTextColor())
        .textAlign(TextAlign.Center)
        .layoutWeight(1)
        .height(38)
        .borderRadius(19)
        .backgroundColor(this.appThemeMode === 'light' ? '#007DFF' : (this.appDarkMode ? '#24272D' : '#F0F2F5'))
        .onClick(() => {
          this.applyThemeMode('light');
        })
      Text('深色')
        .fontSize(14)
        .fontColor(this.appThemeMode === 'dark' ? '#FFFFFF' : this.primaryTextColor())
        .textAlign(TextAlign.Center)
        .layoutWeight(1)
        .height(38)
        .borderRadius(19)
        .backgroundColor(this.appThemeMode === 'dark' ? '#007DFF' : (this.appDarkMode ? '#24272D' : '#F0F2F5'))
        .onClick(() => {
          this.applyThemeMode('dark');
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor(this.cardColor())
  }

  @Builder
  pageTurnOptions() {
    Row({ space: 8 }) {
      Text('滚动阅读')
        .fontSize(14)
        .fontColor(this.readerPageTurnMode === 0 ? '#FFFFFF' : this.primaryTextColor())
        .textAlign(TextAlign.Center)
        .layoutWeight(1)
        .height(38)
        .borderRadius(19)
        .backgroundColor(this.readerPageTurnMode === 0 ? '#007DFF' : (this.appDarkMode ? '#24272D' : '#F0F2F5'))
        .onClick(() => {
          this.readerPageTurnMode = 0;
        })
      Text('滑动翻章')
        .fontSize(14)
        .fontColor(this.readerPageTurnMode === 1 ? '#FFFFFF' : this.primaryTextColor())
        .textAlign(TextAlign.Center)
        .layoutWeight(1)
        .height(38)
        .borderRadius(19)
        .backgroundColor(this.readerPageTurnMode === 1 ? '#007DFF' : (this.appDarkMode ? '#24272D' : '#F0F2F5'))
        .onClick(() => {
          this.readerPageTurnMode = 1;
        })
      Text('点击翻章')
        .fontSize(14)
        .fontColor(this.readerPageTurnMode === 2 ? '#FFFFFF' : this.primaryTextColor())
        .textAlign(TextAlign.Center)
        .layoutWeight(1)
        .height(38)
        .borderRadius(19)
        .backgroundColor(this.readerPageTurnMode === 2 ? '#007DFF' : (this.appDarkMode ? '#24272D' : '#F0F2F5'))
        .onClick(() => {
          this.readerPageTurnMode = 2;
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor(this.cardColor())
  }

  @Builder
  valueSlider(
    title: string,
    valueText: string,
    value: number,
    min: number,
    max: number,
    step: number,
    onChange: (value: number) => void
  ) {
    Column() {
      Row() {
        Text(title)
          .fontSize(16)
          .fontColor(this.primaryTextColor())
          .layoutWeight(1)
        Text(valueText)
          .fontSize(14)
          .fontColor(this.subTextColor())
      }
      .width('100%')

      Slider({ value: value, min: min, max: max, step: step })
        .width('100%')
        .margin({ top: 8 })
        .onChange((sliderValue: number) => {
          onChange(sliderValue);
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor(this.cardColor())
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
  }
}
