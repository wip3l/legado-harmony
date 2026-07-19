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
  static readonly BACKGROUND_STRAWBERRY_LIGHT: string = 'strawberry-light';
  static readonly BACKGROUND_STRAWBERRY_DARK: string = 'strawberry-dark';
  static readonly BACKGROUND_CRIMSON_LIGHT: string = 'crimson-light';
  static readonly BACKGROUND_CRIMSON_DARK: string = 'crimson-dark';
  static readonly BACKGROUND_PLUM_TEA_LIGHT: string = 'plum-tea-light';
  static readonly BACKGROUND_PLUM_TEA_DARK: string = 'plum-tea-dark';
  static readonly BACKGROUND_ROSE_LETTER_LIGHT: string = 'rose-letter-light';
  static readonly BACKGROUND_ROSE_LETTER_DARK: string = 'rose-letter-dark';
  static readonly BACKGROUND_MOON_CRANE_LIGHT: string = 'moon-crane-light';
  static readonly BACKGROUND_MOON_CRANE_DARK: string = 'moon-crane-dark';

  static readonly ICON_PACK_CLASSIC: string = 'classic';
  static readonly ICON_PACK_ROUNDED: string = 'rounded';
  static readonly ICON_PACK_INK: string = 'ink';
  static readonly ICON_PACK_STRAWBERRY: string = 'strawberry';
  static readonly ICON_PACK_CRIMSON: string = 'crimson';
  static readonly ICON_PACK_PLUM: string = 'plum';
  static readonly ICON_PACK_ROSE: string = 'rose';
  static readonly ICON_PACK_CRANE: string = 'crane';

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
      case ThemeAssetRegistry.BACKGROUND_STRAWBERRY_LIGHT:
        return $r('app.media.reader_bg_strawberry_light');
      case ThemeAssetRegistry.BACKGROUND_STRAWBERRY_DARK:
        return $r('app.media.reader_bg_strawberry_dark');
      case ThemeAssetRegistry.BACKGROUND_CRIMSON_LIGHT:
        return $r('app.media.reader_bg_crimson_light');
      case ThemeAssetRegistry.BACKGROUND_CRIMSON_DARK:
        return $r('app.media.reader_bg_crimson_dark');
      case ThemeAssetRegistry.BACKGROUND_PLUM_TEA_LIGHT:
        return $r('app.media.reader_bg_plum_tea_light');
      case ThemeAssetRegistry.BACKGROUND_PLUM_TEA_DARK:
        return $r('app.media.reader_bg_plum_tea_dark');
      case ThemeAssetRegistry.BACKGROUND_ROSE_LETTER_LIGHT:
        return $r('app.media.reader_bg_rose_letter_light');
      case ThemeAssetRegistry.BACKGROUND_ROSE_LETTER_DARK:
        return $r('app.media.reader_bg_rose_letter_dark');
      case ThemeAssetRegistry.BACKGROUND_MOON_CRANE_LIGHT:
        return $r('app.media.reader_bg_moon_crane_light');
      case ThemeAssetRegistry.BACKGROUND_MOON_CRANE_DARK:
        return $r('app.media.reader_bg_moon_crane_dark');
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
    if (normalizedPackId === ThemeAssetRegistry.ICON_PACK_STRAWBERRY ||
      normalizedPackId === ThemeAssetRegistry.ICON_PACK_CRIMSON ||
      normalizedPackId === ThemeAssetRegistry.ICON_PACK_PLUM ||
      normalizedPackId === ThemeAssetRegistry.ICON_PACK_ROSE ||
      normalizedPackId === ThemeAssetRegistry.ICON_PACK_CRANE) {
      return ThemeAssetRegistry.themedNavigationIcon(normalizedPackId, normalizedTabId);
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
      case ThemeIds.STRAWBERRY_CREAM:
        return $r('app.media.theme_logo_strawberry_cream');
      case ThemeIds.CRIMSON_ARCHIVE:
        return $r('app.media.theme_logo_crimson_archive');
      case ThemeIds.PLUM_TEA:
        return $r('app.media.theme_logo_plum_tea');
      case ThemeIds.ROSE_LETTER:
        return $r('app.media.theme_logo_rose_letter');
      case ThemeIds.MOON_CRANE:
        return $r('app.media.theme_logo_moon_crane');
      default:
        return $r('app.media.theme_logo_classic_blue');
    }
  }

  static themeBookCover(assetId: string): ResourceStr {
    return ThemeAssetRegistry.themeBookCovers(assetId)[0];
  }

  static themeBookCovers(assetId: string): ResourceStr[] {
    switch ((assetId || '').trim().toLowerCase()) {
      case ThemeIds.WARM_PAPER: return [$r('app.media.theme_cover_warm_paper')];
      case ThemeIds.FOREST_MIST: return [$r('app.media.theme_cover_forest_mist')];
      case ThemeIds.INK_WASH: return [$r('app.media.theme_cover_ink_wash')];
      case ThemeIds.NEON_NIGHT: return [$r('app.media.theme_cover_neon_night')];
      case ThemeIds.STRAWBERRY_CREAM: return [
        $r('app.media.theme_cover_strawberry_cream_01'), $r('app.media.theme_cover_strawberry_cream_02'),
        $r('app.media.theme_cover_strawberry_cream_03'), $r('app.media.theme_cover_strawberry_cream_04'),
        $r('app.media.theme_cover_strawberry_cream_05'), $r('app.media.theme_cover_strawberry_cream_06')
      ];
      case ThemeIds.CRIMSON_ARCHIVE: return [
        $r('app.media.theme_cover_crimson_archive_01'), $r('app.media.theme_cover_crimson_archive_02'),
        $r('app.media.theme_cover_crimson_archive_03'), $r('app.media.theme_cover_crimson_archive_04'),
        $r('app.media.theme_cover_crimson_archive_05'), $r('app.media.theme_cover_crimson_archive_06')
      ];
      case ThemeIds.PLUM_TEA: return [
        $r('app.media.theme_cover_plum_tea_01'), $r('app.media.theme_cover_plum_tea_02'),
        $r('app.media.theme_cover_plum_tea_03'), $r('app.media.theme_cover_plum_tea_04'),
        $r('app.media.theme_cover_plum_tea_05'), $r('app.media.theme_cover_plum_tea_06')
      ];
      case ThemeIds.ROSE_LETTER: return [
        $r('app.media.theme_cover_rose_letter_01'), $r('app.media.theme_cover_rose_letter_02'),
        $r('app.media.theme_cover_rose_letter_03'), $r('app.media.theme_cover_rose_letter_04'),
        $r('app.media.theme_cover_rose_letter_05'), $r('app.media.theme_cover_rose_letter_06')
      ];
      case ThemeIds.MOON_CRANE: return [
        $r('app.media.theme_cover_moon_crane_01'), $r('app.media.theme_cover_moon_crane_02'),
        $r('app.media.theme_cover_moon_crane_03'), $r('app.media.theme_cover_moon_crane_04'),
        $r('app.media.theme_cover_moon_crane_05'), $r('app.media.theme_cover_moon_crane_06')
      ];
      default: return [$r('app.media.theme_cover_classic_blue')];
    }
  }

  static themeShelfFrame(assetId: string): ResourceStr {
    switch ((assetId || '').trim().toLowerCase()) {
      case ThemeIds.WARM_PAPER: return $r('app.media.theme_frame_warm_paper');
      case ThemeIds.FOREST_MIST: return $r('app.media.theme_frame_forest_mist');
      case ThemeIds.INK_WASH: return $r('app.media.theme_frame_ink_wash');
      case ThemeIds.NEON_NIGHT: return $r('app.media.theme_frame_neon_night');
      case ThemeIds.STRAWBERRY_CREAM: return $r('app.media.theme_frame_strawberry_cream');
      case ThemeIds.CRIMSON_ARCHIVE: return $r('app.media.theme_frame_crimson_archive');
      case ThemeIds.PLUM_TEA: return $r('app.media.theme_frame_plum_tea');
      case ThemeIds.ROSE_LETTER: return $r('app.media.theme_frame_rose_letter');
      case ThemeIds.MOON_CRANE: return $r('app.media.theme_frame_moon_crane');
      default: return $r('app.media.theme_frame_classic_blue');
    }
  }

  static themeShelfFolder(assetId: string): ResourceStr {
    switch ((assetId || '').trim().toLowerCase()) {
      case ThemeIds.WARM_PAPER: return $r('app.media.theme_folder_art_warm_paper');
      case ThemeIds.FOREST_MIST: return $r('app.media.theme_folder_art_forest_mist');
      case ThemeIds.INK_WASH: return $r('app.media.theme_folder_art_ink_wash');
      case ThemeIds.NEON_NIGHT: return $r('app.media.theme_folder_art_neon_night');
      case ThemeIds.STRAWBERRY_CREAM: return $r('app.media.theme_folder_art_strawberry_cream');
      case ThemeIds.CRIMSON_ARCHIVE: return $r('app.media.theme_folder_art_crimson_archive');
      case ThemeIds.PLUM_TEA: return $r('app.media.theme_folder_art_plum_tea');
      case ThemeIds.ROSE_LETTER: return $r('app.media.theme_folder_art_rose_letter');
      case ThemeIds.MOON_CRANE: return $r('app.media.theme_folder_art_moon_crane');
      default: return $r('app.media.theme_folder_art_classic_blue');
    }
  }

  static regexBubbleFrame(styleId: string): ResourceStr {
    switch ((styleId || '').trim().toLowerCase()) {
      case 'classic-glass': return $r('app.media.regex_frame_classic_glass');
      case 'warm-scroll': return $r('app.media.regex_frame_warm_scroll');
      case 'forest-dew': return $r('app.media.regex_frame_forest_dew');
      case 'ink-brush': return $r('app.media.regex_frame_ink_brush');
      case 'neon-pulse': return $r('app.media.regex_frame_neon_pulse');
      case 'strawberry-ribbon': return $r('app.media.regex_frame_strawberry_ribbon');
      case 'crimson-stamp': return $r('app.media.regex_frame_crimson_stamp');
      case 'celadon-slip': return $r('app.media.regex_frame_celadon_slip');
      case 'rose-frame': return $r('app.media.regex_frame_rose_letter');
      case 'moon-halo': return $r('app.media.regex_frame_moon_halo');
      default: return '';
    }
  }

  static hasRegexBubbleFrame(styleId: string): boolean {
    return !!ThemeAssetRegistry.regexBubbleFrame(styleId);
  }

  static regexBubbleCap(styleId: string): ResourceStr {
    switch ((styleId || '').trim().toLowerCase()) {
      case 'classic-glass': return $r('app.media.regex_cap_classic_glass');
      case 'warm-scroll': return $r('app.media.regex_cap_warm_scroll');
      case 'forest-dew': return $r('app.media.regex_cap_forest_dew');
      case 'ink-brush': return $r('app.media.regex_cap_ink_brush');
      case 'neon-pulse': return $r('app.media.regex_cap_neon_pulse');
      case 'strawberry-ribbon': return $r('app.media.regex_cap_strawberry_ribbon');
      case 'crimson-stamp': return $r('app.media.regex_cap_crimson_stamp');
      case 'celadon-slip': return $r('app.media.regex_cap_celadon_slip');
      case 'rose-frame': return $r('app.media.regex_cap_rose_letter');
      case 'moon-halo': return $r('app.media.regex_cap_moon_halo');
      default: return '';
    }
  }

  static hasRegexBubbleCap(styleId: string): boolean {
    return !!ThemeAssetRegistry.regexBubbleCap(styleId);
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
      case ThemeAssetRegistry.BACKGROUND_STRAWBERRY_LIGHT:
      case ThemeAssetRegistry.BACKGROUND_STRAWBERRY_DARK:
      case ThemeAssetRegistry.BACKGROUND_CRIMSON_LIGHT:
      case ThemeAssetRegistry.BACKGROUND_CRIMSON_DARK:
      case ThemeAssetRegistry.BACKGROUND_PLUM_TEA_LIGHT:
      case ThemeAssetRegistry.BACKGROUND_PLUM_TEA_DARK:
      case ThemeAssetRegistry.BACKGROUND_ROSE_LETTER_LIGHT:
      case ThemeAssetRegistry.BACKGROUND_ROSE_LETTER_DARK:
      case ThemeAssetRegistry.BACKGROUND_MOON_CRANE_LIGHT:
      case ThemeAssetRegistry.BACKGROUND_MOON_CRANE_DARK:
        return normalized;
      default:
        return '';
    }
  }

  static normalizeIconPackId(iconPackId: string): string {
    const normalized = (iconPackId || '').trim().toLowerCase();
    if (normalized === ThemeAssetRegistry.ICON_PACK_ROUNDED ||
      normalized === ThemeAssetRegistry.ICON_PACK_INK ||
      normalized === ThemeAssetRegistry.ICON_PACK_STRAWBERRY ||
      normalized === ThemeAssetRegistry.ICON_PACK_CRIMSON ||
      normalized === ThemeAssetRegistry.ICON_PACK_PLUM ||
      normalized === ThemeAssetRegistry.ICON_PACK_ROSE ||
      normalized === ThemeAssetRegistry.ICON_PACK_CRANE) {
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

  private static themedNavigationIcon(iconPackId: string, tabId: string): Resource {
    if (iconPackId === ThemeAssetRegistry.ICON_PACK_STRAWBERRY) {
      switch (tabId) {
        case ThemeAssetRegistry.TAB_EXPLORE: return $r('app.media.ic_theme_strawberry_explore');
        case ThemeAssetRegistry.TAB_SEARCH: return $r('app.media.ic_theme_strawberry_search');
        case ThemeAssetRegistry.TAB_MINE: return $r('app.media.ic_theme_strawberry_mine');
        default: return $r('app.media.ic_theme_strawberry_bookshelf');
      }
    }
    if (iconPackId === ThemeAssetRegistry.ICON_PACK_CRIMSON) {
      switch (tabId) {
        case ThemeAssetRegistry.TAB_EXPLORE: return $r('app.media.ic_theme_crimson_explore');
        case ThemeAssetRegistry.TAB_SEARCH: return $r('app.media.ic_theme_crimson_search');
        case ThemeAssetRegistry.TAB_MINE: return $r('app.media.ic_theme_crimson_mine');
        default: return $r('app.media.ic_theme_crimson_bookshelf');
      }
    }
    if (iconPackId === ThemeAssetRegistry.ICON_PACK_PLUM) {
      switch (tabId) {
        case ThemeAssetRegistry.TAB_EXPLORE: return $r('app.media.ic_theme_plum_explore');
        case ThemeAssetRegistry.TAB_SEARCH: return $r('app.media.ic_theme_plum_search');
        case ThemeAssetRegistry.TAB_MINE: return $r('app.media.ic_theme_plum_mine');
        default: return $r('app.media.ic_theme_plum_bookshelf');
      }
    }
    if (iconPackId === ThemeAssetRegistry.ICON_PACK_ROSE) {
      switch (tabId) {
        case ThemeAssetRegistry.TAB_EXPLORE: return $r('app.media.ic_theme_rose_explore');
        case ThemeAssetRegistry.TAB_SEARCH: return $r('app.media.ic_theme_rose_search');
        case ThemeAssetRegistry.TAB_MINE: return $r('app.media.ic_theme_rose_mine');
        default: return $r('app.media.ic_theme_rose_bookshelf');
      }
    }
    switch (tabId) {
      case ThemeAssetRegistry.TAB_EXPLORE: return $r('app.media.ic_theme_crane_explore');
      case ThemeAssetRegistry.TAB_SEARCH: return $r('app.media.ic_theme_crane_search');
      case ThemeAssetRegistry.TAB_MINE: return $r('app.media.ic_theme_crane_mine');
      default: return $r('app.media.ic_theme_crane_bookshelf');
    }
  }
}
