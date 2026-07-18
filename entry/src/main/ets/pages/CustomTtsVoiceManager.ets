import { router, promptAction } from '@kit.ArkUI';
import picker from '@ohos.file.picker';
import fs from '@ohos.file.fs';
import { util } from '@kit.ArkTS';
import { HttpTTS } from '../model/data/Book';
import { HttpClient } from '../core/http/HttpClient';
import { syncSystemBars } from '../utils/SystemBars';
import { SystemTtsReader } from '../utils/SystemTtsReader';
import { ImmersiveBackButton } from '../components/ImmersiveBackButton';
import { TtsSettings, TtsSettingsStore } from '../utils/TtsSettingsStore';
import { ThemeRuntime } from '../theme/ThemeRuntime';

const CUSTOM_TTS_IMPORT_FILE_LIMIT_BYTES: number = 2 * 1024 * 1024;

@Entry
@Component
struct CustomTtsVoiceManagerPage {
  @StorageLink('ttsCustomVoiceId') ttsCustomVoiceId: string = '';
  @StorageLink('ttsCustomVoices') ttsCustomVoices: string = '';
  @StorageLink('ttsPerson') ttsPerson: number = 0;
  @StorageLink('ttsOnline') ttsOnline: number = 1;
  @StorageLink('ttsStyle') ttsStyle: string = '';
  @StorageLink('ttsLanguage') ttsLanguage: string = 'zh-CN';
  @StorageLink('ttsSpeed') ttsSpeed: number = 1;
  @StorageLink('ttsInstalledVoiceKeys') ttsInstalledVoiceKeys: string = '';
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('appLightAccentColor') appLightAccentColor: string = '#007DFF';
  @StorageLink('appDarkAccentColor') appDarkAccentColor: string = '#4E9BFF';
  @StorageLink('appLightButtonColor') appLightButtonColor: string = '#007DFF';
  @StorageLink('appDarkButtonColor') appDarkButtonColor: string = '#3F8CFF';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;

  @State voices: HttpTTS[] = [];
  @State searchText: string = '';
  @State selectionMode: boolean = false;
  @State selectedVoiceIds: string[] = [];
  @State showAddDialog: boolean = false;
  @State showImportUrlDialog: boolean = false;
  @State showEditDialog: boolean = false;
  @State importUrl: string = '';
  @State isImporting: boolean = false;
  @State isBatchOperating: boolean = false;
  @State editingVoiceId: string = '';
  @State editName: string = '';
  @State editUrl: string = '';
  @State editContentType: string = '';
  @State editConcurrentRate: string = '';
  @State editLoginUrl: string = '';
  @State editLoginUi: string = '';
  @State editLoginCheckJs: string = '';
  @State editHeader: string = '';
  @State editJsLib: string = '';
  @State editJsEngine: string = '';
  @State editEnabledCookieJar: boolean = false;
  @State showVoiceActionMenu: boolean = false;
  @State actionVoiceId: string = '';
  @State contextMenuX: number = 16;
  @State contextMenuY: number = 96;
  @State contextViewportWidth: number = 360;
  @State contextViewportHeight: number = 720;

  aboutToAppear(): void {
    this.syncBars();
    this.loadSettings();
  }

