import { bundleManager } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { syncSystemBars } from '../utils/SystemBars';

@Entry
@Component
struct AboutPage {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @State appVersionName: string = '';

  aboutToAppear(): void {
    this.syncBars();
    this.loadAppVersion();
  }

  onPageShow(): void {
    this.syncBars();
  }

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
            Image($r('app.media.icon'))
              .width(72)
              .height(72)
              .borderRadius(18)
          }
          .width(72)
          .height(72)
          .borderRadius(18)
          .justifyContent(FlexAlign.Center)
          .margin({ top: 28, bottom: 14 })

          Text('开源轻页')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.primaryTextColor())
          Text(this.appVersionName || '-')
            .fontSize(13)
            .fontColor(this.subTextColor())
            .margin({ top: 6, bottom: 24 })

          this.infoCard('项目说明',
            '开源轻页是一个本地阅读与书源规则兼容项目，用于验证用户自行提供且有合法使用权限的规则在移动端的导入、解析和阅读体验。')

          this.infoCard('合规说明',
            '本项目不内置、不托管、不分发任何小说正文、章节内容、封面图片或付费资源；不提供书源订阅服务，也不推荐、维护或背书任何第三方内容站点。')

          this.infoCard('使用提醒',
            '导入书源前，请自行确认书源来源、目标站点协议、内容授权和所在地法律法规要求。项目仅按用户配置的规则发起访问和解析，不以破解付费内容、绕过访问控制、规避反爬机制或批量抓取受保护内容为目标。')

          this.infoCard('开源许可',
            '本项目采用 GPL-3.0 许可证。使用、修改和分发时请遵守对应开源协议。')

          Column() {
            Text('请仅使用自有、授权或明确允许访问的内容与规则。')
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
    .padding({ top: this.statusBarHeight, bottom: this.navBarHeight })
    .backgroundColor(this.pageColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
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

  syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, this.pageColor());
  }

  loadAppVersion(): void {
    try {
      const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      this.appVersionName = info.versionName || '';
    } catch (error) {
      console.error('获取应用版本信息失败:', error);
      this.appVersionName = '';
    }
  }
}
