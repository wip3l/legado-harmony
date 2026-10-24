import { AdaptiveSwitch } from '../AdaptiveSwitch';
import { AppFontSize } from '../../theme/AppFontSize';
import { AppSpacing } from '../../theme/AppSpacing';
import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { ThemePackageLimits } from '../../theme/share/ThemePackageFormat';
import {
  ThemeExportFontInfo,
  ThemeExportOptions,
  ThemeExportPlan,
  ThemeImportPreview
} from '../../theme/share/ThemePackageService';
import { CustomThemeScheme } from '../../utils/CustomThemeSchemeStore';

function formatBytes(bytes: number): string {
  if (bytes >= 1024 * 1024) return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
  if (bytes >= 1024) return `${Math.max(1, Math.round(bytes / 1024))} KB`;
  return `${bytes} B`;
}

/** 署名在主题详情右下角的样式，导出面板预览和详情页共用。 */
export function themeAuthorLine(author: string): string {
  return `author by ${author}`;
}

@Component
struct ThemeShareToggleRow {
  @Prop title: string = '';
  @Prop detail: string = '';
  @Prop isOn: boolean = false;
  @Prop rowEnabled: boolean = true;
  @Prop darkMode: boolean = false;
  onChange: (isOn: boolean) => void = (_isOn: boolean) => {};

  build() {
    Row({ space: AppSpacing.LG }) {
      Column({ space: AppSpacing.XXS }) {
        Text(this.title)
          .fontSize(AppFontSize.BODY_LARGE)
          .fontColor(ThemeRuntime.primaryTextColor(this.darkMode))
        Text(this.detail)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(ThemeRuntime.subTextColor(this.darkMode))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      AdaptiveSwitch({
        isOn: this.isOn,
        switchEnabled: this.rowEnabled,
        accessibilityLabel: this.title,
        onChange: (isOn: boolean) => this.onChange(isOn)
      })
    }
    .width('100%')
    .opacity(this.rowEnabled ? 1 : 0.5)
  }
}

@Component
struct ThemeShareNotice {
  @Prop title: string = '';
  @Prop items: string[] = [];
  @Prop danger: boolean = false;
  @Prop darkMode: boolean = false;

  build() {
    Column({ space: AppSpacing.XXS }) {
      Text(this.title)
        .fontSize(AppFontSize.CAPTION)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.danger ? ThemeRuntime.dangerColor(this.darkMode) : ThemeRuntime.primaryTextColor(this.darkMode))
      ForEach(this.items, (item: string) => {
        Text(`· ${item}`)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(ThemeRuntime.subTextColor(this.darkMode))
      }, (item: string, index: number) => `${index}_${item}`)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(AppSpacing.MD)
    .borderRadius(ThemeRuntime.mediumRadius())
    .backgroundColor(ThemeRuntime.inputColor(this.darkMode))
  }
}

@Component
struct ShareDialogSurface {
  @Prop darkMode: boolean = false;
  @BuilderParam content: () => void;

  build() {
    Column() {
      this.content()
    }
    .width('100%')
    .padding(AppSpacing.XXL)
  }
}

@Builder
function shareDialogTitle(title: string, darkMode: boolean) {
  Row({ space: AppSpacing.SM }) {
    Text(title)
      .fontSize(AppFontSize.SUBTITLE)
      .fontWeight(FontWeight.Bold)
      .fontColor(ThemeRuntime.primaryTextColor(darkMode))
    Text('Beta')
      .fontSize(AppFontSize.MICRO)
      .fontColor(ThemeRuntime.accentColor(darkMode))
      .padding({ left: AppSpacing.SM, right: AppSpacing.SM, top: 2, bottom: 2 })
      .borderRadius(8)
      .backgroundColor(ThemeRuntime.inputColor(darkMode))
  }
  .width('100%')
  .alignItems(VerticalAlign.Center)
}

/** 导出主题包：选择附带内容和署名，然后保存到文件或直接分享。 */
@Component
export struct ThemeExportDialog {
  @Prop darkMode: boolean = false;
  plan: ThemeExportPlan = new ThemeExportPlan();
  onClose: () => void = () => {};
  onExport: (options: ThemeExportOptions, share: boolean) => Promise<void> =
    (_options: ThemeExportOptions, _share: boolean): Promise<void> => Promise.resolve();
  @State includeAuthor: boolean = false;
  @State authorName: string = '';
  @State includeRules: boolean = false;
  @State includeFonts: boolean = false;
  @State busy: boolean = false;

