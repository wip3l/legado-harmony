import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';
import { ThemeIds } from '../theme/ThemeModels';
import { AppThemeSettings, AppThemeSettingsStore } from './AppThemeSettingsStore';
import { CloudSyncChangeTracker } from '../account/CloudSyncChangeTracker';
import { CustomThemeQuota } from '../account/CustomThemeQuota';
import { ReaderSettingsStore } from './ReaderSettingsStore';

export class CustomThemeScheme {
  id: string = '';
  name: string = '';
  revision: number = 1;
  settings: AppThemeSettings = new AppThemeSettings();
  // 从主题包导入且作者选择署名时才有值，只用于展示，不代表认证身份。
  author: string = '';
}

export class CustomThemeSchemeStore {
  static readonly STORAGE_ACTIVE_SCHEME_ID: string = 'activeCustomThemeSchemeId';
  static readonly STORAGE_ACTIVE_SCHEME_REVISION: string = 'activeCustomThemeSchemeRevision';
  static readonly STORAGE_REVISION: string = 'customThemeSchemesRevision';
  private static readonly STORE_NAME: string = 'custom_theme_schemes';
  private static readonly KEY_SCHEMES: string = 'schemes';
  private static readonly KEY_ACTIVE_SCHEME_ID: string = 'active_scheme_id';
  private static readonly KEY_ACTIVE_SCHEME_REVISION: string = 'active_scheme_revision';

  static async load(context: Context, legacySettings: AppThemeSettings): Promise<CustomThemeScheme[]> {
    const store = await preferences.getPreferences(context, CustomThemeSchemeStore.STORE_NAME);
    const raw = await store.get(CustomThemeSchemeStore.KEY_SCHEMES, '');
    const schemes = CustomThemeSchemeStore.decode(typeof raw === 'string' ? raw : '');
    if (schemes.length === 0) {
      const migrated = CustomThemeSchemeStore.createScheme(
        'custom_1',
        '自定义主题 1',
        legacySettings,
        1
      );
      schemes.push(migrated);
      await store.put(CustomThemeSchemeStore.KEY_SCHEMES, CustomThemeSchemeStore.encode(schemes));
      await store.flush();
    }
    let activeIdValue = await store.get(CustomThemeSchemeStore.KEY_ACTIVE_SCHEME_ID, '');
    let activeId = typeof activeIdValue === 'string' ? activeIdValue : '';
    if (!CustomThemeSchemeStore.find(schemes, activeId)) {
      activeId = schemes[0].id;
      await store.put(CustomThemeSchemeStore.KEY_ACTIVE_SCHEME_ID, activeId);
    }
    const activeScheme = CustomThemeSchemeStore.find(schemes, activeId);
    const activeRevisionValue = await store.get(CustomThemeSchemeStore.KEY_ACTIVE_SCHEME_REVISION, 0);
    let activeRevision = typeof activeRevisionValue === 'number' ? activeRevisionValue : 0;
    if (activeRevision <= 0 && legacySettings.themeId === ThemeIds.CUSTOM && activeScheme) {
      activeRevision = activeScheme.revision;
      await store.put(CustomThemeSchemeStore.KEY_ACTIVE_SCHEME_REVISION, activeRevision);
    }
    await store.flush();
    AppStorage.setOrCreate(CustomThemeSchemeStore.STORAGE_ACTIVE_SCHEME_ID, activeId);
    AppStorage.setOrCreate(CustomThemeSchemeStore.STORAGE_ACTIVE_SCHEME_REVISION, activeRevision);
    AppStorage.setOrCreate(
      CustomThemeSchemeStore.STORAGE_REVISION,
      AppStorage.get<number>(CustomThemeSchemeStore.STORAGE_REVISION) || 0
    );
    return CustomThemeSchemeStore.cloneSchemes(schemes);
  }

  static async saveScheme(
    context: Context,
    legacySettings: AppThemeSettings,
    scheme: CustomThemeScheme
  ): Promise<void> {
    const schemes = await CustomThemeSchemeStore.load(context, legacySettings);
    let replaced = false;
    for (let index = 0; index < schemes.length; index++) {
      if (schemes[index].id === scheme.id) {
        schemes[index] = CustomThemeSchemeStore.createScheme(
          scheme.id,
          scheme.name || schemes[index].name,
          scheme.settings,
          schemes[index].revision + 1,
          schemes[index].author
        );
        replaced = true;
        break;
      }
    }
    if (!replaced) {
      throw new Error('自定义主题方案不存在');
    }
    await CustomThemeSchemeStore.persistSchemes(context, schemes);
  }

