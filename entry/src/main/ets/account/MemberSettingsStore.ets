import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';

/** 会员标识的本机显示偏好，不参与会员权限判断。 */
export class MemberSettingsStore {
  static readonly STORE_NAME: string = 'member_display_settings';
  static readonly IDENTITY_VISIBLE: string = 'memberIdentityVisible';
  static readonly SETTINGS_VISIBLE: string = 'memberSettingsVisible';
  private static revision: number = 0;
  private static writes: Promise<void> = Promise.resolve();

  static async load(context: Context): Promise<void> {
    const revision = MemberSettingsStore.revision;
    const store = await preferences.getPreferences(context, MemberSettingsStore.STORE_NAME);
    const identity = await store.get(MemberSettingsStore.IDENTITY_VISIBLE, true);
    const settings = await store.get(MemberSettingsStore.SETTINGS_VISIBLE, true);
    if (revision !== MemberSettingsStore.revision) return;
    AppStorage.setOrCreate(MemberSettingsStore.IDENTITY_VISIBLE, typeof identity === 'boolean' ? identity : true);
    AppStorage.setOrCreate(MemberSettingsStore.SETTINGS_VISIBLE, typeof settings === 'boolean' ? settings : true);
  }

  static save(context: Context, key: string, enabled: boolean): Promise<void> {
    if (key !== MemberSettingsStore.IDENTITY_VISIBLE && key !== MemberSettingsStore.SETTINGS_VISIBLE) {
      return Promise.reject(new Error('未知会员设置'));
    }
    ++MemberSettingsStore.revision;
    const write = MemberSettingsStore.writes.then(async (): Promise<void> => {
      const store = await preferences.getPreferences(context, MemberSettingsStore.STORE_NAME);
      await store.put(key, enabled);
      await store.flush();
      AppStorage.setOrCreate(key, enabled);
    });
    MemberSettingsStore.writes = write.catch(() => {});
    return write;
  }
}
