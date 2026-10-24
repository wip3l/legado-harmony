import { MembershipBadge } from '../common/MembershipBadge';
import { AdaptiveSwitch } from '../AdaptiveSwitch';
import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { AppFontSize } from '../../theme/AppFontSize';
import { AppSpacing } from '../../theme/AppSpacing';
import { ImmersiveMaterialRuntime } from '../../utils/ImmersiveMaterialRuntime';

/** 阅读页设置面板里的一行：标题与说明，右侧放控件。配色用阅读主题，由页面传入。 */
@Component
export struct ReaderSettingLabel {
  @Prop title: string = '';
  @Prop minimumMembership: string = '';
  @Prop description: string = '';
  @Prop textColor: string = '#000000';
  @Prop subTextColor: string = '#666666';

  build() {
    Column() {
      Row({ space: AppSpacing.XS }) {
        Text(this.title)
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.textColor)
          .flexShrink(1)
        if (this.minimumMembership) {
          MembershipBadge({ sku: this.minimumMembership })
        }
      }
      Text(this.description)
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor)
        .margin({ top: AppSpacing.XS })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
  }
}

@Component
export struct ReaderSettingSwitchRow {
  @Prop title: string = '';
  @Prop minimumMembership: string = '';
  @Prop description: string = '';
  @Prop checked: boolean = false;
  @Prop textColor: string = '#000000';
  @Prop subTextColor: string = '#666666';
  onChange: (checked: boolean) => void = () => {};

  build() {
    Row() {
      ReaderSettingLabel({
        title: this.title,
        minimumMembership: this.minimumMembership,
        description: this.description,
        textColor: this.textColor,
        subTextColor: this.subTextColor
      })
        .layoutWeight(1)
      AdaptiveSwitch({
        isOn: this.checked,
        onChange: (value: boolean) => {
          this.onChange(value);
        }
      })
    }
    .width('100%')
    .constraintSize({ minHeight: 56 })
    .alignItems(VerticalAlign.Center)
  }
}

@Component
export struct ReaderSettingSelectRow {
  @StorageProp('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  @Prop title: string = '';
  @Prop minimumMembership: string = '';
  @Prop description: string = '';
  @Prop options: SelectOption[] = [];
  @Prop selected: number = 0;
  @Prop controlId: string = '';
  @Prop textColor: string = '#000000';
  @Prop subTextColor: string = '#666666';
  @Prop accentColor: string = '#0A59F7';
  @Prop dark: boolean = false;
  /** 下拉菜单底色（随阅读主题）。 */
  @Prop menuColor: string = '#FFFFFF';
  menuItemModifier: ContentModifier<MenuItemConfiguration> | undefined = undefined;
  onSelect: (index: number) => void = () => {};

  private selectedValue(): ResourceStr {
    if (this.selected >= 0 && this.selected < this.options.length) return this.options[this.selected].value;
    return this.options.length > 0 ? this.options[0].value : '';
  }

  build() {
    Row() {
      ReaderSettingLabel({
        title: this.title,
        minimumMembership: this.minimumMembership,
        description: this.description,
        textColor: this.textColor,
        subTextColor: this.subTextColor
      })
        .layoutWeight(1)

      Select(this.options)
        .id(this.controlId)
        .selected(this.selected)
        .value(this.selectedValue())
        .font({ size: AppFontSize.BODY })
        .fontColor(this.textColor)
        .backgroundColor(this.dark ? '#8030343B' : '#80ECEEF2')
        .arrowPosition(ArrowPosition.END)
        .padding({ left: 12, right: 12 })
        // Keep the hit area rectangular, but soften its corners to match the rounded settings cards.
        .borderRadius(16)
        .border({ width: 0 })
        .optionBgColor(Color.Transparent)
        .divider(null)
        .optionFontColor(this.textColor)
        .selectedOptionFontColor(this.textColor)
        .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.dark))
        .menuBackgroundColor(this.menuColor)
        .menuBackgroundBlurStyle(BlurStyle.NONE)
        .menuItemContentModifier(this.menuItemModifier)
        .attributeModifier(ImmersiveMaterialRuntime.selectMenuModifier(this.immersiveLightLevel, this.dark, this.menuColor))
        .onSelect((index: number) => {
          this.onSelect(index);
        })
    }
    .width('100%')
    .constraintSize({ minHeight: 56 })
    .alignItems(VerticalAlign.Center)
  }
}

/** 右侧是一个按钮的设置行（如“点击区域动作 · 配置”）。 */
@Component
export struct ReaderSettingActionRow {
  @Prop title: string = '';
  @Prop minimumMembership: string = '';
  @Prop description: string = '';
  @Prop actionText: string = '';
  @Prop textColor: string = '#000000';
  @Prop subTextColor: string = '#666666';
  @Prop buttonColor: string = '#0A59F7';
  @Prop buttonTextColor: string = '#FFFFFF';
  onAction: () => void = () => {};

  build() {
    Row() {
      ReaderSettingLabel({
        title: this.title,
        minimumMembership: this.minimumMembership,
        description: this.description,
        textColor: this.textColor,
        subTextColor: this.subTextColor
      })
        .layoutWeight(1)

      // 没有按钮文字时只显示说明（如功能不可用）。
      if (this.actionText) {
        Button(this.actionText)
          .height(34)
          .fontSize(AppFontSize.BODY)
          .backgroundColor(this.buttonColor)
          .fontColor(this.buttonTextColor)
          .margin({ left: AppSpacing.LG })
          .onClick(() => this.onAction())
      }
    }
    .width('100%')
    .constraintSize({ minHeight: 56 })
    .alignItems(VerticalAlign.Center)
  }
}
