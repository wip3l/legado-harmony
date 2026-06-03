import { textToSpeech } from '@kit.CoreSpeechKit';

export interface TtsChunk {
  text: string;
  start: number;
  end: number;
}

export interface TtsReadOptions {
  onFinished?: () => void;
  onError?: (message: string) => void;
  onChunkStart?: (chunk: TtsChunk, index: number) => void;
}

export class SystemTtsReader {
  private engine: textToSpeech.TextToSpeechEngine | null = null;
  private chunks: TtsChunk[] = [];
  private chunkIndex: number = 0;
  private active: boolean = false;
  private onFinished?: () => void;
  private onError?: (message: string) => void;
  private onChunkStart?: (chunk: TtsChunk, index: number) => void;
  private currentRequestId: string = '';
  private readGeneration: number = 0;
  private currentSpeakStartedAt: number = 0;
  private currentSpeakMinDuration: number = 0;
  private completionPending: boolean = false;

  async start(text: string, options?: TtsReadOptions): Promise<void> {
    const cleanText = this.normalizeText(text);
    if (!cleanText) {
      throw new Error('朗读内容为空');
    }
    this.stop();
    const generation = ++this.readGeneration;
    this.onFinished = options?.onFinished;
    this.onError = options?.onError;
    this.onChunkStart = options?.onChunkStart;
    this.chunks = this.splitText(cleanText, 64);
    this.chunkIndex = 0;
    this.active = true;
    const engine = await this.ensureEngine();
    if (!this.active || this.readGeneration !== generation) {
      return;
    }
    engine.setListener({
      onStart: (_utteranceId: string, _response: textToSpeech.StartResponse) => {
      },
      onComplete: (_utteranceId: string, _response: textToSpeech.CompleteResponse) => {
        if (this.readGeneration !== generation || !this.active || !this.currentRequestId) {
          return;
        }
        this.completeCurrentChunk(generation);
      },
      onStop: () => {
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
        const message = errorMessage || `系统朗读失败(${errorCode})`;
        if (this.onError) this.onError(message);
      },
      onData: (_utteranceId: string, _audio: ArrayBuffer, _response: textToSpeech.SynthesisResponse) => {
      }
    });
    this.speakNext(generation);
  }

  stop(): void {
    this.readGeneration++;
    this.active = false;
    this.chunks = [];
    this.chunkIndex = 0;
    this.onChunkStart = undefined;
    this.currentRequestId = '';
    this.currentSpeakStartedAt = 0;
    this.currentSpeakMinDuration = 0;
    this.completionPending = false;
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
    this.engine = null;
  }

  isSpeaking(): boolean {
    return this.active;
  }

  private async ensureEngine(): Promise<textToSpeech.TextToSpeechEngine> {
    if (this.engine) return this.engine;
    const extraParam: Record<string, Object> = {};
    extraParam['style'] = 'interaction-broadcast' as Object;
    extraParam['locate'] = 'CN' as Object;
    extraParam['name'] = 'LegadoReaderTts' as Object;
    try {
      this.engine = await textToSpeech.createEngine({
        language: 'zh-CN',
        person: 0,
        online: 1,
        extraParams: extraParam
      });
    } catch (error) {
      this.engine = await textToSpeech.createEngine({
        language: 'zh-CN',
        person: 0,
        online: 0,
        extraParams: extraParam
      });
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
    if (this.onChunkStart) {
      this.onChunkStart(chunk, index);
    }
    const extraParams: Record<string, Object> = {};
    extraParams['queueMode'] = 0 as Object;
    extraParams['speed'] = 1 as Object;
    extraParams['volume'] = 2 as Object;
    extraParams['pitch'] = 1 as Object;
    extraParams['languageContext'] = 'zh-CN' as Object;
    extraParams['audioType'] = 'pcm' as Object;
    extraParams['soundChannel'] = 1 as Object;
    extraParams['playType'] = 1 as Object;
    try {
      const requestId = this.createRequestId();
      this.currentRequestId = requestId;
      this.currentSpeakStartedAt = Date.now();
      this.currentSpeakMinDuration = this.estimateSpeakDuration(speakText);
      this.completionPending = false;
      this.engine.speak(speakText, {
        requestId: requestId,
        extraParams: extraParams
      });
    } catch (error) {
      this.currentRequestId = '';
      this.currentSpeakStartedAt = 0;
      this.currentSpeakMinDuration = 0;
      this.completionPending = false;
      this.active = false;
      if (this.onError) this.onError('系统朗读失败');
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
    if (notify && this.onFinished) this.onFinished();
  }

  private completeCurrentChunk(generation: number): void {
    if (this.readGeneration !== generation || !this.active || this.completionPending) {
      return;
    }
    this.completionPending = true;
    const elapsed = Date.now() - this.currentSpeakStartedAt;
    const waitMs = Math.max(0, this.currentSpeakMinDuration - elapsed);
    setTimeout(() => {
      if (this.readGeneration !== generation || !this.active) {
        return;
      }
      this.currentRequestId = '';
      this.currentSpeakStartedAt = 0;
      this.currentSpeakMinDuration = 0;
      this.completionPending = false;
      this.speakNext(generation);
    }, waitMs);
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
    return Math.max(700, Math.min(18000, readableChars * 210 + punctuationCount * 120));
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
