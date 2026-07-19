import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';

export class BookSourceGroupStore {
  private static readonly STORE_NAME: string = 'book_source_groups';
  private static readonly KEY_GROUPS: string = 'groups';
  private static readonly KEY_USER_GROUPS: string = 'user_groups';
  private static readonly KEY_USER_GROUPS_READY: string = 'user_groups_ready';

  static async load(context: Context, sourceGroups: string[] = []): Promise<string[]> {
    const store = await preferences.getPreferences(context, BookSourceGroupStore.STORE_NAME);
    const raw = await store.get(BookSourceGroupStore.KEY_GROUPS, '');
    const storedGroups = BookSourceGroupStore.decode(typeof raw === 'string' ? raw : '');
    const normalizedSourceGroups = BookSourceGroupStore.normalize(sourceGroups);
    const userRaw = await store.get(BookSourceGroupStore.KEY_USER_GROUPS, '');
    const readyRaw = await store.get(BookSourceGroupStore.KEY_USER_GROUPS_READY, false);
    let userGroups = BookSourceGroupStore.decode(typeof userRaw === 'string' ? userRaw : '');
    if (readyRaw !== true) {
      // 旧版本没有记录分组来源：当前没有书源引用的持久分组只能来自用户手动创建。
      userGroups = storedGroups.filter((group: string) => !normalizedSourceGroups.includes(group));
    }
    const groups = BookSourceGroupStore.normalize(userGroups.concat(normalizedSourceGroups));
    await BookSourceGroupStore.save(context, groups, userGroups);
    return groups;
  }

  static async add(context: Context, groupName: string, groups: string[], userCreated: boolean = true): Promise<string[]> {
    const next = BookSourceGroupStore.normalize(groups.concat([groupName]));
    const userGroups = await BookSourceGroupStore.loadUserGroups(context);
    const nextUserGroups = userCreated ? BookSourceGroupStore.normalize(userGroups.concat([groupName])) : userGroups;
    await BookSourceGroupStore.save(context, next, nextUserGroups);
    return next;
  }

  static async rename(context: Context, oldName: string, newName: string, groups: string[]): Promise<string[]> {
    const next = BookSourceGroupStore.normalize(groups.map((group: string) => group === oldName ? newName : group));
    const userGroups = await BookSourceGroupStore.loadUserGroups(context);
    const nextUserGroups = BookSourceGroupStore.normalize(
      userGroups.map((group: string) => group === oldName ? newName : group)
    );
    await BookSourceGroupStore.save(context, next, nextUserGroups);
    return next;
  }

  static async remove(context: Context, groupName: string, groups: string[]): Promise<string[]> {
    const next = BookSourceGroupStore.normalize(groups.filter((group: string) => group !== groupName));
    const userGroups = await BookSourceGroupStore.loadUserGroups(context);
    const nextUserGroups = BookSourceGroupStore.normalize(
      userGroups.filter((group: string) => group !== groupName)
    );
    await BookSourceGroupStore.save(context, next, nextUserGroups);
    return next;
  }

  private static async loadUserGroups(context: Context): Promise<string[]> {
    const store = await preferences.getPreferences(context, BookSourceGroupStore.STORE_NAME);
    const raw = await store.get(BookSourceGroupStore.KEY_USER_GROUPS, '');
    return BookSourceGroupStore.decode(typeof raw === 'string' ? raw : '');
  }

  private static async save(context: Context, groups: string[], userGroups: string[]): Promise<void> {
    const store = await preferences.getPreferences(context, BookSourceGroupStore.STORE_NAME);
    await store.put(BookSourceGroupStore.KEY_GROUPS, BookSourceGroupStore.encode(groups));
    await store.put(BookSourceGroupStore.KEY_USER_GROUPS, BookSourceGroupStore.encode(userGroups));
    await store.put(BookSourceGroupStore.KEY_USER_GROUPS_READY, true);
    await store.flush();
  }

  private static normalize(groups: string[]): string[] {
    const result: string[] = [];
    for (const item of groups) {
      const group = (item || '').trim();
      if (group && !result.includes(group)) {
        result.push(group);
      }
    }
    return result.sort((a: string, b: string) => a.localeCompare(b));
  }

  private static decode(raw: string): string[] {
    if (!raw) {
      return [];
    }
    try {
      const parsed = JSON.parse(raw) as string[];
      return Array.isArray(parsed) ? BookSourceGroupStore.normalize(parsed) : [];
    } catch (e) {
      return [];
    }
  }

  private static encode(groups: string[]): string {
    return JSON.stringify(BookSourceGroupStore.normalize(groups));
  }
}
