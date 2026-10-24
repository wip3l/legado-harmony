import { ReaderComicTranslationRow } from './ReaderComicTranslationRow';
import { AiAccessPolicy } from '../../account/AiAccessPolicy';
import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { AppFontSize } from '../../theme/AppFontSize';
import { AppSpacing } from '../../theme/AppSpacing';
import {
  ReaderComicBackground,
  ReaderComicFit,
  ReaderComicMode,
  ReaderComicOption
} from '../../core/reader/ReaderComicSettings';
import { ReaderComicSuperResolutionAccess } from '@legado/aiengine';
import { ReaderSettingActionRow, ReaderSettingSelectRow, ReaderSettingSwitchRow } from './ReaderSettingRows';

/** 阅读主题下的设置面板配色，由阅读页传入。 */
export class ReaderComicPanelColors {
  textColor: string = '#000000';
  subTextColor: string = '#666666';
  accentColor: string = '#0A59F7';
  dark: boolean = false;
  /** 下拉菜单底色。 */
  menuColor: string = '#FFFFFF';
  buttonColor: string = '#0A59F7';
  buttonTextColor: string = '#FFFFFF';
}

/** 阅读方式面板里“本书阅读方式”的取值：三种漫画方式之外再加“文字阅读”（退出漫画模式）。 */
export const READER_COMIC_TEXT_MODE: string = 'text';

/** 一组并排的选项块。 */
@Component
export struct ReaderComicOptionGroup {
  @Prop title: string = '';
  @Prop options: ReaderComicOption[] = [];
  @Prop selected: string = '';
  @Prop colors: ReaderComicPanelColors = new ReaderComicPanelColors();
  onSelect: (value: string) => void = () => {};

