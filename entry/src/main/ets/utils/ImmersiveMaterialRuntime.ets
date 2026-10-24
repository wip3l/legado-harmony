import deviceInfo from '@ohos.deviceInfo';
import { display, uiMaterial } from '@kit.ArkUI';
import { hdsMaterial } from '@kit.UIDesignKit';
import { ThemeRuntime } from '../theme/ThemeRuntime';

export interface ImmersiveSurfaceBorder {
  width: number;
  color: ResourceColor;
}

/**
 * Applies the shared dropdown material to a Select. `menuSystemMaterial` only exists from API 26; calling the
 * attribute directly on an older system fails while the page is being built, so it is set through this modifier,
 * which leaves older systems on their platform default.
 */
export class SelectMenuMaterialModifier implements AttributeModifier<SelectAttribute> {
  private lightLevel: string;

  constructor(lightLevel: string) {
    this.lightLevel = lightLevel;
  }

  applyNormalAttribute(instance: SelectAttribute): void {
    if (deviceInfo.sdkApiVersion >= 20) {
      instance.menuOutline(ImmersiveMaterialRuntime.surfaceBorder(this.lightLevel,
        AppStorage.get<boolean>('appDarkMode') || false));
    }
    if (deviceInfo.sdkApiVersion < 26) return;
    instance.menuSystemMaterial(ImmersiveMaterialRuntime.selectMenuMaterial(this.lightLevel));
    if (ImmersiveMaterialRuntime.reducedMaterial(this.lightLevel)) {
      instance.menuBackgroundColor(ImmersiveMaterialRuntime.surfaceColor(this.lightLevel,
        AppStorage.get<boolean>('appDarkMode') || false));
      instance.menuBackgroundBlurStyle(ImmersiveMaterialRuntime.surfaceBlur(this.lightLevel));
    } else {
      // 同一个 Select 从弱/均衡切回跟随系统时，清除上次覆盖的底色与模糊。
      instance.menuBackgroundColor(Color.Transparent);
      instance.menuBackgroundBlurStyle(BlurStyle.NONE);
    }
  }
}

/**
 * 彩色标签的玻璃胶囊：标签原浅底色上叠一层自上而下的高光渐变、一圈同色系半透明细边，
 * 再用标签文字色做很淡的柔和投影，让标签像悬浮栏的沉浸材质那样有反光、轮廓和浮起感。
 * 组件级系统材质放在不透明卡片里没有可透出的内容，几乎看不见，所以这里直接画出这三层，
 * 各系统版本效果一致。文字颜色由调用处照旧设置，按序号配色的规则不变。
 */
export class ImmersiveTagModifier implements AttributeModifier<CommonAttribute> {
  static readonly CAPSULE_RADIUS: number = 999;
  private surfaceColor: string;
  private lightColor: string;
  private darkMode: boolean;

  /**
   * @param surfaceColor 标签原本的浅底色
   * @param lightColor 标签文字色，用于边缘与投影的色调
   */
  constructor(surfaceColor: string, lightColor: string, darkMode: boolean) {
    this.surfaceColor = surfaceColor;
    this.lightColor = lightColor;
    this.darkMode = darkMode;
  }

  applyNormalAttribute(instance: CommonAttribute): void {
    const surface = ImmersiveTagModifier.isHex(this.surfaceColor) ? this.surfaceColor : '#F0F0F0';
    // 顶部向白色提亮，模拟玻璃上沿的反光；深色模式提亮幅度小一些。
    const highlight = ImmersiveTagModifier.mixWithWhite(surface, this.darkMode ? 0.14 : 0.7);
    instance.linearGradient({
      direction: GradientDirection.Bottom,
      colors: [[highlight, 0], [surface, 0.62], [surface, 1]]
    });
    if (ImmersiveTagModifier.isHex(this.lightColor)) {
      const tone = this.lightColor.substring(1);
      instance.border({ width: 0.75, color: `${this.darkMode ? '#4D' : '#3D'}${tone}` });
      instance.shadow({
        radius: 6,
        color: `${this.darkMode ? '#33' : '#2E'}${tone}`,
        offsetX: 0,
        offsetY: 2
      });
    }
    // 胶囊形：圆角超过高度一半时按一半绘制。
    instance.borderRadius(ImmersiveTagModifier.CAPSULE_RADIUS);
  }

  private static isHex(color: string): boolean {
    return /^#[0-9A-Fa-f]{6}$/.test(color);
  }

