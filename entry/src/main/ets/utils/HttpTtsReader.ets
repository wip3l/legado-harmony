import { router } from '@kit.ArkUI';
import { util } from '@kit.ArkTS';
import http from '@ohos.net.http';
import fs from '@ohos.file.fs';
import { HttpTTS } from '../model/data/Book';
import { CookieStore } from '../core/http/CookieStore';
import { JsRuntime } from '../core/rule/JsRuntime';
import { TtsAvAudioPlayer } from './TtsAvAudioPlayer';
import { PcmPlaybackCue, TtsPcmAudioPlayer } from './TtsPcmAudioPlayer';
import { HdsFeedback } from './HdsFeedback';

class TtsRequestRule {
  url: string = '';
  method: string = 'GET';
  headers: Record<string, string> = {};
  body: string = '';
  charset: string = 'utf-8';
  bodyJs: string = '';
  retry: number = 0;
  type: string = '';
}

class TtsRequestResult {
  url: string = '';
  method: http.RequestMethod = http.RequestMethod.GET;
  headers: Record<string, string> = {};
  body: string = '';
  charset: string = 'utf-8';
  retry: number = 0;
}

class TtsRateBucket {
  active: number = 0;
  timestamps: number[] = [];
}

class TtsRateConfig {
  mode: number = 0;
  limit: number = 0;
  windowMs: number = 0;
  waitMs: number = 0;
}

class HttpTtsCancelledError extends Error {
  constructor() {
    super('自定义音色合成已停止');
    this.name = 'HttpTtsCancelledError';
  }
}

export class HttpTtsAudio {
  pcm: ArrayBuffer = new ArrayBuffer(0);
  sampleRate: number = 16000;
  filePath: string = '';
  contentType: string = '';
  speed: number = 1;
}

export class HttpTtsReader {
  private static readonly MAX_RETRY: number = 5;
  private static readonly CACHE_DIR_NAME: string = 'http_tts';
  private static readonly MAX_CACHE_FILES: number = 600;
  private static rateBuckets: Record<string, TtsRateBucket> = {};
  private static sharedRuntimes: Record<string, JsRuntime> = {};

  private pcmPlayer: TtsPcmAudioPlayer = new TtsPcmAudioPlayer();
  private avPlayer: TtsAvAudioPlayer = new TtsAvAudioPlayer();
  private generation: number = 0;
  private currentClients: http.HttpRequest[] = [];
  private loginPromptedAt: Record<string, number> = {};
  private protectedCachePaths: Map<string, number> = new Map<string, number>();

  async play(voice: HttpTTS, text: string, speed: number = 1): Promise<void> {
    const audio = await this.synthesize(voice, text, speed);
    await this.writeAudioRecovering(voice, text, speed, audio);
    await this.drain();
  }

  async synthesize(voice: HttpTTS, text: string, speed: number = 1): Promise<HttpTtsAudio> {
    const generation = this.generation;
    const normalizedSpeed = this.normalizeSpeed(speed);
    try {
      const audio = await this.synthesizeWithRetry(voice, text, normalizedSpeed, generation);
      this.assertGeneration(generation);
      if (audio.filePath) {
        this.retainCacheFile(audio.filePath);
      }
      if (this.templateAppliesSpeed(voice)) {
        // The provider already synthesized this audio at the requested pace
        // (the URL template consumed the speed variables). Applying the speed
        // again would compound it, and the PCM fallback below resamples by
        // dropping samples, which raises the pitch audibly.
        audio.speed = 1;
        return audio;
      }
      return audio.filePath ? audio : this.applyLocalSpeed(audio, normalizedSpeed);
    } catch (error) {
      if (this.isCancelledError(error as Error) || generation !== this.generation) {
        throw new HttpTtsCancelledError();
      }
      console.warn('[TTS] custom voice synthesize failed:', error);
      // synthesizeWithRetry has already exhausted the voice/request retry policy. Replacing this paragraph with
      // silence makes continuous reading advance as though it had been spoken, which is especially visible on
      // the final page. Surface the error so the reader stops at the exact paragraph and can retry it later.
      throw error as Error;
    }
  }

  async writeAudio(audio: HttpTtsAudio, onPlaybackStart?: (durationMs: number) => void): Promise<void> {
    if (audio.filePath) {
      try {
        await this.avPlayer.play(audio.filePath, audio.speed || 1, onPlaybackStart);
      } finally {
        this.releaseCacheFile(audio.filePath);
      }
      return;
    }
    if (onPlaybackStart) {
      const durationMs = audio.sampleRate > 0 ?
        audio.pcm.byteLength * 1000 / (audio.sampleRate * 2) : 0;
      onPlaybackStart(durationMs);
    }
    await this.pcmPlayer.write(audio.pcm, audio.sampleRate);
  }

  async writeAudioRecovering(voice: HttpTTS, text: string, speed: number, audio: HttpTtsAudio,
    onPlaybackStart?: (durationMs: number) => void): Promise<void> {
    try {
      await this.writeAudio(audio, onPlaybackStart);
    } catch (error) {
      if (!audio.filePath || !this.isMissingCacheFileError(error as Error)) {
        throw error as Error;
      }
      // The system may clear cache files between prefetch and playback. Remove the stale
      // reservation and synthesize only the affected sentence again instead of aborting TTS.
      this.deleteCacheFile(audio.filePath);
      const replacement = await this.synthesize(voice, text, speed);
      await this.writeAudio(replacement, onPlaybackStart);
    }
  }

