import { textToSpeech } from '@kit.CoreSpeechKit';
import { connection } from '@kit.NetworkKit';
import deviceInfo from '@ohos.deviceInfo';
import { CloudTtsAudio, CloudTtsClient, CloudTtsTiming } from '../account/CloudTtsClient';
import { HttpTTS } from '../model/data/Book';
import { HttpTtsAudio, HttpTtsReader } from './HttpTtsReader';
import { TtsAudioSession } from './TtsAudioSession';
import { PcmPlaybackCue, TtsPcmAudioPlayer } from './TtsPcmAudioPlayer';

export interface TtsChunk {
  text: string;
  start: number;
  end: number;
}

export interface TtsReadOptions {
  onFinished?: () => void;
  onError?: (message: string) => void;
  onChunkStart?: (chunk: TtsChunk, index: number) => void;
  onAudioStart?: () => void;
  person?: number;
  online?: number;
  style?: string;
  language?: string;
  speed?: number;
  cloudVoiceId?: string;
  cloudVoiceName?: string;
  cloudVoiceTier?: string;
  focusBreakOffsets?: number[];
  keepAudioOutputOnFinish?: boolean;
}

export interface TtsVoiceDownloadCallbacks {
  onStart?: (message: string) => void;
  onProgress?: (progress: string) => void;
}

interface CustomTtsAudioResult {
  audio?: HttpTtsAudio;
  error?: Error;
}

interface CustomTtsAudioJob {
  index: number;
  chunk: TtsChunk;
  text: string;
  promise: Promise<CustomTtsAudioResult>;
}

interface CloudTtsAudioResult {
  audio?: CloudTtsAudio;
  error?: Error;
}

interface CloudTtsAudioJob {
  index: number;
  chunk: TtsChunk;
  text: string;
  sourceToSpeechOffsets: number[];
  promise: Promise<CloudTtsAudioResult>;
}

interface NormalizedSpeechText {
  text: string;
  sourceToSpeechOffsets: number[];
}

interface SystemPcmSegment {
  index: number;
  chunk: TtsChunk;
  pcm: ArrayBuffer;
  sampleRate: number;
}

export class TtsVoiceOption {
  id: number = 0;
  name: string = '默认音色';
  online: number = 1;
  status: string = '';
  systemStatus: string = '';
  style: string = '';
  language: string = 'zh-CN';
  downloadLanguage: string = '';
  gender: string = '';
  available: boolean = true;
  downloadable: boolean = false;
}

export class SystemTtsReader {
  private static audioSessionOwnerSerial: number = 0;
  private static readonly LEGACY_ONLINE_MODE: number = 0;
  private static readonly OFFLINE_MODE: number = 1;
  private static readonly CUSTOM_TTS_PREFETCH_WINDOW: number = 3;
  private static readonly CUSTOM_TTS_HIDDEN_GAP_LENGTH: number = 8;
  private static readonly CLOUD_TTS_WIFI_PREFETCH_WINDOW: number = 2;
  private static readonly CLOUD_TTS_MOBILE_PREFETCH_WINDOW: number = 1;
  private static readonly CLOUD_TTS_FOCUS_CHUNK_LENGTH: number = 10;
  private static readonly CLOUD_TTS_STANDARD_FIRST_CHUNK_LENGTH: number = 100;
  private static readonly CLOUD_TTS_PREMIUM_FIRST_CHUNK_LENGTH: number = 50;
  private static readonly SYSTEM_TTS_START_BUFFER_SEGMENTS: number = 2;
  private static readonly SYSTEM_TTS_MAX_BUFFERED_SEGMENTS: number = 3;
  private static readonly DIRECT_PLAY_COMPLETION_GRACE_MS: number = 5000;
  private static readonly MAX_ESTIMATED_CHUNK_DURATION_MS: number = 45000;
  private engine: textToSpeech.TextToSpeechEngine | null = null;
  private pcmPlayer: TtsPcmAudioPlayer = new TtsPcmAudioPlayer();
  private httpReader: HttpTtsReader = new HttpTtsReader();
  private cloudReader: CloudTtsClient = new CloudTtsClient();
  private chunks: TtsChunk[] = [];
  private chunkIndex: number = 0;
  private active: boolean = false;
  private paused: boolean = false;
  private onFinished?: () => void;
  private onError?: (message: string) => void;
  private onChunkStart?: (chunk: TtsChunk, index: number) => void;
  private onAudioStart?: () => void;
  private audioStarted: boolean = false;
  private currentRequestId: string = '';
  private readGeneration: number = 0;
  private currentSpeakStartedAt: number = 0;
  private currentSpeakMinDuration: number = 0;
  private completionPending: boolean = false;
  private currentAudioSampleRate: number = 16000;
  private currentAudioSampleBit: number = 16;
  private currentAudioChannel: number = 1;
  private currentAudioType: string = 'pcm';
  private currentFocusChunk: TtsChunk | null = null;
  private currentFocusChunkIndex: number = -1;
  private currentFocusDuration: number = 0;
  private currentFocusQueued: boolean = false;
  private currentFocusAudioReceived: boolean = false;
  private currentFocusAudioWritten: boolean = false;
  private currentAudioWritePromise: Promise<void> = Promise.resolve();
  private currentFocusRetryCount: number = 0;
  // Keep playback in this application's AUDIOBOOK AudioRenderer. Letting the
  // system TTS service play directly moves the audible stream to its process,
  // so HarmonyOS sees this app's audioPlayback task as idle and freezes it.
  private ttsPcmPlayType: number = 0;
  private speakWatchdogId: number = -1;
  private suppressEngineStopEvent: boolean = false;
  private enginePerson: number = -1;
  private engineOnline: number = -1;
  private engineStyle: string = '';
  private engineLanguage: string = '';
  private optionPerson: number | null = null;
  private optionOnline: number | null = null;
  private optionStyle: string | null = null;
  private optionLanguage: string | null = null;
  private optionSpeed: number | null = null;
  private optionCloudVoiceId: string = '';
  private optionCloudVoiceName: string = '';
  private optionCloudVoiceTier: string = 'STANDARD';
  private optionFocusBreakOffsets: number[] = [];
  private systemCurrentPcmBuffers: ArrayBuffer[] = [];
  private systemCurrentPcmSequences: number[] = [];
  private systemCurrentPcmBytes: number = 0;
  private systemReadySegments: SystemPcmSegment[] = [];
  private systemPlaybackStarted: boolean = false;
  private systemSynthesisFinished: boolean = false;
  private systemDrainScheduled: boolean = false;
  private systemLastWritePromise: Promise<void> = Promise.resolve();
  private systemBufferedSegmentCount: number = 0;
  private systemAudioSessionOwner: string = '';
  private keepAudioOutputOnFinish: boolean = false;
  private pcmOutputReleaseTimerId: number = -1;

  static async listAvailableVoices(): Promise<TtsVoiceOption[]> {
    try {
      let voices: TtsVoiceOption[] = [];
      voices = voices.concat(await SystemTtsReader.listModuleVoices(SystemTtsReader.OFFLINE_MODE));
      voices = voices.concat(await SystemTtsReader.listModuleVoices(SystemTtsReader.LEGACY_ONLINE_MODE));
      if (voices.length === 0) {
        voices = SystemTtsReader.knownVoiceOptions();
      } else {
        voices = SystemTtsReader.knownVoiceOptions().concat(voices);
      }
      const parsed = SystemTtsReader.dedupeVoices(voices);
      return SystemTtsReader.applyVoiceFeatureAvailability(
        parsed.length > 0 ? parsed : SystemTtsReader.defaultVoices());
    } catch (_) {
      return SystemTtsReader.applyVoiceFeatureAvailability(
        SystemTtsReader.dedupeVoices(SystemTtsReader.knownVoiceOptions()));
    }
  }

  static supportsVoiceDownload(): boolean {
    return deviceInfo.sdkApiVersion >= 19;
  }

  static async downloadVoice(voice: TtsVoiceOption, callbacks?: TtsVoiceDownloadCallbacks): Promise<void> {
    if (!SystemTtsReader.supportsVoiceDownload()) {
      throw new Error('当前系统版本不支持下载系统音色，请升级至 API 19 或更高版本');
    }
    const variants = SystemTtsReader.createVoiceDownloadVariants(voice);
    let lastError: Error | undefined = undefined;
    for (const params of variants) {
      try {
        await SystemTtsReader.downloadVoiceWithParams(params, callbacks);
        return;
      } catch (error) {
        lastError = error as Error;
      }
    }
    throw lastError || new Error('音色下载失败');
  }

