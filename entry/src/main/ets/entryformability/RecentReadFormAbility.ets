import { ConfigurationConstant, Want } from '@kit.AbilityKit';
import { FormExtensionAbility, formBindingData, formInfo, formProvider } from '@kit.FormKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  RECENT_READ_DEFAULT_DIMENSION,
  RecentReadCardData,
  RecentReadCardDataProvider
} from '../utils/RecentReadCardData';
import { RecentReadCardUpdater } from '../utils/RecentReadCardUpdater';
import { RecentReadFormStore } from '../utils/RecentReadFormStore';

export default class RecentReadFormAbility extends FormExtensionAbility {
  private formDimensions: Map<string, number> = new Map();

  onAddForm(want: Want): formBindingData.FormBindingData {
    const formId = this.getFormId(want);
    const dimension = this.getDimension(want.parameters);
    this.rememberForm(formId, dimension);
    this.updateFormLater(formId, dimension);
    return RecentReadCardUpdater.bindingData(
      RecentReadCardDataProvider.empty(dimension, this.isDarkMode())
    );
  }

  onUpdateForm(formId: string, wantParams?: Record<string, Object>): void {
    const dimension = this.getDimension(wantParams, this.getRememberedDimension(formId));
    this.rememberForm(formId, dimension);
    this.updateFormLater(formId, dimension);
  }

  onFormEvent(formId: string, message: string): void {
    hilog.info(0x0000, 'recentCard', 'Form event %{public}s %{public}s', formId, message);
    const action = this.getEventAction(message);
    if (action && action !== 'refresh') {
      hilog.info(0x0000, 'recentCard', 'Ignore form event %{public}s', action);
      return;
    }
    const dimension = this.getRememberedDimension(formId);
    this.rememberForm(formId, dimension);
    this.updateFormLater(formId, dimension, 'event');
  }

  onSizeChanged(formId: string, newDimension: formInfo.FormDimension): void {
    const dimension = newDimension as number;
    this.rememberForm(formId, dimension);
    this.updateFormLater(formId, dimension);
  }

  onCastToNormalForm(formId: string): void {
    const dimension = this.getRememberedDimension(formId);
    this.rememberForm(formId, dimension);
    this.updateFormLater(formId, dimension);
  }

  onChangeFormVisibility(newStatus: Record<string, number>): void {
    const formIds = Object.keys(newStatus);
    for (const formId of formIds) {
      if (newStatus[formId] !== formInfo.VisibilityType.FORM_VISIBLE) {
        continue;
      }
      const dimension = this.getRememberedDimension(formId);
      this.rememberForm(formId, dimension);
      this.updateFormLater(formId, dimension);
    }
  }

  onRemoveForm(formId: string): void {
    this.formDimensions.delete(formId);
    RecentReadFormStore.remove(this.context, formId).catch((err: Error) => {
      console.error('移除最近阅读卡片信息失败:', err);
    });
  }

  private rememberForm(formId: string, dimension: number): void {
    if (!formId) {
      return;
    }
    const normalizedDimension = this.normalizeDimension(dimension);
    this.formDimensions.set(formId, normalizedDimension);
    RecentReadFormStore.save(this.context, formId, normalizedDimension).catch((err: Error) => {
      console.error('保存最近阅读卡片信息失败:', err);
    });
  }

  private updateFormLater(formId: string, dimension: number, reason: string = 'lifecycle'): void {
    if (!formId) {
      return;
    }
    this.updateFormNow(formId, dimension, reason).catch((err: Error) => {
      console.error('更新最近阅读卡片失败:', err);
    });
  }

  private async updateFormNow(formId: string, dimension: number, reason: string): Promise<void> {
    const data = await this.buildData(dimension);
    try {
      await formProvider.updateForm(formId, RecentReadCardUpdater.bindingData(data));
      hilog.info(
        0x0000,
        'recentCard',
        'FormAbility update %{public}s %{public}s %{public}s',
        formId,
        reason,
        data.orderSignature
      );
    } finally {
      RecentReadCardUpdater.closeFormImages(data);
    }
  }

  private async buildData(dimension: number): Promise<RecentReadCardData> {
    return RecentReadCardDataProvider.load(this.context, dimension, this.isDarkMode());
  }

  private getFormId(want: Want): string {
    const value = want.parameters?.[formInfo.FormParam.IDENTITY_KEY];
    return typeof value === 'string' ? value : '';
  }

  private getDimension(params?: Record<string, Object>, fallback: number = RECENT_READ_DEFAULT_DIMENSION): number {
    const value = params?.[formInfo.FormParam.DIMENSION_KEY];
    return typeof value === 'number' ? this.normalizeDimension(value) : this.normalizeDimension(fallback);
  }

  private getRememberedDimension(formId: string): number {
    return this.normalizeDimension(this.formDimensions.get(formId) || RECENT_READ_DEFAULT_DIMENSION);
  }

  private normalizeDimension(dimension: number): number {
    return dimension > 0 ? dimension : RECENT_READ_DEFAULT_DIMENSION;
  }

  private getEventAction(message: string): string {
    if (!message) {
      return '';
    }
    try {
      const parsed = JSON.parse(message) as CardEventMessage;
      if (parsed.params && parsed.params.action) {
        return parsed.params.action;
      }
      if (parsed.action === 'message') {
        return '';
      }
      return parsed.action || '';
    } catch (e) {
      return message === 'refresh' ? 'refresh' : '';
    }
  }

  private isDarkMode(): boolean {
    return this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  }
}

class CardEventMessage {
  action: string = '';
  params: CardEventParams = new CardEventParams();
}

class CardEventParams {
  action: string = '';
}