  async writeTimedPcm(audio: HttpTtsAudio, cues: PcmPlaybackCue[]): Promise<void> {
    if (audio.filePath || !audio.pcm || audio.pcm.byteLength === 0) {
      throw new Error('时间轴朗读需要 PCM 音频');
    }
    await this.pcmPlayer.writeTimedSegment(audio.pcm, audio.sampleRate, cues);
  }

  async drain(): Promise<void> {
    await this.pcmPlayer.drain();
  }

  async pause(): Promise<void> {
    await this.pcmPlayer.pause();
    await this.avPlayer.pause();
  }

  async resume(): Promise<void> {
    await this.pcmPlayer.resume();
    await this.avPlayer.resume();
  }

  isPaused(): boolean {
    return this.pcmPlayer.isPaused() || this.avPlayer.isPaused();
  }

  stop(): void {
    this.generation++;
    const clients = this.currentClients.slice();
    this.currentClients = [];
    this.protectedCachePaths.clear();
    for (const client of clients) {
      try {
        client.destroy();
      } catch (_) {
      }
    }
    this.pcmPlayer.stop();
    this.avPlayer.stop();
  }

  release(): void {
    this.stop();
    this.pcmPlayer.release();
    this.avPlayer.release();
  }

  debugState(): string {
    return `httpGeneration=${this.generation},requests=${this.currentClients.length},` +
      `${this.pcmPlayer.debugState()},${this.avPlayer.debugState()}`;
  }

  private async synthesizeWithRetry(voice: HttpTTS, text: string, speed: number,
    generation: number): Promise<HttpTtsAudio> {
    this.assertGeneration(generation);
    const rule = this.buildRequest(voice, text, speed);
    const maxRetry = Math.max(HttpTtsReader.MAX_RETRY, rule.retry + 1);
    let lastError: Error = new Error('自定义音色请求失败');
    for (let attempt = 0; attempt < maxRetry; attempt++) {
      this.assertGeneration(generation);
      try {
        return await this.withRateLimit(voice, generation,
          () => this.fetchAudio(voice, rule, text, speed, generation));
      } catch (error) {
        if (this.isCancelledError(error as Error) || generation !== this.generation) {
          throw new HttpTtsCancelledError();
        }
        lastError = error as Error;
        if (attempt + 1 < maxRetry) {
          await this.delayCancelable(Math.min(1800, 300 + attempt * 300), generation);
        }
      }
    }
    throw lastError;
  }

  private async fetchAudio(voice: HttpTTS, rule: TtsRequestResult, text: string, speed: number,
    generation: number): Promise<HttpTtsAudio> {
    this.assertGeneration(generation);
    const cachePath = this.cachePath(voice, rule, text, speed);
    if (cachePath && this.fileExists(cachePath)) {
      this.assertGeneration(generation);
      return this.audioFromFile(cachePath, this.contentTypeFromPath(cachePath), speed);
    }
    const client = http.createHttp();
    this.currentClients.push(client);
    try {
      const headers: Record<string, string> = this.copyHeaders(rule.headers);
      if (this.cookieEnabled(voice) && !this.hasHeader(headers, 'Cookie')) {
        const cookie = CookieStore.getCookie(rule.url);
        if (cookie) {
          headers['Cookie'] = cookie;
        }
      }
      const response = await client.request(rule.url, {
        method: rule.method,
        header: headers,
        extraData: rule.body || undefined,
        connectTimeout: 300000,
        readTimeout: 300000,
        expectDataType: http.HttpDataType.ARRAY_BUFFER
      });
      this.assertGeneration(generation);
      const responseHeaders = (response.header || {}) as Record<string, string>;
      if (this.cookieEnabled(voice)) {
        this.saveResponseCookies(rule.url, responseHeaders);
      }
      const buffer = this.responseBuffer(response.result);
      const contentType = this.findHeader(responseHeaders, 'content-type');
      if (response.responseCode < 200 || response.responseCode >= 300) {
        const bodyText = this.decodeText(buffer, rule.charset);
        this.handleLoginCheck(voice, bodyText, rule.url);
        const preview = this.errorBodyPreview(bodyText);
        throw new Error(preview ? `HTTP ${response.responseCode}：${preview}` : `HTTP ${response.responseCode}`);
      }
      if (!buffer || buffer.byteLength <= 0) {
        throw new Error('音频响应为空');
      }
      this.assertContentType(voice, contentType, buffer, rule.url);
      this.handleLoginCheck(voice, this.safePreviewText(buffer, contentType, rule.charset), rule.url);
      const wavAudio = this.tryParseWavPcm(buffer);
      if (wavAudio) {
        wavAudio.pcm = this.trimTrailingPcmSilence(wavAudio.pcm, wavAudio.sampleRate, text);
        wavAudio.contentType = contentType || 'audio/wav';
        wavAudio.speed = speed;
        return wavAudio;
      }
      if (!cachePath) {
        throw new Error('非 PCM 音频需要应用缓存目录');
      }
      this.assertGeneration(generation);
      this.writeCacheFile(cachePath, buffer);
      // listFileSync order is not an age order. Exclude the freshly written file so
      // pruning cannot delete the same file that is about to be returned.
      this.pruneCache(cachePath);
      return this.audioFromFile(cachePath, contentType, speed);
    } finally {
      this.currentClients = this.currentClients.filter((item: http.HttpRequest) => item !== client);
      try {
        client.destroy();
      } catch (_) {
      }
    }
  }

