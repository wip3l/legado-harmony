import { bundleManager, common } from '@kit.AbilityKit';
import { promptAction, router } from '@kit.ArkUI';
import { syncSystemBars } from '../utils/SystemBars';
import { ThemeRuntime } from '../theme/ThemeRuntime';

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

          this.feedbackCard()

          this.infoCard('开源许可',
            '本项目采用 GPL-3.0 许可证。使用、修改和分发时请遵守对应开源协议。')

          this.infoCard('致谢',
            '感谢 @南破万卷墙 @一个人吃二二 @jueyaocaptain @茶安安安 @相思界 为App开发提出的建议和支持。')

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

  @Builder
  feedbackCard() {
    Column() {
      Text('问题反馈')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.primaryTextColor())
        .width('100%')

      this.feedbackRow('邮箱', 'i@icynol.com', () => {
        this.openUri('mailto:i@icynol.com', '未找到可用的邮件应用');
      })

      this.feedbackRow('QQ群', '345769197', () => {
        this.openUri('mqqapi://card/show_pslcard?src_type=internal&version=1&uin=345769197&card_type=group&source=qrcode',
          '未找到 QQ 或无法打开群资料');
      })
    }
    .width('100%')
    .padding(16)
    .backgroundColor(this.cardColor())
    .borderRadius(10)
    .margin({ left: 16, right: 16, bottom: 12 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  feedbackRow(label: string, value: string, action: () => void) {
    Row() {
      Text(`${label}：`)
        .fontSize(14)
        .fontColor(this.secondaryTextColor())
        .width(76)
      Text(value)
        .fontSize(14)
        .fontColor(this.accentColor())
    }
    .width('100%')
    .padding({ top: 12, bottom: 2 })
    .justifyContent(FlexAlign.Start)
    .onClick(action)
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

  secondaryTextColor(): string {
    return ThemeRuntime.subTextColor(this.appDarkMode);
  }

  subTextColor(): string {
    return ThemeRuntime.subTextColor(this.appDarkMode);
  }

  accentColor(): string {
    return ThemeRuntime.accentColor(this.appDarkMode);
  }

  openUri(uri: string, fallbackMessage: string): void {
    const context = getContext(this) as common.UIAbilityContext;
    context.startAbility({
      action: 'ohos.want.action.viewData',
      uri: uri
    }).catch((error: Error) => {
      console.error('打开外部应用失败:', error);
      this.showToastSafely(fallbackMessage);
    });
  }

  showToastSafely(message: string): void {
    try {
      promptAction.showToast({ message: message });
    } catch (error) {
      console.error('显示关于页提示失败:', error);
    }
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
