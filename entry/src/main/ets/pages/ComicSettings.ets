import { router } from '@kit.ArkUI';
import { syncSystemBars } from '../utils/SystemBars';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';
import { PageScaffold } from '../components/common/PageScaffold';
import { SettingNavRow, SettingRow, SettingSwitchRow } from '../components/common/SettingRow';
import {
  ReaderComicBackground,
  ReaderComicFit,
  ReaderComicMode,
  ReaderComicSettings,
  ReaderComicSettingsStore
} from '../core/reader/ReaderComicSettings';
import {
  ReaderComicSuperResolution,
  ReaderComicSuperResolutionAccess
} from '../core/reader/ReaderComicSuperResolution';

/**
 * 阅读设置 → 漫画：漫画的全局设置。与阅读页「阅读方式」「画面设置」面板读写同一份设置；
 * 按书单独设置的阅读方式只在阅读页里改。
 */
@Entry
@Component
struct ComicSettingsPage {
  @StorageProp('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageLink('appLightAccentColor') appLightAccentColor: string = '#007DFF';
  @StorageLink('appDarkAccentColor') appDarkAccentColor: string = '#4E9BFF';
  /** 会员档位变化（开通后返回本页）时刷新AI超分一行。 */
  @StorageProp('accountMembershipSku') membershipSku: string = '';
  @State settings: ReaderComicSettings = new ReaderComicSettings();

  private static readonly MODES: string[] = [ReaderComicMode.WEBTOON, ReaderComicMode.LTR, ReaderComicMode.RTL];
  private static readonly BACKGROUNDS: string[] =
    [ReaderComicBackground.BLACK, ReaderComicBackground.WHITE, ReaderComicBackground.THEME];
  private static readonly FITS: string[] = [ReaderComicFit.WIDTH, ReaderComicFit.SCREEN];

  onPageShow(): void {
    this.syncBars();
    ReaderComicSettingsStore.load(getContext(this)).then((settings: ReaderComicSettings): void => {
      this.settings = settings;
    });
  }

  build() {
    Stack() {
      PageScaffold({ title: '漫画设置', content: () => {
        this.pageContent()
      } })
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  pageContent() {
    this.sectionTitle('阅读方式')
    Column() {
      this.selectItem('默认阅读方式', '没单独设置过的漫画使用这里的方式',
        ComicSettingsPage.MODES.map((mode: string): SelectOption => ({ value: ReaderComicMode.label(mode) })),
        Math.max(0, ComicSettingsPage.MODES.indexOf(this.settings.defaultMode)), (index: number) => {
          this.update((next: ReaderComicSettings): void => {
            next.defaultMode = ComicSettingsPage.MODES[index] || ReaderComicMode.WEBTOON;
          });
        }, 'comic_settings_default_mode_select')
      SettingSwitchRow({
        title: '横屏双页',
        description: '翻页模式下，横屏、折叠屏展开等宽屏两页并排',
        isOn: this.settings.dualPage,
        onChange: (value: boolean) => {
          this.update((next: ReaderComicSettings): void => {
            next.dualPage = value;
          });
        }
      })
      SettingSwitchRow({
        title: '点击翻页',
        description: '点击屏幕两侧翻页（条漫为翻一屏），中间呼出菜单',
        isOn: this.settings.tapTurn,
        showDivider: false,
        onChange: (value: boolean) => {
          this.update((next: ReaderComicSettings): void => {
            next.tapTurn = value;
          });
        }
      })
    }
    .width('calc(100% - 24vp)')
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(this.cardColor())

    this.sectionTitle('画面')
    Column() {
      this.selectItem('背景', '图片四周和页间距的颜色',
        [{ value: '黑色' }, { value: '白色' }, { value: '跟随阅读主题' }],
        Math.max(0, ComicSettingsPage.BACKGROUNDS.indexOf(this.settings.background)), (index: number) => {
          this.update((next: ReaderComicSettings): void => {
            next.background = ComicSettingsPage.BACKGROUNDS[index] || ReaderComicBackground.BLACK;
          });
        }, 'comic_settings_background_select')
      this.selectItem('页间距', '条漫图片之间的间隔',
        [{ value: '无' }, { value: '小' }, { value: '大' }],
        Math.max(0, ReaderComicSettings.PAGE_GAPS.indexOf(this.settings.pageGap)), (index: number) => {
          this.update((next: ReaderComicSettings): void => {
            next.pageGap = ReaderComicSettings.PAGE_GAPS[index] ?? 0;
          });
        }, 'comic_settings_page_gap_select')
      this.selectItem('图片缩放', '条漫按宽度铺满，或整张放进一屏',
        [{ value: '适应宽度' }, { value: '适应屏幕' }],
        Math.max(0, ComicSettingsPage.FITS.indexOf(this.settings.fit)), (index: number) => {
          this.update((next: ReaderComicSettings): void => {
            next.fit = ComicSettingsPage.FITS[index] || ReaderComicFit.WIDTH;
          });
        }, 'comic_settings_fit_select')
      this.selectItem('网络图片预加载', '提前下载后面的图片',
        ReaderComicSettings.PRELOAD_COUNTS.map((count: number): SelectOption =>
          ({ value: count > 0 ? `${count} 张` : '关闭' })),
        Math.max(0, ReaderComicSettings.PRELOAD_COUNTS.indexOf(this.settings.preloadCount)), (index: number) => {
          this.update((next: ReaderComicSettings): void => {
            next.preloadCount = ReaderComicSettings.PRELOAD_COUNTS[index] ?? 5;
          });
        }, 'comic_settings_preload_select')
      SettingSwitchRow({
        title: '双击缩放',
        description: '双击放大到 2 倍，再双击还原；关闭后单击响应更快',
        isOn: this.settings.doubleTapZoom,
        onChange: (value: boolean) => {
          this.update((next: ReaderComicSettings): void => {
            next.doubleTapZoom = value;
          });
        }
      })
      SettingSwitchRow({
        title: '信息条',
        description: '在右下角显示话名、页码、时间与电量',
        isOn: this.settings.infoBar,
        showDivider: false,
        onChange: (value: boolean) => {
          this.update((next: ReaderComicSettings): void => {
            next.infoBar = value;
          });
        }
      })
    }
    .width('calc(100% - 24vp)')
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(this.cardColor())

    this.sectionTitle('AI超分')
    Column() {
      this.superResolutionRow()
    }
    .width('calc(100% - 24vp)')
    .margin({ left: AppSpacing.LG, right: AppSpacing.LG })
    .borderRadius(ThemeRuntime.cardRadius())
    .clip(true)
    .backgroundColor(this.cardColor())

    Text('点击区域动作、屏幕方向、音量键翻页与小说共用，在上一页「操作」中调整；单本漫画的阅读方式在阅读页里设置。')
      .fontSize(AppFontSize.CAPTION)
      .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
      .width('100%')
      .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.MD, bottom: AppSpacing.XXL })
  }

  @Builder
  superResolutionRow() {
    if (this.superResolutionAccess() === ReaderComicSuperResolutionAccess.READY) {
      SettingSwitchRow({
        title: 'AI超分',
        minimumMembership: 'MONTHLY',
        description: '借助AI把低清图片放大变清晰，处理好后自动替换；只处理正在看的图，会多耗一些电',
        isOn: this.settings.superResolution,
        showDivider: false,
        onChange: (value: boolean) => {
          this.update((next: ReaderComicSettings): void => {
            next.superResolution = value;
          });
        }
      })
    } else if (this.superResolutionAccess() === ReaderComicSuperResolutionAccess.MEMBER_REQUIRED) {
      SettingNavRow({
        title: 'AI超分',
        minimumMembership: 'MONTHLY',
        description: this.settings.superResolution ? '会员已到期，续费后自动恢复' :
          '借助AI把低清图片放大变清晰',
        value: '开通会员',
        showDivider: false,
        onTap: () => {
          router.pushUrl({ url: 'pages/AccountCenter' });
        }
      })
    } else {
      SettingSwitchRow({
        title: 'AI超分',
        minimumMembership: 'MONTHLY',
        description: '当前系统不支持，需要 API 26 及以上且支持图片超分的设备',
        isOn: false,
        switchEnabled: false,
        showDivider: false
      })
    }
  }

  superResolutionAccess(): string {
    // 读取会员档位只为让档位变化时界面重算；是否有效以账号快照按服务端时间推算为准。
    const sku = this.membershipSku;
    return sku !== undefined ? ReaderComicSuperResolution.access() : ReaderComicSuperResolutionAccess.MEMBER_REQUIRED;
  }

  update(mutate: (settings: ReaderComicSettings) => void): void {
    const next = this.settings.copy();
    mutate(next);
    this.settings = next;
    ReaderComicSettingsStore.save(getContext(this), next).catch((error: Error) => {
      console.warn('保存漫画设置失败:', error);
    });
  }

  @Builder
  sectionTitle(title: string) {
    Text(title)
      .fontSize(AppFontSize.BODY)
      .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
      .width('100%')
      .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.XXL, bottom: AppSpacing.MD })
  }

  @Builder
  selectItem(title: string, desc: string, options: SelectOption[], selected: number,
    onSelect: (index: number) => void, controlId: string, showDivider: boolean = true) {
    SettingRow({ title: title, description: desc, showDivider: showDivider }) {
      Select(options)
        .id(controlId)
        .selected(selected)
        .value(selected >= 0 && selected < options.length ? options[selected].value : '')
        .font({ size: AppFontSize.BODY })
        .fontColor(ThemeRuntime.subTextColor(this.appDarkMode))
        .backgroundColor(Color.Transparent)
        .arrowPosition(ArrowPosition.END)
        .padding({ left: 0, right: 0 })
        .borderRadius(16)
        .border({ width: 0 })
        .optionBgColor(Color.Transparent)
        .divider(null)
        .optionFontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
        .selectedOptionFontColor(ThemeRuntime.accentColor(this.appDarkMode))
        .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.appDarkMode))
        .menuBackgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode))
        .menuBackgroundBlurStyle(BlurStyle.NONE)
        .attributeModifier(ImmersiveMaterialRuntime.selectMenuModifier(this.immersiveLightLevel))
        .onSelect((index: number) => {
          onSelect(index);
        })
    }
  }

  cardColor(): string {
    return ThemeRuntime.cardColor(this.appDarkMode);
  }

  syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, ThemeRuntime.pageColor(this.appDarkMode));
  }
}
