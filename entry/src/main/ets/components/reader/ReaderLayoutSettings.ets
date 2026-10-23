import { ReaderFontWeight } from '../../core/reader/ReaderFontWeight';
import { ImmersiveMaterialRuntime } from '../../utils/ImmersiveMaterialRuntime';
import { ImmersiveBackButton } from '../ImmersiveBackButton';
import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { AdaptiveSwitch } from '../AdaptiveSwitch';
import { ReaderInfoBarConfig, ReaderInfoItem, ReaderInfoProgressBar } from '../../core/reader/ReaderInfoBarModel';
import { AppFontSize } from '../../theme/AppFontSize';
import { AppSpacing } from '../../theme/AppSpacing';

interface ReaderHeaderFooterSwitchOptions {
  title: string;
  description: string;
  checked: boolean;
  onChange: (checked: boolean) => void;
}

/** 排版参数在草稿数组里的下标。 */
export class ReaderTypographyField {
  static readonly FONT_SIZE: number = 0;
  static readonly FONT_WEIGHT: number = 1;
  static readonly LETTER_SPACING: number = 2;
  static readonly LINE_HEIGHT: number = 3;
  static readonly PARAGRAPH_SPACING: number = 4;
  static readonly MARGIN_LEFT: number = 5;
  static readonly MARGIN_RIGHT: number = 6;
  static readonly MARGIN_TOP: number = 7;
  static readonly MARGIN_BOTTOM: number = 8;
  static readonly COUNT: number = 9;

  static readonly LABELS: string[] = ['字号', '字体粗细', '字距', '行距', '段落间距', '左边距', '右边距', '上边距', '下边距'];

  static min(field: number): number {
    if (field === ReaderTypographyField.FONT_WEIGHT) return ReaderFontWeight.MIN;
    return field === ReaderTypographyField.FONT_SIZE ? 14 : 0;
  }

  static max(field: number): number {
    if (field === ReaderTypographyField.FONT_WEIGHT) return ReaderFontWeight.MAX;
    if (field === ReaderTypographyField.FONT_SIZE) return 50;
    if (field === ReaderTypographyField.LETTER_SPACING) return 8;
    if (field === ReaderTypographyField.LINE_HEIGHT) return 52;
    if (field === ReaderTypographyField.PARAGRAPH_SPACING) return 32;
    if (field === ReaderTypographyField.MARGIN_LEFT || field === ReaderTypographyField.MARGIN_RIGHT) return 80;
    return 120;
  }

  static step(field: number): number {
    return field === ReaderTypographyField.FONT_WEIGHT ? ReaderFontWeight.STEP : 1;
  }

  static clamp(field: number, value: number): number {
    if (field === ReaderTypographyField.FONT_WEIGHT) return ReaderFontWeight.normalize(value);
    return Math.max(ReaderTypographyField.min(field), Math.min(Math.round(value), ReaderTypographyField.max(field)));
  }
}

/**
 * 正文排版的统一调节控件：下拉选一个参数（字号、字体粗细、字距、行距、段距、四侧边距），用加减按钮或直接输入数值。
 * 数值草稿是组件自己的状态，连点加减只刷新这个控件；每次变化把整组草稿交给页面，
 * 页面稍后一次性提交并重排正文。
 */
@Component
export struct ReaderTypographyStepper {
  /** 打开时的初始值，顺序见 ReaderTypographyField。 */
  initialValues: number[] = [];
  @Prop dark: boolean = false;
  @Prop textColor: string = '#202124';
  @Prop subTextColor: string = '#80868B';
  @Prop accentColor: string = '#0A59F7';
  @Prop inputColor: string = '#FFFFFF';
  @Prop menuColor: string = '#FFFFFF';
  onChange: (values: number[]) => void = (_values: number[]): void => {
  };

  @State private field: number = 0;
  @State private values: number[] = [];
  @State private inputVisible: boolean = false;
  @State private inputDraft: string = '';

  aboutToAppear(): void {
    const values: number[] = [];
    for (let field = 0; field < ReaderTypographyField.COUNT; field++) {
      const fallback = field === ReaderTypographyField.FONT_WEIGHT ? ReaderFontWeight.DEFAULT :
        ReaderTypographyField.min(field);
      values.push(ReaderTypographyField.clamp(field,
        field < this.initialValues.length ? this.initialValues[field] : fallback));
    }
    this.values = values;
  }