  static async add(
    context: Context,
    legacySettings: AppThemeSettings
  ): Promise<CustomThemeScheme | null> {
    const schemes = await CustomThemeSchemeStore.load(context, legacySettings);
    const limit = CustomThemeQuota.current();
    if (schemes.length >= limit) {
      return null;
    }
    let sequence = 1;
    while (sequence <= limit) {
      let used = false;
      for (const scheme of schemes) {
        if (scheme.name === `自定义主题 ${sequence}`) {
          used = true;
          break;
        }
      }
      if (!used) break;
      sequence++;
    }
    const initial = AppThemeSettingsStore.createForTheme(ThemeIds.CUSTOM);
    const scheme = CustomThemeSchemeStore.createScheme(
      `custom_${Date.now()}_${sequence}`,
      `自定义主题 ${sequence}`,
      initial,
      1
    );
    schemes.push(scheme);
    await CustomThemeSchemeStore.persistSchemes(context, schemes);
    return CustomThemeSchemeStore.cloneScheme(scheme);
  }

  static async rename(
    context: Context,
    legacySettings: AppThemeSettings,
    schemeId: string,
    name: string
  ): Promise<boolean> {
    const normalizedName = (name || '').trim();
    if (!normalizedName) {
      return false;
    }
    const schemes = await CustomThemeSchemeStore.load(context, legacySettings);
    for (const scheme of schemes) {
      if (scheme.id !== schemeId && scheme.name === normalizedName) {
        return false;
      }
    }
    let renamed = false;
    for (let index = 0; index < schemes.length; index++) {
      if (schemes[index].id === schemeId) {
        schemes[index] = CustomThemeSchemeStore.createScheme(
          schemes[index].id,
          normalizedName,
          schemes[index].settings,
          schemes[index].revision,
          schemes[index].author
        );
        renamed = true;
        break;
      }
    }
    if (!renamed) {
      return false;
    }
    await CustomThemeSchemeStore.persistSchemes(context, schemes);
    return true;
  }

  static async delete(
    context: Context,
    legacySettings: AppThemeSettings,
    schemeId: string
  ): Promise<boolean> {
    const schemes = await CustomThemeSchemeStore.load(context, legacySettings);
    if (schemes.length <= 1 || !CustomThemeSchemeStore.find(schemes, schemeId)) {
      return false;
    }
    const remaining: CustomThemeScheme[] = [];
    for (const scheme of schemes) {
      if (scheme.id !== schemeId) {
        remaining.push(scheme);
      }
    }
    const store = await preferences.getPreferences(context, CustomThemeSchemeStore.STORE_NAME);
    const activeValue = await store.get(CustomThemeSchemeStore.KEY_ACTIVE_SCHEME_ID, '');
    const activeId = typeof activeValue === 'string' ? activeValue : '';
    if (activeId === schemeId) {
      const nextActive = remaining[0];
      await store.put(CustomThemeSchemeStore.KEY_ACTIVE_SCHEME_ID, nextActive.id);
      await store.put(CustomThemeSchemeStore.KEY_ACTIVE_SCHEME_REVISION, 0);
      AppStorage.setOrCreate(CustomThemeSchemeStore.STORAGE_ACTIVE_SCHEME_ID, nextActive.id);
      AppStorage.setOrCreate(CustomThemeSchemeStore.STORAGE_ACTIVE_SCHEME_REVISION, 0);
    }
    await store.put(CustomThemeSchemeStore.KEY_SCHEMES, CustomThemeSchemeStore.encode(remaining));
    await store.flush();
    const revision = (AppStorage.get<number>(CustomThemeSchemeStore.STORAGE_REVISION) || 0) + 1;
    AppStorage.setOrCreate(CustomThemeSchemeStore.STORAGE_REVISION, revision);
    CloudSyncChangeTracker.markPreferenceChanged();
    await ReaderSettingsStore.deleteProfile(context, ReaderSettingsStore.profileIdFor(ThemeIds.CUSTOM, schemeId));
    return true;
  }

