import { UIContext, promptAction, uiMaterial } from '@kit.ArkUI';
import deviceInfo from '@ohos.deviceInfo';
import { ImmersiveMaterialRuntime } from './ImmersiveMaterialRuntime';
import {
  HdsSnackBar,
  SnackBarIconOptions,
  SnackBarMessageOptions,
  SnackBarOperationOptions,
  SnackBarOperationType
} from '@kit.UIDesignKit';

/** Shows API 26+ immersive-light feedback and lets callers retain their Toast fallback. */
export class HdsFeedback {
  static show(uiContext: UIContext | null, message: string): boolean {
    if (uiContext === null || deviceInfo.sdkApiVersion < 26) return false;
    try {
      const snackBar: HdsSnackBar = new HdsSnackBar(uiContext);
      const icon: SnackBarIconOptions = {};
      const content: SnackBarMessageOptions = { title: message };
      const operation: SnackBarOperationOptions = {
        operationType: SnackBarOperationType.TEXT_ONLY,
        content: ''
      };
      snackBar.show(icon, content, operation);
      return true;
    } catch (error) {
      console.warn('HdsSnackBar 不可用，回退到 Toast:', error);
      return false;
    }
  }

  /** Uses the API 26 system-material Toast when supported, otherwise the legacy Toast. */
  static showToast(message: string): void {
    try {
      if (deviceInfo.sdkApiVersion >= 26 && uiMaterial.isImmersiveMaterialSupported()) {
        const material: uiMaterial.ImmersiveMaterial = new uiMaterial.ImmersiveMaterial({
          style: ImmersiveMaterialRuntime.materialStyle(),
          applyShadow: true,
          interactive: ImmersiveMaterialRuntime.configuredLightLevel() !== 'weak',
          lightEffect: ImmersiveMaterialRuntime.lightEffect()
        });
        promptAction.showToast({ message: message, systemMaterial: material });
        return;
      }
    } catch (error) {
      console.warn('创建 API 26 系统材质 Toast 失败，回退普通 Toast:', error);
    }
    promptAction.showToast({ message: message });
  }
}
