import { router, promptAction } from '@kit.ArkUI';
import { BookSource, SearchBook, BookListRule, SearchRule, ExploreRule, BookInfoRule, TocRule, ContentRule } from '../model/data/Book';
import { AppDatabase } from '../model/data/AppDatabase';
import { HttpClient } from '../core/http/HttpClient';
import { SearchCoordinator, SearchProgress } from '../core/book/SearchCoordinator';
import { syncSystemBars } from '../utils/SystemBars';
import { SearchExploreSettingsStore } from '../utils/SearchExploreSettingsStore';
import picker from '@ohos.file.picker';
import fs from '@ohos.file.fs';
import { util } from '@kit.ArkTS';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { VerificationSupport } from '../core/http/VerificationSupport';
import { CookieStore } from '../core/http/CookieStore';

const BOOK_SOURCE_IMPORT_FILE_LIMIT_BYTES = 25 * 1024 * 1024;
const BOOK_SOURCE_IMPORT_TIMEOUT_MS = 20000;
const BOOK_SOURCE_IMPORT_URL_RETRY_COUNT = 3;
const BOOK_SOURCE_CHECK_KEYWORD = '斗破苍穹';

@Entry
@Component
struct BookSourcePage {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('appLightAccentColor') appLightAccentColor: string = '#007DFF';
  @StorageLink('appDarkAccentColor') appDarkAccentColor: string = '#4E9BFF';
  @StorageLink('appLightButtonColor') appLightButtonColor: string = '#007DFF';
  @StorageLink('appDarkButtonColor') appDarkButtonColor: string = '#3F8CFF';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @State sources: BookSource[] = [];
  @State isLoading: boolean = false;
  @State searchText: string = '';
  @State showAddDialog: boolean = false;
  @State showImportUrlDialog: boolean = false;
  @State selectionMode: boolean = false;
  @State selectedSourceUrls: string[] = [];
  @State showBatchDeleteDialog: boolean = false;
  @State showGroupDialog: boolean = false;
  @State showMoreActionDialog: boolean = false;
  @State showSourceActionDialog: boolean = false;
  @State showSourceDeleteDialog: boolean = false;
  @State actionSourceUrl: string = '';
  @State contextMenuX: number = 16;
  @State contextMenuY: number = 96;
  @State contextViewportWidth: number = 360;
  @State contextViewportHeight: number = 720;
  @State groupNameInput: string = '';
  @State importUrl: string = '';
  @State isImporting: boolean = false;
  @State isBatchOperating: boolean = false;
  @State batchOperationText: string = '正在操作书源...';
  @State showCheckDialog: boolean = false;
  @State showCheckOptionsDialog: boolean = false;
  @State isCheckingSources: boolean = false;
  @State checkDone: number = 0;
  @State checkTotal: number = 0;
  @State checkOkCount: number = 0;
  @State checkBadUrls: string[] = [];
  @State checkBadNames: string[] = [];
  @State checkStatus: string = '';
  @State checkInvalidAction: string = 'none';
  @State checkAutoHandledCount: number = 0;
  private hasShownOnce: boolean = false;

  aboutToAppear() {
    this.syncBars();
    this.loadSources();
  }

  onPageShow(): void {
    this.syncBars();
    if (!this.hasShownOnce) {
      this.hasShownOnce = true;
      return;
    }
    this.refreshSources();
  }

  async refreshSources(): Promise<void> {
    if (this.searchText) {
      await this.searchSources();
    } else {
      await this.loadSources();
    }
  }