  /**
   * 导入主题包得到的方案。新增占用当前权益额度；replaceSchemeId 非空时原位替换那一套（保留其 ID，
   * 正在使用的状态和阅读档案跟着换）。名称与其他方案重复时加序号。
   */
  static async addImported(
    context: Context,
    legacySettings: AppThemeSettings,
    name: string,
    settings: AppThemeSettings,
    author: string,
    replaceSchemeId: string
  ): Promise<CustomThemeScheme | null> {
    const schemes = await CustomThemeSchemeStore.load(context, legacySettings);
    const replaceIndex = replaceSchemeId ?
      schemes.findIndex((item: CustomThemeScheme): boolean => item.id === replaceSchemeId) : -1;
    if (replaceSchemeId && replaceIndex < 0) return null;
    if (replaceIndex < 0 && schemes.length >= CustomThemeQuota.current()) return null;
    const others = schemes.filter((item: CustomThemeScheme): boolean => item.id !== replaceSchemeId);
    const baseName = (name || '').trim() || '导入的主题';
    let uniqueName = baseName;
    for (let sequence = 2; others.some((item: CustomThemeScheme): boolean => item.name === uniqueName); sequence++) {
      uniqueName = `${baseName} (${sequence})`;
    }
    const scheme = CustomThemeSchemeStore.createScheme(
      replaceIndex >= 0 ? schemes[replaceIndex].id : `custom_${Date.now()}_import`,
      uniqueName,
      settings,
      replaceIndex >= 0 ? schemes[replaceIndex].revision + 1 : 1,
      author
    );
    if (replaceIndex >= 0) {
      schemes[replaceIndex] = scheme;
    } else {
      schemes.push(scheme);
    }
    await CustomThemeSchemeStore.persistSchemes(context, schemes);
    return CustomThemeSchemeStore.cloneScheme(scheme);
  }

  /** 冷启动时先恢复正在使用的方案 ID，阅读设置才能读到这套方案自己的排版。 */
  static async restoreActiveSchemeId(context: Context): Promise<void> {
    const store = await preferences.getPreferences(context, CustomThemeSchemeStore.STORE_NAME);
    const value = await store.get(CustomThemeSchemeStore.KEY_ACTIVE_SCHEME_ID, '');
    if (typeof value === 'string' && value &&
      !AppStorage.get<string>(CustomThemeSchemeStore.STORAGE_ACTIVE_SCHEME_ID)) {
      AppStorage.setOrCreate(CustomThemeSchemeStore.STORAGE_ACTIVE_SCHEME_ID, value);
    }
  }

  static async setActiveScheme(context: Context, scheme: CustomThemeScheme): Promise<void> {
    const store = await preferences.getPreferences(context, CustomThemeSchemeStore.STORE_NAME);
    await store.put(CustomThemeSchemeStore.KEY_ACTIVE_SCHEME_ID, scheme.id);
    await store.put(CustomThemeSchemeStore.KEY_ACTIVE_SCHEME_REVISION, scheme.revision);
    await store.flush();
    AppStorage.setOrCreate(CustomThemeSchemeStore.STORAGE_ACTIVE_SCHEME_ID, scheme.id);
    AppStorage.setOrCreate(CustomThemeSchemeStore.STORAGE_ACTIVE_SCHEME_REVISION, scheme.revision);
  }

  static find(schemes: CustomThemeScheme[], schemeId: string): CustomThemeScheme | null {
    for (const scheme of schemes) {
      if (scheme.id === schemeId) {
        return scheme;
      }
    }
    return null;
  }

  private static async persistSchemes(context: Context, schemes: CustomThemeScheme[]): Promise<void> {
    const store = await preferences.getPreferences(context, CustomThemeSchemeStore.STORE_NAME);
    await store.put(CustomThemeSchemeStore.KEY_SCHEMES, CustomThemeSchemeStore.encode(schemes));
    await store.flush();
    const revision = (AppStorage.get<number>(CustomThemeSchemeStore.STORAGE_REVISION) || 0) + 1;
    AppStorage.setOrCreate(CustomThemeSchemeStore.STORAGE_REVISION, revision);
    CloudSyncChangeTracker.markPreferenceChanged();
  }