  aboutToAppear(): void {
    // 首次导出默认不署名；导入的方案再导出时沿用原署名，可以关掉。
    this.authorName = this.plan.author;
    this.includeAuthor = !!this.plan.author;
    this.includeRules = this.plan.ruleCount > 0;
    this.includeFonts = this.hasAvailableFonts();
  }

  /** 随当前选项会打包的字体：只被强调规则用到的，不附带规则时不算。 */
  selectedFonts(): ThemeExportFontInfo[] {
    return this.plan.fonts.filter((font: ThemeExportFontInfo): boolean => this.includeRules || !font.ruleOnly);
  }

  missingFonts(): string[] {
    return this.selectedFonts().filter((font: ThemeExportFontInfo): boolean => !font.available)
      .map((font: ThemeExportFontInfo): string => font.name);
  }

  hasAvailableFonts(): boolean {
    return this.selectedFonts().some((font: ThemeExportFontInfo): boolean => font.available);
  }

  fontBytes(): number {
    let total = 0;
    for (const font of this.selectedFonts()) total += font.size;
    return total;
  }

  fontDetail(): string {
    const fonts = this.selectedFonts();
    if (fonts.length === 0) return '这套方案没有使用自定义字体';
    const names = fonts.map((font: ThemeExportFontInfo): string => `${font.name}（${font.usage}）`).join('、');
    return `${names} · ${formatBytes(this.fontBytes())}。只打包这套方案正在用的字体，请确认字体允许分享`;
  }

  estimatedBytes(): number {
    return this.plan.imageBytes + (this.includeFonts ? this.fontBytes() : 0) + 8 * 1024;
  }

  canExport(): boolean {
    return !this.busy && this.plan.missingImages.length === 0 &&
      (!this.includeAuthor || !!this.authorName.trim());
  }

  async run(share: boolean): Promise<void> {
    if (!this.canExport()) return;
    const options = new ThemeExportOptions();
    options.includeAuthor = this.includeAuthor;
    options.authorName = this.authorName;
    options.includeRules = this.includeRules;
    options.includeFonts = this.includeFonts;
    this.busy = true;
    try {
      await this.onExport(options, share);
    } finally {
      this.busy = false;
    }
  }

  build() {
    ShareDialogSurface({ darkMode: this.darkMode }) {
      this.content()
    }
  }

