import { router } from '@kit.ArkUI';
import picker from '@ohos.file.picker';
import fs from '@ohos.file.fs';
import { util } from '@kit.ArkTS';
import { HttpTTS, HttpClient } from '@legado/sourceengine';
import { syncSystemBars } from '../utils/SystemBars';
import { SystemTtsReader } from '../utils/SystemTtsReader';
import { ImmersiveBackButton } from '../components/ImmersiveBackButton';
import { TtsSettings, TtsSettingsStore } from '../utils/TtsSettingsStore';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { ResponsiveManagerListLayout } from '../utils/ResponsiveManagerListLayout';
import { FormDraftStore } from '../utils/FormDraftStore';
import deviceInfo from '@ohos.deviceInfo';
import { HdsListItem, HdsSwipeActionOptions } from '@kit.UIDesignKit';
import { SymbolGlyphModifier } from '@kit.ArkUI';
import { HdsFeedback } from '../utils/HdsFeedback';
import { SystemDialogSession } from '../utils/SystemDialogSession';
import { AdaptiveSwitch } from '../components/AdaptiveSwitch';
import { AppFontSize } from '../theme/AppFontSize';
import { AppSpacing } from '../theme/AppSpacing';
import { CollapsingHeader } from '../utils/CollapsingHeader';
import { ImmersiveMaterialRuntime } from '../utils/ImmersiveMaterialRuntime';
import { ImmersiveMaterialSurface } from '../components/ImmersiveMaterialSurface';
import { PopupMenuAction } from '../components/common/PopupMenuAction';

class VoiceEditFormDraft {
  editingVoiceId: string = '';
  name: string = '';
  url: string = '';
  contentType: string = '';
  concurrentRate: string = '';
  loginUrl: string = '';
  loginUi: string = '';
  loginCheckJs: string = '';
  header: string = '';
  jsLib: string = '';
  jsEngine: string = '';
  enabledCookieJar: boolean = false;
}

const CUSTOM_TTS_IMPORT_FILE_LIMIT_BYTES: number = 2 * 1024 * 1024;

@Entry
@Component
struct CustomTtsVoiceManagerPage {
  @StorageProp('immersiveLightLevel') immersiveLightLevel: string = 'adaptive';
  @State headerCollapse: number = 0;
  @StorageLink('ttsCustomVoiceId') ttsCustomVoiceId: string = '';
  @StorageLink('ttsCustomVoices') ttsCustomVoices: string = '';
  @StorageLink('ttsPerson') ttsPerson: number = 0;
  @StorageLink('ttsOnline') ttsOnline: number = 1;
  @StorageLink('ttsStyle') ttsStyle: string = '';
  @StorageLink('ttsLanguage') ttsLanguage: string = 'zh-CN';
  @StorageLink('ttsSpeed') ttsSpeed: number = 1;
  @StorageLink('ttsInstalledVoiceKeys') ttsInstalledVoiceKeys: string = '';
  @StorageLink('ttsCloudVoiceId') ttsCloudVoiceId: string = '';
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
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
  private importUrlDialogSession: SystemDialogSession = new SystemDialogSession();
  private editVoiceDialogSession: SystemDialogSession = new SystemDialogSession();
  @State @Watch('onSystemDialogFlagChanged') showImportUrlDialog: boolean = false;
  @State @Watch('syncShowEditDialog') showEditDialog: boolean = false;
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
  private voiceSelectionAreas: Map<string, number[]> = new Map<string, number[]>();
  private voiceDragVisited: Set<string> = new Set<string>();
  private voiceDragSelectValue: boolean = true;
  private voiceListScroller: Scroller = new Scroller();
  private voiceSelectionDragging: boolean = false;
  private voiceSelectionLastX: number = 0;
  private voiceSelectionLastY: number = 0;
  private voiceSelectionAutoScrollId: number = -1;
  private voiceSelectionAutoDirection: number = 0;
  private voiceSelectionViewportTop: number = 0;
  private voiceSelectionViewportBottom: number = 0;
  private voiceFirstVisibleIndex: number = 0;
  private voiceLastVisibleIndex: number = 0;
  private voiceSelectionSuppressClickUntil: number = 0;

  aboutToAppear(): void {
    this.syncBars();
    this.loadSettings();
    this.restorePersistentVoiceEditDraft();
  }

  onPageShow(): void {
    this.syncBars();
    this.loadSettings();
  }

