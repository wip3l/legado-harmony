import { router, window } from '@kit.ArkUI';
import { KeyboardAvoidMode } from '@ohos.arkui.UIContext';
import { BookSource } from '../model/data/Book';
import { AppDatabase } from '../model/data/AppDatabase';
import { syncSystemBars } from '../utils/SystemBars';
import { ThemeRuntime } from '../theme/ThemeRuntime';
import { ImmersiveBackButton } from '../components/ImmersiveBackButton';
import { FormDraftStore } from '../utils/FormDraftStore';
import { HdsFeedback } from '../utils/HdsFeedback';
import { SystemDialogSession } from '../utils/SystemDialogSession';

class BookSourceEditDraft {
  sourceJson: string = '';
  savedSnapshot: string = '';
  currentTab: number = 0;
}

@Entry
@Component
struct BookSourceEditPage {
  @StorageLink('appDarkMode') appDarkMode: boolean = false;
  @StorageLink('themeRevision') themeRevision: number = 0;
  @StorageLink('appLightAccentColor') appLightAccentColor: string = '#007DFF';
  @StorageLink('appDarkAccentColor') appDarkAccentColor: string = '#4E9BFF';
  @StorageLink('appLightButtonColor') appLightButtonColor: string = '#007DFF';
  @StorageLink('appDarkButtonColor') appDarkButtonColor: string = '#3F8CFF';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  @State bookSourceUrl: string = '';
  @State source: BookSource = new BookSource();
  @State isLoading: boolean = false;
  @State currentTab: number = 0;
  @State sourceLoadedVersion: number = 0;
  @State savedSourceSnapshot: string = '';
  private unsavedDialogSession: SystemDialogSession = new SystemDialogSession();
  private draftConflictDialogSession: SystemDialogSession = new SystemDialogSession();
  @State @Watch('onSystemDialogFlagChanged') showUnsavedDialog: boolean = false;
  @State @Watch('onSystemDialogFlagChanged') showDraftConflictDialog: boolean = false;
  @State keyboardInset: number = 0;
  private keyboardAvoidModeConfigured: boolean = false;
  private previousKeyboardAvoidMode: KeyboardAvoidMode = KeyboardAvoidMode.OFFSET;
  private sourceInitialized: boolean = false;
  private draftSaveTimerId: number = -1;
  private conflictingDraftRaw: string = '';
  private keyboardWindow: window.Window | null = null;
  private keyboardAvoidAreaCallback: (data: window.AvoidAreaOptions) => void =
    (data: window.AvoidAreaOptions): void => {
      if (data.type === window.AvoidAreaType.TYPE_KEYBOARD) {
        this.keyboardInset = this.keyboardAvoidAreaHeight(data.area);
      }
    };

  aboutToAppear() {
    this.syncBars();
    this.configureKeyboardAvoidanceMode();
    this.registerKeyboardAvoidance();
    if (this.sourceInitialized) return;
    this.sourceInitialized = true;
    const params = router.getParams() as Record<string, string>;
    this.bookSourceUrl = params && params['bookSourceUrl'] ? params['bookSourceUrl'] : '';
    this.initializeSourceForm();
  }

  onPageShow(): void {
    this.syncBars();
    this.configureKeyboardAvoidanceMode();
    this.registerKeyboardAvoidance();
  }

  onPageHide(): void {
    this.persistDraftNow();
    this.unregisterKeyboardAvoidance();
    this.restoreKeyboardAvoidanceMode();
  }

  async initializeSourceForm(): Promise<void> {
    // Existing sources must be loaded before drafts. An import may have updated
    // the database while an older unsaved draft still exists for the same URL.
    // Restoring that draft first would hide the imported version and could save
    // the old rules back over it without warning.
    this.isLoading = true;
    try {
      if (this.bookSourceUrl) {
        await this.loadSource();
        const raw = await FormDraftStore.load(getContext(this), this.draftKey());
        if (!raw) return;
        try {
          const draft = JSON.parse(raw) as BookSourceEditDraft;
          if (!draft.sourceJson) {
            FormDraftStore.removePersistent(getContext(this), this.draftKey());
            return;
          }
          if (draft.savedSnapshot && draft.savedSnapshot === this.savedSourceSnapshot) {
            this.restoreDraft(raw);
            return;
          }
          this.conflictingDraftRaw = raw;
          this.openDraftConflictDialog();
        } catch (_) {
          FormDraftStore.removePersistent(getContext(this), this.draftKey());
        }
        return;
      }
      const restored = await this.restorePersistentDraft();
      if (!restored) this.markSourceSaved();
    } finally {
      this.isLoading = false;
    }
  }