  build() {
    Column({ space: AppSpacing.MD }) {
      Text(this.title)
        .fontSize(AppFontSize.BODY_LARGE)
        .fontColor(this.colors.textColor)
      Row({ space: AppSpacing.MD }) {
        ForEach(this.options, (option: ReaderComicOption) => {
          Row({ space: AppSpacing.SM }) {
            if (option.swatch) {
              Row()
                .width(14)
                .height(14)
                .borderRadius(7)
                .backgroundColor(option.swatch)
                .border({ width: 1, color: this.colors.dark ? '#55FFFFFF' : '#33000000' })
            }
            Text(option.label)
              .fontSize(AppFontSize.BODY)
              .fontColor(this.colors.textColor)
              .fontWeight(this.selected === option.value ? FontWeight.Bold : FontWeight.Regular)
              .maxLines(1)
          }
          .layoutWeight(1)
          .height(40)
          .justifyContent(FlexAlign.Center)
          .borderRadius(20)
          .backgroundColor(this.selected === option.value ? ThemeRuntime.accentSurfaceColor(this.colors.dark) :
            (this.colors.dark ? '#14FFFFFF' : '#0D000000'))
          .border({ width: this.selected === option.value ? 1.5 : 0, color: this.colors.accentColor })
          .onClick(() => this.onSelect(option.value))
        }, (option: ReaderComicOption) => `${option.value}_${this.selected === option.value ? 1 : 0}`)
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

/** 漫画「阅读方式」面板。设置的读写都在阅读页，这里只负责显示与回调。 */
@Component
export struct ReaderComicModeSettingsPanel {
  /** 本书当前生效的漫画阅读方式。 */
  @Prop mode: string = ReaderComicMode.WEBTOON;
  @Prop defaultMode: string = ReaderComicMode.WEBTOON;
  @Prop tapTurn: boolean = true;
  @Prop dualPage: boolean = true;
  @Prop volumeTurnPage: boolean = false;
  @Prop tapZoneSummary: string = '';
  @Prop orientationOptions: SelectOption[] = [];
  @Prop orientationSelected: number = 0;
  @Prop colors: ReaderComicPanelColors = new ReaderComicPanelColors();
  /** 选中三种漫画方式之一，或 READER_COMIC_TEXT_MODE。 */
  onSelectMode: (mode: string) => void = () => {};
  onSetDefaultMode: () => void = () => {};
  onTapTurnChange: (checked: boolean) => void = () => {};
  onConfigureTapZones: () => void = () => {};
  onVolumeTurnChange: (checked: boolean) => void = () => {};
  onOrientationChange: (index: number) => void = () => {};
  onDualPageChange: (checked: boolean) => void = () => {};

  private paged(): boolean {
    return ReaderComicMode.isPaged(this.mode);
  }

  private modeOptions(): ReaderComicOption[] {
    return [
      new ReaderComicOption(ReaderComicMode.WEBTOON, '条漫'),
      new ReaderComicOption(ReaderComicMode.LTR, '从左往右'),
      new ReaderComicOption(ReaderComicMode.RTL, '从右往左'),
      new ReaderComicOption(READER_COMIC_TEXT_MODE, '文字阅读')
    ];
  }

  @Builder
  defaultModeRow() {
    Row() {
      Column() {
        Text('设为默认方式')
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.colors.textColor)
        Text(`没单独设置过的漫画使用默认方式，当前默认：${ReaderComicMode.label(this.defaultMode)}`)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.colors.subTextColor)
          .margin({ top: AppSpacing.XS })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Text(this.defaultMode === this.mode ? '已是默认' : '设为默认')
        .fontSize(AppFontSize.BODY)
        .fontColor(this.defaultMode === this.mode ? this.colors.subTextColor : this.colors.textColor)
        .padding({ left: AppSpacing.LG, right: AppSpacing.LG, top: AppSpacing.SM, bottom: AppSpacing.SM })
        .borderRadius(16)
        .backgroundColor(this.defaultMode === this.mode ? Color.Transparent :
          ThemeRuntime.accentSurfaceColor(this.colors.dark))
        .enabled(this.defaultMode !== this.mode)
        .onClick(() => this.onSetDefaultMode())
    }
    .width('100%')
    .constraintSize({ minHeight: 56 })
    .alignItems(VerticalAlign.Center)
  }

  build() {
    Column({ space: 14 }) {
      ReaderComicOptionGroup({
        title: '本书阅读方式',
        options: this.modeOptions(),
        selected: this.mode,
        colors: this.colors,
        onSelect: (value: string): void => this.onSelectMode(value)
      })

      this.defaultModeRow()

      if (this.paged()) {
        ReaderSettingSwitchRow({
          title: '横屏双页',
          description: '横屏、折叠屏展开等宽屏下两页并排',
          checked: this.dualPage,
          textColor: this.colors.textColor,
          subTextColor: this.colors.subTextColor,
          onChange: (checked: boolean): void => this.onDualPageChange(checked)
        })
      }

      ReaderSettingSwitchRow({
        title: '点击翻页',
        description: this.paged() ? '点击屏幕两侧翻到上一页/下一页，中间呼出菜单' :
          '点击屏幕两侧向上/向下翻一屏，中间呼出菜单',
        checked: this.tapTurn,
        textColor: this.colors.textColor,
        subTextColor: this.colors.subTextColor,
        onChange: (checked: boolean): void => this.onTapTurnChange(checked)
      })

      if (this.tapTurn) {
        ReaderSettingActionRow({
          title: '点击区域动作',
          description: this.tapZoneSummary,
          actionText: '配置',
          textColor: this.colors.textColor,
          subTextColor: this.colors.subTextColor,
          buttonColor: this.colors.buttonColor,
          buttonTextColor: this.colors.buttonTextColor,
          onAction: (): void => this.onConfigureTapZones()
        })
      }

      ReaderSettingSwitchRow({
        title: '音量键翻页',
        description: this.paged() ? '音量上/下键翻到上一页/下一页' : '音量上/下键向上/向下翻一屏',
        checked: this.volumeTurnPage,
        textColor: this.colors.textColor,
        subTextColor: this.colors.subTextColor,
        onChange: (checked: boolean): void => this.onVolumeTurnChange(checked)
      })

      ReaderSettingSelectRow({
        title: '屏幕方向',
        description: '阅读时的屏幕方向',
        options: this.orientationOptions,
        selected: this.orientationSelected,
        controlId: 'reader_comic_screen_orientation_select',
        textColor: this.colors.textColor,
        subTextColor: this.colors.subTextColor,
        accentColor: this.colors.accentColor,
        dark: this.colors.dark,
        menuColor: this.colors.menuColor,
        onSelect: (index: number): void => this.onOrientationChange(index)
      })
    }
    .width('100%')
  }
}

/** 漫画「画面设置」面板。 */
@Component
export struct ReaderComicDisplaySettingsPanel {
  @StorageProp('aiTrialOpen') trialOpen: boolean = false;
  @StorageProp('accountLoggedIn') loggedIn: boolean = false;
  @Prop colorEnabled: boolean = false;
  @Prop colorAccess: string = '';
  onColorEnabled: (enabled: boolean) => void = () => {};
  /** 「背景」设置值（组件属性不能叫 background，会与内置属性冲突）。 */
  @Prop surface: string = ReaderComicBackground.BLACK;
  @Prop pageGap: number = 0;
  @Prop fit: string = ReaderComicFit.WIDTH;
  @Prop preloadCount: number = 5;
  @Prop infoBar: boolean = true;
  @Prop doubleTapZoom: boolean = true;
  /** 「AI超分」开关的保存值。 */
  @Prop superResolution: boolean = false;
  /** ReaderComicSuperResolutionAccess 的取值。 */
  @Prop superResolutionAccess: string = ReaderComicSuperResolutionAccess.UNSUPPORTED;
  /** 本书「繁→简」开关的保存值（会员功能）。 */
  @Prop textConvert: boolean = false;
  /** ReaderComicSuperResolutionAccess 的取值。 */
  @Prop textConvertAccess: string = ReaderComicSuperResolutionAccess.UNSUPPORTED;
  /** 「跟随主题」色块显示的阅读主题底色。 */
  @Prop themeBackground: string = '#FFFFFF';
  @Prop colors: ReaderComicPanelColors = new ReaderComicPanelColors();
  onBackgroundChange: (value: string) => void = () => {};
  onPageGapChange: (value: number) => void = () => {};
  onFitChange: (value: string) => void = () => {};
  onPreloadCountChange: (value: number) => void = () => {};
  onInfoBarChange: (checked: boolean) => void = () => {};
  onDoubleTapZoomChange: (checked: boolean) => void = () => {};
  onSuperResolutionChange: (checked: boolean) => void = () => {};
  onTextConvertChange: (checked: boolean) => void = () => {};
  onOpenMembership: () => void = () => {};

  private aiDescription(description: string, access: string): string {
    if (access === ReaderComicSuperResolutionAccess.MEMBER_REQUIRED) {
      return this.trialOpen && !this.loggedIn ? '登录后免费试用，至 10 月 31 日（北京时间）' :
        '免费试用已结束，开通会员继续使用';
    }
    return this.trialOpen ? `${AiAccessPolicy.TRIAL_LABEL}。${description}` : description;
  }

  @Builder
  superResolutionRow() {
    if (this.superResolutionAccess === ReaderComicSuperResolutionAccess.READY) {
      ReaderSettingSwitchRow({
        title: 'AI超分',
        minimumMembership: this.trialOpen ? '' : 'MONTHLY',
        description: this.aiDescription('借助AI把低清图片放大变清晰，处理好后自动替换；只处理正在看的图，会多耗一些电', this.superResolutionAccess),
        checked: this.superResolution,
        textColor: this.colors.textColor,
        subTextColor: this.colors.subTextColor,
        onChange: (checked: boolean): void => this.onSuperResolutionChange(checked)
      })
    } else if (this.superResolutionAccess === ReaderComicSuperResolutionAccess.MEMBER_REQUIRED) {
      ReaderSettingActionRow({
        title: 'AI超分',
        minimumMembership: this.trialOpen ? '' : 'MONTHLY',
        description: this.aiDescription('', this.superResolutionAccess),
        actionText: this.trialOpen && !this.loggedIn ? '登录后免费试用' : '开通会员',
        textColor: this.colors.textColor,
        subTextColor: this.colors.subTextColor,
        buttonColor: this.colors.buttonColor,
        buttonTextColor: this.colors.buttonTextColor,
        onAction: (): void => this.onOpenMembership()
      })
    } else {
      ReaderSettingActionRow({
        title: 'AI超分',
        minimumMembership: this.trialOpen ? '' : 'MONTHLY',
        description: '当前系统不支持，需要 API 26 及以上且支持图片超分的设备',
        actionText: '',
        textColor: this.colors.textColor,
        subTextColor: this.colors.subTextColor
      })
    }
  }

  @Builder
  colorRow() {
    if (this.colorAccess === ReaderComicSuperResolutionAccess.READY) {
      ReaderSettingSwitchRow({
        title: 'AI着色',
        minimumMembership: this.trialOpen ? '' : 'MONTHLY',
        description: this.aiDescription('借助AI为黑白漫画着色，当前画面优先；单张超长图暂不支持。开启后暂停AI超分', this.colorAccess),
        checked: this.colorEnabled,
        textColor: this.colors.textColor,
        subTextColor: this.colors.subTextColor,
        onChange: (checked: boolean): void => this.onColorEnabled(checked)
      })
    } else {
      ReaderSettingActionRow({
        title: 'AI着色',
        minimumMembership: this.trialOpen ? '' : 'MONTHLY',
        description: this.colorAccess === ReaderComicSuperResolutionAccess.MEMBER_REQUIRED ?
          this.aiDescription('', this.colorAccess) : '当前设备不支持本地着色引擎',
        actionText: this.colorAccess === ReaderComicSuperResolutionAccess.MEMBER_REQUIRED ?
          (this.trialOpen && !this.loggedIn ? '登录后免费试用' : '开通会员') : '',
        textColor: this.colors.textColor,
        subTextColor: this.colors.subTextColor,
        buttonColor: this.colors.buttonColor,
        buttonTextColor: this.colors.buttonTextColor,
        onAction: (): void => this.onOpenMembership()
      })
    }
  }

  @Builder
  textConvertRow() {
    ReaderComicTranslationRow({
      textConvert: this.textConvert,
      access: this.textConvertAccess,
      textColor: this.colors.textColor,
      subTextColor: this.colors.subTextColor,
      accentColor: this.colors.accentColor,
      dark: this.colors.dark,
      onChange: (enabled: boolean): void => this.onTextConvertChange(enabled),
      onOpenMembership: (): void => this.onOpenMembership()
    })
  }

  build() {
    Column({ space: 18 }) {
      ReaderComicOptionGroup({
        title: '背景',
        options: [
          new ReaderComicOption(ReaderComicBackground.BLACK, '黑色', '#000000'),
          new ReaderComicOption(ReaderComicBackground.WHITE, '白色', '#FFFFFF'),
          new ReaderComicOption(ReaderComicBackground.THEME, '跟随主题', this.themeBackground)
        ],
        selected: this.surface,
        colors: this.colors,
        onSelect: (value: string): void => this.onBackgroundChange(value)
      })
      ReaderComicOptionGroup({
        title: '页间距',
        options: [new ReaderComicOption('0', '无'), new ReaderComicOption('6', '小'), new ReaderComicOption('16', '大')],
        selected: `${this.pageGap}`,
        colors: this.colors,
        onSelect: (value: string): void => this.onPageGapChange(Number(value) || 0)
      })
      ReaderComicOptionGroup({
        title: '图片缩放',
        options: [
          new ReaderComicOption(ReaderComicFit.WIDTH, '适应宽度'),
          new ReaderComicOption(ReaderComicFit.SCREEN, '适应屏幕')
        ],
        selected: this.fit,
        colors: this.colors,
        onSelect: (value: string): void => this.onFitChange(value)
      })
      ReaderComicOptionGroup({
        title: '网络图片预加载',
        options: [
          new ReaderComicOption('0', '关闭'),
          new ReaderComicOption('3', '3 张'),
          new ReaderComicOption('5', '5 张'),
          new ReaderComicOption('10', '10 张')
        ],
        selected: `${this.preloadCount}`,
        colors: this.colors,
        onSelect: (value: string): void => this.onPreloadCountChange(Number(value) || 0)
      })

      this.superResolutionRow()

      this.colorRow()

      this.textConvertRow()

      ReaderSettingSwitchRow({
        title: '双击缩放',
        description: '双击放大到 2 倍，再双击还原；关闭后单击响应更快，双指缩放不受影响',
        checked: this.doubleTapZoom,
        textColor: this.colors.textColor,
        subTextColor: this.colors.subTextColor,
        onChange: (checked: boolean): void => this.onDoubleTapZoomChange(checked)
      })

      ReaderSettingSwitchRow({
        title: '信息条',
        description: '在右下角显示话名、页码、时间与电量',
        checked: this.infoBar,
        textColor: this.colors.textColor,
        subTextColor: this.colors.subTextColor,
        onChange: (checked: boolean): void => this.onInfoBarChange(checked)
      })
    }
    .width('100%')
  }
}
