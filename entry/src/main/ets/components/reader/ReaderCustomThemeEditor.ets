import { ReaderSettingsStore } from '../../utils/ReaderSettingsStore';
import { ReaderThemeHelper } from '../../utils/ReaderThemeHelper';
import { ReaderCustomThemeData, ReaderCustomThemeHelper, ReaderCustomThemeScheme } from
  '../../utils/ReaderCustomThemeHelper';
import { ReaderBackgroundImageStore } from '../../utils/ReaderBackgroundImageStore';
import { ImmersiveMaterialRuntime } from '../../utils/ImmersiveMaterialRuntime';
import { HdsFeedback } from '../../utils/HdsFeedback';
import { AdaptiveColorPicker } from '../AdaptiveColorPicker';
import { ThemeRuntime } from '../../theme/ThemeRuntime';
import { HexColor } from '../../utils/HexColor';
import { AppFontSize } from '../../theme/AppFontSize';
import { AppSpacing } from '../../theme/AppSpacing';

/**
 * 阅读页"自定义"配色的编辑器：多套方案的新增、删除、改名，背景色或背景图片，文字颜色。
 * 直接读写全局的自定义配色设置并保存；阅读页监听同一组设置来刷新正文，
 * onChanged 只用于让页面顺带保存本书的阅读配置。
 */
