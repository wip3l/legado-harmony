import { router, promptAction } from '@kit.ArkUI';
import { util } from '@kit.ArkTS';
import http from '@ohos.net.http';
import fs from '@ohos.file.fs';
import { HttpTTS } from '../model/data/Book';
import { CookieStore } from '../core/http/CookieStore';
import { JsRuntime } from '../core/rule/JsRuntime';
import { TtsAvAudioPlayer } from './TtsAvAudioPlayer';
import { TtsPcmAudioPlayer } from './TtsPcmAudioPlayer';

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
  private static readonly DEFAULT_SILENCE_MS: number = 450;
  private static rateBuckets: Record<string, TtsRateBucket> = {};
  private static sharedRuntimes: Record<string, JsRuntime> = {};

  private pcmPlayer: TtsPcmAudioPlayer = new TtsPcmAudioPlayer();
  private avPlayer: TtsAvAudioPlayer = new TtsAvAudioPlayer();
  private generation: number = 0;
  private currentClients: http.HttpRequest[] = [];
  private consecutiveErrors: number = 0;
  private loginPromptedAt: Record<string, number> = {};

  async play(voice: HttpTTS, text: string, speed: number = 1): Promise<void> {
    const audio = await this.synthesize(voice, text, speed);
    await this.writeAudio(audio);
    await this.drain();
  }

  async synthesize(voice: HttpTTS, text: string, speed: number = 1): Promise<HttpTtsAudio> {
    const generation = this.generation;
    const normalizedSpeed = this.normalizeSpeed(speed);
    try {
      const audio = await this.synthesizeWithRetry(voice, text, normalizedSpeed);
      if (generation !== this.generation) {
        throw new Error('自定义音色合成已停止');
      }
      this.consecutiveErrors = 0;
      return audio.filePath ? audio : this.applyLocalSpeed(audio, normalizedSpeed);
    } catch (error) {
      this.consecutiveErrors++;
      console.warn('[TTS] custom voice synthesize failed:', error);
      if (this.consecutiveErrors >= HttpTtsReader.MAX_RETRY) {
        this.consecutiveErrors = 0;
        throw error as Error;
      }
      const silent = this.createSilentAudio();
      silent.speed = normalizedSpeed;
      return silent;
    }
  }

  async writeAudio(audio: HttpTtsAudio): Promise<void> {
    if (audio.filePath) {
      await this.avPlayer.play(audio.filePath, audio.speed || 1);
      return;
    }
    await this.pcmPlayer.write(audio.pcm, audio.sampleRate);
  }

  async drain(): Promise<void> {
    await this.pcmPlayer.drain();
  }

  stop(): void {
    this.generation++;
    const clients = this.currentClients.slice();
    this.currentClients = [];
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

  private async synthesizeWithRetry(voice: HttpTTS, text: string, speed: number): Promise<HttpTtsAudio> {
    const rule = this.buildRequest(voice, text, speed);
    const maxRetry = Math.max(HttpTtsReader.MAX_RETRY, rule.retry + 1);
    let lastError: Error = new Error('自定义音色请求失败');
    for (let attempt = 0; attempt < maxRetry; attempt++) {
      try {
        return await this.withRateLimit(voice, () => this.fetchAudio(voice, rule, text, speed));
      } catch (error) {
        lastError = error as Error;
        if (attempt + 1 < maxRetry) {
          await this.delay(Math.min(1800, 300 + attempt * 300));
        }
      }
    }
    throw lastError;
  }

  private async fetchAudio(voice: HttpTTS, rule: TtsRequestResult, text: string, speed: number): Promise<HttpTtsAudio> {
    const cachePath = this.cachePath(voice, rule, text, speed);
    if (cachePath && this.fileExists(cachePath)) {
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
      const responseHeaders = (response.header || {}) as Record<string, string>;
      if (this.cookieEnabled(voice)) {
        this.saveResponseCookies(rule.url, responseHeaders);
      }
      const buffer = this.responseBuffer(response.result);
      const contentType = this.findHeader(responseHeaders, 'content-type');
      if (response.responseCode < 200 || response.responseCode >= 300) {
        const bodyText = this.decodeText(buffer, rule.charset);
        this.handleLoginCheck(voice, bodyText, rule.url);
        throw new Error(`HTTP ${response.responseCode}`);
      }
      if (!buffer || buffer.byteLength <= 0) {
        throw new Error('音频响应为空');
      }
      this.assertContentType(voice, contentType, buffer, rule.url);
      this.handleLoginCheck(voice, this.safePreviewText(buffer, contentType, rule.charset), rule.url);
      const wavAudio = this.tryParseWavPcm(buffer);
      if (wavAudio) {
        wavAudio.contentType = contentType || 'audio/wav';
        wavAudio.speed = speed;
        return wavAudio;
      }
      if (!cachePath) {
        throw new Error('非 PCM 音频需要应用缓存目录');
      }
      this.writeCacheFile(cachePath, buffer);
      this.pruneCache();
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
    rawRule.body = runtime.evalTemplate(rawRule.body || '');
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

  private findOptionIndex(value: string): number {
    let quote = '';
    let depth = 0;
    for (let i = value.length - 1; i >= 0; i--) {
      const ch = value.charAt(i);
      const prev = i > 0 ? value.charAt(i - 1) : '';
      if (quote) {
        if (ch === quote && prev !== '\\') quote = '';
        continue;
      }
      if (ch === '"' || ch === "'") {
        quote = ch;
        continue;
      }
      if (ch === '}') depth++;
      else if (ch === '{') depth--;
      else if (ch === ',' && depth > 0) return i;
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
    promptAction.showToast({ message: `${voice.name || '自定义音色'} 需要登录` });
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

  private createSilentAudio(): HttpTtsAudio {
    const audio = new HttpTtsAudio();
    audio.sampleRate = 16000;
    audio.pcm = new ArrayBuffer(Math.floor(16000 * HttpTtsReader.DEFAULT_SILENCE_MS / 1000) * 2);
    return audio;
  }

  private async withRateLimit<T>(voice: HttpTTS, action: () => Promise<T>): Promise<T> {
    const max = this.parseConcurrentRate(voice.concurrentRate);
    if (max <= 0) return action();
    const key = this.voiceKey(voice);
    const bucket = HttpTtsReader.rateBuckets[key] || new TtsRateBucket();
    HttpTtsReader.rateBuckets[key] = bucket;
    while (bucket.active >= max) {
      await this.delay(80);
    }
    bucket.active++;
    try {
      return await action();
    } finally {
      bucket.active = Math.max(0, bucket.active - 1);
    }
  }

  private parseConcurrentRate(value: string): number {
    const raw = (value || '').trim();
    if (!raw || raw === '0') return 0;
    const match = raw.match(/^\d+/);
    return match ? Math.max(1, Number(match[0]) || 1) : 1;
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

  private pruneCache(): void {
    const dir = this.cacheDir();
    if (!dir) return;
    try {
      const files = fs.listFileSync(dir).filter((name: string) => !!name);
      if (files.length <= HttpTtsReader.MAX_CACHE_FILES) return;
      const removeCount = files.length - HttpTtsReader.MAX_CACHE_FILES;
      for (let i = 0; i < removeCount; i++) {
        try {
          fs.unlinkSync(`${dir}/${files[i]}`);
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

  private delay(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }
}
