import { ReaderComicSuperResolutionAccess } from '@legado/aiengine';
import { AiAccessPolicy } from '../../account/AiAccessPolicy';
import { AppFontSize } from '../../theme/AppFontSize';
import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { ReaderSettingSelectRow } from './ReaderSettingRows';

/** 保留现有按书保存的繁→简设置；尚未上线的语言不可选择。 */
@Component
export struct ReaderComicTranslationRow {
  @StorageProp('aiTrialOpen') trialOpen: boolean = false;
  @StorageProp('accountLoggedIn') loggedIn: boolean = false;
  @Prop textConvert: boolean = false;
  @Prop access: string = ReaderComicSuperResolutionAccess.UNSUPPORTED;
  @Prop textColor: string = '#000000';
  @Prop subTextColor: string = '#666666';
  @Prop accentColor: string = '#0A59F7';
  @Prop dark: boolean = false;
  @Prop menuColor: string = '#FFFFFF';
  onChange: (enabled: boolean) => void = () => {};
  onOpenMembership: () => void = () => {};

  private description(): string {
    if (this.access === ReaderComicSuperResolutionAccess.MEMBER_REQUIRED) {
      return this.trialOpen && !this.loggedIn ? '登录后免费试用，至 10 月 31 日（北京时间）' :
        '免费试用已结束，开通会员继续使用';
    }
    if (this.access === ReaderComicSuperResolutionAccess.UNSUPPORTED) return '当前设备不支持系统文字识别';
    return (this.trialOpen ? `${AiAccessPolicy.TRIAL_LABEL}。` : '') +
      '借助AI识别并转换漫画对白；日→中、韩→中即将推出';
  }

  private selectOption(index: number): void {
    // 双重保护：未上线的选项既禁用点击，也不能通过回调更改书籍设置。
    if (index !== 0 && index !== 1) return;
    if (index === 1 && this.access !== ReaderComicSuperResolutionAccess.READY) {
      if (this.access === ReaderComicSuperResolutionAccess.MEMBER_REQUIRED) this.onOpenMembership();
      return;
    }
    this.onChange(index === 1);
  }

  build() {
    ReaderSettingSelectRow({
      title: 'AI翻译',
      minimumMembership: this.trialOpen ? '' : 'MONTHLY',
      description: this.description(),
      options: [{ value: '关闭' }, { value: '繁→简' }, { value: '日→中' }, { value: '韩→中' }],
      selected: this.textConvert ? 1 : 0,
      controlId: 'readerComicTranslationSelect',
      textColor: this.textColor,
      subTextColor: this.subTextColor,
      accentColor: this.accentColor,
      dark: this.dark,
      menuColor: this.menuColor,
      menuItemModifier: new TranslationMenuModifier(this.access, this.textColor, this.dark,
        () => this.selectOption(1)),
      onSelect: (index: number): void => this.selectOption(index)
    })
  }
}

/** 使用系统 Select 的弹层，只定制条目以支持禁用语言与“即将推出”提示。 */
class TranslationMenuModifier implements ContentModifier<MenuItemConfiguration> {
  access: string;
  textColor: string;
  dark: boolean;
  onAccessRequired: () => void;

  constructor(access: string, textColor: string, dark: boolean, onAccessRequired: () => void) {
    this.access = access;
    this.textColor = textColor;
    this.dark = dark;
    this.onAccessRequired = onAccessRequired;
  }

  enabled(index: number): boolean {
    return index === 0 || (index === 1 && this.access !== ReaderComicSuperResolutionAccess.UNSUPPORTED);
  }

  select(configuration: MenuItemConfiguration): void {
    if (!this.enabled(configuration.index)) return;
    if (configuration.index === 1 && this.access !== ReaderComicSuperResolutionAccess.READY) {
      this.onAccessRequired();
      return;
    }
    configuration.triggerSelect(configuration.index, configuration.index === 0 ? '关闭' : '繁→简');
  }

  applyContent(): WrappedBuilder<[MenuItemConfiguration]> {
    return wrapBuilder(translationMenuItem);
  }
}

@Builder
function translationMenuItem(configuration: MenuItemConfiguration) {
  Row({ space: 12 }) {
    Text(configuration.value)
      .fontSize(AppFontSize.BODY_LARGE)
      .fontColor((configuration.contentModifier as TranslationMenuModifier).textColor)
      .layoutWeight(1)
    if (configuration.index > 1) {
      Text('即将推出')
        .fontSize(AppFontSize.MICRO)
        .fontColor((configuration.contentModifier as TranslationMenuModifier).textColor)
    }
  }
  .constraintSize({ minWidth: 176, minHeight: 40 })
  .padding({ left: 12, right: 12 })
  .borderRadius(8)
  .backgroundColor(configuration.selected ?
    ThemeRuntime.accentSurfaceColor((configuration.contentModifier as TranslationMenuModifier).dark) : Color.Transparent)
  .opacity((configuration.contentModifier as TranslationMenuModifier).enabled(configuration.index) ? 1 : 0.38)
  .enabled((configuration.contentModifier as TranslationMenuModifier).enabled(configuration.index))
  .onClick(() => (configuration.contentModifier as TranslationMenuModifier).select(configuration))
}