  private static mixWithWhite(hex: string, ratio: number): string {
    const channel = (start: number): string => {
      const value = parseInt(hex.substring(start, start + 2), 16);
      const mixed = Math.round(value + (255 - value) * ratio);
      return mixed.toString(16).padStart(2, '0').toUpperCase();
    };
    return `#${channel(1)}${channel(3)}${channel(5)}`;
  }
}

/**
 * 玻璃标签（白玻璃彩字）：放在有图像的背景上（模糊封面行、详情页氛围背景、弹出层）时使用。
 * 半透明白底自上而下略淡、上沿稍亮，再加白色细边与很浅的投影；
 * 直接绘制而不用组件级系统材质（后者在真机上几乎不可见），各系统版本效果一致。
 * 文字颜色由调用处按序号配色设置。
 */
export class GlassTagModifier implements AttributeModifier<CommonAttribute> {
  private darkMode: boolean;

  constructor(darkMode: boolean) {
    this.darkMode = darkMode;
  }

  applyNormalAttribute(instance: CommonAttribute): void {
    // 不做实时背景模糊：列表里几十个标签各开一块离屏缓冲，显存开销过大；背后的封面本身已是模糊图。
    instance.linearGradient({
      direction: GradientDirection.Bottom,
      colors: this.darkMode ?
        [['#2EFFFFFF', 0], ['#1FFFFFFF', 0.5], ['#1AFFFFFF', 1]] :
        [['#D9FFFFFF', 0], ['#A6FFFFFF', 0.5], ['#99FFFFFF', 1]]
    });
    instance.border({ width: 0.5, color: this.darkMode ? '#26FFFFFF' : '#E6FFFFFF' });
    instance.shadow({ radius: 4, color: this.darkMode ? '#33000000' : '#1A000000', offsetX: 0, offsetY: 1 });
    instance.borderRadius(ImmersiveTagModifier.CAPSULE_RADIUS);
  }
}

/** Centralizes HDS material probing and compatibility fallback. */
export class ImmersiveMaterialRuntime {
  static readonly KEY_LIGHT_LEVEL: string = 'immersiveLightLevel';
  /** 下拉弹出菜单的圆角与内边距；菜单项圆角取两者之差，与弹出层同心。 */
  static readonly POPUP_MENU_RADIUS: number = 18;
  static readonly POPUP_MENU_PADDING: number = 4;
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

