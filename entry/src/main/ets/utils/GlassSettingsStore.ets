import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';
import { ThemeRuntime } from '../theme/ThemeRuntime';

export class GlassPresetIds {
  static readonly OFF: string = 'off';
  static readonly LIGHT: string = 'light';
  static readonly STANDARD: string = 'standard';
  static readonly STRONG: string = 'strong';
  static readonly CUSTOM: string = 'custom';
}

export class GlassSettings {
  preset: string = GlassPresetIds.STANDARD;
  enabled: boolean = true;
  blur: number = 22;
  tintOpacity: number = 82;
  borderOpacity: number = 44;
  borderWidth: number = 1;
  shadowEnabled: boolean = true;
  lightShadowOpacity: number = 17;
  darkShadowOpacity: number = 44;
  shadowRadius: number = 18;
  shadowOffsetX: number = 0;
  shadowOffsetY: number = 6;
  cornerRadius: number = 16;
  lowPerformance: boolean = false;
}

export class GlassSettingsStore {
  static readonly KEY_PRESET: string = 'glassPreset';
  private static readonly STORE_NAME: string = 'glass_settings';
  private static readonly KEY_TINT_OPACITY: string = 'glassTintOpacity';
  private static readonly KEY_BORDER_OPACITY: string = 'glassBorderOpacity';
  private static cached: GlassSettings | null = null;

  static async load(context: Context): Promise<GlassSettings> {
    if (GlassSettingsStore.cached) return GlassSettingsStore.cloneSettings(GlassSettingsStore.cached);
    const store = await preferences.getPreferences(context, GlassSettingsStore.STORE_NAME);
    const settings = new GlassSettings();
    settings.preset = await GlassSettingsStore.getString(store, GlassSettingsStore.KEY_PRESET, settings.preset);
    settings.enabled = await GlassSettingsStore.getBoolean(store, ThemeRuntime.KEY_GLASS_ENABLED, settings.enabled);
    settings.blur = await GlassSettingsStore.getNumber(store, ThemeRuntime.KEY_GLASS_PANEL_BLUR, settings.blur);
    const lightTintOpacity = await GlassSettingsStore.getNumber(store,
      ThemeRuntime.KEY_GLASS_LIGHT_TINT_OPACITY, 85);
    const darkTintOpacity = await GlassSettingsStore.getNumber(store,
      ThemeRuntime.KEY_GLASS_DARK_TINT_OPACITY, 78);
    settings.tintOpacity = await GlassSettingsStore.getNumber(store, GlassSettingsStore.KEY_TINT_OPACITY,
      Math.round((lightTintOpacity + darkTintOpacity) / 2));
    const lightBorderOpacity = await GlassSettingsStore.getNumber(store,
      ThemeRuntime.KEY_GLASS_LIGHT_BORDER_OPACITY, 65);
    const darkBorderOpacity = await GlassSettingsStore.getNumber(store,
      ThemeRuntime.KEY_GLASS_DARK_BORDER_OPACITY, 22);
    settings.borderOpacity = await GlassSettingsStore.getNumber(store, GlassSettingsStore.KEY_BORDER_OPACITY,
      Math.round((lightBorderOpacity + darkBorderOpacity) / 2));
    settings.borderWidth = await GlassSettingsStore.getNumber(store, ThemeRuntime.KEY_GLASS_BORDER_WIDTH,
      settings.borderWidth);
    settings.shadowEnabled = await GlassSettingsStore.getBoolean(store, ThemeRuntime.KEY_GLASS_SHADOW_ENABLED,
      settings.shadowEnabled);
    settings.lightShadowOpacity = await GlassSettingsStore.getNumber(store,
      ThemeRuntime.KEY_GLASS_LIGHT_SHADOW_OPACITY, settings.lightShadowOpacity);
    settings.darkShadowOpacity = await GlassSettingsStore.getNumber(store,
      ThemeRuntime.KEY_GLASS_DARK_SHADOW_OPACITY, settings.darkShadowOpacity);
    settings.shadowRadius = await GlassSettingsStore.getNumber(store, ThemeRuntime.KEY_GLASS_SHADOW_RADIUS,
      settings.shadowRadius);
    settings.shadowOffsetX = await GlassSettingsStore.getNumber(store, ThemeRuntime.KEY_GLASS_SHADOW_OFFSET_X,
      settings.shadowOffsetX);
    settings.shadowOffsetY = await GlassSettingsStore.getNumber(store, ThemeRuntime.KEY_GLASS_SHADOW_OFFSET_Y,
      settings.shadowOffsetY);
    settings.cornerRadius = await GlassSettingsStore.getNumber(store, ThemeRuntime.KEY_GLASS_CORNER_RADIUS,
      settings.cornerRadius);
    settings.lowPerformance = await GlassSettingsStore.getBoolean(store,
      ThemeRuntime.KEY_GLASS_LOW_PERFORMANCE, settings.lowPerformance);
    if (settings.preset === GlassPresetIds.OFF) {
      settings.preset = GlassPresetIds.STANDARD;
      settings.enabled = false;
    } else if (settings.preset !== GlassPresetIds.LIGHT && settings.preset !== GlassPresetIds.STANDARD &&
      settings.preset !== GlassPresetIds.STRONG && settings.preset !== GlassPresetIds.CUSTOM) {
      settings.preset = GlassPresetIds.CUSTOM;
    }
    GlassSettingsStore.cached = GlassSettingsStore.cloneSettings(settings);
    return settings;
  }

