import deviceInfo from '@ohos.deviceInfo';
import { uiMaterial } from '@kit.ArkUI';
import { hdsMaterial } from '@kit.UIDesignKit';

/** Centralizes HDS material probing and compatibility fallback. */
export class ImmersiveMaterialRuntime {
  static readonly KEY_LIGHT_LEVEL: string = 'immersiveLightLevel';
  private static resolved: boolean = false;
  private static resolvedType: hdsMaterial.MaterialType = hdsMaterial.MaterialType.ADAPTIVE;
  private static immersiveSupported: boolean | null = null;

  static supportsHds(): boolean {
    // Immersive material is enabled only on API 26+ and only when the device
    // reports support. Older versions, and API 26 devices without the
    // capability, continue to use the existing standard ArkUI components.
    if (deviceInfo.sdkApiVersion < 26) return false;
    if (ImmersiveMaterialRuntime.immersiveSupported !== null) {
      return ImmersiveMaterialRuntime.immersiveSupported;
    }
    try {
      ImmersiveMaterialRuntime.immersiveSupported = uiMaterial.isImmersiveMaterialSupported();
    } catch (error) {
      console.warn('读取沉浸光感设备能力失败，使用兼容界面:', error);
      ImmersiveMaterialRuntime.immersiveSupported = false;
    }
    return ImmersiveMaterialRuntime.immersiveSupported;
  }

  static materialType(): hdsMaterial.MaterialType {
    if (!ImmersiveMaterialRuntime.supportsHds()) return hdsMaterial.MaterialType.NONE;
    if (ImmersiveMaterialRuntime.resolved) return ImmersiveMaterialRuntime.resolvedType;
    ImmersiveMaterialRuntime.resolved = true;
    try {
      const supportedTypes: Array<hdsMaterial.MaterialType> = hdsMaterial.getSystemMaterialTypes();
      ImmersiveMaterialRuntime.resolvedType = supportedTypes.indexOf(hdsMaterial.MaterialType.IMMERSIVE) >= 0 ?
        hdsMaterial.MaterialType.IMMERSIVE : hdsMaterial.MaterialType.ADAPTIVE;
    } catch (error) {
      console.warn('读取系统沉浸光感材质能力失败，使用自适应材质:', error);
      ImmersiveMaterialRuntime.resolvedType = hdsMaterial.MaterialType.ADAPTIVE;
    }
    return ImmersiveMaterialRuntime.resolvedType;
  }

  static materialLevel(): hdsMaterial.MaterialLevel {
    const configured = (AppStorage.get<string>(ImmersiveMaterialRuntime.KEY_LIGHT_LEVEL) || 'adaptive')
      .trim().toLowerCase();
    if (configured === 'high') return hdsMaterial.MaterialLevel.EXQUISITE;
    if (configured === 'balanced') return hdsMaterial.MaterialLevel.GENTLE;
    if (configured === 'weak') return hdsMaterial.MaterialLevel.SMOOTH;
    return hdsMaterial.MaterialLevel.ADAPTIVE;
  }

  /**
   * Shared dropdown material. Select menus otherwise inherit device-specific
   * shadows on API 26+, which makes identical controls look different across
   * pages. Older devices keep the platform fallback by returning undefined.
   */
  static selectMenuMaterial(): uiMaterial.ImmersiveMaterial | undefined {
    if (!ImmersiveMaterialRuntime.supportsHds()) return undefined;
    return new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.REGULAR,
      materialColor: '#00000000',
      applyShadow: false,
      interactive: false,
      lightEffect: null
    });
  }
}