  onPageHide(): void {
    this.stopVoiceSelectionAutoScroll();
    this.persistVoiceEditDraftNow();
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        // 顶栏随列表上滑跟手收起、下滑展开，与其他二级页面一致。
        Column() {
          this.titleBar()
        }
        .width('100%')
        .height(56 + this.statusBarHeight - this.headerCollapse)
        .clip(true)
        .opacity(CollapsingHeader.contentOpacity(this.headerCollapse))
        .hitTestBehavior(CollapsingHeader.acceptsTouch(this.headerCollapse) ? HitTestMode.Default : HitTestMode.None)
        this.searchBar()
        if (this.selectionMode) {
          this.selectionHeader()
        }

        if (this.filteredVoices().length === 0) {
          Column() {
            Text(this.searchText ? '未找到匹配音色' : '暂无自定义音色')
              .fontSize(AppFontSize.BODY_LARGE)
              .fontColor(this.subTextColor())
            Text('点击右下角“+”导入原版 HttpTTS JSON')
              .fontSize(AppFontSize.BODY)
              .fontColor(this.subTextColor())
              .margin({ top: AppSpacing.MD })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          List({ space: AppSpacing.MD, scroller: this.voiceListScroller }) {
            ForEach(this.filteredVoices(), (voice: HttpTTS) => {
              if (deviceInfo.sdkApiVersion >= 26) {
                HdsListItem({
                  customItemBuilder: () => {
                    this.voiceListItem(voice)
                  },
                  swipeActionOptions: this.voiceSwipeActions(voice)
                })
              } else {
                ListItem() {
                  this.voiceListItem(voice)
                }
                .swipeAction({
                  end: {
                    builder: () => {
                      this.voiceFallbackSwipeActions(voice)
                    },
                    actionAreaDistance: 128,
                    onAction: () => this.deleteVoice(voice)
                  },
                  edgeEffect: SwipeEdgeEffect.Spring
                })
              }
            }, (voice: HttpTTS) => this.voiceKey(voice))

            // 底部避让 spacer 按 lanes 列数复制占满整行，否则多列时最后一行卡片没有底部避让。
            ForEach(this.voiceListSpacerKeys(), (_spacerKey: string) => {
              ListItem() {
                Row()
                  .height(this.voiceListBottomInset())
                  .hitTestBehavior(HitTestMode.None)
              }
            }, (spacerKey: string) => spacerKey)
          }
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
          .width('100%')
          .layoutWeight(1)
          .padding({ left: AppSpacing.XL, right: AppSpacing.XL })
          .clip(true)
          .lanes(ResponsiveManagerListLayout.laneCount(this.contextViewportWidth),
            ResponsiveManagerListLayout.gutter(this.contextViewportWidth))
          .onScrollIndex((start: number, end: number) => {
            this.voiceFirstVisibleIndex = start;
            this.voiceLastVisibleIndex = end;
          })
          .onAreaChange((_oldValue: Area, area: Area) => {
            this.voiceSelectionViewportTop = Number(area.globalPosition.y);
            this.voiceSelectionViewportBottom = this.voiceSelectionViewportTop + Number(area.height);
          })
          .onDidScroll((yOffset: number) => {
            this.headerCollapse = CollapsingHeader.next(this.headerCollapse, yOffset,
              this.voiceListScroller.currentOffset().yOffset);
          })
          .onScrollStop(() => {
            const target = CollapsingHeader.settle(this.headerCollapse, this.voiceListScroller.currentOffset().yOffset);
            if (target !== this.headerCollapse) {
              animateTo({ duration: 200, curve: Curve.FastOutSlowIn }, () => {
                this.headerCollapse = target;
              });
            }
          })
        }

        if (this.selectionMode) {
          this.batchBar()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.pageColor())

      if (!this.selectionMode && !this.isImporting && !this.isBatchOperating) {
        this.addVoiceFloatingButton()
      }

      Column()
        .width(1)
        .height(1)
        .position({ x: this.contextMenuX, y: this.contextMenuY })
        .hitTestBehavior(HitTestMode.None)
        .bindPopup(this.showVoiceActionMenu, ImmersiveMaterialRuntime.popupMenuOptions(this.immersiveLightLevel, (): void => {
          this.voiceActionMenu()
        }, Placement.BottomLeft, this.appDarkMode, this.accentColor(), () => {
          this.showVoiceActionMenu = false;
        }))
    }
    .width('100%')
    .height('100%')
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      const width = Number(newValue.width);
      const height = Number(newValue.height);
      if (Number.isFinite(width) && width > 0) this.contextViewportWidth = width;
      if (Number.isFinite(height) && height > 0) this.contextViewportHeight = height;
    })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  private voiceSwipeActions(voice: HttpTTS): HdsSwipeActionOptions {
    return { icons: [
      {
        icon: new SymbolGlyphModifier(voice.enabled ? $r('sys.symbol.minus_circle') : $r('sys.symbol.checkmark_circle')),
        backgroundColor: this.buttonColor(),
        iconOptions: { accessibilityText: voice.enabled ? '禁用音色' : '启用音色' },
        onAction: () => this.toggleVoiceState(voice)
      },
      { icon: new SymbolGlyphModifier($r('sys.symbol.trash')), backgroundColor: ThemeRuntime.dangerColor(this.appDarkMode), iconOptions: { accessibilityText: '删除音色' }, onAction: () => this.deleteVoice(voice) }
    ] };
  }

  @Builder
  voiceFallbackSwipeActions(voice: HttpTTS) {
    Row() {
      this.voiceDisableSwipeAction(voice)
      this.voiceDeleteSwipeAction(voice)
    }
    .height('100%')
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
      this.ttsCloudVoiceId = settings.cloudVoiceId;
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
    settings.cloudVoiceId = this.ttsCloudVoiceId;
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

  // List.lanes 的列数；底部避让 spacer 按列数复制，保证多列时占满一整行。
  voiceListSpacerKeys(): string[] {
    const laneCount = ResponsiveManagerListLayout.laneCount(this.contextViewportWidth);
    const keys: string[] = [];
    for (let i = 0; i < laneCount; i++) {
      keys.push(`voice_list_spacer_${i}`);
    }
    return keys;
  }

  // 列表底部避让：右下角悬浮新增按钮（52 高，底边距 navBarHeight+22）必须完整让出，
  // 否则最后一条卡片被按钮盖住，左滑露出的操作键无法点按。
  voiceListBottomInset(): number {
    return Math.max(20, this.navBarHeight + 88);
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

  toggleVoiceState(voice: HttpTTS): void {
    const enabled = !voice.enabled;
    this.toggleVoiceEnabled(voice, enabled);
    HdsFeedback.showToast(enabled ? '音色已启用' : '音色已禁用');
  }

  deleteVoice(voice: HttpTTS): void {
    const id = String(voice.id);
    if (this.isCurrentVoice(voice)) {
      this.clearCustomVoiceSelection();
    }
    this.voices = this.voices.filter((item: HttpTTS) => String(item.id) !== id);
    this.selectedVoiceIds = this.selectedVoiceIds.filter((selectedId: string) => selectedId !== id);
    this.saveSettings();
    HdsFeedback.showToast('音色已删除');
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
    this.stopVoiceSelectionAutoScroll();
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
      HdsFeedback.showToast(`已${enabled ? '启用' : '禁用'} ${this.selectedVoiceIds.length} 个音色`);
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
    HdsFeedback.showToast(`已删除 ${count} 个音色`);
  }

  openEditDialog(voice: HttpTTS): void {
    FormDraftStore.removePersistent(getContext(this), 'custom_tts:edit');
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
    this.saveVoiceEditDraft();
  }

  openCreateVoiceDialog(): void {
    FormDraftStore.removePersistent(getContext(this), 'custom_tts:edit');
    this.editingVoiceId = '';
    this.editName = '';
    this.editUrl = '';
    this.editContentType = '';
    this.editConcurrentRate = '';
    this.editLoginUrl = '';
    this.editLoginUi = '';
    this.editLoginCheckJs = '';
    this.editHeader = '';
    this.editJsLib = '';
    this.editJsEngine = '';
    this.editEnabledCookieJar = false;
    this.showEditDialog = true;
    this.saveVoiceEditDraft();
  }

  closeEditDialog(): void {
    this.showEditDialog = false;
    this.editingVoiceId = '';
    FormDraftStore.removePersistent(getContext(this), 'custom_tts:edit');
  }

  restoreVoiceEditDraft(rawValue: string = ''): void {
    const raw = rawValue || FormDraftStore.get('custom_tts:edit');
    if (!raw) return;
    try {
      const draft = JSON.parse(raw) as VoiceEditFormDraft;
      this.editingVoiceId = draft.editingVoiceId;
      this.editName = draft.name;
      this.editUrl = draft.url;
      this.editContentType = draft.contentType;
      this.editConcurrentRate = draft.concurrentRate;
      this.editLoginUrl = draft.loginUrl;
      this.editLoginUi = draft.loginUi;
      this.editLoginCheckJs = draft.loginCheckJs;
      this.editHeader = draft.header;
      this.editJsLib = draft.jsLib;
      this.editJsEngine = draft.jsEngine;
      this.editEnabledCookieJar = draft.enabledCookieJar;
      this.showEditDialog = true;
    } catch (_) {
      FormDraftStore.removePersistent(getContext(this), 'custom_tts:edit');
    }
  }

  async restorePersistentVoiceEditDraft(): Promise<void> {
    const raw = await FormDraftStore.load(getContext(this), 'custom_tts:edit');
    this.restoreVoiceEditDraft(raw);
  }

  saveVoiceEditDraft(): void {
    if (!this.showEditDialog) return;
    const draft = new VoiceEditFormDraft();
    draft.editingVoiceId = this.editingVoiceId;
    draft.name = this.editName;
    draft.url = this.editUrl;
    draft.contentType = this.editContentType;
    draft.concurrentRate = this.editConcurrentRate;
    draft.loginUrl = this.editLoginUrl;
    draft.loginUi = this.editLoginUi;
    draft.loginCheckJs = this.editLoginCheckJs;
    draft.header = this.editHeader;
    draft.jsLib = this.editJsLib;
    draft.jsEngine = this.editJsEngine;
    draft.enabledCookieJar = this.editEnabledCookieJar;
    FormDraftStore.persistSoon(getContext(this), 'custom_tts:edit', JSON.stringify(draft));
  }

  persistVoiceEditDraftNow(): void {
    if (!this.showEditDialog) return;
    const draft = new VoiceEditFormDraft();
    draft.editingVoiceId = this.editingVoiceId;
    draft.name = this.editName;
    draft.url = this.editUrl;
    draft.contentType = this.editContentType;
    draft.concurrentRate = this.editConcurrentRate;
    draft.loginUrl = this.editLoginUrl;
    draft.loginUi = this.editLoginUi;
    draft.loginCheckJs = this.editLoginCheckJs;
    draft.header = this.editHeader;
    draft.jsLib = this.editJsLib;
    draft.jsEngine = this.editJsEngine;
    draft.enabledCookieJar = this.editEnabledCookieJar;
    FormDraftStore.persist(getContext(this), 'custom_tts:edit', JSON.stringify(draft));
  }

  saveEditedVoice(): void {
    const name = this.editName.trim();
    const url = this.editUrl.trim();
    if (!name) {
      HdsFeedback.showToast('请输入音色名称');
      return;
    }
    if (!url) {
      HdsFeedback.showToast('请输入音色 URL');
      return;
    }
    const targetId = this.editingVoiceId;
    if (!targetId) {
      const voice = new HttpTTS();
      voice.id = Date.now();
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
      this.voices = [...this.voices, voice];
      this.saveSettings();
      this.closeEditDialog();
      HdsFeedback.showToast('已新建音色');
      return;
    }
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
    HdsFeedback.showToast('已保存音色');
  }

  async importFromUrl(): Promise<void> {
    const url = this.importUrl.trim();
    if (!url) {
      HdsFeedback.showToast('请输入音色 JSON URL');
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
      HdsFeedback.showToast(`导入失败：${this.shortErrorMessage(error as Object)}`);
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
      HdsFeedback.showToast(`导入失败：${this.shortErrorMessage(error as Object)}`);
    } finally {
      this.isImporting = false;
    }
  }

  importFromJson(content: string): void {
    const incoming = SystemTtsReader.parseCustomVoices(content);
    if (incoming.length === 0) {
      HdsFeedback.showToast('未识别到有效自定义音色');
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
    HdsFeedback.showToast(`已导入 ${changed} 个自定义音色`);
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

  rememberVoiceSelectionArea(voice: HttpTTS, area: Area): void {
    const position = area.globalPosition;
    this.voiceSelectionAreas.set(String(voice.id), [Number(position.x), Number(position.y),
      Number(position.x) + Number(area.width), Number(position.y) + Number(area.height)]);
  }

  @Builder
  voiceSelectionSafeArea(voice: HttpTTS) {
    Stack({ alignContent: Alignment.Center }) {
      Toggle({ type: ToggleType.Checkbox, isOn: this.isVoiceSelected(voice) })
        .selectedColor(this.buttonColor())
        .hitTestBehavior(HitTestMode.None)
    }
    .width(56)
    .height(64)
    .margin({ left: -10, right: AppSpacing.XXS })
    .priorityGesture(
      GestureGroup(GestureMode.Exclusive,
        PanGesture({ direction: PanDirection.Vertical, distance: 2 })
          .onActionStart((event: GestureEvent) => this.beginVoiceSlideSelection(event))
          .onActionUpdate((event: GestureEvent) => this.updateVoiceSlideSelection(event))
          .onActionEnd(() => this.endVoiceSlideSelection())
          .onActionCancel(() => this.endVoiceSlideSelection()),
        TapGesture().onAction(() => {
          if (!this.isBatchOperating) {
            this.voiceSelectionSuppressClickUntil = Date.now() + 240;
            this.toggleVoiceSelected(voice);
          }
        })
      ),
      GestureMask.IgnoreInternal
    )
  }

  beginVoiceSlideSelection(event: GestureEvent): void {
    if (!this.selectionMode || this.isBatchOperating) return;
    this.voiceDragVisited.clear();
    const voice = this.voiceAtGesture(event);
    if (!voice) return;
    this.voiceSelectionDragging = true;
    this.captureVoiceSelectionPoint(event);
    this.voiceDragSelectValue = !this.isVoiceSelected(voice);
    this.applyVoiceSlideSelection(voice);
    this.updateVoiceSelectionAutoScroll();
  }

  updateVoiceSlideSelection(event: GestureEvent): void {
    if (!this.selectionMode || this.isBatchOperating) return;
    this.captureVoiceSelectionPoint(event);
    this.applyVoiceSlideSelection(this.voiceAtGesture(event));
    this.updateVoiceSelectionAutoScroll();
  }

  endVoiceSlideSelection(): void {
    this.voiceSelectionSuppressClickUntil = Date.now() + 240;
    this.voiceSelectionDragging = false;
    this.voiceDragVisited.clear();
    this.stopVoiceSelectionAutoScroll();
  }

  voiceAtGesture(event: GestureEvent): HttpTTS | null {
    const finger = event.fingerList.length > 0 ? event.fingerList[0] : undefined;
    if (!finger) return null;
    return this.voiceAtPoint(finger.globalX, finger.globalY);
  }

  voiceAtPoint(globalX: number, globalY: number): HttpTTS | null {
    for (const voice of this.filteredVoices()) {
      const area = this.voiceSelectionAreas.get(String(voice.id));
      if (area && globalX >= area[0] && globalX <= area[2] &&
        globalY >= area[1] && globalY <= area[3]) return voice;
    }
    return null;
  }

  applyVoiceSlideSelection(voice: HttpTTS | null): void {
    if (!voice) return;
    const id = String(voice.id);
    if (this.voiceDragVisited.has(id)) return;
    this.voiceDragVisited.add(id);
    this.setVoiceSelected(voice, this.voiceDragSelectValue);
  }

  captureVoiceSelectionPoint(event: GestureEvent): void {
    const finger = event.fingerList.length > 0 ? event.fingerList[0] : undefined;
    if (!finger) return;
    this.voiceSelectionLastX = finger.globalX;
    this.voiceSelectionLastY = finger.globalY;
  }

  updateVoiceSelectionAutoScroll(): void {
    if (!this.voiceSelectionDragging || this.voiceSelectionViewportBottom <= this.voiceSelectionViewportTop) {
      this.stopVoiceSelectionAutoScroll();
      return;
    }
    const edgeSize = 72;
    let direction = 0;
    if (this.voiceSelectionLastY <= this.voiceSelectionViewportTop + edgeSize) direction = -1;
    if (this.voiceSelectionLastY >= this.voiceSelectionViewportBottom - edgeSize) direction = 1;
    if (direction === this.voiceSelectionAutoDirection && this.voiceSelectionAutoScrollId >= 0) return;
    this.stopVoiceSelectionAutoScroll();
    if (direction === 0 || this.voiceSelectionReachedBoundary(direction)) return;
    this.voiceSelectionAutoDirection = direction;
    this.voiceSelectionAutoScrollId = setInterval(() => {
      if (!this.voiceSelectionDragging || this.voiceSelectionReachedBoundary(direction)) {
        this.stopVoiceSelectionAutoScroll();
        return;
      }
      this.voiceListScroller.scrollBy(0, direction * 12);
      setTimeout(() => {
        if (!this.voiceSelectionDragging) return;
        this.applyVoiceSlideSelection(this.voiceAtPoint(
          this.voiceSelectionLastX, this.voiceSelectionLastY));
      }, 0);
    }, 24);
  }

  voiceSelectionReachedBoundary(direction: number): boolean {
    if (direction < 0) return this.voiceFirstVisibleIndex <= 0;
    return this.voiceLastVisibleIndex >= this.filteredVoices().length - 1;
  }

  stopVoiceSelectionAutoScroll(): void {
    if (this.voiceSelectionAutoScrollId >= 0) {
      clearInterval(this.voiceSelectionAutoScrollId);
      this.voiceSelectionAutoScrollId = -1;
    }
    this.voiceSelectionAutoDirection = 0;
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
        buttonSize: 40, containerWidth: 56, materialScale: 0.83, compactLayout: true,
        onBack: () => router.back() })

      Text('自定义音色管理')
        .fontSize(AppFontSize.TITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)

      Text(this.selectionMode ? '取消' : '选择')
        .fontSize(AppFontSize.BODY_LARGE)
        .fontColor(this.primaryTextColor())
        .width(52)
        .height(56)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.selectionMode ? this.exitSelectionMode() : this.enterSelectionMode();
        })

    }
    .width('100%')
    .height(56 + this.statusBarHeight)
    .padding({ right: AppSpacing.XL, top: this.statusBarHeight })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  addVoiceFloatingButton() {
    Stack() {
      ImmersiveMaterialSurface({
        surfaceWidth: 52,
        surfaceHeight: 52,
        darkMode: this.appDarkMode,
        fallbackColor: this.cardColor(),
        glowColor: `#40${this.accentColor().substring(1)}`
      }) {
        SymbolGlyph($r('sys.symbol.plus'))
          .fontSize(25)
          .fontColor([this.accentColor()])
      }
    }
    .width(52)
    .height(52)
    .margin({ right: AppSpacing.XXL, bottom: this.navBarHeight + 22 })
    .accessibilityText('新增自定义音色')
    .onClick(() => {
      this.showAddDialog = true;
    })
    .accessibilityRole(AccessibilityRoleType.BUTTON)
    .bindPopup(this.showAddDialog, ImmersiveMaterialRuntime.popupMenuOptions(this.immersiveLightLevel, (): void => {
      this.addDialog()
    }, Placement.TopRight, this.appDarkMode, this.accentColor(), () => {
      this.showAddDialog = false;
    }))
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
        .padding({ left: AppSpacing.XL, right: AppSpacing.XL })
        .onChange((value: string) => {
          this.searchText = value;
          this.pruneSelectedVoices();
        })
    }
    .width('100%')
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.MD, bottom: AppSpacing.MD })
  }

  @Builder
  selectionHeader() {
    Row() {
      Text(this.isAllSelected() ? '☑' : '☐')
        .fontSize(AppFontSize.TITLE)
        .fontColor(this.accentColor())
        .width(28)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.toggleAllVoices();
        })
      Text(`已选择 ${this.selectedVoiceIds.length}/${this.filteredVoices().length}`)
        .fontSize(AppFontSize.BODY)
        .fontColor(this.subTextColor())
        .margin({ left: AppSpacing.MD })
        .layoutWeight(1)
      Text(this.isAllSelected() ? '取消全选' : '全选')
        .fontSize(AppFontSize.BODY)
        .fontColor(this.accentColor())
        .onClick(() => {
          this.toggleAllVoices();
        })
    }
    .width('100%')
    .height(42)
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL })
  }

  @Builder
  voiceListItem(voice: HttpTTS) {
    Row() {
      if (this.selectionMode) {
        this.voiceSelectionSafeArea(voice)
      }

      Column() {
        Text(voice.name || '未命名音色')
          .fontSize(AppFontSize.BODY_LARGE)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(voice.url || '')
          .fontSize(AppFontSize.CAPTION)
          .fontColor(this.subTextColor())
          .margin({ top: AppSpacing.XS })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(voice.enabled ? '已启用' : '已禁用')
          .fontSize(AppFontSize.CAPTION)
          .fontColor(voice.enabled ? ThemeRuntime.successColor(this.appDarkMode) : this.subTextColor())
          .margin({ top: AppSpacing.XS })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(AppSpacing.LG)
    .backgroundColor(this.cardColor())
    .borderRadius(ThemeRuntime.cardRadius())
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
        if (Date.now() < this.voiceSelectionSuppressClickUntil) return;
        this.toggleVoiceSelected(voice);
      }
    })
  }

  @Builder
  voiceDisableSwipeAction(voice: HttpTTS) {
    Column({ space: AppSpacing.XS }) {
      SymbolGlyph(voice.enabled ? $r('sys.symbol.minus_circle') : $r('sys.symbol.checkmark_circle'))
        .fontSize(22)
        .fontColor(['#FFFFFF'])
      Text(voice.enabled ? '禁用' : '启用')
        .fontSize(AppFontSize.CAPTION)
        .fontColor('#FFFFFF')
    }
    .width(64)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(this.buttonColor())
    .onClick(() => {
      if (!this.selectionMode) this.toggleVoiceState(voice);
    })
  }

  @Builder
  voiceDeleteSwipeAction(voice: HttpTTS) {
    Column({ space: AppSpacing.XS }) {
      SymbolGlyph($r('sys.symbol.trash'))
        .fontSize(22)
        .fontColor(['#FFFFFF'])
      Text('删除')
        .fontSize(AppFontSize.CAPTION)
        .fontColor('#FFFFFF')
    }
    .width(64)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(ThemeRuntime.dangerColor(this.appDarkMode))
    .onClick(() => {
      if (!this.selectionMode) this.deleteVoice(voice);
    })
  }

  @Builder
  voiceActionMenu() {
    Scroll() {
      Column() {
        this.voiceContextActionItem($r('sys.symbol.square_and_pencil'), '编辑', this.primaryTextColor(),
          () => this.openActionVoiceEdit())
        this.voiceContextActionItem(this.actionVoice()?.enabled ? $r('sys.symbol.minus_circle') :
          $r('sys.symbol.checkmark_circle'), this.actionVoice()?.enabled ? '禁用' : '启用', this.primaryTextColor(),
          () => this.toggleActionVoiceEnabled())
        this.voiceContextActionItem($r('sys.symbol.list_bullet'), '多选', this.primaryTextColor(),
          () => this.enterActionVoiceSelection())
        this.voiceContextActionItem($r('sys.symbol.trash'), '删除', ThemeRuntime.dangerColor(this.appDarkMode), () => this.deleteActionVoice())

      }
      .width('100%')
    }
    .width(176)
    .constraintSize({ maxHeight: ImmersiveMaterialRuntime.popupMenuMaxHeight() })
    .scrollBar(BarState.Off)
    .padding(ImmersiveMaterialRuntime.POPUP_MENU_PADDING)
  }

  @Builder
  voiceContextActionItem(icon: Resource, label: string, color: string, action: () => void) {
    PopupMenuAction(icon, label, color, action)
  }

  @Builder
  batchBar() {
    Row() {
      Button('启用')
        .layoutWeight(1)
        .height(42)
        .enabled(this.selectedVoiceIds.length > 0 && !this.isBatchOperating)
        .backgroundColor(this.buttonColor())
        .fontColor(ThemeRuntime.onAccentColor())
        .onClick(() => {
          this.batchSetEnabled(true);
        })
      Button('禁用')
        .layoutWeight(1)
        .height(42)
        .margin({ left: AppSpacing.MD })
        .enabled(this.selectedVoiceIds.length > 0 && !this.isBatchOperating)
        .backgroundColor(this.inputColor())
        .fontColor(this.primaryTextColor())
        .onClick(() => {
          this.batchSetEnabled(false);
        })
      Button('删除')
        .layoutWeight(1)
        .height(42)
        .margin({ left: AppSpacing.MD })
        .enabled(this.selectedVoiceIds.length > 0 && !this.isBatchOperating)
        .backgroundColor(ThemeRuntime.dangerColor(this.appDarkMode))
        .fontColor(ThemeRuntime.onAccentColor())
        .onClick(() => {
          this.batchDelete();
        })
    }
    .width('100%')
    .padding({ left: AppSpacing.XL, right: AppSpacing.XL, top: AppSpacing.MD, bottom: AppSpacing.LG })
    .backgroundColor(this.cardColor())
  }

  @Builder
  addDialog() {
    Scroll() {
      Column() {
        this.addVoiceMenuItem('手动新建', () => {
          this.showAddDialog = false;
          this.openCreateVoiceDialog();
        })
        this.addVoiceMenuItem('从 URL 导入', () => {
          this.showAddDialog = false;
          this.importUrl = '';
          this.openImportUrlDialog();
        })
        this.addVoiceMenuItem('从文件导入', () => {
          this.showAddDialog = false;
          this.importFromFile();
        })

      }
      .width('100%')
    }
    .width(176)
    .constraintSize({ maxHeight: ImmersiveMaterialRuntime.popupMenuMaxHeight() })
    .scrollBar(BarState.Off)
    .padding(ImmersiveMaterialRuntime.POPUP_MENU_PADDING)
  }

  @Builder
  addVoiceMenuItem(label: string, action: () => void) {
    PopupMenuAction(undefined, label, this.primaryTextColor(), action)
  }

  onSystemDialogFlagChanged(): void {
    if (!this.showImportUrlDialog) this.importUrlDialogSession.close(this.getUIContext());
  }

  openImportUrlDialog(): void {
    this.showImportUrlDialog = true;
    this.importUrlDialogSession.open(this.getUIContext(), (): void => {
      this.importUrlDialogContent();
    }, {
      autoCancel: true,
      maskColor: ThemeRuntime.scrimColor(this.appDarkMode),
      warnTag: '显示音色URL导入弹窗失败:'
    });
  }

  @Builder
  importUrlDialogContent() {
    Column() {
      Text('从URL导入')
        .fontSize(AppFontSize.SUBTITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ bottom: AppSpacing.LG })
      TextInput({ placeholder: '音色 JSON URL', text: this.importUrl })
        .width('100%')
        .height(44)
        .backgroundColor(this.inputColor())
        .fontColor(this.primaryTextColor())
        .placeholderColor(this.subTextColor())
        .onChange((value: string) => {
          this.importUrl = value;
        })
      Row({ space: AppSpacing.MD }) {
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
          .fontColor(ThemeRuntime.onAccentColor())
          .enabled(!this.isImporting)
          .onClick(() => {
            this.importFromUrl();
          })
      }
      .width('100%')
      .margin({ top: AppSpacing.LG })
    }    .padding(AppSpacing.XXL)
  }


  @Builder
  editVoiceDialog() {
    Column() {
      Text(this.editingVoiceId ? '编辑自定义音色' : '新建自定义音色')
        .fontSize(AppFontSize.SUBTITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ bottom: AppSpacing.LG })

      Scroll() {
        Column({ space: AppSpacing.MD }) {
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
              .fontSize(AppFontSize.BODY_LARGE)
              .fontColor(this.primaryTextColor())
              .layoutWeight(1)
            AdaptiveSwitch({
              isOn: this.editEnabledCookieJar,
              onChange: (value: boolean) => {
                this.editEnabledCookieJar = value;
                this.saveVoiceEditDraft();
              }
            })
          }
          .width('100%')
          .padding({ top: AppSpacing.XS, bottom: AppSpacing.XS })
        }
        .width('100%')
      }
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .width('100%')
      .height(420)

      Row({ space: AppSpacing.MD }) {
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
          .fontColor(ThemeRuntime.onAccentColor())
          .onClick(() => {
            this.saveEditedVoice();
          })
      }
      .width('100%')
      .margin({ top: AppSpacing.LG })
    }
    .width('100%')
    .padding(AppSpacing.XXL)
  }

  syncShowEditDialog(): void {
    this.editVoiceDialogSession.sync(this.getUIContext(), this.showEditDialog, (): void => {
      this.editVoiceDialog();
    }, {
      autoCancel: false,
      maskColor: ThemeRuntime.scrimColor(this.appDarkMode),
      warnTag: '显示编辑音色弹窗失败:'
    });
  }

  @Builder
  editInput(label: string, placeholder: string, value: string, onChange: (value: string) => void) {
    Column() {
      Text(label)
        .fontSize(AppFontSize.CAPTION)
        .fontColor(this.subTextColor())
        .width('100%')
        .margin({ bottom: AppSpacing.XS })
      TextInput({ placeholder, text: value })
        .width('100%')
        .height(42)
        .backgroundColor(this.inputColor())
        .fontColor(this.primaryTextColor())
        .placeholderColor(this.subTextColor())
        .onChange((nextValue: string) => {
          onChange(nextValue);
          this.saveVoiceEditDraft();
        })
    }
    .width('100%')
  }
}