  async loadSources() {
    this.isLoading = true;
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      this.sources = await db.getAllBookSources();
      this.pruneSelectedSources();
    } catch (e) {
      console.error('加载书源失败:', e);
    } finally {
      this.isLoading = false;
    }
  }

  build() {
    Stack() {
      Column() {
        Row() {
          Text('<')
            .fontSize(24)
            .fontColor(this.primaryTextColor())
            .width(40)
            .height(56)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              router.back();
            })

          Text('书源管理')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.primaryTextColor())
            .layoutWeight(1)

          Text(this.selectionMode ? '取消' : '选择')
            .fontSize(15)
            .fontColor(this.isBatchOperating ? this.subTextColor() : this.primaryTextColor())
            .width(52)
            .height(56)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              if (this.isBatchOperating) {
                return;
              }
              if (this.selectionMode) {
                this.exitSelectionMode();
              } else {
                this.enterSelectionMode();
              }
            })

          if (!this.selectionMode) {
            Text('校验')
              .fontSize(15)
              .fontColor(this.isCheckingSources ? this.subTextColor() : this.primaryTextColor())
              .width(52)
              .height(56)
              .textAlign(TextAlign.Center)
              .onClick(() => {
                this.openCheckOptions();
              })

            Text('+')
              .fontSize(24)
              .fontColor(this.primaryTextColor())
              .width(40)
              .height(56)
              .textAlign(TextAlign.Center)
              .onClick(() => {
                this.showAddDialog = true;
              })
          }
        }
        .width('100%')
        .height(56)
        .backgroundColor(this.glassCardColor())
        .border({ width: 1, color: this.glassBorderColor() })
        .alignItems(VerticalAlign.Center)

        Row() {
          TextInput({ placeholder: '搜索书源', text: this.searchText })
            .layoutWeight(1)
            .height(40)
            .borderRadius(20)
            .backgroundColor(this.glassInputColor())
            .border({ width: 1, color: this.glassBorderColor() })
            .shadow({ radius: 8, color: this.glassShadowColor(), offsetX: 0, offsetY: 3 })
            .fontColor(this.primaryTextColor())
            .placeholderColor(this.placeholderTextColor())
            .padding({ left: 16, right: 16 })
            .onChange((value: string) => {
              this.searchText = value;
              this.searchSources();
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })

        if (this.selectionMode) {
          Row() {
            Text(this.isAllSelected() ? '☑' : '☐')
              .fontSize(20)
              .fontColor(this.accentColor())
              .width(28)
              .textAlign(TextAlign.Center)
              .onClick(() => {
                if (this.isBatchOperating) {
                  return;
                }
                this.toggleAllSources();
              })

            Text(`已选择 ${this.selectedSourceUrls.length}/${this.sources.length}`)
              .fontSize(14)
              .fontColor(this.secondaryTextColor())
              .margin({ left: 8 })
              .layoutWeight(1)

            Text(this.isAllSelected() ? '取消全选' : '全选')
              .fontSize(14)
              .fontColor(this.isBatchOperating ? this.subTextColor() : this.accentColor())
              .onClick(() => {
                if (this.isBatchOperating) {
                  return;
                }
                this.toggleAllSources();
              })
          }
          .width('100%')
          .height(42)
          .padding({ left: 16, right: 16 })
        }

        if (this.isLoading) {
          Column() {
            LoadingProgress()
              .width(40)
              .height(40)
            Text('加载中...')
              .fontSize(14)
              .fontColor(this.subTextColor())
              .margin({ top: 8 })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        } else if (this.sources.length === 0) {
          Column() {
            Text('暂无书源')
              .fontSize(16)
              .fontColor(this.subTextColor())
            Text('点击右上角"+"添加书源')
              .fontSize(14)
              .fontColor(this.subTextColor())
              .margin({ top: 8 })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        } else {
          List({ space: 8 }) {
            ForEach(this.sources, (source: BookSource) => {
              ListItem() {
                Row() {
                  if (this.selectionMode) {
                    Toggle({ type: ToggleType.Checkbox, isOn: this.isSourceSelected(source.bookSourceUrl) })
                      .selectedColor(this.buttonColor())
                      .enabled(!this.isBatchOperating)
                      .margin({ right: 12 })
                      .onChange((isOn: boolean) => {
                        if (this.isBatchOperating) {
                          return;
                        }
                        this.setSourceSelected(source.bookSourceUrl, isOn);
                      })
                  }

                  Column() {
                    Row() {
                      Text(source.bookSourceName)
                        .fontSize(16)
                        .fontWeight(FontWeight.Bold)
                        .fontColor(this.primaryTextColor())
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .layoutWeight(1)

                      if (this.sourceNeedsLogin(source)) {
                        Text(this.sourceLoggedIn(source) ? '已登录' : '未登录')
                          .fontSize(11)
                          .fontColor(this.sourceLoggedIn(source) ? '#1E8E3E' : '#C62828')
                          .backgroundColor(this.sourceLoggedIn(source) ? '#E7F5EA' : '#FDECEC')
                          .padding({ left: 7, right: 7, top: 3, bottom: 3 })
                          .borderRadius(4)
                          .margin({ left: 8 })
                      }
                    }
                    .width('100%')
                    .alignItems(VerticalAlign.Center)

                    Text(source.bookSourceUrl)
                      .fontSize(12)
                      .fontColor(this.subTextColor())
                      .margin({ top: 4 })
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })

                    if (source.bookSourceGroup) {
                      Text(source.bookSourceGroup)
                        .fontSize(12)
                        .fontColor(this.secondaryTextColor())
                        .margin({ top: 4 })
                    }
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)

                  Column() {
                    if (!this.selectionMode) {
                      Toggle({ type: ToggleType.Switch, isOn: source.enabled })
                        .selectedColor(this.buttonColor())
                        .onChange((isOn: boolean) => {
                          source.enabled = isOn;
                          this.updateSource(source);
                        })

                    } else {
                      Text(source.enabled ? '已启用' : '已禁用')
                        .fontSize(12)
                        .fontColor(source.enabled ? '#1E8E3E' : this.subTextColor())
                      Text(source.enabledExplore ? '发现已启用' : '发现已禁用')
                        .fontSize(12)
                        .fontColor(source.enabledExplore ? '#1E8E3E' : this.subTextColor())
                        .margin({ top: 4 })
                    }
                  }
                  .alignItems(HorizontalAlign.End)
                }
                .width('100%')
                .padding(12)
                .backgroundColor(this.glassCardColor())
                .borderRadius(8)
                .border({ width: 1, color: this.glassBorderColor() })
                .shadow({ radius: 10, color: this.glassShadowColor(), offsetX: 0, offsetY: 4 })
                .gesture(
                  LongPressGesture({ repeat: false })
                    .onAction((event: GestureEvent) => {
                      if (!this.selectionMode && !this.isBatchOperating) {
                        this.openSourceActions(source, event);
                      }
                    })
                )
                .onClick(() => {
                  if (this.isBatchOperating) {
                    return;
                  }
                  if (this.selectionMode) {
                    this.toggleSourceSelected(source.bookSourceUrl);
                  }
                })
              }
            }, (source: BookSource) => this.sourceListItemKey(source))
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 16, right: 16 })
        }

        if (this.selectionMode) {
          Row() {
            Button('启用')
              .layoutWeight(1)
              .height(42)
              .enabled(this.selectedSourceUrls.length > 0 && !this.isBatchOperating)
              .backgroundColor(this.buttonColor())
              .fontColor('#FFFFFF')
              .onClick(() => {
                this.batchSetEnabled(true);
              })

            Button('禁用')
              .layoutWeight(1)
              .height(42)
              .margin({ left: 8 })
              .enabled(this.selectedSourceUrls.length > 0 && !this.isBatchOperating)
              .backgroundColor(this.inputColor())
              .fontColor(this.primaryTextColor())
              .onClick(() => {
                this.batchSetEnabled(false);
              })

            Button('分组')
              .layoutWeight(1)
              .height(42)
              .margin({ left: 8 })
              .enabled(this.selectedSourceUrls.length > 0 && !this.isBatchOperating)
              .backgroundColor(this.inputColor())
              .fontColor(this.primaryTextColor())
              .onClick(() => {
                this.groupNameInput = this.commonSelectedGroupName();
                this.showGroupDialog = true;
              })

            Button('更多')
              .layoutWeight(1)
              .height(42)
              .margin({ left: 8 })
              .enabled(this.selectedSourceUrls.length > 0 && !this.isBatchOperating)
              .backgroundColor(this.inputColor())
              .fontColor(this.primaryTextColor())
              .onClick(() => {
                this.showMoreActionDialog = true;
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 10, bottom: 12 })
          .backgroundColor(this.glassCardColor())
          .border({ width: 1, color: this.glassBorderColor() })
        }
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.statusBarHeight, bottom: this.navBarHeight })
      .backgroundColor(this.pageColor())

      if (this.showAddDialog) {
        Column() {
          Column() {
            Text('添加书源')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.primaryTextColor())
              .width('100%')
              .textAlign(TextAlign.Center)
              .margin({ bottom: 16 })

            Button('新建书源')
              .width('100%')
              .height(48)
              .margin({ bottom: 8 })
              .backgroundColor(this.buttonColor())
              .fontColor('#FFFFFF')
              .onClick(() => {
                this.showAddDialog = false;
                router.pushUrl({
                  url: 'pages/BookSourceEdit',
                  params: { bookSourceUrl: '' }
                });
              })

            Button('从URL导入')
              .width('100%')
              .height(48)
              .margin({ bottom: 8 })
              .backgroundColor(this.buttonColor())
              .fontColor('#FFFFFF')
              .onClick(() => {
                this.showAddDialog = false;
                this.showImportUrlDialog = true;
              })

            Button('从文件导入')
              .width('100%')
              .height(48)
              .margin({ bottom: 8 })
              .backgroundColor(this.buttonColor())
              .fontColor('#FFFFFF')
              .onClick(() => {
                this.showAddDialog = false;
                this.importFromFile();
              })

            Button('取消')
              .width('100%')
              .height(48)
              .backgroundColor(this.inputColor())
              .fontColor(this.primaryTextColor())
              .onClick(() => {
                this.showAddDialog = false;
              })
          }
          .width('90%')
          .padding(24)
          .backgroundColor(this.cardColor())
          .borderRadius(12)
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#80000000')
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.showAddDialog = false;
        })
      }

      if (this.showImportUrlDialog) {
        Column() {
          Column() {
            Text('从URL导入')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.primaryTextColor())
              .width('100%')
              .textAlign(TextAlign.Center)
              .margin({ bottom: 16 })

            TextInput({ placeholder: '请输入书源URL', text: this.importUrl })
              .width('100%')
              .height(48)
              .borderRadius(8)
              .backgroundColor(this.inputColor())
              .fontColor(this.primaryTextColor())
              .placeholderColor(this.placeholderTextColor())
              .padding({ left: 12, right: 12 })
              .margin({ bottom: 16 })
              .onChange((value: string) => {
                this.importUrl = value;
              })

            Row() {
              Button('取消')
                .width('45%')
                .height(44)
                .backgroundColor(this.inputColor())
                .fontColor(this.primaryTextColor())
                .onClick(() => {
                  this.showImportUrlDialog = false;
                  this.importUrl = '';
                })

              Button('导入')
                .width('45%')
                .height(44)
                .backgroundColor(this.buttonColor())
                .fontColor('#FFFFFF')
                .onClick(() => {
                  this.importFromUrl();
                })
            }
            .width('100%')
            .justifyContent(FlexAlign.SpaceBetween)
          }
          .width('90%')
          .padding(24)
          .backgroundColor(this.cardColor())
          .borderRadius(12)
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#80000000')
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.showImportUrlDialog = false;
        })
      }

      if (this.showBatchDeleteDialog) {
        Column() {
          Column() {
            Text('确认删除')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.primaryTextColor())
              .width('100%')
              .textAlign(TextAlign.Center)
              .margin({ bottom: 12 })

            Text(`确定删除已选择的 ${this.selectedSourceUrls.length} 个书源吗？删除后不可恢复。`)
              .fontSize(15)
              .fontColor(this.secondaryTextColor())
              .width('100%')
              .textAlign(TextAlign.Center)
              .margin({ bottom: 20 })

            Row() {
              Button('取消')
                .width('45%')
                .height(44)
                .backgroundColor(this.inputColor())
                .fontColor(this.primaryTextColor())
                .onClick(() => {
                  this.showBatchDeleteDialog = false;
                })

              Button('删除')
                .width('45%')
                .height(44)
                .backgroundColor('#E53935')
                .onClick(() => {
                  this.showBatchDeleteDialog = false;
                  this.batchDeleteSelectedSources();
                })
            }
            .width('100%')
            .justifyContent(FlexAlign.SpaceBetween)
          }
          .width('85%')
          .padding(24)
          .backgroundColor(this.cardColor())
          .borderRadius(12)
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#80000000')
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.showBatchDeleteDialog = false;
        })
      }

      if (this.showGroupDialog) {
        Column() {
          Column() {
            Text('设置书源分组')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.primaryTextColor())
              .width('100%')
              .textAlign(TextAlign.Center)
              .margin({ bottom: 12 })

            Text(`已选择 ${this.selectedSourceUrls.length} 个书源`)
              .fontSize(13)
              .fontColor(this.subTextColor())
              .width('100%')
              .textAlign(TextAlign.Center)
              .margin({ bottom: 14 })

            TextInput({ placeholder: '输入新分组名称，留空为未分组', text: this.groupNameInput })
              .width('100%')
              .height(44)
              .borderRadius(8)
              .backgroundColor(this.inputColor())
              .fontColor(this.primaryTextColor())
              .placeholderColor(this.placeholderTextColor())
              .padding({ left: 12, right: 12 })
              .onChange((value: string) => {
                this.groupNameInput = value;
              })

            if (this.getSourceGroups().length > 0) {
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.getSourceGroups(), (group: string) => {
                  Text(group)
                    .fontSize(13)
                    .fontColor(this.secondaryTextColor())
                    .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                    .backgroundColor(this.inputColor())
                    .borderRadius(14)
                    .margin({ right: 8, top: 10 })
                    .onClick(() => {
                      this.groupNameInput = group;
                    })
                })
              }
              .width('100%')
            }

            Row() {
              Button('取消')
                .width('45%')
                .height(44)
                .backgroundColor(this.inputColor())
                .fontColor(this.primaryTextColor())
                .onClick(() => {
                  this.showGroupDialog = false;
                })

              Button('保存')
                .width('45%')
                .height(44)
                .backgroundColor(this.buttonColor())
                .fontColor('#FFFFFF')
                .onClick(() => {
                  this.applySelectedSourceGroup();
                })
            }
            .width('100%')
            .justifyContent(FlexAlign.SpaceBetween)
            .margin({ top: 18 })
          }
          .width('88%')
          .padding(24)
          .backgroundColor(this.cardColor())
          .borderRadius(12)
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#80000000')
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.showGroupDialog = false;
        })
      }

      if (this.showMoreActionDialog) {
        Column() {
          Column() {
            Text('更多操作')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.primaryTextColor())
              .width('100%')
              .textAlign(TextAlign.Center)
              .margin({ bottom: 8 })

            Text(`已选择 ${this.selectedSourceUrls.length} 个书源`)
              .fontSize(13)
              .fontColor(this.subTextColor())
              .width('100%')
              .textAlign(TextAlign.Center)
              .margin({ bottom: 16 })

            Button('启用发现')
              .width('100%')
              .height(44)
              .backgroundColor(this.buttonColor())
              .fontColor('#FFFFFF')
              .margin({ bottom: 10 })
              .onClick(() => {
                this.showMoreActionDialog = false;
                this.batchSetExploreEnabled(true);
              })

            Button('禁用发现')
              .width('100%')
              .height(44)
              .backgroundColor(this.inputColor())
              .fontColor(this.primaryTextColor())
              .margin({ bottom: 10 })
              .onClick(() => {
                this.showMoreActionDialog = false;
                this.batchSetExploreEnabled(false);
              })

            Button('导出 JSON')
              .width('100%')
              .height(44)
              .backgroundColor(this.inputColor())
              .fontColor(this.primaryTextColor())
              .margin({ bottom: 10 })
              .onClick(() => {
                this.showMoreActionDialog = false;
                this.exportSelectedSources();
              })

            Button('删除')
              .width('100%')
              .height(44)
              .backgroundColor('#E53935')
              .fontColor('#FFFFFF')
              .margin({ bottom: 10 })
              .onClick(() => {
                this.showMoreActionDialog = false;
                this.showBatchDeleteDialog = true;
              })

            Button('取消')
              .width('100%')
              .height(44)
              .backgroundColor(this.inputColor())
              .fontColor(this.primaryTextColor())
              .onClick(() => {
                this.showMoreActionDialog = false;
              })
          }
          .width('88%')
          .padding(24)
          .backgroundColor(this.cardColor())
          .borderRadius(12)
          .onClick(() => {
          })
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#80000000')
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.showMoreActionDialog = false;
        })
      }

      if (this.showCheckOptionsDialog) {
        this.checkOptionsDialog()
      }

      if (this.showSourceActionDialog) {
        this.sourceActionDialog()
      }

      if (this.showSourceDeleteDialog) {
        this.sourceDeleteDialog()
      }

      if (this.showCheckDialog) {
        Column() {
          Column() {
            Text(this.isCheckingSources ? '正在校验书源' : '校验完成')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.primaryTextColor())
              .width('100%')
              .textAlign(TextAlign.Center)
              .margin({ bottom: 12 })

            if (this.isCheckingSources) {
              LoadingProgress()
                .width(42)
                .height(42)
                .color(this.accentColor())
                .margin({ bottom: 12 })
            }

            Text(this.checkStatus || (this.isCheckingSources ? '准备中...' : this.checkSummaryText()))
              .fontSize(14)
              .fontColor(this.secondaryTextColor())
              .width('100%')
              .textAlign(TextAlign.Center)
              .margin({ bottom: 12 })

            Progress({ value: this.checkDone, total: Math.max(this.checkTotal, 1), type: ProgressType.Linear })
              .width('100%')
              .height(8)
              .color(this.buttonColor())
              .backgroundColor(this.inputColor())
              .margin({ bottom: 12 })

            Text(`${this.checkDone}/${this.checkTotal}`)
              .fontSize(13)
              .fontColor(this.subTextColor())
              .margin({ bottom: this.isCheckingSources ? 0 : 12 })

            if (!this.isCheckingSources) {
              Text(this.checkResultText())
                .fontSize(14)
                .fontColor(this.secondaryTextColor())
                .width('100%')
                .textAlign(TextAlign.Center)
                .margin({ bottom: 12 })

              if (this.checkBadUrls.length > 0) {
                Scroll() {
                  Column() {
                    ForEach(this.checkBadNames, (name: string, index: number) => {
                      Text(name)
                        .fontSize(13)
                        .fontColor(this.subTextColor())
                        .width('100%')
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .margin({ bottom: index === this.checkBadNames.length - 1 ? 0 : 6 })
                    }, (name: string, index: number) => `${index}-${name}`)
                  }
                  .width('100%')
                  .alignItems(HorizontalAlign.Start)
                }
                .width('100%')
                .height(Math.min(this.checkBadNames.length * 25 + 20, 120))
                .padding(10)
                .backgroundColor(this.inputColor())
                .borderRadius(8)
                .margin({ bottom: 16 })
                .scrollBar(BarState.Auto)
              }

              Row({ space: 8 }) {
                if (this.checkInvalidAction === 'none') {
                  Button('一键禁用', { type: ButtonType.Normal })
                    .layoutWeight(1)
                    .height(42)
                    .borderRadius(10)
                    .fontSize(13)
                    .enabled(this.checkBadUrls.length > 0 && !this.isBatchOperating)
                    .backgroundColor(this.checkBadUrls.length > 0 && !this.isBatchOperating ? '#E53935' : this.inputColor())
                    .fontColor(this.checkBadUrls.length > 0 && !this.isBatchOperating ? '#FFFFFF' : this.subTextColor())
                    .onClick(() => {
                      this.disableFailedCheckedSources();
                    })

                  Button('一键删除', { type: ButtonType.Normal })
                    .layoutWeight(1)
                    .height(42)
                    .borderRadius(10)
                    .fontSize(13)
                    .enabled(this.checkBadUrls.length > 0 && !this.isBatchOperating)
                    .backgroundColor(this.checkBadUrls.length > 0 && !this.isBatchOperating ? '#B71C1C' : this.inputColor())
                    .fontColor(this.checkBadUrls.length > 0 && !this.isBatchOperating ? '#FFFFFF' : this.subTextColor())
                    .onClick(() => {
                      this.deleteFailedCheckedSources();
                    })
                }

                Button(this.checkInvalidAction === 'none' ? '取消' : '关闭', { type: ButtonType.Normal })
                  .layoutWeight(1)
                  .height(42)
                  .borderRadius(10)
                  .fontSize(13)
                  .backgroundColor(this.inputColor())
                  .fontColor(this.primaryTextColor())
                  .onClick(() => {
                    this.showCheckDialog = false;
                  })
              }
              .width('100%')
              .justifyContent(FlexAlign.SpaceBetween)
            }
          }
          .width('88%')
          .constraintSize({ maxHeight: '78%' })
          .padding(24)
          .backgroundColor(this.cardColor())
          .borderRadius(12)
          .alignItems(HorizontalAlign.Center)
          .onClick(() => {
          })
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#80000000')
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          if (!this.isCheckingSources) {
            this.showCheckDialog = false;
          }
        })
      }

      if (this.isImporting) {
        Column() {
          Column() {
            LoadingProgress()
              .width(46)
              .height(46)
              .color(this.accentColor())

            Text('正在导入书源...')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.primaryTextColor())
              .margin({ top: 14 })

            Text('请稍候')
              .fontSize(13)
              .fontColor(this.subTextColor())
              .margin({ top: 6 })
          }
          .width(180)
          .padding({ left: 24, right: 24, top: 26, bottom: 24 })
          .backgroundColor(this.cardColor())
          .borderRadius(12)
          .alignItems(HorizontalAlign.Center)
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#80000000')
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
        })
      }

      if (this.isBatchOperating) {
        Column() {
          Column() {
            LoadingProgress()
              .width(46)
              .height(46)
              .color(this.accentColor())

            Text(this.batchOperationText)
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.primaryTextColor())
              .margin({ top: 14 })

            Text('请稍候')
              .fontSize(13)
              .fontColor(this.subTextColor())
              .margin({ top: 6 })
          }
          .width(190)
          .padding({ left: 24, right: 24, top: 26, bottom: 24 })
          .backgroundColor(this.cardColor())
          .borderRadius(12)
          .alignItems(HorizontalAlign.Center)
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#80000000')
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageColor())
    .onAreaChange((_oldValue: Area, newValue: Area) => this.updateContextViewport(newValue))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  @Builder
  checkOptionsDialog() {
    Column() {
      Column({ space: 12 }) {
        Text('校验设置')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())
          .width('100%')

        Text('选择发现无效书源时的处理方式。禁用或删除会在每个书源校验结束后立即执行。')
          .fontSize(13)
          .fontColor(this.secondaryTextColor())
          .width('100%')

        this.checkActionOption('仅校验', '记录无效书源，校验完成后再手动处理', 'none')
        this.checkActionOption('自动禁用', '边校验边禁用无效书源，可稍后重新启用', 'disable')
        this.checkActionOption('自动删除', '边校验边永久删除无效书源，此操作不可恢复', 'delete', true)

        Row({ space: 10 }) {
          Button('取消')
            .layoutWeight(1)
            .height(42)
            .backgroundColor(this.inputColor())
            .fontColor(this.primaryTextColor())
            .onClick(() => {
              this.showCheckOptionsDialog = false;
            })

          Button('开始校验')
            .layoutWeight(1)
            .height(42)
            .backgroundColor(this.checkInvalidAction === 'delete' ? '#B71C1C' : this.buttonColor())
            .fontColor('#FFFFFF')
            .onClick(() => {
              this.startCheckEnabledSources(this.checkInvalidAction);
            })
        }
        .width('100%')
        .margin({ top: 4 })
      }
      .width('88%')
      .padding(22)
      .backgroundColor(this.cardColor())
      .borderRadius(14)
      .onClick(() => {
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#80000000')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.showCheckOptionsDialog = false;
    })
  }

  @Builder
  checkActionOption(title: string, description: string, action: string, danger: boolean = false) {
    Row() {
      Text(this.checkInvalidAction === action ? '●' : '○')
        .fontSize(20)
        .fontColor(this.checkInvalidAction === action ?
          (danger ? '#B71C1C' : this.accentColor()) : this.subTextColor())
        .width(28)

      Column() {
        Text(title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(danger ? '#B71C1C' : this.primaryTextColor())
        Text(description)
          .fontSize(12)
          .fontColor(this.subTextColor())
          .margin({ top: 3 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .borderRadius(9)
    .backgroundColor(this.checkInvalidAction === action ? this.inputColor() : this.cardColor())
    .border({
      width: this.checkInvalidAction === action ? 1 : 0.5,
      color: this.checkInvalidAction === action ? (danger ? '#B71C1C' : this.accentColor()) : this.glassBorderColor()
    })
    .onClick(() => {
      this.checkInvalidAction = action;
    })
  }

  @Builder
  sourceActionDialog() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.appDarkMode ? '#52000000' : '#26FFFFFF')
        .backdropBlur(18)
        .onClick(() => this.closeSourceActions())
      Column() {
        if (this.actionSourceNeedsLogin()) {
          this.contextActionItem('↗', this.actionSourceLoggedIn() ? '重新登录' : '登录',
            this.primaryTextColor(), () => this.openActionSourceLogin())
        }
        this.contextActionItem('✎', '修改', this.primaryTextColor(), () => this.openActionSourceEdit())
        this.contextActionItem('◉', this.actionSourceEnabled() ? '禁用' : '启用', this.primaryTextColor(),
          () => this.toggleActionSourceEnabled())
        this.contextActionItem('⌫', '删除', '#E53935', () => {
            this.showSourceActionDialog = false;
            this.showSourceDeleteDialog = true;
          })
      }
      .width(158)
      .padding({ top: 6, bottom: 6 })
      .backgroundColor(this.cardColor())
      .borderRadius(14)
      .border({ width: 1, color: this.glassBorderColor() })
      .shadow({ radius: 18, color: this.appDarkMode ? '#80000000' : '#33000000', offsetX: 0, offsetY: 7 })
      .position({
        x: this.contextMenuLeft(158),
        y: this.contextMenuTop(this.actionSourceNeedsLogin() ? 188 : 144)
      })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  contextActionItem(icon: string, label: string, color: string, action: () => void) {
    Row({ space: 10 }) {
      Text(icon)
        .fontSize(18)
        .fontColor(color)
        .width(24)
        .textAlign(TextAlign.Center)
      Text(label)
        .fontSize(15)
        .fontColor(color)
        .layoutWeight(1)
    }
    .width('100%')
    .height(44)
    .padding({ left: 12, right: 12 })
    .alignItems(VerticalAlign.Center)
    .onClick(action)
  }

  @Builder
  sourceDeleteDialog() {
    Column() {
      Column() {
        Text('删除书源')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())
          .width('100%')
          .textAlign(TextAlign.Center)

        Text(`确定删除“${this.actionSourceName()}”吗？删除后不可恢复。`)
          .fontSize(14)
          .fontColor(this.secondaryTextColor())
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ top: 12, bottom: 20 })

        Row({ space: 10 }) {
          Button('取消')
            .layoutWeight(1)
            .height(44)
            .backgroundColor(this.inputColor())
            .fontColor(this.primaryTextColor())
            .onClick(() => {
              this.showSourceDeleteDialog = false;
              this.actionSourceUrl = '';
            })

          Button('删除')
            .layoutWeight(1)
            .height(44)
            .backgroundColor('#B71C1C')
            .fontColor('#FFFFFF')
            .onClick(() => {
              this.deleteActionSource();
            })
        }
        .width('100%')
      }
      .width('86%')
      .padding(22)
      .backgroundColor(this.cardColor())
      .borderRadius(12)
      .onClick(() => {
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#80000000')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.showSourceDeleteDialog = false;
      this.actionSourceUrl = '';
    })
  }

  syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, this.pageColor());
  }

  pageColor(): string {
    return ThemeRuntime.pageColor(this.appDarkMode);
  }

  cardColor(): string {
    return ThemeRuntime.cardColor(this.appDarkMode);
  }

  glassCardColor(): string {
    return this.cardColor();
  }

  inputColor(): string {
    return ThemeRuntime.inputColor(this.appDarkMode);
  }

  glassInputColor(): string {
    return this.cardColor();
  }

  glassBorderColor(): string {
    return this.appDarkMode ? '#262A31' : '#FFFFFF';
  }

  glassShadowColor(): string {
    return '#00000000';
  }

  primaryTextColor(): string {
    return ThemeRuntime.primaryTextColor(this.appDarkMode);
  }

  secondaryTextColor(): string {
    return ThemeRuntime.subTextColor(this.appDarkMode);
  }

  subTextColor(): string {
    return ThemeRuntime.subTextColor(this.appDarkMode);
  }

  placeholderTextColor(): string {
    return ThemeRuntime.subTextColor(this.appDarkMode);
  }

  accentColor(): string {
    return ThemeRuntime.accentColor(this.appDarkMode);
  }

  buttonColor(): string {
    return ThemeRuntime.buttonColor(this.appDarkMode);
  }

  async searchSources() {
    if (!this.searchText) {
      await this.loadSources();
      return;
    }

    try {
      const db = AppDatabase.getInstance();
      this.sources = await db.searchBookSources(this.searchText);
      this.pruneSelectedSources();
    } catch (e) {
      console.error('搜索书源失败:', e);
    }
  }

  sourceNeedsLogin(source: BookSource): boolean {
    const loginUrl = String(source.loginUrl || '').trim();
    const loginUi = String(source.loginUi || '').trim();
    const loginCheckJs = String(source.loginCheckJs || '').trim();
    const loginHeader = String(source.loginHeader || '').trim();
    if (loginUrl || loginUi || loginCheckJs || loginHeader) {
      return true;
    }
    const rules = `${source.jsLib || ''}\n${source.searchUrl || ''}\n${source.exploreUrl || ''}\n` +
      `${source.bookInfoRule?.init || ''}\n${source.tocRule?.chapterList || ''}\n${source.contentRule?.content || ''}`;
    return /loginCheck|loginUrl|loginUi|book-source-login|请先登[录陆]|需要登[录陆]|账号登[录陆]|网页登录|登[录陆]后/i.test(rules);
  }

  sourceLoggedIn(source: BookSource): boolean {
    if (!this.sourceNeedsLogin(source)) {
      return false;
    }
    if (String(source.loginHeader || '').trim()) {
      return true;
    }
    const loginUrl = VerificationSupport.resolveBookSourceLoginUrl(source);
    const urls = [
      String(source.loginUrl || '').trim(),
      loginUrl,
      this.sourceUrlOrigin(loginUrl),
      String(source.bookSourceUrl || '').trim(),
      this.sourceUrlOrigin(String(source.bookSourceUrl || '').trim())
    ];
    for (const url of urls) {
      if (url && this.hasLoginCookie(CookieStore.getCookie(url))) {
        return true;
      }
    }
    return false;
  }

  hasLoginCookie(cookie: string): boolean {
    return VerificationSupport.hasEffectiveLoginCookie(cookie);
  }

  sourceUrlOrigin(url: string): string {
    const match = (url || '').match(/^(https?:\/\/[^/]+)/i);
    return match && match[1] ? match[1] : '';
  }

  openSourceActions(source: BookSource, event?: GestureEvent): void {
    const finger = event && event.fingerList.length > 0 ? event.fingerList[0] : undefined;
    if (finger) {
      this.contextMenuX = finger.globalX;
      this.contextMenuY = finger.globalY;
    }
    this.actionSourceUrl = source.bookSourceUrl;
    this.showSourceDeleteDialog = false;
    this.showSourceActionDialog = true;
  }

  updateContextViewport(area: Area): void {
    const width = Number(area.width);
    const height = Number(area.height);
    if (Number.isFinite(width) && width > 0) this.contextViewportWidth = width;
    if (Number.isFinite(height) && height > 0) this.contextViewportHeight = height;
  }

  contextMenuLeft(menuWidth: number): number {
    return Math.max(12, Math.min(this.contextMenuX - 18, this.contextViewportWidth - menuWidth - 12));
  }

  contextMenuTop(menuHeight: number): number {
    const below = this.contextMenuY + 12;
    if (below + menuHeight <= this.contextViewportHeight - 12) return below;
    return Math.max(this.statusBarHeight + 8, this.contextMenuY - menuHeight - 12);
  }

  closeSourceActions(): void {
    this.showSourceActionDialog = false;
    this.actionSourceUrl = '';
  }

  actionSource(): BookSource | null {
    return this.sources.find((source: BookSource) => source.bookSourceUrl === this.actionSourceUrl) || null;
  }

  actionSourceName(): string {
    const source = this.actionSource();
    return source ? (source.bookSourceName || source.bookSourceUrl) : '当前书源';
  }

  actionSourceNeedsLogin(): boolean {
    const source = this.actionSource();
    return source ? this.sourceNeedsLogin(source) : false;
  }

  actionSourceLoggedIn(): boolean {
    const source = this.actionSource();
    return source ? this.sourceLoggedIn(source) : false;
  }

  actionSourceEnabled(): boolean {
    const source = this.actionSource();
    return source ? source.enabled : false;
  }

  openActionSourceLogin(): void {
    const source = this.actionSource();
    if (!source || !this.sourceNeedsLogin(source)) {
      return;
    }
    this.showSourceActionDialog = false;
    if (this.sourceUsesEditorLogin(source)) {
      this.actionSourceUrl = '';
      router.pushUrl({
        url: 'pages/BookSourceEdit',
        params: { bookSourceUrl: source.bookSourceUrl }
      });
      return;
    }
    const loginEntryUrl = VerificationSupport.resolveBookSourceLoginUrl(source) ||
      VerificationSupport.pickVerificationUrl(source, source.bookSourceUrl);
    if (!loginEntryUrl || !/^https?:\/\//i.test(loginEntryUrl)) {
      this.actionSourceUrl = '';
      promptAction.showToast({ message: '未找到可用的网页登录地址，请检查书源登录配置' });
      return;
    }
    VerificationSupport.requestVerification(
      loginEntryUrl,
      `${source.bookSourceName || '书源'} 登录`,
      source
    );
    this.actionSourceUrl = '';
    router.pushUrl({
      url: 'pages/VerifyWeb',
      params: {
        url: loginEntryUrl,
        title: `${source.bookSourceName || '书源'} 登录`,
        requireLoginCookie: 'true'
      }
    });
  }

  sourceUsesEditorLogin(source: BookSource): boolean {
    const raw = `${source.bookSourceName || ''}\n${source.bookSourceUrl || ''}\n${source.loginUrl || ''}\n${source.jsLib || ''}`.toLowerCase();
    return raw.includes('书山') || raw.includes('shushan');
  }

  openActionSourceEdit(): void {
    const source = this.actionSource();
    if (!source) {
      return;
    }
    this.closeSourceActions();
    router.pushUrl({
      url: 'pages/BookSourceEdit',
      params: { bookSourceUrl: source.bookSourceUrl }
    });
  }

  async toggleActionSourceEnabled(): Promise<void> {
    const source = this.actionSource();
    if (!source) {
      return;
    }
    source.enabled = !source.enabled;
    await this.updateSource(source);
    this.sources = this.sources.map((item: BookSource) =>
      item.bookSourceUrl === source.bookSourceUrl ? source : item);
    this.closeSourceActions();
    promptAction.showToast({ message: source.enabled ? '书源已启用' : '书源已禁用' });
  }

  async deleteActionSource(): Promise<void> {
    const source = this.actionSource();
    if (!source || this.isBatchOperating) {
      return;
    }
    this.showSourceDeleteDialog = false;
    this.isBatchOperating = true;
    this.batchOperationText = '正在删除书源...';
    try {
      const db = AppDatabase.getInstance();
      await db.deleteBookSource(source.bookSourceUrl);
      this.sources = this.sources.filter((item: BookSource) => item.bookSourceUrl !== source.bookSourceUrl);
      this.actionSourceUrl = '';
      promptAction.showToast({ message: '书源已删除' });
    } catch (e) {
      console.error('删除书源失败:', e);
      promptAction.showToast({ message: '删除书源失败' });
    } finally {
      this.isBatchOperating = false;
    }
  }

  enterSelectionMode(): void {
    this.selectionMode = true;
    this.selectedSourceUrls = [];
  }

  exitSelectionMode(): void {
    this.selectionMode = false;
    this.selectedSourceUrls = [];
    this.showBatchDeleteDialog = false;
    this.showMoreActionDialog = false;
  }

  sourceListItemKey(source: BookSource): string {
    const loginStatus = this.sourceNeedsLogin(source) ? (this.sourceLoggedIn(source) ? 'logged' : 'unlogged') : 'none';
    return `${source.bookSourceUrl}_${source.bookSourceGroup || ''}_${source.enabled ? '1' : '0'}_${source.enabledExplore ? '1' : '0'}_${source.bookSourceName || ''}_${loginStatus}`;
  }

  isSourceSelected(bookSourceUrl: string): boolean {
    return this.selectedSourceUrls.includes(bookSourceUrl);
  }

  setSourceSelected(bookSourceUrl: string, selected: boolean): void {
    if (selected) {
      if (!this.isSourceSelected(bookSourceUrl)) {
        this.selectedSourceUrls = this.selectedSourceUrls.concat([bookSourceUrl]);
      }
      return;
    }
    this.selectedSourceUrls = this.selectedSourceUrls.filter((url: string) => url !== bookSourceUrl);
  }

  toggleSourceSelected(bookSourceUrl: string): void {
    this.setSourceSelected(bookSourceUrl, !this.isSourceSelected(bookSourceUrl));
  }

  isAllSelected(): boolean {
    return this.sources.length > 0 && this.selectedSourceUrls.length === this.sources.length;
  }

  selectAllSources(): void {
    this.selectedSourceUrls = this.sources.map((source: BookSource) => source.bookSourceUrl);
  }

  toggleAllSources(): void {
    if (this.isAllSelected()) {
      this.clearSelection();
      return;
    }
    this.selectAllSources();
  }

  clearSelection(): void {
    this.selectedSourceUrls = [];
  }

  pruneSelectedSources(): void {
    if (this.selectedSourceUrls.length === 0) {
      return;
    }
    const visibleUrls = this.sources.map((source: BookSource) => source.bookSourceUrl);
    this.selectedSourceUrls = this.selectedSourceUrls.filter((url: string) => visibleUrls.includes(url));
  }

  getSelectedSources(): BookSource[] {
    return this.sources.filter((source: BookSource) => this.isSourceSelected(source.bookSourceUrl));
  }

  getSourceGroups(): string[] {
    const groups: string[] = [];
    for (const source of this.sources) {
      const group = (source.bookSourceGroup || '').trim();
      if (group && !groups.includes(group)) {
        groups.push(group);
      }
    }
    return groups.sort((a: string, b: string) => a.localeCompare(b));
  }

  commonSelectedGroupName(): string {
    const selected = this.getSelectedSources();
    if (selected.length === 0) {
      return '';
    }
    const first = selected[0].bookSourceGroup || '';
    for (const source of selected) {
      if ((source.bookSourceGroup || '') !== first) {
        return '';
      }
    }
    return first;
  }

  async applySelectedSourceGroup(): Promise<void> {
    if (this.isBatchOperating) {
      return;
    }
    const selectedSources = this.getSelectedSources();
    if (selectedSources.length === 0) {
      promptAction.showToast({ message: '请先选择书源' });
      return;
    }

    const groupName = this.groupNameInput.trim();
    this.isBatchOperating = true;
    this.batchOperationText = '正在设置分组...';
    try {
      const db = AppDatabase.getInstance();
      for (const source of selectedSources) {
        source.bookSourceGroup = groupName;
        source.lastUpdateTime = Date.now();
        await db.updateBookSource(source);
      }
      this.sources = this.sources.map((source: BookSource) => {
        if (this.isSourceSelected(source.bookSourceUrl)) {
          source.bookSourceGroup = groupName;
        }
        return source;
      });
      this.showGroupDialog = false;
      promptAction.showToast({ message: groupName ? `已加入分组：${groupName}` : '已移出分组' });
    } catch (e) {
      console.error('设置书源分组失败:', e);
      promptAction.showToast({ message: '设置分组失败' });
    } finally {
      this.isBatchOperating = false;
    }
  }

  async batchSetEnabled(enabled: boolean): Promise<void> {
    if (this.isBatchOperating) {
      return;
    }
    const selectedSources = this.getSelectedSources();
    if (selectedSources.length === 0) {
      promptAction.showToast({ message: '请先选择书源' });
      return;
    }

    this.isBatchOperating = true;
    this.batchOperationText = enabled ? '正在启用书源...' : '正在禁用书源...';
    try {
      const db = AppDatabase.getInstance();
      for (const source of selectedSources) {
        source.enabled = enabled;
        source.lastUpdateTime = Date.now();
        await db.updateBookSource(source);
      }
      this.sources = this.sources.map((source: BookSource) => {
        if (this.isSourceSelected(source.bookSourceUrl)) {
          source.enabled = enabled;
        }
        return source;
      });
      promptAction.showToast({ message: `已${enabled ? '启用' : '禁用'} ${selectedSources.length} 个书源` });
    } catch (e) {
      console.error('批量更新书源失败:', e);
      promptAction.showToast({ message: '批量操作失败' });
    } finally {
      this.isBatchOperating = false;
    }
  }

  async batchSetExploreEnabled(enabled: boolean): Promise<void> {
    if (this.isBatchOperating) {
      return;
    }
    const selectedSources = this.getSelectedSources();
    if (selectedSources.length === 0) {
      promptAction.showToast({ message: '请先选择书源' });
      return;
    }

    this.isBatchOperating = true;
    this.batchOperationText = enabled ? '正在启用发现...' : '正在禁用发现...';
    try {
      const db = AppDatabase.getInstance();
      for (const source of selectedSources) {
        source.enabledExplore = enabled;
        source.lastUpdateTime = Date.now();
        await db.updateBookSource(source);
      }
      this.sources = this.sources.map((source: BookSource) => {
        if (this.isSourceSelected(source.bookSourceUrl)) {
          source.enabledExplore = enabled;
        }
        return source;
      });
      promptAction.showToast({ message: `已${enabled ? '启用' : '禁用'} ${selectedSources.length} 个书源的发现` });
    } catch (e) {
      console.error('批量更新发现状态失败:', e);
      promptAction.showToast({ message: '批量操作失败' });
    } finally {
      this.isBatchOperating = false;
    }
  }

  async batchDeleteSelectedSources(): Promise<void> {
    if (this.isBatchOperating) {
      return;
    }
    const selectedUrls = this.selectedSourceUrls.slice();
    if (selectedUrls.length === 0) {
      promptAction.showToast({ message: '请先选择书源' });
      return;
    }

    this.isBatchOperating = true;
    this.batchOperationText = '正在删除书源...';
    try {
      const db = AppDatabase.getInstance();
      for (const url of selectedUrls) {
        await db.deleteBookSource(url);
      }
      this.selectedSourceUrls = [];
      await this.loadSources();
      this.selectionMode = false;
      promptAction.showToast({ message: `已删除 ${selectedUrls.length} 个书源` });
    } catch (e) {
      console.error('批量删除书源失败:', e);
      promptAction.showToast({ message: '批量删除失败' });
    } finally {
      this.isBatchOperating = false;
    }
  }

  async updateSource(source: BookSource) {
    try {
      const db = AppDatabase.getInstance();
      await db.updateBookSource(source);
    } catch (e) {
      console.error('更新书源失败:', e);
    }
  }

  openCheckOptions(): void {
    if (this.selectionMode) {
      return;
    }
    if (this.isCheckingSources) {
      promptAction.showToast({ message: '正在校验中' });
      return;
    }
    this.showCheckOptionsDialog = true;
  }

  async startCheckEnabledSources(action: string = 'none'): Promise<void> {
    if (this.selectionMode) {
      return;
    }
    if (this.isCheckingSources) {
      promptAction.showToast({ message: '正在校验中' });
      return;
    }

    this.checkInvalidAction = action === 'disable' || action === 'delete' ? action : 'none';
    this.showCheckOptionsDialog = false;

    const db = AppDatabase.getInstance();
    const enabledSources = await db.getEnabledBookSources();
    if (enabledSources.length === 0) {
      promptAction.showToast({ message: '暂无启用书源' });
      return;
    }

    this.showCheckDialog = true;
    this.isCheckingSources = true;
    this.checkDone = 0;
    this.checkTotal = enabledSources.length;
    this.checkOkCount = 0;
    this.checkBadUrls = [];
    this.checkBadNames = [];
    this.checkAutoHandledCount = 0;
    this.checkStatus = `准备校验 ${enabledSources.length} 个启用书源`;
    const availableUrls = new Set<string>();

    try {
      const coordinator = new SearchCoordinator(SearchExploreSettingsStore.getSearchConcurrency());
      await coordinator.search(BOOK_SOURCE_CHECK_KEYWORD, (progress: SearchProgress) => {
        this.checkDone = progress.done;
        this.checkTotal = progress.total;
        this.checkStatus = this.formatCheckProgressStatus(progress);
      }, {
        onSourceComplete: async (source: BookSource, books: SearchBook[]) => {
          if (books.length > 0) {
            availableUrls.add(source.bookSourceUrl);
          }
          await this.handleCheckedSourceCompletion(source, books.length > 0);
        },
        validationOnly: true
      });

      const badSources = enabledSources.filter((source: BookSource) => !availableUrls.has(source.bookSourceUrl));
      this.checkOkCount = Math.max(0, enabledSources.length - badSources.length);
      this.checkBadUrls = badSources.map((source: BookSource) => source.bookSourceUrl);
      this.checkBadNames = badSources.map((source: BookSource) => source.bookSourceName || source.bookSourceUrl);
      this.checkDone = enabledSources.length;
      this.checkTotal = enabledSources.length;
      this.checkStatus = this.checkSummaryText();
    } catch (e) {
      console.error('校验书源失败:', e);
      this.checkStatus = '校验失败，请稍后重试';
      promptAction.showToast({ message: '校验失败' });
    } finally {
      this.isCheckingSources = false;
      if (this.checkInvalidAction !== 'none') {
        await this.loadSources();
      }
    }
  }

  async handleCheckedSourceCompletion(source: BookSource, available: boolean): Promise<void> {
    if (available) {
      this.checkOkCount++;
      return;
    }
    if (!this.checkBadUrls.includes(source.bookSourceUrl)) {
      this.checkBadUrls = [...this.checkBadUrls, source.bookSourceUrl];
      this.checkBadNames = [...this.checkBadNames, source.bookSourceName || source.bookSourceUrl];
    }
    if (this.checkInvalidAction === 'none') {
      return;
    }

    try {
      const db = AppDatabase.getInstance();
      if (this.checkInvalidAction === 'disable') {
        source.enabled = false;
        source.lastUpdateTime = Date.now();
        await db.updateBookSource(source);
        this.sources = this.sources.map((item: BookSource) =>
          item.bookSourceUrl === source.bookSourceUrl ? source : item);
      } else if (this.checkInvalidAction === 'delete') {
        await db.deleteBookSource(source.bookSourceUrl);
        this.sources = this.sources.filter((item: BookSource) => item.bookSourceUrl !== source.bookSourceUrl);
      }
      this.checkAutoHandledCount++;
    } catch (e) {
      console.error(`自动${this.checkInvalidAction === 'delete' ? '删除' : '禁用'}无效书源失败:`, e);
    }
  }

  checkSummaryText(): string {
    return `已校验 ${this.checkTotal} 个启用书源${this.checkAutoActionSummary()}`;
  }

  formatCheckProgressStatus(progress: SearchProgress): string {
    const verifyText = progress.needVerification ? '；有书源需要网页验证' : '';
    return `已校验 ${progress.done}/${progress.total}${this.checkAutoActionSummary()}${verifyText}`;
  }

  checkAutoActionSummary(): string {
    if (this.checkInvalidAction === 'disable') {
      return `，已自动禁用 ${this.checkAutoHandledCount} 个`;
    }
    if (this.checkInvalidAction === 'delete') {
      return `，已自动删除 ${this.checkAutoHandledCount} 个`;
    }
    return '';
  }

  checkResultText(): string {
    if (this.checkTotal === 0) {
      return '没有需要校验的启用书源';
    }
    if (this.checkBadUrls.length === 0) {
      return `全部可用，共 ${this.checkOkCount} 个书源通过校验`;
    }
    return `可用 ${this.checkOkCount} 个，异常 ${this.checkBadUrls.length} 个${this.checkAutoActionSummary()}`;
  }

  async disableFailedCheckedSources(): Promise<void> {
    if (this.isBatchOperating) {
      return;
    }
    if (this.checkBadUrls.length === 0) {
      return;
    }

    this.isBatchOperating = true;
    this.batchOperationText = '正在禁用书源...';
    try {
      const db = AppDatabase.getInstance();
      for (const url of this.checkBadUrls) {
        const source = await db.getBookSource(url);
        if (source) {
          source.enabled = false;
          source.lastUpdateTime = Date.now();
          await db.updateBookSource(source);
        }
      }
      const disabledCount = this.checkBadUrls.length;
      this.showCheckDialog = false;
      await this.loadSources();
      promptAction.showToast({ message: `已禁用 ${disabledCount} 个异常书源` });
    } catch (e) {
      console.error('禁用异常书源失败:', e);
      promptAction.showToast({ message: '禁用失败' });
    } finally {
      this.isBatchOperating = false;
    }
  }

  async deleteFailedCheckedSources(): Promise<void> {
    if (this.isBatchOperating) {
      return;
    }
    const failedUrls = this.checkBadUrls.slice();
    if (failedUrls.length === 0) {
      return;
    }

    this.isBatchOperating = true;
    this.batchOperationText = '正在删除书源...';
    try {
      const db = AppDatabase.getInstance();
      for (const url of failedUrls) {
        await db.deleteBookSource(url);
      }
      this.checkBadUrls = [];
      this.checkBadNames = [];
      this.showCheckDialog = false;
      await this.loadSources();
      promptAction.showToast({ message: `已删除 ${failedUrls.length} 个异常书源` });
    } catch (e) {
      console.error('删除异常书源失败:', e);
      promptAction.showToast({ message: '删除失败' });
    } finally {
      this.isBatchOperating = false;
    }
  }

  async importFromFile() {
    try {
      const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = ['JSON|.json', '文本|.txt'];
      const pickerResult: Array<string> = await new picker.DocumentViewPicker().select(options);

      if (!pickerResult || pickerResult.length === 0) {
        return;
      }

      this.isImporting = true;
      const content = await this.readTextFile(pickerResult[0]);
      if (!content.trim()) {
        promptAction.showToast({ message: '文件内容为空' });
        return;
      }
      await this.importSourcesFromJson(content);
    } catch (e) {
      console.error('从文件导入失败:', e);
      const errMsg = e instanceof Error ? e.message : String(e);
      promptAction.showToast({ message: `导入失败: ${errMsg}` });
    } finally {
      this.isImporting = false;
    }
  }

  async exportSelectedSources(): Promise<void> {
    if (this.selectedSourceUrls.length === 0 || this.isBatchOperating) {
      promptAction.showToast({ message: '请先选择书源' });
      return;
    }
    const selected = this.sources.filter((source: BookSource) =>
      this.selectedSourceUrls.includes(source.bookSourceUrl));
    if (selected.length === 0) {
      promptAction.showToast({ message: '未找到可导出的书源' });
      return;
    }

    let file: fs.File | null = null;
    try {
      const options: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
      options.newFileNames = [`legado_book_sources_${this.exportTimestamp()}.json`];
      options.fileSuffixChoices = ['JSON 文件|.json'];
      const result = await new picker.DocumentViewPicker(getContext(this)).save(options);
      if (!result || result.length === 0) {
        return;
      }

      this.isBatchOperating = true;
      this.batchOperationText = '正在导出书源...';
      const json = JSON.stringify(selected, null, 2);
      const bytes = new util.TextEncoder().encodeInto(json);
      file = await fs.open(result[0], fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      await fs.write(file.fd, bytes.buffer, { offset: 0, length: bytes.byteLength });
      await fs.close(file);
      file = null;
      promptAction.showToast({ message: `已导出 ${selected.length} 个书源` });
    } catch (e) {
      console.error('导出书源失败:', e);
      const message = e instanceof Error ? e.message : String(e);
      promptAction.showToast({ message: `导出失败: ${message}` });
    } finally {
      if (file) {
        try {
          await fs.close(file);
        } catch (_) {
        }
      }
      this.isBatchOperating = false;
      this.batchOperationText = '正在操作书源...';
    }
  }

  exportTimestamp(): string {
    const date = new Date();
    const pad = (value: number): string => value < 10 ? `0${value}` : `${value}`;
    return `${date.getFullYear()}${pad(date.getMonth() + 1)}${pad(date.getDate())}_` +
      `${pad(date.getHours())}${pad(date.getMinutes())}`;
  }

  async readTextFile(filePath: string): Promise<string> {
    let file: fs.File | null = null;
    try {
      const stat = await fs.stat(filePath);
      if (stat.size <= 0) {
        return '';
      }
      if (stat.size > BOOK_SOURCE_IMPORT_FILE_LIMIT_BYTES) {
        throw new Error('文件过大，请选择 25MB 以内的书源文件');
      }

      file = await fs.open(filePath, fs.OpenMode.READ_ONLY);
      const buffer = new ArrayBuffer(stat.size);
      await fs.read(file.fd, buffer, { offset: 0, length: stat.size });
      const text = util.TextDecoder.create('utf-8').decodeWithStream(new Uint8Array(buffer), { stream: false });
      return text.replace(/^\uFEFF/, '');
    } finally {
      if (file) {
        await fs.close(file);
      }
    }
  }

  async importFromUrl() {
    const url = this.importUrl.trim();
    if (!url) {
      promptAction.showToast({ message: '请输入URL' });
      return;
    }

    try {
      this.isImporting = true;
      const content = await this.fetchImportUrlBody(url);
      await this.importSourcesFromJson(content);
      this.showImportUrlDialog = false;
      this.importUrl = '';
    } catch (e) {
      console.error('从URL导入失败:', e);
      const errMsg = e instanceof Error ? e.message : String(e);
      promptAction.showToast({ message: `导入失败: ${errMsg}` });
    } finally {
      this.isImporting = false;
    }
  }

  async fetchImportUrlBody(url: string): Promise<string> {
    let lastError = '';
    for (let attempt = 1; attempt <= BOOK_SOURCE_IMPORT_URL_RETRY_COUNT; attempt++) {
      const response = await new HttpClient(BOOK_SOURCE_IMPORT_TIMEOUT_MS).execute({
        url,
        method: 'GET',
        headers: {},
        connectTimeout: BOOK_SOURCE_IMPORT_TIMEOUT_MS,
        readTimeout: BOOK_SOURCE_IMPORT_TIMEOUT_MS
      });
      if (response.success && this.looksLikeBookSourceJson(response.body)) {
        return response.body.replace(/^\uFEFF/, '');
      }
      lastError = response.success ? '响应内容不是有效书源JSON' : (response.error || `HTTP ${response.statusCode}`);
      if (attempt < BOOK_SOURCE_IMPORT_URL_RETRY_COUNT) {
        await new Promise<void>((resolve) => setTimeout(resolve, attempt * 500));
      }
    }
    throw new Error(lastError || '获取书源失败');
  }

  looksLikeBookSourceJson(body: string): boolean {
    const text = (body || '').replace(/^\uFEFF/, '').replace(/^\s+/, '');
    return text.startsWith('[') || text.startsWith('{');
  }

  async importSourcesFromJson(json: string) {
    try {
      console.log('开始解析JSON，长度:', json.length);
      let sources: BookSource[] = [];

      const parsed: Object = JSON.parse(json);
      console.log('JSON解析成功，类型:', typeof parsed);

      // 处理 {"value": [...]} 结构
      let items: Record<string, Object>[] = [];
      if (Array.isArray(parsed)) {
        items = parsed as Record<string, Object>[];
      } else if (typeof parsed === 'object') {
        const obj = parsed as Record<string, Object>;
        if (Array.isArray(obj['value'])) {
          items = obj['value'] as Record<string, Object>[];
        } else if (obj['bookSourceUrl']) {
          items = [obj];
        }
      }

      console.log('待解析书源数量:', items.length);

      for (const item of items) {
        const source = this.parseBookSource(item);
        if (source.bookSourceUrl) {
          sources.push(source);
        }
      }

      console.log('解析到书源数量:', sources.length);

      if (sources.length === 0) {
        promptAction.showToast({ message: '未找到有效的书源' });
        return;
      }

      const db = AppDatabase.getInstance();
      let importCount = 0;
      for (const source of sources) {
        if (source.bookSourceUrl && source.bookSourceName) {
          try {
            await db.insertBookSource(source);
            importCount++;
          } catch (insertErr) {
            console.error('插入书源失败:', source.bookSourceName, insertErr);
          }
        }
      }

      const loginCount = sources.filter((source: BookSource) => this.sourceNeedsLogin(source)).length;
      const loginMessage = loginCount > 0 ? `，其中 ${loginCount} 个需要登录` : '';
      promptAction.showToast({ message: `成功导入 ${importCount} 个书源${loginMessage}` });
      await this.loadSources();
    } catch (e) {
      console.error('解析书源失败:', e);
      const errMsg = e instanceof Error ? e.message : String(e);
      promptAction.showToast({ message: `书源格式错误: ${errMsg}` });
    }
  }

  parseBookSource(obj: Record<string, Object>): BookSource {
    const source = new BookSource();
    source.bookSourceUrl = obj['bookSourceUrl'] as string || '';
    source.bookSourceName = obj['bookSourceName'] as string || '';
    source.bookSourceGroup = obj['bookSourceGroup'] as string || '';
    source.bookSourceComment = obj['bookSourceComment'] as string || '';
    source.loginUrl = obj['loginUrl'] as string || '';
    source.loginUi = obj['loginUi'] as string || '';
    source.loginCheckJs = obj['loginCheckJs'] as string || '';
    source.loginHeader = obj['loginHeader'] as string || '';
    source.bookUrlPattern = obj['bookUrlPattern'] as string || '';
    source.searchUrl = obj['searchUrl'] as string || '';
    source.exploreUrl = obj['exploreUrl'] as string || '';
    source.jsLib = obj['jsLib'] as string || '';
    source.header = obj['header'] as string || '';
    source.variableComment = obj['variableComment'] as string || obj['variable'] as string || '';
    source.enabled = obj['enabled'] !== false;
    source.enabledExplore = obj['enabledExplore'] !== false;
    source.weight = (obj['weight'] as number) || 0;
    source.lastUpdateTime = Date.now();

    // 解析 searchRule (ruleSearch)
    const ruleSearch = obj['ruleSearch'];
    if (ruleSearch && typeof ruleSearch === 'string') {
      const fields = this.parseCompactRule(ruleSearch as string);
      const rule = new SearchRule();
      this.applyRuleToSearchRule(fields, rule);
      source.searchRule = rule;
    } else if (ruleSearch && typeof ruleSearch === 'object') {
      source.searchRule = ruleSearch as SearchRule;
    } else if (obj['searchRule'] && typeof obj['searchRule'] === 'object') {
      source.searchRule = obj['searchRule'] as SearchRule;
    }

    // 解析 exploreRule (ruleExplore)
    const ruleExplore = obj['ruleExplore'];
    if (ruleExplore && typeof ruleExplore === 'string') {
      const fields = this.parseCompactRule(ruleExplore as string);
      const rule = new ExploreRule();
      this.applyRuleToSearchRule(fields, rule);
      source.exploreRule = rule;
    } else if (ruleExplore && typeof ruleExplore === 'object') {
      source.exploreRule = ruleExplore as ExploreRule;
    } else if (obj['exploreRule'] && typeof obj['exploreRule'] === 'object') {
      source.exploreRule = obj['exploreRule'] as ExploreRule;
    }

    // 解析 bookInfoRule (ruleBookInfo)
    const ruleBookInfo = obj['ruleBookInfo'];
    if (ruleBookInfo && typeof ruleBookInfo === 'string') {
      const fields = this.parseCompactRule(ruleBookInfo as string);
      const rule = new BookInfoRule();
      this.applyRuleToBookInfoRule(fields, rule);
      source.bookInfoRule = rule;
    } else if (ruleBookInfo && typeof ruleBookInfo === 'object') {
      source.bookInfoRule = ruleBookInfo as BookInfoRule;
    } else if (obj['bookInfoRule'] && typeof obj['bookInfoRule'] === 'object') {
      source.bookInfoRule = obj['bookInfoRule'] as BookInfoRule;
    }

    // 解析 tocRule (ruleToc)
    const ruleToc = obj['ruleToc'];
    if (ruleToc && typeof ruleToc === 'string') {
      const fields = this.parseCompactRule(ruleToc as string);
      const rule = new TocRule();
      this.applyRuleToTocRule(fields, rule);
      source.tocRule = rule;
    } else if (ruleToc && typeof ruleToc === 'object') {
      source.tocRule = ruleToc as TocRule;
    } else if (obj['tocRule'] && typeof obj['tocRule'] === 'object') {
      source.tocRule = obj['tocRule'] as TocRule;
    }

    // 解析 contentRule (ruleContent)
    const ruleContent = obj['ruleContent'];
    if (ruleContent && typeof ruleContent === 'string') {
      const fields = this.parseCompactRule(ruleContent as string);
      const rule = new ContentRule();
      this.applyRuleToContentRule(fields, rule);
      source.contentRule = rule;
    } else if (ruleContent && typeof ruleContent === 'object') {
      source.contentRule = ruleContent as ContentRule;
    } else if (obj['contentRule'] && typeof obj['contentRule'] === 'object') {
      source.contentRule = obj['contentRule'] as ContentRule;
    }

    return source;
  }

  parseCompactRule(ruleStr: string): Record<string, string> {
    const result: Record<string, string> = {};

    let content = ruleStr.trim();
    if (content.startsWith('@{')) {
      content = content.substring(2);
    }
    if (content.endsWith('}')) {
      content = content.substring(0, content.length - 1);
    }

    let depth = 0;
    let inString = false;
    let stringChar = '';
    let inJsValue = false; // 是否在 @js: 值内部

    const pairs: string[] = [];
    let current = '';

    for (let i = 0; i < content.length; i++) {
      const ch = content[i];

      if (inString) {
        current += ch;
        if (ch === '\\') {
          i++;
          if (i < content.length) current += content[i];
        } else if (ch === stringChar) {
          inString = false;
        }
        continue;
      }

      if (ch === '"' || ch === "'") {
        inString = true;
        stringChar = ch;
        current += ch;
        continue;
      }

      if (ch === '(' || ch === '[' || ch === '{') {
        depth++;
        current += ch;
        continue;
      }

      if (ch === ')' || ch === ']' || ch === '}') {
        if (depth > 0) depth--;
        current += ch;
        continue;
      }

      // 检测当前是否在 @js: 值中（值以 @js: 开头时禁用分号拆分）
      if (!inJsValue && current.trim().includes('=@js:')) {
        inJsValue = true;
      }

      // 在非 @js: 值中，分号且深度为0时作为分隔符
      if (ch === ';' && depth === 0 && !inJsValue) {
        pairs.push(current.trim());
        current = '';
        continue;
      }

      // 在 @js: 值中，分号+换行可能表示新字段开始
      if (ch === ';' && depth === 0 && inJsValue) {
        // 检查后续是否是新字段: ;\s*keyword=
        const rest = content.substring(i + 1);
        const nextFieldMatch = rest.match(/^\s*(\w+)=/);
        if (nextFieldMatch) {
          // 是新字段开始，结束当前 @js: 值
          pairs.push(current.trim());
          current = '';
          inJsValue = false;
          // 跳过空白
          while (i + 1 < content.length && (content[i + 1] === ' ' || content[i + 1] === '\n' || content[i + 1] === '\r')) {
            i++;
          }
          continue;
        }
      }

      current += ch;
    }

    if (current.trim()) {
      pairs.push(current.trim());
    }

    for (const pair of pairs) {
      const eqIdx = pair.indexOf('=');
      if (eqIdx > 0) {
        const field = pair.substring(0, eqIdx).trim();
        let value = pair.substring(eqIdx + 1).trim();

        if ((value.startsWith('"') && value.endsWith('"')) ||
          (value.startsWith("'") && value.endsWith("'"))) {
          value = value.substring(1, value.length - 1);
        }

        result[field] = value;
      }
    }

    return result;
  }

  applyRuleToSearchRule(fields: Record<string, string>, rule: SearchRule): void {
    rule.bookList = fields['bookList'] || fields['booklist'] || '';
    rule.name = fields['name'] || '';
    rule.author = fields['author'] || '';
    rule.coverUrl = fields['coverUrl'] || '';
    rule.intro = fields['intro'] || fields['desc'] || '';
    rule.kind = fields['kind'] || '';
    rule.lastChapter = fields['lastChapter'] || fields['lastchapter'] || '';
    rule.bookUrl = fields['bookUrl'] || fields['bookurl'] || '';
    rule.wordCount = fields['wordCount'] || fields['wordcount'] || '';
  }

  applyRuleToTocRule(fields: Record<string, string>, rule: TocRule): void {
    rule.chapterList = fields['chapterList'] || fields['chapterlist'] || '';
    rule.chapterName = fields['chapterName'] || fields['chaptername'] || '';
    rule.chapterUrl = fields['chapterUrl'] || fields['chapterurl'] || '';
    rule.isVip = fields['isVip'] || fields['isvip'] || '';
    rule.isPay = fields['isPay'] || fields['ispay'] || '';
    rule.updateTime = fields['updateTime'] || fields['updatetime'] || '';
  }

  applyRuleToContentRule(fields: Record<string, string>, rule: ContentRule): void {
    rule.content = fields['content'] || '';
    rule.title = fields['title'] || '';
    rule.images = fields['images'] || '';
    rule.replaceRegex = fields['replaceRegex'] || fields['replaceregex'] || '';
    rule.imageStyle = fields['imageStyle'] || fields['imagestyle'] || '';
    rule.payAction = fields['payAction'] || fields['payaction'] || '';
  }

  applyRuleToBookInfoRule(fields: Record<string, string>, rule: BookInfoRule): void {
    rule.init = fields['init'] || '';
    rule.name = fields['name'] || '';
    rule.author = fields['author'] || '';
    rule.coverUrl = fields['coverUrl'] || '';
    rule.intro = fields['intro'] || fields['desc'] || '';
    rule.kind = fields['kind'] || '';
    rule.lastChapter = fields['lastChapter'] || fields['lastchapter'] || '';
    rule.wordCount = fields['wordCount'] || fields['wordcount'] || '';
    rule.updateTime = fields['updateTime'] || fields['updatetime'] || '';
    rule.tocUrl = fields['tocUrl'] || fields['tocurl'] || '';
  }
}