  static async save(context: Context, source: GlassSettings): Promise<void> {
    const settings = GlassSettingsStore.normalize(source);
    const store = await preferences.getPreferences(context, GlassSettingsStore.STORE_NAME);
    await store.put(GlassSettingsStore.KEY_PRESET, settings.preset);
    await store.put(ThemeRuntime.KEY_GLASS_ENABLED, settings.enabled);
    await store.put(ThemeRuntime.KEY_GLASS_PANEL_BLUR, settings.blur);
    await store.put(ThemeRuntime.KEY_GLASS_POPOVER_BLUR, settings.blur);
    await store.put(ThemeRuntime.KEY_GLASS_BUTTON_BLUR, settings.blur);
    await store.put(ThemeRuntime.KEY_GLASS_OVERLAY_BLUR, settings.blur);
    await store.put(ThemeRuntime.KEY_GLASS_MENU_BLUR, settings.blur);
    await store.put(GlassSettingsStore.KEY_TINT_OPACITY, settings.tintOpacity);
    await store.put(ThemeRuntime.KEY_GLASS_LIGHT_TINT_OPACITY, settings.tintOpacity);
    await store.put(ThemeRuntime.KEY_GLASS_DARK_TINT_OPACITY, settings.tintOpacity);
    await store.put(GlassSettingsStore.KEY_BORDER_OPACITY, settings.borderOpacity);
    await store.put(ThemeRuntime.KEY_GLASS_LIGHT_BORDER_OPACITY, settings.borderOpacity);
    await store.put(ThemeRuntime.KEY_GLASS_DARK_BORDER_OPACITY, settings.borderOpacity);
    await store.put(ThemeRuntime.KEY_GLASS_BORDER_WIDTH, settings.borderWidth);
    await store.put(ThemeRuntime.KEY_GLASS_SHADOW_ENABLED, settings.shadowEnabled);
    await store.put(ThemeRuntime.KEY_GLASS_LIGHT_SHADOW_OPACITY, settings.lightShadowOpacity);
    await store.put(ThemeRuntime.KEY_GLASS_DARK_SHADOW_OPACITY, settings.darkShadowOpacity);
    await store.put(ThemeRuntime.KEY_GLASS_SHADOW_RADIUS, settings.shadowRadius);
    await store.put(ThemeRuntime.KEY_GLASS_SHADOW_OFFSET_X, settings.shadowOffsetX);
    await store.put(ThemeRuntime.KEY_GLASS_SHADOW_OFFSET_Y, settings.shadowOffsetY);
    await store.put(ThemeRuntime.KEY_GLASS_CORNER_RADIUS, settings.cornerRadius);
    await store.put(ThemeRuntime.KEY_GLASS_LOW_PERFORMANCE, settings.lowPerformance);
    await store.flush();
    GlassSettingsStore.cached = GlassSettingsStore.cloneSettings(settings);
    GlassSettingsStore.applyToStorage(settings);
  }

  static applyToStorage(source: GlassSettings): void {
    const settings = GlassSettingsStore.normalize(source);
    AppStorage.setOrCreate(GlassSettingsStore.KEY_PRESET, settings.preset);
    AppStorage.setOrCreate(ThemeRuntime.KEY_GLASS_ENABLED, settings.enabled);
    AppStorage.setOrCreate(ThemeRuntime.KEY_GLASS_PANEL_BLUR, settings.blur);
    AppStorage.setOrCreate(ThemeRuntime.KEY_GLASS_POPOVER_BLUR, settings.blur);
    AppStorage.setOrCreate(ThemeRuntime.KEY_GLASS_BUTTON_BLUR, settings.blur);
    AppStorage.setOrCreate(ThemeRuntime.KEY_GLASS_OVERLAY_BLUR, settings.blur);
    AppStorage.setOrCreate(ThemeRuntime.KEY_GLASS_MENU_BLUR, settings.blur);
    AppStorage.setOrCreate(ThemeRuntime.KEY_GLASS_LIGHT_TINT_OPACITY, settings.tintOpacity);
    AppStorage.setOrCreate(ThemeRuntime.KEY_GLASS_DARK_TINT_OPACITY, settings.tintOpacity);
    AppStorage.setOrCreate(ThemeRuntime.KEY_GLASS_LIGHT_BORDER_OPACITY, settings.borderOpacity);
    AppStorage.setOrCreate(ThemeRuntime.KEY_GLASS_DARK_BORDER_OPACITY, settings.borderOpacity);
    AppStorage.setOrCreate(ThemeRuntime.KEY_GLASS_BORDER_WIDTH, settings.borderWidth);
    AppStorage.setOrCreate(ThemeRuntime.KEY_GLASS_SHADOW_ENABLED, settings.shadowEnabled);
    AppStorage.setOrCreate(ThemeRuntime.KEY_GLASS_LIGHT_SHADOW_OPACITY, settings.lightShadowOpacity);
    AppStorage.setOrCreate(ThemeRuntime.KEY_GLASS_DARK_SHADOW_OPACITY, settings.darkShadowOpacity);
    AppStorage.setOrCreate(ThemeRuntime.KEY_GLASS_SHADOW_RADIUS, settings.shadowRadius);
    AppStorage.setOrCreate(ThemeRuntime.KEY_GLASS_SHADOW_OFFSET_X, settings.shadowOffsetX);
    AppStorage.setOrCreate(ThemeRuntime.KEY_GLASS_SHADOW_OFFSET_Y, settings.shadowOffsetY);
    AppStorage.setOrCreate(ThemeRuntime.KEY_GLASS_CORNER_RADIUS, settings.cornerRadius);
    AppStorage.setOrCreate(ThemeRuntime.KEY_GLASS_LOW_PERFORMANCE, settings.lowPerformance);
    const revision = AppStorage.get<number>(ThemeRuntime.KEY_THEME_REVISION) ?? 0;
    AppStorage.setOrCreate(ThemeRuntime.KEY_THEME_REVISION, revision + 1);
  }

