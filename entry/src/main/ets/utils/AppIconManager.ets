import { bundleManager, Context } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { AppIconSettings, AppIconSettingsStore } from './AppIconSettingsStore';
import { BuiltinThemeRegistry } from '../theme/BuiltinThemeRegistry';
import { ThemeIds } from '../theme/ThemeModels';
import { AccountSessionStore } from '../account/AccountSessionStore';

export class AppIconOption {
  id: string = '';
  title: string = '';
  desc: string = '';
  alternateIconName: string = '';
  preview: Resource = $r('app.media.icon');
}

export class AppIconManager {
  static readonly UNSUPPORTED_MESSAGE: string = '该能力需要鸿蒙7及以上';
  static readonly OPTIONS: AppIconOption[] = [
    AppIconManager.option('default', '默认主题', '应用默认桌面图标', '', $r('app.media.icon')),
    AppIconManager.option('warm_book', '纸书暖光', '温润纸页与书签', 'warm_book', $r('app.media.ic_app_warm_book')),
    AppIconManager.option('night_neon', '夜读霓虹', '深色发光书页', 'night_neon', $r('app.media.ic_app_night_neon')),
    AppIconManager.option('minimal_line', '极简线性', '清爽几何线条', 'minimal_line', $r('app.media.ic_app_minimal_line')),
    AppIconManager.option('ink_wash', '水墨书山', '东方水墨意象', 'ink_wash', $r('app.media.ic_app_ink_wash')),
    AppIconManager.option('pixel_retro', '像素复古', '轻快像素书本', 'pixel_retro', $r('app.media.ic_app_pixel_retro')),
    AppIconManager.themeOption(ThemeIds.CLASSIC_BLUE, 'theme_classic_blue', $r('app.media.ic_app_theme_classic_blue')),
    AppIconManager.themeOption(ThemeIds.WARM_PAPER, 'theme_warm_paper', $r('app.media.ic_app_theme_warm_paper')),
    AppIconManager.themeOption(ThemeIds.FOREST_MIST, 'theme_forest_mist', $r('app.media.ic_app_theme_forest_mist')),
    AppIconManager.themeOption(ThemeIds.INK_WASH, 'theme_ink_wash', $r('app.media.ic_app_theme_ink_wash')),
    AppIconManager.themeOption(ThemeIds.NEON_NIGHT, 'theme_neon_night', $r('app.media.ic_app_theme_neon_night')),
    AppIconManager.themeOption(ThemeIds.STRAWBERRY_CREAM, 'theme_strawberry_cream', $r('app.media.ic_app_theme_strawberry_cream')),
    AppIconManager.themeOption(ThemeIds.CRIMSON_ARCHIVE, 'theme_crimson_archive', $r('app.media.ic_app_theme_crimson_archive')),
    AppIconManager.themeOption(ThemeIds.PLUM_TEA, 'theme_plum_tea', $r('app.media.ic_app_theme_plum_tea')),
    AppIconManager.themeOption(ThemeIds.ROSE_LETTER, 'theme_rose_letter', $r('app.media.ic_app_theme_rose_letter')),
    AppIconManager.themeOption(ThemeIds.MOON_CRANE, 'theme_moon_crane', $r('app.media.ic_app_theme_moon_crane')),
    AppIconManager.themeOption(ThemeIds.SWORD_FROST, 'theme_sword_frost', $r('app.media.ic_app_theme_sword_frost')),
    AppIconManager.themeOption(ThemeIds.QINGLUAN_WATER, 'theme_qingluan_water', $r('app.media.ic_app_theme_qingluan_water')),
    AppIconManager.themeOption(ThemeIds.CAT_PIPI, 'theme_cat_pipi', $r('app.media.ic_app_theme_cat_pipi')),
    AppIconManager.themeOption(ThemeIds.AZURE_MECHA, 'theme_azure_mecha', $r('app.media.ic_app_theme_azure_mecha')),
    AppIconManager.themeOption(ThemeIds.STARWISH_MAGIC, 'theme_starwish_magic', $r('app.media.ic_app_theme_starwish_magic')),
    AppIconManager.themeOption(ThemeIds.LETTERPRESS_PAGE, 'theme_letterpress_page', $r('app.media.ic_app_theme_letterpress_page')),
    AppIconManager.themeOption(ThemeIds.OBSIDIAN_ARCHIVE, 'theme_obsidian_archive', $r('app.media.ic_app_theme_obsidian_archive')),
    AppIconManager.themeOption(ThemeIds.NEON_HARBOR, 'theme_neon_harbor', $r('app.media.ic_app_theme_neon_harbor')),
    AppIconManager.themeOption(ThemeIds.CUSTOM, 'theme_custom', $r('app.media.ic_app_theme_custom'))
  ];
  private static changeRevision: number = 0;
  private static applying: boolean = false;

