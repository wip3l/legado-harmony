import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';

export class BookSourceGroupStore {
  private static readonly STORE_NAME: string = 'book_source_groups';
  private static readonly KEY_GROUPS: string = 'groups';

  static async load(context: Context, sourceGroups: string[] = []): Promise<string[]> {
    const store = await preferences.getPreferences(context, BookSourceGroupStore.STORE_NAME);
    const raw = await store.get(BookSourceGroupStore.KEY_GROUPS, '');
    const storedGroups = BookSourceGroupStore.decode(typeof raw === 'string' ? raw : '');
    const groups = BookSourceGroupStore.normalize(storedGroups.concat(sourceGroups));
    if (BookSourceGroupStore.encode(groups) !== BookSourceGroupStore.encode(storedGroups)) {
      await BookSourceGroupStore.save(context, groups);
    }
    return groups;
  }

  static async add(context: Context, groupName: string, groups: string[]): Promise<string[]> {
    const next = BookSourceGroupStore.normalize(groups.concat([groupName]));
    await BookSourceGroupStore.save(context, next);
    return next;
  }

  static async rename(context: Context, oldName: string, newName: string, groups: string[]): Promise<string[]> {
    const next = BookSourceGroupStore.normalize(groups.map((group: string) => group === oldName ? newName : group));
    await BookSourceGroupStore.save(context, next);
    return next;
  }

  static async remove(context: Context, groupName: string, groups: string[]): Promise<string[]> {
    const next = BookSourceGroupStore.normalize(groups.filter((group: string) => group !== groupName));
    await BookSourceGroupStore.save(context, next);
    return next;
  }

  private static async save(context: Context, groups: string[]): Promise<void> {
    const store = await preferences.getPreferences(context, BookSourceGroupStore.STORE_NAME);
    await store.put(BookSourceGroupStore.KEY_GROUPS, BookSourceGroupStore.encode(groups));
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