  static async replaceFromSync(
    context: Context,
    legacySettings: AppThemeSettings,
    source: CustomThemeScheme[]
  ): Promise<void> {
    const localSchemes = await CustomThemeSchemeStore.load(context, legacySettings);
    const schemes: CustomThemeScheme[] = [];
    for (const item of source || []) {
      if (!item || !item.id) {
        continue;
      }
      const incomingSettings = AppThemeSettingsStore.cloneSettings(item.settings || new AppThemeSettings());
      const localScheme = CustomThemeSchemeStore.find(localSchemes, item.id);
      incomingSettings.themeApplyLayoutEnabled = localScheme ?
        localScheme.settings.themeApplyLayoutEnabled : false;
      // 启动封面图片是设备本地资源，云端只同步方案设置，不覆盖本机文件绑定。
      incomingSettings.customLightStartupImagePath = localScheme ?
        localScheme.settings.customLightStartupImagePath : '';
      incomingSettings.customDarkStartupImagePath = localScheme ?
        localScheme.settings.customDarkStartupImagePath : '';
      schemes.push(CustomThemeSchemeStore.createScheme(
        item.id,
        item.name || `自定义主题 ${schemes.length + 1}`,
        incomingSettings,
        item.revision || 1,
        item.author || ''
      ));
    }
    if (schemes.length === 0) {
      return;
    }
    const store = await preferences.getPreferences(context, CustomThemeSchemeStore.STORE_NAME);
    await store.put(CustomThemeSchemeStore.KEY_SCHEMES, CustomThemeSchemeStore.encode(schemes));
    const activeValue = await store.get(CustomThemeSchemeStore.KEY_ACTIVE_SCHEME_ID, '');
    const activeId = typeof activeValue === 'string' ? activeValue : '';
    if (!CustomThemeSchemeStore.find(schemes, activeId)) {
      await store.put(CustomThemeSchemeStore.KEY_ACTIVE_SCHEME_ID, schemes[0].id);
      await store.put(CustomThemeSchemeStore.KEY_ACTIVE_SCHEME_REVISION, 0);
      AppStorage.setOrCreate(CustomThemeSchemeStore.STORAGE_ACTIVE_SCHEME_ID, schemes[0].id);
      AppStorage.setOrCreate(CustomThemeSchemeStore.STORAGE_ACTIVE_SCHEME_REVISION, 0);
    }
    await store.flush();
    AppStorage.setOrCreate(
      CustomThemeSchemeStore.STORAGE_REVISION,
      (AppStorage.get<number>(CustomThemeSchemeStore.STORAGE_REVISION) || 0) + 1
    );
  }

  private static createScheme(
    id: string,
    name: string,
    settings: AppThemeSettings,
    revision: number,
    author: string = ''
  ): CustomThemeScheme {
    const scheme = new CustomThemeScheme();
    scheme.id = id;
    scheme.name = name;
    scheme.revision = Math.max(1, Math.floor(revision || 1));
    scheme.settings = CustomThemeSchemeStore.normalizeSettings(settings);
    scheme.author = typeof author === 'string' ? author : '';
    return scheme;
  }

  private static normalizeSettings(settings: AppThemeSettings): AppThemeSettings {
    const normalized = AppThemeSettingsStore.cloneSettings(settings);
    normalized.themeId = ThemeIds.CUSTOM;
    normalized.lightAccentColor = normalized.customLightAccentColor;
    normalized.darkAccentColor = normalized.customDarkAccentColor;
    normalized.lightButtonColor = normalized.customLightButtonColor;
    normalized.darkButtonColor = normalized.customDarkButtonColor;
    return AppThemeSettingsStore.cloneSettings(normalized);
  }

  private static encode(schemes: CustomThemeScheme[]): string {
    return JSON.stringify(schemes);
  }

  private static decode(raw: string): CustomThemeScheme[] {
    if (!raw) {
      return [];
    }
    try {
      const parsed = JSON.parse(raw) as CustomThemeScheme[];
      if (!Array.isArray(parsed)) {
        return [];
      }
      const schemes: CustomThemeScheme[] = [];
      for (const item of parsed) {
        if (!item || !item.id) {
          continue;
        }
        schemes.push(CustomThemeSchemeStore.createScheme(
          item.id,
          item.name || `自定义主题 ${schemes.length + 1}`,
          item.settings || new AppThemeSettings(),
          item.revision || 1,
          item.author || ''
        ));
      }
      return schemes;
    } catch (_) {
      return [];
    }
  }

  private static cloneSchemes(schemes: CustomThemeScheme[]): CustomThemeScheme[] {
    const result: CustomThemeScheme[] = [];
    for (const scheme of schemes) {
      result.push(CustomThemeSchemeStore.cloneScheme(scheme));
    }
    return result;
  }

  private static cloneScheme(source: CustomThemeScheme): CustomThemeScheme {
    return CustomThemeSchemeStore.createScheme(source.id, source.name, source.settings, source.revision,
      source.author);
  }
}