  private current(): number {
    return this.field < this.values.length ? this.values[this.field] : 0;
  }

  private apply(value: number): void {
    const next = [...this.values];
    next[this.field] = ReaderTypographyField.clamp(this.field, value);
    this.values = next;
    this.onChange([...next]);
  }

  private applyInput(): void {
    if (!this.inputVisible) return;
    const value = Number(this.inputDraft);
    if (this.inputDraft.trim() && Number.isFinite(value)) this.apply(value);
    this.inputVisible = false;
  }

  build() {
    Row({ space: AppSpacing.MD }) {
      Select(ReaderTypographyField.LABELS.map((label: string): SelectOption => ({ value: label })))
        .id('reader_typography_selector')
        .selected(this.field)
        .value(ReaderTypographyField.LABELS[this.field])
        .font({ size: AppFontSize.BODY_LARGE })
        .fontColor(this.subTextColor)
        .backgroundColor(Color.Transparent)
        .arrowPosition(ArrowPosition.START)
        .padding({ left: 0, right: 0 })
        .borderRadius(16)
        .border({ width: 0 })
        .optionBgColor(Color.Transparent)
        .divider(null)
        .optionFontColor(this.textColor)
        .selectedOptionFontColor(this.accentColor)
        .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.dark))
        .menuBackgroundColor(this.menuColor)
        .menuBackgroundBlurStyle(BlurStyle.NONE)
        .attributeModifier(ImmersiveMaterialRuntime.selectMenuModifier())
        .onSelect((index: number) => {
          this.inputVisible = false;
          this.field = Math.max(0, Math.min(index, ReaderTypographyField.COUNT - 1));
        })
      Blank()
        .layoutWeight(1)
      this.stepButton($r('sys.symbol.minus'), '减小当前排版参数',
        this.current() > ReaderTypographyField.min(this.field), () => this.apply(this.current() - ReaderTypographyField.step(this.field)))
      if (this.inputVisible) {
        TextInput({ text: this.inputDraft, placeholder: `${this.current()}` })
          .type(InputType.Number)
          .enterKeyType(EnterKeyType.Done)
          .defaultFocus(true)
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.textColor)
          .width(52)
          .height(36)
          .padding(0)
          .textAlign(TextAlign.Center)
          .backgroundColor(this.inputColor)
          .borderRadius(ThemeRuntime.mediumRadius())
          .onChange((value: string) => {
            this.inputDraft = value.replace(/[^0-9]/g, '').substring(0, 3);
          })
          .onSubmit(() => this.applyInput())
          .onBlur(() => this.applyInput())
      } else {
        Text(`${Math.round(this.current())}`)
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(this.textColor)
          .width(52)
          .height(36)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.inputDraft = '';
            this.inputVisible = true;
          })
      }
      this.stepButton($r('sys.symbol.plus'), '增大当前排版参数',
        this.current() < ReaderTypographyField.max(this.field), () => this.apply(this.current() + ReaderTypographyField.step(this.field)))
    }
    .width('100%')
    // Keep the selector on the same content baseline as the settings below.
    .padding({ left: 0, right: 0, top: AppSpacing.LG, bottom: AppSpacing.LG })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  stepButton(icon: Resource, accessibilityText: string, enabled: boolean, action: () => void) {
    ImmersiveBackButton({
      icon: icon,
      accessibilityLabel: accessibilityText,
      iconColor: this.dark ? '#FFFFFFFF' : '#FF202124',
      disabledIconColor: this.subTextColor,
      darkMode: this.dark,
      buttonEnabled: enabled,
      buttonSize: 34,
      containerWidth: 34,
      containerHeight: 34,
      startInset: 0,
      compactLayout: true,
      onBack: action
    })
  }
}

/**
 * 页眉页脚设置组：两个总开关、六个内容槽位和外观项，直接绑定全局设置。
 * 操作回调直接提交完整设置；页面监听只负责更新正文，避免依赖跨组件监听的通知时机保存。
 * cardStyle 为 true 时使用设置页的卡片行样式。
 */