  @Builder
  content() {
    Scroll() {
      Column({ space: AppSpacing.LG }) {
        shareDialogTitle('导出主题包', this.darkMode)
        Text(`「${this.plan.name}」的配色、部件、排版（含页眉页脚与缩进）和上传的图片会打包为 .qytheme 文件，` +
          `会员可在其他设备导入。`)
          .fontSize(AppFontSize.BODY)
          .fontColor(ThemeRuntime.subTextColor(this.darkMode))
          .width('100%')
        if (this.plan.missingImages.length > 0) {
          ThemeShareNotice({
            title: '以下图片已丢失，请在编辑主题里重新上传后再导出',
            items: this.plan.missingImages,
            danger: true,
            darkMode: this.darkMode
          })
        }
        ThemeShareToggleRow({
          title: '附带强调规则',
          detail: this.plan.ruleCount > 0 ? `这套方案的 ${this.plan.ruleCount} 条正文强调规则` : '这套方案没有强调规则',
          isOn: this.includeRules,
          rowEnabled: this.plan.ruleCount > 0,
          darkMode: this.darkMode,
          onChange: (isOn: boolean) => {
            this.includeRules = isOn;
          }
        })
        ThemeShareToggleRow({
          title: '附带字体文件',
          detail: this.fontDetail(),
          isOn: this.includeFonts,
          rowEnabled: this.hasAvailableFonts(),
          darkMode: this.darkMode,
          onChange: (isOn: boolean) => {
            this.includeFonts = isOn;
          }
        })
        if (this.missingFonts().length > 0) {
          ThemeShareNotice({
            title: '以下字体文件已丢失，导入方会改用全局字体',
            items: this.missingFonts(),
            darkMode: this.darkMode
          })
        }
        ThemeShareToggleRow({
          title: '包含作者信息',
          detail: '导入后在主题详情右下角显示署名',
          isOn: this.includeAuthor,
          darkMode: this.darkMode,
          onChange: (isOn: boolean) => {
            this.includeAuthor = isOn;
          }
        })
        if (this.includeAuthor) {
          TextInput({ placeholder: '作者名称或笔名', text: this.authorName })
            .width('100%')
            .height(40)
            .maxLength(ThemePackageLimits.MAX_AUTHOR_LENGTH)
            .fontColor(ThemeRuntime.primaryTextColor(this.darkMode))
            .placeholderColor(ThemeRuntime.subTextColor(this.darkMode))
            .backgroundColor(ThemeRuntime.inputColor(this.darkMode))
            .borderRadius(ThemeRuntime.mediumRadius())
            .onChange((value: string) => {
              this.authorName = value;
            })
          if (this.authorName.trim()) {
            Text(themeAuthorLine(this.authorName.trim()))
              .fontSize(AppFontSize.CAPTION)
              .fontColor(ThemeRuntime.subTextColor(this.darkMode))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .textAlign(TextAlign.End)
          }
        }
        Text(`图片 ${this.plan.imageCount} 张 · 预计 ${formatBytes(this.estimatedBytes())}`)
          .fontSize(AppFontSize.CAPTION)
          .fontColor(ThemeRuntime.subTextColor(this.darkMode))
          .width('100%')
        Row({ space: AppSpacing.MD }) {
          Button('取消', { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(42)
            .borderRadius(ThemeRuntime.buttonRadius())
            .backgroundColor(ThemeRuntime.cardColor(this.darkMode))
            .fontColor(ThemeRuntime.primaryTextColor(this.darkMode))
            .enabled(!this.busy)
            .onClick(() => this.onClose())
          Button('保存到文件', { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(42)
            .borderRadius(ThemeRuntime.buttonRadius())
            .backgroundColor(ThemeRuntime.inputColor(this.darkMode))
            .fontColor(ThemeRuntime.accentColor(this.darkMode))
            .enabled(this.canExport())
            .onClick(() => this.run(false))
          Button(this.busy ? '处理中' : '分享', { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(42)
            .borderRadius(ThemeRuntime.buttonRadius())
            .backgroundColor(ThemeRuntime.accentColor(this.darkMode))
            .fontColor(ThemeRuntime.onAccentColor(ThemeRuntime.accentColor(this.darkMode)))
            .enabled(this.canExport())
            .onClick(() => this.run(true))
        }
        .width('100%')
      }
      .width('100%')
    }
    .scrollBar(BarState.Off)
    .constraintSize({ maxHeight: '80%' })
  }
}

/** 导入主题包：展示包里有什么、哪些部件会被替换，额度已满时选择替换哪一套。 */
@Component
export struct ThemeImportDialog {
  @Prop darkMode: boolean = false;
  preview: ThemeImportPreview = new ThemeImportPreview();
  schemes: CustomThemeScheme[] = [];
  limit: number = 5;
  activeSchemeId: string = '';
  onClose: () => void = () => {};
  onImport: (replaceSchemeId: string) => Promise<void> = (_id: string): Promise<void> => Promise.resolve();
  @State replaceSchemeId: string = '';
  @State busy: boolean = false;

  isFull(): boolean {
    return this.schemes.length >= this.limit;
  }

  replaceable(): CustomThemeScheme[] {
    return this.schemes.filter((scheme: CustomThemeScheme): boolean => scheme.id !== this.activeSchemeId);
  }

  contentSummary(): string[] {
    const items: string[] = [];
    if (this.preview.hasLayout) items.push('方案排版（正文、标题、缩进、页眉页脚）');
    if (this.preview.imageCount > 0) items.push(`图片 ${this.preview.imageCount} 张`);
    if (this.preview.ruleCount > 0) items.push(`强调规则 ${this.preview.ruleCount} 条，追加在你原有规则之后`);
    if (this.preview.bundledFontCount > 0) items.push(`字体 ${this.preview.bundledFontCount} 款，加入你的字体库`);
    return items;
  }

  async run(): Promise<void> {
    if (this.busy || (this.isFull() && !this.replaceSchemeId)) return;
    this.busy = true;
    try {
      await this.onImport(this.isFull() ? this.replaceSchemeId : '');
    } finally {
      this.busy = false;
    }
  }

  build() {
    ShareDialogSurface({ darkMode: this.darkMode }) {
      this.content()
    }
  }

  @Builder
  content() {
    Scroll() {
      Column({ space: AppSpacing.LG }) {
        shareDialogTitle('导入主题包', this.darkMode)
        Column({ space: AppSpacing.XXS }) {
          Text(this.preview.manifest.name)
            .fontSize(AppFontSize.BODY_LARGE)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeRuntime.primaryTextColor(this.darkMode))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.preview.manifest.author) {
            Text(themeAuthorLine(this.preview.manifest.author))
              .fontSize(AppFontSize.CAPTION)
              .fontColor(ThemeRuntime.subTextColor(this.darkMode))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        ThemeShareNotice({
          title: '将导入为一套新的自定义方案，包含',
          items: ['配色与各部件选择', ...this.contentSummary()],
          darkMode: this.darkMode
        })
        if (this.preview.replaced.length > 0) {
          ThemeShareNotice({
            title: '以下部件来自你尚未获得的主题，已换成默认主题的样式',
            items: this.preview.replaced,
            darkMode: this.darkMode
          })
        }
        if (this.preview.unknown.length > 0) {
          ThemeShareNotice({
            title: '以下部件需要更新应用才能显示，已换成默认样式',
            items: this.preview.unknown,
            darkMode: this.darkMode
          })
        }
        if (this.preview.missingFonts.length > 0) {
          ThemeShareNotice({
            title: '主题包没有附带这些字体，将使用全局字体',
            items: this.preview.missingFonts,
            darkMode: this.darkMode
          })
        }
        if (this.preview.lockedBubbles.length > 0) {
          ThemeShareNotice({
            title: '这些强调规则的气泡尚未解锁，阅读时显示为可用的气泡',
            items: this.preview.lockedBubbles,
            darkMode: this.darkMode
          })
        }
        if (this.isFull()) {
          Text(`已有 ${this.schemes.length} 套方案，达到当前上限 ${this.limit} 套。选择一套替换：`)
            .fontSize(AppFontSize.CAPTION)
            .fontColor(ThemeRuntime.dangerColor(this.darkMode))
            .width('100%')
          ForEach(this.replaceable(), (scheme: CustomThemeScheme) => {
            Row({ space: AppSpacing.MD }) {
              Radio({ value: scheme.id, group: 'qythemeReplace' })
                .checked(this.replaceSchemeId === scheme.id)
                .onChange((checked: boolean) => {
                  if (checked) this.replaceSchemeId = scheme.id;
                })
              Text(scheme.name)
                .fontSize(AppFontSize.BODY)
                .fontColor(ThemeRuntime.primaryTextColor(this.darkMode))
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .width('100%')
            .onClick(() => {
              this.replaceSchemeId = scheme.id;
            })
          }, (scheme: CustomThemeScheme) => scheme.id)
          Text('正在使用的方案不能被替换。替换后原方案的设置无法恢复。')
            .fontSize(AppFontSize.CAPTION)
            .fontColor(ThemeRuntime.subTextColor(this.darkMode))
            .width('100%')
        } else {
          Text(`导入后共 ${this.schemes.length + 1}/${this.limit} 套方案`)
            .fontSize(AppFontSize.CAPTION)
            .fontColor(ThemeRuntime.subTextColor(this.darkMode))
            .width('100%')
        }
        Row({ space: AppSpacing.LG }) {
          Button('取消', { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(42)
            .borderRadius(ThemeRuntime.buttonRadius())
            .backgroundColor(ThemeRuntime.cardColor(this.darkMode))
            .fontColor(ThemeRuntime.primaryTextColor(this.darkMode))
            .enabled(!this.busy)
            .onClick(() => this.onClose())
          Button(this.busy ? '导入中' : (this.isFull() ? '替换并导入' : '导入'), { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(42)
            .borderRadius(ThemeRuntime.buttonRadius())
            .backgroundColor(this.isFull() ? ThemeRuntime.dangerColor(this.darkMode) : ThemeRuntime.accentColor(this.darkMode))
            .fontColor(ThemeRuntime.onAccentColor(this.isFull() ? ThemeRuntime.dangerColor(this.darkMode) :
              ThemeRuntime.accentColor(this.darkMode)))
            .enabled(!this.busy && (!this.isFull() || !!this.replaceSchemeId))
            .onClick(() => this.run())
        }
        .width('100%')
      }
      .width('100%')
    }
    .scrollBar(BarState.Off)
    .constraintSize({ maxHeight: '80%' })
  }
}
