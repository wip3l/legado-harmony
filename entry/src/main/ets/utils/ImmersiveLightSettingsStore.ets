import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';

/** 显式落盘；AppStorage 只负责通知界面，不作为唯一保存来源。 */
export class ImmersiveLightSettingsStore {
  static readonly KEY: string = 'immersiveLightLevel';
  static readonly STORE_NAME: string = 'immersive_light_settings';
  private static revision: number = 0;
  private static writes: Promise<void> = Promise.resolve();

  static normalize(value: string): string {
    return ['adaptive', 'high', 'balanced', 'weak'].includes(value) ? value : 'adaptive';
  }

  static async load(context: Context): Promise<void> {
    const revision = ImmersiveLightSettingsStore.revision;
    const store = await preferences.getPreferences(context, ImmersiveLightSettingsStore.STORE_NAME);
    // 首次升级沿用旧 PersistentStorage 中仍可读取的值。
    const legacy = AppStorage.get<string>(ImmersiveLightSettingsStore.KEY) || 'adaptive';
    const value = await store.get(ImmersiveLightSettingsStore.KEY, '');
    if (revision !== ImmersiveLightSettingsStore.revision) return;
    if (value === '') {
      await ImmersiveLightSettingsStore.save(context, legacy);
      return;
    }
    AppStorage.setOrCreate(ImmersiveLightSettingsStore.KEY,
      ImmersiveLightSettingsStore.normalize(typeof value === 'string' ? value : 'adaptive'));
  }

  static save(context: Context, value: string): Promise<void> {
    const next = ImmersiveLightSettingsStore.normalize(value);
    ++ImmersiveLightSettingsStore.revision;
    const write = ImmersiveLightSettingsStore.writes.then(async (): Promise<void> => {
      const store = await preferences.getPreferences(context, ImmersiveLightSettingsStore.STORE_NAME);
      await store.put(ImmersiveLightSettingsStore.KEY, next);
      await store.flush();
      AppStorage.setOrCreate(ImmersiveLightSettingsStore.KEY, next);
    });
    ImmersiveLightSettingsStore.writes = write.catch(() => {});
    return write;
  }
}
