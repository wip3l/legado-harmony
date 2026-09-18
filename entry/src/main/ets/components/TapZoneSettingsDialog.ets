import { ReaderSettingsStore } from '../utils/ReaderSettingsStore';
import { ThemeRuntime } from '../theme/ThemeRuntime';

/**
 * 点击区域动作设置内容（配合系统自定义对话框使用，表面材质由系统渲染）。
 * 阅读器与设置页两处宿主共用；编辑结果经 AppStorage 同步。
 */
@Component
export struct TapZoneSettingsDialogContent {
  @StorageLink('readerTapZoneActions') readerTapZoneActions: string = '3,3,3,3,1,2,2,2,2';
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  onDone: () => void = (): void => {
  };

  actionsList(): number[] {
    return this.readerTapZoneActions.split(',').map((value: string): number => Number(value));
  }

  actionAt(index: number): number {
    const list = this.actionsList();
    return list[index];
  }

  cycleAction(index: number): void {
    const list = this.actionsList();
    const safeIndex = Math.max(0, Math.min(8, Math.round(index)));
    list[safeIndex] = (list[safeIndex] + 1) % 4;
    this.saveActions(list.join(','));
  }

  saveActions(actions: string): void {
    const normalized = this.normalizeActions(actions);
    this.readerTapZoneActions = normalized;
    ReaderSettingsStore.saveTapZoneActions(getContext(this), normalized).catch((e: Error) => {
      console.error('保存点击区域动作失败:', e);
    });
  }

  normalizeActions(actions: string): string {
    const fallback = [3, 3, 3, 3, 1, 2, 2, 2, 2];
    const parts = (actions || '').split(',');
    const result: number[] = [];
    for (let i = 0; i < 9; i++) {
      const parsed = Number(parts[i]);
      result.push(Number.isFinite(parsed) && parsed >= 0 && parsed <= 3 ? Math.round(parsed) : fallback[i]);
    }
    return result.join(',');
  }

  actionLabel(action: number): string {
    switch (action) {
      case 1:
        return '菜单';
      case 2:
        return '下一页';
      case 3:
        return '上一页';
      case 0:
      default:
        return '无动作';
    }
  }

  cellColor(action: number): string {
    if (action === 1) {
      return '#332A6FCC';
    }
    if (action === 2) {
      return '#2239A86B';
    }
    if (action === 3) {
      return '#22A85C39';
    }
    return this.appDarkMode ? '#14000000' : '#0F000000';
  }

  primaryTextColor(): string {
    return ThemeRuntime.primaryTextColor(this.appDarkMode);
  }

  subTextColor(): string {
    return ThemeRuntime.subTextColor(this.appDarkMode);
  }

  inputColor(): string {
    return ThemeRuntime.inputColor(this.appDarkMode);
  }

  buttonColor(): string {
    return ThemeRuntime.buttonColor(this.appDarkMode);
  }

  build() {
    Column({ space: 14 }) {
      Row() {
        Text('点击区域动作')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())
          .layoutWeight(1)

        Button('×')
          .fontSize(24)
          .fontColor(this.primaryTextColor())
          .width(44)
          .height(44)
          .backgroundColor(Color.Transparent)
          .padding(0)
          .onClick(() => {
            this.onDone();
          })
      }
      .width('100%')
      .height(48)
      .alignItems(VerticalAlign.Center)

      Text('点击九宫格可循环设置：无动作、菜单、下一页、上一页')
        .fontSize(12)
        .fontColor(this.subTextColor())
        .width('100%')

      Column() {
        ForEach([0, 1, 2], (row: number) => {
          Row() {
            ForEach([0, 1, 2], (column: number) => {
              this.cell(row * 3 + column)
            }, (column: number) => `${row}_${column}`)
          }
          .width('100%')
          .layoutWeight(1)
        }, (row: number) => `${row}`)
      }
      .width('100%')
      .height(280)
      .border({ width: 1, color: this.appDarkMode ? '#44FFFFFF' : '#22000000' })
      .clip(true)

      Row({ space: 12 }) {
        Button('重置默认')
          .layoutWeight(1)
          .height(40)
          .fontSize(14)
          .backgroundColor(this.inputColor())
          .fontColor(this.primaryTextColor())
          .onClick(() => {
            this.saveActions('3,3,3,3,1,2,2,2,2');
          })

        Button('完成')
          .layoutWeight(1)
          .height(40)
          .fontSize(14)
          .backgroundColor(this.buttonColor())
          .fontColor('#FFFFFF')
          .onClick(() => {
            this.onDone();
          })
      }
      .width('100%')
    }
    .width('100%')
    .constraintSize({ maxWidth: 420 })
    .padding(18)
  }

  @Builder
  cell(index: number) {
    Text(this.actionLabel(this.actionAt(index)))
      .fontSize(16)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.primaryTextColor())
      .textAlign(TextAlign.Center)
      .width('100%')
      .height('100%')
      .layoutWeight(1)
      .backgroundColor(this.cellColor(this.actionAt(index)))
      .border({ width: 0.5, color: this.appDarkMode ? '#33FFFFFF' : '#22000000' })
      .onClick(() => {
        this.cycleAction(index);
      })
  }
}
