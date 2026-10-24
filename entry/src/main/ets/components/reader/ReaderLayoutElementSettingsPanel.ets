import { ReaderSettingsStore } from '../../utils/ReaderSettingsStore';
import { HdsFeedback } from '../../utils/HdsFeedback';
import { ImmersiveBackButton } from '../ImmersiveBackButton';
import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { AdaptiveSwitch } from '../AdaptiveSwitch';
import { AppFontSize } from '../../theme/AppFontSize';
import { AppSpacing } from '../../theme/AppSpacing';

/**
 * 阅读页"布局元素设置"对话框内容：控制点击阅读页后出现哪些快捷组件。
 * 两个开关直接绑定全局设置并自行保存；由阅读页用系统对话框打开，配色跟随应用主题，由页面传入。
 */
@Component
export struct ReaderLayoutElementSettingsPanel {
  dark: boolean = false;
  textColor: string = '#202124';
  subTextColor: string = '#80868B';
  accentColor: string = '#0A59F7';
  onClose: () => void = (): void => {
  };
  /** 关掉章节快速跳转组件时，页面要复位章节滑杆的预览。 */
  onChapterQuickJumpChanged: (enabled: boolean) => void = (_enabled: boolean): void => {
  };

  @StorageLink('readerUseTtsQuickAction') readerUseTtsQuickAction: boolean = true;
  @StorageLink('readerUseChapterQuickJump') readerUseChapterQuickJump: boolean = true;

  private save(): void {
    ReaderSettingsStore.saveLayoutElementSettings(getContext(this), this.readerUseTtsQuickAction,
      this.readerUseChapterQuickJump).catch((e: Error) => {
      console.error('保存阅读布局元素设置失败:', e);
      HdsFeedback.showToast('布局元素设置保存失败');
    });
  }

  build() {
    Column({ space: AppSpacing.XS }) {
      Row() {
        Text('布局元素设置')
          .fontSize(AppFontSize.TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.textColor)
          .layoutWeight(1)
        ImmersiveBackButton({
          icon: $r('sys.symbol.xmark'),
          iconOffsetX: 0,
          iconColor: this.dark ? '#FFFFFFFF' : '#FF202124',
          darkMode: this.dark,
          buttonSize: 38,
          containerWidth: 38,
          containerHeight: 38,
          startInset: 0,
          compactLayout: true,
          accessibilityLabel: '关闭布局元素设置',
          onBack: () => this.onClose()
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text('控制点击阅读页后出现的快捷组件')
        .fontSize(AppFontSize.BODY)
        .fontColor(this.subTextColor)
        .width('100%')
        .margin({ bottom: AppSpacing.MD })

      this.toggleRow('使用快速朗读组件', '显示朗读快捷按钮和悬浮胶囊', this.readerUseTtsQuickAction,
        (enabled: boolean) => {
          this.readerUseTtsQuickAction = enabled;
          this.save();
        })
      this.toggleRow('使用章节快速跳转组件', '显示章节滑杆和上一章、下一章按钮', this.readerUseChapterQuickJump,
        (enabled: boolean) => {
          this.readerUseChapterQuickJump = enabled;
          this.onChapterQuickJumpChanged(enabled);
          this.save();
        })
    }
    .width('100%')
    .padding({ left: AppSpacing.XXL, right: AppSpacing.XXL, top: AppSpacing.XL, bottom: AppSpacing.XL })
  }

  @Builder
  toggleRow(title: string, description: string, enabled: boolean, onChange: (enabled: boolean) => void) {
    Row({ space: AppSpacing.LG }) {
      Column({ space: AppSpacing.XS }) {
        Text(title)
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.textColor)
        Text(description)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      AdaptiveSwitch({
        isOn: enabled,
        selectedColor: this.accentColor,
        onChange: onChange
      })
    }
    .width('100%')
    .constraintSize({ minHeight: 64 })
    .padding({ left: AppSpacing.LG, right: AppSpacing.MD })
    .borderRadius(ThemeRuntime.largeRadius())
    .backgroundColor(ThemeRuntime.softFillColor(this.dark))
    .alignItems(VerticalAlign.Center)
  }
}