  static materialLevel(configured: string = ImmersiveMaterialRuntime.configuredLightLevel()): hdsMaterial.MaterialLevel {
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

  /** ArkUI 的材质等级由系统决定，厚度/触摸光效不能代替等级。手动降档时显式关闭原材质。 */
  static reducedMaterial(level: string): boolean {
    return level === 'weak' || level === 'balanced';
  }

  static componentMaterial(options: uiMaterial.ImmersiveOptions, level: string): uiMaterial.Material {
    return ImmersiveMaterialRuntime.reducedMaterial(level) ? uiMaterial.Material.empty :
      new uiMaterial.ImmersiveMaterial(options);
  }

  /** 弱档用实色表面；均衡用普通磨砂，不保留系统高档材质的折射和光边。 */
  static surfaceColor(level: string, darkMode: boolean, fallback: ResourceColor = ''): ResourceColor {
    if (level === 'weak') return fallback || ThemeRuntime.cardColor(darkMode);
    if (level === 'balanced') return darkMode ? '#D926272B' : '#D9F5F5F5';
    return Color.Transparent;
  }

  static surfaceBlur(level: string): BlurStyle {
    return level === 'balanced' ? BlurStyle.COMPONENT_THICK : BlurStyle.NONE;
  }

  /** 弱档没有原生材质光边，统一补一圈内描边；其它档位保留调用方原有边框。 */
  static surfaceBorder(level: string, darkMode: boolean,
    fallbackWidth: number = 0, fallbackColor: ResourceColor = Color.Transparent): ImmersiveSurfaceBorder {
    return level === 'weak' ? { width: 0.75, color: darkMode ? '#40FFFFFF' : '#26000000' } :
      { width: fallbackWidth, color: fallbackColor };
  }

  /** 原生材质的厚度；手动弱/均衡由 componentMaterial 关闭原生材质并使用普通表面。 */
  static materialStyle(configured: string = ImmersiveMaterialRuntime.configuredLightLevel()): uiMaterial.ImmersiveStyle {
    if (configured === 'high') return uiMaterial.ImmersiveStyle.ULTRA_THIN;
    return uiMaterial.ImmersiveStyle.REGULAR;
  }

  /**
   * Component-level immersive materials do not expose HDS MaterialLevel. Their
   * light-sense feedback is therefore mapped to the same app setting instead.
   * Undefined leaves the component-level light feedback unset, while null
   * disables it explicitly.
   */
  static lightEffect(forceAdaptive: boolean = false,
    configured: string = ImmersiveMaterialRuntime.configuredLightLevel(),
    color: string = '#FFFFFF'): uiMaterial.LightEffectOptions | null | undefined {
    if (configured === 'weak') return null;
    const rgb = /^#[0-9a-fA-F]{6}$/.test(color) ? color.substring(1) :
      (/^#[0-9a-fA-F]{8}$/.test(color) ? color.substring(3) : 'FFFFFF');
    if (configured === 'high') return { color: `#88${rgb}` };
    if (configured === 'balanced') return { color: `#55${rgb}` };
    // An undefined lightEffect means "do not enable light feedback" for a
    // component-level material. Stepper buttons opt in explicitly so the
    // default follow-system setting still provides the expected touch glow.
    if (forceAdaptive) return { color: `#55${rgb}` };
    return undefined;
  }

  /** The manually drawn touch glow follows the same strength as system material feedback. */
  static touchGlowOpacity(configured: string): number {
    if (configured === 'weak') return 0;
    return configured === 'high' ? 1 : 0.625;
  }

  /**
   * Shared dropdown material. Select menus otherwise inherit device-specific
   * shadows on API 26+, which makes identical controls look different across
   * pages. Older devices keep the platform fallback by returning undefined.
   */
  /** A fresh instance per build pass, so a changed light-sense setting is applied again. */
  static selectMenuModifier(lightLevel: string): SelectMenuMaterialModifier {
    return new SelectMenuMaterialModifier(lightLevel);
  }

  /**
   * 下拉弹出菜单（bindPopup）的沉浸光感材质：随光感档位的薄材质、带投影，光感取强调色。
   * API 26 以下返回 undefined，调用方退回磨砂底。
   */
  static popupMenuMaterial(accentColor: string,
    lightLevel: string = ImmersiveMaterialRuntime.configuredLightLevel()): uiMaterial.Material | undefined {
    if (!ImmersiveMaterialRuntime.supportsHds()) return undefined;
    return ImmersiveMaterialRuntime.componentMaterial({
      style: ImmersiveMaterialRuntime.materialStyle(lightLevel),
      applyShadow: true,
      interactive: false,
      lightEffect: ImmersiveMaterialRuntime.lightEffect(true, lightLevel, accentColor)
    }, lightLevel);
  }

  /** 操作菜单的最大高度：屏高的六成，条目多时在菜单里滚动。 */
  static popupMenuMaxHeight(): number {
    try {
      const screen = display.getDefaultDisplaySync();
      const density = screen.densityPixels > 0 ? screen.densityPixels : 1;
      return Math.max(240, Math.floor(screen.height / density * 0.6));
    } catch (error) {
      return 420;
    }
  }

  /**
   * 下拉菜单统一用系统弹出层：API 26+ 背景是沉浸光感材质，旧系统退回半透明磨砂；
   * 点菜单外自动收起，收起时回调让调用方复位开关。builder 用箭头函数传入，保证其中的 this 指向页面。
   */
  static popupMenuOptions(lightLevel: string, builder: CustomBuilder, placement: Placement, darkMode: boolean, accentColor: string,
    onHidden: () => void, focusable: boolean = true): CustomPopupOptions {
    const material = ImmersiveMaterialRuntime.popupMenuMaterial(accentColor, lightLevel);
    const options: CustomPopupOptions = {
      builder: builder,
      placement: placement,
      popupColor: ImmersiveMaterialRuntime.reducedMaterial(lightLevel) ?
        ImmersiveMaterialRuntime.surfaceColor(lightLevel, darkMode) :
        (material !== undefined ? Color.Transparent : ThemeRuntime.glassPanelColor(darkMode, '', 'panel')),
      radius: ImmersiveMaterialRuntime.POPUP_MENU_RADIUS,
      enableArrow: false,
      targetSpace: 8,
      // 跟着输入框弹出的面板传 false，免得抢走焦点收起键盘。
      focusable: focusable,
      onStateChange: (event) => {
        if (!event.isVisible) {
          onHidden();
        }
      }
    };
    if (material !== undefined) {
      options.systemMaterial = material;
      options.backgroundBlurStyle = ImmersiveMaterialRuntime.surfaceBlur(lightLevel);
    } else {
      options.backgroundBlurStyle = BlurStyle.COMPONENT_THICK;
    }
    if (lightLevel === 'weak' && deviceInfo.sdkApiVersion >= 20) {
      const border = ImmersiveMaterialRuntime.surfaceBorder(lightLevel, darkMode);
      options.borderWidth = border.width;
      options.borderLinearGradient = { colors: [[border.color, 0], [border.color, 1]] };
    }
    return options;
  }

  /**
   * 长按触发的系统菜单（bindContextMenu + ResponseType.LongPress）的选项：API 26+ 挂与弹出菜单同一种
   * 沉浸光感材质，旧系统用系统默认菜单底。由开关控制显隐的 bindContextMenu(isShown) 在真机上弹不出来，
   * 那类菜单改用 popupMenuOptions。
   */
  static contextMenuOptions(lightLevel: string, accentColor: string, onHidden: () => void): ContextMenuOptions {
    const options: ContextMenuOptions = {
      enableArrow: false,
      onDisappear: onHidden
    };
    if (lightLevel === 'weak' && deviceInfo.sdkApiVersion >= 20) {
      const border = ImmersiveMaterialRuntime.surfaceBorder(lightLevel, AppStorage.get<boolean>('appDarkMode') || false);
      options.outlineWidth = border.width;
      options.outlineColor = border.color;
    }
    const material = ImmersiveMaterialRuntime.popupMenuMaterial(accentColor, lightLevel);
    if (material !== undefined) {
      options.systemMaterial = material;
      if (ImmersiveMaterialRuntime.reducedMaterial(lightLevel)) {
        options.backgroundColor = ImmersiveMaterialRuntime.surfaceColor(lightLevel,
          AppStorage.get<boolean>('appDarkMode') || false);
        options.backgroundBlurStyle = ImmersiveMaterialRuntime.surfaceBlur(lightLevel);
      }
    }
    return options;
  }

  /**
   * 给半模态弹层挂沉浸光感材质：API 26+ 按应用档位设置，旧系统退回系统厚模糊加面板色。
   * 直接改传入的 options 并返回。
   */
  static applySheetMaterial(lightLevel: string, options: SheetOptions, darkMode: boolean, accentColor: string): SheetOptions {
    const border = ImmersiveMaterialRuntime.surfaceBorder(lightLevel, darkMode);
    options.borderWidth = border.width;
    options.borderColor = border.color;
    const material = ImmersiveMaterialRuntime.sheetMaterial(accentColor, lightLevel);
    if (material !== undefined) {
      options.backgroundColor = ImmersiveMaterialRuntime.surfaceColor(lightLevel, darkMode);
      options.blurStyle = ImmersiveMaterialRuntime.surfaceBlur(lightLevel);
      options.systemMaterial = material;
    } else {
      options.blurStyle = BlurStyle.COMPONENT_THICK;
      options.backgroundColor = ThemeRuntime.glassPanelColor(darkMode, '', 'panel');
    }
    return options;
  }

  /**
   * 半模态弹层（目录等）的沉浸光感材质：材质与光效均跟随应用档位，带投影，光感取强调色。
   * API 26 以下返回 undefined，调用方退回厚磨砂。
   */
  static sheetMaterial(accentColor: string,
    lightLevel: string = ImmersiveMaterialRuntime.configuredLightLevel()): uiMaterial.Material | undefined {
    if (!ImmersiveMaterialRuntime.supportsHds()) return undefined;
    return ImmersiveMaterialRuntime.componentMaterial({
      style: ImmersiveMaterialRuntime.materialStyle(lightLevel),
      applyShadow: true,
      interactive: false,
      lightEffect: ImmersiveMaterialRuntime.lightEffect(true, lightLevel, accentColor)
    }, lightLevel);
  }

  static selectMenuMaterial(lightLevel: string): uiMaterial.Material | undefined {
    if (!ImmersiveMaterialRuntime.supportsHds()) return undefined;
    return ImmersiveMaterialRuntime.componentMaterial({
      style: ImmersiveMaterialRuntime.materialStyle(lightLevel),
      materialColor: '#00000000',
      applyShadow: false,
      interactive: lightLevel !== 'weak',
      lightEffect: ImmersiveMaterialRuntime.lightEffect(false, lightLevel)
    }, lightLevel);
  }
}
