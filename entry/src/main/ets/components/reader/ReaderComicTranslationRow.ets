import { ReaderComicSuperResolutionAccess } from '@legado/aiengine';
import { AppFontSize } from '../../theme/AppFontSize';
import { ImmersiveMaterialRuntime } from '../../utils/ImmersiveMaterialRuntime';
import { PopupMenuAction } from '../common/PopupMenuAction';
import { ReaderSettingLabel } from './ReaderSettingRows';

/** 保留现有按书保存的繁→简设置；尚未上线的语言不可选择。 */
@Component
export struct ReaderComicTranslationRow {
  @StorageProp('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  @State menuVisible: boolean = false;
  @Prop textConvert: boolean = false;
  @Prop access: string = ReaderComicSuperResolutionAccess.UNSUPPORTED;
  @Prop textColor: string = '#000000';
  @Prop subTextColor: string = '#666666';
  @Prop accentColor: string = '#0A59F7';
  @Prop dark: boolean = false;
  onChange: (enabled: boolean) => void = () => {};
  onOpenMembership: () => void = () => {};

  private description(): string {
    if (this.access === ReaderComicSuperResolutionAccess.MEMBER_REQUIRED) {
      return this.textConvert ? '会员已到期，续费后恢复繁→简' : '借助AI识别漫画对白，并将繁体字转换为简体';
    }
    if (this.access === ReaderComicSuperResolutionAccess.UNSUPPORTED) return '当前设备不支持系统文字识别';
    return '借助AI识别并转换漫画对白；日→中、韩→中即将推出';
  }

  private selectOption(index: number): void {
    // 双重保护：未上线的选项既禁用点击，也不能通过回调更改书籍设置。
    if (index !== 0 && index !== 1) return;
    this.menuVisible = false;
    if (index === 1 && this.access !== ReaderComicSuperResolutionAccess.READY) {
      if (this.access === ReaderComicSuperResolutionAccess.MEMBER_REQUIRED) this.onOpenMembership();
      return;
    }
    this.onChange(index === 1);
  }

  @Builder
  translationMenu() {
    Column() {
      PopupMenuAction(undefined, '关闭', !this.textConvert ? this.accentColor : this.textColor,
        () => this.selectOption(0))
      PopupMenuAction(undefined, '繁→简', this.textConvert ? this.accentColor : this.textColor,
        () => this.selectOption(1), this.access !== ReaderComicSuperResolutionAccess.UNSUPPORTED)
      PopupMenuAction(undefined, '日→中', this.textColor, () => this.selectOption(2), false, '即将推出')
      PopupMenuAction(undefined, '韩→中', this.textColor, () => this.selectOption(3), false, '即将推出')
    }
    .width(216)
    .padding(ImmersiveMaterialRuntime.POPUP_MENU_PADDING)
  }

  build() {
    Row() {
      ReaderSettingLabel({
        title: 'AI翻译',
        minimumMembership: 'MONTHLY',
        description: this.description(),
        textColor: this.textColor,
        subTextColor: this.subTextColor
      })
      Button({ type: ButtonType.Normal }) {
        Row({ space: 6 }) {
          Text(this.textConvert ? '繁→简' : '关闭')
            .fontSize(AppFontSize.BODY)
            .fontColor(this.textColor)
          SymbolGlyph($r('sys.symbol.chevron_down'))
            .fontSize(14)
            .fontColor([this.textColor])
        }
      }
      .id('readerComicTranslationSelect')
      .height(40)
      .padding({ left: 12, right: 12 })
      .borderRadius(16)
      .backgroundColor(this.dark ? '#8030343B' : '#80ECEEF2')
      .accessibilityText(`AI翻译，当前${this.textConvert ? '繁→简' : '关闭'}`)
      .onClick(() => { this.menuVisible = !this.menuVisible; })
      .bindPopup(this.menuVisible, ImmersiveMaterialRuntime.popupMenuOptions(this.immersiveLightLevel,
        () => this.translationMenu(), Placement.Bottom, this.dark, this.accentColor,
        () => { this.menuVisible = false; }))
    }
    .width('100%')
    .constraintSize({ minHeight: 56 })
    .alignItems(VerticalAlign.Center)
  }
}
