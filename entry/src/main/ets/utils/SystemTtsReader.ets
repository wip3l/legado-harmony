import { textToSpeech } from '@kit.CoreSpeechKit';
import { TtsPcmAudioPlayer } from './TtsPcmAudioPlayer';

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
}

export interface TtsVoiceDownloadCallbacks {
  onStart?: (message: string) => void;
  onProgress?: (progress: string) => void;
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
  private static readonly LEGACY_ONLINE_MODE: number = 0;
  private static readonly OFFLINE_MODE: number = 1;
  private engine: textToSpeech.TextToSpeechEngine | null = null;
  private pcmPlayer: TtsPcmAudioPlayer = new TtsPcmAudioPlayer();
  private chunks: TtsChunk[] = [];
  private chunkIndex: number = 0;
  private active: boolean = false;
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
  private chunkFocusChain: Promise<void> = Promise.resolve();
  private currentFocusChunk: TtsChunk | null = null;
  private currentFocusChunkIndex: number = -1;
  private currentFocusDuration: number = 0;
  private currentFocusQueued: boolean = false;
  private currentFocusAudioReceived: boolean = false;
  private currentFocusAudioWritten: boolean = false;
  private currentFocusRetryCount: number = 0;
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
      return parsed.length > 0 ? parsed : SystemTtsReader.defaultVoices();
    } catch (_) {
      return SystemTtsReader.dedupeVoices(SystemTtsReader.knownVoiceOptions());
    }
  }

  static async downloadVoice(voice: TtsVoiceOption, callbacks?: TtsVoiceDownloadCallbacks): Promise<void> {
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
    return this.pcmPlayer.debugState();
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
    const cleanText = this.normalizeText(text);
    if (!cleanText) {
      throw new Error('朗读内容为空');
    }
    if (this.active || this.currentRequestId || this.chunks.length > 0) {
      this.stop();
    } else {
      this.clearSpeakWatchdog();
    }
    const generation = ++this.readGeneration;
    this.onFinished = options?.onFinished;
    this.onError = options?.onError;
    this.onChunkStart = options?.onChunkStart;
    this.onAudioStart = options?.onAudioStart;
    this.audioStarted = false;
    this.ttsPcmPlayType = 0;
    this.chunkFocusChain = Promise.resolve();
    this.optionPerson = options?.person ?? null;
    this.optionOnline = options?.online ?? null;
    this.optionStyle = options?.style ?? null;
    this.optionLanguage = options?.language ?? null;
    this.optionSpeed = options?.speed ?? null;
    this.chunks = this.splitText(cleanText, 64);
    this.chunkIndex = 0;
    this.active = true;
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
    this.bindEngineListener(generation, engine);
    this.speakNext(generation);
  }

  private bindEngineListener(generation: number, engine: textToSpeech.TextToSpeechEngine): void {
    engine.setListener({
      onStart: (_utteranceId: string, response: textToSpeech.StartResponse) => {
        this.currentAudioSampleRate = response && response.sampleRate ? response.sampleRate : 16000;
        console.info(`[TTS] speak start: audioType=${response ? response.audioType || '' : ''},sampleRate=${this.currentAudioSampleRate},${this.pcmPlayer.debugState()}`);
      },
      onComplete: (_utteranceId: string, _response: textToSpeech.CompleteResponse) => {
        if (this.readGeneration !== generation || !this.active || !this.currentRequestId) {
          return;
        }
        if (!this.currentFocusAudioReceived) {
          console.info(`[TTS] speak complete without pcm data: ${this.pcmPlayer.debugState()}`);
          if (this.retryWithoutPcmData(generation)) {
            return;
          }
        }
        if (!this.currentFocusAudioReceived) {
          this.queueCurrentChunkFocusOnAudio(generation);
          this.clearSpeakWatchdog();
        } else if (this.currentFocusAudioWritten) {
          this.clearSpeakWatchdog();
        }
        this.completeCurrentChunk(generation);
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
      onError: (_utteranceId: string, errorCode: number, errorMessage: string) => {
        if (this.readGeneration !== generation || !this.active) {
          return;
        }
        this.currentRequestId = '';
        this.active = false;
        this.clearSpeakWatchdog();
        const message = `${errorMessage || `系统朗读失败(${errorCode})`}：${this.currentVoiceLabel()}`;
        console.error('[TTS] speak error:', message);
        if (this.onError) this.onError(message);
      },
      onData: (_utteranceId: string, audioData: ArrayBuffer, response: textToSpeech.SynthesisResponse) => {
        if (this.readGeneration !== generation || !this.active || !audioData || audioData.byteLength === 0) {
          return;
        }
        this.currentFocusAudioReceived = true;
        if (!this.currentFocusQueued && this.currentFocusChunk && this.currentFocusChunkIndex >= 0) {
          const focusChunk = this.currentFocusChunk;
          const focusIndex = this.currentFocusChunkIndex;
          const focusDuration = this.currentFocusDuration;
          this.currentFocusQueued = true;
          this.pcmPlayer.write(audioData, this.currentAudioSampleRate)
            .then(() => {
              this.clearSpeakWatchdog();
              this.currentFocusAudioWritten = true;
              this.notifyAudioStarted();
              this.queueChunkFocus(generation, focusChunk, focusIndex, focusDuration);
            })
            .catch((error: Error) => {
              console.warn(`[TTS] write synthesis data failed: sequence=${response ? response.sequence : -1}`, error);
            });
          return;
        }
        this.pcmPlayer.write(audioData, this.currentAudioSampleRate)
          .then(() => {
            this.clearSpeakWatchdog();
            this.currentFocusAudioWritten = true;
            this.notifyAudioStarted();
          })
          .catch((error: Error) => {
            console.warn(`[TTS] write synthesis data failed: sequence=${response ? response.sequence : -1}`, error);
          });
      }
    });
  }

  stop(): void {
    this.readGeneration++;
    this.active = false;
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
    this.ttsPcmPlayType = 0;
    this.clearSpeakWatchdog();
    this.chunkFocusChain = Promise.resolve();
    this.pcmPlayer.stop();
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
      this.finish(true);
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
    extraParams['soundChannel'] = 3 as Object;
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
      this.currentAudioSampleRate = 16000;
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
      const message = `系统朗读失败：${this.currentVoiceLabel()} ${this.formatError(error)}`;
      console.error('[TTS] speak throw:', message);
      if (this.onError) this.onError(message);
    }
  }

  private finish(notify: boolean): void {
    this.readGeneration++;
    this.active = false;
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
    this.currentFocusRetryCount = 0;
    this.clearSpeakWatchdog();
    this.chunkFocusChain = Promise.resolve();
    if (!notify) {
      this.pcmPlayer.stop();
    }
    this.audioStarted = false;
    if (notify && this.onFinished) this.onFinished();
  }

  private retryWithoutPcmData(generation: number): boolean {
    if (this.ttsPcmPlayType !== 0 || this.currentFocusChunkIndex < 0) {
      return false;
    }
    console.warn('[TTS] no pcm data with playType=0, fallback to playType=1');
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

  private completeCurrentChunk(generation: number): void {
    if (this.readGeneration !== generation || !this.active || this.completionPending) {
      return;
    }
    this.completionPending = true;
    const elapsed = Date.now() - this.currentSpeakStartedAt;
    const waitMs = Math.max(0, this.currentSpeakMinDuration - elapsed);
    if (this.chunkIndex < this.chunks.length) {
      this.currentRequestId = '';
      this.currentSpeakStartedAt = 0;
      this.currentSpeakMinDuration = 0;
      this.completionPending = false;
      this.clearSpeakWatchdog();
      this.speakNext(generation);
      return;
    }
    this.pcmPlayer.drain()
      .then(() => {
        this.finishCurrentRead(generation, 0);
      })
      .catch((error: Error) => {
        console.warn('[TTS] drain pcm audio failed:', error);
        this.finishCurrentRead(generation, waitMs);
      });
  }

  private queueCurrentChunkFocusOnAudio(generation: number): void {
    if (this.readGeneration !== generation || !this.active || this.currentFocusQueued ||
      !this.currentFocusChunk || this.currentFocusChunkIndex < 0) {
      return;
    }
    this.currentFocusQueued = true;
    this.queueChunkFocus(generation, this.currentFocusChunk, this.currentFocusChunkIndex, this.currentFocusDuration);
  }

  private armSpeakWatchdog(generation: number, chunkIndex: number): void {
    this.clearSpeakWatchdog();
    this.speakWatchdogId = setTimeout(() => {
      this.recoverStalledSpeak(generation, chunkIndex);
    }, 12000);
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
      this.chunkIndex = Math.max(0, Math.min(chunkIndex, this.chunks.length));
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

  private queueChunkFocus(generation: number, chunk: TtsChunk, index: number, duration: number): void {
    const waitMs = Math.max(120, duration);
    this.chunkFocusChain = this.chunkFocusChain
      .then(async () => {
        if (this.readGeneration !== generation || !this.active) {
          return;
        }
        if (this.onChunkStart) {
          this.onChunkStart(chunk, index);
        }
        await this.sleep(waitMs);
      })
      .catch((error: Error) => {
        console.warn('[TTS] update chunk focus failed:', error);
      });
  }

  private sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve) => {
      setTimeout(resolve, ms);
    });
  }

  private normalizeText(text: string): string {
    return (text || '')
      .replace(/\r\n/g, '\n');
  }

  private normalizeChunkForSpeech(text: string): string {
    return (text || '')
      .replace(/\r\n/g, '\n')
      .replace(/\s*\n+\s*/g, '，')
      .replace(/[ \t]{2,}/g, ' ')
      .replace(/，{2,}/g, '，')
      .replace(/^[，。！？；;,.!?]+/, '')
      .replace(/[，,]+$/, '')
      .trim();
  }

  private estimateSpeakDuration(text: string): number {
    const value = text || '';
    const readableChars = value.replace(/\s/g, '').length;
    const punctuationMatches = value.match(/[，。！？；;,.!?、]/g);
    const punctuationCount = punctuationMatches ? punctuationMatches.length : 0;
    const speed = Math.max(0.5, Math.min(2, this.getTtsSpeed()));
    return Math.max(450, Math.min(18000, (readableChars * 210 + punctuationCount * 120) / speed));
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
    const mode = this.getTtsOnline() === SystemTtsReader.LEGACY_ONLINE_MODE ? '在线' : '离线';
    const style = this.getTtsStyle();
    return `person=${this.getTtsPerson()} ${mode} language=${this.getTtsLanguage()}${style ? ` style=${style}` : ''}`;
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

  private findSentenceBreak(text: string, start: number, limit: number, maxLength: number): number {
    const minBreak = start + Math.min(18, Math.floor(maxLength * 0.35));
    for (let i = start; i < limit; i++) {
      if (i >= minBreak && this.isSentenceEnd(text.charAt(i))) {
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
      value === '.';
  }

  private isTrimChar(value: string): boolean {
    return value === ' ' || value === '\t' || value === '\n' || value === '\r';
  }

  private createRequestId(): string {
    const seed = `${Date.now()}_${Math.floor(Math.random() * 1000000)}`;
    return `tts_${seed}`;
  }
}
