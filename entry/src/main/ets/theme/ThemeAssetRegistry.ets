import { ThemeIds } from './ThemeModels';

export class ThemeAssetRegistry {
  static readonly BACKGROUND_PAPER_LIGHT: string = 'paper-light';
  static readonly BACKGROUND_PAPER_DARK: string = 'paper-dark';
  static readonly BACKGROUND_FOREST_LIGHT: string = 'forest-light';
  static readonly BACKGROUND_FOREST_DARK: string = 'forest-dark';
  static readonly BACKGROUND_INK_LIGHT: string = 'ink-light';
  static readonly BACKGROUND_INK_DARK: string = 'ink-dark';
  static readonly BACKGROUND_NEON_LIGHT: string = 'neon-light';
  static readonly BACKGROUND_NEON_DARK: string = 'neon-dark';

  static readonly ICON_PACK_CLASSIC: string = 'classic';
  static readonly ICON_PACK_ROUNDED: string = 'rounded';
  static readonly ICON_PACK_INK: string = 'ink';

  static readonly TAB_BOOKSHELF: string = 'bookshelf';
  static readonly TAB_EXPLORE: string = 'explore';
  static readonly TAB_SEARCH: string = 'search';
  static readonly TAB_MINE: string = 'mine';

  static readerBackground(assetId: string): ResourceStr {
    switch (ThemeAssetRegistry.normalizeBackgroundAssetId(assetId)) {
      case ThemeAssetRegistry.BACKGROUND_PAPER_LIGHT:
        return $r('app.media.reader_bg_paper_light');
      case ThemeAssetRegistry.BACKGROUND_PAPER_DARK:
        return $r('app.media.reader_bg_paper_dark');
      case ThemeAssetRegistry.BACKGROUND_FOREST_LIGHT:
        return $r('app.media.reader_bg_forest_light');
      case ThemeAssetRegistry.BACKGROUND_FOREST_DARK:
        return $r('app.media.reader_bg_forest_dark');
      case ThemeAssetRegistry.BACKGROUND_INK_LIGHT:
        return $r('app.media.reader_bg_ink_light');
      case ThemeAssetRegistry.BACKGROUND_INK_DARK:
        return $r('app.media.reader_bg_ink_dark');
      case ThemeAssetRegistry.BACKGROUND_NEON_LIGHT:
        return $r('app.media.reader_bg_neon_light');
      case ThemeAssetRegistry.BACKGROUND_NEON_DARK:
        return $r('app.media.reader_bg_neon_dark');
      default:
        return '';
    }
  }

  static navigationIcon(iconPackId: string, tabId: string): Resource {
    const normalizedPackId = ThemeAssetRegistry.normalizeIconPackId(iconPackId);
    const normalizedTabId = ThemeAssetRegistry.normalizeTabId(tabId);
    if (normalizedPackId === ThemeAssetRegistry.ICON_PACK_ROUNDED) {
      return ThemeAssetRegistry.roundedNavigationIcon(normalizedTabId);
    }
    if (normalizedPackId === ThemeAssetRegistry.ICON_PACK_INK) {
      return ThemeAssetRegistry.inkNavigationIcon(normalizedTabId);
    }
    return ThemeAssetRegistry.classicNavigationIcon(normalizedTabId);
  }

  static themeLogo(themeId: string): Resource {
    switch ((themeId || '').trim().toLowerCase()) {
      case ThemeIds.CUSTOM:
        return $r('app.media.theme_logo_custom');
      case ThemeIds.WARM_PAPER:
        return $r('app.media.theme_logo_warm_paper');
      case ThemeIds.FOREST_MIST:
        return $r('app.media.theme_logo_forest_mist');
      case ThemeIds.INK_WASH:
        return $r('app.media.theme_logo_ink_wash');
      case ThemeIds.NEON_NIGHT:
        return $r('app.media.theme_logo_neon_night');
      default:
        return $r('app.media.theme_logo_classic_blue');
    }
  }

  static normalizeBackgroundAssetId(assetId: string): string {
    const normalized = (assetId || '').trim().toLowerCase();
    switch (normalized) {
      case ThemeAssetRegistry.BACKGROUND_PAPER_LIGHT:
      case ThemeAssetRegistry.BACKGROUND_PAPER_DARK:
      case ThemeAssetRegistry.BACKGROUND_FOREST_LIGHT:
      case ThemeAssetRegistry.BACKGROUND_FOREST_DARK:
      case ThemeAssetRegistry.BACKGROUND_INK_LIGHT:
      case ThemeAssetRegistry.BACKGROUND_INK_DARK:
      case ThemeAssetRegistry.BACKGROUND_NEON_LIGHT:
      case ThemeAssetRegistry.BACKGROUND_NEON_DARK:
        return normalized;
      default:
        return '';
    }
  }

  static normalizeIconPackId(iconPackId: string): string {
    const normalized = (iconPackId || '').trim().toLowerCase();
    if (normalized === ThemeAssetRegistry.ICON_PACK_ROUNDED ||
      normalized === ThemeAssetRegistry.ICON_PACK_INK) {
      return normalized;
    }
    return ThemeAssetRegistry.ICON_PACK_CLASSIC;
  }

  static normalizeTabId(tabId: string): string {
    const normalized = (tabId || '').trim().toLowerCase();
    if (normalized === ThemeAssetRegistry.TAB_EXPLORE ||
      normalized === ThemeAssetRegistry.TAB_SEARCH ||
      normalized === ThemeAssetRegistry.TAB_MINE) {
      return normalized;
    }
    return ThemeAssetRegistry.TAB_BOOKSHELF;
  }

  private static classicNavigationIcon(tabId: string): Resource {
    switch (tabId) {
      case ThemeAssetRegistry.TAB_EXPLORE:
        return $r('app.media.ic_tab_explore');
      case ThemeAssetRegistry.TAB_SEARCH:
        return $r('app.media.ic_tab_search');
      case ThemeAssetRegistry.TAB_MINE:
        return $r('app.media.ic_tab_mine');
      default:
        return $r('app.media.ic_tab_bookshelf');
    }
  }

  private static roundedNavigationIcon(tabId: string): Resource {
    switch (tabId) {
      case ThemeAssetRegistry.TAB_EXPLORE:
        return $r('app.media.ic_theme_rounded_explore');
      case ThemeAssetRegistry.TAB_SEARCH:
        return $r('app.media.ic_theme_rounded_search');
      case ThemeAssetRegistry.TAB_MINE:
        return $r('app.media.ic_theme_rounded_mine');
      default:
        return $r('app.media.ic_theme_rounded_bookshelf');
    }
  }

  private static inkNavigationIcon(tabId: string): Resource {
    switch (tabId) {
      case ThemeAssetRegistry.TAB_EXPLORE:
        return $r('app.media.ic_theme_ink_explore');
      case ThemeAssetRegistry.TAB_SEARCH:
        return $r('app.media.ic_theme_ink_search');
      case ThemeAssetRegistry.TAB_MINE:
        return $r('app.media.ic_theme_ink_mine');
      default:
        return $r('app.media.ic_theme_ink_bookshelf');
    }
  }
}
