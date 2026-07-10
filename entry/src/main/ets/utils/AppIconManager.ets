import { appInfoManager } from '@kit.AppGalleryKit';
import { AppIconSettingsStore } from './AppIconSettingsStore';

export class AppIconOption {
  id: string = '';
  title: string = '';
  desc: string = '';
  dynamicIconId: string = '';
  preview: Resource = $r('app.media.icon');
}

export class AppIconManager {
  static readonly OPTIONS: AppIconOption[] = [
    AppIconManager.option(
      AppIconSettingsStore.DEFAULT_ICON_ID,
      '默认图标',
      '当前桌面图标',
      '',
      $r('app.media.icon')
    ),
    AppIconManager.option(
      'warm_book',
      '纸书暖光',
      '温润纸页与书签',
      'warm_book',
      $r('app.media.ic_app_warm_book')
    ),
    AppIconManager.option(
      'night_neon',
      '夜读霓虹',
      '深色发光书页',
      'night_neon',
      $r('app.media.ic_app_night_neon')
    ),
    AppIconManager.option(
      'minimal_line',
      '极简线性',
      '清爽几何线条',
      'minimal_line',
      $r('app.media.ic_app_minimal_line')
    ),
    AppIconManager.option(
      'ink_wash',
      '水墨书山',
      '东方水墨意象',
      'ink_wash',
      $r('app.media.ic_app_ink_wash')
    ),
    AppIconManager.option(
      'pixel_retro',
      '像素复古',
      '轻快像素书本',
      'pixel_retro',
      $r('app.media.ic_app_pixel_retro')
    ),
    AppIconManager.option(
      'theme_classic_blue',
      '经典蓝·书页',
      '经典蓝主题专属图标',
      'theme_classic_blue',
      $r('app.media.ic_app_theme_classic_blue')
    ),
    AppIconManager.option(
      'theme_warm_paper',
      '暖纸·书笺',
      '暖纸主题专属图标',
      'theme_warm_paper',
      $r('app.media.ic_app_theme_warm_paper')
    ),
    AppIconManager.option(
      'theme_forest_mist',
      '林雾·叶语',
      '林雾主题专属图标',
      'theme_forest_mist',
      $r('app.media.ic_app_theme_forest_mist')
    ),
    AppIconManager.option(
      'theme_ink_wash',
      '水墨·书山',
      '水墨主题专属图标',
      'theme_ink_wash',
      $r('app.media.ic_app_theme_ink_wash')
    ),
    AppIconManager.option(
      'theme_neon_night',
      '霓虹·夜读',
      '霓虹主题专属图标',
      'theme_neon_night',
      $r('app.media.ic_app_theme_neon_night')
    )
  ];

  static async queryConfiguredIconIds(): Promise<string[]> {
    const icons = await appInfoManager.queryDynamicIcons();
    const ids: string[] = [];
    icons.forEach((icon: appInfoManager.DynamicIconInfo) => {
      if (icon.iconId) {
        ids.push(icon.iconId);
      }
    });
    return ids;
  }

  static async applyIcon(option: AppIconOption): Promise<void> {
    if (!option.dynamicIconId) {
      await appInfoManager.disableDynamicIcon();
      return;
    }
    await appInfoManager.selectDynamicIcon(option.dynamicIconId);
  }

  static optionById(iconId: string): AppIconOption {
    const normalized = AppIconSettingsStore.normalizeIconId(iconId);
    const matched = AppIconManager.OPTIONS.find((option: AppIconOption) => option.id === normalized);
    return matched || AppIconManager.OPTIONS[0];
  }

  private static option(
    id: string,
    title: string,
    desc: string,
    dynamicIconId: string,
    preview: Resource
  ): AppIconOption {
    const option = new AppIconOption();
    option.id = id;
    option.title = title;
    option.desc = desc;
    option.dynamicIconId = dynamicIconId;
    option.preview = preview;
    return option;
  }
}