  static preset(id: string): GlassSettings {
    const settings = new GlassSettings();
    settings.preset = id;
    if (id === GlassPresetIds.OFF) {
      settings.preset = GlassPresetIds.STANDARD;
      settings.enabled = false;
      settings.shadowEnabled = false;
    } else if (id === GlassPresetIds.LIGHT) {
      settings.blur = 12;
      settings.tintOpacity = 89;
      settings.shadowRadius = 8; settings.lightShadowOpacity = 8; settings.darkShadowOpacity = 20;
    } else if (id === GlassPresetIds.STRONG) {
      settings.blur = 32;
      settings.tintOpacity = 71;
      settings.shadowRadius = 24; settings.lightShadowOpacity = 22; settings.darkShadowOpacity = 52;
    }
    return settings;
  }

  static cloneSettings(source: GlassSettings): GlassSettings {
    const target = new GlassSettings();
    target.preset = source.preset; target.enabled = source.enabled;
    target.blur = source.blur; target.tintOpacity = source.tintOpacity;
    target.borderOpacity = source.borderOpacity; target.borderWidth = source.borderWidth;
    target.shadowEnabled = source.shadowEnabled; target.lightShadowOpacity = source.lightShadowOpacity;
    target.darkShadowOpacity = source.darkShadowOpacity; target.shadowRadius = source.shadowRadius;
    target.shadowOffsetX = source.shadowOffsetX; target.shadowOffsetY = source.shadowOffsetY;
    target.cornerRadius = source.cornerRadius; target.lowPerformance = source.lowPerformance;
    return target;
  }

  private static normalize(source: GlassSettings): GlassSettings {
    const settings = GlassSettingsStore.cloneSettings(source);
    settings.blur = GlassSettingsStore.clamp(settings.blur, 0, 40);
    settings.tintOpacity = GlassSettingsStore.clamp(settings.tintOpacity, 0, 100);
    settings.borderOpacity = GlassSettingsStore.clamp(settings.borderOpacity, 0, 100);
    settings.borderWidth = GlassSettingsStore.clamp(settings.borderWidth, 0, 2);
    settings.lightShadowOpacity = GlassSettingsStore.clamp(settings.lightShadowOpacity, 0, 100);
    settings.darkShadowOpacity = GlassSettingsStore.clamp(settings.darkShadowOpacity, 0, 100);
    settings.shadowRadius = GlassSettingsStore.clamp(settings.shadowRadius, 0, 30);
    settings.shadowOffsetX = GlassSettingsStore.clamp(settings.shadowOffsetX, -12, 12);
    settings.shadowOffsetY = GlassSettingsStore.clamp(settings.shadowOffsetY, -12, 12);
    settings.cornerRadius = GlassSettingsStore.clamp(settings.cornerRadius, 0, 32);
    return settings;
  }

  private static clamp(value: number, min: number, max: number): number {
    return Math.max(min, Math.min(max, value));
  }

  private static async getString(store: preferences.Preferences, key: string, fallback: string): Promise<string> {
    return `${await store.get(key, fallback)}`;
  }

  private static async getNumber(store: preferences.Preferences, key: string, fallback: number): Promise<number> {
    const value = await store.get(key, fallback);
    return typeof value === 'number' ? value : fallback;
  }

  private static async getBoolean(store: preferences.Preferences, key: string,
    fallback: boolean): Promise<boolean> {
    const value = await store.get(key, fallback);
    return typeof value === 'boolean' ? value : fallback;
  }
}
