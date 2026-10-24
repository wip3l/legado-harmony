import { router } from '@kit.ArkUI';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { BookSource } from '@legado/sourceengine';
import { SearchExploreSettings } from '../../utils/SearchExploreSettingsStore';
import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { CloudSyncSettingsStore } from '../../account/CloudSyncSettingsStore';
import { AppFontSize } from '../../theme/AppFontSize';
import { AppSpacing } from '../../theme/AppSpacing';
import { CollapsingHeader } from '../../utils/CollapsingHeader';
import { StatusBarScrim } from '../common/StatusBarScrim';
import { CommunityGroup } from '../../utils/CommunityGroup';
import { MembershipIcons } from '../../account/MembershipIcons';
import { AppThemeModeStore } from '../../utils/AppThemeModeStore';
import { ImmersiveMaterialRuntime } from '../../utils/ImmersiveMaterialRuntime';

class ThemeModeOption {
  mode: string = '';
  label: string = '';
  icon: Resource = $r('sys.symbol.circle_lefthalf_inset_filled');
}

/** 首页"我的"页签：设置入口列表。 */
@Component
export struct SettingsPage {
  @StorageProp('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  @Prop statusBarHeight: number = 0;
  @Prop navBarHeight: number = 0;
  @State headerCollapse: number = 0;
  private scroller: Scroller = new Scroller();
  onHeaderCollapseChange: (progress: number) => void = () => {};
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageLink('accountLoggedIn') accountLoggedIn: boolean = false;
  @StorageLink('accountDisplayName') accountDisplayName: string = '';
  @StorageLink('accountAvatarUrl') accountAvatarUrl: string = '';
  @StorageLink('accountPoints') accountPoints: number = 0;
  @StorageLink('accountMembershipSku') membershipSku: string = '';
  @StorageProp('memberIdentityVisible') memberIdentityVisible: boolean = true;
  @StorageLink('cloudSyncEnabled') cloudSyncEnabled: boolean = false;
  @StorageLink('cloudSyncLastSuccessAt') cloudSyncLastSuccessAt: number = 0;
  @StorageLink('cloudSyncPendingCount') cloudSyncPendingCount: number = 0;
  @StorageLink('cloudSyncStatus') cloudSyncStatus: string = CloudSyncSettingsStore.STATUS_DISABLED;
  @StorageLink('appThemeMode') appThemeMode: string = 'system';
  @State showThemeModeMenu: boolean = false;
  private readonly themeModeOptions: ThemeModeOption[] = [
    { mode: 'light', label: '浅色', icon: $r('sys.symbol.sun_max') },
    { mode: 'dark', label: '深色', icon: $r('sys.symbol.moon') },
    { mode: 'system', label: '自动', icon: $r('sys.symbol.circle_lefthalf_inset_filled') }
  ];

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Scroll(this.scroller) {
        Column({ space: AppSpacing.LG }) {
          Row()
            .width('100%')
            .height(56 + this.statusBarHeight)

          this.accountSummaryCard()

          Column() {
            this.syncMenuItem()
            this.menuItem($r('sys.symbol.timer'), '阅读统计', false, () => {
              router.pushUrl({ url: 'pages/ReadingStats' });
            })
          }
          .width('100%')
          .borderRadius(ThemeRuntime.largeRadius())
          .clip(true)
          .backgroundColor(this.glassCardColor())

          Column() {
            this.menuItem($r('sys.symbol.externaldrive'), '书源管理', true, () => {
              router.pushUrl({ url: 'pages/BookSource' });
            })
            this.menuItem($r('sys.symbol.download'), '书籍导入', false, () => {
              router.pushUrl({ url: 'pages/BookImport' });
            })
          }
          .width('100%')
          .borderRadius(ThemeRuntime.largeRadius())
          .clip(true)
          .backgroundColor(this.glassCardColor())

          Column() {
            this.menuItem($r('sys.symbol.book'), '阅读设置', true, () => {
              router.pushUrl({ url: 'pages/Settings' });
            })
            this.menuItem($r('sys.symbol.speaker_wave_3'), '朗读设置', true, () => {
              router.pushUrl({ url: 'pages/TtsSettings' });
            })
            this.menuItem($r('sys.symbol.bookshelf'), '书架设置', true, () => {
              router.pushUrl({ url: 'pages/BookshelfSettings' });
            })
            this.menuItem($r('sys.symbol.magnifyingglass'), '搜索/发现配置', true, () => {
              router.pushUrl({ url: 'pages/SearchExploreSettings' });
            })
            this.menuItem($r('sys.symbol.circle_lefthalf_inset_filled'), '主题', true, () => {
              router.pushUrl({ url: 'pages/ThemeSettings' });
            })
            this.menuItem($r('sys.symbol.gearshape'), '其他设置', false, () => {
              router.pushUrl({ url: 'pages/OtherSettings' });
            })
          }
          .width('100%')
          .borderRadius(ThemeRuntime.largeRadius())
          .clip(true)
          .backgroundColor(this.glassCardColor())

          Column() {
            this.menuItem($r('sys.symbol.questionmark_circle'), '帮助', true, () => {
              router.pushUrl({ url: 'pages/Help' });
            })
            this.menuItem($r('sys.symbol.info_circle'), '关于', true, () => {
              router.pushUrl({ url: 'pages/About' });
            })
            this.menuItem($r('sys.symbol.person_2'), '加入交流群', false, () => {
              CommunityGroup.open(getContext(this) as common.UIAbilityContext);
            })
          }
          .width('100%')
          .borderRadius(ThemeRuntime.largeRadius())
          .clip(true)
          .backgroundColor(this.glassCardColor())

          Row()
            .width('100%')
            .height(56 + Math.max(this.navBarHeight, 8) + 20)
        }
        .width('calc(100% - 32vp)')
        .margin({ left: AppSpacing.XL, right: AppSpacing.XL })
        .justifyContent(FlexAlign.Start)
      }
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .width('100%')
      .height('100%')
      .align(Alignment.TopStart)
      .backgroundColor(this.pageColor())
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      .onDidScroll((_xOffset: number, yOffset: number) => {
        this.headerCollapse = CollapsingHeader.next(this.headerCollapse, yOffset,
          this.scroller.currentOffset().yOffset);
      })
      .onScrollStop(() => {
        const target = CollapsingHeader.settle(this.headerCollapse, this.scroller.currentOffset().yOffset);
        if (target !== this.headerCollapse) {
          animateTo({ duration: 200, curve: Curve.FastOutSlowIn }, () => {
            this.headerCollapse = target;
          });
        }
      })

      StatusBarScrim({ statusBarHeight: this.statusBarHeight, pageColor: this.pageColor(),
        scrimOpacity: CollapsingHeader.scrimOpacity(this.headerCollapse) })
        .width('100%')

      Column() {
        Row() {
          Text('我的')
            .fontSize(AppFontSize.DISPLAY)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.primaryTextColor())
            .layoutWeight(1)
          this.themeModeButton()
        }
        .width('100%')
        .height(56 + this.statusBarHeight)
        .alignItems(VerticalAlign.Center)
        .padding({ left: AppSpacing.XL, right: AppSpacing.LG, top: this.statusBarHeight })
        .opacity(CollapsingHeader.contentOpacity(this.headerCollapse))
        .hitTestBehavior(CollapsingHeader.acceptsTouch(this.headerCollapse) ? HitTestMode.Default : HitTestMode.None)
      }
      .width('100%')
      .height(56 + this.statusBarHeight - this.headerCollapse)
      .clip(true)
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        this.onHeaderCollapseChange((56 + this.statusBarHeight - Number(newArea.height)) /
          CollapsingHeader.DISTANCE);
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  themeModeButton() {
    Row() {
      SymbolGlyph(this.themeModeIcon())
        .fontSize(22)
        .fontColor([this.primaryTextColor()])
    }
    .width(40)
    .height(40)
    .justifyContent(FlexAlign.Center)
    .accessibilityText(`显示模式：${this.themeModeLabel()}，切换显示模式`)
    .bindPopup(this.showThemeModeMenu, ImmersiveMaterialRuntime.popupMenuOptions(this.immersiveLightLevel, (): void => {
      this.themeModeMenuContent()
    }, Placement.BottomRight, this.appDarkMode, this.accentColor(), () => {
      this.showThemeModeMenu = false;
    }))
    .onClick(() => {
      this.showThemeModeMenu = !this.showThemeModeMenu;
    })
  }

