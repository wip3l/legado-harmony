import { BookCoverResolver } from '../../utils/BookCoverResolver';
import fileUri from '@ohos.file.fileuri';
import { common, WantAgent, wantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { avSession } from '@kit.AVSessionKit';
import { audio } from '@kit.AudioKit';
import image from '@ohos.multimedia.image';
import fs from '@ohos.file.fs';
import { BookCoverCache } from '../../utils/BookCoverCache';

/** 系统媒体卡片上展示的当前朗读信息。 */
export interface ReaderTtsMediaInfo {
  bookUrl: string;
  bookName: string;
  author: string;
  chapterIndex: number;
  chapterTitle: string;
  /** 章节标题加阅读进度。 */
  subtitle: string;
  pageIndex: number;
  elapsedTime: number;
  duration: number;
  canPlayPrevious: boolean;
  canPlayNext: boolean;
}

/** 阅读页为朗读的系统媒体会话提供的状态与命令入口。 */
export interface ReaderTtsMediaHost {
  abilityContext: () => common.UIAbilityContext;
  isSpeaking: () => boolean;
  isPaused: () => boolean;
  audioDebugState: () => string;
  mediaInfo: () => ReaderTtsMediaInfo;
  /** 媒体卡片封面的原始地址（书架当前展示的那张）。 */
  coverRaw: () => ResourceStr;
  onPlay: () => void;
  onPause: () => void;
  onStop: () => void;
  onPlayNext: () => void;
  onPlayPrevious: () => void;
  onSetSpeed: (speed: number) => void;
  /** 章节缓存任务正在运行。它与朗读共用后台长时任务许可，朗读停止时许可要交给它而不是释放。 */
  cacheTaskRunning: () => boolean;
  cacheHoldsBackground: () => boolean;
  handBackgroundToCache: () => void;
}

/**
 * 朗读的系统侧：后台长时任务（音频播放）、AVSession 媒体卡片与耳机/锁屏按键、卡片封面。
 * 朗读本身（合成、播放、焦点）不在这里；这里只保证息屏后不被挂起，并让系统控件与朗读状态一致。
 */
export class ReaderTtsMediaSession {
  backgroundRunning: boolean = false;
  backgroundRequesting: boolean = false;

  private readonly host: ReaderTtsMediaHost;
  private backgroundDesired: boolean = false;
  private heartbeatId: number = -1;
  private lastLogAt: number = 0;
  private session: avSession.AVSession | null = null;
  private sessionRequesting: boolean = false;
  private mediaImage: string = '';
  private mediaImageRaw: string = '';
  private mediaPixelMap: image.PixelMap | null = null;
  private mediaImageRefreshSerial: number = 0;
  private routingManager: audio.AudioRoutingManager | null = null;
  private outputOnExternalDevice: boolean = false;
  private readonly outputRendererInfo: audio.AudioRendererInfo = {
    usage: audio.StreamUsage.STREAM_USAGE_AUDIOBOOK,
    rendererFlags: 0
  };
  private readonly onPreferredOutputChange = (devices: audio.AudioDeviceDescriptors): void => {
    this.handleOutputDeviceChange(devices);
  };

  constructor(host: ReaderTtsMediaHost) {
    this.host = host;
  }

  static formatError(error: Object | null | undefined): string {
    if (!error) return 'unknown';
    const record = error as Record<string, Object>;
    const code = record['code'];
    const message = record['message'];
    const parts: string[] = [];
    if (code !== undefined) parts.push(`code=${String(code)}`);
    if (message !== undefined) parts.push(`message=${String(message)}`);
    return parts.length > 0 ? parts.join(',') : String(error);
  }

  hasSession(): boolean {
    return !!this.session;
  }

  debugState(): string {
    return `desired=${this.backgroundDesired},running=${this.backgroundRunning},` +
      `requesting=${this.backgroundRequesting},speaking=${this.host.isSpeaking()},` +
      `avSession=${this.session ? 'yes' : 'no'},audio=${this.host.audioDebugState()}`;
  }

  playbackState(): avSession.PlaybackState {
    return this.host.isPaused() ? avSession.PlaybackState.PLAYBACK_STATE_PAUSE :
      avSession.PlaybackState.PLAYBACK_STATE_PLAY;
  }

  // ---------------------------------------------------------------- 后台长时任务

  async startBackgroundRunning(): Promise<boolean> {
    this.backgroundDesired = true;
    if (this.backgroundRunning) {
      if (!this.session && !this.sessionRequesting) {
        const agent = await this.createWantAgent();
        await this.startSession(agent);
      }
      await this.updatePlaybackState(this.playbackState());
      this.startHeartbeat();
      return !!this.session;
    }
    if (this.backgroundRequesting) {
      return this.backgroundRunning;
    }
    this.backgroundRequesting = true;
    try {
      const agent = await this.createWantAgent();
      await this.startSession(agent);
      await backgroundTaskManager.startBackgroundRunning(this.host.abilityContext(), ['audioPlayback'], agent);
      if (this.backgroundDesired) {
        this.backgroundRunning = true;
        this.startHeartbeat();
        console.info(`[TTS-BG] background audio task started: ${this.debugState()}`);
      } else {
        await backgroundTaskManager.stopBackgroundRunning(this.host.abilityContext());
        await this.stopSession();
      }
      return this.backgroundRunning;
    } catch (error) {
      this.backgroundRunning = false;
      this.stopHeartbeat();
      console.warn(`[TTS-BG] start background audio task failed: ` +
        `${ReaderTtsMediaSession.formatError(error as Object)}; ${this.debugState()}`, error);
      return false;
    } finally {
      this.backgroundRequesting = false;
    }
  }

  async stopBackgroundRunning(): Promise<void> {
    this.backgroundDesired = false;
    this.stopHeartbeat();
    await this.stopSession();
    if (!this.backgroundRunning && !this.backgroundRequesting) return;
    if (this.backgroundRequesting && !this.backgroundRunning) return;
    this.backgroundRunning = false;
    // The cache task shares this ability's background permit: hand it over instead of releasing it.
    if (this.host.cacheTaskRunning()) {
      this.host.handBackgroundToCache();
      return;
    }
    if (this.host.cacheHoldsBackground()) return;
    try {
      await backgroundTaskManager.stopBackgroundRunning(this.host.abilityContext());
      console.info(`[TTS-BG] background audio task stopped: ${this.debugState()}`);
    } catch (error) {
      console.warn(`[TTS-BG] stop background audio task failed: ` +
        `${ReaderTtsMediaSession.formatError(error as Object)}; ${this.debugState()}`, error);
    }
  }

  onAudioStarted(): void {
    console.info(`[TTS-BG] audio started: ${this.debugState()}`);
    this.refreshAfterAudioStarted().catch((error: Error) => {
      console.warn(`[TTS-BG] refresh after audio started failed: ` +
        `${ReaderTtsMediaSession.formatError(error as Object)}; ${this.debugState()}`, error);
    });
  }

  private async refreshAfterAudioStarted(): Promise<void> {
    if (!this.backgroundRunning && !this.backgroundRequesting) {
      await this.startBackgroundRunning();
      return;
    }
    await this.syncSystemMediaControls();
  }

  private startHeartbeat(): void {
    if (this.heartbeatId >= 0) return;
    this.heartbeatId = setInterval(() => {
      this.keepAlive().catch((error: Error) => {
        console.warn(`[TTS-BG] heartbeat failed: ${ReaderTtsMediaSession.formatError(error as Object)}; ` +
          `${this.debugState()}`, error);
      });
    }, 30000);
  }

  private stopHeartbeat(): void {
    if (this.heartbeatId < 0) return;
    clearInterval(this.heartbeatId);
    this.heartbeatId = -1;
  }

  private async keepAlive(): Promise<void> {
    if (!this.backgroundDesired || !this.host.isSpeaking()) {
      this.stopHeartbeat();
      return;
    }
    if (!this.backgroundRunning && !this.backgroundRequesting) {
      await this.startBackgroundRunning();
      return;
    }
    await this.syncSystemMediaControls();
    const now = Date.now();
    if (now - this.lastLogAt >= 120000) {
      this.lastLogAt = now;
      console.info(`[TTS-BG] heartbeat: ${this.debugState()}`);
    }
  }

  private async createWantAgent(): Promise<WantAgent> {
    return await wantAgent.getWantAgent({
      wants: [{
        bundleName: this.host.abilityContext().abilityInfo.bundleName,
        abilityName: 'EntryAbility'
      }],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: 1001,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    });
  }

  // ---------------------------------------------------------------- AVSession

  private async startSession(agent: WantAgent): Promise<void> {
    if (this.sessionRequesting) return;
    this.sessionRequesting = true;
    try {
      if (!this.session) {
        this.session = await avSession.createAVSession(this.host.abilityContext(), 'LegadoReaderTts', 'audio');
        this.registerCommands(this.session);
        this.watchOutputDevice();
      }
      const info = this.host.mediaInfo();
      await this.session.setLaunchAbility(agent);
      await this.session.setAVQueueTitle(info.bookName || '听书');
      await this.refreshMediaImage();
      await this.session.setAVMetadata(this.metadata());
      await this.session.setExtras({
        bookUrl: info.bookUrl || '',
        chapterIndex: info.chapterIndex,
        chapterTitle: info.chapterTitle
      });
      await this.updatePlaybackState(this.playbackState());
      await this.session.activate();
      await this.syncSystemMediaControls();
      console.info(`[TTS-BG] AVSession activated: ${this.debugState()}`);
    } catch (error) {
      console.warn(`[TTS-BG] start AVSession failed: ${ReaderTtsMediaSession.formatError(error as Object)}; ` +
        `${this.debugState()}`, error);
    } finally {
      this.sessionRequesting = false;
    }
  }

  private registerCommands(session: avSession.AVSession): void {
    session.on('play', () => this.host.onPlay());
    session.on('pause', () => this.host.onPause());
    session.on('stop', () => this.host.onStop());
    session.on('playNext', () => this.host.onPlayNext());
    session.on('playPrevious', () => this.host.onPlayPrevious());
    session.on('setSpeed', (speed: number) => this.host.onSetSpeed(speed));
  }

  private unregisterCommands(session: avSession.AVSession): void {
    try { session.off('play'); } catch (_) {}
    try { session.off('pause'); } catch (_) {}
    try { session.off('stop'); } catch (_) {}
    try { session.off('playNext'); } catch (_) {}
    try { session.off('playPrevious'); } catch (_) {}
    try { session.off('setSpeed'); } catch (_) {}
  }

  async updatePlaybackState(state: avSession.PlaybackState): Promise<void> {
    if (!this.session) return;
    try {
      await this.refreshMediaImage();
      const info = this.host.mediaInfo();
      await this.session.setAVMetadata(this.metadata());
      await this.session.setAVPlaybackState({
        state: state,
        speed: AppStorage.get<number>('ttsSpeed') || 1,
        position: {
          elapsedTime: info.elapsedTime,
          updateTime: Date.now()
        },
        bufferedTime: info.duration,
        loopMode: avSession.LoopMode.LOOP_MODE_SEQUENCE,
        activeItemId: info.chapterIndex
      });
      if (state === avSession.PlaybackState.PLAYBACK_STATE_PLAY ||
        state === avSession.PlaybackState.PLAYBACK_STATE_BUFFERING) {
        await this.session.activate();
      }
    } catch (error) {
      console.warn(`[TTS-BG] update AVSession playback state failed: ` +
        `${ReaderTtsMediaSession.formatError(error as Object)}; ${this.debugState()}`, error);
    }
  }

  async syncSystemMediaControls(): Promise<void> {
    if (!this.host.isSpeaking()) return;
    try {
      if (!this.session) {
        await this.startBackgroundRunning();
        return;
      }
      await this.session.activate();
      await this.updatePlaybackState(this.playbackState());
    } catch (error) {
      console.warn(`[TTS-BG] sync media controls failed: ${ReaderTtsMediaSession.formatError(error as Object)}; ` +
        `${this.debugState()}`, error);
    }
  }

  private metadata(): avSession.AVMetadata {
    const info = this.host.mediaInfo();
    const chapterAssetId = (chapterIndex: number): string => `${info.bookUrl || 'reader_tts'}_${chapterIndex}`;
    const metadata: avSession.AVMetadata = {
      assetId: `${chapterAssetId(info.chapterIndex)}_${info.pageIndex}_${this.mediaImageIdentity()}`,
      title: info.bookName || '朗读',
      subtitle: info.subtitle,
      artist: info.author || '阅读',
      author: info.author || '阅读',
      album: info.bookName || '听书',
      duration: info.duration,
      previousAssetId: info.canPlayPrevious ? chapterAssetId(info.chapterIndex - 1) : '',
      nextAssetId: info.canPlayNext ? chapterAssetId(info.chapterIndex + 1) : '',
      avQueueName: info.bookName || '听书',
      avQueueId: info.bookUrl || 'reader_tts'
    };
    if (this.mediaPixelMap) {
      metadata.mediaImage = this.mediaPixelMap;
      metadata.avQueueImage = this.mediaPixelMap;
    } else if (this.mediaImage) {
      metadata.mediaImage = this.mediaImage;
      metadata.avQueueImage = this.mediaImage;
    }
    return metadata;
  }

  private async stopSession(): Promise<void> {
    if (!this.session) return;
    const session = this.session;
    this.session = null;
    this.unregisterCommands(session);
    this.unwatchOutputDevice();
    try {
      await session.setAVPlaybackState({
        state: avSession.PlaybackState.PLAYBACK_STATE_STOP
      });
    } catch (error) {
      console.warn(`[TTS-BG] mark AVSession stopped failed: ${ReaderTtsMediaSession.formatError(error as Object)}`,
        error);
    }
    try {
      await session.deactivate();
    } catch (error) {
      console.warn(`[TTS-BG] deactivate AVSession failed: ${ReaderTtsMediaSession.formatError(error as Object)}`,
        error);
    }
    try {
      await session.destroy();
      console.info('[TTS-BG] AVSession destroyed');
    } catch (error) {
      console.warn(`[TTS-BG] destroy AVSession failed: ${ReaderTtsMediaSession.formatError(error as Object)}`, error);
    } finally {
      this.mediaImage = '';
      this.mediaImageRaw = '';
      this.releaseMediaPixelMap();
    }
  }

  // ---------------------------------------------------------------- 输出设备

  /**
   * 蓝牙/有线耳机断开时系统把声音切回外放，朗读不会自己停。监听朗读这类流的首选输出设备，
   * 从耳机等外接设备落回扬声器/听筒时按耳机暂停键处理。系统朗读引擎自己播放，拿不到它的
   * AudioRenderer，所以在这里统一监听而不是挂在各播放器上。
   */
  private watchOutputDevice(): void {
    if (this.routingManager) return;
    try {
      const manager = audio.getAudioManager().getRoutingManager();
      this.outputOnExternalDevice = ReaderTtsMediaSession.isExternalOutput(
        manager.getPreferredOutputDeviceForRendererInfoSync(this.outputRendererInfo));
      manager.on('preferOutputDeviceChangeForRendererInfo', this.outputRendererInfo, this.onPreferredOutputChange);
      this.routingManager = manager;
    } catch (error) {
      console.warn(`[TTS-BG] watch output device failed: ${ReaderTtsMediaSession.formatError(error as Object)}`, error);
    }
  }

  private unwatchOutputDevice(): void {
    if (!this.routingManager) return;
    try {
      this.routingManager.off('preferOutputDeviceChangeForRendererInfo', this.onPreferredOutputChange);
    } catch (error) {
      console.warn(`[TTS-BG] unwatch output device failed: ${ReaderTtsMediaSession.formatError(error as Object)}`,
        error);
    }
    this.routingManager = null;
    this.outputOnExternalDevice = false;
  }

  private handleOutputDeviceChange(devices: audio.AudioDeviceDescriptors): void {
    const wasExternal = this.outputOnExternalDevice;
    const external = ReaderTtsMediaSession.isExternalOutput(devices);
    this.outputOnExternalDevice = external;
    const builtIn = devices.some((device: audio.AudioDeviceDescriptor): boolean =>
      device.deviceType === audio.DeviceType.SPEAKER || device.deviceType === audio.DeviceType.EARPIECE);
    if (!wasExternal || external || !builtIn) return;
    console.info(`[TTS-BG] output fell back to built-in device, pausing: ${this.debugState()}`);
    if (this.host.isSpeaking() && !this.host.isPaused()) {
      this.host.onPause();
    }
  }

  private static isExternalOutput(devices: audio.AudioDeviceDescriptors): boolean {
    return devices.some((device: audio.AudioDeviceDescriptor): boolean =>
      device.deviceType !== audio.DeviceType.SPEAKER &&
        device.deviceType !== audio.DeviceType.EARPIECE &&
        device.deviceType !== audio.DeviceType.INVALID);
  }

  // ---------------------------------------------------------------- 媒体卡片封面

  async refreshMediaImage(): Promise<void> {
    const serial = ++this.mediaImageRefreshSerial;
    const raw = this.host.coverRaw();
    const rawKey = JSON.stringify(raw);
    if (raw && rawKey === this.mediaImageRaw && this.mediaPixelMap) return;
    if (!raw) {
      if (serial === this.mediaImageRefreshSerial) {
        this.mediaImage = '';
        this.mediaImageRaw = '';
        this.releaseMediaPixelMap();
      }
      return;
    }
    let resolved = typeof raw === 'string' ? raw : '';
    let pixelMap: image.PixelMap | null = null;
    try {
      const context = this.host.abilityContext();
      const coverPath = await BookCoverResolver.prepareFile(context, raw);
      if (coverPath) {
        pixelMap = await this.createMediaPixelMap(coverPath);
        resolved = fileUri.getUriFromPath(coverPath);
      } else if (typeof raw === 'string') {
        resolved = await BookCoverCache.resolveCover(context, raw);
      }
    } catch (error) {
      console.warn('解析朗读媒体封面失败:', error);
    }
    if (serial === this.mediaImageRefreshSerial) {
      this.releaseMediaPixelMap();
      this.mediaImage = resolved;
      this.mediaImageRaw = rawKey;
      this.mediaPixelMap = pixelMap;
    } else if (pixelMap) {
      pixelMap.release().catch((e: Error) => {
        console.warn('释放过期朗读媒体封面失败:', e);
      });
    }
  }

  private async createMediaPixelMap(path: string): Promise<image.PixelMap | null> {
    let file: fs.File | null = null;
    let source: image.ImageSource | null = null;
    try {
      file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      source = image.createImageSource(file.fd);
      return await source.createPixelMap({
        desiredSize: {
          width: 512,
          height: 512
        }
      });
    } catch (error) {
      console.warn('创建朗读媒体封面 PixelMap 失败:', error);
      return null;
    } finally {
      if (source) {
        try {
          await source.release();
        } catch (e) {
        }
      }
      if (file) {
        try {
          fs.closeSync(file);
        } catch (e) {
        }
      }
    }
  }

  private releaseMediaPixelMap(): void {
    if (!this.mediaPixelMap) return;
    try {
      this.mediaPixelMap.release().catch((e: Error) => {
        console.warn('释放朗读媒体封面失败:', e);
      });
    } catch (e) {
      console.warn('释放朗读媒体封面失败:', e);
    }
    this.mediaPixelMap = null;
  }

  private mediaImageIdentity(): string {
    const value = this.mediaImageRaw || this.mediaImage || 'cover';
    let hash = 0;
    for (let i = 0; i < value.length; i++) {
      hash = value.charCodeAt(i) + ((hash << 5) - hash);
    }
    return Math.abs(hash).toString(16);
  }
}
