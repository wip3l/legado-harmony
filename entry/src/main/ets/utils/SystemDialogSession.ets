import { UIContext } from '@kit.ArkUI';

export interface SystemDialogOptions {
  /** 点蒙层/返回键是否直接关闭；蒙层带副作用的确认框应传 false，仅用按钮关闭。 */
  autoCancel: boolean;
  maskColor: string;
  warnTag: string;
}

/**
 * 系统自定义对话框（openCustomDialog）会话封装。对话框表面材质由系统渲染，
 * API 26+ 即沉浸光感效果，与“点数使用说明”弹窗保持同一形态。
 */
export class SystemDialogSession {
  private dialogId: number = -1;

  isOpen(): boolean {
    return this.dialogId >= 0;
  }

  /**
   * 打开对话框。autoCancel 对话框被蒙层/返回键关闭后，本会话记录的 id 会失效（stale），
   * 因此这里不做"已打开"拦截，重复调用以新 id 覆盖；蒙层会挡住用户操作，实际不会重复弹出。
   */
  open(uiContext: UIContext, builder: CustomBuilder, options: SystemDialogOptions): void {
    uiContext.getPromptAction().openCustomDialog({
      builder: builder,
      autoCancel: options.autoCancel,
      alignment: DialogAlignment.Center,
      maskColor: options.maskColor
    }).then((dialogId: number) => {
      this.dialogId = dialogId;
    }).catch((error: Error) => {
      console.warn(options.warnTag, error);
    });
  }

  close(uiContext: UIContext): void {
    if (this.dialogId < 0) return;
    const id = this.dialogId;
    this.dialogId = -1;
    // closeCustomDialog 在当前 SDK 中返回 void（同步执行），无需挂 .catch；
    // 对话框已被蒙层或返回键提前关闭时重复关闭是安全调用。
    uiContext.getPromptAction().closeCustomDialog(id);
  }
}