  async loadSource() {
    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      const source = await db.getBookSource(this.bookSourceUrl);
      if (source) {
        this.source = source;
        this.markSourceSaved();
        this.currentTab = 0;
        this.sourceLoadedVersion++;
      }
    } catch (e) {
      console.error('加载书源失败:', e);
    }
  }

  async saveSource() {
    if (this.source.isLocked) {
      HdsFeedback.showToast('锁定的书源不能修改，请先在书源管理中解锁');
      return;
    }
    if (!this.source.bookSourceUrl) {
      HdsFeedback.showToast('请输入书源地址');
      return;
    }
    if (!this.source.bookSourceName) {
      HdsFeedback.showToast('请输入书源名称');
      return;
    }

    try {
      const db = AppDatabase.getInstance();
      await db.initWithContext(getContext(this));
      const originalUrl = this.bookSourceUrl || this.source.bookSourceUrl;
      const existing = await db.getBookSource(originalUrl);
      if (originalUrl !== this.source.bookSourceUrl) {
        const conflicting = await db.getBookSource(this.source.bookSourceUrl);
        if (conflicting) {
          HdsFeedback.showToast('新的书源地址已存在，请更换地址后再保存');
          return;
        }
      }
      this.synchronizeRawSourceJson();
      this.source.validationStatus = BookSource.VALIDATION_UNCHECKED;
      if (existing) {
        await db.updateBookSource(this.source, originalUrl);
      } else {
        await db.insertBookSource(this.source);
      }
      this.clearDraft();
      this.markSourceSaved();
      HdsFeedback.showToast('保存成功');
      router.back();
    } catch (e) {
      console.error('保存书源失败:', e);
      HdsFeedback.showToast('保存失败');
    }
  }

  async saveSourceAndBackFromDialog(): Promise<void> {
    if (!this.source.bookSourceUrl) {
      HdsFeedback.showToast('请输入书源地址');
      return;
    }
    if (!this.source.bookSourceName) {
      HdsFeedback.showToast('请输入书源名称');
      return;
    }
    this.showUnsavedDialog = false;
    await this.saveSource();
  }

  build() {
    Stack() {
      Column() {
        Row() {
          ImmersiveBackButton({ iconColor: this.primaryTextColor(), darkMode: this.appDarkMode,
            buttonSize: 40, containerWidth: 56, materialScale: 0.83, compactLayout: true,
            onBack: () => this.requestBack() })

          Text(this.bookSourceUrl ? '编辑书源' : '新建书源')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.primaryTextColor())
            .layoutWeight(1)

          Text('保存')
            .fontSize(16)
            .fontColor(this.accentColor())
            .width(60)
            .height(56)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.saveSource();
            })

          Text('调试')
            .fontSize(16)
            .fontColor(this.accentColor())
            .width(60)
            .height(56)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.openDebugDraft();
            })
        }
        .width('100%')
        .height(56 + this.statusBarHeight)
        .padding({ top: this.statusBarHeight })
        .backgroundColor(ThemeRuntime.topBarColor(this.appDarkMode))
        .backdropBlur(ThemeRuntime.topBarBlur())
        .alignItems(VerticalAlign.Center)

        // Tab栏
        Row() {
          Text('基本')
            .fontSize(14)
            .fontColor(this.currentTab === 0 ? this.accentColor() : this.secondaryTextColor())
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .padding({ top: 12, bottom: 12 })
            .borderWidth({ bottom: this.currentTab === 0 ? 2 : 0 })
            .borderColor(this.accentColor())
            .onClick(() => {
              this.currentTab = 0;
            })

          Text('搜索')
            .fontSize(14)
            .fontColor(this.currentTab === 1 ? this.accentColor() : this.secondaryTextColor())
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .padding({ top: 12, bottom: 12 })
            .borderWidth({ bottom: this.currentTab === 1 ? 2 : 0 })
            .borderColor(this.accentColor())
            .onClick(() => {
              this.currentTab = 1;
            })

          Text('发现')
            .fontSize(14)
            .fontColor(this.currentTab === 2 ? this.accentColor() : this.secondaryTextColor())
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .padding({ top: 12, bottom: 12 })
            .borderWidth({ bottom: this.currentTab === 2 ? 2 : 0 })
            .borderColor(this.accentColor())
            .onClick(() => {
              this.currentTab = 2;
            })

          Text('详情')
            .fontSize(14)
            .fontColor(this.currentTab === 3 ? this.accentColor() : this.secondaryTextColor())
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .padding({ top: 12, bottom: 12 })
            .borderWidth({ bottom: this.currentTab === 3 ? 2 : 0 })
            .borderColor(this.accentColor())
            .onClick(() => {
              this.currentTab = 3;
            })

          Text('目录')
            .fontSize(14)
            .fontColor(this.currentTab === 4 ? this.accentColor() : this.secondaryTextColor())
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .padding({ top: 12, bottom: 12 })
            .borderWidth({ bottom: this.currentTab === 4 ? 2 : 0 })
            .borderColor(this.accentColor())
            .onClick(() => {
              this.currentTab = 4;
            })

          Text('正文')
            .fontSize(14)
            .fontColor(this.currentTab === 5 ? this.accentColor() : this.secondaryTextColor())
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .padding({ top: 12, bottom: 12 })
            .borderWidth({ bottom: this.currentTab === 5 ? 2 : 0 })
            .borderColor(this.accentColor())
            .onClick(() => {
              this.currentTab = 5;
            })
        }
        .width('100%')
        .backgroundColor(this.cardColor())
        .borderWidth({ bottom: 1 })
        .borderColor(this.dividerColor())

        if (this.isLoading) {
          Column() {
            LoadingProgress()
              .width(40)
              .height(40)
            Text('加载书源中...')
              .fontSize(14)
              .fontColor(this.secondaryTextColor())
              .margin({ top: 8 })
          }
          .layoutWeight(1)
          .width('100%')
          .justifyContent(FlexAlign.Center)
        } else {
          // 内容区域
          Scroll() {
            Column() {
              if (this.currentTab === 0) {
                this.basicTabBuilder()
              } else if (this.currentTab === 1) {
                this.searchTabBuilder()
              } else if (this.currentTab === 2) {
                this.exploreTabBuilder()
              } else if (this.currentTab === 3) {
                this.infoTabBuilder()
              } else if (this.currentTab === 4) {
                this.tocTabBuilder()
              } else if (this.currentTab === 5) {
                this.contentTabBuilder()
              }
            }
            .id(`book_source_form_${this.currentTab}_${this.sourceLoadedVersion}`)
            .width('100%')
            // RESIZE mode already reduces this Scroll viewport above the keyboard.
            // Do not add the full keyboard avoid height again, otherwise the form
            // gets a large blank tail and the last editor can be pushed out of view.
            .padding({ left: 16, right: 16, top: 16, bottom: 16 + this.navBarHeight })
          }
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
          .layoutWeight(1)
          .scrollBar(BarState.Off)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.pageColor())
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])


    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  openDebugDraft(): void {
    if (!this.source.bookSourceUrl) {
      HdsFeedback.showToast('请先填写书源地址');
      return;
    }
    this.synchronizeRawSourceJson();
    AppStorage.setOrCreate('bookSourceDebugDraftJson', JSON.stringify(this.source));
    router.pushUrl({ url: 'pages/BookSourceDebug', params: { bookSourceUrl: this.source.bookSourceUrl } });
  }

  onBackPress(): boolean {
    return this.requestBack();
  }

  requestBack(): boolean {
    if (this.hasUnsavedChanges()) {
      this.openUnsavedDialog();
      return true;
    }
    router.back();
    return true;
  }

  hasUnsavedChanges(): boolean {
    return this.sourceSnapshot() !== this.savedSourceSnapshot;
  }

  markSourceSaved(): void {
    this.savedSourceSnapshot = this.sourceSnapshot();
  }

  /** Keep the lossless import snapshot aligned with manual edits, including fields cleared to an empty string. */
  synchronizeRawSourceJson(): void {
    let raw: Record<string, Object> = {};
    try {
      const parsed = JSON.parse(this.source.rawSourceJson || '{}') as Object;
      if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
        raw = parsed as Record<string, Object>;
      }
    } catch (_) {}
    raw['bookSourceUrl'] = this.source.bookSourceUrl;
    raw['bookSourceName'] = this.source.bookSourceName;
    raw['bookSourceType'] = this.source.bookSourceType;
    raw['bookSourceGroup'] = this.source.bookSourceGroup;
    raw['bookSourceComment'] = this.source.bookSourceComment;
    raw['loginUrl'] = this.source.loginUrl;
    raw['loginUi'] = this.source.loginUi;
    raw['loginCheckJs'] = this.source.loginCheckJs;
    raw['loginHeader'] = this.source.loginHeader;
    // Runtime login state is not a source-definition field and must not be copied into exports.
    raw['loginInfo'] = '';
    raw['bookUrlPattern'] = this.source.bookUrlPattern;
    raw['searchUrl'] = this.source.searchUrl;
    raw['exploreUrl'] = this.source.exploreUrl;
    raw['jsLib'] = this.source.jsLib;
    raw['header'] = this.source.header;
    raw['variableComment'] = this.source.variableComment;
    raw['variable'] = this.source.variable;
    raw['enabledCookieJar'] = this.source.enabledCookieJar;
    raw['enabled'] = this.source.enabled;
    raw['enabledExplore'] = this.source.enabledExplore;
    raw['weight'] = this.source.weight;
    raw['ruleSearch'] = this.mergeRuleForRawSource(raw['ruleSearch'], this.source.searchRule);
    raw['ruleExplore'] = this.mergeRuleForRawSource(raw['ruleExplore'], this.source.exploreRule);
    raw['ruleBookInfo'] = this.mergeRuleForRawSource(raw['ruleBookInfo'], this.source.bookInfoRule);
    raw['ruleToc'] = this.mergeRuleForRawSource(raw['ruleToc'], this.source.tocRule);
    raw['ruleContent'] = this.mergeRuleForRawSource(raw['ruleContent'], this.source.contentRule);
    this.source.rawSourceJson = JSON.stringify(raw);
  }

  mergeRuleForRawSource(rawRule: Object | undefined, editedRule: Object): Object {
    const merged: Record<string, Object> = {};
    if (rawRule && typeof rawRule === 'object' && !Array.isArray(rawRule)) {
      const rawRecord = rawRule as Record<string, Object>;
      for (const key of Object.keys(rawRecord)) merged[key] = rawRecord[key];
    }
    const edited = JSON.parse(JSON.stringify(editedRule || {})) as Record<string, Object>;
    for (const key of Object.keys(edited)) merged[key] = edited[key];
    return merged;
  }

  draftKey(): string {
    return `book_source_edit:${this.bookSourceUrl || '__new__'}`;
  }

  restoreDraft(rawValue: string = ''): boolean {
    const raw = rawValue || FormDraftStore.get(this.draftKey());
    if (!raw) return false;
    try {
      const draft = JSON.parse(raw) as BookSourceEditDraft;
      this.source = JSON.parse(draft.sourceJson) as BookSource;
      this.savedSourceSnapshot = draft.savedSnapshot || '';
      this.currentTab = Math.max(0, Math.min(draft.currentTab || 0, 5));
      this.sourceLoadedVersion++;
      return true;
    } catch (_) {
      FormDraftStore.removePersistent(getContext(this), this.draftKey());
      return false;
    }
  }

  async restorePersistentDraft(): Promise<boolean> {
    const raw = await FormDraftStore.load(getContext(this), this.draftKey());
    return this.restoreDraft(raw);
  }

  scheduleDraftSave(): void {
    if (this.draftSaveTimerId >= 0) clearTimeout(this.draftSaveTimerId);
    this.draftSaveTimerId = setTimeout(() => {
      this.draftSaveTimerId = -1;
      const draft = new BookSourceEditDraft();
      draft.sourceJson = JSON.stringify(this.source);
      draft.savedSnapshot = this.savedSourceSnapshot;
      draft.currentTab = this.currentTab;
      const raw = JSON.stringify(draft);
      FormDraftStore.persistSoon(getContext(this), this.draftKey(), raw);
    }, 60);
  }

  persistDraftNow(): void {
    if (!this.hasUnsavedChanges()) return;
    if (this.draftSaveTimerId >= 0) {
      clearTimeout(this.draftSaveTimerId);
      this.draftSaveTimerId = -1;
    }
    const draft = new BookSourceEditDraft();
    draft.sourceJson = JSON.stringify(this.source);
    draft.savedSnapshot = this.savedSourceSnapshot;
    draft.currentTab = this.currentTab;
    FormDraftStore.persist(getContext(this), this.draftKey(), JSON.stringify(draft));
  }

  clearDraft(): void {
    if (this.draftSaveTimerId >= 0) {
      clearTimeout(this.draftSaveTimerId);
      this.draftSaveTimerId = -1;
    }
    this.savedSourceSnapshot = this.sourceSnapshot();
    FormDraftStore.removePersistent(getContext(this), this.draftKey());
  }

  useImportedSourceInsteadOfDraft(): void {
    this.conflictingDraftRaw = '';
    this.showDraftConflictDialog = false;
    this.clearDraft();
  }

  restoreConflictingDraft(): void {
    const raw = this.conflictingDraftRaw;
    this.conflictingDraftRaw = '';
    this.showDraftConflictDialog = false;
    if (!raw || !this.restoreDraft(raw)) {
      HdsFeedback.showToast('草稿已失效，已使用最新书源');
    }
  }

  sourceSnapshot(): string {
    const parts: string[] = [];
    this.appendSnapshotPart(parts, this.source.bookSourceUrl);
    this.appendSnapshotPart(parts, this.source.bookSourceName);
    this.appendSnapshotPart(parts, String(this.source.bookSourceType));
    this.appendSnapshotPart(parts, this.source.bookSourceGroup);
    this.appendSnapshotPart(parts, this.source.bookSourceComment);
    this.appendSnapshotPart(parts, this.source.loginUrl);
    this.appendSnapshotPart(parts, this.source.loginUi);
    this.appendSnapshotPart(parts, this.source.loginCheckJs);
    this.appendSnapshotPart(parts, this.source.loginHeader);
    this.appendSnapshotPart(parts, this.source.bookUrlPattern);
    this.appendSnapshotPart(parts, this.source.searchUrl);
    this.appendSnapshotPart(parts, this.source.exploreUrl);
    this.appendSnapshotPart(parts, this.source.jsLib);
    this.appendSnapshotPart(parts, this.source.header);
    this.appendSnapshotPart(parts, this.source.variable);
    this.appendSnapshotPart(parts, this.source.enabledCookieJar ? '1' : '0');
    this.appendSnapshotPart(parts, this.source.enabled ? '1' : '0');
    this.appendSnapshotPart(parts, this.source.enabledExplore ? '1' : '0');
    this.appendSnapshotPart(parts, String(this.source.weight));

    this.appendSnapshotPart(parts, this.source.searchRule.bookList);
    this.appendSnapshotPart(parts, this.source.searchRule.name);
    this.appendSnapshotPart(parts, this.source.searchRule.author);
    this.appendSnapshotPart(parts, this.source.searchRule.coverUrl);
    this.appendSnapshotPart(parts, this.source.searchRule.intro);
    this.appendSnapshotPart(parts, this.source.searchRule.kind);
    this.appendSnapshotPart(parts, this.source.searchRule.status || '');
    this.appendSnapshotPart(parts, this.source.searchRule.lastChapter);
    this.appendSnapshotPart(parts, this.source.searchRule.bookUrl);
    this.appendSnapshotPart(parts, this.source.searchRule.wordCount);

    this.appendSnapshotPart(parts, this.source.exploreRule.bookList);
    this.appendSnapshotPart(parts, this.source.exploreRule.name);
    this.appendSnapshotPart(parts, this.source.exploreRule.author);
    this.appendSnapshotPart(parts, this.source.exploreRule.coverUrl);
    this.appendSnapshotPart(parts, this.source.exploreRule.intro);
    this.appendSnapshotPart(parts, this.source.exploreRule.kind);
    this.appendSnapshotPart(parts, this.source.exploreRule.status || '');
    this.appendSnapshotPart(parts, this.source.exploreRule.lastChapter);
    this.appendSnapshotPart(parts, this.source.exploreRule.bookUrl);
    this.appendSnapshotPart(parts, this.source.exploreRule.wordCount);

    this.appendSnapshotPart(parts, this.source.bookInfoRule.init);
    this.appendSnapshotPart(parts, this.source.bookInfoRule.name);
    this.appendSnapshotPart(parts, this.source.bookInfoRule.author);
    this.appendSnapshotPart(parts, this.source.bookInfoRule.coverUrl);
    this.appendSnapshotPart(parts, this.source.bookInfoRule.intro);
    this.appendSnapshotPart(parts, this.source.bookInfoRule.kind);
    this.appendSnapshotPart(parts, this.source.bookInfoRule.lastChapter);
    this.appendSnapshotPart(parts, this.source.bookInfoRule.wordCount);
    this.appendSnapshotPart(parts, this.source.bookInfoRule.updateTime);
    this.appendSnapshotPart(parts, this.source.bookInfoRule.tocUrl);

    this.appendSnapshotPart(parts, this.source.tocRule.chapterList);
    this.appendSnapshotPart(parts, this.source.tocRule.chapterName);
    this.appendSnapshotPart(parts, this.source.tocRule.chapterUrl);
    this.appendSnapshotPart(parts, this.source.tocRule.nextTocUrl);
    this.appendSnapshotPart(parts, this.source.tocRule.isVip);
    this.appendSnapshotPart(parts, this.source.tocRule.isPay);
    this.appendSnapshotPart(parts, this.source.tocRule.updateTime);

    this.appendSnapshotPart(parts, this.source.contentRule.content);
    this.appendSnapshotPart(parts, this.source.contentRule.title);
    this.appendSnapshotPart(parts, this.source.contentRule.images);
    this.appendSnapshotPart(parts, this.source.contentRule.nextContentUrl);
    this.appendSnapshotPart(parts, this.source.contentRule.replaceRegex);
    this.appendSnapshotPart(parts, this.source.contentRule.imageDecode);
    this.appendSnapshotPart(parts, this.source.contentRule.imageStyle);
    // Cover imported fields that are not exposed by the editor as well. This
    // makes a draft's base snapshot change whenever the database definition was
    // replaced, instead of only when a visible input happened to change.
    this.appendSnapshotPart(parts, JSON.stringify(this.source));
    return parts.join('');
  }

  appendSnapshotPart(parts: string[], value: string): void {
    const text = value || '';
    parts.push(`${text.length}:${text};`);
  }


  onSystemDialogFlagChanged(): void {
    if (!this.showUnsavedDialog) this.unsavedDialogSession.close(this.getUIContext());
    if (!this.showDraftConflictDialog) this.draftConflictDialogSession.close(this.getUIContext());
  }

  openUnsavedDialog(): void {
    this.showUnsavedDialog = true;
    this.unsavedDialogSession.open(this.getUIContext(), (): void => {
      this.unsavedChangesDialogContent();
    }, {
      autoCancel: true,
      maskColor: this.appDarkMode ? '#99000000' : '#33000000',
      warnTag: '显示未保存确认弹窗失败:'
    });
  }

  openDraftConflictDialog(): void {
    this.showDraftConflictDialog = true;
    // 两个按钮都是明确的决定，蒙层不可关闭。
    this.draftConflictDialogSession.open(this.getUIContext(), (): void => {
      this.draftConflictDialogContent();
    }, {
      autoCancel: false,
      maskColor: this.appDarkMode ? '#99000000' : '#33000000',
      warnTag: '显示草稿冲突弹窗失败:'
    });
  }

  @Builder
  unsavedChangesDialogContent() {
    Column() {
      Text('保存书源修改？')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ bottom: 10 })

      Text('当前书源有未保存的编辑，返回前请选择是否保存。')
        .fontSize(14)
        .fontColor(this.secondaryTextColor())
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ bottom: 18 })

      Button('保存并返回')
        .width('100%')
        .height(44)
        .backgroundColor(this.buttonColor())
        .fontColor('#FFFFFF')
        .margin({ bottom: 10 })
        .onClick(() => {
          this.saveSourceAndBackFromDialog();
        })

      Button('放弃修改')
        .width('100%')
        .height(44)
        .backgroundColor(this.inputColor())
        .fontColor(this.primaryTextColor())
        .margin({ bottom: 10 })
        .onClick(() => {
          this.showUnsavedDialog = false;
          this.clearDraft();
          router.back();
        })

      Button('取消')
        .width('100%')
        .height(44)
        .backgroundColor(this.inputColor())
        .fontColor(this.primaryTextColor())
        .onClick(() => {
          this.showUnsavedDialog = false;
        })
    }    .padding(22)
  }


  @Builder
  draftConflictDialogContent() {
    Column() {
      Text('书源已经更新')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ bottom: 10 })

      Text('检测到这个书源有一份基于旧版本的未保存草稿。使用新版可保留刚导入的内容；恢复草稿后再次保存会覆盖新版。')
        .fontSize(14)
        .fontColor(this.secondaryTextColor())
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ bottom: 18 })

      Button('使用导入的新版')
        .width('100%')
        .height(44)
        .backgroundColor(this.buttonColor())
        .fontColor('#FFFFFF')
        .margin({ bottom: 10 })
        .onClick(() => {
          this.useImportedSourceInsteadOfDraft();
        })

      Button('恢复未保存草稿')
        .width('100%')
        .height(44)
        .backgroundColor(this.inputColor())
        .fontColor(this.primaryTextColor())
        .onClick(() => {
          this.restoreConflictingDraft();
        })
    }    .padding(22)
  }


  @Builder
  basicTabBuilder() {
    Column({ space: 12 }) {
      Text(`${this.sourceLoadedVersion}`)
        .fontSize(0.1)
        .height(0)
        .opacity(0)

      this.inputItemBuilder('书源名称', this.source.bookSourceName, (value: string) => {
        this.source.bookSourceName = value;
      })

      this.inputItemBuilder('书源地址', this.source.bookSourceUrl, (value: string) => {
        this.source.bookSourceUrl = value;
      })

      this.inputItemBuilder('书源类型', String(this.source.bookSourceType), (value: string) => {
        const parsed = Number(value);
        this.source.bookSourceType = Number.isFinite(parsed) ? parsed : 0;
      })

      this.inputItemBuilder('书源分组', this.source.bookSourceGroup, (value: string) => {
        this.source.bookSourceGroup = value;
      })

      this.inputItemBuilder('书源备注', this.source.bookSourceComment, (value: string) => {
        this.source.bookSourceComment = value;
      })

      this.inputItemBuilder('登录地址', this.source.loginUrl, (value: string) => {
        this.source.loginUrl = value;
      })

      this.inputItemBuilder('登录界面', this.source.loginUi, (value: string) => {
        this.source.loginUi = value;
      })

      this.inputItemBuilder('登录检测JS', this.source.loginCheckJs, (value: string) => {
        this.source.loginCheckJs = value;
      })

      this.inputItemBuilder('登录密钥', this.source.loginHeader, (value: string) => {
        this.source.loginHeader = value;
      })

      this.inputItemBuilder('URL正则', this.source.bookUrlPattern, (value: string) => {
        this.source.bookUrlPattern = value;
      })

      this.inputItemBuilder('搜索地址', this.source.searchUrl, (value: string) => {
        this.source.searchUrl = value;
      })

      this.inputItemBuilder('发现地址', this.source.exploreUrl, (value: string) => {
        this.source.exploreUrl = value;
      })

      this.inputItemBuilder('JS库', this.source.jsLib, (value: string) => {
        this.source.jsLib = value;
      })

      this.inputItemBuilder('请求头', this.source.header, (value: string) => {
        this.source.header = value;
      })

      this.inputItemBuilder('书源变量', this.source.variable, (value: string) => {
        this.source.variable = value;
      })

      Row() {
        Text('启用 Cookie')
          .fontSize(16)
          .fontColor(this.primaryTextColor())
          .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.source.enabledCookieJar })
          .selectedColor(this.buttonColor())
          .onChange((isOn: boolean) => {
            this.source.enabledCookieJar = isOn;
            this.scheduleDraftSave();
          })
      }
      .width('100%')
      .padding({ top: 12, bottom: 12 })

      Row() {
        Text('启用书源')
          .fontSize(16)
          .fontColor(this.primaryTextColor())
          .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.source.enabled })
          .selectedColor(this.buttonColor())
          .onChange((isOn: boolean) => {
            this.source.enabled = isOn;
            this.scheduleDraftSave();
          })
      }
      .width('100%')
      .padding({ top: 12, bottom: 12 })

      Row() {
        Text('启用发现')
          .fontSize(16)
          .fontColor(this.primaryTextColor())
          .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.source.enabledExplore })
          .selectedColor(this.buttonColor())
          .onChange((isOn: boolean) => {
            this.source.enabledExplore = isOn;
            this.scheduleDraftSave();
          })
      }
      .width('100%')
      .padding({ top: 12, bottom: 12 })

      this.inputItemBuilder('权重', String(this.source.weight), (value: string) => {
        this.source.weight = parseInt(value) || 0;
      })
    }
  }

  @Builder
  searchTabBuilder() {
    Column({ space: 12 }) {
      Text('搜索规则')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .width('100%')

      this.inputItemBuilder('书籍列表', this.source.searchRule.bookList, (value: string) => {
        this.source.searchRule.bookList = value;
      })

      this.inputItemBuilder('书名', this.source.searchRule.name, (value: string) => {
        this.source.searchRule.name = value;
      })

      this.inputItemBuilder('作者', this.source.searchRule.author, (value: string) => {
        this.source.searchRule.author = value;
      })

      this.inputItemBuilder('封面', this.source.searchRule.coverUrl, (value: string) => {
        this.source.searchRule.coverUrl = value;
      })

      this.inputItemBuilder('简介', this.source.searchRule.intro, (value: string) => {
        this.source.searchRule.intro = value;
      })

      this.inputItemBuilder('分类', this.source.searchRule.kind, (value: string) => {
        this.source.searchRule.kind = value;
      })

      this.inputItemBuilder('状态', this.source.searchRule.status || '', (value: string) => {
        this.source.searchRule.status = value;
      })

      this.inputItemBuilder('更新时间', this.source.searchRule.updateTime || '', (value: string) => {
        this.source.searchRule.updateTime = value;
      })

      this.inputItemBuilder('最新章节', this.source.searchRule.lastChapter, (value: string) => {
        this.source.searchRule.lastChapter = value;
      })

      this.inputItemBuilder('详情页', this.source.searchRule.bookUrl, (value: string) => {
        this.source.searchRule.bookUrl = value;
      })

      this.inputItemBuilder('字数', this.source.searchRule.wordCount, (value: string) => {
        this.source.searchRule.wordCount = value;
      })
    }
  }

  @Builder
  exploreTabBuilder() {
    Column({ space: 12 }) {
      Text('发现规则')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .width('100%')

      this.inputItemBuilder('书籍列表', this.source.exploreRule.bookList, (value: string) => {
        this.source.exploreRule.bookList = value;
      })

      this.inputItemBuilder('书名', this.source.exploreRule.name, (value: string) => {
        this.source.exploreRule.name = value;
      })

      this.inputItemBuilder('作者', this.source.exploreRule.author, (value: string) => {
        this.source.exploreRule.author = value;
      })

      this.inputItemBuilder('封面', this.source.exploreRule.coverUrl, (value: string) => {
        this.source.exploreRule.coverUrl = value;
      })

      this.inputItemBuilder('简介', this.source.exploreRule.intro, (value: string) => {
        this.source.exploreRule.intro = value;
      })

      this.inputItemBuilder('分类', this.source.exploreRule.kind, (value: string) => {
        this.source.exploreRule.kind = value;
      })

      this.inputItemBuilder('状态', this.source.exploreRule.status || '', (value: string) => {
        this.source.exploreRule.status = value;
      })

      this.inputItemBuilder('更新时间', this.source.exploreRule.updateTime || '', (value: string) => {
        this.source.exploreRule.updateTime = value;
      })

      this.inputItemBuilder('最新章节', this.source.exploreRule.lastChapter, (value: string) => {
        this.source.exploreRule.lastChapter = value;
      })

      this.inputItemBuilder('详情页', this.source.exploreRule.bookUrl, (value: string) => {
        this.source.exploreRule.bookUrl = value;
      })

      this.inputItemBuilder('字数', this.source.exploreRule.wordCount, (value: string) => {
        this.source.exploreRule.wordCount = value;
      })
    }
  }

  @Builder
  infoTabBuilder() {
    Column({ space: 12 }) {
      Text('详情规则')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .width('100%')

      this.inputItemBuilder('初始化', this.source.bookInfoRule.init, (value: string) => {
        this.source.bookInfoRule.init = value;
      })

      this.inputItemBuilder('书名', this.source.bookInfoRule.name, (value: string) => {
        this.source.bookInfoRule.name = value;
      })

      this.inputItemBuilder('作者', this.source.bookInfoRule.author, (value: string) => {
        this.source.bookInfoRule.author = value;
      })

      this.inputItemBuilder('封面', this.source.bookInfoRule.coverUrl, (value: string) => {
        this.source.bookInfoRule.coverUrl = value;
      })

      this.inputItemBuilder('简介', this.source.bookInfoRule.intro, (value: string) => {
        this.source.bookInfoRule.intro = value;
      })

      this.inputItemBuilder('分类', this.source.bookInfoRule.kind, (value: string) => {
        this.source.bookInfoRule.kind = value;
      })

      this.inputItemBuilder('状态', this.source.bookInfoRule.status || '', (value: string) => {
        this.source.bookInfoRule.status = value;
      })

      this.inputItemBuilder('最新章节', this.source.bookInfoRule.lastChapter, (value: string) => {
        this.source.bookInfoRule.lastChapter = value;
      })

      this.inputItemBuilder('字数', this.source.bookInfoRule.wordCount, (value: string) => {
        this.source.bookInfoRule.wordCount = value;
      })

      this.inputItemBuilder('更新时间', this.source.bookInfoRule.updateTime, (value: string) => {
        this.source.bookInfoRule.updateTime = value;
      })

      this.inputItemBuilder('目录地址', this.source.bookInfoRule.tocUrl, (value: string) => {
        this.source.bookInfoRule.tocUrl = value;
      })
    }
  }

  @Builder
  tocTabBuilder() {
    Column({ space: 12 }) {
      Text('目录规则')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .width('100%')

      this.inputItemBuilder('章节列表', this.source.tocRule.chapterList, (value: string) => {
        this.source.tocRule.chapterList = value;
      })

      this.inputItemBuilder('章节名称', this.source.tocRule.chapterName, (value: string) => {
        this.source.tocRule.chapterName = value;
      })

      this.inputItemBuilder('章节地址', this.source.tocRule.chapterUrl, (value: string) => {
        this.source.tocRule.chapterUrl = value;
      })

      this.inputItemBuilder('目录下一页', this.source.tocRule.nextTocUrl, (value: string) => {
        this.source.tocRule.nextTocUrl = value;
      })

      this.inputItemBuilder('VIP标记', this.source.tocRule.isVip, (value: string) => {
        this.source.tocRule.isVip = value;
      })

      this.inputItemBuilder('付费标记', this.source.tocRule.isPay, (value: string) => {
        this.source.tocRule.isPay = value;
      })

      this.inputItemBuilder('更新时间', this.source.tocRule.updateTime, (value: string) => {
        this.source.tocRule.updateTime = value;
      })
    }
  }

  @Builder
  contentTabBuilder() {
    Column({ space: 12 }) {
      Text('正文规则')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .width('100%')

      this.inputItemBuilder('正文内容', this.source.contentRule.content, (value: string) => {
        this.source.contentRule.content = value;
      })

      this.inputItemBuilder('章节标题', this.source.contentRule.title, (value: string) => {
        this.source.contentRule.title = value;
      })

      this.inputItemBuilder('图片', this.source.contentRule.images, (value: string) => {
        this.source.contentRule.images = value;
      })

      this.inputItemBuilder('正文下一页', this.source.contentRule.nextContentUrl, (value: string) => {
        this.source.contentRule.nextContentUrl = value;
      })

      this.inputItemBuilder('替换净化', this.source.contentRule.replaceRegex, (value: string) => {
        this.source.contentRule.replaceRegex = value;
      })

      this.inputItemBuilder('图片解密', this.source.contentRule.imageDecode, (value: string) => {
        this.source.contentRule.imageDecode = value;
      })

      this.inputItemBuilder('图片样式', this.source.contentRule.imageStyle, (value: string) => {
        this.source.contentRule.imageStyle = value;
      })
    }
  }

  @Builder
  inputItemBuilder(label: string, value: string, onChange: (value: string) => void) {
    Column() {
      Text(label)
        .fontSize(14)
        .fontColor(this.secondaryTextColor())
        .width('100%')
        .margin({ bottom: 4 })

      TextInput({ text: value, placeholder: `请输入${label}` })
        .width('100%')
        .height(44)
        .borderRadius(8)
        .backgroundColor(this.cardColor())
        .fontColor(this.primaryTextColor())
        .placeholderColor(this.placeholderTextColor())
        .padding({ left: 12, right: 12 })
        .onChange((val: string) => {
          onChange(val);
          this.scheduleDraftSave();
        })
    }
    .width('100%')
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

  secondaryTextColor(): string {
    return ThemeRuntime.subTextColor(this.appDarkMode);
  }

  dividerColor(): string {
    return ThemeRuntime.dividerColor(this.appDarkMode);
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

  syncBars(): void {
    syncSystemBars(getContext(this), this.appDarkMode, this.pageColor());
  }

  /**
   * The default OFFSET mode pans the whole page when a lower form field gets focus,
   * which can move the title and tab bars off-screen. RESIZE keeps those bars fixed
   * and gives the Scroll content the reduced viewport above the keyboard.
   */
  private configureKeyboardAvoidanceMode(): void {
    try {
      const uiContext = this.getUIContext();
      if (!this.keyboardAvoidModeConfigured) {
        this.previousKeyboardAvoidMode = uiContext.getKeyboardAvoidMode();
        this.keyboardAvoidModeConfigured = true;
      }
      uiContext.setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
    } catch (error) {
      console.warn('设置书源编辑页键盘避让模式失败:', error);
    }
  }

  private restoreKeyboardAvoidanceMode(): void {
    if (!this.keyboardAvoidModeConfigured) return;
    try {
      this.getUIContext().setKeyboardAvoidMode(this.previousKeyboardAvoidMode);
    } catch (error) {
      console.warn('恢复键盘避让模式失败:', error);
    }
    this.keyboardAvoidModeConfigured = false;
  }

  private registerKeyboardAvoidance(): void {
    window.getLastWindow(getContext(this)).then((mainWindow: window.Window): void => {
      if (this.keyboardWindow === mainWindow) {
        this.refreshKeyboardInset(mainWindow);
        return;
      }
      if (this.keyboardWindow) {
        try {
          this.keyboardWindow.off('avoidAreaChange', this.keyboardAvoidAreaCallback);
        } catch (_) {
        }
      }
      this.keyboardWindow = mainWindow;
      mainWindow.on('avoidAreaChange', this.keyboardAvoidAreaCallback);
      this.refreshKeyboardInset(mainWindow);
    }).catch((error: Error): void => {
      console.warn('注册键盘避让监听失败:', error.message);
    });
  }

  private unregisterKeyboardAvoidance(): void {
    if (this.keyboardWindow) {
      try {
        this.keyboardWindow.off('avoidAreaChange', this.keyboardAvoidAreaCallback);
      } catch (_) {
      }
    }
    this.keyboardWindow = null;
    this.keyboardInset = 0;
  }

  private refreshKeyboardInset(mainWindow: window.Window): void {
    try {
      const area = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_KEYBOARD);
      this.keyboardInset = this.keyboardAvoidAreaHeight(area);
    } catch (_) {
      this.keyboardInset = 0;
    }
  }

  private keyboardAvoidAreaHeight(area: window.AvoidArea): number {
    return px2vp(Math.max(0, area.bottomRect.height));
  }
}
