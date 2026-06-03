import { ConfigurationConstant, Want } from '@kit.AbilityKit';
import { FormExtensionAbility, formBindingData, formInfo, formProvider } from '@kit.FormKit';
import { RecentReadCardData, RecentReadCardDataProvider } from '../utils/RecentReadCardData';
import { BookCoverCache } from '../utils/BookCoverCache';
import fs from '@ohos.file.fs';

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
    this.buildData(dimension).then(async (data: RecentReadCardData) => {
      data.formImages = await this.buildFormImages(data);
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

  private async buildFormImages(data: RecentReadCardData): Promise<Record<string, number>> {
    const formImages: Record<string, number> = {};
    await this.bindCoverImage(formImages, 'book0Cover0', data.book0Cover0Raw);
    await this.bindCoverImage(formImages, 'book0Cover1', data.book0Cover1Raw);
    await this.bindCoverImage(formImages, 'book0Cover2', data.book0Cover2Raw);
    await this.bindCoverImage(formImages, 'book1Cover0', data.book1Cover0Raw);
    await this.bindCoverImage(formImages, 'book1Cover1', data.book1Cover1Raw);
    await this.bindCoverImage(formImages, 'book1Cover2', data.book1Cover2Raw);
    await this.bindCoverImage(formImages, 'book2Cover0', data.book2Cover0Raw);
    await this.bindCoverImage(formImages, 'book2Cover1', data.book2Cover1Raw);
    await this.bindCoverImage(formImages, 'book2Cover2', data.book2Cover2Raw);
    return formImages;
  }

  private async bindCoverImage(formImages: Record<string, number>, key: string, raw: string): Promise<void> {
    if (!raw) {
      return;
    }
    try {
      const imagePath = await BookCoverCache.prepareCoverFile(this.context, raw);
      if (!imagePath) {
        return;
      }
      const file = fs.openSync(imagePath, fs.OpenMode.READ_ONLY);
      formImages[key] = file.fd;
    } catch (e) {
      console.warn(`准备卡片封面失败 ${key}:`, e);
    }
  }

  private isDarkMode(): boolean {
    return this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  }
}
