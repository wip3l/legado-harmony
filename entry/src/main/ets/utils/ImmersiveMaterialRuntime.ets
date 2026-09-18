import deviceInfo from '@ohos.deviceInfo';
import { uiMaterial } from '@kit.ArkUI';
import { hdsMaterial } from '@kit.UIDesignKit';

/** Centralizes HDS material probing and compatibility fallback. */
export class ImmersiveMaterialRuntime {
  static readonly KEY_LIGHT_LEVEL: string = 'immersiveLightLevel';
  private static resolved: boolean = false;
  private static resolvedType: hdsMaterial.MaterialType = hdsMaterial.MaterialType.ADAPTIVE;
  private static hdsMaterialSupported: boolean | null = null;
  private static immersiveSupported: boolean | null = null;

  static supportsHds(): boolean {
    // ArkUI uiMaterial.ImmersiveMaterial is an API 26 feature. Keep this
    // capability separate from HDS tabs/material, which starts at API 23.
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

  /** HDS tabs/floating bars and HDS system materials start at HarmonyOS 6/API 23. */
  static supportsHdsTabs(): boolean {
    return deviceInfo.sdkApiVersion >= 23;
  }

  /**
   * HDS list containers are used for swipe actions. Keep their gate in the
   * same runtime capability helper as the other HDS controls so pages do not
   * each make a subtly different SDK-only decision.
   */
  static supportsHdsListItem(): boolean {
    return deviceInfo.sdkApiVersion >= 26;
  }

  /** HDS SnackBar is exposed from API 26 and still needs a UI context. */
  static supportsHdsSnackBar(): boolean {
    return deviceInfo.sdkApiVersion >= 26;
  }

  /**
   * HDS system material (used by HdsTabs floating bars) is available from
   * HarmonyOS 6/API 23. This is intentionally separate from supportsHds(),
   * which checks the API 26 ArkUI uiMaterial namespace used by menus/buttons.
   */
  static supportsHdsMaterial(): boolean {
    if (!ImmersiveMaterialRuntime.supportsHdsTabs()) return false;
    if (ImmersiveMaterialRuntime.hdsMaterialSupported !== null) {
      return ImmersiveMaterialRuntime.hdsMaterialSupported;
    }
    try {
      const supportedTypes: Array<hdsMaterial.MaterialType> = hdsMaterial.getSystemMaterialTypes();
      ImmersiveMaterialRuntime.hdsMaterialSupported = supportedTypes.indexOf(hdsMaterial.MaterialType.IMMERSIVE) >= 0 ||
        supportedTypes.indexOf(hdsMaterial.MaterialType.ADAPTIVE) >= 0;
    } catch (error) {
      console.warn('读取 HDS 系统材质能力失败，使用兼容底栏:', error);
      ImmersiveMaterialRuntime.hdsMaterialSupported = false;
    }
    return ImmersiveMaterialRuntime.hdsMaterialSupported;
  }

  static materialType(): hdsMaterial.MaterialType {
    if (!ImmersiveMaterialRuntime.supportsHdsMaterial()) return hdsMaterial.MaterialType.NONE;
    if (ImmersiveMaterialRuntime.resolved) return ImmersiveMaterialRuntime.resolvedType;
    ImmersiveMaterialRuntime.resolved = true;
    try {
      const supportedTypes: Array<hdsMaterial.MaterialType> = hdsMaterial.getSystemMaterialTypes();
      ImmersiveMaterialRuntime.resolvedType = supportedTypes.indexOf(hdsMaterial.MaterialType.IMMERSIVE) >= 0 ?
        hdsMaterial.MaterialType.IMMERSIVE :
        supportedTypes.indexOf(hdsMaterial.MaterialType.ADAPTIVE) >= 0 ?
          hdsMaterial.MaterialType.ADAPTIVE : hdsMaterial.MaterialType.NONE;
    } catch (error) {
      console.warn('读取系统沉浸光感材质能力失败，使用兼容底栏:', error);
      ImmersiveMaterialRuntime.resolvedType = hdsMaterial.MaterialType.NONE;
    }
    return ImmersiveMaterialRuntime.resolvedType;
  }

  static materialLevel(): hdsMaterial.MaterialLevel {
    const configured = ImmersiveMaterialRuntime.configuredLightLevel();
    if (configured === 'high') return hdsMaterial.MaterialLevel.EXQUISITE;
    if (configured === 'balanced') return hdsMaterial.MaterialLevel.GENTLE;
    if (configured === 'weak') return hdsMaterial.MaterialLevel.SMOOTH;
    return hdsMaterial.MaterialLevel.ADAPTIVE;
  }

  /** Returns the persisted app-level light setting, defaulting to follow-system. */
  static configuredLightLevel(): string {
    return (AppStorage.get<string>(ImmersiveMaterialRuntime.KEY_LIGHT_LEVEL) || 'adaptive')
      .trim().toLowerCase();
  }

  /** Maps the app setting to the closest API 26 material style for component-level materials. */
  static materialStyle(): uiMaterial.ImmersiveStyle {
    const configured = ImmersiveMaterialRuntime.configuredLightLevel();
    if (configured === 'high') return uiMaterial.ImmersiveStyle.ULTRA_THIN;
    if (configured === 'weak') return uiMaterial.ImmersiveStyle.THICK;
    return uiMaterial.ImmersiveStyle.REGULAR;
  }

  /**
   * Component-level immersive materials do not expose HDS MaterialLevel. Their
   * light-sense feedback is therefore mapped to the same app setting instead.
   * Undefined leaves the component-level light feedback unset, while null
   * disables it explicitly.
   */
  static lightEffect(forceAdaptive: boolean = false): uiMaterial.LightEffectOptions | null | undefined {
    const configured = ImmersiveMaterialRuntime.configuredLightLevel();
    if (configured === 'high') return { color: '#88FFFFFF' };
    if (configured === 'balanced') return { color: '#55FFFFFF' };
    if (configured === 'weak') return null;
    // An undefined lightEffect means "do not enable light feedback" for a
    // component-level material. Stepper buttons opt in explicitly so the
    // default follow-system setting still provides the expected touch glow.
    if (forceAdaptive) return { color: '#55FFFFFF' };
    return undefined;
  }

  /**
   * Shared dropdown material. Select menus otherwise inherit device-specific
   * shadows on API 26+, which makes identical controls look different across
   * pages. Older devices keep the platform fallback by returning undefined.
   */
  static selectMenuMaterial(): uiMaterial.ImmersiveMaterial | undefined {
    if (!ImmersiveMaterialRuntime.supportsHds()) return undefined;
    return new uiMaterial.ImmersiveMaterial({
      style: ImmersiveMaterialRuntime.materialStyle(),
      materialColor: '#00000000',
      applyShadow: false,
      interactive: ImmersiveMaterialRuntime.configuredLightLevel() !== 'weak',
      lightEffect: ImmersiveMaterialRuntime.lightEffect()
    });
  }
}
