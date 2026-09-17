export class ReaderTtsFloatingSession {
  private static ownerId: string = '';
  private static toggleAction: (() => Promise<void>) | null = null;
  private static pausedState: (() => boolean) | null = null;
  private static stopAction: (() => Promise<void> | void) | null = null;
  private static previousAction: (() => void) | null = null;
  private static nextAction: (() => void) | null = null;
  private static positionAction: ((chapterIndex: number, pageIndex: number,
    sourceOffset: number) => Promise<void> | void) | null = null;
  private static speedAction: ((value: number) => void) | null = null;
  private static timerAction: ((minutes: number) => void) | null = null;
  private static voiceAction: (() => void) | null = null;
  private static audioSeekAction: ((positionMs: number) => void) | null = null;
  // Chapter catalog for the floating panel. Both reader modes publish one: the
  // audio mode from the book source, the TTS mode from the loaded chapters.
  private static catalogTitleLabels: string[] = [];
  private static catalogCachedFlags: boolean[] = [];
  private static catalogCurrentIndex: number = 0;
  private static catalogSelectAction: ((index: number) => void) | null = null;
  private static ttsVoiceLabels: string[] = [];
  private static ttsVoiceSelectedIndex: number = 0;
  private static ttsVoiceSelectAction: ((index: number) => void) | null = null;

  static attach(ownerId: string, bookUrl: string, bookName: string, chapterTitle: string,
    paused: boolean, toggleAction: () => Promise<void>, pausedState: () => boolean,
    stopAction: () => Promise<void> | void): void {
    ReaderTtsFloatingSession.ownerId = ownerId;
    ReaderTtsFloatingSession.toggleAction = toggleAction;
    ReaderTtsFloatingSession.pausedState = pausedState;
    ReaderTtsFloatingSession.stopAction = stopAction;
    AppStorage.setOrCreate('globalTtsActive', true);
    AppStorage.setOrCreate('globalTtsPaused', paused);
    AppStorage.setOrCreate('globalTtsBookUrl', bookUrl);
    AppStorage.setOrCreate('globalTtsBookName', bookName || '正在朗读');
    AppStorage.setOrCreate('globalTtsChapterTitle', chapterTitle || '');
    AppStorage.setOrCreate('globalTtsMode', 'tts');
    AppStorage.setOrCreate('globalTtsVoiceCode', '');
    ReaderTtsFloatingSession.notifyChanged();
  }

  static update(ownerId: string, bookName: string, chapterTitle: string, paused: boolean): void {
    if (!ReaderTtsFloatingSession.isOwner(ownerId)) {
      return;
    }
    const nextName = bookName || '正在朗读';
    const nextTitle = chapterTitle || '';
    const changed = AppStorage.get<boolean>('globalTtsPaused') !== paused ||
      AppStorage.get<string>('globalTtsBookName') !== nextName ||
      AppStorage.get<string>('globalTtsChapterTitle') !== nextTitle;
    if (!changed) return;
    AppStorage.setOrCreate('globalTtsActive', true);
    AppStorage.setOrCreate('globalTtsPaused', paused);
    AppStorage.setOrCreate('globalTtsBookName', nextName);
    AppStorage.setOrCreate('globalTtsChapterTitle', nextTitle);
    ReaderTtsFloatingSession.notifyChanged();
  }

  static configureControls(ownerId: string, previousAction: () => void, nextAction: () => void,
    speedAction: (value: number) => void, timerAction: (minutes: number) => void): void {
    if (!ReaderTtsFloatingSession.isOwner(ownerId)) {
      return;
    }
    ReaderTtsFloatingSession.previousAction = previousAction;
    ReaderTtsFloatingSession.nextAction = nextAction;
    ReaderTtsFloatingSession.speedAction = speedAction;
    ReaderTtsFloatingSession.timerAction = timerAction;
  }

  static configurePositionControl(ownerId: string,
    positionAction: (chapterIndex: number, pageIndex: number, sourceOffset: number) => Promise<void> | void): void {
    if (!ReaderTtsFloatingSession.isOwner(ownerId)) {
      return;
    }
    ReaderTtsFloatingSession.positionAction = positionAction;
  }

  static configureTtsVoices(ownerId: string, labels: string[], selectedIndex: number,
    selectAction: (index: number) => void): void {
    if (!ReaderTtsFloatingSession.isOwner(ownerId)) return;
    const nextLabels = labels.slice();
    const nextIndex = Math.max(0, Math.min(Math.round(selectedIndex || 0), Math.max(0, nextLabels.length - 1)));
    const labelsChanged = nextLabels.length !== ReaderTtsFloatingSession.ttsVoiceLabels.length ||
      nextLabels.some((label: string, index: number) =>
        label !== ReaderTtsFloatingSession.ttsVoiceLabels[index]);
    const indexChanged = nextIndex !== ReaderTtsFloatingSession.ttsVoiceSelectedIndex;
    ReaderTtsFloatingSession.ttsVoiceLabels = nextLabels;
    ReaderTtsFloatingSession.ttsVoiceSelectedIndex = nextIndex;
    ReaderTtsFloatingSession.ttsVoiceSelectAction = selectAction;
    const voiceLabel = nextLabels[nextIndex] || '';
    const labelChanged = AppStorage.get<string>('globalTtsVoiceCode') !== voiceLabel;
    if (labelChanged) AppStorage.setOrCreate('globalTtsVoiceCode', voiceLabel);
    if (labelsChanged || indexChanged || labelChanged) ReaderTtsFloatingSession.notifyVoiceChanged();
  }

  static ttsVoiceTitles(): string[] {
    return ReaderTtsFloatingSession.ttsVoiceLabels.slice();
  }

  static ttsVoiceIndex(): number {
    return ReaderTtsFloatingSession.ttsVoiceSelectedIndex;
  }

  static selectTtsVoice(index: number): void {
    const target = Math.max(0, Math.min(Math.round(index || 0),
      Math.max(0, ReaderTtsFloatingSession.ttsVoiceLabels.length - 1)));
    ReaderTtsFloatingSession.ttsVoiceSelectedIndex = target;
    AppStorage.setOrCreate('globalTtsVoiceCode', ReaderTtsFloatingSession.ttsVoiceLabels[target] || '');
    const action = ReaderTtsFloatingSession.ttsVoiceSelectAction;
    if (action) action(target);
    ReaderTtsFloatingSession.notifyVoiceChanged();
  }

  static configureAudioControls(ownerId: string, voiceCode: string,
    voiceAction: () => void, seekAction: (positionMs: number) => void): void {
    if (!ReaderTtsFloatingSession.isOwner(ownerId)) return;
    ReaderTtsFloatingSession.voiceAction = voiceAction;
    ReaderTtsFloatingSession.audioSeekAction = seekAction;
    AppStorage.setOrCreate('globalTtsMode', 'audio');
    AppStorage.setOrCreate('globalTtsVoiceCode', voiceCode || '默认');
  }

  static updateAudioProgress(ownerId: string, positionMs: number, durationMs: number): void {
    if (!ReaderTtsFloatingSession.isOwner(ownerId)) return;
    const nextDuration = Math.max(0, durationMs || 0);
    const nextPosition = Math.max(0, Math.min(positionMs || 0, nextDuration || positionMs || 0));
    if (AppStorage.get<number>('globalTtsAudioPositionMs') !== nextPosition) {
      AppStorage.setOrCreate('globalTtsAudioPositionMs', nextPosition);
    }
    if (AppStorage.get<number>('globalTtsAudioDurationMs') !== nextDuration) {
      AppStorage.setOrCreate('globalTtsAudioDurationMs', nextDuration);
    }
  }

  static seekAudio(positionMs: number): void {
    const action = ReaderTtsFloatingSession.audioSeekAction;
    if (action) action(Math.max(0, positionMs || 0));
  }

  static openVoice(): void {
    const action = ReaderTtsFloatingSession.voiceAction;
    if (action) action();
  }

  static configureCatalog(ownerId: string, titles: string[], currentIndex: number,
    selectAction: (index: number) => void, cachedFlags: boolean[] = []): void {
    if (!ReaderTtsFloatingSession.isOwner(ownerId)) return;
    ReaderTtsFloatingSession.catalogTitleLabels = titles.slice();
    // Published alongside the titles so a catalog opened from another page (the
    // shelf) can render the cache chip without resolving the book itself.
    ReaderTtsFloatingSession.catalogCachedFlags = cachedFlags.slice();
    ReaderTtsFloatingSession.catalogCurrentIndex = currentIndex;
    ReaderTtsFloatingSession.catalogSelectAction = selectAction;
    ReaderTtsFloatingSession.updateCatalogChapterAvailability(currentIndex);
  }

  static updateCatalogIndex(ownerId: string, currentIndex: number): void {
    if (!ReaderTtsFloatingSession.isOwner(ownerId)) return;
    if (ReaderTtsFloatingSession.catalogCurrentIndex === currentIndex) return;
    ReaderTtsFloatingSession.catalogCurrentIndex = currentIndex;
    ReaderTtsFloatingSession.updateCatalogChapterAvailability(currentIndex);
  }

  static catalogTitles(): string[] {
    return ReaderTtsFloatingSession.catalogTitleLabels.slice();
  }

  /**
   * Cache flag for one chapter, in the canonical chapter order published by
   * `configureCatalog` (i.e. pass a canonical index, not a display one).
   */
  static catalogCachedFlag(canonicalIndex: number): boolean {
    return ReaderTtsFloatingSession.catalogCachedFlags[canonicalIndex] === true;
  }

  /** Owner of the session currently holding the catalog, for re-publishers. */
  static currentOwnerId(): string {
    return ReaderTtsFloatingSession.ownerId;
  }

  /**
   * Refreshes the cache snapshot of an already-published catalog. Every entry point
   * calls this right before it opens the catalog, so a chapter cached mid-session
   * shows up immediately instead of waiting for the next `configureCatalog`.
   * `ownerId` guards against a page that no longer owns the session clobbering it.
   */
  static updateCatalogCachedFlags(ownerId: string, cachedFlags: boolean[]): void {
    if (!ReaderTtsFloatingSession.isOwner(ownerId)) return;
    ReaderTtsFloatingSession.catalogCachedFlags = cachedFlags.slice();
  }

  /**
   * Count-only accessor. Index math and row decoration run per visible row, and
   * `catalogTitles()` would copy the whole label array every call.
   */
  static catalogCount(): number {
    return ReaderTtsFloatingSession.catalogTitleLabels.length;
  }

  static catalogIndex(): number {
    return ReaderTtsFloatingSession.catalogCurrentIndex;
  }

  static selectCatalogIndex(index: number): void {
    const action = ReaderTtsFloatingSession.catalogSelectAction;
    if (action) action(index);
  }

  static updateDetails(ownerId: string, content: string, textBefore: string, currentText: string,
    textAfter: string, cover: ResourceStr, coverFrame: ResourceStr,
    chapterProgress: string, speed: number, timerMinutes: number, timerRemainingSeconds: number,
    canPrevious: boolean, canNext: boolean, progress: number = 0): void {
    if (!ReaderTtsFloatingSession.isOwner(ownerId)) {
      return;
    }
    if (AppStorage.get<ResourceStr>('globalTtsCover') !== cover) {
      AppStorage.setOrCreate<ResourceStr>('globalTtsCover', cover);
    }
    if (AppStorage.get<ResourceStr>('globalTtsCoverFrame') !== coverFrame) {
      AppStorage.setOrCreate<ResourceStr>('globalTtsCoverFrame', coverFrame);
    }
    if (AppStorage.get<string>('globalTtsContent') !== content) {
      AppStorage.setOrCreate('globalTtsContent', content);
    }
    if (AppStorage.get<string>('globalTtsTextBefore') !== textBefore) {
      AppStorage.setOrCreate('globalTtsTextBefore', textBefore);
    }
    if (AppStorage.get<string>('globalTtsCurrentText') !== currentText) {
      AppStorage.setOrCreate('globalTtsCurrentText', currentText);
    }
    if (AppStorage.get<string>('globalTtsTextAfter') !== textAfter) {
      AppStorage.setOrCreate('globalTtsTextAfter', textAfter);
    }
    if (AppStorage.get<string>('globalTtsChapterProgress') !== chapterProgress) {
      AppStorage.setOrCreate('globalTtsChapterProgress', chapterProgress);
    }
    const normalizedProgress = Math.max(0, Math.min(100, progress || 0));
    if (AppStorage.get<number>('globalTtsProgress') !== normalizedProgress) {
      AppStorage.setOrCreate('globalTtsProgress', normalizedProgress);
    }
    if (AppStorage.get<number>('globalTtsSpeed') !== speed) {
      AppStorage.setOrCreate('globalTtsSpeed', speed);
    }
    if (AppStorage.get<number>('globalTtsTimerMinutes') !== timerMinutes) {
      AppStorage.setOrCreate('globalTtsTimerMinutes', timerMinutes);
    }
    if (AppStorage.get<number>('globalTtsTimerRemainingSeconds') !== timerRemainingSeconds) {
      AppStorage.setOrCreate('globalTtsTimerRemainingSeconds', timerRemainingSeconds);
    }
    if (AppStorage.get<boolean>('globalTtsCanPrevious') !== canPrevious) {
      AppStorage.setOrCreate('globalTtsCanPrevious', canPrevious);
    }
    if (AppStorage.get<boolean>('globalTtsCanNext') !== canNext) {
      AppStorage.setOrCreate('globalTtsCanNext', canNext);
    }
    // These fields are StorageLink-backed and update their consumers directly. Bumping the
    // global revision for every audio position tick rebuilt the capsule once per second.
  }

  static updateTimer(ownerId: string, timerMinutes: number, timerRemainingSeconds: number): void {
    if (!ReaderTtsFloatingSession.isOwner(ownerId)) {
      return;
    }
    if (AppStorage.get<number>('globalTtsTimerMinutes') !== timerMinutes) {
      AppStorage.setOrCreate('globalTtsTimerMinutes', timerMinutes);
    }
    if (AppStorage.get<number>('globalTtsTimerRemainingSeconds') !== timerRemainingSeconds) {
      AppStorage.setOrCreate('globalTtsTimerRemainingSeconds', timerRemainingSeconds);
    }
  }

  static updatePosition(ownerId: string, chapterIndex: number, offsetStart: number, offsetEnd: number): void {
    if (!ReaderTtsFloatingSession.isOwner(ownerId)) {
      return;
    }
    const changed = AppStorage.get<number>('globalTtsChapterIndex') !== chapterIndex ||
      AppStorage.get<number>('globalTtsOffsetStart') !== offsetStart ||
      AppStorage.get<number>('globalTtsOffsetEnd') !== offsetEnd;
    if (!changed) return;
    AppStorage.setOrCreate('globalTtsChapterIndex', chapterIndex);
    AppStorage.setOrCreate('globalTtsOffsetStart', offsetStart);
    AppStorage.setOrCreate('globalTtsOffsetEnd', offsetEnd);
    // A reopened reader is a separate mirror while the retained original page still owns TTS.
    // Publish every changed range; page lifecycle overlap cannot be used to decide whether a mirror exists.
    ReaderTtsFloatingSession.notifyChanged();
  }

  static isOwner(ownerId: string): boolean {
    return !!ownerId && ReaderTtsFloatingSession.ownerId === ownerId &&
      (AppStorage.get<boolean>('globalTtsActive') || false);
  }

  static isActive(): boolean {
    return !!ReaderTtsFloatingSession.ownerId &&
      (AppStorage.get<boolean>('globalTtsActive') || false);
  }

  static async toggle(): Promise<void> {
    const action = ReaderTtsFloatingSession.toggleAction;
    if (action) {
      await action();
      const pausedState = ReaderTtsFloatingSession.pausedState;
      if (pausedState && ReaderTtsFloatingSession.isActive()) {
        AppStorage.setOrCreate('globalTtsPaused', pausedState());
        ReaderTtsFloatingSession.notifyChanged();
      }
    }
  }

  static stop(): void {
    const action = ReaderTtsFloatingSession.stopAction;
    if (action) {
      Promise.resolve(action()).catch((error: Error) => {
        console.warn('停止后台播放失败:', error);
      });
      return;
    }
    ReaderTtsFloatingSession.clear();
  }

  static previous(): void {
    const action = ReaderTtsFloatingSession.previousAction;
    if (action) action();
  }

  static next(): void {
    const action = ReaderTtsFloatingSession.nextAction;
    if (action) action();
  }

  static async jumpToPosition(chapterIndex: number, pageIndex: number, sourceOffset: number = -1): Promise<void> {
    const action = ReaderTtsFloatingSession.positionAction;
    if (action) await Promise.resolve(action(chapterIndex, pageIndex, sourceOffset));
  }

  static setSpeed(value: number): void {
    const nextSpeed = Math.max(0.5, Math.min(2, Math.round((value || 1) * 10) / 10));
    // The bookshelf retains its own host page. Publish the shared panel state before dispatching
    // to the hidden reader owner so every mounted instance updates in the same UI turn.
    AppStorage.setOrCreate('globalTtsSpeed', nextSpeed);
    const action = ReaderTtsFloatingSession.speedAction;
    if (action) action(nextSpeed);
  }

  static setTimer(minutes: number): void {
    const nextMinutes = Math.max(0, Math.round(minutes || 0));
    AppStorage.setOrCreate('globalTtsTimerMinutes', nextMinutes);
    if (nextMinutes <= 0) AppStorage.setOrCreate('globalTtsTimerRemainingSeconds', 0);
    const action = ReaderTtsFloatingSession.timerAction;
    if (action) action(nextMinutes);
  }

  static async stopOther(ownerId: string): Promise<void> {
    if (!ReaderTtsFloatingSession.isActive() || ReaderTtsFloatingSession.isOwner(ownerId)) {
      return;
    }
    const action = ReaderTtsFloatingSession.stopAction;
    if (action) {
      await Promise.resolve(action());
    } else {
      ReaderTtsFloatingSession.clear();
    }
  }

  private static updateCatalogChapterAvailability(currentIndex: number): void {
    const count = ReaderTtsFloatingSession.catalogTitleLabels.length;
    const canPrevious = count > 0 && currentIndex > 0;
    const canNext = count > 0 && currentIndex < count - 1;
    if (AppStorage.get<boolean>('globalTtsCanPrevious') !== canPrevious) {
      AppStorage.setOrCreate('globalTtsCanPrevious', canPrevious);
    }
    if (AppStorage.get<boolean>('globalTtsCanNext') !== canNext) {
      AppStorage.setOrCreate('globalTtsCanNext', canNext);
    }
  }

  static clear(ownerId: string = ''): void {
    if (ownerId && ReaderTtsFloatingSession.ownerId !== ownerId) {
      return;
    }
    ReaderTtsFloatingSession.ownerId = '';
    ReaderTtsFloatingSession.toggleAction = null;
    ReaderTtsFloatingSession.pausedState = null;
    ReaderTtsFloatingSession.stopAction = null;
    ReaderTtsFloatingSession.previousAction = null;
    ReaderTtsFloatingSession.nextAction = null;
    ReaderTtsFloatingSession.positionAction = null;
    ReaderTtsFloatingSession.speedAction = null;
    ReaderTtsFloatingSession.timerAction = null;
    ReaderTtsFloatingSession.voiceAction = null;
    ReaderTtsFloatingSession.audioSeekAction = null;
    ReaderTtsFloatingSession.catalogTitleLabels = [];
    ReaderTtsFloatingSession.catalogCachedFlags = [];
    ReaderTtsFloatingSession.catalogCurrentIndex = 0;
    ReaderTtsFloatingSession.catalogSelectAction = null;
    ReaderTtsFloatingSession.ttsVoiceLabels = [];
    ReaderTtsFloatingSession.ttsVoiceSelectedIndex = 0;
    ReaderTtsFloatingSession.ttsVoiceSelectAction = null;
    AppStorage.setOrCreate('globalTtsActive', false);
    AppStorage.setOrCreate('globalTtsPaused', false);
    AppStorage.setOrCreate('globalTtsBookUrl', '');
    AppStorage.setOrCreate('globalTtsBookName', '');
    AppStorage.setOrCreate('globalTtsChapterTitle', '');
    AppStorage.setOrCreate('globalTtsMode', '');
    AppStorage.setOrCreate('globalTtsVoiceCode', '');
    AppStorage.setOrCreate('globalTtsAudioPositionMs', 0);
    AppStorage.setOrCreate('globalTtsAudioDurationMs', 0);
    AppStorage.setOrCreate<ResourceStr>('globalTtsCover', '');
    AppStorage.setOrCreate<ResourceStr>('globalTtsCoverFrame', '');
    AppStorage.setOrCreate('globalTtsContent', '');
    AppStorage.setOrCreate('globalTtsTextBefore', '');
    AppStorage.setOrCreate('globalTtsCurrentText', '');
    AppStorage.setOrCreate('globalTtsTextAfter', '');
    AppStorage.setOrCreate('globalTtsChapterProgress', '');
    AppStorage.setOrCreate('globalTtsProgress', 0);
    AppStorage.setOrCreate('globalTtsSpeed', 1);
    AppStorage.setOrCreate('globalTtsTimerMinutes', 0);
    AppStorage.setOrCreate('globalTtsTimerRemainingSeconds', 0);
    AppStorage.setOrCreate('globalTtsCanPrevious', false);
    AppStorage.setOrCreate('globalTtsCanNext', false);
    AppStorage.setOrCreate('globalTtsChapterIndex', -1);
    AppStorage.setOrCreate('globalTtsOffsetStart', -1);
    AppStorage.setOrCreate('globalTtsOffsetEnd', -1);
    AppStorage.setOrCreate('globalTtsVoiceRevision', 0);
    AppStorage.setOrCreate('globalTtsAudioCatalogReverseOrder', false);
    ReaderTtsFloatingSession.notifyChanged();
  }

  private static notifyChanged(): void {
    const revision = AppStorage.get<number>('globalTtsRevision') || 0;
    AppStorage.setOrCreate('globalTtsRevision', revision + 1);
  }

  private static notifyVoiceChanged(): void {
    const revision = AppStorage.get<number>('globalTtsVoiceRevision') || 0;
    AppStorage.setOrCreate('globalTtsVoiceRevision', revision + 1);
  }
}