@Component
export struct ReaderCustomThemeEditor {
  @StorageProp('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  @Prop dark: boolean = false;
  @Prop textColor: string = '#202124';
  @Prop accentColor: string = '#0A59F7';
  @Prop menuColor: string = '#FFFFFF';
  onChanged: () => void = (): void => {
  };

  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('readerLightThemeIndex') readerLightThemeIndex: number = 0;
  @StorageLink('readerDarkThemeIndex') readerDarkThemeIndex: number = 0;
  @StorageLink('readerLightCustomThemeBackgroundColor') lightBackgroundColor: string =
    ReaderThemeHelper.LIGHT_CUSTOM_BACKGROUND_COLOR;
  @StorageLink('readerLightCustomThemeTextColor') lightTextColor: string = ReaderThemeHelper.LIGHT_CUSTOM_TEXT_COLOR;
  @StorageLink('readerDarkCustomThemeBackgroundColor') darkBackgroundColor: string =
    ReaderThemeHelper.DARK_CUSTOM_BACKGROUND_COLOR;
  @StorageLink('readerDarkCustomThemeTextColor') darkTextColor: string = ReaderThemeHelper.DARK_CUSTOM_TEXT_COLOR;
  @StorageLink('readerCustomThemesRaw') customThemesRaw: string = '';
  @State private nameDraft: string = '';

  aboutToAppear(): void {
    this.nameDraft = this.scheme().name;
  }

  private data(): ReaderCustomThemeData {
    return ReaderCustomThemeHelper.parse(this.customThemesRaw, this.lightBackgroundColor, this.lightTextColor,
      this.darkBackgroundColor, this.darkTextColor);
  }

  private scheme(): ReaderCustomThemeScheme {
    return ReaderCustomThemeHelper.selected(this.data(), this.appDarkMode);
  }

  private schemes(): ReaderCustomThemeScheme[] {
    return ReaderCustomThemeHelper.schemesForMode(this.data(), this.appDarkMode);
  }

  private selectedIndex(): number {
    const selectedId = this.scheme().id;
    return Math.max(0, this.schemes().findIndex((item: ReaderCustomThemeScheme) => item.id === selectedId));
  }

  private backgroundTypeIndex(): number {
    return this.scheme().backgroundType === 'image' ? 1 : 0;
  }

  private fitIndex(): number {
    const fit = this.scheme().backgroundImageFit;
    return fit === 'contain' ? 1 : (fit === 'fill' ? 2 : 0);
  }

  private fieldColor(): string {
    return ThemeRuntime.hairlineColor(this.appDarkMode);
  }

  private normalizeColor(color: string, fallback: string): string {
    return HexColor.normalize(color, fallback);
  }

  private persist(data: ReaderCustomThemeData): void {
    const selected = ReaderCustomThemeHelper.selected(data, this.appDarkMode);
    if (this.appDarkMode) {
      this.darkBackgroundColor = selected.backgroundColor;
      this.darkTextColor = selected.textColor;
    } else {
      this.lightBackgroundColor = selected.backgroundColor;
      this.lightTextColor = selected.textColor;
    }
    this.customThemesRaw = ReaderCustomThemeHelper.stringify(data);
    ReaderSettingsStore.saveThemeSettings(getContext(this), this.readerLightThemeIndex, this.readerDarkThemeIndex,
      this.lightBackgroundColor, this.lightTextColor, this.darkBackgroundColor, this.darkTextColor,
      this.appDarkMode, this.customThemesRaw).catch((e: Error) => {
      console.warn('保存阅读配色设置失败:', e);
    });
    this.onChanged();
  }

  private add(): void {
    const data = this.data();
    this.nameDraft = ReaderCustomThemeHelper.add(data, this.appDarkMode).name;
    this.persist(data);
  }

  private removeCurrent(): void {
    const data = this.data();
    if (ReaderCustomThemeHelper.schemesForMode(data, this.appDarkMode).length <= 1) {
      HdsFeedback.showToast('至少保留一套自定义背景');
      return;
    }
    ReaderCustomThemeHelper.removeSelected(data, this.appDarkMode);
    this.nameDraft = ReaderCustomThemeHelper.selected(data, this.appDarkMode).name;
    this.persist(data);
  }

  private select(index: number): void {
    const data = this.data();
    const schemes = ReaderCustomThemeHelper.schemesForMode(data, this.appDarkMode);
    if (index < 0 || index >= schemes.length) return;
    ReaderCustomThemeHelper.select(data, this.appDarkMode, schemes[index].id);
    this.nameDraft = schemes[index].name;
    this.persist(data);
  }

  private rename(name: string): void {
    const data = this.data();
    const current = ReaderCustomThemeHelper.selected(data, this.appDarkMode);
    const value = (name || '').trim().substring(0, 20);
    if (!value) {
      this.nameDraft = current.name;
      return;
    }
    if (value === current.name) return;
    current.name = value;
    this.nameDraft = value;
    this.persist(data);
  }

  private async chooseImage(): Promise<void> {
    const data = this.data();
    const current = ReaderCustomThemeHelper.selected(data, this.appDarkMode);
    try {
      const imageUri = await ReaderBackgroundImageStore.pickAndSave(getContext(this), current.id);
      if (!imageUri) return;
      current.backgroundImageUri = imageUri;
      current.backgroundType = 'image';
      this.persist(data);
    } catch (e) {
      console.error('选择阅读背景图片失败:', e);
      HdsFeedback.showToast('选择背景图片失败');
    }
  }

  private clearImage(): void {
    const data = this.data();
    const current = ReaderCustomThemeHelper.selected(data, this.appDarkMode);
    current.backgroundImageUri = '';
    current.backgroundType = 'color';
    this.persist(data);
  }

  private setBackgroundType(index: number): void {
    const data = this.data();
    ReaderCustomThemeHelper.selected(data, this.appDarkMode).backgroundType = index === 1 ? 'image' : 'color';
    this.persist(data);
  }

  private setImageFit(index: number): void {
    const fits = ['cover', 'contain', 'fill'];
    const data = this.data();
    ReaderCustomThemeHelper.selected(data, this.appDarkMode).backgroundImageFit = fits[index] || 'cover';
    this.persist(data);
  }

  private setBackgroundColor(color: string): void {
    const data = this.data();
    const current = ReaderCustomThemeHelper.selected(data, this.appDarkMode);
    current.backgroundColor = this.normalizeColor(color, current.backgroundColor);
    this.persist(data);
  }

  private setTextColor(color: string): void {
    const data = this.data();
    const current = ReaderCustomThemeHelper.selected(data, this.appDarkMode);
    current.textColor = this.normalizeColor(color, current.textColor);
    this.persist(data);
  }

  build() {
    Column({ space: AppSpacing.MD }) {
      Row({ space: AppSpacing.MD }) {
        Select(this.schemes().map((item: ReaderCustomThemeScheme): SelectOption => ({ value: item.name })))
          .selected(this.selectedIndex())
          .value(this.scheme().name)
          .font({ size: AppFontSize.BODY })
          .fontColor(this.textColor)
          .backgroundColor(this.fieldColor())
          .borderRadius(16)
          .border({ width: 0 })
          .layoutWeight(1)
          .divider(null)
          .optionBgColor(Color.Transparent)
          .optionFontColor(this.textColor)
          .selectedOptionFontColor(this.accentColor)
          .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.dark))
          .menuBackgroundColor(this.menuColor)
          .menuBackgroundBlurStyle(BlurStyle.NONE)
          .attributeModifier(ImmersiveMaterialRuntime.selectMenuModifier(this.immersiveLightLevel, this.dark, this.menuColor))
          .onSelect((index: number) => this.select(index))
        Button('新增')
          .height(36)
          .fontSize(AppFontSize.BODY)
          .backgroundColor(this.accentColor)
          .fontColor(ThemeRuntime.onAccentColor())
          .onClick(() => this.add())
        Button('删除')
          .height(36)
          .fontSize(AppFontSize.BODY)
          .backgroundColor(this.fieldColor())
          .fontColor(this.textColor)
          .onClick(() => this.removeCurrent())
      }
      .width('100%')

      TextInput({ text: this.nameDraft, placeholder: '输入方案名称' })
        .fontSize(AppFontSize.BODY)
        .fontColor(this.textColor)
        .height(36)
        .padding({ left: AppSpacing.MD, right: AppSpacing.MD })
        .backgroundColor(this.fieldColor())
        .borderRadius(ThemeRuntime.mediumRadius())
        .onChange((value: string) => {
          this.nameDraft = value.substring(0, 20);
        })
        .onSubmit(() => this.rename(this.nameDraft))
        .onBlur(() => this.rename(this.nameDraft))

      Row() {
        Text('背景设置')
          .fontSize(AppFontSize.BODY)
          .fontColor(this.textColor)
        Blank()
        Select([{ value: '背景色' }, { value: '背景图片' }])
          .selected(this.backgroundTypeIndex())
          .value(this.backgroundTypeIndex() === 1 ? '背景图片' : '背景色')
          .font({ size: AppFontSize.BODY })
          .fontColor(this.textColor)
          .backgroundColor(this.fieldColor())
          .borderRadius(16)
          .border({ width: 0 })
          .optionBgColor(Color.Transparent)
          .divider(null)
          .optionFontColor(this.textColor)
          .selectedOptionFontColor(this.accentColor)
          .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.dark))
          .menuBackgroundColor(this.menuColor)
          .menuBackgroundBlurStyle(BlurStyle.NONE)
          .attributeModifier(ImmersiveMaterialRuntime.selectMenuModifier(this.immersiveLightLevel, this.dark, this.menuColor))
          .onSelect((index: number) => this.setBackgroundType(index))
      }
      .width('100%')

      if (this.backgroundTypeIndex() === 0) {
        AdaptiveColorPicker({
          value: this.scheme().backgroundColor,
          placeholder: this.scheme().backgroundColor,
          appDarkMode: this.appDarkMode,
          accentColor: this.accentColor,
          optionTitle: '背景颜色',
          onColorChange: (value: string) => this.setBackgroundColor(value)
        })
      } else {
        Row({ space: AppSpacing.MD }) {
          Button(this.scheme().backgroundImageUri ? '更换背景图片' : '选择背景图片')
            .height(36)
            .fontSize(AppFontSize.BODY)
            .backgroundColor(this.accentColor)
            .fontColor(ThemeRuntime.onAccentColor())
            .onClick(() => {
              this.chooseImage();
            })
          if (this.scheme().backgroundImageUri) {
            Button('移除图片')
              .height(36)
              .fontSize(AppFontSize.BODY)
              .backgroundColor(this.fieldColor())
              .fontColor(this.textColor)
              .onClick(() => this.clearImage())
            Select([{ value: '裁剪填充' }, { value: '完整显示' }, { value: '拉伸铺满' }])
              .selected(this.fitIndex())
              .value(['裁剪填充', '完整显示', '拉伸铺满'][this.fitIndex()])
              .font({ size: AppFontSize.BODY })
              .fontColor(this.textColor)
              .backgroundColor(this.fieldColor())
              .borderRadius(16)
              .border({ width: 0 })
              .layoutWeight(1)
              .divider(null)
              .optionBgColor(Color.Transparent)
              .optionFontColor(this.textColor)
              .selectedOptionFontColor(this.accentColor)
              .selectedOptionBgColor(ThemeRuntime.accentSurfaceColor(this.dark))
              .menuBackgroundColor(this.menuColor)
              .menuBackgroundBlurStyle(BlurStyle.NONE)
              .attributeModifier(ImmersiveMaterialRuntime.selectMenuModifier(this.immersiveLightLevel, this.dark, this.menuColor))
              .onSelect((index: number) => this.setImageFit(index))
          }
        }
        .width('100%')
      }

      AdaptiveColorPicker({
        value: this.scheme().textColor,
        placeholder: this.scheme().textColor,
        appDarkMode: this.appDarkMode,
        accentColor: this.accentColor,
        optionTitle: '文字颜色',
        onColorChange: (value: string) => this.setTextColor(value)
      })
    }
    .width('100%')
  }
}
