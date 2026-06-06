import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { formBindingData, formInfo, formProvider } from '@kit.FormKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import fs from '@ohos.file.fs';
import {
  RECENT_READ_FORM_ABILITY,
  RECENT_READ_FORM_MODULE,
  RECENT_READ_FORM_NAME,
  RecentReadCardData,
  RecentReadCardDataProvider
} from './RecentReadCardData';
import { RecentReadFormInfo, RecentReadFormStore } from './RecentReadFormStore';

export class RecentReadCardUpdater {
  static async reload(context: common.UIAbilityContext): Promise<void> {
    const forms = await RecentReadCardUpdater.loadKnownForms(context);
    if (forms.length === 0) {
      await RecentReadCardUpdater.requestSystemReload(context);
      return;
    }

    const darkMode = context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    let updated = false;
    for (const form of forms) {
      updated = await RecentReadCardUpdater.updateOne(context, form, darkMode) || updated;
    }
    if (!updated) {
      await RecentReadCardUpdater.requestSystemReload(context);
    }
  }

  private static async loadKnownForms(context: common.UIAbilityContext): Promise<RecentReadFormInfo[]> {
    const formMap: Map<string, RecentReadFormInfo> = new Map();
    const storedForms = await RecentReadFormStore.load(context);
    for (const form of storedForms) {
      if (form.formId) {
        formMap.set(form.formId, form);
      }
    }

    try {
      const runningForms = await formProvider.getPublishedRunningFormInfos();
      for (const runningForm of runningForms) {
        if (!RecentReadCardUpdater.isRecentReadForm(runningForm)) {
          continue;
        }
        const form = new RecentReadFormInfo();
        form.formId = runningForm.formId;
        form.dimension = RecentReadCardUpdater.normalizeDimension(runningForm.dimension);
        formMap.set(form.formId, form);
        await RecentReadFormStore.save(context, form.formId, form.dimension);
      }
    } catch (e) {
      console.info('查询运行中的最近阅读卡片失败，使用已保存的卡片信息:', e);
    }

    return Array.from(formMap.values());
  }

  private static async updateOne(
    context: common.UIAbilityContext,
    form: RecentReadFormInfo,
    darkMode: boolean
  ): Promise<boolean> {
    let data: RecentReadCardData | null = null;
    try {
      data = await RecentReadCardDataProvider.load(context, form.dimension, darkMode);
      await formProvider.updateForm(form.formId, RecentReadCardUpdater.bindingData(data));
      hilog.info(0x0000, 'recentCard', 'Updater update %{public}s %{public}s', form.formId, data.orderSignature);
      return true;
    } catch (e) {
      console.error(`更新最近阅读卡片失败 ${form.formId}:`, e);
      return false;
    } finally {
      if (data) {
        RecentReadCardUpdater.closeFormImages(data);
      }
    }
  }

  private static async requestSystemReload(context: common.UIAbilityContext): Promise<void> {
    try {
      const count = await formProvider.reloadForms(
        context,
        RECENT_READ_FORM_MODULE,
        RECENT_READ_FORM_ABILITY,
        RECENT_READ_FORM_NAME
      );
      hilog.info(0x0000, 'recentCard', 'System reload %{public}d', count);
    } catch (e) {
      console.info('请求系统重载最近阅读卡片失败，已使用直接 updateForm 路径:', e);
    }
  }

  private static isRecentReadForm(runningForm: formInfo.RunningFormInfo): boolean {
    if (runningForm.formName !== RECENT_READ_FORM_NAME) {
      return false;
    }
    if (runningForm.moduleName && runningForm.moduleName !== RECENT_READ_FORM_MODULE) {
      return false;
    }
    if (runningForm.abilityName && runningForm.abilityName !== RECENT_READ_FORM_ABILITY) {
      return false;
    }
    return true;
  }

  private static normalizeDimension(dimension: number): number {
    return dimension > 0 ? dimension : 3;
  }

  static bindingData(data: RecentReadCardData): formBindingData.FormBindingData {
    return formBindingData.createFormBindingData(data);
  }

  static closeFormImages(data: RecentReadCardData): void {
    const formImages: Record<string, number> = data.formImages;
    const keys = Object.keys(formImages);
    for (const key of keys) {
      const fd = formImages[key];
      if (fd <= 0) {
        continue;
      }
      try {
        fs.closeSync(fd);
      } catch (e) {
        console.warn('关闭最近阅读卡片封面文件失败:', e);
      }
      formImages[key] = 0;
    }
  }
}
