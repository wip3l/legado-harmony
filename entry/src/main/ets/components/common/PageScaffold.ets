import { router } from '@kit.ArkUI';
import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { AppFontSize } from '../../theme/AppFontSize';
import { ImmersiveBackButton } from '../ImmersiveBackButton';
import { CollapsingHeader } from '../../utils/CollapsingHeader';
import { StatusBarScrim } from './StatusBarScrim';

/**
 * 二级页面的统一骨架：页面底色、沉浸式顶栏（返回、标题、右侧操作）和状态栏/导航条的留白。
 *
 * 内容和右侧操作都用箭头函数传入，保证其中的 this 仍指向页面：
 *   PageScaffold({ title: '其他设置', content: () => { this.pageContent() } })
 *
 * scrollable 为 true 时内容放进带回弹的滚动容器；页面自己用 List 等滚动时传 false，
 * 此时骨架只负责顶部留白，底部留白由页面处理。
 * 列表要从顶栏下方滚过去时再加 edgeToEdge: true，内容铺满整页，上下留白都由页面自己放进列表里。
 * 顶栏默认随内容上滑跟手收起、下滑展开，与首页大标题一致；scrollable 为 false 的页面自己跟踪滚动，
 * 用 CollapsingHeader 算出收起量传给 externalCollapse。不需要收起的页面传 collapsible: false。
 */
@Component
export struct PageScaffold {
  /** 顶栏内容区高度，不含状态栏。 */
  static readonly BAR_HEIGHT: number = 56;

  @Prop title: string = '';
  @Prop scrollable: boolean = true;
  /** 仅在 scrollable 为 false 时有效：内容铺满整页，不留顶栏的位置。 */
  @Prop edgeToEdge: boolean = false;
  /** 滚动内容底部在导航条之上额外留出的高度。 */
  @Prop bottomInset: number = 32;
  @Prop collapsible: boolean = true;
  @Prop externalCollapse: number = 0;
  @State headerCollapse: number = 0;
  private scroller: Scroller = new Scroller();
  @StorageProp('appDarkMode') appDarkMode: boolean = false;
  @StorageProp('themeRevision') themeRevision: number = 0;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  onBack: () => void = () => {
    router.back();
  };
  @BuilderParam content: () => void = this.emptySlot;
  @BuilderParam actions: () => void = this.emptySlot;

  @Builder
  emptySlot() {
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.scrollable) {
        Scroll(this.scroller) {
          Column() {
            this.content()
          }
          .width('100%')
          .padding({
            top: PageScaffold.BAR_HEIGHT + this.statusBarHeight,
            bottom: this.bottomInset + this.navBarHeight
          })
        }
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .width('100%')
        .height('100%')
        .align(Alignment.TopStart)
        .onDidScroll((_xOffset: number, yOffset: number) => {
          if (!this.collapsible) return;
          this.headerCollapse = CollapsingHeader.next(this.headerCollapse, yOffset,
            this.scroller.currentOffset().yOffset);
        })
        .onScrollStop(() => {
          if (!this.collapsible) return;
          const target = CollapsingHeader.settle(this.headerCollapse, this.scroller.currentOffset().yOffset);
          if (target !== this.headerCollapse) {
            animateTo({ duration: 200, curve: Curve.FastOutSlowIn }, () => {
              this.headerCollapse = target;
            });
          }
        })
      } else {
        Column() {
          this.content()
        }
        .width('100%')
        .height('100%')
        .padding({ top: this.edgeToEdge ? 0 : PageScaffold.BAR_HEIGHT + this.statusBarHeight - this.collapseAmount() })
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      }

      if (this.collapsible) {
        // 只有内容会滚进状态栏时才需要遮罩；普通 List 页的内容区本来就从状态栏下面开始。
        if (this.scrollable || this.edgeToEdge) {
          StatusBarScrim({ statusBarHeight: this.statusBarHeight, pageColor: ThemeRuntime.pageColor(this.appDarkMode),
            scrimOpacity: CollapsingHeader.scrimOpacity(this.collapseAmount()) })
            .width('100%')
        }
        Column() {
          this.titleBar()
        }
        .width('100%')
        .height(PageScaffold.BAR_HEIGHT + this.statusBarHeight - this.collapseAmount())
        // 保持顶栏透明，让返回按钮的沉浸光感材质采样下方滚动内容。
        .backgroundColor(Color.Transparent)
        .clip(true)
        .opacity(CollapsingHeader.contentOpacity(this.collapseAmount()))
        .hitTestBehavior(CollapsingHeader.acceptsTouch(this.collapseAmount()) ? HitTestMode.Default : HitTestMode.None)
      } else {
        this.titleBar()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeRuntime.pageColor(this.appDarkMode))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  collapseAmount(): number {
    if (!this.collapsible) return 0;
    return this.scrollable ? this.headerCollapse : Math.max(0, Math.min(CollapsingHeader.DISTANCE, this.externalCollapse));
  }

  @Builder
  titleBar() {
    Row() {
      ImmersiveBackButton({ iconColor: ThemeRuntime.primaryTextColor(this.appDarkMode), darkMode: this.appDarkMode,
        buttonSize: 40, containerWidth: 56, materialScale: 0.83, compactLayout: true,
        onBack: () => this.onBack() })
      Text(this.title)
        .fontSize(AppFontSize.TITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeRuntime.primaryTextColor(this.appDarkMode))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      this.actions()
    }
    .width('100%')
    .height(PageScaffold.BAR_HEIGHT + this.statusBarHeight)
    .padding({ top: this.statusBarHeight })
    .alignItems(VerticalAlign.Center)
  }
}