@Component
export struct ReaderHeaderFooterSettings {
  @Prop dark: boolean = false;
  @Prop textColor: string = '#202124';
  @Prop subTextColor: string = '#80868B';
  @Prop accentColor: string = '#0A59F7';
  @Prop switchColor: string = '#0A59F7';
  @Prop menuColor: string = '#FFFFFF';
  @Prop cardStyle: boolean = false;
  @Prop dividerColor: string = '#00000000';
  onChanged: (headerEnabled: boolean, footerEnabled: boolean, infoBarConfig: string) => void = () => {
  };
  @StorageLink('readerHeaderEnabled') readerHeaderEnabled: boolean = false;
  @StorageLink('readerFooterEnabled') readerFooterEnabled: boolean = true;
  @StorageLink('readerInfoBarConfig') readerInfoBarConfig: string = '';

  private static readonly SLOT_HEADER_LEFT: number = 0;
  private static readonly SLOT_HEADER_CENTER: number = 1;
  private static readonly SLOT_HEADER_RIGHT: number = 2;
  private static readonly SLOT_FOOTER_LEFT: number = 3;
  private static readonly SLOT_FOOTER_CENTER: number = 4;
  private static readonly SLOT_FOOTER_RIGHT: number = 5;
  private static readonly STEPPER_HEADER_FONT_SIZE: number = 0;
  private static readonly STEPPER_HEADER_OPACITY: number = 1;
  private static readonly STEPPER_HEADER_OFFSET: number = 2;
  private static readonly STEPPER_FOOTER_OFFSET: number = 3;
  private static readonly STEPPER_FOOTER_FONT_SIZE: number = 4;
  private static readonly STEPPER_FOOTER_OPACITY: number = 5;

  private config(): ReaderInfoBarConfig {
    return ReaderInfoBarConfig.parse(this.readerInfoBarConfig) ?? new ReaderInfoBarConfig();
  }

  private commit(config: ReaderInfoBarConfig): void {
    this.readerInfoBarConfig = config.serialize();
    this.notifyChanged();
  }

  private notifyChanged(): void {
    this.onChanged(this.readerHeaderEnabled, this.readerFooterEnabled, this.readerInfoBarConfig);
  }

  private slotIndex(slot: number): number {
    const config = this.config();
    let item = config.headerLeft;
    if (slot === ReaderHeaderFooterSettings.SLOT_HEADER_CENTER) item = config.headerCenter;
    if (slot === ReaderHeaderFooterSettings.SLOT_HEADER_RIGHT) item = config.headerRight;
    if (slot === ReaderHeaderFooterSettings.SLOT_FOOTER_LEFT) item = config.footerLeft;
    if (slot === ReaderHeaderFooterSettings.SLOT_FOOTER_CENTER) item = config.footerCenter;
    if (slot === ReaderHeaderFooterSettings.SLOT_FOOTER_RIGHT) item = config.footerRight;
    return Math.max(0, ReaderInfoItem.VALUES.indexOf(item));
  }

  private setSlot(slot: number, index: number): void {
    const item = index >= 0 && index < ReaderInfoItem.VALUES.length ? ReaderInfoItem.VALUES[index] : ReaderInfoItem.NONE;
    const config = this.config();
    if (slot === ReaderHeaderFooterSettings.SLOT_HEADER_LEFT) config.headerLeft = item;
    if (slot === ReaderHeaderFooterSettings.SLOT_HEADER_CENTER) config.headerCenter = item;
    if (slot === ReaderHeaderFooterSettings.SLOT_HEADER_RIGHT) config.headerRight = item;
    if (slot === ReaderHeaderFooterSettings.SLOT_FOOTER_LEFT) config.footerLeft = item;
    if (slot === ReaderHeaderFooterSettings.SLOT_FOOTER_CENTER) config.footerCenter = item;
    if (slot === ReaderHeaderFooterSettings.SLOT_FOOTER_RIGHT) config.footerRight = item;
    this.commit(config);
  }

  private stepperValue(field: number): number {
    const config = this.config();
    if (field === ReaderHeaderFooterSettings.STEPPER_HEADER_OFFSET) return config.headerOffset;
    if (field === ReaderHeaderFooterSettings.STEPPER_FOOTER_OFFSET) return config.footerOffset;
    if (field === ReaderHeaderFooterSettings.STEPPER_HEADER_OPACITY) return config.headerOpacity;
    if (field === ReaderHeaderFooterSettings.STEPPER_FOOTER_OPACITY) return config.footerOpacity;
    return field === ReaderHeaderFooterSettings.STEPPER_HEADER_FONT_SIZE ?
      config.headerFontSize : config.footerFontSize;
  }