  private buildRequest(voice: HttpTTS, text: string, speed: number): TtsRequestResult {
    const rawRule = this.parseRule((voice.url || '').trim());
    if (!rawRule.url) {
      throw new Error('自定义音色 URL 为空');
    }
    const runtime = this.runtimeForVoice(voice, text, speed);
    rawRule.url = runtime.evalTemplate(rawRule.url).trim();
    rawRule.body = this.renderBody(runtime, rawRule.body, text);
    if (rawRule.bodyJs) {
      const bodyFromJs = runtime.evaluate(rawRule.bodyJs, rawRule.body);
      if (bodyFromJs) {
        rawRule.body = bodyFromJs;
      }
    }
    const result = new TtsRequestResult();
    result.url = this.encodeUrl(rawRule.url, rawRule.charset);
    result.method = this.toRequestMethod(rawRule.method);
    result.charset = rawRule.charset || 'utf-8';
    result.retry = rawRule.retry;
    const headers: Record<string, string> = {};
    headers['User-Agent'] = 'Mozilla/5.0 (Linux; HarmonyOS; Mobile) LegadoHarmony';
    headers['Accept'] = '*/*';
    headers['Connection'] = 'keep-alive';
    this.mergeHeaders(headers, this.parseHeaders(voice.header));
    this.mergeHeaders(headers, rawRule.headers);
    result.headers = headers;
    if (result.method === http.RequestMethod.POST || result.method === http.RequestMethod.PUT) {
      result.body = this.buildBody(rawRule.body, result.headers, result.charset);
    }
    return result;
  }

  // Renders the request body. When the body is a JSON object/array, every text variable is
  // JSON-string-escaped before substitution: JsRuntime.evalTemplate is a plain textual replace, so
  // a half-width quote, backslash or line break in the paragraph would otherwise produce an
  // invalid payload that the server answers with 400 instead of audio. The variables are restored
  // afterwards so the URL template (encoded later by encodeUrl) and bodyJs still see the raw text.
  private renderBody(runtime: JsRuntime, body: string, text: string): string {
    const template = body || '';
    if (!this.looksLikeStructuredBody(template)) {
      return runtime.evalTemplate(template);
    }
    const escaped = this.escapeJsonString(text);
    runtime.setVar('speakText', escaped);
    runtime.setVar('text', escaped);
    try {
      return runtime.evalTemplate(template);
    } finally {
      runtime.setVar('speakText', text || '');
      runtime.setVar('text', text || '');
    }
  }

  private escapeJsonString(value: string): string {
    const encoded = JSON.stringify(value || '');
    if (encoded.length < 2) return '';
    return encoded.substring(1, encoded.length - 1);
  }

  private parseRule(value: string): TtsRequestRule {
    const rule = new TtsRequestRule();
    const optionIndex = this.findOptionIndex(value);
    if (optionIndex > 0) {
      rule.url = value.substring(0, optionIndex).trim();
      this.applyOptions(rule, value.substring(optionIndex + 1).trim());
    } else {
      rule.url = value.trim();
    }
    if (rule.url.startsWith('@')) {
      rule.method = 'POST';
      rule.url = rule.url.substring(1);
      const queryIndex = rule.url.indexOf('?');
      if (queryIndex > 0 && !rule.body) {
        rule.body = rule.url.substring(queryIndex + 1);
        rule.url = rule.url.substring(0, queryIndex);
      }
    }
    if (rule.url.includes('@Header:')) {
      const headerStart = rule.url.indexOf('@Header:');
      const headerEnd = rule.url.indexOf('@End', headerStart);
      if (headerEnd > headerStart) {
        const headerText = rule.url.substring(headerStart + 8, headerEnd);
        this.mergeHeaders(rule.headers, this.parseHeaders(headerText));
        rule.url = rule.url.substring(0, headerStart) + rule.url.substring(headerEnd + 4);
      }
    }
    return rule;
  }

