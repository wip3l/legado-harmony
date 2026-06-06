import { Context } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';

export class RecentReadFormInfo {
  formId: string = '';
  dimension: number = 3;
}

export class RecentReadFormStore {
  private static readonly STORE_NAME: string = 'recent_read_forms';
  private static readonly KEY_FORMS: string = 'forms';

  static async load(context: Context): Promise<RecentReadFormInfo[]> {
    try {
      const store = await preferences.getPreferences(
        RecentReadFormStore.preferencesContext(context),
        RecentReadFormStore.STORE_NAME
      );
      const raw = await store.get(RecentReadFormStore.KEY_FORMS, '[]');
      if (typeof raw !== 'string') {
        return [];
      }
      const parsed = JSON.parse(raw) as RecentReadFormInfo[];
      if (!Array.isArray(parsed)) {
        return [];
      }
      const forms: RecentReadFormInfo[] = [];
      for (const item of parsed) {
        const formId = item.formId || '';
        if (!formId) {
          continue;
        }
        const form = new RecentReadFormInfo();
        form.formId = formId;
        form.dimension = RecentReadFormStore.normalizeDimension(item.dimension);
        forms.push(form);
      }
      return forms;
    } catch (e) {
      return [];
    }
  }

  static async save(context: Context, formId: string, dimension: number): Promise<void> {
    if (!formId) {
      return;
    }
    const forms = await RecentReadFormStore.load(context);
    const normalizedDimension = RecentReadFormStore.normalizeDimension(dimension);
    let updated = false;
    for (const form of forms) {
      if (form.formId === formId) {
        form.dimension = normalizedDimension;
        updated = true;
        break;
      }
    }
    if (!updated) {
      const form = new RecentReadFormInfo();
      form.formId = formId;
      form.dimension = normalizedDimension;
      forms.push(form);
    }
    await RecentReadFormStore.persist(context, forms);
  }

  static async remove(context: Context, formId: string): Promise<void> {
    if (!formId) {
      return;
    }
    const forms = await RecentReadFormStore.load(context);
    await RecentReadFormStore.persist(context, forms.filter((form: RecentReadFormInfo) => form.formId !== formId));
  }

  private static async persist(context: Context, forms: RecentReadFormInfo[]): Promise<void> {
    try {
      const store = await preferences.getPreferences(
        RecentReadFormStore.preferencesContext(context),
        RecentReadFormStore.STORE_NAME
      );
      await store.put(RecentReadFormStore.KEY_FORMS, JSON.stringify(forms));
      await store.flush();
    } catch (e) {
      console.error('持久化最近阅读卡片信息失败:', e);
    }
  }

  private static preferencesContext(context: Context): Context {
    try {
      return context.getApplicationContext();
    } catch (e) {
      return context;
    }
  }

  private static normalizeDimension(dimension: number): number {
    return dimension > 0 ? dimension : 3;
  }
}
