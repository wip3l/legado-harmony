import { ConfigurationConstant, Want } from '@kit.AbilityKit';
import { FormExtensionAbility, formBindingData, formInfo, formProvider } from '@kit.FormKit';
import { RecentReadCardData, RecentReadCardDataProvider } from '../utils/RecentReadCardData';

export default class RecentReadFormAbility extends FormExtensionAbility {
  private formDimensions: Map<string, number> = new Map();

  onAddForm(want: Want): formBindingData.FormBindingData {
    const formId = this.getFormId(want);
    const dimension = this.getDimension(want.parameters);
    this.formDimensions.set(formId, dimension);
    const data = RecentReadCardDataProvider.empty(dimension, this.isDarkMode());
    this.updateFormLater(formId, dimension);
    return formBindingData.createFormBindingData(data);
  }

  onUpdateForm(formId: string, wantParams?: Record<string, Object>): void {
    const dimension = this.getDimension(wantParams, this.formDimensions.get(formId) || 2);
    this.formDimensions.set(formId, dimension);
    this.updateFormLater(formId, dimension);
  }

  onFormEvent(formId: string, message: string): void {
    if (message) {
      this.updateFormLater(formId, this.formDimensions.get(formId) || 2);
    }
  }

  onSizeChanged(formId: string, newDimension: formInfo.FormDimension): void {
    this.formDimensions.set(formId, newDimension as number);
    this.updateFormLater(formId, newDimension as number);
  }

  private getFormId(want: Want): string {
    const value = want.parameters?.[formInfo.FormParam.IDENTITY_KEY];
    return typeof value === 'string' ? value : '';
  }

  private getDimension(params?: Record<string, Object>, fallback: number = 2): number {
    const value = params?.[formInfo.FormParam.DIMENSION_KEY];
    return typeof value === 'number' ? value : fallback;
  }

  private updateFormLater(formId: string, dimension: number): void {
    if (!formId) {
      return;
    }
    this.buildData(dimension).then((data: RecentReadCardData) => {
      formProvider.updateForm(formId, formBindingData.createFormBindingData(data)).catch((err: Error) => {
        console.error('更新最近阅读卡片失败:', err);
      });
    }).catch((err: Error) => {
      console.error('加载最近阅读卡片数据失败:', err);
    });
  }

  private async buildData(dimension: number): Promise<RecentReadCardData> {
    return RecentReadCardDataProvider.load(this.context, dimension, this.isDarkMode());
  }

  private isDarkMode(): boolean {
    return this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  }
}
