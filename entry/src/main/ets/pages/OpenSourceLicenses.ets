import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { syncSystemBars } from '../utils/SystemBars';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { PageScaffold } from '../components/common/PageScaffold';

@Entry
@Component
struct OpenSourceLicensesPage {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @State licenseText: string = '正在加载开源许可…';

  aboutToAppear(): void {
    this.syncBars();
    this.loadLicenseText();
  }

  onPageShow(): void {
    this.syncBars();
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      PageScaffold({ title: '开源软件许可', bottomInset: 0, content: () => {
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
    Column() {
      Column() {
        Text('开源轻页采用 GPL-3.0 许可证，并包含 ohos_quickjs、QuickJS、OpenCC 简繁字典和部分 OpenHarmony/Huawei N-API 封装代码。以下源码信息、版权声明与完整许可文本随 HAP 一同分发。')
          .fontSize(AppFontSize.BODY)
          .fontColor(this.secondaryTextColor())
          .lineHeight(22)
          .width('100%')
      }
      .width('100%')
      .padding(AppSpacing.XL)
      .backgroundColor(this.cardColor())
      .borderRadius(ThemeRuntime.cardRadius())
      .margin({ left: AppSpacing.XL, right: AppSpacing.XL, bottom: AppSpacing.LG })
      .alignItems(HorizontalAlign.Start)

      Column() {
        Text(this.licenseText)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.primaryTextColor())
          .lineHeight(19)
          .width('100%')
          .copyOption(CopyOptions.LocalDevice)
      }
      .width('100%')
      .padding(AppSpacing.XL)
      .backgroundColor(this.cardColor())
      .borderRadius(ThemeRuntime.cardRadius())
      .margin({ left: AppSpacing.XL, right: AppSpacing.XL, bottom: AppSpacing.XXXL })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  async loadLicenseText(): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    try {
      const gplBytes = await context.resourceManager.getRawFileContent('licenses/GPL-3.0.txt');
      const thirdPartyBytes = await context.resourceManager
        .getRawFileContent('licenses/THIRD_PARTY_LICENSES.txt');
      const projectNotice = 'OPEN SOURCE PROJECT INFORMATION\n' +
        '开源项目信息\n\n' +
        'Project / 项目：开源轻页 / qingye-reader\n' +
        'Copyright (c) 2026 李其健\n' +
        'Source / 源码：https://github.com/wip3l/qingye-reader\n' +
        'License / 许可证：GNU General Public License version 3 (GPL-3.0)\n\n';
      const gplText = util.TextDecoder.create('utf-8').decodeWithStream(gplBytes, { stream: false });
      const thirdPartyText = util.TextDecoder.create('utf-8')
        .decodeWithStream(thirdPartyBytes, { stream: false });
      const openccBytes = await context.resourceManager.getRawFileContent('opencc/LICENSE');
      const openccText = util.TextDecoder.create('utf-8').decodeWithStream(openccBytes, { stream: false });
      this.licenseText = projectNotice + gplText + '\n\n' + thirdPartyText +
        '\n\nOpenCC ver.1.1.9 — TSCharacters / TSPhrases\n' +
        'Authors: BYVoid and OpenCC contributors\n' +
        'https://github.com/BYVoid/OpenCC/tree/ver.1.1.9\n' + openccText;
    } catch (error) {
      console.error('加载开源许可失败:', error);
      this.licenseText = '开源许可文本加载失败，请查看项目根目录 LICENSE、NOTICE 和 THIRD_PARTY_NOTICES.md。';
    }
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

  syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, this.pageColor());
  }
}