  private applyOptions(rule: TtsRequestRule, optionText: string): void {
    try {
      const option = JSON.parse(optionText) as Record<string, Object>;
      if (option['method']) rule.method = String(option['method']).toUpperCase();
      if (option['body'] !== undefined && option['body'] !== null) {
        rule.body = typeof option['body'] === 'string' ? String(option['body']) : JSON.stringify(option['body']);
      }
      if (option['charset']) rule.charset = String(option['charset']).trim() || 'utf-8';
      if (option['headers']) {
        rule.headers = typeof option['headers'] === 'string' ?
          this.parseHeaders(String(option['headers'])) : this.recordToHeaders(option['headers'] as Record<string, Object>);
      }
      if (option['header']) {
        this.mergeHeaders(rule.headers, this.parseHeaders(String(option['header'])));
      }
      if (option['bodyJs']) rule.bodyJs = String(option['bodyJs']);
      if (option['retry'] !== undefined) rule.retry = Math.max(0, Number(option['retry']) || 0);
      if (option['type']) rule.type = String(option['type']);
    } catch (_) {
      const method = optionText.match(/['"]?method['"]?\s*:\s*['"]?(\w+)['"]?/i);
      if (method) rule.method = method[1].toUpperCase();
      const body = optionText.match(/['"]?body['"]?\s*:\s*(['"])([\s\S]*?)\1/i);
      if (body) rule.body = body[2];
      const charset = optionText.match(/['"]?charset['"]?\s*:\s*(['"])([\s\S]*?)\1/i);
      if (charset) rule.charset = charset[2];
      const bodyJs = optionText.match(/['"]?bodyJs['"]?\s*:\s*(['"])([\s\S]*?)\1/i);
      if (bodyJs) rule.bodyJs = bodyJs[2];
    }
  }

  // Splits "url,{options}" by scanning forward and returning the comma that sits outside every
  // brace, immediately before the options object. The previous backward scan counted nesting in
  // reverse (`depth > 0` on a comma), so a plain "url,{...}" reported -1 and a nested
  // "url,{...,"body":{...}}" reported an inner comma, truncating the URL and dropping the whole
  // options object. Mirrors AnalyzeUrl.findOptionIndex, which the book-source path already uses.
  private findOptionIndex(value: string): number {
    let quote = '';
    let brace = 0;
    for (let i = 0; i < value.length - 1; i++) {
      const ch = value.charAt(i);
      if (quote) {
        if (ch === quote && value.charAt(i - 1) !== '\\') quote = '';
        continue;
      }
      if (ch === '"' || ch === "'") {
        quote = ch;
        continue;
      }
      if (ch === '{') brace++;
      if (ch === '}') brace--;
      if (ch === ',' && brace === 0 && /^\s*\{/.test(value.substring(i + 1))) return i;
    }
    return -1;
  }

  private runtimeForVoice(voice: HttpTTS, text: string, speed: number): JsRuntime {
    const key = this.voiceKey(voice);
    let runtime = HttpTtsReader.sharedRuntimes[key];
    if (!runtime) {
      runtime = new JsRuntime();
      const jsLib = (voice.jsLib || voice.jsEngine || '').trim();
      if (jsLib) {
        runtime.evaluate(jsLib);
      }
      HttpTtsReader.sharedRuntimes[key] = runtime;
    }
    const normalizedSpeed = this.normalizeSpeed(speed);
    const speakSpeed = Math.max(0, Math.min(20, Math.round(normalizedSpeed * 10)));
    runtime.setVar('speakText', text || '');
    runtime.setVar('text', text || '');
    runtime.setVar('speakSpeed', String(speakSpeed));
    runtime.setVar('speechRate', this.formatSpeed(normalizedSpeed));
    runtime.setVar('speed', this.formatSpeed(normalizedSpeed));
    runtime.setVar('rate', this.formatSpeed(normalizedSpeed));
    runtime.setVar('speakSpeedPercent', String(Math.round(normalizedSpeed * 100)));
    return runtime;
  }

  private buildBody(body: string, headers: Record<string, string>, charset: string): string {
    const value = body || '';
    if (!this.hasHeader(headers, 'Content-Type')) {
      headers['Content-Type'] = this.looksLikeStructuredBody(value) ?
        `application/json; charset=${charset || 'utf-8'}` :
        `application/x-www-form-urlencoded; charset=${charset || 'utf-8'}`;
    }
    if (this.looksLikeStructuredBody(value)) {
      return value;
    }
    return this.encodeParams(value, charset, false);
  }

  private encodeUrl(url: string, charset: string): string {
    const trimmed = (url || '').trim();
    const queryIndex = trimmed.indexOf('?');
    if (queryIndex < 0) return trimmed;
    return trimmed.substring(0, queryIndex) + '?' +
      this.encodeParams(trimmed.substring(queryIndex + 1), charset, true);
  }

  private encodeParams(params: string, charset: string, isQuery: boolean): string {
    if (!params) return '';
    return params.split('&').map((field: string) => {
      const index = field.indexOf('=');
      if (index < 0) return this.encodeComponent(field, charset, isQuery);
      return this.encodeComponent(field.substring(0, index), charset, isQuery) + '=' +
        this.encodeComponent(field.substring(index + 1), charset, isQuery);
    }).join('&');
  }

  private encodeComponent(value: string, charset: string, isQuery: boolean): string {
    if (!value || this.looksEncoded(value)) return value;
    const normalized = this.normalizeCharset(charset);
    if (normalized === 'escape') return this.escapeComponent(value);
    try {
      if (normalized !== 'utf-8') {
        const bytes = new util.TextEncoder(normalized).encodeInto(value);
        let output = '';
        for (let i = 0; i < bytes.length; i++) {
          const byte = bytes[i];
          const ch = String.fromCharCode(byte);
          if (/[A-Za-z0-9_.~-]/.test(ch)) output += ch;
          else if (!isQuery && ch === ' ') output += '+';
          else output += '%' + byte.toString(16).toUpperCase().padStart(2, '0');
        }
        return output;
      }
      const encoded = encodeURIComponent(value);
      return isQuery ? encoded : encoded.replace(/%20/g, '+');
    } catch (_) {
      return value;
    }
  }

  private escapeComponent(value: string): string {
    let result = '';
    for (let i = 0; i < value.length; i++) {
      const code = value.charCodeAt(i);
      const ch = value.charAt(i);
      if (/[A-Za-z0-9@*_+\-./]/.test(ch)) result += ch;
      else if (code < 256) result += '%' + code.toString(16).toUpperCase().padStart(2, '0');
      else result += '%u' + code.toString(16).toUpperCase().padStart(4, '0');
    }
    return result;
  }

  private assertContentType(voice: HttpTTS, contentType: string, buffer: ArrayBuffer, url: string): void {
    const expected = (voice.contentType || '').trim();
    if (expected) {
      try {
        if (!new RegExp(expected, 'i').test(contentType || '')) {
          throw new Error(`contentType 不匹配：${contentType || 'unknown'}`);
        }
      } catch (_) {
        if (!(contentType || '').toLowerCase().includes(expected.toLowerCase())) {
          throw new Error(`contentType 不匹配：${contentType || 'unknown'}`);
        }
      }
    }
    const lower = (contentType || '').toLowerCase();
    const looksAudio = lower.includes('audio/') || lower.includes('octet-stream') ||
      this.isLikelyAudioBuffer(buffer, url);
    if (!looksAudio) {
      const bodyText = this.decodeText(buffer, 'utf-8');
      this.handleLoginCheck(voice, bodyText, url);
      throw new Error(`响应不是音频：${contentType || bodyText.substring(0, 80)}`);
    }
  }

  private handleLoginCheck(voice: HttpTTS, bodyText: string, requestUrl: string): void {
    const script = (voice.loginCheckJs || '').trim();
    if (!script || !bodyText) return;
    const result = this.runtimeForVoice(voice, bodyText, 1).evaluate(script, bodyText).trim().toLowerCase();
    if (result === 'false' || result === '0' || result.includes('login') || result.includes('登录')) {
      this.requestLogin(voice, requestUrl);
    }
  }

  private requestLogin(voice: HttpTTS, requestUrl: string): void {
    const loginUrl = (voice.loginUrl || voice.loginUi || '').trim();
    if (!loginUrl) return;
    const key = this.voiceKey(voice);
    const now = Date.now();
    if (now - (this.loginPromptedAt[key] || 0) < 60000) return;
    this.loginPromptedAt[key] = now;
    HdsFeedback.showToast(`${voice.name || '自定义音色'} 需要登录`);
    AppStorage.setOrCreate('pendingVerificationUrl', loginUrl);
    AppStorage.setOrCreate('pendingVerificationTitle', `${voice.name || '自定义音色'} 登录`);
    AppStorage.setOrCreate('pendingVerificationSourceUrl', requestUrl);
    AppStorage.setOrCreate('pendingVerificationLoginUrl', loginUrl);
    router.pushUrl({ url: 'pages/VerifyWeb' }).catch(() => {});
  }

  private tryParseWavPcm(buffer: ArrayBuffer): HttpTtsAudio | null {
    try {
      return this.parseWavPcm(buffer);
    } catch (_) {
      return null;
    }
  }

  private parseWavPcm(buffer: ArrayBuffer): HttpTtsAudio {
    const view = new DataView(buffer);
    if (buffer.byteLength < 44 || this.readAscii(view, 0, 4) !== 'RIFF' || this.readAscii(view, 8, 4) !== 'WAVE') {
      throw new Error('不是 WAV 音频');
    }
    let offset = 12;
    let audioFormat = 0;
    let channels = 1;
    let sampleRate = 16000;
    let bitsPerSample = 16;
    let dataOffset = -1;
    let dataSize = 0;
    while (offset + 8 <= buffer.byteLength) {
      const chunkId = this.readAscii(view, offset, 4);
      const chunkSize = view.getUint32(offset + 4, true);
      const chunkDataOffset = offset + 8;
      if (chunkId === 'fmt ' && chunkSize >= 16) {
        audioFormat = view.getUint16(chunkDataOffset, true);
        channels = view.getUint16(chunkDataOffset + 2, true);
        sampleRate = view.getUint32(chunkDataOffset + 4, true);
        bitsPerSample = view.getUint16(chunkDataOffset + 14, true);
      } else if (chunkId === 'data') {
        dataOffset = chunkDataOffset;
        dataSize = Math.min(chunkSize, buffer.byteLength - chunkDataOffset);
        break;
      }
      offset = chunkDataOffset + chunkSize + (chunkSize % 2);
    }
    if (audioFormat !== 1 || bitsPerSample !== 16 || dataOffset < 0 || dataSize <= 0) {
      throw new Error('仅支持 16bit PCM WAV 音频');
    }
    const audio = new HttpTtsAudio();
    audio.sampleRate = sampleRate;
    const pcm = buffer.slice(dataOffset, dataOffset + dataSize);
    audio.pcm = channels <= 1 ? pcm : this.downmix16BitPcmToMono(pcm, channels);
    return audio;
  }

  private applyLocalSpeed(audio: HttpTtsAudio, speed: number): HttpTtsAudio {
    const normalizedSpeed = this.normalizeSpeed(speed);
    audio.speed = normalizedSpeed;
    if (Math.abs(normalizedSpeed - 1) < 0.01 || !audio.pcm || audio.pcm.byteLength < 4) {
      return audio;
    }
    const adjusted = new HttpTtsAudio();
    adjusted.sampleRate = audio.sampleRate;
    adjusted.contentType = audio.contentType;
    adjusted.speed = normalizedSpeed;
    adjusted.pcm = this.resample16BitPcm(audio.pcm, normalizedSpeed);
    return adjusted;
  }

  private resample16BitPcm(buffer: ArrayBuffer, speed: number): ArrayBuffer {
    const inputFrames = Math.floor(buffer.byteLength / 2);
    if (inputFrames <= 1) return buffer;
    const outputFrames = Math.max(1, Math.floor(inputFrames / speed));
    const input = new DataView(buffer);
    const output = new ArrayBuffer(outputFrames * 2);
    const outputView = new DataView(output);
    for (let frame = 0; frame < outputFrames; frame++) {
      const sourcePosition = Math.min(inputFrames - 1, frame * speed);
      const sourceFrame = Math.floor(sourcePosition);
      const nextFrame = Math.min(inputFrames - 1, sourceFrame + 1);
      const fraction = sourcePosition - sourceFrame;
      const current = input.getInt16(sourceFrame * 2, true);
      const next = input.getInt16(nextFrame * 2, true);
      const sample = Math.round(current + (next - current) * fraction);
      outputView.setInt16(frame * 2, Math.max(-32768, Math.min(32767, sample)), true);
    }
    return output;
  }

  private downmix16BitPcmToMono(buffer: ArrayBuffer, channels: number): ArrayBuffer {
    const input = new DataView(buffer);
    const frameCount = Math.floor(buffer.byteLength / (channels * 2));
    const output = new ArrayBuffer(frameCount * 2);
    const outputView = new DataView(output);
    for (let frame = 0; frame < frameCount; frame++) {
      let sum = 0;
      for (let channel = 0; channel < channels; channel++) {
        sum += input.getInt16((frame * channels + channel) * 2, true);
      }
      outputView.setInt16(frame * 2, Math.max(-32768, Math.min(32767, Math.round(sum / channels))), true);
    }
    return output;
  }

  private trimTrailingPcmSilence(pcm: ArrayBuffer, sampleRate: number, text: string): ArrayBuffer {
    const safeSampleRate = Math.max(8000, Math.round(sampleRate || 16000));
    const totalFrames = Math.floor(pcm.byteLength / 2);
    if (totalFrames < Math.round(safeSampleRate * 0.35)) return pcm;
    const view = new DataView(pcm);
    const windowFrames = Math.max(32, Math.round(safeSampleRate * 0.01));
    let lastActiveFrame = -1;
    for (let windowEnd = totalFrames; windowEnd > 0; windowEnd -= windowFrames) {
      const windowStart = Math.max(0, windowEnd - windowFrames);
      let absoluteSum = 0;
      let peak = 0;
      let samples = 0;
      for (let frame = windowStart; frame < windowEnd; frame += 2) {
        const amplitude = Math.abs(view.getInt16(frame * 2, true));
        absoluteSum += amplitude;
        peak = Math.max(peak, amplitude);
        samples++;
      }
      const average = samples > 0 ? absoluteSum / samples : 0;
      if (average >= 64 || peak >= 320) {
        lastActiveFrame = windowEnd;
        break;
      }
    }
    if (lastActiveFrame < 0) return pcm;
    const keepFrames = Math.round(safeSampleRate * this.trailingPauseSeconds(text));
    const targetFrames = Math.min(totalFrames, lastActiveFrame + keepFrames);
    if (totalFrames - targetFrames < Math.round(safeSampleRate * 0.12)) return pcm;
    return pcm.slice(0, targetFrames * 2);
  }

  private trailingPauseSeconds(text: string): number {
    const value = (text || '').trim();
    let index = value.length - 1;
    while (index >= 0 && '”’"\'）)】]》〉」』'.includes(value.charAt(index))) index--;
    const last = index >= 0 ? value.charAt(index) : '';
    if ('。！？!?'.includes(last)) return 0.22;
    if ('；;：:'.includes(last)) return 0.16;
    if ('，,、'.includes(last)) return 0.12;
    return 0.1;
  }

  private async withRateLimit<T>(voice: HttpTTS, generation: number,
    action: () => Promise<T>): Promise<T> {
    this.assertGeneration(generation);
    const config = this.parseConcurrentRate(voice.concurrentRate);
    if (config.mode === 0) return action();
    const key = this.voiceKey(voice);
    const bucket = HttpTtsReader.rateBuckets[key] || new TtsRateBucket();
    HttpTtsReader.rateBuckets[key] = bucket;

    if (config.mode === 2) {
      while (true) {
        this.assertGeneration(generation);
        const now = Date.now();
        bucket.timestamps = bucket.timestamps.filter((timestamp: number): boolean =>
          now - timestamp < config.windowMs);
        if (bucket.timestamps.length < config.limit) {
          bucket.timestamps.push(now);
          return action();
        }
        const waitMs = Math.max(1, bucket.timestamps[0] + config.windowMs - now);
        await this.delayCancelable(Math.min(250, waitMs), generation);
      }
    }

    const pollMs = Math.max(20, Math.min(200, config.waitMs));
    while (bucket.active > 0) {
      await this.delayCancelable(pollMs, generation);
    }
    this.assertGeneration(generation);
    bucket.active++;
    try {
      return await action();
    } finally {
      bucket.active = Math.max(0, bucket.active - 1);
    }
  }

  private parseConcurrentRate(value: string): TtsRateConfig {
    const config = new TtsRateConfig();
    const raw = (value || '').trim();
    if (!raw || raw === '0') return config;
    const windowMatch = raw.match(/^(\d+)\s*\/\s*(\d+)$/);
    if (windowMatch) {
      config.mode = 2;
      config.limit = Math.min(1000, Math.max(1, Number(windowMatch[1]) || 1));
      config.windowMs = Math.min(60 * 60 * 1000, Math.max(100, Number(windowMatch[2]) || 100));
      return config;
    }
    if (/^\d+$/.test(raw)) {
      config.mode = 1;
      config.waitMs = Math.min(60 * 60 * 1000, Math.max(1, Number(raw) || 1));
    }
    return config;
  }

  private cachePath(voice: HttpTTS, rule: TtsRequestResult, text: string, speed: number): string {
    const dir = this.cacheDir();
    if (!dir) return '';
    this.ensureDir(dir);
    const ext = this.extFromUrl(rule.url);
    const key = `${this.voiceKey(voice)}\n${rule.url}\n${rule.method}\n${rule.body}\n${text}\n${this.formatSpeed(speed)}`;
    return `${dir}/${this.hashText(key)}.${ext}`;
  }

  private audioFromFile(filePath: string, contentType: string, speed: number): HttpTtsAudio {
    const audio = new HttpTtsAudio();
    audio.filePath = filePath;
    audio.contentType = contentType;
    audio.speed = speed;
    return audio;
  }

  private writeCacheFile(path: string, buffer: ArrayBuffer): void {
    const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, buffer);
    } finally {
      fs.closeSync(file);
    }
  }

  private pruneCache(excludedPath: string = ''): void {
    const dir = this.cacheDir();
    if (!dir) return;
    try {
      const files = fs.listFileSync(dir).filter((name: string) => !!name);
      if (files.length <= HttpTtsReader.MAX_CACHE_FILES) return;
      const removeCount = files.length - HttpTtsReader.MAX_CACHE_FILES;
      let removed = 0;
      for (let i = 0; i < files.length && removed < removeCount; i++) {
        const filePath = `${dir}/${files[i]}`;
        if (filePath === excludedPath || (this.protectedCachePaths.get(filePath) || 0) > 0) continue;
        try {
          fs.unlinkSync(filePath);
          removed++;
        } catch (_) {
        }
      }
    } catch (_) {
    }
  }

  private cacheDir(): string {
    const root = AppStorage.get<string>('appCacheDir') || '';
    return root ? `${root}/${HttpTtsReader.CACHE_DIR_NAME}` : '';
  }

  private ensureDir(path: string): void {
    try {
      if (!fs.accessSync(path)) {
        fs.mkdirSync(path, true);
      }
    } catch (_) {
      try {
        fs.mkdirSync(path, true);
      } catch (_) {
      }
    }
  }

  private fileExists(path: string): boolean {
    try {
      return fs.accessSync(path);
    } catch (_) {
      return false;
    }
  }

  private deleteCacheFile(path: string): void {
    if (!path) return;
    try {
      if (fs.accessSync(path)) fs.unlinkSync(path);
    } catch (_) {
    }
  }

  private retainCacheFile(path: string): void {
    if (!path) return;
    this.protectedCachePaths.set(path, (this.protectedCachePaths.get(path) || 0) + 1);
  }

  private releaseCacheFile(path: string): void {
    if (!path) return;
    const count = this.protectedCachePaths.get(path) || 0;
    if (count <= 1) {
      this.protectedCachePaths.delete(path);
    } else {
      this.protectedCachePaths.set(path, count - 1);
    }
  }

  private isMissingCacheFileError(error: Error): boolean {
    const message = `${error?.message || error || ''}`.toLowerCase();
    return message.includes('13900002') || message.includes('no such file') ||
      message.includes('open failed') || message.includes('enoent');
  }

  private responseBuffer(result: string | Object): ArrayBuffer {
    if (result instanceof ArrayBuffer) return result as ArrayBuffer;
    if (typeof result === 'string') {
      return new util.TextEncoder().encodeInto(result as string).buffer as ArrayBuffer;
    }
    return new ArrayBuffer(0);
  }

  private decodeText(buffer: ArrayBuffer, charset: string): string {
    try {
      return util.TextDecoder.create(this.normalizeCharset(charset || 'utf-8'))
        .decodeWithStream(new Uint8Array(buffer), { stream: false });
    } catch (_) {
      try {
        return util.TextDecoder.create('utf-8').decodeWithStream(new Uint8Array(buffer), { stream: false });
      } catch (_) {
        return '';
      }
    }
  }

  private safePreviewText(buffer: ArrayBuffer, contentType: string, charset: string): string {
    const lower = (contentType || '').toLowerCase();
    if (lower.includes('json') || lower.startsWith('text/')) {
      return this.decodeText(buffer, charset);
    }
    return '';
  }

  private parseHeaders(raw: string): Record<string, string> {
    const value = (raw || '').trim();
    if (!value) return this.emptyHeaders();
    if (value.startsWith('{')) {
      try {
        return this.recordToHeaders(JSON.parse(value) as Record<string, Object>);
      } catch (_) {
      }
    }
    const headers: Record<string, string> = {};
    for (const line of value.split(/\r?\n/)) {
      const index = line.indexOf(':');
      if (index > 0) {
        headers[line.substring(0, index).trim()] = line.substring(index + 1).trim();
      }
    }
    return headers;
  }

  private recordToHeaders(source: Record<string, Object>): Record<string, string> {
    const headers: Record<string, string> = {};
    for (const key of Object.keys(source)) {
      const value = source[key];
      if (key && value !== undefined && value !== null) {
        headers[key] = String(value);
      }
    }
    return headers;
  }

  private emptyHeaders(): Record<string, string> {
    const headers: Record<string, string> = {};
    return headers;
  }

  private copyHeaders(source: Record<string, string>): Record<string, string> {
    const headers: Record<string, string> = {};
    this.mergeHeaders(headers, source);
    return headers;
  }

  private mergeHeaders(target: Record<string, string>, source: Record<string, string>): void {
    for (const key of Object.keys(source)) {
      if (key && source[key] !== undefined && source[key] !== null) {
        target[key] = String(source[key]);
      }
    }
  }

  private findHeader(headers: Record<string, string>, name: string): string {
    const lower = name.toLowerCase();
    for (const key of Object.keys(headers)) {
      if (key.toLowerCase() === lower) return String(headers[key] || '');
    }
    return '';
  }

  private hasHeader(headers: Record<string, string>, name: string): boolean {
    return !!this.findHeader(headers, name);
  }

  private saveResponseCookies(url: string, headers: Record<string, string>): void {
    const setCookie = this.findHeader(headers, 'set-cookie');
    if (setCookie) {
      CookieStore.setCookies(url, setCookie);
      CookieStore.saveAsync();
    }
  }

  private cookieEnabled(voice: HttpTTS): boolean {
    return voice.enabledCookieJar === true;
  }

  private looksLikeStructuredBody(value: string): boolean {
    const trimmed = (value || '').trim();
    return trimmed.startsWith('{') || trimmed.startsWith('[');
  }

  private looksEncoded(value: string): boolean {
    return /%[0-9A-Fa-f]{2}/.test(value) || value.includes('%u');
  }

  private isLikelyAudioBuffer(buffer: ArrayBuffer, url: string): boolean {
    if (!buffer || buffer.byteLength < 4) return false;
    const view = new DataView(buffer);
    const a = view.getUint8(0);
    const b = view.getUint8(1);
    const c = view.getUint8(2);
    const d = view.getUint8(3);
    if (a === 0x52 && b === 0x49 && c === 0x46 && d === 0x46) return true;
    if (a === 0x49 && b === 0x44 && c === 0x33) return true;
    if (a === 0xFF && (b & 0xE0) === 0xE0) return true;
    if (a === 0x00 && b === 0x00 && (c === 0x00 || c === 0x01) && d >= 0x18) return true;
    return /\.(mp3|aac|m4a|wav|flac|amr|ogg)(?:[?#]|$)/i.test(url || '');
  }

  private extFromUrl(url: string): string {
    const match = (url || '').match(/\.([a-z0-9]{2,5})(?:[?#]|$)/i);
    const ext = match ? match[1].toLowerCase() : '';
    return /^(mp3|aac|m4a|wav|flac|amr|ogg)$/.test(ext) ? ext : 'mp3';
  }

  private contentTypeFromPath(path: string): string {
    const ext = this.extFromUrl(path);
    switch (ext) {
      case 'wav': return 'audio/wav';
      case 'aac': return 'audio/aac';
      case 'm4a': return 'audio/mp4';
      case 'flac': return 'audio/flac';
      case 'ogg': return 'audio/ogg';
      default: return 'audio/mpeg';
    }
  }

  private toRequestMethod(method: string): http.RequestMethod {
    switch ((method || '').toUpperCase()) {
      case 'POST': return http.RequestMethod.POST;
      case 'PUT': return http.RequestMethod.PUT;
      case 'DELETE': return http.RequestMethod.DELETE;
      case 'HEAD': return http.RequestMethod.HEAD;
      default: return http.RequestMethod.GET;
    }
  }

  private normalizeCharset(charset: string): string {
    const value = (charset || '').toLowerCase().replace(/["']/g, '').trim();
    if (value === 'gbk' || value === 'gb2312') return 'gb18030';
    return value || 'utf-8';
  }

  private normalizeSpeed(speed: number): number {
    return Math.max(0.5, Math.min(2, speed || 1));
  }

  // Matches the speed variables injected in runtimeForVoice inside a {{...}}
  // expression. When the request template consumes one of them, the provider
  // performs the speed change during synthesis and the local fallback
  // (applyLocalSpeed / AVPlayer playback rate) must stay off.
  private static readonly SPEED_VAR_PATTERN: RegExp =
    new RegExp('\\{\\{[^}]*\\b(speakSpeed|speakSpeedPercent|speechRate|speed|rate)\\b[^}]*\\}\\}');

  private templateAppliesSpeed(voice: HttpTTS): boolean {
    return HttpTtsReader.SPEED_VAR_PATTERN.test(voice.url || '');
  }

  private formatSpeed(speed: number): string {
    return String(Math.round(speed * 100) / 100);
  }

  private readAscii(view: DataView, offset: number, length: number): string {
    let value = '';
    for (let index = 0; index < length; index++) {
      value += String.fromCharCode(view.getUint8(offset + index));
    }
    return value;
  }

  private voiceKey(voice: HttpTTS): string {
    return String(voice.id || voice.name || voice.url || 'default');
  }

  private hashText(input: string): string {
    let hash = 2166136261;
    for (let i = 0; i < input.length; i++) {
      hash ^= input.charCodeAt(i);
      hash = Math.imul(hash, 16777619);
    }
    return (hash >>> 0).toString(16);
  }

  private errorBodyPreview(value: string): string {
    return (value || '')
      .replace(/\s+/g, ' ')
      .trim()
      .substring(0, 160);
  }

  private assertGeneration(generation: number): void {
    if (generation !== this.generation) {
      throw new HttpTtsCancelledError();
    }
  }

  private isCancelledError(error: Error): boolean {
    return error instanceof HttpTtsCancelledError || error.name === 'HttpTtsCancelledError' ||
      error.message === '自定义音色合成已停止';
  }

  private async delayCancelable(ms: number, generation: number): Promise<void> {
    await this.delay(ms);
    this.assertGeneration(generation);
  }

  private delay(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }
}