  @Builder
  themeModeMenuContent() {
    Column({ space: AppSpacing.XXS }) {
      ForEach(this.themeModeOptions, (option: ThemeModeOption) => {
        Row({ space: AppSpacing.MD }) {
          SymbolGlyph(option.icon)
            .fontSize(18)
            .fontColor([this.isThemeModeSelected(option.mode) ? this.accentColor() : this.primaryTextColor()])
          Text(option.label)
            .fontSize(AppFontSize.BODY_LARGE)
            .fontWeight(this.isThemeModeSelected(option.mode) ? FontWeight.Medium : FontWeight.Regular)
            .fontColor(this.isThemeModeSelected(option.mode) ? this.accentColor() : this.primaryTextColor())
            .layoutWeight(1)
          if (this.isThemeModeSelected(option.mode)) {
            SymbolGlyph($r('sys.symbol.checkmark'))
              .fontSize(14)
              .fontColor([this.accentColor()])
          }
        }
        .width('100%')
        .height(44)
        .padding({ left: 12, right: 12 })
        .borderRadius(ImmersiveMaterialRuntime.POPUP_MENU_RADIUS - ImmersiveMaterialRuntime.POPUP_MENU_PADDING)
        .backgroundColor(this.isThemeModeSelected(option.mode) ? this.selectedMenuItemColor() : '#00000000')
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          this.showThemeModeMenu = false;
          this.applyThemeMode(option.mode);
        })
      }, (option: ThemeModeOption) => option.mode)
    }
    .width(160)
    .padding(ImmersiveMaterialRuntime.POPUP_MENU_PADDING)
  }

  isThemeModeSelected(mode: string): boolean {
    return AppThemeModeStore.normalizeMode(this.appThemeMode) === mode;
  }

  themeModeIcon(): Resource {
    const mode = AppThemeModeStore.normalizeMode(this.appThemeMode);
    if (mode === 'system') {
      return $r('sys.symbol.circle_lefthalf_inset_filled');
    }
    return mode === 'dark' ? $r('sys.symbol.moon') : $r('sys.symbol.sun_max');
  }

  themeModeLabel(): string {
    const mode = AppThemeModeStore.normalizeMode(this.appThemeMode);
    return mode === 'light' ? '浅色' : (mode === 'dark' ? '深色' : '自动');
  }

  applyThemeMode(nextMode: string): void {
    const mode = AppThemeModeStore.normalizeMode(nextMode);
    if (mode === AppThemeModeStore.normalizeMode(this.appThemeMode)) {
      return;
    }
    const context = getContext(this) as common.UIAbilityContext;
    const systemDarkMode = context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    const nextDarkMode = mode === 'dark' || (mode === 'system' && systemDarkMode);
    const colorMode = mode === 'dark' ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK :
      (mode === 'light' ? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT :
        ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    // 先同步模式来源，setColorMode 触发的配置更新才不会读到旧模式又改回去。
    AppThemeModeStore.applyToStorage(mode);
    if (this.appDarkMode !== nextDarkMode) {
      this.appDarkMode = nextDarkMode;
    }
    context.getApplicationContext().setColorMode(colorMode);
    AppThemeModeStore.save(context, mode).catch((e: Error) => {
      console.warn('保存显示模式失败:', e);
    });
  }

  selectedMenuItemColor(): string {
    const color = this.accentColor();
    return /^#[0-9A-Fa-f]{6}$/.test(color) ? `#11${color.substring(1)}` : '#11000000';
  }

  @Builder
  accountSummaryCard() {
    Column() {
      Row({ space: AppSpacing.LG }) {
        if (this.accountLoggedIn && this.accountAvatarUrl) {
          Image(this.accountAvatarUrl)
            .width(56)
            .height(56)
            .borderRadius(28)
            .objectFit(ImageFit.Cover)
        } else {
          Image($r('app.media.ic_default_reader_avatar'))
            .width(56)
            .height(56)
            .borderRadius(28)
            .objectFit(ImageFit.Cover)
        }

        Column({ space: AppSpacing.XS }) {
          Row({ space: AppSpacing.SM }) {
            Text(this.accountLoggedIn ? this.accountDisplayName : '登录华为账号')
              .fontSize(AppFontSize.SUBTITLE)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.nameColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .flexShrink(1)
            if (this.membershipSku && this.memberIdentityVisible) {
              Image(MembershipIcons.forSku(this.membershipSku))
                .width(26)
                .height(26)
                .objectFit(ImageFit.Contain)
                .flexShrink(0)
                .accessibilityText(MembershipIcons.label(this.membershipSku))
            }
          }
          .alignItems(VerticalAlign.Center)

          Text(this.accountSubtitle())
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.subTextColor())
            .maxLines(1)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(18)
          .fontColor([this.subTextColor()])
      }
      .width('100%')

      Divider()
        .strokeWidth(0.5)
        .color(this.dividerColor())
        .margin({ top: AppSpacing.LG, bottom: AppSpacing.LG })

      Row({ space: AppSpacing.MD }) {
        Text(this.membershipSlogan())
          .fontSize(AppFontSize.BODY)
          .fontColor(this.subTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(this.membershipSku ? '会员中心' : '开通会员')
          .fontSize(AppFontSize.BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor(MembershipIcons.cardTextColor(this.appDarkMode))
          .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.MD, bottom: AppSpacing.MD })
          .borderRadius(18)
          .linearGradient({ angle: 135, colors: MembershipIcons.cardGradient(this.membershipSku, this.appDarkMode) })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding(AppSpacing.XL)
    .borderRadius(ThemeRuntime.largeRadius())
    .backgroundColor(this.glassCardColor())
    .onClick(() => {
      router.pushUrl({ url: 'pages/AccountCenter' });
    })
  }

  nameColor(): string {
    return this.accountLoggedIn && this.membershipSku ?
      MembershipIcons.nameColor(this.membershipSku, this.appDarkMode) : this.primaryTextColor();
  }

  accountSubtitle(): string {
    if (!this.accountLoggedIn) return '首次登录免费送 300 点';
    return this.membershipSku ? `${MembershipIcons.label(this.membershipSku)} · ${this.accountPoints} 点` :
      `${this.accountPoints} 点`;
  }

  membershipSlogan(): string {
    if (!this.accountLoggedIn) return '初逢书页，且读一章';
    if (this.membershipSku === 'MONTHLY') return '一月书香，日日相伴';
    if (this.membershipSku === 'ANNUAL') return '四季有书，岁月生香';
    if (this.membershipSku === 'LIFETIME') return '一生有书，心有所栖';
    if (this.membershipSku === 'SUPER_LIFETIME') return '字里山河，耳畔书声';
    return '初逢书页，且读一章';
  }

  @Builder
  syncMenuItem() {
    Column() {
      Row() {
        SymbolGlyph($r('sys.symbol.arrow_clockwise'))
          .fontSize(22)
          .fontColor([this.accentColor()])
          .width(32)

        Column({ space: AppSpacing.XXS }) {
          Text('数据同步')
            .fontSize(AppFontSize.BODY_LARGE)
            .fontColor(this.primaryTextColor())
          Text(CloudSyncSettingsStore.statusSummary(this.accountLoggedIn, this.cloudSyncEnabled,
            this.cloudSyncStatus, this.cloudSyncPendingCount, this.cloudSyncLastSuccessAt))
            .fontSize(AppFontSize.CAPTION)
            .fontColor(this.cloudSyncEnabled && this.accountLoggedIn ? this.accentColor() : this.subTextColor())
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .margin({ left: AppSpacing.LG })

        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(18)
          .fontColor([this.subTextColor()])
      }
      .width('100%')
      .height(64)
      .padding({ left: AppSpacing.XL, right: AppSpacing.XL })
      .alignItems(VerticalAlign.Center)

      Divider()
        .strokeWidth(0.5)
        .color(this.dividerColor())
        .width('calc(100% - 60vp)')
        .margin({ left: 60 })
    }
    .width('100%')
    .onClick(() => {
      router.pushUrl({ url: 'pages/DataSync' });
    })
  }

  @Builder
  menuItem(icon: Resource, title: string, showDivider: boolean, onClick: () => void) {
    Column() {
      Row() {
        SymbolGlyph(icon)
          .fontSize(22)
          .fontColor([this.accentColor()])
          .width(32)

        Text(title)
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.primaryTextColor())
          .layoutWeight(1)
          .margin({ left: AppSpacing.LG })

        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(18)
          .fontColor([this.subTextColor()])
      }
      .width('100%')
      .height(56)
      .padding({ left: AppSpacing.XL, right: AppSpacing.XL })
      .alignItems(VerticalAlign.Center)

      if (showDivider) {
        Divider()
          .strokeWidth(0.5)
          .color(this.dividerColor())
          .margin({ left: 60, right: AppSpacing.XL })
      }
    }
    .width('100%')
    .onClick(onClick)
  }

  pageColor(): string {
    return ThemeRuntime.pageColor(this.appDarkMode);
  }

  primaryTextColor(): string {
    return ThemeRuntime.primaryTextColor(this.appDarkMode);
  }

  subTextColor(): string {
    return ThemeRuntime.subTextColor(this.appDarkMode);
  }

  accentColor(): string {
    return ThemeRuntime.accentColor(this.appDarkMode);
  }

  glassCardColor(): string {
    return ThemeRuntime.cardColor(this.appDarkMode);
  }

  dividerColor(): string {
    return ThemeRuntime.hairlineColor(this.appDarkMode);
  }

}