  private isOffsetStepper(field: number): boolean {
    return field === ReaderHeaderFooterSettings.STEPPER_HEADER_OFFSET ||
      field === ReaderHeaderFooterSettings.STEPPER_FOOTER_OFFSET;
  }

  private stepperMin(field: number): number {
    if (this.isOffsetStepper(field)) return 0;
    return this.isOpacityStepper(field) ?
      ReaderInfoBarConfig.OPACITY_MIN : ReaderInfoBarConfig.FONT_SIZE_MIN;
  }

  private stepperMax(field: number): number {
    if (this.isOffsetStepper(field)) return ReaderInfoBarConfig.OFFSET_MAX;
    return this.isOpacityStepper(field) ?
      ReaderInfoBarConfig.OPACITY_MAX : ReaderInfoBarConfig.FONT_SIZE_MAX;
  }

  private isOpacityStepper(field: number): boolean {
    return field === ReaderHeaderFooterSettings.STEPPER_HEADER_OPACITY ||
      field === ReaderHeaderFooterSettings.STEPPER_FOOTER_OPACITY;
  }

  private stepperText(field: number): string {
    const value = this.stepperValue(field);
    return this.isOpacityStepper(field) ? `${value}%` : `${value}`;
  }

  private stepBy(field: number, direction: number): void {
    const config = this.config();
    if (field === ReaderHeaderFooterSettings.STEPPER_HEADER_OFFSET) {
      config.headerOffset = ReaderInfoBarConfig.clampOffset(
        config.headerOffset + direction * ReaderInfoBarConfig.OFFSET_STEP);
    } else if (field === ReaderHeaderFooterSettings.STEPPER_FOOTER_OFFSET) {
      config.footerOffset = ReaderInfoBarConfig.clampOffset(
        config.footerOffset + direction * ReaderInfoBarConfig.OFFSET_STEP);
    } else if (field === ReaderHeaderFooterSettings.STEPPER_HEADER_OPACITY) {
      config.headerOpacity = ReaderInfoBarConfig.clampOpacity(
        config.headerOpacity + direction * ReaderInfoBarConfig.OPACITY_STEP);
    } else if (field === ReaderHeaderFooterSettings.STEPPER_FOOTER_OPACITY) {
      config.footerOpacity = ReaderInfoBarConfig.clampOpacity(
        config.footerOpacity + direction * ReaderInfoBarConfig.OPACITY_STEP);
    } else if (field === ReaderHeaderFooterSettings.STEPPER_HEADER_FONT_SIZE) {
      config.headerFontSize = ReaderInfoBarConfig.clampFontSize(config.headerFontSize + direction);
    } else if (field === ReaderHeaderFooterSettings.STEPPER_FOOTER_FONT_SIZE) {
      config.footerFontSize = ReaderInfoBarConfig.clampFontSize(config.footerFontSize + direction);
    }
    this.commit(config);
  }

