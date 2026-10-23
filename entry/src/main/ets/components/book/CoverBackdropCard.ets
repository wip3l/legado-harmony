/**
 * 带模糊封面背景的卡片：封面按极低分辨率解码后拉伸铺满，得到模糊效果而不做实时模糊；
 * 最底层垫淡淡的主题色斜向渐变（封面没加载出来时露出），最上层盖半透明卡片色保证文字可读。
 *
 * 背景作为组件内的普通子组件，封面地址是属性，异步换成本地缓存路径后会跟着重绘
 * （用 background 属性挂背景时只在创建时绘制一次，换路径后会停在旧地址上）。
 * 背景高度取内容实测高度，不用百分比：列表项里百分比高度会按列表可视高度计算而撑满整屏。
 *
 * 内容用尾随闭包传入：CoverBackdropCard({ cover: ..., ... }) { Row() { ... } }
 */
@Component
export struct CoverBackdropCard {
  @Prop cover: ResourceStr = '';
  @Prop showBackdrop: boolean = true;
  @Prop accentColor: string = '#007DFF';
  /** 卡片底色，遮罩在它的基础上加透明度。 */
  @Prop cardColor: string = '#FFFFFF';
  @Prop darkMode: boolean = false;
  @State contentHeight: number = 0;
  @BuilderParam content: () => void = this.emptyContent;

  @Builder
  emptyContent() {
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.showBackdrop && this.contentHeight > 0) {
        Stack() {
          Column()
            .width('100%')
            .height('100%')
            .linearGradient({
              angle: 135,
              colors: [
                [this.accentWithAlpha(this.darkMode ? '80' : '66'), 0],
                [this.accentWithAlpha(this.darkMode ? '33' : '1F'), 0.55],
                [this.accentWithAlpha('00'), 1]
              ]
            })
          if (this.cover) {
            Image(this.cover)
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Cover)
              .sourceSize({ width: 12, height: 16 })
              .interpolation(ImageInterpolation.High)
          }
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor(this.scrimColor())
        }
        .width('100%')
        .height(this.contentHeight)
        .hitTestBehavior(HitTestMode.None)
      }

      Column() {
        this.content()
      }
      .width('100%')
      .onAreaChange((_oldValue: Area, newValue: Area) => {
        const height = Math.round(Number(newValue.height));
        if (Number.isFinite(height) && height > 0 && height !== this.contentHeight) {
          this.contentHeight = height;
        }
      })
    }
    .width('100%')
    .backgroundColor(this.cardColor)
  }

  private accentWithAlpha(alpha: string): string {
    return /^#[0-9A-Fa-f]{6}$/.test(this.accentColor) ? `#${alpha}${this.accentColor.substring(1)}` : this.accentColor;
  }

  private scrimColor(): string {
    const card = /^#[0-9A-Fa-f]{6}$/.test(this.cardColor) ? this.cardColor : (this.darkMode ? '#191B1F' : '#FFFFFF');
    // 遮罩更实一些，封面只透出一层淡淡的颜色，避免行背景偏深。
    return `${this.darkMode ? '#D4' : '#CF'}${card.substring(1)}`;
  }
}