  private static downloadVoiceWithParams(downloadParams: textToSpeech.VoiceDownload,
    callbacks?: TtsVoiceDownloadCallbacks): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      console.info(`[TTS] downloadVoice request: person=${downloadParams.person}, language=${downloadParams.language}, style=${downloadParams.style}`);
      let settled = false;
      let response: textToSpeech.DownloadResponse | null = null;
      const cleanup = (): void => {
        if (!response) {
          return;
        }
        try {
          response.off('start', startCallback);
          response.off('progress', progressCallback);
          response.off('complete', completeCallback);
          response.off('cancel', cancelCallback);
          response.off('error', errorCallback);
        } catch (_) {
        }
      };
      const finish = (): void => {
        if (settled) {
          return;
        }
        settled = true;
        cleanup();
        console.info(`[TTS] downloadVoice finished: person=${downloadParams.person}, language=${downloadParams.language}, style=${downloadParams.style}`);
        resolve();
      };
      const fail = (error: Object | undefined, fallback: string): void => {
        if (settled) {
          return;
        }
        settled = true;
        cleanup();
        const message = SystemTtsReader.formatStaticError(error) || fallback;
        console.error(`[TTS] downloadVoice failed: person=${downloadParams.person}, language=${downloadParams.language}, style=${downloadParams.style}, error=${message}`);
        reject(new Error(message));
      };
      const startCallback = (message: string): void => {
        console.info(`[TTS] downloadVoice started: ${message || downloadParams.requestId}`);
        if (callbacks && callbacks.onStart) {
          callbacks.onStart(message || '');
        }
      };
      const progressCallback = (progress: string): void => {
        console.info(`[TTS] downloadVoice progress: ${progress || ''}`);
        if (callbacks && callbacks.onProgress) {
          callbacks.onProgress(progress || '');
        }
      };
      const completeCallback = (_voiceInfo: textToSpeech.VoiceInfo): void => {
        finish();
      };
      const cancelCallback = (_message: string): void => {
        fail(undefined, '音色下载已取消');
      };
      const errorCallback = (error: Object): void => {
        fail(error as Object, '音色下载失败');
      };
      try {
        textToSpeech.downloadVoice(downloadParams, (error: Object | null | undefined,
          downloadResponse: textToSpeech.DownloadResponse) => {
          const code = SystemTtsReader.errorCode(error as Object | undefined);
          if (code === 1002300010) {
            finish();
            return;
          }
          if (error) {
            fail(error as Object, '音色下载失败');
            return;
          }
          if (!downloadResponse) {
            fail(undefined, '音色下载失败');
            return;
          }
          response = downloadResponse;
          response.on('start', startCallback);
          response.on('progress', progressCallback);
          response.on('complete', completeCallback);
          response.on('cancel', cancelCallback);
          response.on('error', errorCallback);
        });
      } catch (error) {
        const code = SystemTtsReader.errorCode(error as Object);
        if (code === 1002300010) {
          finish();
          return;
        }
        fail(error as Object, '音色下载失败');
      }
    });
  }

  audioDebugState(): string {
    return (this.getCurrentCustomVoice() || this.optionCloudVoiceId) ?
      this.httpReader.debugState() : this.pcmPlayer.debugState();
  }

  private static createVoiceDownloadVariants(voice: TtsVoiceOption): textToSpeech.VoiceDownload[] {
    const languages: string[] = [];
    const addLanguage = (language: string): void => {
      const value = (language || '').trim();
      if (value && !languages.includes(value)) {
        languages.push(value);
      }
    };
    addLanguage(voice.downloadLanguage);
    for (const language of SystemTtsReader.languageVariants(voice.language || 'zh-CN')) {
      addLanguage(language);
    }
    const styles: string[] = [];
    const addStyle = (style: string): void => {
      if (!styles.includes(style)) {
        styles.push(style);
      }
    };
    addStyle(voice.style || '');
    addStyle('');
    const result: textToSpeech.VoiceDownload[] = [];
    for (const language of languages) {
      for (const style of styles) {
        result.push({
          requestId: `voice_download_${Date.now()}_${voice.id}_${result.length}`,
          language: language,
          person: voice.id,
          style: style
        });
      }
    }
    return result;
  }

  private static async listModuleVoices(online: number): Promise<TtsVoiceOption[]> {
    if (deviceInfo.sdkApiVersion < 19) {
      return SystemTtsReader.listLegacyEngineVoices(online);
    }
    try {
      const voices = await textToSpeech.listVoices({
        requestId: `module_voices_${online}_${Date.now()}`,
        online: online
      });
      console.info(`[TTS] module listVoices online=${online}: ${SystemTtsReader.voiceInfosSummary(voices)}`);
      return SystemTtsReader.parseVoices(voices, online);
    } catch (error) {
      console.warn(`[TTS] module listVoices failed online=${online}: ${SystemTtsReader.formatStaticError(error as Object)}`);
      return [];
    }
  }

  private static errorCode(error: Object | null | undefined): number {
    if (!error) {
      return 0;
    }
    const anyError = error as Record<string, Object>;
    const code = anyError['code'];
    if (typeof code === 'number') {
      return Math.round(code);
    }
    if (code !== undefined) {
      const parsed = Number(String(code));
      if (!Number.isNaN(parsed)) {
        return Math.round(parsed);
      }
    }
    return 0;
  }

  private static voiceInfosSummary(voices: Array<textToSpeech.VoiceInfo>): string {
    if (!voices || voices.length === 0) {
      return 'empty';
    }
    const items: string[] = [];
    for (const voice of voices) {
      items.push(`person=${voice.person},language=${voice.language || ''},style=${voice.style || ''},gender=${voice.gender || ''},status=${voice.status || ''},description=${voice.description || ''}`);
    }
    return items.join(' | ');
  }

  async start(text: string, options?: TtsReadOptions): Promise<void> {
    const reusingPcmOutput = this.cancelPendingPcmOutputRelease();
    if (reusingPcmOutput) {
      console.info(`[TTS] reusing pcm output across chapter handoff: ${this.pcmPlayer.debugState()}`);
    }
    const cleanText = this.normalizeText(text);
    if (!cleanText || !cleanText.trim()) {
      throw new Error('朗读内容为空');
    }
    if (this.active || this.currentRequestId || this.chunks.length > 0) {
      this.stop();
    } else {
      this.clearSpeakWatchdog();
      this.releaseSystemAudioSession();
    }
    const generation = ++this.readGeneration;
    this.paused = false;
    this.onFinished = options?.onFinished;
    this.onError = options?.onError;
    this.onChunkStart = options?.onChunkStart;
    this.onAudioStart = options?.onAudioStart;
    this.audioStarted = false;
    this.ttsPcmPlayType = 0;
    this.optionPerson = options?.person ?? null;
    this.optionOnline = options?.online ?? null;
    this.optionStyle = options?.style ?? null;
    this.optionLanguage = options?.language ?? null;
    this.optionSpeed = options?.speed ?? null;
    this.optionCloudVoiceId = options?.cloudVoiceId || '';
    this.optionCloudVoiceName = options?.cloudVoiceName || '';
    this.optionCloudVoiceTier = (options?.cloudVoiceTier || '').toUpperCase() === 'PREMIUM' ?
      'PREMIUM' : 'STANDARD';
    this.optionFocusBreakOffsets = this.normalizeFocusBreakOffsets(options?.focusBreakOffsets, cleanText.length);
    this.keepAudioOutputOnFinish = options?.keepAudioOutputOnFinish === true;
    const customVoice = this.getCurrentCustomVoice();
    const splitChunks = this.optionCloudVoiceId ? this.splitCloudText(cleanText) :
      (customVoice ? this.splitCustomText(cleanText, 64) :
        this.splitSystemText(cleanText, this.optionFocusBreakOffsets));
    // A run of trailing punctuation (for example "......" or "……") can be split into a
    // punctuation-only chunk. Some Harmony TTS engines return no PCM/onStart for such a
    // chunk, which makes the reader believe the chapter tail was not spoken and retry/stop.
    // Coalesce those chunks with the preceding readable chunk while keeping the original
    // source offsets intact. This applies to all synthesis routes (system/custom/cloud).
    this.chunks = this.coalescePunctuationOnlyChunks(splitChunks, cleanText);
    if (this.chunks.length === 0) {
      throw new Error('朗读内容为空');
    }
    this.chunkIndex = 0;
    this.active = true;
    if (this.optionCloudVoiceId) {
      if (this.engine) {
        try {
          this.engine.shutdown();
        } catch (_) {
        }
        this.engine = null;
      }
      this.speakCloudNext(generation, this.optionCloudVoiceId);
      return;
    }
    if (customVoice) {
      if (this.engine) {
        try {
          this.engine.shutdown();
        } catch (_) {
        }
        this.engine = null;
      }
      this.speakCustomNext(generation, customVoice);
      return;
    }
    this.resetSystemPcmPipeline();
    let engine: textToSpeech.TextToSpeechEngine;
    try {
      engine = await this.ensureEngine();
    } catch (error) {
      this.active = false;
      const message = `TTS初始化失败：${this.currentVoiceLabel()} ${this.formatError(error)}`;
      console.error('[TTS] ensure engine failed:', message);
      if (this.onError) {
        this.onError(message);
        return;
      }
      throw new Error(message);
    }
    if (!this.active || this.readGeneration !== generation) {
      return;
    }
    const audioSessionOwner = `system-tts-${++SystemTtsReader.audioSessionOwnerSerial}`;
    this.systemAudioSessionOwner = audioSessionOwner;
    await TtsAudioSession.acquire(audioSessionOwner);
    if (!this.active || this.readGeneration !== generation || this.systemAudioSessionOwner !== audioSessionOwner) {
      TtsAudioSession.release(audioSessionOwner);
      if (this.systemAudioSessionOwner === audioSessionOwner) {
        this.systemAudioSessionOwner = '';
      }
      return;
    }
    this.bindEngineListener(generation, engine);
    this.speakNext(generation);
  }

  private bindEngineListener(generation: number, engine: textToSpeech.TextToSpeechEngine): void {
    engine.setListener({
      onStart: (utteranceId: string, response: textToSpeech.StartResponse) => {
        if (this.readGeneration !== generation || !this.active || utteranceId !== this.currentRequestId) {
          return;
        }
        this.currentAudioSampleRate = response && response.sampleRate ? response.sampleRate : 16000;
        this.currentAudioSampleBit = response && response.sampleBit ? response.sampleBit : 16;
        this.currentAudioChannel = response && response.audioChannel ? response.audioChannel : 1;
        this.currentAudioType = response && response.audioType ? response.audioType : 'pcm';
        console.info(`[TTS] speak start: audioType=${this.currentAudioType},` +
          `sampleRate=${this.currentAudioSampleRate},sampleBit=${this.currentAudioSampleBit},` +
          `channels=${this.currentAudioChannel},${this.pcmPlayer.debugState()}`);
        if (this.ttsPcmPlayType !== 0) {
          this.emitCurrentSystemChunkFocus(generation);
          this.notifyAudioStarted();
        }
      },
      onComplete: (utteranceId: string, response: textToSpeech.CompleteResponse) => {
        if (this.readGeneration !== generation || !this.active || utteranceId !== this.currentRequestId) {
          return;
        }
        console.info(`[TTS] speak complete: type=${response ? response.type : -1},request=${utteranceId}`);
        if (this.ttsPcmPlayType === 1 && (!response || response.type !== 1)) {
          // HarmonyOS sends type=0 when synthesis is complete and type=1 only
          // after direct speech playback has actually completed. Advancing on
          // type=0 truncates the audible chunk and can consume a whole chapter
          // in seconds.
          return;
        }
        if (!this.currentFocusAudioReceived) {
          console.info(`[TTS] speak complete without pcm data: ${this.pcmPlayer.debugState()}`);
          if (this.retryWithoutPcmData(generation)) {
            return;
          }
        }
        if (!this.currentFocusAudioReceived) {
          this.emitCurrentSystemChunkFocus(generation);
          this.clearSpeakWatchdog();
        }
        this.completeCurrentChunk(generation, utteranceId);
      },
      onStop: () => {
        if (this.suppressEngineStopEvent) {
          return;
        }
        if (this.readGeneration !== generation || !this.active) {
          return;
        }
        this.finish(false);
      },
      onError: (utteranceId: string, errorCode: number, errorMessage: string) => {
        if (this.readGeneration !== generation || !this.active || utteranceId !== this.currentRequestId) {
          return;
        }
        this.currentRequestId = '';
        this.active = false;
        this.clearSpeakWatchdog();
        this.pcmPlayer.stop();
        this.releaseSystemAudioSession();
        const message = `${errorMessage || `系统朗读失败(${errorCode})`}：${this.currentVoiceLabel()}`;
        console.error('[TTS] speak error:', message);
        if (this.onError) this.onError(message);
      },
      onData: (utteranceId: string, audioData: ArrayBuffer, response: textToSpeech.SynthesisResponse) => {
        if (this.readGeneration !== generation || !this.active || utteranceId !== this.currentRequestId ||
          !audioData || audioData.byteLength === 0) {
          return;
        }
        if (this.ttsPcmPlayType !== 0) {
          return;
        }
        this.currentFocusAudioReceived = true;
        this.systemCurrentPcmBuffers.push(audioData.slice(0));
        this.systemCurrentPcmSequences.push(response && response.sequence ? response.sequence :
          this.systemCurrentPcmSequences.length + 1);
        this.systemCurrentPcmBytes += audioData.byteLength;
        this.armSpeakWatchdog(generation, this.currentFocusChunkIndex);
        console.info(`[TTS] pcm data buffered: sequence=${response ? response.sequence : -1},` +
          `bytes=${audioData.byteLength},total=${this.systemCurrentPcmBytes}`);
      }
    });
  }

  async pause(): Promise<boolean> {
    if (!this.active || this.paused) {
      return this.active && this.paused;
    }
    this.paused = true;
    await this.pcmPlayer.pause();
    await this.httpReader.pause();
    if (this.ttsPcmPlayType === 1 && this.engine) {
      const resumeIndex = this.currentFocusChunkIndex;
      if (resumeIndex >= 0) {
        this.chunkIndex = Math.max(0, Math.min(resumeIndex, this.chunks.length));
      }
      this.currentRequestId = '';
      this.currentSpeakStartedAt = 0;
      this.currentSpeakMinDuration = 0;
      this.completionPending = false;
      this.currentFocusChunk = null;
      this.currentFocusChunkIndex = -1;
      this.currentFocusDuration = 0;
      this.currentFocusQueued = false;
      this.clearSpeakWatchdog();
      try {
        this.suppressEngineStopEvent = true;
        this.engine.stop();
      } catch (_) {
      } finally {
        setTimeout(() => {
          this.suppressEngineStopEvent = false;
        }, 500);
      }
    }
    return true;
  }

  async resume(): Promise<boolean> {
    if (!this.active || !this.paused) {
      return this.active && !this.paused;
    }
    this.paused = false;
    await this.pcmPlayer.resume();
    await this.httpReader.resume();
    if (this.ttsPcmPlayType === 1 && this.engine && !this.currentRequestId) {
      this.speakNext(this.readGeneration);
    }
    return true;
  }

  isPaused(): boolean {
    return this.active && this.paused;
  }

  stop(): void {
    this.cancelPendingPcmOutputRelease();
    this.readGeneration++;
    this.active = false;
    this.paused = false;
    this.chunks = [];
    this.chunkIndex = 0;
    this.onChunkStart = undefined;
    this.onAudioStart = undefined;
    this.audioStarted = false;
    this.optionPerson = null;
    this.optionOnline = null;
    this.optionStyle = null;
    this.optionLanguage = null;
    this.optionSpeed = null;
    this.optionCloudVoiceId = '';
    this.optionCloudVoiceName = '';
    this.optionCloudVoiceTier = 'STANDARD';
    this.optionFocusBreakOffsets = [];
    this.keepAudioOutputOnFinish = false;
    this.currentRequestId = '';
    this.currentSpeakStartedAt = 0;
    this.currentSpeakMinDuration = 0;
    this.completionPending = false;
    this.currentFocusChunk = null;
    this.currentFocusChunkIndex = -1;
    this.currentFocusDuration = 0;
    this.currentFocusQueued = false;
    this.currentFocusAudioReceived = false;
    this.currentFocusAudioWritten = false;
    this.currentAudioWritePromise = Promise.resolve();
    this.currentFocusRetryCount = 0;
    this.ttsPcmPlayType = 0;
    this.resetSystemPcmPipeline();
    this.clearSpeakWatchdog();
    this.httpReader.stop();
    this.cloudReader.stop();
    this.pcmPlayer.stop();
    this.releaseSystemAudioSession();
    try {
      this.engine?.stop();
    } catch (_) {
    }
  }

  shutdown(): void {
    this.stop();
    try {
      this.engine?.shutdown();
    } catch (_) {
    }
    this.pcmPlayer.release();
    this.httpReader.release();
    this.engine = null;
  }

  isSpeaking(): boolean {
    return this.active;
  }

  private async ensureEngine(): Promise<textToSpeech.TextToSpeechEngine> {
    const person = this.getTtsPerson();
    const online = this.getTtsOnline();
    const style = this.getTtsStyle();
    const language = this.getTtsLanguage();
    if (this.engine && this.enginePerson === person && this.engineOnline === online &&
      this.engineStyle === style && this.engineLanguage === language) return this.engine;
    if (this.engine) {
      try {
        this.engine.shutdown();
      } catch (_) {
      }
      this.engine = null;
    }
    let actualOnline = online;
    let lastError: Object | undefined = undefined;
    try {
      this.engine = await SystemTtsReader.createEngineWithMode(person, online, style, language);
    } catch (error) {
      lastError = error as Object;
      actualOnline = SystemTtsReader.alternateOnlineMode(online);
      try {
        this.engine = await SystemTtsReader.createEngineWithMode(person, actualOnline, style, language);
      } catch (secondError) {
        lastError = secondError as Object;
        throw new Error(SystemTtsReader.formatStaticError(lastError) || 'createEngine failed');
      }
    }
    this.enginePerson = person;
    this.engineOnline = actualOnline;
    this.engineStyle = style;
    this.engineLanguage = language;
    if (this.optionOnline === null && actualOnline !== online) {
      AppStorage.setOrCreate('ttsOnline', actualOnline);
    }
    return this.engine;
  }

  private speakNext(generation: number): void {
    if (this.readGeneration !== generation || !this.active || !this.engine) return;
    if (this.chunkIndex >= this.chunks.length) {
      if (this.ttsPcmPlayType === 0) {
        this.systemSynthesisFinished = true;
        this.pumpSystemPcmPlayback(generation);
      } else {
        this.finish(true);
      }
      return;
    }
    const index = this.chunkIndex;
    const chunk = this.chunks[this.chunkIndex++];
    const speakText = this.normalizeChunkForSpeech(chunk.text);
    if (!speakText) {
      this.speakNext(generation);
      return;
    }
    if (this.currentFocusChunkIndex !== index) {
      this.currentFocusRetryCount = 0;
    }
    const extraParams: Record<string, Object> = {};
    extraParams['queueMode'] = 0 as Object;
    extraParams['speed'] = this.getTtsSpeed() as Object;
    extraParams['volume'] = 2 as Object;
    extraParams['pitch'] = 1 as Object;
    extraParams['languageContext'] = this.getTtsLanguage() as Object;
    extraParams['audioType'] = 'pcm' as Object;
    extraParams['isBackStage'] = true as Object;
    // Keep TTS on the media channel so the hardware volume keys adjust the
    // system media volume instead of a voice-assistant relative volume.
    extraParams['soundChannel'] = 1 as Object;
    extraParams['playType'] = this.ttsPcmPlayType as Object;
    try {
      const requestId = this.createRequestId();
      this.currentRequestId = requestId;
      this.currentSpeakStartedAt = Date.now();
      this.currentSpeakMinDuration = this.estimateSpeakDuration(speakText);
      this.completionPending = false;
      this.currentFocusChunk = chunk;
      this.currentFocusChunkIndex = index;
      this.currentFocusDuration = this.currentSpeakMinDuration;
      this.currentFocusQueued = false;
      this.currentFocusAudioReceived = false;
      this.currentFocusAudioWritten = false;
      this.currentAudioWritePromise = Promise.resolve();
      this.currentAudioSampleRate = 16000;
      this.currentAudioSampleBit = 16;
      this.currentAudioChannel = 1;
      this.currentAudioType = 'pcm';
      this.systemCurrentPcmBuffers = [];
      this.systemCurrentPcmSequences = [];
      this.systemCurrentPcmBytes = 0;
      this.armSpeakWatchdog(generation, index);
      this.engine.speak(speakText, {
        requestId: requestId,
        extraParams: extraParams
      });
    } catch (error) {
      this.currentRequestId = '';
      this.currentSpeakStartedAt = 0;
      this.currentSpeakMinDuration = 0;
      this.completionPending = false;
      this.currentFocusChunk = null;
      this.currentFocusChunkIndex = -1;
      this.currentFocusDuration = 0;
      this.currentFocusQueued = false;
      this.currentFocusAudioReceived = false;
      this.currentFocusAudioWritten = false;
      this.currentFocusRetryCount = 0;
      this.clearSpeakWatchdog();
      this.active = false;
      this.pcmPlayer.stop();
      this.releaseSystemAudioSession();
      const message = `系统朗读失败：${this.currentVoiceLabel()} ${this.formatError(error)}`;
      console.error('[TTS] speak throw:', message);
      if (this.onError) this.onError(message);
    }
  }

  private finish(notify: boolean): void {
    const keepPcmOutput = notify && this.keepAudioOutputOnFinish && this.ttsPcmPlayType === 0;
    this.readGeneration++;
    this.active = false;
    this.paused = false;
    this.chunks = [];
    this.chunkIndex = 0;
    this.onChunkStart = undefined;
    this.currentRequestId = '';
    this.currentSpeakStartedAt = 0;
    this.currentSpeakMinDuration = 0;
    this.completionPending = false;
    this.currentFocusChunk = null;
    this.currentFocusChunkIndex = -1;
    this.currentFocusDuration = 0;
    this.currentFocusQueued = false;
    this.currentFocusAudioReceived = false;
    this.currentFocusAudioWritten = false;
    this.currentAudioWritePromise = Promise.resolve();
    this.currentFocusRetryCount = 0;
    this.resetSystemPcmPipeline();
    this.clearSpeakWatchdog();
    if (keepPcmOutput) {
      // Continuous reading restarts with the next chapter. Keep the same
      // AudioRenderer and audio-session owner across that short handoff so the
      // device does not reselect an audio route or recalculate stream gain at
      // every (possibly hour-long) chapter boundary.
      this.schedulePcmOutputRelease();
    } else {
      this.pcmPlayer.stop();
    }
    this.releaseSystemAudioSession();
    this.audioStarted = false;
    this.optionCloudVoiceId = '';
    this.optionCloudVoiceName = '';
    this.optionCloudVoiceTier = 'STANDARD';
    this.optionFocusBreakOffsets = [];
    this.keepAudioOutputOnFinish = false;
    if (notify && this.onFinished) this.onFinished();
  }

  private schedulePcmOutputRelease(): void {
    this.cancelPendingPcmOutputRelease();
    console.info(`[TTS] keeping pcm output for chapter handoff: ${this.pcmPlayer.debugState()}`);
    this.pcmOutputReleaseTimerId = setTimeout(() => {
      this.pcmOutputReleaseTimerId = -1;
      if (!this.active) {
        console.info('[TTS] releasing idle pcm output after chapter handoff grace period');
        this.pcmPlayer.stop();
      }
    }, 15000);
  }

  private cancelPendingPcmOutputRelease(): boolean {
    if (this.pcmOutputReleaseTimerId < 0) {
      return false;
    }
    clearTimeout(this.pcmOutputReleaseTimerId);
    this.pcmOutputReleaseTimerId = -1;
    return true;
  }

  private releaseSystemAudioSession(): void {
    const owner = this.systemAudioSessionOwner;
    this.systemAudioSessionOwner = '';
    if (owner) {
      TtsAudioSession.release(owner);
    }
  }

  private speakCloudNext(generation: number, voiceId: string): void {
    this.playCloudQueue(generation, voiceId).catch((error: Error) => {
      if (this.readGeneration !== generation || !this.active) {
        return;
      }
      this.currentRequestId = '';
      this.active = false;
      const label = this.optionCloudVoiceName || '在线音色';
      const message = `${label}朗读失败：${this.formatError(error)}`;
      console.error('[TTS] cloud voice failed:', message);
      if (this.onError) this.onError(message);
    });
  }

  private async playCloudQueue(generation: number, voiceId: string): Promise<void> {
    const jobs: CloudTtsAudioJob[] = [];
    this.fillCloudAudioJobs(generation, voiceId, jobs);
    while (this.readGeneration === generation && this.active) {
      if (jobs.length === 0) {
        await this.httpReader.drain();
        if (this.readGeneration === generation && this.active) {
          this.httpReader.stop();
          this.finish(true);
        }
        return;
      }
      const job = jobs.shift() as CloudTtsAudioJob;
      this.currentRequestId = this.createRequestId();
      this.currentSpeakStartedAt = Date.now();
      this.currentSpeakMinDuration = this.estimateSpeakDuration(job.text);
      this.currentFocusChunk = job.chunk;
      this.currentFocusChunkIndex = job.index;
      this.currentFocusDuration = this.currentSpeakMinDuration;
      this.currentFocusQueued = false;
      this.currentFocusAudioReceived = false;
      this.currentFocusAudioWritten = false;
      const result = await job.promise;
      if (this.readGeneration !== generation || !this.active) return;
      if (result.error || !result.audio) {
        throw result.error || new Error('在线音色合成失败');
      }
      this.fillCloudAudioJobs(generation, voiceId, jobs);
      this.currentFocusAudioReceived = true;
      const cues = this.buildCloudPlaybackCues(generation, job, result.audio);
      await this.httpReader.writeTimedPcm(result.audio, cues);
      if (this.readGeneration !== generation || !this.active) return;
      this.currentFocusAudioWritten = true;
      this.currentRequestId = '';
      this.currentSpeakStartedAt = 0;
      this.currentSpeakMinDuration = 0;
      this.currentFocusChunk = null;
      this.currentFocusChunkIndex = -1;
      this.currentFocusDuration = 0;
      this.currentFocusQueued = false;
      this.currentFocusAudioReceived = false;
      this.currentFocusAudioWritten = false;
    }
  }

  private fillCloudAudioJobs(generation: number, voiceId: string, jobs: CloudTtsAudioJob[]): void {
    const prefetchWindow = this.cloudTtsPrefetchWindow();
    while (this.readGeneration === generation && this.active &&
      jobs.length < prefetchWindow && this.chunkIndex < this.chunks.length) {
      const index = this.chunkIndex;
      const chunk = this.chunks[this.chunkIndex++];
      const normalized = this.normalizeChunkForSpeechWithMap(chunk.text);
      const speakText = normalized.text;
      if (!speakText) continue;
      const promise = this.cloudReader.synthesize(voiceId, speakText, this.getTtsSpeed())
        .then((audio: CloudTtsAudio): CloudTtsAudioResult => {
          if (this.readGeneration !== generation || !this.active) {
            return { error: new Error('在线音色合成已停止') };
          }
          return { audio };
        })
        .catch((error: Error): CloudTtsAudioResult => ({ error }));
      jobs.push({ index, chunk, text: speakText,
        sourceToSpeechOffsets: normalized.sourceToSpeechOffsets, promise });
    }
  }

  private cloudTtsPrefetchWindow(): number {
    try {
      const handle = connection.getDefaultNetSync();
      const capabilities = connection.getNetCapabilitiesSync(handle);
      if ((capabilities.bearerTypes || []).includes(connection.NetBearType.BEARER_WIFI)) {
        return SystemTtsReader.CLOUD_TTS_WIFI_PREFETCH_WINDOW;
      }
    } catch (_) {
    }
    return SystemTtsReader.CLOUD_TTS_MOBILE_PREFETCH_WINDOW;
  }

  private buildCloudPlaybackCues(generation: number, job: CloudTtsAudioJob,
    audio: CloudTtsAudio): PcmPlaybackCue[] {
    const focusChunks = this.splitCloudFocusChunks(job.chunk);
    const durationMs = audio.sampleRate > 0 ?
      audio.pcm.byteLength * 1000 / (audio.sampleRate * 2) : 0;
    const cues: PcmPlaybackCue[] = [];
    let lastFrame = -1;
    for (let focusIndex = 0; focusIndex < focusChunks.length; focusIndex++) {
      const focusChunk = focusChunks[focusIndex];
      const sourceOffset = Math.max(0, focusChunk.start - job.chunk.start);
      const speechOffset = this.cloudSpeechOffset(job.chunk.text, job.text, sourceOffset,
        job.sourceToSpeechOffsets);
      const startTime = focusIndex === 0 ? 0 :
        this.cloudTimingAtOffset(audio.timings, speechOffset, durationMs, job.text.length);
      const frameOffset = Math.max(0, Math.round(startTime * audio.sampleRate / 1000));
      if (frameOffset === lastFrame) {
        continue;
      }
      const capturedChunk = focusChunk;
      cues.push({
        frameOffset,
        callback: () => {
          if (this.readGeneration !== generation || !this.active) {
            return;
          }
          if (this.onChunkStart) {
            this.onChunkStart(capturedChunk, job.index);
          }
          this.notifyAudioStarted();
        }
      });
      lastFrame = frameOffset;
    }
    if (cues.length === 0) {
      cues.push({
        frameOffset: 0,
        callback: () => {
          if (this.readGeneration !== generation || !this.active) {
            return;
          }
          if (this.onChunkStart) {
            this.onChunkStart(job.chunk, job.index);
          }
          this.notifyAudioStarted();
        }
      });
    }
    console.info(`[TTS] cloud timeline queued: mode=${audio.timingMode},` +
      `timings=${audio.timings.length},focus=${cues.length},bytes=${audio.pcm.byteLength}`);
    return cues;
  }

  private cloudSpeechOffset(sourceText: string, speechText: string, sourceOffset: number,
    sourceToSpeechOffsets: number[] = []): number {
    if (sourceToSpeechOffsets.length === sourceText.length + 1) {
      const safeOffset = Math.max(0, Math.min(sourceText.length, Math.round(sourceOffset)));
      return Math.max(0, Math.min(speechText.length, sourceToSpeechOffsets[safeOffset] || 0));
    }
    if (!sourceText || sourceText === speechText) {
      return Math.max(0, Math.min(speechText.length, sourceOffset));
    }
    const safeOffset = Math.max(0, Math.min(sourceText.length, sourceOffset));
    const prefix = this.normalizeChunkForSpeech(sourceText.substring(0, safeOffset));
    if (prefix && speechText.startsWith(prefix)) {
      return Math.min(speechText.length, prefix.length);
    }
    return Math.round(safeOffset * speechText.length / Math.max(1, sourceText.length));
  }

  private cloudTimingAtOffset(timings: CloudTtsTiming[], offset: number,
    durationMs: number, textLength: number): number {
    if (!timings || timings.length === 0) {
      return durationMs * Math.max(0, Math.min(textLength, offset)) / Math.max(1, textLength);
    }
    for (let index = 0; index < timings.length; index++) {
      const timing = timings[index];
      if (offset < timing.startOffset) {
        return timing.startTime;
      }
      if (offset >= timing.startOffset && offset < timing.endOffset) {
        if (timing.endOffset <= timing.startOffset || timing.endTime <= timing.startTime) {
          return timing.startTime;
        }
        const progress = (offset - timing.startOffset) / (timing.endOffset - timing.startOffset);
        return timing.startTime + (timing.endTime - timing.startTime) * progress;
      }
    }
    const lastTiming = timings[timings.length - 1];
    if (textLength > lastTiming.endOffset && durationMs > lastTiming.endTime) {
      const progress = (offset - lastTiming.endOffset) /
        Math.max(1, textLength - lastTiming.endOffset);
      return Math.max(0, Math.min(durationMs,
        lastTiming.endTime + (durationMs - lastTiming.endTime) * progress));
    }
    return Math.max(0, Math.min(durationMs, lastTiming.endTime));
  }

  private speakCustomNext(generation: number, voice: HttpTTS): void {
    this.playCustomQueue(generation, voice).catch((error: Error) => {
      this.handleCustomVoiceError(generation, voice, error);
    });
  }

  private async playCustomQueue(generation: number, voice: HttpTTS): Promise<void> {
    const jobs: CustomTtsAudioJob[] = [];
    this.fillCustomAudioJobs(generation, voice, jobs);
    while (this.readGeneration === generation && this.active) {
      if (jobs.length === 0) {
        await this.httpReader.drain();
        if (this.readGeneration === generation && this.active) {
          this.finish(true);
        }
        return;
      }
      const job = jobs.shift() as CustomTtsAudioJob;
      this.currentRequestId = this.createRequestId();
      this.currentSpeakStartedAt = Date.now();
      this.currentSpeakMinDuration = this.estimateSpeakDuration(job.text);
      this.completionPending = false;
      this.currentFocusChunk = job.chunk;
      this.currentFocusChunkIndex = job.index;
      this.currentFocusDuration = this.currentSpeakMinDuration;
      this.currentFocusQueued = false;
      this.currentFocusAudioReceived = false;
      this.currentFocusAudioWritten = false;
      const result = await job.promise;
      if (this.readGeneration !== generation || !this.active) {
        return;
      }
      if (result.error || !result.audio) {
        throw result.error || new Error('自定义音色合成失败');
      }
      this.fillCustomAudioJobs(generation, voice, jobs);
      this.currentFocusAudioReceived = true;
      await this.httpReader.writeAudioRecovering(voice, job.text, this.getTtsSpeed(), result.audio,
        (durationMs: number): void => {
          if (durationMs > 0) this.currentFocusDuration = durationMs;
          this.emitCurrentCustomChunkFocus(generation);
        });
      if (this.readGeneration !== generation || !this.active) {
        return;
      }
      // Every built-in writer reports playback start. Keep a guarded fallback for third-party containers whose
      // platform player omits duration/start metadata, without publishing the same focus twice.
      this.emitCurrentCustomChunkFocus(generation);
      this.currentFocusAudioWritten = true;
      this.notifyAudioStarted();
      this.currentRequestId = '';
      this.currentSpeakStartedAt = 0;
      this.currentSpeakMinDuration = 0;
      this.completionPending = false;
      this.currentFocusChunk = null;
      this.currentFocusChunkIndex = -1;
      this.currentFocusDuration = 0;
      this.currentFocusQueued = false;
      this.currentFocusAudioReceived = false;
      this.currentFocusAudioWritten = false;
    }
  }

  private fillCustomAudioJobs(generation: number, voice: HttpTTS, jobs: CustomTtsAudioJob[]): void {
    const prefetchWindow = this.customTtsPrefetchWindow(voice);
    while (this.readGeneration === generation && this.active &&
      jobs.length < prefetchWindow && this.chunkIndex < this.chunks.length) {
      const index = this.chunkIndex;
      const chunk = this.chunks[this.chunkIndex++];
      const speakText = this.normalizeChunkForSpeech(chunk.text);
      if (!speakText) {
        continue;
      }
      jobs.push(this.createCustomAudioJob(generation, voice, chunk, index, speakText));
    }
  }

  private customTtsPrefetchWindow(voice: HttpTTS): number {
    const raw = (voice.concurrentRate || '').trim();
    if (!raw || raw === '0') {
      return SystemTtsReader.CUSTOM_TTS_PREFETCH_WINDOW;
    }
    if (/^\d+$/.test(raw)) {
      // A plain Android concurrentRate value is a serialized-access wait, not
      // a parallelism count. Do not create requests which can only sit behind
      // the active request and outlive a stop/restart operation.
      return 1;
    }
    const windowMatch = raw.match(/^(\d+)\s*\/\s*(\d+)$/);
    if (!windowMatch) {
      return 1;
    }
    return Math.max(1, Math.min(SystemTtsReader.CUSTOM_TTS_PREFETCH_WINDOW,
      Number(windowMatch[1]) || 1));
  }

  private createCustomAudioJob(generation: number, voice: HttpTTS, chunk: TtsChunk, index: number,
    speakText: string): CustomTtsAudioJob {
    const promise = this.httpReader.synthesize(voice, speakText, this.getTtsSpeed())
      .then((audio: HttpTtsAudio): CustomTtsAudioResult => {
        if (this.readGeneration !== generation || !this.active) {
          return { error: new Error('自定义音色合成已停止') };
        }
        return { audio };
      })
      .catch((error: Error): CustomTtsAudioResult => {
        return { error };
      });
    return {
      index,
      chunk,
      text: speakText,
      promise
    };
  }

  private handleCustomVoiceError(generation: number, voice: HttpTTS, error: Error): void {
    if (this.readGeneration !== generation || !this.active) {
      return;
    }
    this.currentRequestId = '';
    this.active = false;
    const message = `自定义音色朗读失败：${voice.name || '未命名音色'} ${this.formatError(error)}`;
    console.error('[TTS] custom voice failed:', message);
    if (this.onError) this.onError(message);
  }

  private retryWithoutPcmData(generation: number): boolean {
    if (this.ttsPcmPlayType !== 0 || this.currentFocusChunkIndex < 0) {
      return false;
    }
    console.warn('[TTS] no pcm data with playType=0, fallback to playType=1');
    this.resetSystemPcmPipeline();
    this.pcmPlayer.stop();
    this.ttsPcmPlayType = 1;
    this.currentRequestId = '';
    this.currentSpeakStartedAt = 0;
    this.currentSpeakMinDuration = 0;
    this.completionPending = false;
    this.currentFocusChunk = null;
    this.currentFocusDuration = 0;
    this.currentFocusQueued = false;
    this.currentFocusAudioReceived = false;
    this.currentFocusAudioWritten = false;
    this.currentAudioWritePromise = Promise.resolve();
    this.currentFocusRetryCount = 0;
    this.chunkIndex = Math.max(0, Math.min(this.currentFocusChunkIndex, this.chunks.length));
    this.currentFocusChunkIndex = -1;
    this.clearSpeakWatchdog();
    this.speakNext(generation);
    return true;
  }

  private notifyAudioStarted(): void {
    if (this.audioStarted) {
      return;
    }
    this.audioStarted = true;
    if (this.onAudioStart) {
      this.onAudioStart();
    }
  }

  private completeSystemPcmChunk(generation: number, requestId: string): void {
    if (this.readGeneration !== generation || !this.active || requestId !== this.currentRequestId ||
      !this.currentFocusChunk || this.currentFocusChunkIndex < 0) {
      return;
    }
    this.completionPending = true;
    this.clearSpeakWatchdog();
    const pcm = this.mergeSystemPcmBuffers(
      this.systemCurrentPcmBuffers, this.systemCurrentPcmSequences, this.systemCurrentPcmBytes);
    const normalizedPcm = this.normalizeSystemPcm(
      pcm, this.currentAudioSampleBit, this.currentAudioChannel, this.currentAudioType);
    const trimmedPcm = this.trimSystemPcmSilence(
      normalizedPcm, this.currentAudioSampleRate, this.currentFocusChunk.text);
    const playbackPcm = this.fadeSystemPcmEdges(trimmedPcm, this.currentAudioSampleRate);
    if (playbackPcm.byteLength === 0) {
      this.completionPending = false;
      this.currentFocusAudioReceived = false;
      if (this.retryWithoutPcmData(generation)) {
        return;
      }
      this.failSystemPcmPlayback('系统音色返回的PCM音频为空');
      return;
    }
    this.systemReadySegments.push({
      index: this.currentFocusChunkIndex,
      chunk: this.currentFocusChunk,
      pcm: playbackPcm,
      sampleRate: this.currentAudioSampleRate
    });
    this.systemBufferedSegmentCount++;
    console.info(`[TTS] system pcm segment ready: index=${this.currentFocusChunkIndex},` +
      `bytes=${playbackPcm.byteLength},buffered=${this.systemBufferedSegmentCount}`);
    this.resetCurrentSystemRequestState();
    this.pumpSystemPcmPlayback(generation);
    this.continueSystemPcmSynthesis(generation);
  }

  private pumpSystemPcmPlayback(generation: number): void {
    if (this.readGeneration !== generation || !this.active || this.ttsPcmPlayType !== 0) {
      return;
    }
    if (!this.systemPlaybackStarted) {
      if (!this.systemSynthesisFinished &&
        this.systemReadySegments.length < SystemTtsReader.SYSTEM_TTS_START_BUFFER_SEGMENTS) {
        return;
      }
      this.systemPlaybackStarted = true;
      console.info(`[TTS] system pcm playback starts: buffered=${this.systemReadySegments.length}`);
    }
    while (this.systemReadySegments.length > 0) {
      const segment = this.systemReadySegments.shift() as SystemPcmSegment;
      const writePromise = this.pcmPlayer.writeSegment(segment.pcm, segment.sampleRate, () => {
        if (this.readGeneration !== generation || !this.active || this.ttsPcmPlayType !== 0) {
          return;
        }
        if (this.onChunkStart) {
          this.onChunkStart(segment.chunk, segment.index);
        }
        this.notifyAudioStarted();
      });
      writePromise.then(() => {
        if (this.readGeneration !== generation || !this.active || this.ttsPcmPlayType !== 0) {
          return;
        }
        // Audio production must never depend on a UI-focus callback. The PCM
        // writeData completion provides backpressure independently of UI focus.
        this.systemBufferedSegmentCount = Math.max(0, this.systemBufferedSegmentCount - 1);
        this.continueSystemPcmSynthesis(generation);
      }).catch((error: Error) => {
        console.warn('[TTS] system pcm segment write failed:', error);
        if (this.readGeneration === generation && this.active && this.ttsPcmPlayType === 0) {
          // Never consume a synthesized paragraph whose PCM failed to enter the renderer. Advancing here makes
          // the chapter appear complete and is most noticeable when the failed segment is on the last page.
          this.failSystemPcmPlayback(`系统音频写入失败：${this.formatError(error as Object)}`);
        }
      });
      this.systemLastWritePromise = writePromise;
    }
    if (this.systemSynthesisFinished && !this.systemDrainScheduled) {
      this.systemDrainScheduled = true;
      this.finishSystemPcmPlayback(generation);
    }
  }

  private async finishSystemPcmPlayback(generation: number): Promise<void> {
    try {
      await this.systemLastWritePromise;
      await this.pcmPlayer.drain();
    } catch (error) {
      console.warn('[TTS] drain system pcm playback failed:', error);
      if (this.readGeneration === generation && this.active) {
        this.failSystemPcmPlayback(`系统音频播放被中断：${this.formatError(error as Object)}`);
      }
      return;
    }
    if (this.readGeneration !== generation || !this.active || this.ttsPcmPlayType !== 0) {
      return;
    }
    this.finish(true);
  }

  private continueSystemPcmSynthesis(generation: number): void {
    if (this.readGeneration !== generation || !this.active || this.ttsPcmPlayType !== 0 ||
      this.currentRequestId) {
      return;
    }
    if (this.chunkIndex >= this.chunks.length) {
      this.systemSynthesisFinished = true;
      this.pumpSystemPcmPlayback(generation);
      return;
    }
    if (this.systemBufferedSegmentCount >= SystemTtsReader.SYSTEM_TTS_MAX_BUFFERED_SEGMENTS) {
      return;
    }
    this.speakNext(generation);
  }

  private resetCurrentSystemRequestState(): void {
    this.currentRequestId = '';
    this.currentSpeakStartedAt = 0;
    this.currentSpeakMinDuration = 0;
    this.completionPending = false;
    this.currentFocusChunk = null;
    this.currentFocusChunkIndex = -1;
    this.currentFocusDuration = 0;
    this.currentFocusQueued = false;
    this.currentFocusAudioReceived = false;
    this.currentFocusAudioWritten = false;
    this.currentAudioWritePromise = Promise.resolve();
    this.systemCurrentPcmBuffers = [];
    this.systemCurrentPcmSequences = [];
    this.systemCurrentPcmBytes = 0;
  }

  private resetSystemPcmPipeline(): void {
    this.systemCurrentPcmBuffers = [];
    this.systemCurrentPcmSequences = [];
    this.systemCurrentPcmBytes = 0;
    this.systemReadySegments = [];
    this.systemPlaybackStarted = false;
    this.systemSynthesisFinished = false;
    this.systemDrainScheduled = false;
    this.systemLastWritePromise = Promise.resolve();
    this.systemBufferedSegmentCount = 0;
  }

  private mergeSystemPcmBuffers(buffers: ArrayBuffer[], sequences: number[],
    totalBytes: number): ArrayBuffer {
    if (buffers.length === 0 || totalBytes <= 0) {
      return new ArrayBuffer(0);
    }
    if (buffers.length === 1) {
      return buffers[0].slice(0);
    }
    const order: number[] = [];
    for (let index = 0; index < buffers.length; index++) {
      order.push(index);
    }
    order.sort((left: number, right: number) =>
      (sequences[left] || left + 1) - (sequences[right] || right + 1));
    const merged = new ArrayBuffer(totalBytes);
    const output = new Uint8Array(merged);
    let offset = 0;
    for (const index of order) {
      const buffer = buffers[index];
      const bytes = new Uint8Array(buffer);
      output.set(bytes, offset);
      offset += bytes.length;
    }
    return merged;
  }

  private normalizeSystemPcm(pcm: ArrayBuffer, sampleBit: number,
    channelCount: number, audioType: string): ArrayBuffer {
    if (!pcm || pcm.byteLength === 0) {
      return new ArrayBuffer(0);
    }
    const type = (audioType || 'pcm').toLowerCase();
    if (type !== 'pcm') {
      console.warn(`[TTS] unexpected system audio type: ${audioType}`);
    }
    const safeBits = Math.round(sampleBit || 16);
    const safeChannels = Math.max(1, Math.round(channelCount || 1));
    if (safeBits !== 16) {
      console.warn(`[TTS] unexpected system pcm sample bits: ${safeBits}`);
      return pcm.byteLength % 2 === 0 ? pcm : pcm.slice(0, pcm.byteLength - 1);
    }
    const safeByteLength = pcm.byteLength - pcm.byteLength % (2 * safeChannels);
    if (safeByteLength <= 0) {
      return new ArrayBuffer(0);
    }
    if (safeChannels === 1) {
      return safeByteLength === pcm.byteLength ? pcm : pcm.slice(0, safeByteLength);
    }
    const input = new DataView(pcm, 0, safeByteLength);
    const frameCount = Math.floor(safeByteLength / (2 * safeChannels));
    const output = new ArrayBuffer(frameCount * 2);
    const outputView = new DataView(output);
    for (let frame = 0; frame < frameCount; frame++) {
      let total = 0;
      for (let channel = 0; channel < safeChannels; channel++) {
        total += input.getInt16((frame * safeChannels + channel) * 2, true);
      }
      outputView.setInt16(frame * 2, Math.max(-32768,
        Math.min(32767, Math.round(total / safeChannels))), true);
    }
    console.info(`[TTS] system pcm downmixed: channels=${safeChannels},frames=${frameCount}`);
    return output;
  }

  private fadeSystemPcmEdges(pcm: ArrayBuffer, sampleRate: number): ArrayBuffer {
    const frameCount = Math.floor(pcm.byteLength / 2);
    const fadeFrames = Math.min(Math.round(Math.max(8000, sampleRate || 16000) * 0.006),
      Math.floor(frameCount / 4));
    if (fadeFrames <= 1) {
      return pcm;
    }
    const result = pcm.slice(0);
    const view = new DataView(result);
    for (let index = 0; index < fadeFrames; index++) {
      const gain = index / fadeFrames;
      const first = view.getInt16(index * 2, true);
      const lastIndex = frameCount - index - 1;
      const last = view.getInt16(lastIndex * 2, true);
      view.setInt16(index * 2, Math.round(first * gain), true);
      view.setInt16(lastIndex * 2, Math.round(last * gain), true);
    }
    return result;
  }

  private trimSystemPcmSilence(pcm: ArrayBuffer, sampleRate: number, text: string): ArrayBuffer {
    const frameCount = Math.floor(pcm.byteLength / 2);
    const safeSampleRate = Math.max(8000, Math.round(sampleRate || 16000));
    if (frameCount < safeSampleRate / 4) {
      return pcm;
    }
    const view = new DataView(pcm);
    const threshold = 96;
    let firstActive = 0;
    while (firstActive < frameCount && Math.abs(view.getInt16(firstActive * 2, true)) <= threshold) {
      firstActive++;
    }
    let lastActive = frameCount - 1;
    while (lastActive > firstActive && Math.abs(view.getInt16(lastActive * 2, true)) <= threshold) {
      lastActive--;
    }
    if (firstActive >= frameCount || lastActive <= firstActive) {
      return pcm;
    }
    const leadingKeep = Math.round(safeSampleRate * 0.06);
    const trailingKeep = Math.round(safeSampleRate * this.systemTrailingPauseSeconds(text));
    const startFrame = firstActive > Math.round(safeSampleRate * 0.18) ?
      Math.max(0, firstActive - leadingKeep) : 0;
    const endFrame = frameCount - lastActive > trailingKeep + Math.round(safeSampleRate * 0.12) ?
      Math.min(frameCount, lastActive + trailingKeep + 1) : frameCount;
    if (startFrame <= 0 && endFrame >= frameCount) {
      return pcm;
    }
    return pcm.slice(startFrame * 2, endFrame * 2);
  }

  private systemTrailingPauseSeconds(text: string): number {
    const value = (text || '').trim();
    let lastIndex = Math.max(0, value.length - 1);
    while (lastIndex > 0 && this.isClosingPunctuation(value.charAt(lastIndex))) {
      lastIndex--;
    }
    const last = value.charAt(lastIndex);
    if (last === '。' || last === '！' || last === '？' || last === '!' || last === '?') {
      return 0.26;
    }
    if (last === '；' || last === ';' || last === '：' || last === ':') {
      return 0.18;
    }
    if (last === '，' || last === ',' || last === '、') {
      return 0.12;
    }
    return 0.08;
  }

  private failSystemPcmPlayback(message: string): void {
    this.currentRequestId = '';
    this.active = false;
    this.clearSpeakWatchdog();
    console.error('[TTS] system pcm playback failed:', message);
    if (this.onError) {
      this.onError(message);
    }
  }

  private completeCurrentChunk(generation: number, requestId: string): void {
    if (this.readGeneration !== generation || !this.active || this.completionPending) {
      return;
    }
    if (this.ttsPcmPlayType === 0 && this.currentFocusAudioReceived) {
      this.completeSystemPcmChunk(generation, requestId);
      return;
    }
    this.completionPending = true;
    const writePromise = this.currentAudioWritePromise;
    writePromise
      .then(async () => {
        if (this.readGeneration !== generation || !this.active || requestId !== this.currentRequestId) {
          return;
        }
        this.clearSpeakWatchdog();
        if (this.chunkIndex >= this.chunks.length) {
          try {
            await this.pcmPlayer.drain();
          } catch (error) {
            console.warn('[TTS] drain pcm audio failed:', error);
            if (this.readGeneration === generation && this.active) {
              this.failSystemPcmPlayback(`系统音频播放被中断：${this.formatError(error as Object)}`);
            }
            return;
          }
          this.finishCurrentRead(generation, 0);
          return;
        }
        this.currentRequestId = '';
        this.currentSpeakStartedAt = 0;
        this.currentSpeakMinDuration = 0;
        this.completionPending = false;
        this.currentFocusChunk = null;
        this.currentFocusChunkIndex = -1;
        this.currentFocusDuration = 0;
        this.currentFocusQueued = false;
        this.currentFocusAudioReceived = false;
        this.currentFocusAudioWritten = false;
        this.currentAudioWritePromise = Promise.resolve();
        this.speakNext(generation);
      })
      .catch((error: Error) => {
        if (this.readGeneration !== generation || !this.active || requestId !== this.currentRequestId) {
          return;
        }
        console.warn('[TTS] wait current pcm write failed:', error);
        // The old fallback called speakNext(), silently dropping this chunk. Stop at the failed chunk so resume
        // starts from the same visible paragraph instead of jumping several lines or entering the next chapter.
        this.failSystemPcmPlayback(`系统音频写入失败：${this.formatError(error as Object)}`);
      });
  }

  private emitCurrentCustomChunkFocus(generation: number): void {
    if (this.readGeneration !== generation || !this.active || this.currentFocusQueued ||
      !this.currentFocusChunk || this.currentFocusChunkIndex < 0) {
      return;
    }
    this.currentFocusQueued = true;
    if (this.onChunkStart) {
      this.onChunkStart(this.currentFocusChunk, this.currentFocusChunkIndex);
    }
    this.notifyAudioStarted();
  }

  private emitCurrentSystemChunkFocus(generation: number): void {
    if (this.readGeneration !== generation || !this.active || this.currentFocusQueued ||
      !this.currentFocusChunk || this.currentFocusChunkIndex < 0) {
      return;
    }
    this.currentFocusQueued = true;
    if (this.onChunkStart) {
      this.onChunkStart(this.currentFocusChunk, this.currentFocusChunkIndex);
    }
  }

  private armSpeakWatchdog(generation: number, chunkIndex: number): void {
    this.clearSpeakWatchdog();
    this.speakWatchdogId = setTimeout(() => {
      this.recoverStalledSpeak(generation, chunkIndex);
    }, this.speakWatchdogTimeoutMs());
  }

  private speakWatchdogTimeoutMs(): number {
    if (this.ttsPcmPlayType === 1 && this.currentSpeakMinDuration > 0) {
      // Direct playback may legitimately spend more than 12 seconds on a long
      // chunk. Firing the old fixed watchdog interrupted that audible chunk and
      // replayed/reordered it.
      return Math.max(12000,
        Math.round(this.currentSpeakMinDuration + SystemTtsReader.DIRECT_PLAY_COMPLETION_GRACE_MS));
    }
    return 12000;
  }

  private clearSpeakWatchdog(): void {
    if (this.speakWatchdogId < 0) {
      return;
    }
    clearTimeout(this.speakWatchdogId);
    this.speakWatchdogId = -1;
  }

  private async recoverStalledSpeak(generation: number, chunkIndex: number): Promise<void> {
    if (this.readGeneration !== generation || !this.active || this.currentFocusAudioWritten ||
      this.completionPending || this.currentFocusChunkIndex !== chunkIndex) {
      return;
    }
    if (this.ttsPcmPlayType === 1 && this.currentFocusQueued && this.currentRequestId) {
      // onStart proved that direct playback began. If only onComplete is lost,
      // completing after the estimated duration is safer than stopping the
      // engine and replaying the same chunk.
      const requestId = this.currentRequestId;
      console.warn(`[TTS] direct-play completion recovered after timeout: request=${requestId},` +
        `chunk=${chunkIndex}`);
      this.completeCurrentChunk(generation, requestId);
      return;
    }
    if (this.retryWithoutPcmData(generation)) {
      return;
    }
    if (this.currentFocusRetryCount >= 2) {
      this.currentRequestId = '';
      this.active = false;
      const message = `系统朗读无音频回调：${this.currentVoiceLabel()}`;
      console.warn('[TTS] speak watchdog exhausted:', message);
      if (this.onError) {
        this.onError(message);
      }
      return;
    }
    this.currentFocusRetryCount++;
    console.warn(`[TTS] speak watchdog retry ${this.currentFocusRetryCount}: ${this.currentVoiceLabel()}`);
    try {
      this.currentRequestId = '';
      this.currentSpeakStartedAt = 0;
      this.currentSpeakMinDuration = 0;
      this.completionPending = false;
      this.currentFocusQueued = false;
      this.currentFocusAudioReceived = false;
      this.currentFocusAudioWritten = false;
      this.currentAudioWritePromise = Promise.resolve();
      this.chunkIndex = Math.max(0, Math.min(chunkIndex, this.chunks.length));
      this.resetSystemPcmPipeline();
      this.pcmPlayer.stop();
      if (this.engine) {
        try {
          this.suppressEngineStopEvent = true;
          this.engine.shutdown();
        } catch (_) {
        } finally {
          setTimeout(() => {
            this.suppressEngineStopEvent = false;
          }, 500);
        }
        this.engine = null;
      }
      const engine = await this.ensureEngine();
      if (this.readGeneration !== generation || !this.active) {
        return;
      }
      this.bindEngineListener(generation, engine);
      this.speakNext(generation);
    } catch (error) {
      this.currentRequestId = '';
      this.active = false;
      const message = `系统朗读恢复失败：${this.currentVoiceLabel()} ${this.formatError(error)}`;
      console.error('[TTS] speak watchdog recover failed:', message);
      if (this.onError) {
        this.onError(message);
      }
    }
  }

  private finishCurrentRead(generation: number, waitMs: number): void {
    setTimeout(() => {
      if (this.readGeneration !== generation || !this.active) {
        return;
      }
      this.finish(true);
    }, waitMs);
  }

  private splitCloudFocusChunks(chunk: TtsChunk): TtsChunk[] {
    const sentenceChunks = this.splitText(
      chunk.text, SystemTtsReader.CLOUD_TTS_FOCUS_CHUNK_LENGTH);
    const result: TtsChunk[] = [];
    for (const sentenceChunk of sentenceChunks) {
      const absoluteStart = chunk.start + sentenceChunk.start;
      const absoluteEnd = chunk.start + sentenceChunk.end;
      let partStart = absoluteStart;
      for (const breakOffset of this.optionFocusBreakOffsets) {
        if (breakOffset <= partStart) {
          continue;
        }
        if (breakOffset >= absoluteEnd) {
          break;
        }
        this.appendFocusChunk(result, chunk, partStart, breakOffset);
        partStart = breakOffset;
      }
      this.appendFocusChunk(result, chunk, partStart, absoluteEnd);
    }
    return result.length > 0 ? result : [chunk];
  }

  private appendFocusChunk(result: TtsChunk[], sourceChunk: TtsChunk, start: number, end: number): void {
    let safeStart = Math.max(sourceChunk.start, Math.min(start, sourceChunk.end));
    let safeEnd = Math.max(safeStart, Math.min(end, sourceChunk.end));
    while (safeStart < safeEnd &&
      this.isTrimChar(sourceChunk.text.charAt(safeStart - sourceChunk.start))) {
      safeStart++;
    }
    while (safeEnd > safeStart &&
      this.isTrimChar(sourceChunk.text.charAt(safeEnd - sourceChunk.start - 1))) {
      safeEnd--;
    }
    if (safeEnd <= safeStart) {
      return;
    }
    result.push({
      text: sourceChunk.text.substring(safeStart - sourceChunk.start, safeEnd - sourceChunk.start),
      start: safeStart,
      end: safeEnd
    });
  }

  private normalizeFocusBreakOffsets(offsets: number[] | undefined, textLength: number): number[] {
    if (!offsets || offsets.length === 0 || textLength <= 0) {
      return [];
    }
    const candidates: number[] = [];
    for (const offset of offsets) {
      const value = Math.round(offset);
      if (!Number.isFinite(value) || value <= 0 || value >= textLength) {
        continue;
      }
      candidates.push(value);
    }
    candidates.sort((left: number, right: number) => left - right);
    const result: number[] = [];
    for (const value of candidates) {
      if (result.length === 0 || result[result.length - 1] !== value) {
        result.push(value);
      }
    }
    return result;
  }

  private sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve) => {
      setTimeout(resolve, ms);
    });
  }

  private normalizeText(text: string): string {
    return this.sanitizeStructuralSpeechArtifacts(
      this.replaceUnsafeSpeechCharacters((text || '').replace(/\r\n/g, '\n')));
  }

  private sanitizeStructuralSpeechArtifacts(text: string): string {
    if (!text) return '';
    return text.split('\n').map((line: string): string => {
      const trimmed = line.trim();
      if (!trimmed) return line;
      // Treat x/× dimensions and two-or-more-digit multiplication layouts as structural.
      // A standalone expression such as "3*4" must remain available to the math normalizer.
      const dimensionOnly = /^\d{1,5}\s*[x×]\s*\d{1,5}$/.test(trimmed) ||
        /^\d{2,5}\s*\*\s*\d{2,5}$/.test(trimmed);
      const signatures = [
        /\bjava\.(?:ajax|base64Decode|put|get)\s*\(/i,
        /\.match\s*\(\s*\//i,
        /\bsrc\s*=/i,
        /<\/?js>|@js:/i,
        /\b(?:JSON\.parse|document\.querySelector)\s*\(/i,
        /=>|\bfunction\s*\(/i
      ];
      let signatureCount = 0;
      for (const signature of signatures) {
        if (signature.test(trimmed)) signatureCount++;
      }
      // Sources commonly use long runs of *, #, &, dashes or similar symbols as scene separators.
      // Do not cap the run length: a rendered separator often contains dozens of characters and the
      // old 16-character limit let exactly those lines through to be spoken one symbol at a time.
      const decorativePunctuationOnly = /^[\s=;:{}()[\].,+*#&＊＃＆_~～·•—–|｜\/\\\-!！?？%％^＾@＠<>《》]+$/.test(trimmed);
      let sanitized = line;
      if (!dimensionOnly && !decorativePunctuationOnly && signatureCount < 1) {
        // Remove only long repeated decorative runs embedded in otherwise readable text.
        // Single punctuation and short runs remain meaningful (e.g. "啊！！").
        const hasUrl = /\b(?:https?|ftp):\/\//i.test(trimmed);
        if (!hasUrl) {
          sanitized = sanitized.replace(/([*#&=+＋~～·•—–|｜_\/\\\-!！?？%％^＾@＠:：<>《》])\1{2,}/g,
            (match: string): string => ' '.repeat(match.length));
        }
        return sanitized;
      }
      // Replace one-for-one so chunk/focus offsets continue to map to the original reader document.
      return ' '.repeat(line.length);
    }).join('\n');
  }

  private normalizeChunkForSpeech(text: string): string {
    return this.normalizeMathNotationForSpeech(this.replaceUnsafeSpeechCharacters(text || ''))
      .replace(/\r\n/g, '\n')
      .replace(/\s*\n+\s*/g, '。')
      .replace(/[ \t]{2,}/g, ' ')
      .replace(/，{2,}/g, '，')
      .replace(/。{2,}/g, '。')
      .replace(/([！!?！？])\1+/g, '$1')
      .replace(/(?:\.{3,}|…{2,})/g, '…')
      .replace(/^[，。！？；;：:,.!?…]+/, '')
      .replace(/[，,]+$/, '')
      .trim();
  }

  /**
   * Merge chunks whose speech payload contains only punctuation/whitespace. A splitter is
   * intentionally punctuation-aware, so a trailing ellipsis can otherwise become a separate
   * audio request. Keeping it attached to the previous chunk avoids empty-audio callbacks while
   * preserving the source range used by reader highlighting and chapter-end confirmation.
   */
  private coalescePunctuationOnlyChunks(chunks: TtsChunk[], source: string): TtsChunk[] {
    if (!chunks || chunks.length === 0) return [];
    const result: TtsChunk[] = [];
    for (const chunk of chunks) {
      const speech = this.normalizeChunkForSpeech(chunk.text);
      if (speech && !this.isSpeechOnlyPunctuation(speech)) {
        result.push({ text: chunk.text, start: chunk.start, end: chunk.end });
        continue;
      }
      if (result.length === 0) {
        // Leading decorative punctuation has no useful audible content. Drop it rather than
        // creating an audio request that may never emit a completion callback.
        continue;
      }
      const previous = result[result.length - 1];
      const mergedEnd = Math.max(previous.end, chunk.end);
      previous.end = mergedEnd;
      previous.text = source.substring(previous.start, mergedEnd);
    }
    return result;
  }

  /** Return true when a normalized chunk has no letters/numbers/words, only punctuation. */
  private isSpeechOnlyPunctuation(text: string): boolean {
    const value = (text || '').trim();
    if (!value) return true;
    for (let index = 0; index < value.length; index++) {
      const code = value.charCodeAt(index);
      if (this.isSpeechPunctuationCode(code)) continue;
      return false;
    }
    return true;
  }

  private isSpeechPunctuationCode(code: number): boolean {
    // ASCII punctuation and controls.
    if (code <= 0x2f || (code >= 0x3a && code <= 0x40) ||
      (code >= 0x5b && code <= 0x60) || (code >= 0x7b && code <= 0x7e)) return true;
    // Unicode punctuation blocks commonly found in book sources. Keep letters/digits outside
    // these blocks as readable content (including CJK, kana, Cyrillic and emoji).
    if ((code >= 0x2000 && code <= 0x206f) ||
      (code >= 0x2e00 && code <= 0x2e7f) ||
      (code >= 0x3000 && code <= 0x303f) ||
      (code >= 0xff00 && code <= 0xff65)) return true;
    return false;
  }

  /**
   * Normalize once and retain a source-code-unit to speech-code-unit map. The map is deliberately
   * calculated from prefixes so every replacement (math, whitespace, punctuation and trimming)
   * follows the exact same rules as the text sent to the service.
   */
  private normalizeChunkForSpeechWithMap(text: string): NormalizedSpeechText {
    const source = text || '';
    const offsets: number[] = [];
    for (let index = 0; index <= source.length; index++) {
      offsets.push(this.normalizeChunkForSpeech(source.substring(0, index)).length);
    }
    return {
      text: this.normalizeChunkForSpeech(source),
      sourceToSpeechOffsets: offsets
    };
  }

  /**
   * Make common mathematical notation explicit for Chinese TTS. This is applied only to
   * the text sent to the synthesizer; TtsChunk offsets still refer to the original text so
   * reader highlighting and resume positions remain unchanged.
   */
  private normalizeMathNotationForSpeech(text: string): string {
    if (!text) return '';
    let result = text;
    const english = (this.getTtsLanguage() || '').toLowerCase().startsWith('en');
    if (english) {
      result = result.replace(/(\d+(?:[.．]\d+)?)\s*[%％]/g,
        (_match: string, value: string): string => `${value} percent`);
      result = result.replace(/(\d+)\s*[.．]\s*(\d+)/g,
        (_match: string, left: string, right: string): string => `${left} point ${right}`);
      result = result.replace(/(\d+)\s*[\/／]\s*(\d+)/g,
        (match: string, numerator: string, denominator: string): string => {
          return (numerator.length > 1 && numerator.charAt(0) === '0') ||
            (denominator.length > 1 && denominator.charAt(0) === '0') ? match :
            `${numerator} over ${denominator}`;
        });
      result = result.replace(/(\d+)\s*[×*]\s*(\d+)/g,
        (_match: string, left: string, right: string): string => `${left} times ${right}`);
      result = result.replace(/(\d+)\s*[÷]\s*(\d+)/g,
        (_match: string, left: string, right: string): string => `${left} divided by ${right}`);
      result = result.replace(/(\d+)\s*=\s*(\d+)/g,
        (_match: string, left: string, right: string): string => `${left} equals ${right}`);
      return result;
    }
    result = result.replace(/(\d+(?:[.．]\d+)?)\s*[%％]/g,
      (_match: string, value: string): string => `百分之${value}`);
    result = result.replace(/(\d+)\s*[.．]\s*(\d+)/g,
      (_match: string, left: string, right: string): string => `${left}点${right}`);
    result = result.replace(/(\d+)\s*[\/／]\s*(\d+)/g,
      (match: string, numerator: string, denominator: string): string => {
        // Keep zero-padded date-like forms such as 03/04 unchanged. For ordinary proper
        // fractions (3/4), Chinese reads the denominator first: “四分之三”.
        if ((numerator.length > 1 && numerator.charAt(0) === '0') ||
          (denominator.length > 1 && denominator.charAt(0) === '0')) return match;
        const numeratorValue = Number(numerator);
        const denominatorValue = Number(denominator);
        if (!Number.isFinite(numeratorValue) || !Number.isFinite(denominatorValue) ||
          numeratorValue <= 0 || denominatorValue <= numeratorValue || denominatorValue > 999) {
          return match;
        }
        return `${denominator}分之${numerator}`;
      });
    result = result.replace(/(\d+)\s*[×*]\s*(\d+)/g,
      (_match: string, left: string, right: string): string => `${left}乘以${right}`);
    result = result.replace(/(\d+)\s*[÷]\s*(\d+)/g,
      (_match: string, left: string, right: string): string => `${left}除以${right}`);
    result = result.replace(/(\d+)\s*=\s*(\d+)/g,
      (_match: string, left: string, right: string): string => `${left}等于${right}`);
    return result;
  }

  /**
   * Replace invisible controls and damaged UTF-16 units one-for-one. Keeping the code-unit
   * length stable is important because chunk offsets are also used to focus the reader page.
   */
  private replaceUnsafeSpeechCharacters(text: string): string {
    if (!text) return '';
    let result = '';
    for (let index = 0; index < text.length; index++) {
      const code = text.charCodeAt(index);
      if (code >= 0xD800 && code <= 0xDBFF) {
        const next = index + 1 < text.length ? text.charCodeAt(index + 1) : 0;
        if (next >= 0xDC00 && next <= 0xDFFF) {
          result += text.charAt(index) + text.charAt(index + 1);
          index++;
        } else {
          result += ' ';
        }
        continue;
      }
      if (code >= 0xDC00 && code <= 0xDFFF) {
        result += ' ';
        continue;
      }
      const unsafeControl = code <= 0x0008 || (code >= 0x000B && code <= 0x000C) ||
        (code >= 0x000E && code <= 0x001F) || (code >= 0x007F && code <= 0x009F);
      const invisibleFormatting = (code >= 0x200B && code <= 0x200F) ||
        (code >= 0x202A && code <= 0x202E) || (code >= 0x2060 && code <= 0x206F) ||
        code === 0xFEFF || code === 0xFFFD;
      result += unsafeControl || invisibleFormatting ? ' ' : text.charAt(index);
    }
    return result;
  }

  private estimateSpeakDuration(text: string): number {
    const value = text || '';
    const readableChars = value.replace(/\s/g, '').length;
    const punctuationMatches = value.match(/[，。！？；;,.!?、]/g);
    const punctuationCount = punctuationMatches ? punctuationMatches.length : 0;
    const speed = Math.max(0.5, Math.min(2, this.getTtsSpeed()));
    // System chunks can contain up to 60 characters. At 0.5x speed a punctuation-heavy
    // chunk can legitimately exceed the previous 18-second ceiling, which made the
    // lost-onComplete fallback advance while direct playback was still audible.
    return Math.max(450, Math.min(SystemTtsReader.MAX_ESTIMATED_CHUNK_DURATION_MS,
      (readableChars * 210 + punctuationCount * 120) / speed));
  }

  private getTtsPerson(): number {
    const value = AppStorage.get<number>('ttsPerson');
    const optionValue = this.optionPerson;
    return Math.max(0, optionValue === null ? (value === undefined ? 0 : Math.round(value)) : Math.round(optionValue));
  }

  private getTtsSpeed(): number {
    const value = AppStorage.get<number>('ttsSpeed');
    const optionValue = this.optionSpeed;
    return Math.max(0.5, Math.min(2, optionValue === null ? (value === undefined ? 1 : value) : optionValue));
  }

  private getTtsOnline(): number {
    const value = AppStorage.get<number>('ttsOnline');
    const optionValue = this.optionOnline;
    return (optionValue === null ? value : optionValue) === SystemTtsReader.LEGACY_ONLINE_MODE ?
      SystemTtsReader.LEGACY_ONLINE_MODE : SystemTtsReader.OFFLINE_MODE;
  }

  private getTtsStyle(): string {
    const value = AppStorage.get<string>('ttsStyle');
    return this.optionStyle === null ? (value || '') : this.optionStyle;
  }

  private getTtsLanguage(): string {
    const value = AppStorage.get<string>('ttsLanguage');
    const language = this.optionLanguage === null ? (value || '') : this.optionLanguage;
    return language || 'zh-CN';
  }

  private currentVoiceLabel(): string {
    const customVoice = this.getCurrentCustomVoice();
    if (customVoice) {
      return `自定义音色 ${customVoice.name || customVoice.id}`;
    }
    const mode = this.getTtsOnline() === SystemTtsReader.LEGACY_ONLINE_MODE ? '在线' : '离线';
    const style = this.getTtsStyle();
    return `person=${this.getTtsPerson()} ${mode} language=${this.getTtsLanguage()}${style ? ` style=${style}` : ''}`;
  }

  private getCurrentCustomVoice(): HttpTTS | null {
    const selectedId = (AppStorage.get<string>('ttsCustomVoiceId') || '').trim();
    if (!selectedId) {
      return null;
    }
    const voices = SystemTtsReader.parseCustomVoices(AppStorage.get<string>('ttsCustomVoices') || '');
    return voices.find((voice: HttpTTS) => String(voice.id) === selectedId && voice.enabled !== false) || null;
  }

  static parseCustomVoices(raw: string): HttpTTS[] {
    const value = (raw || '').trim();
    if (!value) {
      return [];
    }
    try {
      const parsed = JSON.parse(value) as Object;
      const items = Array.isArray(parsed) ? parsed as Object[] : [parsed];
      const result: HttpTTS[] = [];
      for (const item of items) {
        const voice = SystemTtsReader.parseCustomVoice(item as Record<string, Object>);
        if (voice.name && voice.url) {
          result.push(voice);
        }
      }
      return result;
    } catch (_) {
      return [];
    }
  }

  private static async listLegacyEngineVoices(online: number): Promise<TtsVoiceOption[]> {
    let engine: textToSpeech.TextToSpeechEngine | null = null;
    try {
      engine = await SystemTtsReader.createEngineWithMode(0, online, '', 'zh-CN');
      const voices = await engine.listVoices({
        requestId: `legacy_engine_voices_${online}_${Date.now()}`,
        online: online
      });
      console.info(`[TTS] legacy engine listVoices online=${online}: ` +
        `${SystemTtsReader.voiceInfosSummary(voices)}`);
      return SystemTtsReader.parseVoices(voices, online);
    } catch (error) {
      console.warn(`[TTS] legacy engine listVoices failed online=${online}: ` +
        `${SystemTtsReader.formatStaticError(error as Object)}`);
      return [];
    } finally {
      if (engine) {
        try {
          engine.shutdown();
        } catch (_) {
        }
      }
    }
  }

  private static applyVoiceFeatureAvailability(voices: TtsVoiceOption[]): TtsVoiceOption[] {
    if (SystemTtsReader.supportsVoiceDownload()) {
      return voices;
    }
    for (const voice of voices) {
      voice.downloadable = false;
      if (voice.id === 0) {
        voice.available = true;
      }
    }
    return voices;
  }

  static serializeCustomVoices(voices: HttpTTS[]): string {
    return JSON.stringify(voices);
  }

  private static parseCustomVoice(item: Record<string, Object>): HttpTTS {
    const voice = new HttpTTS();
    voice.id = SystemTtsReader.parseCustomVoiceNumber(item['id'], Date.now());
    voice.name = SystemTtsReader.parseCustomVoiceString(item['name']);
    voice.url = SystemTtsReader.parseCustomVoiceString(item['url']);
    voice.contentType = SystemTtsReader.parseCustomVoiceString(item['contentType']);
    voice.concurrentRate = SystemTtsReader.parseCustomVoiceString(item['concurrentRate']);
    voice.loginUrl = SystemTtsReader.parseCustomVoiceString(item['loginUrl']);
    voice.loginUi = SystemTtsReader.parseCustomVoiceString(item['loginUi']);
    voice.loginCheckJs = SystemTtsReader.parseCustomVoiceString(item['loginCheckJs']);
    voice.header = SystemTtsReader.parseCustomVoiceString(item['header']);
    voice.jsLib = SystemTtsReader.parseCustomVoiceString(item['jsLib']);
    voice.jsEngine = SystemTtsReader.parseCustomVoiceString(item['jsEngine']) || voice.jsLib;
    const enabledCookieJar = item['enabledCookieJar'];
    voice.enabledCookieJar = enabledCookieJar === true || String(enabledCookieJar) === 'true';
    voice.customOrder = SystemTtsReader.parseCustomVoiceNumber(item['customOrder'], 0);
    voice.lastUpdateTime = SystemTtsReader.parseCustomVoiceNumber(item['lastUpdateTime'], 0);
    const enabled = item['enabled'];
    voice.enabled = enabled === undefined || enabled === null ? true : enabled !== false && String(enabled) !== 'false';
    return voice;
  }

  private static parseCustomVoiceString(value: Object | undefined): string {
    return value === undefined || value === null ? '' : String(value);
  }

  private static parseCustomVoiceNumber(value: Object | undefined, fallback: number): number {
    if (typeof value === 'number') {
      return Math.round(value);
    }
    const parsed = Number(value === undefined || value === null ? '' : String(value));
    return Number.isNaN(parsed) ? fallback : Math.round(parsed);
  }

  private static alternateOnlineMode(online: number): number {
    return online === SystemTtsReader.LEGACY_ONLINE_MODE ?
      SystemTtsReader.OFFLINE_MODE : SystemTtsReader.LEGACY_ONLINE_MODE;
  }

  private formatError(error: Object | undefined): string {
    if (!error) return '';
    const anyError = error as Record<string, Object>;
    const code = anyError['code'] === undefined ? '' : `(${String(anyError['code'])})`;
    const message = anyError['message'] === undefined ? '' : String(anyError['message']);
    const text = `${code}${message}`.trim();
    return text || JSON.stringify(error);
  }

  private static createEngineExtraParams(style?: string, language: string = 'zh-CN'): Record<string, Object> {
    const extraParam: Record<string, Object> = {};
    if (style) {
      extraParam['style'] = style as Object;
    }
    extraParam['locate'] = SystemTtsReader.localeToLocate(language) as Object;
    extraParam['name'] = 'LegadoReaderTts' as Object;
    extraParam['isBackStage'] = true as Object;
    return extraParam;
  }

  private static createEngineExtraParamVariants(style: string, language: string): Array<Record<string, Object> | undefined> {
    const variants: Array<Record<string, Object> | undefined> = [];
    variants.push(SystemTtsReader.createEngineExtraParams(style, language));
    if (style) {
      variants.push(SystemTtsReader.createEngineExtraParams('', language));
    }
    const nameOnly: Record<string, Object> = {};
    nameOnly['name'] = 'LegadoReaderTts' as Object;
    nameOnly['isBackStage'] = true as Object;
    variants.push(nameOnly);
    variants.push(undefined);
    return variants;
  }

  private static localeToLocate(language: string): string {
    const value = (language || 'zh-CN').trim();
    if (value.length === 0) {
      return 'CN';
    }
    if (value.toLowerCase().startsWith('en')) {
      return 'US';
    }
    return 'CN';
  }

  private static languageVariants(language: string): string[] {
    const value = (language || 'zh-CN').trim() || 'zh-CN';
    const variants: string[] = [value];
    if (value.includes('-')) {
      variants.push(value.replace(/-/g, '_'));
    }
    if (value.includes('_')) {
      variants.push(value.replace(/_/g, '-'));
    }
    const lower = value.toLowerCase();
    if (lower.startsWith('en')) {
      variants.push('en-US');
      variants.push('en_US');
      variants.push('en');
    } else if (lower.startsWith('zh')) {
      variants.push('zh-CN');
      variants.push('zh_CN');
      variants.push('zh');
    }
    const result: string[] = [];
    for (const item of variants) {
      if (item && !result.includes(item)) {
        result.push(item);
      }
    }
    return result;
  }

  private static parseVoices(voices: Array<textToSpeech.VoiceInfo>, online: number): TtsVoiceOption[] {
    const options: TtsVoiceOption[] = [];
    for (const raw of voices) {
      const id = SystemTtsReader.parseVoiceId(raw);
      const style = raw.style || '';
      const language = SystemTtsReader.parseVoiceLanguage(raw);
      if (id < 0 || options.some((voice: TtsVoiceOption) => voice.id === id &&
        voice.online === online && voice.style === style && voice.language === language)) {
        continue;
      }
      const option = new TtsVoiceOption();
      option.id = id;
      option.name = SystemTtsReader.knownVoiceName(id, language) || SystemTtsReader.parseVoiceName(raw, id);
      option.online = online;
      option.status = raw.status || '';
      option.systemStatus = raw.status || '';
      option.style = style;
      option.language = language;
      option.downloadLanguage = raw.language || '';
      option.gender = raw.gender || SystemTtsReader.knownVoiceGender(id, language);
      option.downloadable = SystemTtsReader.isDownloadableStatus(raw.status || '') &&
        !SystemTtsReader.isInstalledStatus(raw.status || '');
      option.available = !option.downloadable;
      options.push(option);
    }
    options.sort((a: TtsVoiceOption, b: TtsVoiceOption) => a.online - b.online ||
      a.language.localeCompare(b.language) || a.id - b.id || a.name.localeCompare(b.name));
    return options;
  }

  private static dedupeVoices(voices: TtsVoiceOption[]): TtsVoiceOption[] {
    const options: TtsVoiceOption[] = [];
    for (const voice of voices) {
      const voiceKey = SystemTtsReader.voiceDedupeKey(voice);
      const existing = options.find((item: TtsVoiceOption) => SystemTtsReader.voiceDedupeKey(item) === voiceKey);
      if (existing) {
        SystemTtsReader.mergeVoiceMetadata(existing, voice);
      } else {
        options.push(voice);
      }
    }
    options.sort((a: TtsVoiceOption, b: TtsVoiceOption) => a.online - b.online || a.id - b.id ||
      a.language.localeCompare(b.language) || a.style.localeCompare(b.style) || a.name.localeCompare(b.name));
    return options;
  }

  private static voiceDedupeKey(voice: TtsVoiceOption): string {
    const language = SystemTtsReader.normalizeVoiceLanguage(voice.language || 'zh-CN', voice.id);
    const knownName = SystemTtsReader.knownVoiceName(voice.id, language);
    const style = knownName || voice.id === 0 ? '' : (voice.style || '');
    return `${voice.id}_${voice.online}_${language}_${style}`;
  }

  private static parseVoiceId(item: textToSpeech.VoiceInfo): number {
    if (typeof item.person === 'number') {
      return Math.round(item.person);
    }
    return -1;
  }

  private static parseVoiceName(item: textToSpeech.VoiceInfo, id: number): string {
    if (item.description && item.description.trim()) {
      return item.description.trim();
    }
    const tags: string[] = [];
    if (item.style && item.style.trim()) {
      tags.push(item.style.trim());
    }
    if (item.gender && item.gender.trim()) {
      tags.push(item.gender.trim());
    }
    return id === 0 ? '默认音色' : (tags.length > 0 ? `系统音色 ${id} · ${tags.join('/')}` : `系统音色 ${id}`);
  }

  private static parseVoiceLanguage(item: textToSpeech.VoiceInfo): string {
    if (item.language && item.language.trim()) {
      return SystemTtsReader.normalizeVoiceLanguage(item.language, item.person);
    }
    if (item.person === 8) {
      return 'en-US';
    }
    if (item.person === 13 || item.person === 21) {
      return 'zh-CN';
    }
    const text = `${item.description || ''} ${item.style || ''}`.toLowerCase();
    if (text.includes('english') || text.includes('en-us') || text.includes('us voice')) {
      return 'en-US';
    }
    return 'zh-CN';
  }

  private static normalizeVoiceLanguage(language: string, person: number): string {
    if (person === 8) {
      return 'en-US';
    }
    if (person === 13 || person === 21) {
      return 'zh-CN';
    }
    const value = (language || 'zh-CN').trim().replace(/_/g, '-');
    const lower = value.toLowerCase();
    if (lower === 'zh' || lower === 'zh-cn' || lower.startsWith('zh-hans')) {
      return 'zh-CN';
    }
    if (lower === 'en' || lower === 'en-us') {
      return 'en-US';
    }
    return value || 'zh-CN';
  }

  private static defaultVoices(): TtsVoiceOption[] {
      const option = new TtsVoiceOption();
      option.id = 0;
      option.name = '默认音色';
      option.online = SystemTtsReader.OFFLINE_MODE;
      option.status = 'default';
      option.language = 'zh-CN';
      option.available = true;
      return [option];
  }

  private static knownVoiceOptions(): TtsVoiceOption[] {
    const options: TtsVoiceOption[] = [];
    options.push(SystemTtsReader.createKnownVoiceOption(0, '默认音色', 'zh-CN'));
    options.push(SystemTtsReader.createKnownVoiceOption(13, '聆小珊', 'zh-CN'));
    options.push(SystemTtsReader.createKnownVoiceOption(21, '凌飞哲', 'zh-CN'));
    options.push(SystemTtsReader.createKnownVoiceOption(8, 'US Laura', 'en-US'));
    return options;
  }

  private static createKnownVoiceOption(id: number, name: string, language: string): TtsVoiceOption {
    const option = new TtsVoiceOption();
    option.id = id;
    option.name = name;
    option.online = SystemTtsReader.OFFLINE_MODE;
    option.status = 'known';
    option.language = language;
    option.gender = SystemTtsReader.knownVoiceGender(id, language);
    option.available = false;
    option.downloadable = id !== 0;
    return option;
  }

  private static mergeVoiceMetadata(target: TtsVoiceOption, source: TtsVoiceOption): void {
    if (!target.style && source.style) {
      target.style = source.style;
    }
    target.language = SystemTtsReader.normalizeVoiceLanguage(target.language || source.language || 'zh-CN', target.id);
    if (!target.downloadLanguage && source.downloadLanguage) {
      target.downloadLanguage = source.downloadLanguage;
    }
    if (!target.systemStatus && source.systemStatus) {
      target.systemStatus = source.systemStatus;
    }
    if ((!target.status || target.status === 'known') && source.status) {
      target.status = source.status;
    }
    if (!target.gender && source.gender) {
      target.gender = source.gender;
    }
    target.available = target.available || source.available;
    target.downloadable = target.available ? false : (target.downloadable || source.downloadable ||
      SystemTtsReader.isDownloadableStatus(source.systemStatus || source.status));
  }

  private static isDownloadableStatus(status: string): boolean {
    const value = (status || '').toLowerCase();
    return value === 'ga' || value.includes('download') || value.includes('not_installed');
  }

  private static isInstalledStatus(status: string): boolean {
    const value = (status || '').toLowerCase();
    return value.includes('installed') || value.includes('downloaded') || value === 'local';
  }

  private static knownVoiceName(id: number, language: string): string {
    const lower = (language || '').toLowerCase();
    if (id === 0) {
      return '默认音色';
    }
    if (id === 13 && lower.startsWith('zh')) {
      return '聆小珊';
    }
    if (id === 21 && lower.startsWith('zh')) {
      return '凌飞哲';
    }
    if (id === 8 && lower.startsWith('en')) {
      return 'US Laura';
    }
    return '';
  }

  private static knownVoiceGender(id: number, language: string): string {
    const lower = (language || '').toLowerCase();
    if (id === 21 && lower.startsWith('zh')) {
      return 'male';
    }
    if ((id === 13 && lower.startsWith('zh')) || (id === 8 && lower.startsWith('en'))) {
      return 'female';
    }
    return '';
  }

  private static async createEngineWithMode(person: number, online: number, style: string,
    language: string = 'zh-CN'): Promise<textToSpeech.TextToSpeechEngine> {
    let lastError: Object | undefined = undefined;
    for (const lang of SystemTtsReader.languageVariants(language)) {
      for (const extraParams of SystemTtsReader.createEngineExtraParamVariants(style, lang)) {
        try {
          const params: textToSpeech.CreateEngineParams = {
            language: lang || 'zh-CN',
            person: person,
            online: online
          };
          if (extraParams !== undefined) {
            params.extraParams = extraParams;
          }
          return await textToSpeech.createEngine(params);
        } catch (error) {
          lastError = error as Object;
        }
      }
    }
    throw new Error(SystemTtsReader.formatStaticError(lastError) || 'createEngine failed');
  }

  private static formatStaticError(error: Object | undefined): string {
    if (!error) return '';
    const anyError = error as Record<string, Object>;
    const code = anyError['code'] === undefined ? '' : `(${String(anyError['code'])})`;
    const message = anyError['message'] === undefined ? '' : String(anyError['message']);
    const text = `${code}${message}`.trim();
    return text || JSON.stringify(error);
  }

  private splitSystemText(text: string, pageBreakOffsets: number[]): TtsChunk[] {
    const chunks: TtsChunk[] = [];
    const preferredLength = 42;
    const minimumLength = 16;
    const maximumLength = 60;
    let start = 0;
    while (start < text.length) {
      const limit = Math.min(text.length, start + maximumLength);
      const preferredEnd = Math.min(limit, start + preferredLength);
      let end = this.findLastCloudBreak(text, start + minimumLength, preferredEnd, true);
      if (end <= start && preferredEnd < limit) {
        end = this.findFirstCloudBreak(text, preferredEnd, limit, true);
      }
      if (end <= start) {
        end = this.findLastCloudBreak(text, start + minimumLength, preferredEnd, false);
      }
      if (end <= start && preferredEnd < limit) {
        end = this.findFirstCloudBreak(text, preferredEnd, limit, false);
      }
      if (end <= start) {
        end = limit;
      }
      end = this.extendCloudBreak(text, end, limit);
      this.appendAbsoluteTextChunk(chunks, text, start, end);
      start = end;
    }
    return this.splitSystemChunksAtPageBreaks(chunks, text, pageBreakOffsets);
  }

  private splitSystemChunksAtPageBreaks(chunks: TtsChunk[], text: string,
    pageBreakOffsets: number[]): TtsChunk[] {
    if (pageBreakOffsets.length === 0) {
      return chunks;
    }
    const result: TtsChunk[] = [];
    for (const chunk of chunks) {
      let partStart = chunk.start;
      for (const breakOffset of pageBreakOffsets) {
        if (breakOffset <= partStart) {
          continue;
        }
        if (breakOffset >= chunk.end) {
          break;
        }
        if (breakOffset - partStart < 6 || chunk.end - breakOffset < 6) {
          continue;
        }
        this.appendAbsoluteTextChunk(result, text, partStart, breakOffset);
        partStart = breakOffset;
      }
      this.appendAbsoluteTextChunk(result, text, partStart, chunk.end);
    }
    return result;
  }

  private appendAbsoluteTextChunk(result: TtsChunk[], text: string, start: number, end: number): void {
    let chunkStart = Math.max(0, Math.min(start, text.length));
    let chunkEnd = Math.max(chunkStart, Math.min(end, text.length));
    while (chunkStart < chunkEnd && this.isTrimChar(text.charAt(chunkStart))) {
      chunkStart++;
    }
    while (chunkEnd > chunkStart && this.isTrimChar(text.charAt(chunkEnd - 1))) {
      chunkEnd--;
    }
    if (chunkEnd <= chunkStart) {
      return;
    }
    result.push({
      text: text.substring(chunkStart, chunkEnd),
      start: chunkStart,
      end: chunkEnd
    });
  }

  private splitText(text: string, maxLength: number): TtsChunk[] {
    const chunks: TtsChunk[] = [];
    let start = 0;
    while (start < text.length) {
      let end = Math.min(text.length, start + maxLength);
      const sentence = this.findSentenceBreak(text, start, end, maxLength);
      if (sentence > start) {
        end = sentence;
      }
      let chunkStart = start;
      let chunkEnd = end;
      while (chunkStart < chunkEnd && this.isTrimChar(text.charAt(chunkStart))) {
        chunkStart++;
      }
      while (chunkEnd > chunkStart && this.isTrimChar(text.charAt(chunkEnd - 1))) {
        chunkEnd--;
      }
      const chunk = text.substring(chunkStart, chunkEnd);
      if (chunk) {
        chunks.push({
          text: chunk,
          start: chunkStart,
          end: chunkEnd
        });
      }
      start = end;
    }
    return chunks;
  }

  private splitCustomText(text: string, maxLength: number): TtsChunk[] {
    const chunks: TtsChunk[] = [];
    let rangeStart = 0;
    let cursor = 0;
    while (cursor < text.length) {
      if (text.charAt(cursor) !== ' ' && text.charAt(cursor) !== '\t') {
        cursor++;
        continue;
      }
      const gapStart = cursor;
      while (cursor < text.length && (text.charAt(cursor) === ' ' || text.charAt(cursor) === '\t')) {
        cursor++;
      }
      if (cursor - gapStart >= SystemTtsReader.CUSTOM_TTS_HIDDEN_GAP_LENGTH) {
        this.appendCustomTextRange(chunks, text, rangeStart, gapStart, maxLength);
        rangeStart = cursor;
      }
    }
    this.appendCustomTextRange(chunks, text, rangeStart, text.length, maxLength);
    return chunks;
  }

  private appendCustomTextRange(result: TtsChunk[], text: string, rangeStart: number,
    rangeEnd: number, maxLength: number): void {
    let start = Math.max(0, Math.min(rangeStart, text.length));
    const safeRangeEnd = Math.max(start, Math.min(rangeEnd, text.length));
    while (start < safeRangeEnd) {
      let end = Math.min(safeRangeEnd, start + maxLength);
      const sentence = this.findSentenceBreak(text, start, end, maxLength);
      if (sentence > start && sentence <= safeRangeEnd) {
        end = sentence;
      }
      this.appendAbsoluteTextChunk(result, text, start, end);
      start = end;
    }
  }

  private splitCloudText(text: string): TtsChunk[] {
    const chunks: TtsChunk[] = [];
    let start = 0;
    while (start < text.length) {
      const firstChunk = chunks.length === 0;
      const firstChunkLength = this.optionCloudVoiceTier === 'PREMIUM' ?
        SystemTtsReader.CLOUD_TTS_PREMIUM_FIRST_CHUNK_LENGTH :
        SystemTtsReader.CLOUD_TTS_STANDARD_FIRST_CHUNK_LENGTH;
      const preferredLength = firstChunk ? firstChunkLength : 200;
      const minimumStrongLength = firstChunk ? Math.ceil(firstChunkLength * 0.8) : 80;
      const minimumWeakLength = firstChunk ? Math.ceil(firstChunkLength * 0.8) : 140;
      const maximumLength = firstChunk ? firstChunkLength : 450;
      const limit = Math.min(text.length, start + maximumLength);
      const preferredEnd = Math.min(limit, start + preferredLength);
      let end = this.findLastCloudBreak(text, start + minimumStrongLength, preferredEnd, true);
      if (end <= start && preferredEnd < limit) {
        end = this.findFirstCloudBreak(text, preferredEnd, limit, true);
      }
      if (end <= start) {
        end = this.findLastCloudBreak(text, start + minimumWeakLength, limit, false);
      }
      if (end <= start) {
        end = limit;
      }
      end = this.extendCloudBreak(text, end, limit);
      let chunkStart = start;
      let chunkEnd = end;
      while (chunkStart < chunkEnd && this.isTrimChar(text.charAt(chunkStart))) {
        chunkStart++;
      }
      while (chunkEnd > chunkStart && this.isTrimChar(text.charAt(chunkEnd - 1))) {
        chunkEnd--;
      }
      const chunk = text.substring(chunkStart, chunkEnd);
      if (chunk) {
        chunks.push({
          text: chunk,
          start: chunkStart,
          end: chunkEnd
        });
      }
      start = end;
    }
    return chunks;
  }

  private findLastCloudBreak(text: string, from: number, to: number, strong: boolean): number {
    for (let index = Math.min(text.length, to) - 1; index >= from; index--) {
      if (this.isCloudBreak(text.charAt(index), strong) && !this.isNumericDecimalPoint(text, index)) {
        return index + 1;
      }
    }
    return -1;
  }

  private findFirstCloudBreak(text: string, from: number, to: number, strong: boolean): number {
    for (let index = Math.max(0, from); index < Math.min(text.length, to); index++) {
      if (this.isCloudBreak(text.charAt(index), strong) && !this.isNumericDecimalPoint(text, index)) {
        return index + 1;
      }
    }
    return -1;
  }

  private isCloudBreak(value: string, strong: boolean): boolean {
    if (strong) {
      return value === '。' || value === '！' || value === '？' ||
        value === '；' || value === ';' || value === '!' || value === '?' ||
        value === '.' || value === '…' || value === '\n';
    }
    return value === '，' || value === ',' || value === '、' ||
      value === '：' || value === ':' || value === '—' || value === '–';
  }

  private extendCloudBreak(text: string, end: number, limit: number): number {
    let result = end;
    while (result < Math.min(text.length, limit) && this.isClosingPunctuation(text.charAt(result))) {
      result++;
    }
    return result;
  }

  private isClosingPunctuation(value: string): boolean {
    return value === '”' || value === '’' || value === '"' || value === '\'' ||
      value === '）' || value === ')' || value === '】' || value === ']' ||
      value === '》' || value === '〉' || value === '」' || value === '』';
  }

  private findSentenceBreak(text: string, start: number, limit: number, maxLength: number): number {
    const minBreak = start + Math.min(18, Math.floor(maxLength * 0.35));
    for (let i = start; i < limit; i++) {
      if (i >= minBreak && this.isSentenceEnd(text.charAt(i)) && !this.isNumericDecimalPoint(text, i)) {
        return i + 1;
      }
      if (i >= minBreak && text.charAt(i) === '\n') {
        return i + 1;
      }
    }
    if (limit < text.length) {
      return limit;
    }
    return text.length;
  }

  private isSentenceEnd(value: string): boolean {
    return value === '。' || value === '！' || value === '？' ||
      value === '；' || value === '，' || value === ',' || value === ';' || value === '、' ||
      value === '!' || value === '?' ||
      value === '.' || value === '…' || value === '：' || value === ':';
  }

  private isNumericDecimalPoint(text: string, index: number): boolean {
    if (index <= 0 || index >= text.length - 1 || text.charAt(index) !== '.') return false;
    const previous = text.charCodeAt(index - 1);
    const next = text.charCodeAt(index + 1);
    return previous >= 48 && previous <= 57 && next >= 48 && next <= 57;
  }

  private isTrimChar(value: string): boolean {
    return value === ' ' || value === '\t' || value === '\n' || value === '\r' || value === '\u3000';
  }

  private createRequestId(): string {
    const seed = `${Date.now()}_${Math.floor(Math.random() * 1000000)}`;
    return `tts_${seed}`;
  }
}