  build() {
    Column({ space: AppSpacing.XS }) {
      this.switchItem({ title: '显示页眉', description: '正文顶部显示书名、章节、时间等',
        checked: this.readerHeaderEnabled, onChange: (checked: boolean) => {
          this.readerHeaderEnabled = checked;
          this.notifyChanged();
        } })

      if (this.readerHeaderEnabled) {
        this.slotItem('页眉左侧', ReaderHeaderFooterSettings.SLOT_HEADER_LEFT, 'reader_header_left_select')
        this.slotItem('页眉中间', ReaderHeaderFooterSettings.SLOT_HEADER_CENTER, 'reader_header_center_select')
        this.slotItem('页眉右侧', ReaderHeaderFooterSettings.SLOT_HEADER_RIGHT, 'reader_header_right_select')
        this.stepperItem('页眉字号', ReaderHeaderFooterSettings.STEPPER_HEADER_FONT_SIZE)
        this.stepperItem('页眉不透明度', ReaderHeaderFooterSettings.STEPPER_HEADER_OPACITY)
        this.stepperItem('页眉下移', ReaderHeaderFooterSettings.STEPPER_HEADER_OFFSET)
        this.switchItem({ title: '页眉分隔线', description: '页眉下方的细线',
          checked: this.config().headerDivider, onChange: (checked: boolean) => {
            const config = this.config();
            config.headerDivider = checked;
            this.commit(config);
          }
        })
      }

      this.switchItem({ title: '显示页脚', description: '正文底部显示章节信息和进度',
        checked: this.readerFooterEnabled, onChange: (checked: boolean) => {
          this.readerFooterEnabled = checked;
          this.notifyChanged();
        } })

      if (this.readerFooterEnabled) {
        this.slotItem('页脚左侧', ReaderHeaderFooterSettings.SLOT_FOOTER_LEFT, 'reader_footer_left_select')
        this.slotItem('页脚中间', ReaderHeaderFooterSettings.SLOT_FOOTER_CENTER, 'reader_footer_center_select')
        this.slotItem('页脚右侧', ReaderHeaderFooterSettings.SLOT_FOOTER_RIGHT, 'reader_footer_right_select')
        this.stepperItem('页脚字号', ReaderHeaderFooterSettings.STEPPER_FOOTER_FONT_SIZE)
        this.stepperItem('页脚不透明度', ReaderHeaderFooterSettings.STEPPER_FOOTER_OPACITY)
        this.stepperItem('页脚上移', ReaderHeaderFooterSettings.STEPPER_FOOTER_OFFSET)
        this.switchItem({ title: '页脚分隔线', description: '页脚上方的细线',
          checked: this.config().footerDivider, onChange: (checked: boolean) => {
            const config = this.config();
            config.footerDivider = checked;
            this.commit(config);
          }
        })
      }

      if (this.readerHeaderEnabled || this.readerFooterEnabled) {
        this.switchItem({ title: '边距跟随正文', description: '页眉页脚的左右边距与正文一致',
          checked: this.config().followMargin, onChange: (checked: boolean) => {
            const config = this.config();
            config.followMargin = checked;
            this.commit(config);
          } })
        this.selectItem('进度条', '显示在页眉下方或页脚上方', ReaderInfoProgressBar.LABELS,
          Math.max(0, ReaderInfoProgressBar.VALUES.indexOf(this.config().progressBar)),
          (index: number) => {
            const config = this.config();
            config.progressBar = index >= 0 && index < ReaderInfoProgressBar.VALUES.length ?
              ReaderInfoProgressBar.VALUES[index] : ReaderInfoProgressBar.NONE;
            this.commit(config);
          }, 'reader_progress_bar_select')
        if (this.config().progressBar !== ReaderInfoProgressBar.NONE) {
          this.selectItem('进度条范围', '表示本章或全书的进度', ReaderInfoProgressBar.SCOPE_LABELS,
            Math.max(0, ReaderInfoProgressBar.SCOPE_VALUES.indexOf(this.config().progressScope)),
            (index: number) => {
              const config = this.config();
              config.progressScope = index === 1 ?
                ReaderInfoProgressBar.SCOPE_BOOK : ReaderInfoProgressBar.SCOPE_CHAPTER;
              this.commit(config);
            }, 'reader_progress_scope_select')
        }
      }
    }
    .width('100%')
    .padding({ bottom: this.cardStyle ? 0 : 8 })
  }

