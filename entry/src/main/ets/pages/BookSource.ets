import { router } from '@kit.ArkUI';
import { BookSource, BookListRule, SearchRule, ExploreRule, BookInfoRule, TocRule, ContentRule } from '../model/data/Book';
import { AppDatabase } from '../model/data/AppDatabase';
import { httpHelper } from '../model/http/HttpHelper';
import { promptAction } from '@kit.ArkUI';
import { syncSystemBars } from '../utils/SystemBars';
import picker from '@ohos.file.picker';
import fs from '@ohos.file.fs';
import { util } from '@kit.ArkTS';

@Entry
@Component
struct BookSourcePage {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
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
  @State importUrl: string = '';

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
        .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THIN)
        .border({ width: 1, color: this.glassBorderColor() })
        .alignItems(VerticalAlign.Center)

        Row() {
          TextInput({ placeholder: '搜索书源', text: this.searchText })
            .layoutWeight(1)
            .height(40)
            .borderRadius(20)
            .backgroundColor(this.glassInputColor())
            .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THIN)
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
            Toggle({ type: ToggleType.Checkbox, isOn: this.isAllSelected() })
              .onChange((isOn: boolean) => {
                if (isOn) {
                  this.selectAllSources();
                } else {
                  this.clearSelection();
                }
              })

            Text(`已选择 ${this.selectedSourceUrls.length}/${this.sources.length}`)
              .fontSize(14)
              .fontColor(this.secondaryTextColor())
              .margin({ left: 8 })
              .layoutWeight(1)

            Text(this.isAllSelected() ? '取消全选' : '全选')
              .fontSize(14)
              .fontColor('#007DFF')
              .onClick(() => {
                if (this.isAllSelected()) {
                  this.clearSelection();
                } else {
                  this.selectAllSources();
                }
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
                        .onChange((isOn: boolean) => {
                          source.enabled = isOn;
                          this.updateSource(source);
                        })

                      Text('编辑')
                        .fontSize(12)
                        .fontColor('#007DFF')
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
                    }
                  }
                  .alignItems(HorizontalAlign.End)
                }
                .width('100%')
                .padding(12)
                .backgroundColor(this.glassCardColor())
                .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THIN)
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

            Button('删除')
              .layoutWeight(1)
              .height(42)
              .margin({ left: 8 })
              .enabled(this.selectedSourceUrls.length > 0)
              .backgroundColor('#E53935')
              .onClick(() => {
                this.showBatchDeleteDialog = true;
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 10, bottom: 12 })
          .backgroundColor(this.glassCardColor())
          .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THIN)
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
              .onClick(() => {
                this.showAddDialog = false;
                this.showImportUrlDialog = true;
              })

            Button('从文件导入')
              .width('100%')
              .height(48)
              .margin({ bottom: 8 })
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
    return this.appDarkMode ? '#191B1F' : '#38FFFFFF';
  }

  inputColor(): string {
    return this.appDarkMode ? '#24272D' : '#F5F5F5';
  }

  glassInputColor(): string {
    return this.appDarkMode ? '#24272D' : '#2EFFFFFF';
  }

  glassBorderColor(): string {
    return this.appDarkMode ? '#00000000' : '#99FFFFFF';
  }

  glassShadowColor(): string {
    return this.appDarkMode ? '#00000000' : '#10000000';
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

  async importFromFile() {
    try {
      const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = ['JSON|.json', '文本|.txt'];
      const pickerResult: Array<string> = await new picker.DocumentViewPicker().select(options);

      if (!pickerResult || pickerResult.length === 0) {
        return;
      }

      promptAction.showToast({ message: '正在导入...' });
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
    }
  }

  async readTextFile(filePath: string): Promise<string> {
    let file: fs.File | null = null;
    try {
      const stat = await fs.stat(filePath);
      if (stat.size <= 0) {
        return '';
      }
      if (stat.size > 5 * 1024 * 1024) {
        throw new Error('文件过大，请选择 5MB 以内的书源文件');
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
    if (!this.importUrl) {
      promptAction.showToast({ message: '请输入URL' });
      return;
    }

    try {
      promptAction.showToast({ message: '正在导入...' });
      console.log('开始从URL导入:', this.importUrl);
      const content = await httpHelper.getBody(this.importUrl);
      console.log('获取到内容长度:', content.length);
      console.log('内容前100字符:', content.substring(0, 100));
      await this.importSourcesFromJson(content);
      this.showImportUrlDialog = false;
      this.importUrl = '';
    } catch (e) {
      console.error('从URL导入失败:', e);
      const errMsg = e instanceof Error ? e.message : String(e);
      promptAction.showToast({ message: `导入失败: ${errMsg}` });
    }
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
    source.loginCheckJs = obj['loginCheckJs'] as string || '';
    source.bookUrlPattern = obj['bookUrlPattern'] as string || '';
    source.searchUrl = obj['searchUrl'] as string || '';
    source.exploreUrl = obj['exploreUrl'] as string || '';
    source.header = obj['header'] as string || '';
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