  static isSupported(): boolean {
    return deviceInfo.sdkApiVersion >= 26;
  }

  /** Reconcile with the system, including resets after an update or restored backup. */
  static async syncCurrentIcon(context: Context): Promise<string[]> {
    if (!AppIconManager.isSupported()) return [];
    const revision = AppIconManager.changeRevision;
    const icons = await bundleManager.getAlternateIcons();
    const ids: string[] = [];
    let selectedId = AppIconSettingsStore.DEFAULT_ICON_ID;
    for (const icon of icons) {
      ids.push(icon.iconName);
      if (icon.enabled) selectedId = AppIconManager.optionById(icon.iconName).id;
    }
    if (!AppIconManager.applying && revision === AppIconManager.changeRevision) {
      await AppIconManager.rememberIcon(context, selectedId);
    }
    return ids;
  }

  static async applyIcon(context: Context, option: AppIconOption): Promise<void> {
    if (option.id === 'theme_obsidian_archive' && !AccountSessionStore.hasOwnedEntitlement(ThemeIds.OBSIDIAN_ARCHIVE)) {
      throw new Error('请先领取终身超级会员专属主题');
    }
    if (!AppIconManager.isSupported()) throw new Error(AppIconManager.UNSUPPORTED_MESSAGE);
    if (AppIconManager.applying) throw new Error('桌面图标正在切换，请稍后重试');
    AppIconManager.applying = true;
    AppIconManager.changeRevision++;
    try {
      // An already-default icon reports 17700309 when reset; treat it as a no-op.
      if (!option.alternateIconName) {
        const icons = await bundleManager.getAlternateIcons();
        if (icons.some((icon: bundleManager.AlternateIconInfo) => icon.enabled)) {
          await bundleManager.setAlternateIcon('');
        }
      } else {
        await bundleManager.setAlternateIcon(option.alternateIconName);
      }
      await AppIconManager.rememberIcon(context, option.id);
    } finally {
      AppIconManager.changeRevision++;
      AppIconManager.applying = false;
    }
  }

  static optionById(iconId: string): AppIconOption {
    const normalized = AppIconSettingsStore.normalizeIconId(iconId);
    const matched = AppIconManager.OPTIONS.find((option: AppIconOption) => option.id === normalized);
    return matched || AppIconManager.OPTIONS[0];
  }

  static optionForTheme(themeId: string): AppIconOption {
    return themeId === ThemeIds.PLAIN_DEFAULT ? AppIconManager.OPTIONS[0] :
      AppIconManager.optionById(`theme_${themeId.replace(/-/g, '_')}`);
  }

  private static async rememberIcon(context: Context, iconId: string): Promise<void> {
    const settings = new AppIconSettings();
    settings.iconId = iconId;
    // Publish only after system success; persistence failure cannot undo the actual icon.
    AppIconSettingsStore.applyToStorage(settings);
    try {
      await AppIconSettingsStore.save(context, settings);
    } catch (error) {
      console.warn('保存桌面图标设置失败，下次进入时将从系统恢复:', error);
    }
  }

  private static themeOption(themeId: string, id: string, preview: Resource): AppIconOption {
    const name = BuiltinThemeRegistry.findById(themeId).name;
    return AppIconManager.option(id, name, `${name}主题桌面图标`, id, preview);
  }

  private static option(id: string, title: string, desc: string,
    alternateIconName: string, preview: Resource): AppIconOption {
    const option = new AppIconOption();
    option.id = id;
    option.title = title;
    option.desc = desc;
    option.alternateIconName = alternateIconName;
    option.preview = preview;
    return option;
  }
}