  @Builder
  itemLabel(title: string, description: string) {
    Column() {
      Text(title)
        .fontSize(this.cardStyle ? 16 : 15)
        .fontColor(this.textColor)
      if (description) {
        Text(description)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor)
          .margin({ top: AppSpacing.XS })
      }
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  switchItem($$: ReaderHeaderFooterSwitchOptions) {
    Row() {
      this.itemLabel($$.title, $$.description)
      AdaptiveSwitch({
        isOn: $$.checked,
        selectedColor: this.switchColor,
        onChange: (value: boolean) => $$.onChange(value)
      })
    }
    .width(this.cardStyle ? 'calc(100% - 32vp)' : '100%')
    .constraintSize({ minHeight: this.cardStyle ? 64 : 56 })
    .padding({ top: this.cardStyle ? 10 : 0, bottom: this.cardStyle ? 10 : 0 })
    .margin({ left: this.cardStyle ? 16 : 0, right: this.cardStyle ? 16 : 0 })
    .border({ width: { bottom: this.cardStyle ? 0.5 : 0 }, color: this.dividerColor })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  slotItem(title: string, slot: number, controlId: string) {
    this.selectItem(title, '', ReaderInfoItem.LABELS, this.slotIndex(slot), (index: number) => {
      this.setSlot(slot, index);
    }, controlId)
  }

  @Builder
  selectItem(title: string, description: string, labels: string[], selected: number,
    onSelect: (index: number) => void, controlId: string) {
    Row() {
      this.itemLabel(title, description)
      Select(labels.map((label: string): SelectOption => ({ value: label })))
        .id(controlId)
        .selected(selected)
        .value(selected >= 0 && selected < labels.length ? labels[selected] : (labels.length > 0 ? labels[0] : ''))
        .font({ size: AppFontSize.BODY })
        .fontColor(this.subTextColor)
        .backgroundColor(Color.Transparent)
        .arrowPosition(ArrowPosition.END)
        .padding({ left: 0, right: 0 })
        // Keep the hit area rectangular, but soften its corners to match the rounded settings cards.
        .borderRadius(16)
        .border({ width: 0 })
        .optionBgColor(Color.Transparent)
        .divider(null)
        .optionFontColor(this.textColor)
        .selectedOptionFontColor(this.accentColor)
        .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.dark))
        .menuBackgroundColor(this.menuColor)
        .menuBackgroundBlurStyle(BlurStyle.NONE)
        .attributeModifier(ImmersiveMaterialRuntime.selectMenuModifier())
        .onSelect((index: number) => onSelect(index))
    }
    .width(this.cardStyle ? 'calc(100% - 32vp)' : '100%')
    .constraintSize({ minHeight: description ? (this.cardStyle ? 64 : 56) : (this.cardStyle ? 52 : 44) })
    .padding({ top: this.cardStyle && !!description ? 10 : 0, bottom: this.cardStyle && !!description ? 10 : 0 })
    .margin({ left: this.cardStyle ? 16 : 0, right: this.cardStyle ? 16 : 0 })
    .border({ width: { bottom: this.cardStyle ? 0.5 : 0 }, color: this.dividerColor })
    .alignItems(VerticalAlign.Center)
  }

  // 数值直接从配置读取而不是经参数传入，保证点击加减后文字立即刷新。
  @Builder
  stepperItem(title: string, field: number) {
    Row({ space: AppSpacing.MD }) {
      this.itemLabel(title, '')
      this.stepperButton($r('sys.symbol.minus'), `减小${title}`, field, -1)
      Text(this.stepperText(field))
        .fontSize(AppFontSize.BODY_LARGE)
        .fontColor(this.textColor)
        .width(52)
        .textAlign(TextAlign.Center)
      this.stepperButton($r('sys.symbol.plus'), `增大${title}`, field, 1)
    }
    .width(this.cardStyle ? 'calc(100% - 32vp)' : '100%')
    .constraintSize({ minHeight: this.cardStyle ? 52 : 44 })
    .margin({ left: this.cardStyle ? 16 : 0, right: this.cardStyle ? 16 : 0 })
    .border({ width: { bottom: this.cardStyle ? 0.5 : 0 }, color: this.dividerColor })
    .alignItems(VerticalAlign.Center)
  }

  private canStep(field: number, direction: number): boolean {
    return direction < 0 ? this.stepperValue(field) > this.stepperMin(field) :
      this.stepperValue(field) < this.stepperMax(field);
  }

  // 可用状态在这里直接从配置读取。按值传进来的布尔参数不会随配置刷新：初始值在下限的项
  // （页眉下移、页脚上移从 0 开始）减号一开始是禁用的，数值增加后也不会恢复可用。
  @Builder
  stepperButton(icon: Resource, accessibilityText: string, field: number, direction: number) {
    ImmersiveBackButton({
      icon: icon,
      accessibilityLabel: accessibilityText,
      iconColor: this.dark ? '#FFFFFFFF' : '#FF202124',
      disabledIconColor: this.subTextColor,
      darkMode: this.dark,
      buttonEnabled: this.canStep(field, direction),
      buttonSize: 34,
      containerWidth: 34,
      containerHeight: 34,
      startInset: 0,
      compactLayout: true,
      onBack: (): void => this.stepBy(field, direction)
    })
  }
}