  onPageShow(): void {
    this.syncBars();
    this.loadSettings();
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        this.titleBar()
        this.searchBar()
        if (this.selectionMode) {
          this.selectionHeader()
        }

        if (this.filteredVoices().length === 0) {
          Column() {
            Text(this.searchText ? '未找到匹配音色' : '暂无自定义音色')
              .fontSize(16)
              .fontColor(this.subTextColor())
            Text('点击右下角“+”导入原版 HttpTTS JSON')
              .fontSize(14)
              .fontColor(this.subTextColor())
              .margin({ top: 8 })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          List({ space: 8 }) {
            ForEach(this.filteredVoices(), (voice: HttpTTS) => {
              ListItem() {
                this.voiceListItem(voice)
              }
              .swipeAction(this.selectionMode ? {} : {
                start: {
                  builder: () => {
                    this.voiceDisableSwipeAction(voice)
                  },
                  actionAreaDistance: 64,
                  onAction: () => {
                    if (!this.selectionMode) this.toggleVoiceState(voice);
                  }
                },
                end: {
                  builder: () => {
                    this.voiceDeleteSwipeAction(voice)
                  },
                  actionAreaDistance: 64,
                  onAction: () => {
                    if (!this.selectionMode) this.deleteVoice(voice);
                  }
                },
                edgeEffect: SwipeEdgeEffect.Spring
              })
            }, (voice: HttpTTS) => this.voiceKey(voice))
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 16, right: 16 })
        }

        if (this.selectionMode) {
          this.batchBar()
        }
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.statusBarHeight, bottom: this.navBarHeight })
      .backgroundColor(this.pageColor())

      if (!this.selectionMode && !this.showAddDialog && !this.isImporting && !this.isBatchOperating) {
        this.addVoiceFloatingButton()
      }

      if (this.showAddDialog) {
        this.addDialog()
      }

      if (this.showImportUrlDialog) {
        this.importUrlDialog()
      }

      if (this.showEditDialog) {
        this.editVoiceDialog()
      }

      if (this.showVoiceActionMenu) {
        this.voiceActionMenu()
      }
    }
    .width('100%')
    .height('100%')
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      const width = Number(newValue.width);
      const height = Number(newValue.height);
      if (Number.isFinite(width) && width > 0) this.contextViewportWidth = width;
      if (Number.isFinite(height) && height > 0) this.contextViewportHeight = height;
    })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  loadSettings(): void {
    TtsSettingsStore.load(getContext(this)).then((settings: TtsSettings) => {
      this.ttsCustomVoiceId = settings.customVoiceId;
      this.ttsCustomVoices = settings.customVoices;
      this.ttsPerson = settings.person;
      this.ttsOnline = settings.online;
      this.ttsStyle = settings.style;
      this.ttsLanguage = settings.language;
      this.ttsSpeed = settings.speed;
      this.ttsInstalledVoiceKeys = settings.installedVoiceKeys;
      this.voices = SystemTtsReader.parseCustomVoices(settings.customVoices);
      this.pruneSelectedVoices();
    }).catch((error: Error) => {
      console.warn('加载自定义音色失败:', error);
      this.voices = SystemTtsReader.parseCustomVoices(this.ttsCustomVoices);
    });
  }

  saveSettings(): void {
    this.ttsCustomVoices = SystemTtsReader.serializeCustomVoices(this.voices);
    const settings = new TtsSettings();
    settings.person = this.ttsPerson;
    settings.online = this.ttsOnline;
    settings.style = this.ttsStyle;
    settings.language = this.ttsLanguage;
    settings.speed = this.ttsSpeed;
    settings.installedVoiceKeys = this.ttsInstalledVoiceKeys;
    settings.customVoiceId = this.ttsCustomVoiceId;
    settings.customVoices = this.ttsCustomVoices;
    TtsSettingsStore.applyToStorage(settings);
    TtsSettingsStore.save(getContext(this), settings).catch((error: Error) => {
      console.warn('保存自定义音色失败:', error);
    });
  }

  filteredVoices(): HttpTTS[] {
    const keyword = this.searchText.trim().toLowerCase();
    if (!keyword) {
      return this.voices;
    }
    return this.voices.filter((voice: HttpTTS) =>
      (voice.name || '').toLowerCase().includes(keyword) ||
      (voice.url || '').toLowerCase().includes(keyword));
  }

  toggleVoiceEnabled(voice: HttpTTS, enabled: boolean): void {
    this.voices = this.voices.map((item: HttpTTS) => {
      if (String(item.id) === String(voice.id)) {
        item.enabled = enabled;
      }
      return item;
    });
    if (!enabled && this.isCurrentVoice(voice)) {
      this.clearCustomVoiceSelection();
    }
    this.saveSettings();
  }

  disableVoice(voice: HttpTTS): void {
    if (!voice.enabled) {
      return;
    }
    this.toggleVoiceEnabled(voice, false);
    promptAction.showToast({ message: '音色已禁用' });
  }

  toggleVoiceState(voice: HttpTTS): void {
    const enabled = !voice.enabled;
    this.toggleVoiceEnabled(voice, enabled);
    promptAction.showToast({ message: enabled ? '音色已启用' : '音色已禁用' });
  }

  deleteVoice(voice: HttpTTS): void {
    const id = String(voice.id);
    if (this.isCurrentVoice(voice)) {
      this.clearCustomVoiceSelection();
    }
    this.voices = this.voices.filter((item: HttpTTS) => String(item.id) !== id);
    this.selectedVoiceIds = this.selectedVoiceIds.filter((selectedId: string) => selectedId !== id);
    this.saveSettings();
    promptAction.showToast({ message: '音色已删除' });
  }

  clearCustomVoiceSelection(): void {
    this.ttsCustomVoiceId = '';
    this.ttsPerson = 0;
    this.ttsOnline = 1;
    this.ttsStyle = '';
    this.ttsLanguage = 'zh-CN';
  }

  enterSelectionMode(): void {
    this.showAddDialog = false;
    this.selectionMode = true;
    this.selectedVoiceIds = [];
  }

  exitSelectionMode(): void {
    this.selectionMode = false;
    this.selectedVoiceIds = [];
  }

  isVoiceSelected(voice: HttpTTS): boolean {
    return this.selectedVoiceIds.includes(String(voice.id));
  }

  setVoiceSelected(voice: HttpTTS, selected: boolean): void {
    const id = String(voice.id);
    if (selected) {
      if (!this.selectedVoiceIds.includes(id)) {
        this.selectedVoiceIds = this.selectedVoiceIds.concat([id]);
      }
    } else {
      this.selectedVoiceIds = this.selectedVoiceIds.filter((item: string) => item !== id);
    }
  }

  toggleVoiceSelected(voice: HttpTTS): void {
    this.setVoiceSelected(voice, !this.isVoiceSelected(voice));
  }

  isAllSelected(): boolean {
    const visible = this.filteredVoices();
    return visible.length > 0 && visible.every((voice: HttpTTS) => this.isVoiceSelected(voice));
  }

  toggleAllVoices(): void {
    const visible = this.filteredVoices();
    if (this.isAllSelected()) {
      const visibleIds = visible.map((voice: HttpTTS) => String(voice.id));
      this.selectedVoiceIds = this.selectedVoiceIds.filter((id: string) => !visibleIds.includes(id));
    } else {
      const ids = this.selectedVoiceIds.slice();
      for (const voice of visible) {
        const id = String(voice.id);
        if (!ids.includes(id)) {
          ids.push(id);
        }
      }
      this.selectedVoiceIds = ids;
    }
  }

  pruneSelectedVoices(): void {
    const ids = this.voices.map((voice: HttpTTS) => String(voice.id));
    this.selectedVoiceIds = this.selectedVoiceIds.filter((id: string) => ids.includes(id));
  }

  batchSetEnabled(enabled: boolean): void {
    if (this.selectedVoiceIds.length === 0) {
      return;
    }
    this.isBatchOperating = true;
    try {
      this.voices = this.voices.map((voice: HttpTTS) => {
        if (this.selectedVoiceIds.includes(String(voice.id))) {
          voice.enabled = enabled;
        }
        return voice;
      });
      if (!enabled && this.selectedVoiceIds.includes(this.ttsCustomVoiceId)) {
        this.clearCustomVoiceSelection();
      }
      this.saveSettings();
      promptAction.showToast({ message: `已${enabled ? '启用' : '禁用'} ${this.selectedVoiceIds.length} 个音色` });
    } finally {
      this.isBatchOperating = false;
    }
  }

  batchDelete(): void {
    if (this.selectedVoiceIds.length === 0) {
      return;
    }
    const count = this.selectedVoiceIds.length;
    if (this.selectedVoiceIds.includes(this.ttsCustomVoiceId)) {
      this.clearCustomVoiceSelection();
    }
    this.voices = this.voices.filter((voice: HttpTTS) => !this.selectedVoiceIds.includes(String(voice.id)));
    this.selectedVoiceIds = [];
    this.exitSelectionMode();
    this.saveSettings();
    promptAction.showToast({ message: `已删除 ${count} 个音色` });
  }

  openEditDialog(voice: HttpTTS): void {
    this.editingVoiceId = String(voice.id);
    this.editName = voice.name || '';
    this.editUrl = voice.url || '';
    this.editContentType = voice.contentType || '';
    this.editConcurrentRate = voice.concurrentRate || '';
    this.editLoginUrl = voice.loginUrl || '';
    this.editLoginUi = voice.loginUi || '';
    this.editLoginCheckJs = voice.loginCheckJs || '';
    this.editHeader = voice.header || '';
    this.editJsLib = voice.jsLib || voice.jsEngine || '';
    this.editJsEngine = voice.jsEngine || voice.jsLib || '';
    this.editEnabledCookieJar = voice.enabledCookieJar === true;
    this.showEditDialog = true;
  }

  closeEditDialog(): void {
    this.showEditDialog = false;
    this.editingVoiceId = '';
  }

  saveEditedVoice(): void {
    const name = this.editName.trim();
    const url = this.editUrl.trim();
    if (!name) {
      promptAction.showToast({ message: '请输入音色名称' });
      return;
    }
    if (!url) {
      promptAction.showToast({ message: '请输入音色 URL' });
      return;
    }
    const targetId = this.editingVoiceId;
    this.voices = this.voices.map((voice: HttpTTS) => {
      if (String(voice.id) === targetId) {
        voice.name = name;
        voice.url = url;
        voice.contentType = this.editContentType.trim();
        voice.concurrentRate = this.editConcurrentRate.trim();
        voice.loginUrl = this.editLoginUrl.trim();
        voice.loginUi = this.editLoginUi.trim();
        voice.loginCheckJs = this.editLoginCheckJs.trim();
        voice.header = this.editHeader.trim();
        voice.jsLib = this.editJsLib.trim() || this.editJsEngine.trim();
        voice.jsEngine = this.editJsEngine.trim() || voice.jsLib;
        voice.enabledCookieJar = this.editEnabledCookieJar;
        voice.lastUpdateTime = Date.now();
      }
      return voice;
    });
    this.saveSettings();
    this.closeEditDialog();
    promptAction.showToast({ message: '已保存音色' });
  }

  async importFromUrl(): Promise<void> {
    const url = this.importUrl.trim();
    if (!url) {
      promptAction.showToast({ message: '请输入音色 JSON URL' });
      return;
    }
    if (this.isImporting) {
      return;
    }
    this.isImporting = true;
    try {
      const response = await new HttpClient(15000).execute({
        url,
        method: 'GET',
        headers: {},
        maxResponseBytes: CUSTOM_TTS_IMPORT_FILE_LIMIT_BYTES
      });
      if (!response.success) {
        throw new Error(response.error || `HTTP ${response.statusCode}`);
      }
      this.importFromJson(response.body);
      this.showImportUrlDialog = false;
      this.showAddDialog = false;
    } catch (error) {
      promptAction.showToast({ message: `导入失败：${this.shortErrorMessage(error as Object)}` });
    } finally {
      this.isImporting = false;
    }
  }

  async importFromFile(): Promise<void> {
    if (this.isImporting) {
      return;
    }
    try {
      const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = ['JSON|.json', '文本|.txt'];
      const result: Array<string> = await new picker.DocumentViewPicker().select(options);
      if (!result || result.length === 0) {
        return;
      }
      this.isImporting = true;
      const content = await this.readTextFile(result[0]);
      this.importFromJson(content);
      this.showAddDialog = false;
    } catch (error) {
      promptAction.showToast({ message: `导入失败：${this.shortErrorMessage(error as Object)}` });
    } finally {
      this.isImporting = false;
    }
  }

  importFromJson(content: string): void {
    const incoming = SystemTtsReader.parseCustomVoices(content);
    if (incoming.length === 0) {
      promptAction.showToast({ message: '未识别到有效自定义音色' });
      return;
    }
    const merged = this.voices.slice();
    let changed = 0;
    for (const voice of incoming) {
      this.ensureUniqueVoiceId(voice, merged);
      const index = merged.findIndex((item: HttpTTS) => String(item.id) === String(voice.id) ||
        ((item.name || '') === (voice.name || '') && (item.url || '') === (voice.url || '')));
      if (index >= 0) {
        merged[index] = voice;
      } else {
        merged.push(voice);
      }
      changed++;
    }
    this.voices = merged;
    this.saveSettings();
    promptAction.showToast({ message: `已导入 ${changed} 个自定义音色` });
  }

  ensureUniqueVoiceId(voice: HttpTTS, existing: HttpTTS[]): void {
    if (!existing.some((item: HttpTTS) => item.id === voice.id && (item.url || '') !== (voice.url || ''))) {
      return;
    }
    let id = Date.now();
    while (existing.some((item: HttpTTS) => item.id === id)) {
      id++;
    }
    voice.id = id;
  }

  async readTextFile(filePath: string): Promise<string> {
    let file: fs.File | null = null;
    try {
      const stat = await fs.stat(filePath);
      if (stat.size <= 0) {
        return '';
      }
      if (stat.size > CUSTOM_TTS_IMPORT_FILE_LIMIT_BYTES) {
        throw new Error('文件过大，请选择 2MB 以内的音色文件');
      }
      file = await fs.open(filePath, fs.OpenMode.READ_ONLY);
      const buffer = new ArrayBuffer(stat.size);
      await fs.read(file.fd, buffer, { offset: 0, length: stat.size });
      return util.TextDecoder.create('utf-8').decodeWithStream(new Uint8Array(buffer), { stream: false })
        .replace(/^\uFEFF/, '');
    } finally {
      if (file) {
        await fs.close(file);
      }
    }
  }

  shortErrorMessage(error: Object | undefined): string {
    if (!error) {
      return '未知错误';
    }
    const anyError = error as Record<string, Object>;
    const message = anyError['message'];
    return message === undefined ? String(error) : String(message);
  }

  isCurrentVoice(voice: HttpTTS): boolean {
    return (this.ttsCustomVoiceId || '') === String(voice.id);
  }

  voiceKey(voice: HttpTTS): string {
    return `${voice.id}_${voice.name || ''}_${voice.enabled ? '1' : '0'}_${this.selectionMode ? 'select' : 'normal'}`;
  }

  openVoiceActions(voice: HttpTTS, event?: GestureEvent): void {
    const finger = event && event.fingerList.length > 0 ? event.fingerList[0] : undefined;
    if (finger) {
      this.contextMenuX = finger.globalX;
      this.contextMenuY = finger.globalY;
    }
    this.actionVoiceId = String(voice.id);
    this.showVoiceActionMenu = true;
  }

  closeVoiceActions(): void {
    this.showVoiceActionMenu = false;
    this.actionVoiceId = '';
  }

  actionVoice(): HttpTTS | null {
    return this.voices.find((voice: HttpTTS) => String(voice.id) === this.actionVoiceId) || null;
  }

  openActionVoiceEdit(): void {
    const voice = this.actionVoice();
    if (!voice) return;
    this.closeVoiceActions();
    this.openEditDialog(voice);
  }

  toggleActionVoiceEnabled(): void {
    const voice = this.actionVoice();
    if (!voice) return;
    this.closeVoiceActions();
    this.toggleVoiceState(voice);
  }

  deleteActionVoice(): void {
    const voice = this.actionVoice();
    if (!voice) return;
    this.closeVoiceActions();
    this.deleteVoice(voice);
  }

  enterActionVoiceSelection(): void {
    const id = this.actionVoiceId;
    if (!id) return;
    this.closeVoiceActions();
    this.showAddDialog = false;
    this.selectionMode = true;
    this.selectedVoiceIds = [id];
  }

  contextMenuLeft(menuWidth: number): number {
    return Math.max(12, Math.min(this.contextMenuX - 18, this.contextViewportWidth - menuWidth - 12));
  }

  contextMenuTop(menuHeight: number): number {
    const below = this.contextMenuY + 12;
    if (below + menuHeight <= this.contextViewportHeight - 12) return below;
    return Math.max(this.statusBarHeight + 8, this.contextMenuY - menuHeight - 12);
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

  inputColor(): string {
    return ThemeRuntime.inputColor(this.appDarkMode);
  }

  primaryTextColor(): string {
    return ThemeRuntime.primaryTextColor(this.appDarkMode);
  }

  subTextColor(): string {
    return ThemeRuntime.subTextColor(this.appDarkMode);
  }

  accentColor(): string {
    return ThemeRuntime.accentColor(this.appDarkMode);
  }

  buttonColor(): string {
    return ThemeRuntime.buttonColor(this.appDarkMode);
  }

  @Builder
  titleBar() {
    Row() {
      ImmersiveBackButton({ iconColor: this.primaryTextColor(), darkMode: this.appDarkMode,
        onBack: () => router.back() })

      Text('自定义音色管理')
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
          this.selectionMode ? this.exitSelectionMode() : this.enterSelectionMode();
        })

    }
    .width('100%')
    .height(56)
    .padding({ right: 16 })
    .backgroundColor(this.cardColor())
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  addVoiceFloatingButton() {
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
    .accessibilityText('新增自定义音色')
    .onClick(() => {
      this.showAddDialog = true;
    })
  }

  @Builder
  searchBar() {
    Row() {
      TextInput({ placeholder: '搜索自定义音色', text: this.searchText })
        .layoutWeight(1)
        .height(40)
        .borderRadius(20)
        .backgroundColor(this.inputColor())
        .fontColor(this.primaryTextColor())
        .placeholderColor(this.subTextColor())
        .padding({ left: 16, right: 16 })
        .onChange((value: string) => {
          this.searchText = value;
          this.pruneSelectedVoices();
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
  }

  @Builder
  selectionHeader() {
    Row() {
      Text(this.isAllSelected() ? '☑' : '☐')
        .fontSize(20)
        .fontColor(this.accentColor())
        .width(28)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.toggleAllVoices();
        })
      Text(`已选择 ${this.selectedVoiceIds.length}/${this.filteredVoices().length}`)
        .fontSize(14)
        .fontColor(this.subTextColor())
        .margin({ left: 8 })
        .layoutWeight(1)
      Text(this.isAllSelected() ? '取消全选' : '全选')
        .fontSize(14)
        .fontColor(this.accentColor())
        .onClick(() => {
          this.toggleAllVoices();
        })
    }
    .width('100%')
    .height(42)
    .padding({ left: 16, right: 16 })
  }

  @Builder
  voiceListItem(voice: HttpTTS) {
    Row() {
      if (this.selectionMode) {
        Toggle({ type: ToggleType.Checkbox, isOn: this.isVoiceSelected(voice) })
          .selectedColor(this.buttonColor())
          .margin({ right: 12 })
          .onChange((isOn: boolean) => {
            this.setVoiceSelected(voice, isOn);
          })
      }

      Column() {
        Text(voice.name || '未命名音色')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(voice.url || '')
          .fontSize(12)
          .fontColor(this.subTextColor())
          .margin({ top: 4 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(voice.enabled ? '已启用' : '已禁用')
          .fontSize(12)
          .fontColor(voice.enabled ? '#1E8E3E' : this.subTextColor())
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.cardColor())
    .borderRadius(8)
    .opacity(voice.enabled ? 1 : 0.45)
    .gesture(
      LongPressGesture({ repeat: false })
        .onAction((event: GestureEvent) => {
          if (!this.selectionMode && !this.isBatchOperating) {
            this.openVoiceActions(voice, event);
          }
        })
    )
    .onClick(() => {
      if (this.selectionMode) {
        this.toggleVoiceSelected(voice);
      }
    })
  }

  @Builder
  voiceDisableSwipeAction(voice: HttpTTS) {
    Column({ space: 4 }) {
      SymbolGlyph(voice.enabled ? $r('sys.symbol.minus_circle') : $r('sys.symbol.checkmark_circle'))
        .fontSize(22)
        .fontColor(['#FFFFFF'])
      Text(voice.enabled ? '禁用' : '启用')
        .fontSize(11)
        .fontColor('#FFFFFF')
    }
    .width(72)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(voice.enabled ? '#F39C3D' : '#1E8E3E')
    .onClick(() => {
      if (!this.selectionMode) this.toggleVoiceState(voice);
    })
  }

  @Builder
  voiceDeleteSwipeAction(voice: HttpTTS) {
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
      if (!this.selectionMode) this.deleteVoice(voice);
    })
  }

  @Builder
  voiceActionMenu() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.appDarkMode ? '#38000000' : '#18FFFFFF')
        .backdropBlur(ThemeRuntime.glassBlur('button', 12))
        .onClick(() => this.closeVoiceActions())
      Column() {
        this.voiceContextActionItem($r('sys.symbol.square_and_pencil'), '编辑', this.primaryTextColor(),
          () => this.openActionVoiceEdit())
        this.voiceContextActionItem(this.actionVoice()?.enabled ? $r('sys.symbol.minus_circle') :
          $r('sys.symbol.checkmark_circle'), this.actionVoice()?.enabled ? '禁用' : '启用', this.primaryTextColor(),
          () => this.toggleActionVoiceEnabled())
        this.voiceContextActionItem($r('sys.symbol.list_bullet'), '多选', this.primaryTextColor(),
          () => this.enterActionVoiceSelection())
        this.voiceContextActionItem($r('sys.symbol.trash'), '删除', '#E53935', () => this.deleteActionVoice())
      }
      .width(148)
      .padding({ top: 6, bottom: 6 })
      .backgroundColor(ThemeRuntime.glassPanelColor(this.appDarkMode, '', 'panel'))
      .borderRadius(ThemeRuntime.glassCornerRadius(14, 'panel'))
      .backdropBlur(ThemeRuntime.glassBlur('panel', 22))
      .border({ width: ThemeRuntime.glassBorderWidth('panel'), color: ThemeRuntime.glassBorderColor(this.appDarkMode, 'panel') })
      .shadow({ radius: ThemeRuntime.glassShadowRadius('panel'), color: ThemeRuntime.glassShadowColor(this.appDarkMode, 'panel'), offsetX: ThemeRuntime.glassShadowOffsetX('panel'), offsetY: ThemeRuntime.glassShadowOffsetY('panel') })
      .position({ x: this.contextMenuLeft(148), y: this.contextMenuTop(188) })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  voiceContextActionItem(icon: Resource, label: string, color: string, action: () => void) {
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
  batchBar() {
    Row() {
      Button('启用')
        .layoutWeight(1)
        .height(42)
        .enabled(this.selectedVoiceIds.length > 0 && !this.isBatchOperating)
        .backgroundColor(this.buttonColor())
        .fontColor('#FFFFFF')
        .onClick(() => {
          this.batchSetEnabled(true);
        })
      Button('禁用')
        .layoutWeight(1)
        .height(42)
        .margin({ left: 8 })
        .enabled(this.selectedVoiceIds.length > 0 && !this.isBatchOperating)
        .backgroundColor(this.inputColor())
        .fontColor(this.primaryTextColor())
        .onClick(() => {
          this.batchSetEnabled(false);
        })
      Button('删除')
        .layoutWeight(1)
        .height(42)
        .margin({ left: 8 })
        .enabled(this.selectedVoiceIds.length > 0 && !this.isBatchOperating)
        .backgroundColor('#E53935')
        .fontColor('#FFFFFF')
        .onClick(() => {
          this.batchDelete();
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 12 })
    .backgroundColor(this.cardColor())
  }

  @Builder
  addDialog() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column()
        .width('100%')
        .height('100%')
        .onClick(() => {
          this.showAddDialog = false;
        })

      Column() {
        this.addVoiceMenuItem('从 URL 导入', () => {
          this.showAddDialog = false;
          this.importUrl = '';
          this.showImportUrlDialog = true;
        })
        this.addVoiceMenuItem('从文件导入', () => {
          this.showAddDialog = false;
          this.importFromFile();
        }, false)
      }
      .width(176)
      .padding(6)
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
  addVoiceMenuItem(label: string, action: () => void, showDivider: boolean = true) {
    Column() {
      Text(label)
        .fontSize(15)
        .fontColor(this.primaryTextColor())
        .width('100%')
        .height(44)
        .padding({ left: 12, right: 12 })
        .textAlign(TextAlign.Start)
      if (showDivider) {
        Divider()
          .strokeWidth(0.5)
          .color(ThemeRuntime.glassBorderColor(this.appDarkMode))
          .margin({ left: 12, right: 12 })
      }
    }
    .width('100%')
    .onClick(action)
  }

  @Builder
  importUrlDialog() {
    Column() {
      Column() {
        Text('从URL导入')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ bottom: 14 })
        TextInput({ placeholder: '音色 JSON URL', text: this.importUrl })
          .width('100%')
          .height(44)
          .backgroundColor(this.inputColor())
          .fontColor(this.primaryTextColor())
          .placeholderColor(this.subTextColor())
          .onChange((value: string) => {
            this.importUrl = value;
          })
        Row({ space: 10 }) {
          Button('取消')
            .layoutWeight(1)
            .height(42)
            .backgroundColor(this.inputColor())
            .fontColor(this.primaryTextColor())
            .onClick(() => {
              this.showImportUrlDialog = false;
            })
          Button(this.isImporting ? '导入中' : '导入')
            .layoutWeight(1)
            .height(42)
            .backgroundColor(this.buttonColor())
            .fontColor('#FFFFFF')
            .enabled(!this.isImporting)
            .onClick(() => {
              this.importFromUrl();
            })
        }
        .width('100%')
        .margin({ top: 14 })
      }
      .width('86%')
      .padding(20)
      .backgroundColor(this.cardColor())
      .borderRadius(12)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#66000000')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  editVoiceDialog() {
    Column() {
      Column() {
        Text('编辑自定义音色')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ bottom: 14 })

        Scroll() {
          Column({ space: 10 }) {
            this.editInput('名称', '音色名称', this.editName, (value: string) => {
              this.editName = value;
            })
            this.editInput('URL', '请求 URL', this.editUrl, (value: string) => {
              this.editUrl = value;
            })
            this.editInput('请求头', 'header，可留空', this.editHeader, (value: string) => {
              this.editHeader = value;
            })
            this.editInput('内容类型', 'contentType，可留空，如 audio/.*', this.editContentType, (value: string) => {
              this.editContentType = value;
            })
            this.editInput('并发率', 'concurrentRate，可留空', this.editConcurrentRate, (value: string) => {
              this.editConcurrentRate = value;
            })
            this.editInput('登录URL', 'loginUrl，可留空', this.editLoginUrl, (value: string) => {
              this.editLoginUrl = value;
            })
            this.editInput('登录UI', 'loginUi，可留空', this.editLoginUi, (value: string) => {
              this.editLoginUi = value;
            })
            this.editInput('登录检查JS', 'loginCheckJs，可留空', this.editLoginCheckJs, (value: string) => {
              this.editLoginCheckJs = value;
            })
            this.editInput('JS库', 'jsLib，可留空', this.editJsLib, (value: string) => {
              this.editJsLib = value;
            })
            this.editInput('JS引擎', 'jsEngine，兼容旧字段，可留空', this.editJsEngine, (value: string) => {
              this.editJsEngine = value;
            })
            Row() {
              Text('启用 CookieJar')
                .fontSize(15)
                .fontColor(this.primaryTextColor())
                .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.editEnabledCookieJar })
                .selectedColor(this.buttonColor())
                .onChange((value: boolean) => {
                  this.editEnabledCookieJar = value;
                })
            }
            .width('100%')
            .padding({ top: 4, bottom: 4 })
          }
          .width('100%')
        }
        .width('100%')
        .height(420)

        Row({ space: 10 }) {
          Button('取消')
            .layoutWeight(1)
            .height(42)
            .backgroundColor(this.inputColor())
            .fontColor(this.primaryTextColor())
            .onClick(() => {
              this.closeEditDialog();
            })
          Button('保存')
            .layoutWeight(1)
            .height(42)
            .backgroundColor(this.buttonColor())
            .fontColor('#FFFFFF')
            .onClick(() => {
              this.saveEditedVoice();
            })
        }
        .width('100%')
        .margin({ top: 14 })
      }
      .width('90%')
      .padding(20)
      .backgroundColor(this.cardColor())
      .borderRadius(12)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#66000000')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  editInput(label: string, placeholder: string, value: string, onChange: (value: string) => void) {
    Column() {
      Text(label)
        .fontSize(12)
        .fontColor(this.subTextColor())
        .width('100%')
        .margin({ bottom: 4 })
      TextInput({ placeholder, text: value })
        .width('100%')
        .height(42)
        .backgroundColor(this.inputColor())
        .fontColor(this.primaryTextColor())
        .placeholderColor(this.subTextColor())
        .onChange(onChange)
    }
    .width('100%')
  }
}
