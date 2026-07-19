import { router, promptAction } from '@kit.ArkUI';
import { BookSource, SearchBook, BookListRule, SearchRule, ExploreRule, BookInfoRule, TocRule, ContentRule } from '../model/data/Book';
import { AppDatabase } from '../model/data/AppDatabase';
import { HttpClient } from '../core/http/HttpClient';
import { SearchCoordinator, SearchProgress } from '../core/book/SearchCoordinator';
import { syncSystemBars } from '../utils/SystemBars';
import { SearchExploreSettingsStore } from '../utils/SearchExploreSettingsStore';
import { ImmersiveBackButton } from '../components/ImmersiveBackButton';
import picker from '@ohos.file.picker';
import fs from '@ohos.file.fs';
import { util } from '@kit.ArkTS';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { VerificationSupport } from '../core/http/VerificationSupport';
import { CookieStore } from '../core/http/CookieStore';
import { BookSourceGroupStore } from '../utils/BookSourceGroupStore';
import { ResponsiveManagerListLayout } from '../utils/ResponsiveManagerListLayout';
import { VirtualListScrollbar } from '../utils/VirtualListScrollbar';

const BOOK_SOURCE_IMPORT_FILE_LIMIT_BYTES = 25 * 1024 * 1024;
const BOOK_SOURCE_IMPORT_TIMEOUT_MS = 20000;
const BOOK_SOURCE_IMPORT_URL_RETRY_COUNT = 3;
const BOOK_SOURCE_CHECK_KEYWORD = '斗破苍穹';
const BOOK_SOURCE_LIST_BATCH_SIZE = 60;

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
  @StorageLink('pendingBookSourceImportNonce') @Watch('onPendingBookSourceImportChanged')
  pendingBookSourceImportNonce: number = 0;
  @State allSources: BookSource[] = [];
  @State sources: BookSource[] = [];
  @State visibleSources: BookSource[] = [];
  @State sourceListViewportHeight: number = 0;
  @State sourceFirstVisibleIndex: number = 0;
  @State sourceVisibleItemCount: number = 1;
  @State sourceGroups: string[] = [];
  @State isLoading: boolean = false;
  @State searchText: string = '';
  @State activeSourceGroup: string = '__all__';
  @State showAddDialog: boolean = false;
  @State showImportUrlDialog: boolean = false;
  @State selectionMode: boolean = false;
  @State selectedSourceUrls: string[] = [];
  @State showBatchDeleteDialog: boolean = false;
  @State showGroupDialog: boolean = false;
  @State showMoreActionDialog: boolean = false;
  @State showSourceActionDialog: boolean = false;
  @State showSourceDeleteDialog: boolean = false;
  @State showSourceGroupToolsMenu: boolean = false;
  @State showSourceGroupActionMenu: boolean = false;
  @State showRenameSourceGroupDialog: boolean = false;
  @State showDeleteSourceGroupDialog: boolean = false;
  @State showAddSourceGroupDialog: boolean = false;
  @State pendingSourceGroup: string = '';
  @State renameSourceGroupInput: string = '';
  @State newSourceGroupInput: string = '';
  @State actionSourceUrl: string = '';
  @State actionSourceDetail: BookSource | null = null;
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
    this.handlePendingBookSourceImport();
  }

  onPendingBookSourceImportChanged(): void {
    this.handlePendingBookSourceImport();
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
    await this.loadSources();
  }

  async loadSources() {
    this.isLoading = true;
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      this.allSources = await db.getBookSourceSummaries();
      this.sourceGroups = await BookSourceGroupStore.load(getContext(this), this.sourceGroupsFromSources());
      this.ensureActiveSourceGroup();
      this.applySourceFilters();
    } catch (e) {
      console.error('加载书源失败:', e);
    } finally {
      this.isLoading = false;
    }
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        Row() {
          ImmersiveBackButton({ iconColor: this.primaryTextColor(), darkMode: this.appDarkMode,
            buttonSize: 40, containerWidth: 56, materialScale: 0.83, compactLayout: true,
            onBack: () => router.back() })

          Text('书源管理')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.primaryTextColor())
            .layoutWeight(1)

          if (!this.selectionMode) {
            Text('校验')
              .fontSize(15)
              .fontColor(this.isCheckingSources ? this.subTextColor() : this.primaryTextColor())
              .width(44)
              .height(40)
              .textAlign(TextAlign.Center)
              .onClick(() => {
                this.openCheckOptions();
              })

          }

          Text(this.selectionMode ? '取消' : '选择')
            .fontSize(15)
            .fontColor(this.isBatchOperating ? this.subTextColor() : this.primaryTextColor())
            .width(44)
            .height(40)
            .textAlign(TextAlign.Center)
            .margin({ left: this.selectionMode ? 0 : 4 })
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
        }
        .width('100%')
        .height(56)
        .padding({ right: 16 })
        .backgroundColor(this.glassCardColor())
        .border({ width: ThemeRuntime.glassBorderWidth(), color: this.glassBorderColor() })
        .alignItems(VerticalAlign.Center)

        Row() {
          TextInput({ placeholder: '搜索书源', text: this.searchText })
            .layoutWeight(1)
            .height(40)
            .borderRadius(20)
            .backgroundColor(this.glassInputColor())
            .border({ width: ThemeRuntime.glassBorderWidth(), color: this.glassBorderColor() })
            .shadow({ radius: ThemeRuntime.glassShadowRadius(), color: this.glassShadowColor(), offsetX: ThemeRuntime.glassShadowOffsetX(), offsetY: ThemeRuntime.glassShadowOffsetY() })
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

        if (!this.selectionMode) {
          this.sourceGroupBar()
        }

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
            Text(this.emptySourceTitle())
              .fontSize(16)
              .fontColor(this.subTextColor())
            Text(this.emptySourceDescription())
              .fontSize(14)
              .fontColor(this.subTextColor())
              .margin({ top: 8 })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        } else {
          Stack({ alignContent: Alignment.TopEnd }) {
            List({ space: 8 }) {
            ForEach(this.visibleSources, (source: BookSource) => {
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
                      if (source.isLocked) {
                        Text('已锁定')
                          .fontSize(11)
                          .fontColor(this.accentColor())
                          .backgroundColor(this.inputColor())
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

                  if (this.selectionMode) {
                    Column() {
                      Text(source.enabled ? '已启用' : '已禁用')
                        .fontSize(12)
                        .fontColor(source.enabled ? '#1E8E3E' : this.subTextColor())
                      Text(source.enabledExplore ? '发现已启用' : '发现已禁用')
                        .fontSize(12)
                        .fontColor(source.enabledExplore ? '#1E8E3E' : this.subTextColor())
                        .margin({ top: 4 })
                    }
                    .alignItems(HorizontalAlign.End)
                  }
                }
                .width('100%')
                .padding(12)
                .backgroundColor(this.glassCardColor())
                .borderRadius(8)
                .border({ width: ThemeRuntime.glassBorderWidth(), color: this.glassBorderColor() })
                .shadow({ radius: ThemeRuntime.glassShadowRadius(), color: this.glassShadowColor(), offsetX: ThemeRuntime.glassShadowOffsetX(), offsetY: ThemeRuntime.glassShadowOffsetY() })
                .opacity(source.enabled ? 1 : 0.45)
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
              .swipeAction(this.selectionMode || source.isLocked ? {} : {
                start: {
                  builder: () => {
                    this.sourceDisableSwipeAction(source)
                  },
                  actionAreaDistance: 64,
                  onAction: () => {
                    if (!this.selectionMode && !this.isBatchOperating) this.toggleSourceEnabled(source);
                  }
                },
                end: {
                  builder: () => {
                    this.sourceDeleteSwipeAction(source)
                  },
                  actionAreaDistance: 64,
                  onAction: () => {
                    if (!this.selectionMode && !this.isBatchOperating) this.deleteSourceFromSwipe(source);
                  }
                },
                edgeEffect: SwipeEdgeEffect.Spring
              })
            }, (source: BookSource) => this.sourceListItemKey(source))
            }
            .width('100%')
            .height('100%')
            .padding({ left: 16, right: 16 })
            .lanes(ResponsiveManagerListLayout.laneCount(this.contextViewportWidth),
              ResponsiveManagerListLayout.gutter(this.contextViewportWidth))
            .scrollBar(BarState.Off)
            .onScrollIndex((start: number, end: number) => {
              this.sourceFirstVisibleIndex = Math.max(0, start);
              this.sourceVisibleItemCount = Math.max(1, end - start + 1);
            })
            .onReachEnd(() => this.loadMoreVisibleSources())

            this.sourceVirtualScrollbar()
          }
          .width('100%')
          .layoutWeight(1)
          .onAreaChange((_oldValue: Area, newValue: Area) => {
            this.sourceListViewportHeight = Number(newValue.height);
          })
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
          .border({ width: ThemeRuntime.glassBorderWidth(), color: this.glassBorderColor() })
        }
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.statusBarHeight, bottom: this.navBarHeight })
      .backgroundColor(this.pageColor())

      if (!this.selectionMode && !this.showAddDialog && !this.isImporting && !this.isBatchOperating) {
        this.addSourceFloatingButton()
      }

      if (this.showAddDialog) {
        this.addSourceDropdown()
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
          .backgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode, '', 'overlay'))
          .borderRadius(ThemeRuntime.glassCornerRadius(16, 'overlay'))
          .backdropBlur(ThemeRuntime.glassBlur('overlay', 28))
          .border({ width: ThemeRuntime.glassBorderWidth('overlay'), color: ThemeRuntime.glassBorderColor(this.appDarkMode, 'overlay') })
          .shadow({ radius: ThemeRuntime.glassShadowRadius('overlay'), color: ThemeRuntime.glassShadowColor(this.appDarkMode, 'overlay'), offsetX: ThemeRuntime.glassShadowOffsetX('overlay'), offsetY: ThemeRuntime.glassShadowOffsetY('overlay') })
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
          .backgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode, '', 'overlay'))
          .borderRadius(ThemeRuntime.glassCornerRadius(16, 'overlay'))
          .backdropBlur(ThemeRuntime.glassBlur('overlay', 28))
          .border({ width: ThemeRuntime.glassBorderWidth('overlay'), color: ThemeRuntime.glassBorderColor(this.appDarkMode, 'overlay') })
          .shadow({ radius: ThemeRuntime.glassShadowRadius('overlay'), color: ThemeRuntime.glassShadowColor(this.appDarkMode, 'overlay'), offsetX: ThemeRuntime.glassShadowOffsetX('overlay'), offsetY: ThemeRuntime.glassShadowOffsetY('overlay') })
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
          .backgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode, '', 'overlay'))
          .borderRadius(ThemeRuntime.glassCornerRadius(16, 'overlay'))
          .backdropBlur(ThemeRuntime.glassBlur('overlay', 28))
          .border({ width: ThemeRuntime.glassBorderWidth('overlay'), color: ThemeRuntime.glassBorderColor(this.appDarkMode, 'overlay') })
          .shadow({ radius: ThemeRuntime.glassShadowRadius('overlay'), color: ThemeRuntime.glassShadowColor(this.appDarkMode, 'overlay'), offsetX: ThemeRuntime.glassShadowOffsetX('overlay'), offsetY: ThemeRuntime.glassShadowOffsetY('overlay') })
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
        this.batchMorePopupMenu()
      }

      if (this.showSourceGroupActionMenu) {
        this.sourceGroupActionMenu()
      }

      if (this.showSourceGroupToolsMenu) {
        this.sourceGroupToolsMenu()
      }

      if (this.showRenameSourceGroupDialog) {
        this.renameSourceGroupDialog()
      }

      if (this.showDeleteSourceGroupDialog) {
        this.deleteSourceGroupDialog()
      }

      if (this.showAddSourceGroupDialog) {
        this.addSourceGroupDialog()
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
                    .fontSize(11)
                    .enabled(this.checkBadUrls.length > 0 && !this.isBatchOperating)
                    .backgroundColor(this.checkBadUrls.length > 0 && !this.isBatchOperating ? '#F57C00' : this.inputColor())
                    .fontColor(this.checkBadUrls.length > 0 && !this.isBatchOperating ? '#FFFFFF' : this.subTextColor())
                    .onClick(() => {
                      this.disableFailedCheckedSources();
                    })

                  Button('一键删除', { type: ButtonType.Normal })
                    .layoutWeight(1)
                    .height(42)
                    .borderRadius(10)
                    .fontSize(11)
                    .enabled(this.checkBadUrls.length > 0 && !this.isBatchOperating)
                    .backgroundColor(this.checkBadUrls.length > 0 && !this.isBatchOperating ? '#E53935' : this.inputColor())
                    .fontColor(this.checkBadUrls.length > 0 && !this.isBatchOperating ? '#FFFFFF' : this.subTextColor())
                    .onClick(() => {
                      this.deleteFailedCheckedSources();
                    })
                }

                Button(this.checkInvalidAction === 'none' ? '取消' : '关闭', { type: ButtonType.Normal })
                  .layoutWeight(1)
                  .height(42)
                  .borderRadius(10)
                  .fontSize(11)
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
          .backgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode, '', 'overlay'))
          .borderRadius(ThemeRuntime.glassCornerRadius(16, 'overlay'))
          .backdropBlur(ThemeRuntime.glassBlur('overlay', 28))
          .border({ width: ThemeRuntime.glassBorderWidth('overlay'), color: ThemeRuntime.glassBorderColor(this.appDarkMode, 'overlay') })
          .shadow({ radius: ThemeRuntime.glassShadowRadius('overlay'), color: ThemeRuntime.glassShadowColor(this.appDarkMode, 'overlay'), offsetX: ThemeRuntime.glassShadowOffsetX('overlay'), offsetY: ThemeRuntime.glassShadowOffsetY('overlay') })
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
          .backgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode, '', 'overlay'))
          .borderRadius(ThemeRuntime.glassCornerRadius(16, 'overlay'))
          .backdropBlur(ThemeRuntime.glassBlur('overlay', 28))
          .border({ width: ThemeRuntime.glassBorderWidth('overlay'), color: ThemeRuntime.glassBorderColor(this.appDarkMode, 'overlay') })
          .shadow({ radius: ThemeRuntime.glassShadowRadius('overlay'), color: ThemeRuntime.glassShadowColor(this.appDarkMode, 'overlay'), offsetX: ThemeRuntime.glassShadowOffsetX('overlay'), offsetY: ThemeRuntime.glassShadowOffsetY('overlay') })
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
          .backgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode, '', 'overlay'))
          .borderRadius(ThemeRuntime.glassCornerRadius(16, 'overlay'))
          .backdropBlur(ThemeRuntime.glassBlur('overlay', 28))
          .border({ width: ThemeRuntime.glassBorderWidth('overlay'), color: ThemeRuntime.glassBorderColor(this.appDarkMode, 'overlay') })
          .shadow({ radius: ThemeRuntime.glassShadowRadius('overlay'), color: ThemeRuntime.glassShadowColor(this.appDarkMode, 'overlay'), offsetX: ThemeRuntime.glassShadowOffsetX('overlay'), offsetY: ThemeRuntime.glassShadowOffsetY('overlay') })
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
  addSourceFloatingButton() {
    Button({ type: ButtonType.Circle, stateEffect: true }) {
      SymbolGlyph($r('sys.symbol.plus'))
        .fontSize(25)
        .fontColor([this.accentColor()])
    }
    .width(52)
    .height(52)
    .margin({ right: 22, bottom: this.navBarHeight + 22 })
    .backgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode, this.cardColor(), 'button'))
    .backdropBlur(ThemeRuntime.glassBlur('button', 12))
    .border({ width: ThemeRuntime.glassBorderWidth('button'), color: ThemeRuntime.glassBorderColor(this.appDarkMode, 'button') })
    .shadow({ radius: ThemeRuntime.glassShadowRadius('button'), color: ThemeRuntime.glassShadowColor(this.appDarkMode, 'button'), offsetX: ThemeRuntime.glassShadowOffsetX('button'), offsetY: ThemeRuntime.glassShadowOffsetY('button') })
    .accessibilityText('新增书源')
    .onClick(() => {
      this.showAddDialog = true;
    })
  }

  @Builder
  addSourceDropdown() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column()
        .width('100%')
        .height('100%')
        .onClick(() => {
          this.showAddDialog = false;
        })

      Column() {
        this.popupActionItem($r('sys.symbol.plus'), '新建书源', this.primaryTextColor(), () => {
          this.showAddDialog = false;
          router.pushUrl({
            url: 'pages/BookSourceEdit',
            params: { bookSourceUrl: '' }
          });
        })
        this.popupActionItem($r('sys.symbol.arrow_right_up_and_square'), '从 URL 导入', this.primaryTextColor(), () => {
          this.showAddDialog = false;
          this.showImportUrlDialog = true;
        })
        this.popupActionItem($r('sys.symbol.download'), '从文件导入', this.primaryTextColor(), () => {
          this.showAddDialog = false;
          this.importFromFile();
        }, false)
      }
      .width(188)
      .padding({ left: 6, right: 6, top: 6, bottom: 6 })
      .backgroundColor(ThemeRuntime.glassPanelColor(this.appDarkMode, '', 'panel'))
      .borderRadius(ThemeRuntime.glassCornerRadius(16, 'panel'))
      .backdropBlur(ThemeRuntime.glassBlur('panel', 22))
      .border({ width: ThemeRuntime.glassBorderWidth('panel'), color: ThemeRuntime.glassBorderColor(this.appDarkMode, 'panel') })
      .shadow({ radius: ThemeRuntime.glassShadowRadius('panel'), color: ThemeRuntime.glassShadowColor(this.appDarkMode, 'panel'), offsetX: ThemeRuntime.glassShadowOffsetX('panel'), offsetY: ThemeRuntime.glassShadowOffsetY('panel') })
      .margin({ right: 22, bottom: this.navBarHeight + 82 })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  batchMorePopupMenu() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .onClick(() => {
          this.showMoreActionDialog = false;
        })

      Column() {
        Text(`已选择 ${this.selectedSourceUrls.length} 个书源`)
          .fontSize(12)
          .fontColor(this.subTextColor())
          .width('100%')
          .height(34)
          .padding({ left: 12, right: 12 })
          .textAlign(TextAlign.Start)

        this.popupActionItem($r('sys.symbol.checkmark_circle'), '启用发现', this.primaryTextColor(), () => {
          this.showMoreActionDialog = false;
          this.batchSetExploreEnabled(true);
        })
        this.popupActionItem($r('sys.symbol.minus_circle'), '禁用发现', this.primaryTextColor(), () => {
          this.showMoreActionDialog = false;
          this.batchSetExploreEnabled(false);
        })
        this.popupActionItem($r('sys.symbol.download'), '导出 JSON', this.primaryTextColor(), () => {
          this.showMoreActionDialog = false;
          this.exportSelectedSources();
        })
        this.popupActionItem($r('sys.symbol.trash'), '删除', '#E53935', () => {
          this.showMoreActionDialog = false;
          this.showBatchDeleteDialog = true;
        }, false)
      }
      .width(188)
      .padding({ left: 6, right: 6, top: 4, bottom: 6 })
      .backgroundColor(ThemeRuntime.glassPanelColor(this.appDarkMode, '', 'panel'))
      .borderRadius(ThemeRuntime.glassCornerRadius(16, 'panel'))
      .backdropBlur(ThemeRuntime.glassBlur('panel', 22))
      .border({ width: ThemeRuntime.glassBorderWidth('panel'), color: ThemeRuntime.glassBorderColor(this.appDarkMode, 'panel') })
      .shadow({ radius: ThemeRuntime.glassShadowRadius('panel'), color: ThemeRuntime.glassShadowColor(this.appDarkMode, 'panel'), offsetX: ThemeRuntime.glassShadowOffsetX('panel'), offsetY: ThemeRuntime.glassShadowOffsetY('panel') })
      .position({ x: '100%', y: '100%' })
      .translate({ x: -200, y: -(244 + Math.max(this.navBarHeight, 8)) })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  popupActionItem(icon: Resource, label: string, color: string, action: () => void,
    showDivider: boolean = true) {
    Column() {
      Row({ space: 10 }) {
        SymbolGlyph(icon)
          .fontSize(19)
          .fontColor([color])
          .width(24)
        Text(label)
          .fontSize(15)
          .fontColor(color)
          .layoutWeight(1)
      }
      .width('100%')
      .height(44)
      .padding({ left: 10, right: 10 })

      if (showDivider) {
        Divider()
          .strokeWidth(0.5)
          .color(ThemeRuntime.glassBorderColor(this.appDarkMode))
          .margin({ left: 44, right: 8 })
      }
    }
    .width('100%')
    .onClick(action)
  }

  @Builder
  checkOptionsDialog() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.appDarkMode ? '#38000000' : '#14FFFFFF')
        .backdropBlur(ThemeRuntime.glassBlur('menu', 10))
        .onClick(() => {
          this.showCheckOptionsDialog = false;
        })

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
      .width('calc(100% - 24vp)')
      .constraintSize({ maxWidth: 360 })
      .padding(18)
      .backgroundColor(ThemeRuntime.glassPanelColor(this.appDarkMode, '', 'panel'))
      .borderRadius(ThemeRuntime.glassCornerRadius(14, 'panel'))
      .backdropBlur(ThemeRuntime.glassBlur('panel', 22))
      .border({ width: ThemeRuntime.glassBorderWidth('panel'), color: ThemeRuntime.glassBorderColor(this.appDarkMode, 'panel') })
      .shadow({ radius: ThemeRuntime.glassShadowRadius('panel'), color: ThemeRuntime.glassShadowColor(this.appDarkMode, 'panel'), offsetX: ThemeRuntime.glassShadowOffsetX('panel'), offsetY: ThemeRuntime.glassShadowOffsetY('panel') })
      .margin({ top: this.statusBarHeight + 62, right: 12 })
      .onClick(() => {
      })
    }
    .width('100%')
    .height('100%')
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
        .backdropBlur(ThemeRuntime.glassBlur('popover', 18))
        .onClick(() => this.closeSourceActions())
      Column() {
        this.contextActionItem($r('sys.symbol.magnifyingglass'), '搜索', this.primaryTextColor(),
          () => this.openActionSourceSearch())
        if (this.actionSourceNeedsLogin()) {
          this.contextActionItem($r('sys.symbol.arrow_right_up_and_square'),
            this.actionSourceLoggedIn() ? '重新登录' : '登录',
            this.primaryTextColor(), () => this.openActionSourceLogin())
        }
        this.contextActionItem($r('sys.symbol.checkmark_shield'), '校验', this.primaryTextColor(),
          () => this.checkActionSource())
        this.contextActionItem($r('sys.symbol.lock'), this.actionSourceLocked() ? '解锁' : '锁定',
          this.primaryTextColor(), () => this.toggleActionSourceLocked())
        if (!this.actionSourceLocked()) {
          this.contextActionItem($r('sys.symbol.square_and_pencil'), '修改', this.primaryTextColor(),
            () => this.openActionSourceEdit())
          this.contextActionItem(this.actionSourceEnabled() ? $r('sys.symbol.minus_circle') :
            $r('sys.symbol.checkmark_circle'), this.actionSourceEnabled() ? '禁用' : '启用', this.primaryTextColor(),
            () => this.toggleActionSourceEnabled())
        }
        this.contextActionItem($r('sys.symbol.list_bullet'), '多选', this.primaryTextColor(),
          () => this.enterActionSourceSelection())
        if (!this.actionSourceLocked()) {
          this.contextActionItem($r('sys.symbol.trash'), '删除', '#E53935', () => {
              this.showSourceActionDialog = false;
              this.showSourceDeleteDialog = true;
            })
        }
      }
      .width(158)
      .padding({ top: 6, bottom: 6 })
      .backgroundColor(ThemeRuntime.glassPanelColor(this.appDarkMode, '', 'panel'))
      .borderRadius(ThemeRuntime.glassCornerRadius(14, 'panel'))
      .backdropBlur(ThemeRuntime.glassBlur('panel', 22))
      .border({ width: ThemeRuntime.glassBorderWidth('panel'), color: ThemeRuntime.glassBorderColor(this.appDarkMode, 'panel') })
      .shadow({ radius: ThemeRuntime.glassShadowRadius('panel'), color: ThemeRuntime.glassShadowColor(this.appDarkMode, 'panel'), offsetX: ThemeRuntime.glassShadowOffsetX('panel'), offsetY: ThemeRuntime.glassShadowOffsetY('panel') })
      .position({
        x: this.contextMenuLeft(158),
        y: this.contextMenuTop(this.sourceActionMenuHeight())
      })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  contextActionItem(icon: Resource, label: string, color: string, action: () => void) {
    Row({ space: 10 }) {
      SymbolGlyph(icon)
        .fontSize(18)
        .fontColor([color])
        .width(24)
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
  sourceDisableSwipeAction(source: BookSource) {
    Column({ space: 4 }) {
      SymbolGlyph(source.enabled ? $r('sys.symbol.minus_circle') : $r('sys.symbol.checkmark_circle'))
        .fontSize(22)
        .fontColor(['#FFFFFF'])
      Text(source.enabled ? '禁用' : '启用')
        .fontSize(11)
        .fontColor('#FFFFFF')
    }
    .width(72)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(source.enabled ? '#F39C3D' : '#1E8E3E')
    .onClick(() => {
      if (!this.selectionMode && !this.isBatchOperating) this.toggleSourceEnabled(source);
    })
  }

  @Builder
  sourceDeleteSwipeAction(source: BookSource) {
    Column({ space: 4 }) {
      SymbolGlyph($r('sys.symbol.trash'))
        .fontSize(22)
        .fontColor(['#FFFFFF'])
      Text('删除')
        .fontSize(11)
        .fontColor('#FFFFFF')
    }
    .width(72)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#E53935')
    .onClick(() => {
      if (!this.selectionMode && !this.isBatchOperating) this.deleteSourceFromSwipe(source);
    })
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
      .backgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode, '', 'overlay'))
      .borderRadius(ThemeRuntime.glassCornerRadius(16, 'overlay'))
      .backdropBlur(ThemeRuntime.glassBlur('overlay', 28))
      .border({ width: ThemeRuntime.glassBorderWidth('overlay'), color: ThemeRuntime.glassBorderColor(this.appDarkMode, 'overlay') })
      .shadow({ radius: ThemeRuntime.glassShadowRadius('overlay'), color: ThemeRuntime.glassShadowColor(this.appDarkMode, 'overlay'), offsetX: ThemeRuntime.glassShadowOffsetX('overlay'), offsetY: ThemeRuntime.glassShadowOffsetY('overlay') })
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

  @Builder
  sourceVirtualScrollbar() {
    if (this.sourceShouldShowVirtualScrollbar()) {
      Column()
        .width(3)
        .height(this.sourceListViewportHeight)
        .borderRadius(2)
        .backgroundColor(this.appDarkMode ? '#18FFFFFF' : '#14000000')
        .margin({ right: 3 })
        .hitTestBehavior(HitTestMode.None)
      Column()
        .width(3)
        .height(this.sourceScrollbarThumbLength())
        .borderRadius(2)
        .backgroundColor(this.appDarkMode ? '#99D5D8DE' : '#887A6F63')
        .margin({ right: 3 })
        .translate({ y: this.sourceScrollbarThumbOffset() })
        .hitTestBehavior(HitTestMode.None)
    }
  }

  sourceShouldShowVirtualScrollbar(): boolean {
    return this.sourceListViewportHeight > 0 && this.sources.length > this.sourceVisibleItemCount;
  }

  sourceScrollbarThumbLength(): number {
    return VirtualListScrollbar.thumbLength(this.sourceListViewportHeight,
      this.sources.length, this.sourceVisibleItemCount);
  }

  sourceScrollbarThumbOffset(): number {
    return VirtualListScrollbar.thumbOffset(this.sourceListViewportHeight,
      this.sourceScrollbarThumbLength(), this.sources.length,
      this.sourceFirstVisibleIndex, this.sourceVisibleItemCount);
  }

  @Builder
  sourceGroupBar() {
    Scroll() {
      Row({ space: 8 }) {
        Stack({ alignContent: Alignment.Center }) {
          SymbolGlyph($r('sys.symbol.more'))
            .fontSize(18)
            .fontColor([this.primaryTextColor()])
        }
          .width(32)
          .height(32)
          .borderRadius(16)
          .backgroundColor(this.glassCardColor())
          .border({ width: ThemeRuntime.glassBorderWidth(), color: this.glassBorderColor() })
          .onClick((event: ClickEvent) => {
            this.contextMenuX = event.windowX;
            this.contextMenuY = event.windowY;
            this.showSourceGroupToolsMenu = true;
          })
        this.sourceGroupChip('全部', '__all__')
        ForEach(this.getSourceGroups(), (group: string) => {
          this.sourceGroupChip(group, group, true)
        }, (group: string) => group)
        this.sourceGroupChip('未分组', '__ungrouped__')
        Text('＋')
          .fontSize(20)
          .fontColor(this.accentColor())
          .width(34)
          .height(34)
          .textAlign(TextAlign.Center)
          .borderRadius(17)
          .backgroundColor(this.glassCardColor())
          .border({ width: ThemeRuntime.glassBorderWidth(), color: this.glassBorderColor() })
          .onClick(() => {
            this.newSourceGroupInput = '';
            this.showAddSourceGroupDialog = true;
          })
      }
      .padding({ left: 16, right: 16, bottom: 8 })
      .constraintSize({ minWidth: '100%' })
      .justifyContent(FlexAlign.Start)
    }
    .width('100%')
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
  }

  @Builder
  sourceGroupToolsMenu() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.showSourceGroupToolsMenu = false;
        })

      Column() {
        this.contextActionItem($r('sys.symbol.trash'), '清除空分组', this.primaryTextColor(), () => {
          this.showSourceGroupToolsMenu = false;
          this.clearEmptySourceGroups();
        })
        this.contextActionItem($r('sys.symbol.plus'), '新建分组', this.primaryTextColor(), () => {
          this.showSourceGroupToolsMenu = false;
          this.newSourceGroupInput = '';
          this.showAddSourceGroupDialog = true;
        })
      }
      .width(166)
      .padding({ top: 6, bottom: 6 })
      .backgroundColor(ThemeRuntime.glassPanelColor(this.appDarkMode, '', 'panel'))
      .borderRadius(ThemeRuntime.glassCornerRadius(14, 'panel'))
      .backdropBlur(ThemeRuntime.glassBlur('panel', 22))
      .border({ width: ThemeRuntime.glassBorderWidth('panel'), color: ThemeRuntime.glassBorderColor(this.appDarkMode, 'panel') })
      .shadow({ radius: ThemeRuntime.glassShadowRadius('panel'), color: ThemeRuntime.glassShadowColor(this.appDarkMode, 'panel'), offsetX: ThemeRuntime.glassShadowOffsetX('panel'), offsetY: ThemeRuntime.glassShadowOffsetY('panel') })
      .position({ x: this.contextMenuLeft(166), y: this.contextMenuTop(100) })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  sourceGroupChip(label: string, groupKey: string, editable: boolean = false) {
    Text(label)
      .fontSize(13)
      .fontColor(this.activeSourceGroup === groupKey ? '#FFFFFF' : this.primaryTextColor())
      .maxLines(1)
      .padding({ left: 13, right: 13, top: 7, bottom: 7 })
      .borderRadius(16)
      .backgroundColor(this.activeSourceGroup === groupKey ? this.accentColor() : this.glassCardColor())
      .border({ width: this.activeSourceGroup === groupKey ? 0 : 1, color: this.glassBorderColor() })
      .onClick(() => {
        this.selectSourceGroup(groupKey);
      })
      .gesture(
        LongPressGesture({ repeat: false })
          .onAction((event: GestureEvent) => {
            if (editable) {
              this.openSourceGroupActions(groupKey, event);
            }
          })
      )
  }

  @Builder
  sourceGroupActionMenu() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.appDarkMode ? '#52000000' : '#26FFFFFF')
        .backdropBlur(ThemeRuntime.glassBlur('popover', 18))
        .onClick(() => this.closeSourceGroupActions())

      Column() {
        this.contextActionItem($r('sys.symbol.square_and_pencil'), '重命名', this.primaryTextColor(), () => {
            this.renameSourceGroupInput = this.pendingSourceGroup;
            this.showSourceGroupActionMenu = false;
            this.showRenameSourceGroupDialog = true;
          })
        this.contextActionItem($r('sys.symbol.trash'), '删除', '#E53935', () => {
            this.showSourceGroupActionMenu = false;
            this.showDeleteSourceGroupDialog = true;
          })
      }
      .width(148)
      .padding({ top: 6, bottom: 6 })
      .backgroundColor(ThemeRuntime.glassPanelColor(this.appDarkMode, '', 'panel'))
      .borderRadius(ThemeRuntime.glassCornerRadius(14, 'panel'))
      .backdropBlur(ThemeRuntime.glassBlur('panel', 22))
      .border({ width: ThemeRuntime.glassBorderWidth('panel'), color: ThemeRuntime.glassBorderColor(this.appDarkMode, 'panel') })
      .shadow({ radius: ThemeRuntime.glassShadowRadius('panel'), color: ThemeRuntime.glassShadowColor(this.appDarkMode, 'panel'), offsetX: ThemeRuntime.glassShadowOffsetX('panel'), offsetY: ThemeRuntime.glassShadowOffsetY('panel') })
      .position({ x: this.contextMenuLeft(148), y: this.contextMenuTop(100) })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  addSourceGroupDialog() {
    Column() {
      Column({ space: 16 }) {
        Text('新增书源分组')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())

        TextInput({ placeholder: '输入分组名称', text: this.newSourceGroupInput })
          .width('100%')
          .height(42)
          .backgroundColor(this.inputColor())
          .fontColor(this.primaryTextColor())
          .borderRadius(10)
          .onChange((value: string) => this.newSourceGroupInput = value)

        Row({ space: 12 }) {
          Button('取消', { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(42)
            .borderRadius(10)
            .backgroundColor(this.glassCardColor())
            .fontColor(this.primaryTextColor())
            .onClick(() => this.closeAddSourceGroupDialog())
          Button('新增', { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(42)
            .borderRadius(10)
            .backgroundColor(this.buttonColor())
            .fontColor('#FFFFFF')
            .enabled(!!this.newSourceGroupInput.trim() && !this.isBatchOperating)
            .onClick(() => this.addSourceGroup())
        }
        .width('100%')
      }
      .width('85%')
      .padding(22)
      .borderRadius(ThemeRuntime.glassCornerRadius(16, 'overlay'))
      .backgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode, '', 'overlay'))
      .backdropBlur(ThemeRuntime.glassBlur('overlay', 28))
      .border({ width: ThemeRuntime.glassBorderWidth('overlay'), color: ThemeRuntime.glassBorderColor(this.appDarkMode, 'overlay') })
      .shadow({ radius: ThemeRuntime.glassShadowRadius('overlay'), color: ThemeRuntime.glassShadowColor(this.appDarkMode, 'overlay'), offsetX: ThemeRuntime.glassShadowOffsetX('overlay'), offsetY: ThemeRuntime.glassShadowOffsetY('overlay') })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#80000000')
  }

  @Builder
  renameSourceGroupDialog() {
    Column() {
      Column({ space: 16 }) {
        Text('重命名书源分组')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())

        TextInput({ placeholder: '输入分组名称', text: this.renameSourceGroupInput })
          .width('100%')
          .height(42)
          .backgroundColor(this.inputColor())
          .fontColor(this.primaryTextColor())
          .borderRadius(10)
          .onChange((value: string) => this.renameSourceGroupInput = value)

        Row({ space: 12 }) {
          Button('取消', { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(42)
            .borderRadius(10)
            .backgroundColor(this.glassCardColor())
            .fontColor(this.primaryTextColor())
            .onClick(() => this.closeRenameSourceGroupDialog())
          Button('保存', { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(42)
            .borderRadius(10)
            .backgroundColor(this.buttonColor())
            .fontColor('#FFFFFF')
            .enabled(!!this.renameSourceGroupInput.trim() && !this.isBatchOperating)
            .onClick(() => this.renameSourceGroup())
        }
        .width('100%')
      }
      .width('85%')
      .padding(22)
      .borderRadius(ThemeRuntime.glassCornerRadius(16, 'overlay'))
      .backgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode, '', 'overlay'))
      .backdropBlur(ThemeRuntime.glassBlur('overlay', 28))
      .border({ width: ThemeRuntime.glassBorderWidth('overlay'), color: ThemeRuntime.glassBorderColor(this.appDarkMode, 'overlay') })
      .shadow({ radius: ThemeRuntime.glassShadowRadius('overlay'), color: ThemeRuntime.glassShadowColor(this.appDarkMode, 'overlay'), offsetX: ThemeRuntime.glassShadowOffsetX('overlay'), offsetY: ThemeRuntime.glassShadowOffsetY('overlay') })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#80000000')
  }

  @Builder
  deleteSourceGroupDialog() {
    Column() {
      Column({ space: 16 }) {
        Text('删除书源分组')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())
        Text(`删除“${this.pendingSourceGroup}”后，分组内书源将移到未分组，书源本身不会删除。`)
          .fontSize(14)
          .fontColor(this.secondaryTextColor())
          .textAlign(TextAlign.Center)
        Row({ space: 12 }) {
          Button('取消', { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(42)
            .borderRadius(10)
            .backgroundColor(this.glassCardColor())
            .fontColor(this.primaryTextColor())
            .onClick(() => this.closeDeleteSourceGroupDialog())
          Button('删除', { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(42)
            .borderRadius(10)
            .backgroundColor('#E53935')
            .fontColor('#FFFFFF')
            .enabled(!this.isBatchOperating)
            .onClick(() => this.deleteSourceGroup())
        }
        .width('100%')
      }
      .width('85%')
      .padding(22)
      .borderRadius(ThemeRuntime.glassCornerRadius(16, 'overlay'))
      .backgroundColor(ThemeRuntime.dropdownPanelColor(this.appDarkMode, '', 'overlay'))
      .backdropBlur(ThemeRuntime.glassBlur('overlay', 28))
      .border({ width: ThemeRuntime.glassBorderWidth('overlay'), color: ThemeRuntime.glassBorderColor(this.appDarkMode, 'overlay') })
      .shadow({ radius: ThemeRuntime.glassShadowRadius('overlay'), color: ThemeRuntime.glassShadowColor(this.appDarkMode, 'overlay'), offsetX: ThemeRuntime.glassShadowOffsetX('overlay'), offsetY: ThemeRuntime.glassShadowOffsetY('overlay') })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#80000000')
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

  searchSources(): void {
    this.applySourceFilters();
  }

  selectSourceGroup(groupKey: string): void {
    if (this.activeSourceGroup === groupKey) {
      return;
    }
    this.activeSourceGroup = groupKey;
    this.applySourceFilters();
  }

  openSourceGroupActions(group: string, event?: GestureEvent): void {
    const finger = event && event.fingerList.length > 0 ? event.fingerList[0] : undefined;
    if (finger) {
      this.contextMenuX = finger.globalX;
      this.contextMenuY = finger.globalY;
    }
    this.pendingSourceGroup = group;
    this.showSourceGroupActionMenu = true;
  }

  closeSourceGroupActions(): void {
    this.showSourceGroupActionMenu = false;
    this.pendingSourceGroup = '';
  }

  closeRenameSourceGroupDialog(): void {
    this.showRenameSourceGroupDialog = false;
    this.renameSourceGroupInput = '';
    this.pendingSourceGroup = '';
  }

  closeDeleteSourceGroupDialog(): void {
    this.showDeleteSourceGroupDialog = false;
    this.pendingSourceGroup = '';
  }

  closeAddSourceGroupDialog(): void {
    this.showAddSourceGroupDialog = false;
    this.newSourceGroupInput = '';
  }

  async addSourceGroup(): Promise<void> {
    const groupName = this.newSourceGroupInput.trim();
    if (!groupName || this.isBatchOperating) {
      return;
    }
    if (this.getSourceGroups().includes(groupName)) {
      promptAction.showToast({ message: '分组名称已存在' });
      return;
    }
    this.isBatchOperating = true;
    try {
      this.sourceGroups = await BookSourceGroupStore.add(getContext(this), groupName, this.sourceGroups);
      this.activeSourceGroup = groupName;
      this.applySourceFilters();
      this.closeAddSourceGroupDialog();
      promptAction.showToast({ message: '书源分组已新增' });
    } catch (e) {
      console.error('新增书源分组失败:', e);
      promptAction.showToast({ message: '新增分组失败' });
    } finally {
      this.isBatchOperating = false;
    }
  }

  async reconcileSourceGroups(): Promise<void> {
    try {
      this.sourceGroups = await BookSourceGroupStore.load(getContext(this), this.sourceGroupsFromSources());
      this.ensureActiveSourceGroup();
      this.applySourceFilters();
    } catch (e) {
      console.warn('清理空书源分组失败:', e);
    }
  }

  async clearEmptySourceGroups(): Promise<void> {
    if (this.isBatchOperating) {
      return;
    }
    const occupiedGroups = this.sourceGroupsFromSources();
    const emptyGroups = this.getSourceGroups().filter((group: string) => !occupiedGroups.includes(group));
    if (emptyGroups.length === 0) {
      promptAction.showToast({ message: '没有空分组' });
      return;
    }
    this.isBatchOperating = true;
    this.batchOperationText = '正在清除空分组...';
    try {
      let groups = this.sourceGroups;
      for (const group of emptyGroups) {
        groups = await BookSourceGroupStore.remove(getContext(this), group, groups);
      }
      this.sourceGroups = groups;
      this.ensureActiveSourceGroup();
      this.applySourceFilters();
      promptAction.showToast({ message: `已清除 ${emptyGroups.length} 个空分组` });
    } catch (e) {
      console.error('清除空书源分组失败:', e);
      promptAction.showToast({ message: '清除空分组失败' });
    } finally {
      this.isBatchOperating = false;
    }
  }

  async renameSourceGroup(): Promise<void> {
    const oldName = this.pendingSourceGroup;
    const newName = this.renameSourceGroupInput.trim();
    if (!oldName || !newName || this.isBatchOperating) {
      return;
    }
    if (oldName === newName) {
      this.closeRenameSourceGroupDialog();
      return;
    }
    if (this.getSourceGroups().includes(newName)) {
      promptAction.showToast({ message: '分组名称已存在' });
      return;
    }

    this.isBatchOperating = true;
    this.batchOperationText = '正在重命名书源分组...';
    try {
      const db = AppDatabase.getInstance();
      const groupedSources = this.allSources.filter((source: BookSource) =>
        (source.bookSourceGroup || '').trim() === oldName);
      for (const source of groupedSources) {
        source.bookSourceGroup = newName;
        await db.updateBookSourceListFields(source.bookSourceUrl, { bookSourceGroup: newName });
      }
      this.sourceGroups = await BookSourceGroupStore.rename(
        getContext(this), oldName, newName, this.sourceGroups);
      if (this.activeSourceGroup === oldName) {
        this.activeSourceGroup = newName;
      }
      this.showRenameSourceGroupDialog = false;
      this.renameSourceGroupInput = '';
      this.pendingSourceGroup = '';
      await this.loadSources();
      promptAction.showToast({ message: '书源分组已重命名' });
    } catch (e) {
      console.error('重命名书源分组失败:', e);
      promptAction.showToast({ message: '重命名失败' });
    } finally {
      this.isBatchOperating = false;
    }
  }

  async deleteSourceGroup(): Promise<void> {
    const groupName = this.pendingSourceGroup;
    if (!groupName || this.isBatchOperating) {
      return;
    }
    this.isBatchOperating = true;
    this.batchOperationText = '正在删除书源分组...';
    try {
      const db = AppDatabase.getInstance();
      const groupedSources = this.allSources.filter((source: BookSource) =>
        (source.bookSourceGroup || '').trim() === groupName);
      for (const source of groupedSources) {
        source.bookSourceGroup = '';
        await db.updateBookSourceListFields(source.bookSourceUrl, { bookSourceGroup: '' });
      }
      this.sourceGroups = await BookSourceGroupStore.remove(getContext(this), groupName, this.sourceGroups);
      if (this.activeSourceGroup === groupName) {
        this.activeSourceGroup = '__ungrouped__';
      }
      this.showDeleteSourceGroupDialog = false;
      this.pendingSourceGroup = '';
      await this.loadSources();
      promptAction.showToast({ message: '分组已删除，书源已移到未分组' });
    } catch (e) {
      console.error('删除书源分组失败:', e);
      promptAction.showToast({ message: '删除分组失败' });
    } finally {
      this.isBatchOperating = false;
    }
  }

  applySourceFilters(): void {
    const keyword = this.searchText.trim().toLowerCase();
    let filtered: BookSource[] = this.allSources;
    if (this.activeSourceGroup === '__ungrouped__') {
      filtered = filtered.filter((source: BookSource) => !(source.bookSourceGroup || '').trim());
    } else if (this.activeSourceGroup !== '__all__') {
      filtered = filtered.filter((source: BookSource) =>
        (source.bookSourceGroup || '').trim() === this.activeSourceGroup);
    }
    if (keyword) {
      filtered = filtered.filter((source: BookSource) => {
        const searchable = `${source.bookSourceName || ''}\n${source.bookSourceUrl || ''}\n${source.bookSourceGroup || ''}`;
        return searchable.toLowerCase().includes(keyword);
      });
    }
    this.sources = filtered.slice();
    this.visibleSources = this.sources.slice(0, BOOK_SOURCE_LIST_BATCH_SIZE);
    this.sourceFirstVisibleIndex = 0;
    this.sourceVisibleItemCount = 1;
    this.pruneSelectedSources();
  }

  loadMoreVisibleSources(): void {
    if (this.visibleSources.length >= this.sources.length) {
      return;
    }
    const nextCount = Math.min(this.sources.length, this.visibleSources.length + BOOK_SOURCE_LIST_BATCH_SIZE);
    this.visibleSources = this.sources.slice(0, nextCount);
  }

  ensureActiveSourceGroup(): void {
    if (this.activeSourceGroup === '__all__') {
      return;
    }
    if (this.activeSourceGroup === '__ungrouped__') {
      return;
    }
    if (!this.getSourceGroups().includes(this.activeSourceGroup)) {
      this.activeSourceGroup = '__all__';
    }
  }

  hasUngroupedSources(): boolean {
    return this.allSources.some((source: BookSource) => !(source.bookSourceGroup || '').trim());
  }

  emptySourceTitle(): string {
    if (this.searchText.trim()) {
      return '未找到匹配书源';
    }
    if (this.activeSourceGroup !== '__all__') {
      return '当前分组暂无书源';
    }
    return '暂无书源';
  }

  emptySourceDescription(): string {
    if (this.searchText.trim()) {
      return '请尝试其他关键词';
    }
    if (this.activeSourceGroup !== '__all__') {
      return '可切换其他分组查看';
    }
    return '点击右上角"+"添加书源';
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

  async openSourceActions(source: BookSource, event?: GestureEvent): Promise<void> {
    const finger = event && event.fingerList.length > 0 ? event.fingerList[0] : undefined;
    if (finger) {
      this.contextMenuX = finger.globalX;
      this.contextMenuY = finger.globalY;
    }
    this.actionSourceUrl = source.bookSourceUrl;
    this.actionSourceDetail = null;
    this.showSourceDeleteDialog = false;
    this.showSourceActionDialog = true;
    const detail = await AppDatabase.getInstance().getBookSource(source.bookSourceUrl);
    if (this.actionSourceUrl === source.bookSourceUrl) {
      this.actionSourceDetail = detail;
    }
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
    this.actionSourceDetail = null;
  }

  enterActionSourceSelection(): void {
    const sourceUrl = this.actionSourceUrl;
    if (!sourceUrl) {
      return;
    }
    this.showSourceActionDialog = false;
    this.actionSourceUrl = '';
    this.actionSourceDetail = null;
    this.showAddDialog = false;
    this.showMoreActionDialog = false;
    this.selectionMode = true;
    this.selectedSourceUrls = [sourceUrl];
  }

  actionSource(): BookSource | null {
    if (this.actionSourceDetail && this.actionSourceDetail.bookSourceUrl === this.actionSourceUrl) {
      return this.actionSourceDetail;
    }
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

  actionSourceLocked(): boolean {
    const source = this.actionSource();
    return source ? source.isLocked : false;
  }

  sourceActionMenuHeight(): number {
    if (this.actionSourceLocked()) {
      return this.actionSourceNeedsLogin() ? 232 : 188;
    }
    return this.actionSourceNeedsLogin() ? 364 : 320;
  }

  async toggleActionSourceLocked(): Promise<void> {
    const source = this.actionSource();
    if (!source || this.isBatchOperating) return;
    const locked = !source.isLocked;
    await AppDatabase.getInstance().setBookSourceLocked(source.bookSourceUrl, locked);
    source.isLocked = locked;
    this.closeSourceActions();
    await this.loadSources();
    promptAction.showToast({ message: locked ? '书源已锁定' : '书源已解锁' });
  }

  openActionSourceSearch(): void {
    const source = this.actionSource();
    if (!source) {
      this.closeSourceActions();
      promptAction.showToast({ message: '书源不存在' });
      return;
    }
    const nonce = AppStorage.get<number>('singleSourceSearchNonce') || 0;
    AppStorage.setOrCreate('singleSourceSearchUrl', source.bookSourceUrl);
    AppStorage.setOrCreate('singleSourceSearchName', source.bookSourceName || source.bookSourceUrl);
    AppStorage.setOrCreate('singleSourceSearchNonce', nonce + 1);
    this.closeSourceActions();
    router.back();
  }

  async openActionSourceLogin(): Promise<void> {
    const summary = this.actionSource();
    if (!summary) {
      return;
    }
    const source = await AppDatabase.getInstance().getBookSource(summary.bookSourceUrl);
    if (!source || !this.sourceNeedsLogin(source)) {
      promptAction.showToast({ message: '书源不存在' });
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
    if (source.isLocked) {
      this.closeSourceActions();
      promptAction.showToast({ message: '请先解锁书源' });
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
    this.closeSourceActions();
    await this.toggleSourceEnabled(source);
  }

  async toggleSourceEnabled(source: BookSource): Promise<void> {
    if (this.isBatchOperating) {
      return;
    }
    if (source.isLocked) {
      promptAction.showToast({ message: '锁定的书源不能修改' });
      return;
    }
    const enabled = !source.enabled;
    source.enabled = enabled;
    await this.updateSource(source);
    this.sources = this.sources.map((item: BookSource) =>
      item.bookSourceUrl === source.bookSourceUrl ? source : item);
    this.allSources = this.allSources.map((item: BookSource) =>
      item.bookSourceUrl === source.bookSourceUrl ? source : item);
    this.visibleSources = this.visibleSources.map((item: BookSource) =>
      item.bookSourceUrl === source.bookSourceUrl ? source : item);
    promptAction.showToast({ message: enabled ? '书源已启用' : '书源已禁用' });
  }

  async deleteSourceFromSwipe(source: BookSource): Promise<void> {
    if (this.isBatchOperating) {
      return;
    }
    if (source.isLocked) {
      promptAction.showToast({ message: '锁定的书源不能删除' });
      return;
    }
    this.isBatchOperating = true;
    this.batchOperationText = '正在删除书源...';
    try {
      await AppDatabase.getInstance().deleteBookSource(source.bookSourceUrl);
      this.sources = this.sources.filter((item: BookSource) => item.bookSourceUrl !== source.bookSourceUrl);
      this.allSources = this.allSources.filter((item: BookSource) => item.bookSourceUrl !== source.bookSourceUrl);
      this.visibleSources = this.visibleSources.filter((item: BookSource) => item.bookSourceUrl !== source.bookSourceUrl);
      this.selectedSourceUrls = this.selectedSourceUrls.filter((url: string) => url !== source.bookSourceUrl);
      await this.reconcileSourceGroups();
      promptAction.showToast({ message: '书源已删除' });
    } catch (e) {
      console.error('滑动删除书源失败:', e);
      promptAction.showToast({ message: '删除书源失败' });
    } finally {
      this.isBatchOperating = false;
    }
  }

  async deleteActionSource(): Promise<void> {
    const source = this.actionSource();
    if (!source || this.isBatchOperating) {
      return;
    }
    if (source.isLocked) {
      this.showSourceDeleteDialog = false;
      promptAction.showToast({ message: '锁定的书源不能删除' });
      return;
    }
    this.showSourceDeleteDialog = false;
    this.isBatchOperating = true;
    this.batchOperationText = '正在删除书源...';
    try {
      const db = AppDatabase.getInstance();
      await db.deleteBookSource(source.bookSourceUrl);
      this.sources = this.sources.filter((item: BookSource) => item.bookSourceUrl !== source.bookSourceUrl);
      this.allSources = this.allSources.filter((item: BookSource) => item.bookSourceUrl !== source.bookSourceUrl);
      this.visibleSources = this.visibleSources.filter((item: BookSource) => item.bookSourceUrl !== source.bookSourceUrl);
      this.actionSourceUrl = '';
      await this.reconcileSourceGroups();
      promptAction.showToast({ message: '书源已删除' });
    } catch (e) {
      console.error('删除书源失败:', e);
      promptAction.showToast({ message: '删除书源失败' });
    } finally {
      this.isBatchOperating = false;
    }
  }

  enterSelectionMode(): void {
    this.showAddDialog = false;
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
    return `${source.bookSourceUrl}_${source.bookSourceGroup || ''}_${source.enabled ? '1' : '0'}_${source.enabledExplore ? '1' : '0'}_${source.isLocked ? 'locked' : 'unlocked'}_${source.bookSourceName || ''}_${loginStatus}_${this.selectionMode ? 'select' : 'normal'}`;
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

  getSelectedMutableSources(): BookSource[] {
    return this.getSelectedSources().filter((source: BookSource) => !source.isLocked);
  }

  getSourceGroups(): string[] {
    return [...this.sourceGroups].sort((a: string, b: string) => a.localeCompare(b));
  }

  sourceGroupsFromSources(): string[] {
    const groups: string[] = [];
    for (const source of this.allSources) {
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
    const selectedSources = this.getSelectedMutableSources();
    if (selectedSources.length === 0) {
      promptAction.showToast({ message: '所选书源均已锁定' });
      return;
    }

    const groupName = this.groupNameInput.trim();
    const isNewUserGroup = !!groupName && !this.getSourceGroups().includes(groupName);
    this.isBatchOperating = true;
    this.batchOperationText = '正在设置分组...';
    try {
      const db = AppDatabase.getInstance();
      for (const source of selectedSources) {
        source.bookSourceGroup = groupName;
        await db.updateBookSourceListFields(source.bookSourceUrl, { bookSourceGroup: groupName });
      }
      if (groupName) {
        this.sourceGroups = await BookSourceGroupStore.add(
          getContext(this), groupName, this.sourceGroups, isNewUserGroup);
      }
      this.sources = this.sources.map((source: BookSource) => {
        if (this.isSourceSelected(source.bookSourceUrl) && !source.isLocked) {
          source.bookSourceGroup = groupName;
        }
        return source;
      });
      this.ensureActiveSourceGroup();
      this.applySourceFilters();
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
    const selectedSources = this.getSelectedMutableSources();
    if (selectedSources.length === 0) {
      promptAction.showToast({ message: '所选书源均已锁定' });
      return;
    }

    this.isBatchOperating = true;
    this.batchOperationText = enabled ? '正在启用书源...' : '正在禁用书源...';
    try {
      const db = AppDatabase.getInstance();
      for (const source of selectedSources) {
        source.enabled = enabled;
        await db.updateBookSourceListFields(source.bookSourceUrl, { enabled: enabled ? 1 : 0 });
      }
      this.sources = this.sources.map((source: BookSource) => {
        if (this.isSourceSelected(source.bookSourceUrl) && !source.isLocked) {
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
    const selectedSources = this.getSelectedMutableSources();
    if (selectedSources.length === 0) {
      promptAction.showToast({ message: '所选书源均已锁定' });
      return;
    }

    this.isBatchOperating = true;
    this.batchOperationText = enabled ? '正在启用发现...' : '正在禁用发现...';
    try {
      const db = AppDatabase.getInstance();
      for (const source of selectedSources) {
        source.enabledExplore = enabled;
        await db.updateBookSourceListFields(source.bookSourceUrl, { enabledExplore: enabled ? 1 : 0 });
      }
      this.sources = this.sources.map((source: BookSource) => {
        if (this.isSourceSelected(source.bookSourceUrl) && !source.isLocked) {
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
    const selectedUrls = this.getSelectedMutableSources().map((source: BookSource) => source.bookSourceUrl);
    if (selectedUrls.length === 0) {
      promptAction.showToast({ message: '所选书源均已锁定' });
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
      await db.updateBookSourceListFields(source.bookSourceUrl, {
        bookSourceGroup: source.bookSourceGroup || '',
        enabled: source.enabled ? 1 : 0,
        enabledExplore: source.enabledExplore ? 1 : 0
      });
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

    await this.startCheckSources(enabledSources, action);
  }

  async checkActionSource(): Promise<void> {
    const summary = this.actionSource();
    this.closeSourceActions();
    if (!summary) {
      promptAction.showToast({ message: '书源不存在' });
      return;
    }
    if (this.isCheckingSources) {
      promptAction.showToast({ message: '正在校验中' });
      return;
    }
    const source = await AppDatabase.getInstance().getBookSource(summary.bookSourceUrl);
    if (!source) {
      promptAction.showToast({ message: '书源不存在' });
      return;
    }
    await this.startCheckSources([source], 'none');
  }

  async startCheckSources(targetSources: BookSource[], action: string = 'none'): Promise<void> {
    if (targetSources.length === 0) {
      return;
    }

    this.checkInvalidAction = action === 'disable' || action === 'delete' ? action : 'none';
    this.showCheckOptionsDialog = false;
    this.showCheckDialog = true;
    this.isCheckingSources = true;
    this.checkDone = 0;
    this.checkTotal = targetSources.length;
    this.checkOkCount = 0;
    this.checkBadUrls = [];
    this.checkBadNames = [];
    this.checkAutoHandledCount = 0;
    this.checkStatus = `准备校验 ${targetSources.length} 个书源`;
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
        targetSources: targetSources,
        validationOnly: true
      });

      const badSources = targetSources.filter((source: BookSource) => !availableUrls.has(source.bookSourceUrl));
      this.checkOkCount = Math.max(0, targetSources.length - badSources.length);
      this.checkBadUrls = badSources.map((source: BookSource) => source.bookSourceUrl);
      this.checkBadNames = badSources.map((source: BookSource) => source.bookSourceName || source.bookSourceUrl);
      this.checkDone = targetSources.length;
      this.checkTotal = targetSources.length;
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
    if (source.isLocked) {
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
        this.allSources = this.allSources.filter((item: BookSource) => item.bookSourceUrl !== source.bookSourceUrl);
        this.visibleSources = this.visibleSources.filter(
          (item: BookSource) => item.bookSourceUrl !== source.bookSourceUrl);
      }
      this.checkAutoHandledCount++;
    } catch (e) {
      console.error(`自动${this.checkInvalidAction === 'delete' ? '删除' : '禁用'}无效书源失败:`, e);
    }
  }

  checkSummaryText(): string {
    return `已校验 ${this.checkTotal} 个书源${this.checkAutoActionSummary()}`;
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
      return '没有需要校验的书源';
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
    const lockedUrls = new Set(this.allSources.filter((source: BookSource) => source.isLocked)
      .map((source: BookSource) => source.bookSourceUrl));
    const failedUrls = this.checkBadUrls.filter((url: string) => !lockedUrls.has(url));
    if (failedUrls.length === 0) {
      promptAction.showToast({ message: '异常书源均已锁定，未执行禁用' });
      return;
    }

    this.isBatchOperating = true;
    this.batchOperationText = '正在禁用书源...';
    try {
      const db = AppDatabase.getInstance();
      for (const url of failedUrls) {
        const source = await db.getBookSource(url);
        if (source) {
          source.enabled = false;
          source.lastUpdateTime = Date.now();
          await db.updateBookSource(source);
        }
      }
      const disabledCount = failedUrls.length;
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
    const lockedUrls = new Set(this.allSources.filter((source: BookSource) => source.isLocked)
      .map((source: BookSource) => source.bookSourceUrl));
    const failedUrls = this.checkBadUrls.filter((url: string) => !lockedUrls.has(url));
    if (failedUrls.length === 0) {
      promptAction.showToast({ message: '异常书源均已锁定，未执行删除' });
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

  async handlePendingBookSourceImport(): Promise<void> {
    if (this.isImporting) return;
    const uri = AppStorage.get<string>('pendingBookSourceImportUri') || '';
    if (!uri) return;
    AppStorage.setOrCreate('pendingBookSourceImportUri', '');
    this.isImporting = true;
    try {
      const content = await this.readTextFile(uri);
      if (!content.trim()) {
        promptAction.showToast({ message: '文件内容为空' });
        return;
      }
      await this.importSourcesFromJson(content);
    } catch (e) {
      console.error('打开 JSON 书源文件失败:', e);
      const message = e instanceof Error ? e.message : String(e);
      promptAction.showToast({ message: `导入失败: ${message}` });
    } finally {
      this.isImporting = false;
      if (AppStorage.get<string>('pendingBookSourceImportUri')) {
        this.handlePendingBookSourceImport();
      }
    }
  }

  async exportSelectedSources(): Promise<void> {
    if (this.selectedSourceUrls.length === 0 || this.isBatchOperating) {
      promptAction.showToast({ message: '请先选择书源' });
      return;
    }
    const selectedSummaries = this.sources.filter((source: BookSource) =>
      this.selectedSourceUrls.includes(source.bookSourceUrl));
    if (selectedSummaries.length === 0) {
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
      const selected: BookSource[] = [];
      const db = AppDatabase.getInstance();
      for (const summary of selectedSummaries) {
        const source = await db.getBookSource(summary.bookSourceUrl);
        if (source) selected.push(source);
      }
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
      await db.initWithContext(getContext(this));
      let importCount = 0;
      let failedCount = 0;
      let lastInsertError = '';
      for (const source of sources) {
        if (source.bookSourceUrl && source.bookSourceName) {
          try {
            await db.insertBookSource(source);
            importCount++;
          } catch (insertErr) {
            failedCount++;
            lastInsertError = insertErr instanceof Error ? insertErr.message : String(insertErr);
            console.error('插入书源失败:', source.bookSourceName, insertErr);
          }
        }
      }

      if (importCount === 0) {
        throw new Error(lastInsertError || '书源未能写入本地数据库');
      }

      const loginCount = sources.filter((source: BookSource) => this.sourceNeedsLogin(source)).length;
      const loginMessage = loginCount > 0 ? `，其中 ${loginCount} 个需要登录` : '';
      const failedMessage = failedCount > 0 ? `，${failedCount} 个失败` : '';
      promptAction.showToast({ message: `成功导入 ${importCount} 个书源${failedMessage}${loginMessage}` });
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
    source.isLocked = obj['isLocked'] === true || obj['locked'] === true;
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
