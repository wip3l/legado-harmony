import { router } from '@kit.ArkUI';

@Entry
@Component
struct AboutPage {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;

  build() {
    Column() {
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

        Text('关于')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())
          .layoutWeight(1)
      }
      .width('100%')
      .height(56)
      .backgroundColor(this.cardColor())
      .alignItems(VerticalAlign.Center)

      Scroll() {
        Column() {
          Column() {
            Text('阅')
              .fontSize(34)
              .fontColor('#FFFFFF')
          }
          .width(72)
          .height(72)
          .borderRadius(18)
          .backgroundColor('#007DFF')
          .justifyContent(FlexAlign.Center)
          .margin({ top: 28, bottom: 14 })

          Text('Legado Harmony')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.primaryTextColor())
          Text('1.0.0')
            .fontSize(13)
            .fontColor(this.subTextColor())
            .margin({ top: 6, bottom: 24 })

          this.infoCard('项目说明',
            'Legado Harmony 是面向 HarmonyOS NEXT 的阅读应用移植项目，目标是在鸿蒙端实现书源导入、搜索、发现、目录解析和正文阅读等核心能力。')

          this.infoCard('当前状态',
            '项目仍处于兼容完善阶段。常见 CSS、JSONPath、基础 XPath、旧式链式规则和正则捕获已有基础支持；复杂 JS、反爬验证和部分动态正文仍会按书源继续适配。')

          this.infoCard('开源许可',
            '本项目采用 GPL-3.0 许可证。使用、修改和分发时请遵守对应开源协议。')

          this.infoCard('致谢',
            '感谢 Legado / 阅读项目及其书源生态。本项目用于 HarmonyOS NEXT 端的学习、移植和兼容验证。')

          Column() {
            Text('仅用于学习与技术研究。请尊重版权，支持正版内容。')
              .fontSize(12)
              .fontColor(this.subTextColor())
              .textAlign(TextAlign.Center)
          }
          .width('100%')
          .padding({ left: 24, right: 24, top: 20, bottom: 32 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
      }
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageColor())
  }

  @Builder
  infoCard(title: string, content: string) {
    Column() {
      Text(title)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.primaryTextColor())
        .width('100%')
      Text(content)
        .fontSize(14)
        .fontColor(this.secondaryTextColor())
        .lineHeight(22)
        .width('100%')
        .margin({ top: 8 })
    }
    .width('100%')
    .padding(16)
    .backgroundColor(this.cardColor())
    .borderRadius(10)
    .margin({ left: 16, right: 16, bottom: 12 })
    .alignItems(HorizontalAlign.Start)
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

  secondaryTextColor(): string {
    return this.appDarkMode ? '#B8BDC7' : '#666666';
  }

  subTextColor(): string {
    return this.appDarkMode ? '#8A8F98' : '#888888';
  }
}
