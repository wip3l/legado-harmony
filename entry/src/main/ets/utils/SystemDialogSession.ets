import { UIContext, promptAction } from '@kit.ArkUI';
import { ImmersiveMaterialRuntime } from './ImmersiveMaterialRuntime';

export interface SystemDialogOptions {
  /** 点蒙层/返回键是否直接关闭；蒙层带副作用的确认框应传 false，仅用按钮关闭。 */
  autoCancel: boolean;
  maskColor: string;
  warnTag: string;
  /** 弹窗以任何方式关闭（含蒙层/返回键自动关闭）后的回调，用于复位页面侧标志位。 */
  onDismiss?: () => void;
}

/**
 * 系统自定义对话框（openCustomDialog）会话封装。对话框表面材质由系统渲染，
 * API 26+ 即沉浸光感效果，与“点数使用说明”弹窗保持同一形态。
 */
export class SystemDialogSession {
  private dialogId: number = -1;
  /** 页面最后一次要求的状态；打开是异步的，id 回来前页面可能已经要求关闭。 */
  private wanted: boolean = false;

  isOpen(): boolean {
    return this.dialogId >= 0 || this.wanted;
  }

  /**
   * 打开对话框。autoCancel 对话框被蒙层/返回键关闭后，本会话记录的 id 会失效（stale），
   * 因此这里不做"已打开"拦截，重复调用以新 id 覆盖；蒙层会挡住用户操作，实际不会重复弹出。
   */
  open(uiContext: UIContext, builder: CustomBuilder, options: SystemDialogOptions): void {
    this.wanted = true;
    const dialogOptions: promptAction.CustomDialogOptions = {
      builder: builder,
      autoCancel: options.autoCancel,
      alignment: DialogAlignment.Center,
      maskColor: options.maskColor,
      // 注册了这个回调后蒙层/返回键不会自动关闭，autoCancel 的对话框要在这里放行。
      onWillDismiss: (action: DismissDialogAction): void => {
        if (!options.autoCancel) return;
        this.wanted = false;
        this.dialogId = -1;
        action.dismiss();
        if (options.onDismiss) options.onDismiss();
      }
    };
    const material = ImmersiveMaterialRuntime.sheetMaterial('#FFFFFF');
    if (material !== undefined) {
      dialogOptions.systemMaterial = material;
      const level = ImmersiveMaterialRuntime.configuredLightLevel();
      dialogOptions.backgroundColor = ImmersiveMaterialRuntime.surfaceColor(level,
        AppStorage.get<boolean>('appDarkMode') || false);
      dialogOptions.backgroundBlurStyle = ImmersiveMaterialRuntime.surfaceBlur(level);
      const border = ImmersiveMaterialRuntime.surfaceBorder(level, AppStorage.get<boolean>('appDarkMode') || false);
      dialogOptions.borderWidth = border.width;
      dialogOptions.borderColor = border.color;
    }
    uiContext.getPromptAction().openCustomDialog(dialogOptions).then((dialogId: number) => {
      this.dialogId = dialogId;
      if (!this.wanted) this.close(uiContext);
    }).catch((error: Error) => {
      this.wanted = false;
      console.warn(options.warnTag, error);
    });
  }

  /**
   * 跟随页面开关：开关打开时弹出、关上时关闭，供原先用布尔开关控制的浮层直接换成系统对话框。
   * 蒙层/返回键关闭时经 options.onDismiss 让页面复位开关。
   */
  sync(uiContext: UIContext, shown: boolean, builder: CustomBuilder, options: SystemDialogOptions): void {
    if (shown && !this.isOpen()) {
      this.open(uiContext, builder, options);
    } else if (!shown && this.isOpen()) {
      this.close(uiContext);
    }
  }

  close(uiContext: UIContext): void {
    this.wanted = false;
    if (this.dialogId < 0) return;
    const id = this.dialogId;
    this.dialogId = -1;
    // closeCustomDialog 在当前 SDK 中返回 void（同步执行），无需挂 .catch；
    // 对话框已被蒙层或返回键提前关闭时重复关闭是安全调用。
    uiContext.getPromptAction().closeCustomDialog(id);
  }
}
