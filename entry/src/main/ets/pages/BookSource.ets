import { router, promptAction } from '@kit.ArkUI';
import { BookSource, SearchBook, BookListRule, SearchRule, ExploreRule, BookInfoRule, TocRule, ContentRule } from '../model/data/Book';
import { AppDatabase } from '../model/data/AppDatabase';
import { HttpClient } from '../core/http/HttpClient';
import { SearchCoordinator, SearchProgress } from '../core/book/SearchCoordinator';
import { syncSystemBars } from '../utils/SystemBars';
import picker from '@ohos.file.picker';
import fs from '@ohos.file.fs';
import { util } from '@kit.ArkTS';

const BOOK_SOURCE_IMPORT_FILE_LIMIT_BYTES = 25 * 1024 * 1024;
const BOOK_SOURCE_IMPORT_TIMEOUT_MS = 20000;
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
  @State groupNameInput: string = '';
  @State importUrl: string = '';
  @State isImporting: boolean = false;
  @State showCheckDialog: boolean = false;
  @State isCheckingSources: boolean = false;
  @State checkDone: number = 0;
  @State checkTotal: number = 0;
  @State checkOkCount: number = 0;
  @State checkBadUrls: string[] = [];
  @State checkBadNames: string[] = [];
  @State checkStatus: string = '';

  aboutToAppear() {
    this.syncBars();
    this.loadSources();
  }

  onPageShow(): void {
    this.syncBars();
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
            .fontColor(this.primaryTextColor())
            .width(52)
            .height(56)
            .textAlign(TextAlign.Center)
            .onClick(() => {
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
                this.startCheckEnabledSources();
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
                this.toggleAllSources();
              })

            Text(`已选择 ${this.selectedSourceUrls.length}/${this.sources.length}`)
              .fontSize(14)
              .fontColor(this.secondaryTextColor())
              .margin({ left: 8 })
              .layoutWeight(1)

            Text(this.isAllSelected() ? '取消全选' : '全选')
              .fontSize(14)
              .fontColor(this.accentColor())
              .onClick(() => {
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
                      .margin({ right: 12 })
                      .onChange((isOn: boolean) => {
                        this.setSourceSelected(source.bookSourceUrl, isOn);
                      })
                  }

                  Column() {
                    Text(source.bookSourceName)
                      .fontSize(16)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(this.primaryTextColor())
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })

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

                      Text('编辑')
                        .fontSize(12)
                        .fontColor(this.accentColor())
                        .margin({ top: 8 })
                        .onClick(() => {
                          router.pushUrl({
                            url: 'pages/BookSourceEdit',
                            params: { bookSourceUrl: source.bookSourceUrl }
                          });
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
                .onClick(() => {
                  if (this.selectionMode) {
                    this.toggleSourceSelected(source.bookSourceUrl);
                  } else {
                    router.pushUrl({
                      url: 'pages/BookSourceEdit',
                      params: { bookSourceUrl: source.bookSourceUrl }
                    });
                  }
                })
              }
            })
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
              .enabled(this.selectedSourceUrls.length > 0)
              .backgroundColor(this.buttonColor())
              .fontColor('#FFFFFF')
              .onClick(() => {
                this.batchSetEnabled(true);
              })

            Button('禁用')
              .layoutWeight(1)
              .height(42)
              .margin({ left: 8 })
              .enabled(this.selectedSourceUrls.length > 0)
              .backgroundColor(this.inputColor())
              .fontColor(this.primaryTextColor())
              .onClick(() => {
                this.batchSetEnabled(false);
              })

            Button('分组')
              .layoutWeight(1)
              .height(42)
              .margin({ left: 8 })
              .enabled(this.selectedSourceUrls.length > 0)
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
              .enabled(this.selectedSourceUrls.length > 0)
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
                Column() {
                  ForEach(this.checkBadNames, (name: string) => {
                    Text(name)
                      .fontSize(13)
                      .fontColor(this.subTextColor())
                      .width('100%')
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .margin({ bottom: 6 })
                  }, (name: string) => name)
                }
                .width('100%')
                .constraintSize({ maxHeight: 120 })
                .padding(10)
                .backgroundColor(this.inputColor())
                .borderRadius(8)
                .margin({ bottom: 16 })
              }

              Row() {
                Button('一键禁用')
                  .width('45%')
                  .height(44)
                  .enabled(this.checkBadUrls.length > 0)
                  .backgroundColor(this.checkBadUrls.length > 0 ? '#E53935' : this.inputColor())
                  .fontColor(this.checkBadUrls.length > 0 ? '#FFFFFF' : this.subTextColor())
                  .onClick(() => {
                    this.disableFailedCheckedSources();
                  })

                Button('取消')
                  .width('45%')
                  .height(44)
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
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.statusBarHeight, bottom: this.navBarHeight })
    .backgroundColor(this.pageColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, this.pageColor());
  }

  pageColor(): string {
    return this.appDarkMode ? '#101113' : '#F5F5F5';
  }

  cardColor(): string {
    return this.appDarkMode ? '#191B1F' : '#FFFFFF';
  }

  glassCardColor(): string {
    return this.cardColor();
  }

  inputColor(): string {
    return this.appDarkMode ? '#24272D' : '#F5F5F5';
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
    return this.appDarkMode ? '#F2F3F5' : '#1F1F1F';
  }

  secondaryTextColor(): string {
    return this.appDarkMode ? '#B8BDC7' : '#666666';
  }

  subTextColor(): string {
    return this.appDarkMode ? '#8A8F98' : '#999999';
  }

  placeholderTextColor(): string {
    return this.appDarkMode ? '#6F7480' : '#999999';
  }

  accentColor(): string {
    return this.appDarkMode ? this.appDarkAccentColor : this.appLightAccentColor;
  }

  buttonColor(): string {
    return this.appDarkMode ? this.appDarkButtonColor : this.appLightButtonColor;
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
    const selectedSources = this.getSelectedSources();
    if (selectedSources.length === 0) {
      promptAction.showToast({ message: '请先选择书源' });
      return;
    }

    const groupName = this.groupNameInput.trim();
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
    }
  }

  async batchSetEnabled(enabled: boolean): Promise<void> {
    const selectedSources = this.getSelectedSources();
    if (selectedSources.length === 0) {
      promptAction.showToast({ message: '请先选择书源' });
      return;
    }

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
    }
  }

  async batchSetExploreEnabled(enabled: boolean): Promise<void> {
    const selectedSources = this.getSelectedSources();
    if (selectedSources.length === 0) {
      promptAction.showToast({ message: '请先选择书源' });
      return;
    }

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
    }
  }

  async batchDeleteSelectedSources(): Promise<void> {
    const selectedUrls = this.selectedSourceUrls.slice();
    if (selectedUrls.length === 0) {
      promptAction.showToast({ message: '请先选择书源' });
      return;
    }

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

  async startCheckEnabledSources(): Promise<void> {
    if (this.selectionMode) {
      return;
    }
    if (this.isCheckingSources) {
      promptAction.showToast({ message: '正在校验中' });
      return;
    }

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
    this.checkStatus = `准备校验 ${enabledSources.length} 个启用书源`;

    try {
      const coordinator = new SearchCoordinator(8);
      const results = await coordinator.search(BOOK_SOURCE_CHECK_KEYWORD, (progress: SearchProgress) => {
        this.checkDone = progress.done;
        this.checkTotal = progress.total;
        this.checkStatus = this.formatCheckProgressStatus(progress);
      });

      const okUrls = this.uniqueResultOrigins(results);
      const badSources = enabledSources.filter((source: BookSource) => !okUrls.includes(source.bookSourceUrl));
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
    }
  }

  uniqueResultOrigins(results: SearchBook[]): string[] {
    const origins: string[] = [];
    for (const book of results) {
      const origin = book.origin || '';
      if (origin && !origins.includes(origin)) {
        origins.push(origin);
      }
    }
    return origins;
  }

  checkSummaryText(): string {
    return `已校验 ${this.checkTotal} 个启用书源`;
  }

  formatCheckProgressStatus(progress: SearchProgress): string {
    const verifyText = progress.needVerification ? '；有书源需要网页验证' : '';
    return `已校验 ${progress.done}/${progress.total}，命中 ${progress.results.length} 本${verifyText}`;
  }

  checkResultText(): string {
    if (this.checkTotal === 0) {
      return '没有需要校验的启用书源';
    }
    if (this.checkBadUrls.length === 0) {
      return `全部可用，共 ${this.checkOkCount} 个书源通过校验`;
    }
    return `可用 ${this.checkOkCount} 个，异常 ${this.checkBadUrls.length} 个`;
  }

  async disableFailedCheckedSources(): Promise<void> {
    if (this.checkBadUrls.length === 0) {
      return;
    }

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
    const response = await new HttpClient(BOOK_SOURCE_IMPORT_TIMEOUT_MS).execute({
      url,
      method: 'GET',
      headers: {},
      connectTimeout: BOOK_SOURCE_IMPORT_TIMEOUT_MS,
      readTimeout: BOOK_SOURCE_IMPORT_TIMEOUT_MS
    });
    if (!response.success) {
      throw new Error(response.error || `HTTP ${response.statusCode}`);
    }
    return response.body;
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

      promptAction.showToast({ message: `成功导入 ${importCount} 个书源` });
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
