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
  person?: number;
  online?: number;
  style?: string;
  language?: string;
  speed?: number;
}

export class TtsVoiceOption {
  id: number = 0;
  name: string = '默认音色';
  online: number = 0;
  status: string = '';
  style: string = '';
  language: string = 'zh-CN';
}

export class SystemTtsReader {
  private static readonly MAX_PROBE_PERSON: number = 20;
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
    let engine: textToSpeech.TextToSpeechEngine | null = null;
    try {
      engine = await SystemTtsReader.createEngineWithMode(0, 0, '');
    } catch (_) {
      try {
        engine = await SystemTtsReader.createEngineWithMode(0, 1, '');
      } catch (_) {
        return await SystemTtsReader.probeAvailableVoices();
      }
    }
    try {
      let voices: TtsVoiceOption[] = [];
      try {
        voices = voices.concat(SystemTtsReader.parseVoices(await engine.listVoices({
          requestId: `voices_online_${Date.now()}`,
          online: 0
        }), 0));
      } catch (_) {
      }
      try {
        voices = voices.concat(SystemTtsReader.parseVoices(await engine.listVoices({
          requestId: `voices_offline_${Date.now()}`,
          online: 1
        }), 1));
      } catch (_) {
      }
      const parsed = SystemTtsReader.dedupeVoices(voices);
      let verified = await SystemTtsReader.filterAvailableVoices(parsed);
      if (verified.filter((voice: TtsVoiceOption) => voice.online === 0).length <= 1) {
        verified = SystemTtsReader.dedupeVoices(verified.concat(await SystemTtsReader.probeAvailableVoices(0)));
      }
      return verified.length > 0 ? verified : await SystemTtsReader.probeAvailableVoices();
    } catch (_) {
      return await SystemTtsReader.probeAvailableVoices();
    } finally {
      try {
        engine.shutdown();
      } catch (_) {
      }
    }
  }

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
        const message = `${errorMessage || `系统朗读失败(${errorCode})`}：${this.currentVoiceLabel()}`;
        console.error('[TTS] speak error:', message);
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
    this.optionPerson = null;
    this.optionOnline = null;
    this.optionStyle = null;
    this.optionLanguage = null;
    this.optionSpeed = null;
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
      actualOnline = online === 0 ? 1 : 0;
      try {
        this.engine = await SystemTtsReader.createEngineWithMode(person, actualOnline, style, language);
      } catch (secondError) {
        lastError = secondError as Object;
        const fallbackPerson = 0;
        actualOnline = online;
        const fallbackStyle = '';
        try {
          this.engine = await SystemTtsReader.createEngineWithMode(fallbackPerson, actualOnline, fallbackStyle, language);
        } catch (thirdError) {
          lastError = thirdError as Object;
          actualOnline = online === 0 ? 1 : 0;
          try {
            this.engine = await SystemTtsReader.createEngineWithMode(fallbackPerson, actualOnline, fallbackStyle, language);
          } catch (fourthError) {
            lastError = fourthError as Object;
            throw new Error(SystemTtsReader.formatStaticError(lastError) || 'createEngine failed');
          }
        }
      }
    }
    this.enginePerson = person;
    this.engineOnline = online;
    this.engineStyle = style;
    this.engineLanguage = language;
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
    extraParams['speed'] = this.getTtsSpeed() as Object;
    extraParams['volume'] = 2 as Object;
    extraParams['pitch'] = 1 as Object;
    extraParams['languageContext'] = this.getTtsLanguage() as Object;
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
    return (optionValue === null ? value : optionValue) === 1 ? 1 : 0;
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
    const mode = this.getTtsOnline() === 0 ? '在线' : '离线';
    const style = this.getTtsStyle();
    return `person=${this.getTtsPerson()} ${mode} language=${this.getTtsLanguage()}${style ? ` style=${style}` : ''}`;
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
    variants.push(nameOnly);
    variants.push(undefined);
    return variants;
  }

  private static localeToLocate(language: string): string {
    const value = (language || 'zh-CN').trim();
    if (value.length === 0) {
      return 'CN';
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
      variants.push('zh-CN');
      variants.push('zh_CN');
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
        voice.online === online && voice.style === style && voice.language === language &&
        voice.name === SystemTtsReader.parseVoiceName(raw, id))) {
        continue;
      }
      const option = new TtsVoiceOption();
      option.id = id;
      option.name = SystemTtsReader.parseVoiceName(raw, id);
      option.online = online;
      option.status = raw.status || '';
      option.style = style;
      option.language = language;
      options.push(option);
    }
    options.sort((a: TtsVoiceOption, b: TtsVoiceOption) => a.online - b.online ||
      a.language.localeCompare(b.language) || a.id - b.id || a.name.localeCompare(b.name));
    return options;
  }

  private static dedupeVoices(voices: TtsVoiceOption[]): TtsVoiceOption[] {
    const options: TtsVoiceOption[] = [];
    for (const voice of voices) {
      if (!options.some((item: TtsVoiceOption) => item.id === voice.id &&
        item.online === voice.online && item.style === voice.style &&
        item.language === voice.language && item.name === voice.name)) {
        options.push(voice);
      }
    }
    options.sort((a: TtsVoiceOption, b: TtsVoiceOption) => a.online - b.online || a.id - b.id ||
      a.language.localeCompare(b.language) || a.style.localeCompare(b.style) || a.name.localeCompare(b.name));
    return options;
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
      return item.language.trim();
    }
    const text = `${item.description || ''} ${item.style || ''}`.toLowerCase();
    if (text.includes('english') || text.includes('en-us') || text.includes('us voice')) {
      return 'en-US';
    }
    return 'zh-CN';
  }

  private static defaultVoices(): TtsVoiceOption[] {
      const option = new TtsVoiceOption();
      option.id = 0;
      option.name = '默认音色';
      option.online = 0;
      option.status = 'default';
      option.language = 'zh-CN';
      return [option];
  }

  private static async probeAvailableVoices(online: number = 0): Promise<TtsVoiceOption[]> {
    const options: TtsVoiceOption[] = [];
    for (let person = 0; person <= SystemTtsReader.MAX_PROBE_PERSON; person++) {
      const available = await SystemTtsReader.canCreateEngine(person, online);
      if (!available) {
        continue;
      }
      const option = new TtsVoiceOption();
      option.id = person;
      option.name = person === 0 ? '默认音色' : `${online === 0 ? '在线音色' : '离线音色'} ${person}`;
      option.online = online;
      option.status = 'probed';
      option.language = 'zh-CN';
      options.push(option);
    }
    return options.length > 0 ? options : SystemTtsReader.defaultVoices();
  }

  private static async filterAvailableVoices(voices: TtsVoiceOption[]): Promise<TtsVoiceOption[]> {
    const options: TtsVoiceOption[] = [];
    for (const voice of voices) {
      const available = await SystemTtsReader.canCreateEngine(voice.id, voice.online, voice.style, voice.language);
      if (available) {
        options.push(voice);
      }
    }
    return options;
  }

  private static async canCreateEngine(person: number, online: number, style: string = '',
    language: string = 'zh-CN'): Promise<boolean> {
    let engine: textToSpeech.TextToSpeechEngine | null = null;
    try {
      engine = await SystemTtsReader.createEngineWithMode(person, online, style, language);
      return true;
    } catch (_) {
      return false;
    } finally {
      try {
        engine?.shutdown();
      } catch (_) {
      }
    }
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
