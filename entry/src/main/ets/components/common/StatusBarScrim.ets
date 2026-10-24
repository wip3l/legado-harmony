import { CollapsingHeader } from '../../utils/CollapsingHeader';

/**
 * 顶栏收起后衬在状态栏下面的渐变遮罩：页面底色铺满状态栏上半段，到状态栏下沿外再渐隐
 * CollapsingHeader.SCRIM_FADE_HEIGHT，滚上来的封面、卡片不会和系统图标叠在一起，也没有硬边。
 * 只负责绘制、不接收触摸；页面按收起量用 CollapsingHeader.scrimOpacity 算出 scrimOpacity，
 * 放在滚动内容之上、顶栏内容之下。
 */
@Component
export struct StatusBarScrim {
  @Prop statusBarHeight: number = 0;
  /** `#RRGGBB` 页面底色。 */
  @Prop pageColor: string = '#FFFFFF';
  @Prop scrimOpacity: number = 0;

  build() {
    Column()
      .width('100%')
      .height(this.statusBarHeight + CollapsingHeader.SCRIM_FADE_HEIGHT)
      .linearGradient({ direction: GradientDirection.Bottom, colors: this.gradientColors() })
      .opacity(this.scrimOpacity)
      .visibility(this.scrimOpacity > 0 && this.statusBarHeight > 0 ? Visibility.Visible : Visibility.Hidden)
      .hitTestBehavior(HitTestMode.None)
      .accessibilityLevel('no')
  }

  gradientColors(): Array<[ResourceColor, number]> {
    const total = this.statusBarHeight + CollapsingHeader.SCRIM_FADE_HEIGHT;
    const rgb = this.pageColor.substring(1);
    return [
      [this.pageColor, 0],
      // 系统图标所在的上半段保持实色，到状态栏下沿只剩少许透出。
      [this.pageColor, this.statusBarHeight * 0.5 / total],
      [`#D9${rgb}`, this.statusBarHeight / total],
      [`#00${rgb}`, 1]
    ];
  }
}
