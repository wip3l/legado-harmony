import { common } from '@kit.AbilityKit';
import { formProvider } from '@kit.FormKit';
import { RECENT_READ_FORM_ABILITY, RECENT_READ_FORM_NAME } from './RecentReadCardData';

export class RecentReadCardUpdater {
  static async reload(context: common.UIAbilityContext): Promise<void> {
    try {
      await formProvider.reloadForms(context, 'entry', RECENT_READ_FORM_ABILITY, RECENT_READ_FORM_NAME);
    } catch (e) {
      console.error('刷新最近阅读卡片失败:', e);
    }
  }
}
