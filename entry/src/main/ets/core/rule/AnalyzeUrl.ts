import { BookSource } from '../../model/data/Book';
import { HttpClient, HttpRequest, HttpResponse } from '../http/HttpClient';
import { VerificationSupport } from '../http/VerificationSupport';
import { util } from '@kit.ArkTS';

export interface UrlConfig {
  url: string;
  method: string;
  body: string;
  charset: string;
  headers: Record<string, string>;
  sourceHeaders: Record<string, string>;
  retry: number;
  type: string;
  useWebView: boolean;
  webJs: string;
}

export class AnalyzeUrl {
  private config: UrlConfig;
  private source: BookSource | null;
  private client: HttpClient;

  constructor(source: BookSource | null, client: HttpClient) {
    this.source = source;
    this.client = client;
    this.config = this.emptyConfig('');
  }

  parse(urlTemplate: string): UrlConfig {
    this.config = this.emptyConfig(urlTemplate);
    if (!urlTemplate) return this.config;

    let url = urlTemplate.trim();
    url = this.stripLeadingJs(url);

    // 1. 解析 URL 选项 JSON: url,{"method":"POST","body":"...","headers":{...}}
    const optIndex = this.findOptionIndex(url);
    if (optIndex > 0) {
      const optStr = url.substring(optIndex + 1).trim();
      url = url.substring(0, optIndex);
      this.parseOption(optStr);
    }

    // 2. 解析 @ 前缀 → POST 方法, body 在 ? 之后
    if (url.startsWith('@')) {
      this.config.method = 'POST';
      url = url.substring(1);
      const qIdx = url.indexOf('?');
      if (qIdx > 0) {
        this.config.body = url.substring(qIdx + 1);
        url = url.substring(0, qIdx);
      }
    }

    // 3. 解析内联 Header: @Header:{...}@End
    if (url.includes('@Header:')) {
      const hStart = url.indexOf('@Header:');
      const hEnd = url.indexOf('@End', hStart);
      if (hEnd > hStart) {
        const hStr = url.substring(hStart + 8, hEnd);
        url = url.substring(0, hStart) + url.substring(hEnd + 4);
        this.parseHeaders(hStr);
      }
    }

    // 4. 加载书源 headers, 使用单引号→双引号兼容
    this.config.sourceHeaders = this.loadSourceHeaders();

    // 5. 解决相对 URL
    this.config.url = this.encodeUrl(this.resolveUrl(url.trim()));
    if (this.config.method === 'POST' && this.config.body && !this.looksLikeStructuredBody(this.config.body)) {
      this.config.body = this.encodeParams(this.config.body, false);
    }

    return this.config;
  }

  private parseOption(optStr: string): void {
    try {
      const opt = this.parseLooseObject(optStr) || {};
      if (opt['method']) this.config.method = String(opt['method']).toUpperCase();
      if (opt['body'] !== undefined && opt['body'] !== null) {
        this.config.body = typeof opt['body'] === 'string' ? String(opt['body']) : JSON.stringify(opt['body']);
      }
      if (opt['charset']) this.config.charset = String(opt['charset']);
      if (opt['headers']) {
        if (typeof opt['headers'] === 'string') this.config.headers = this.parseHeaderObject(String(opt['headers']));
        else this.config.headers = opt['headers'] as Record<string, string>;
      }
      if (opt['retry'] !== undefined) this.config.retry = Math.max(0, parseInt(String(opt['retry'])) || 0);
      if (opt['type']) this.config.type = String(opt['type']);
      if (opt['webView'] !== undefined) this.config.useWebView = String(opt['webView']).toLowerCase() !== 'false';
      if (opt['webJs']) this.config.webJs = String(opt['webJs']);
    } catch (e) {
      // 正则保底提取
      const m = optStr.match(/['"]?method['"]?\s*:\s*['"]?(\w+)['"]?/i);
      if (m) this.config.method = m[1].toUpperCase();
      const b = optStr.match(/['"]?body['"]?\s*:\s*(['"])([\s\S]*?)\1/i);
      if (b) this.config.body = b[2];
      const c = optStr.match(/['"]?charset['"]?\s*:\s*(['"])([\s\S]*?)\1/i);
      if (c) this.config.charset = c[2];
    }
  }

  private stripLeadingJs(url: string): string {
    let result = url;
    const end = result.lastIndexOf('</js>');
    if (end >= 0) {
      const tail = result.substring(end + 5).trim();
      if (tail) return tail;
      const head = result.substring(0, end);
      const pathWithOption = head.match(/(\/[^"'`;]+,\{[\s\S]*?\})/);
      if (pathWithOption) return pathWithOption[1];
      const path = head.match(/(\/[A-Za-z0-9_./?=&%{}-]+)/);
      if (path) return path[1];
    }
    return result.replace(/<js>[\s\S]*?<\/js>/gi, '').trim();
  }

  private parseHeaders(hdr: string): void {
    const parsed = this.parseHeaderObject(hdr);
    for (const key in parsed) this.config.headers[key] = parsed[key];
  }

  private parseHeaderObject(hdr: string): Record<string, string> {
    const result: Record<string, string> = {};
    const text = (hdr || '').trim();
    if (text.startsWith('{')) {
      try {
        const source = this.parseLooseObject(text) || {};
        for (const key in source) result[key] = String(source[key]);
        return result;
      } catch (_) {}
    }
    for (const line of hdr.split(/[\n\r]+/)) {
      const idx = line.indexOf(':');
      if (idx > 0) {
        result[line.substring(0, idx).trim()] = line.substring(idx + 1).trim();
      }
    }
    return result;
  }

  private loadSourceHeaders(): Record<string, string> {
    if (!this.source?.header) return {};
    try {
      const parsed = this.parseLooseObject(this.source.header);
      if (parsed) {
        const headers: Record<string, string> = {};
        for (const key in parsed) headers[key] = String(parsed[key]);
        return headers;
      }
      const h: Record<string, string> = {};
      for (const line of this.source.header.split(/[\n\r]+/)) {
        const idx = line.indexOf(':');
        if (idx > 0) h[line.substring(0, idx).trim()] = line.substring(idx + 1).trim();
      }
      return h;
    } catch (e) {
      const h: Record<string, string> = {};
      for (const line of this.source.header.split(/[\n\r]+/)) {
        const idx = line.indexOf(':');
        if (idx > 0) h[line.substring(0, idx).trim()] = line.substring(idx + 1).trim();
      }
      return h;
    }
  }

  private resolveUrl(url: string): string {
    if (!url || url.startsWith('http://') || url.startsWith('https://') || url.startsWith('data:')) return url;
    if (/^\/\/[A-Za-z0-9.-]+(?::\d+)?(?:[/?#]|$)/.test(url)) return 'https:' + url;

    const base = this.cleanBaseUrl(this.source?.bookSourceUrl || '');
    if (!base) return url;

    if (url.startsWith('/')) {
      const m = base.match(/^(https?:\/\/[^/]+)/);
      return m ? m[0] + url : base + url;
    }
    const b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    return b + '/' + url;
  }

  private encodeUrl(url: string): string {
    const queryIndex = url.indexOf('?');
    if (queryIndex < 0 || url.startsWith('data:')) return url;
    return url.substring(0, queryIndex) + '?' + this.encodeParams(url.substring(queryIndex + 1), true);
  }

  private encodeParams(params: string, isQuery: boolean): string {
    const charset = (this.config.charset || '').toLowerCase();
    return params.split('&').map(field => {
      const index = field.indexOf('=');
      const key = index < 0 ? field : field.substring(0, index);
      const value = index < 0 ? '' : field.substring(index + 1);
      const encodedKey = this.encodeComponent(key, charset, isQuery);
      return index < 0 ? encodedKey : encodedKey + '=' + this.encodeComponent(value, charset, isQuery);
    }).join('&');
  }

  private encodeComponent(value: string, charset: string, isQuery: boolean): string {
    if (!value) return value;
    if (!charset && this.looksEncoded(value)) return value;
    if (charset === 'escape') return this.escapeComponent(value);
    if (charset && charset !== 'utf-8' && charset !== 'utf8') {
      return this.percentEncode(value, charset, !isQuery);
    }
    try {
      const encoded = encodeURIComponent(charset ? value : this.safeDecode(value));
      return isQuery ? encoded : encoded.replace(/%20/g, '+');
    } catch (_) {
      return value;
    }
  }

  private percentEncode(value: string, charset: string, form: boolean): string {
    try {
      const normalized = charset === 'gbk' || charset === 'gb2312' ? 'gb18030' : charset;
      const bytes = new util.TextEncoder(normalized).encodeInto(value);
      let result = '';
      for (let i = 0; i < bytes.length; i++) {
        const byte = bytes[i];
        const ch = String.fromCharCode(byte);
        if (/[A-Za-z0-9_.~-]/.test(ch) || (form && ch === '*')) result += ch;
        else if (form && ch === ' ') result += '+';
        else result += '%' + byte.toString(16).toUpperCase().padStart(2, '0');
      }
      return result;
    } catch (_) {
      return value;
    }
  }

  private safeDecode(value: string): string {
    if (!this.looksEncoded(value)) return value;
    try { return decodeURIComponent(value.replace(/\+/g, '%20')); } catch (_) { return value; }
  }

  private looksEncoded(value: string): boolean {
    return /%[0-9A-Fa-f]{2}/.test(value) || (!/[\u0080-\uFFFF\s]/.test(value) && value.includes('+'));
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

  private parseLooseObject(text: string): Record<string, Object> | null {
    const value = (text || '').trim();
    if (!value.startsWith('{') || !value.endsWith('}')) return null;
    try {
      return JSON.parse(this.normalizeLooseJson(value)) as Record<string, Object>;
    } catch (_) {
      return null;
    }
  }

  private normalizeLooseJson(text: string): string {
    return (text || '')
      .replace(/[“”]/g, '"')
      .replace(/[‘’]/g, "'")
      .replace(/'((?:\\.|[^'\\])*)'/g, (_: string, body: string) => {
        return JSON.stringify(body.replace(/\\'/g, "'"));
      })
      .replace(/([{,]\s*)([A-Za-z_$][A-Za-z0-9_$-]*)\s*:/g, (_: string, prefix: string, key: string) => {
        return `${prefix}"${key}":`;
      })
      .replace(/,\s*([}\]])/g, '$1');
  }

  private looksLikeStructuredBody(body: string): boolean {
    const value = body.trim();
    return (value.startsWith('{') && value.endsWith('}')) || (value.startsWith('[') && value.endsWith(']')) ||
      value.startsWith('<?xml') || value.startsWith('<');
  }

  private cleanBaseUrl(url: string): string {
    const i = url.indexOf('##');
    return i >= 0 ? url.substring(0, i) : url;
  }

  buildRequest(): HttpRequest {
    const merged = { ...this.config.sourceHeaders, ...this.config.headers };
    if (this.source && !merged['Cookie']) {
      const cookie = VerificationSupport.sourceCookieHeader(this.source, this.config.url);
      if (cookie) merged['Cookie'] = cookie;
    }
    if (this.config.method === 'POST' && this.config.body && !this.findHeader(merged, 'content-type')) {
      merged['Content-Type'] = this.looksLikeStructuredBody(this.config.body) && this.config.body.trim().startsWith('{') ?
        'application/json; charset=utf-8' : 'application/x-www-form-urlencoded';
    }
    return {
      url: this.config.url,
      method: this.config.method,
      headers: merged,
      body: this.config.body,
      charset: this.config.charset
    };
  }

  async fetch(urlTemplate: string, maxResponseBytes?: number): Promise<HttpResponse> {
    this.parse(urlTemplate);
    const req = this.buildRequest();
    if (maxResponseBytes !== undefined) {
      req.maxResponseBytes = maxResponseBytes;
    }
    if (!req.url) {
      return { url: urlTemplate, statusCode: 0, headers: {}, body: '', success: false, error: 'empty url' };
    }
    if (req.url.startsWith('data:')) return this.decodeDataUrl(req.url);
    const resp = await this.fetchWithRetry(req);
    if (this.isUsableResponse(resp)) return resp;

    const fallbackUrls = this.buildFallbackUrls(req.url);
    for (const url of fallbackUrls) {
      const fallbackResp = await this.fetchWithRetry({ ...req, url: url });
      if (this.isUsableResponse(fallbackResp)) {
        return fallbackResp;
      }
    }
    return resp;
  }

  private async fetchWithRetry(req: HttpRequest): Promise<HttpResponse> {
    let response = await this.fetchFollowingRedirects(req);
    for (let i = 0; i < this.config.retry && !this.isUsableResponse(response); i++) {
      response = await this.fetchFollowingRedirects(req);
    }
    return response;
  }

  private decodeDataUrl(url: string): HttpResponse {
    try {
      const comma = url.indexOf(',');
      if (comma < 0) throw new Error('invalid data url');
      const meta = url.substring(5, comma);
      const payload = url.substring(comma + 1);
      let body = '';
      if (/;base64(?:;|$)/i.test(meta)) {
        const bytes = new util.Base64Helper().decodeSync(payload);
        body = util.TextDecoder.create('utf-8').decodeWithStream(bytes, { stream: false });
      } else {
        body = decodeURIComponent(payload);
      }
      return { url: url, statusCode: 200, headers: { 'Content-Type': meta }, body: body, success: true };
    } catch (e) {
      return { url: url, statusCode: 0, headers: {}, body: '', success: false, error: String(e) };
    }
  }

  private async fetchFollowingRedirects(req: HttpRequest): Promise<HttpResponse> {
    let currentReq = req;
    let lastResp = await this.client.execute(currentReq);
    for (let i = 0; i < 3; i++) {
      if (lastResp.statusCode < 300 || lastResp.statusCode >= 400) return lastResp;
      const location = this.findHeader(lastResp.headers, 'location');
      if (!location) return lastResp;
      const nextUrl = this.resolveRedirectUrl(location, currentReq.url);
      if (!nextUrl || nextUrl === currentReq.url) return lastResp;
      const switchToGet = (lastResp.statusCode === 301 || lastResp.statusCode === 302 || lastResp.statusCode === 303) &&
        currentReq.method.toUpperCase() !== 'GET' && currentReq.method.toUpperCase() !== 'HEAD';
      currentReq = switchToGet ? { ...currentReq, url: nextUrl, method: 'GET', body: '' } : { ...currentReq, url: nextUrl };
      lastResp = await this.client.execute(currentReq);
    }
    return lastResp;
  }

  private findHeader(headers: Record<string, string>, name: string): string {
    const lower = name.toLowerCase();
    for (const key in headers) {
      if (key.toLowerCase() === lower) return String(headers[key] || '');
    }
    return '';
  }

  private resolveRedirectUrl(location: string, baseUrl: string): string {
    const value = (location || '').trim();
    if (!value) return '';
    if (value.startsWith('http://') || value.startsWith('https://')) return value;
    if (value.startsWith('//')) return 'https:' + value;
    const base = this.cleanBaseUrl(baseUrl);
    const origin = base.match(/^(https?:\/\/[^/]+)/);
    if (value.startsWith('/')) return origin ? origin[1] + value : value;
    const qIndex = base.indexOf('?');
    const clean = qIndex >= 0 ? base.substring(0, qIndex) : base;
    const dir = clean.endsWith('/') ? clean : clean.replace(/\/[^/]*$/, '/');
    return dir + value;
  }

  getConfig(): UrlConfig {
    return this.config;
  }

  private emptyConfig(url: string): UrlConfig {
    return {
      url: url, method: 'GET', body: '', charset: '', headers: {}, sourceHeaders: {},
      retry: 0, type: '', useWebView: false, webJs: ''
    };
  }

  private findOptionIndex(value: string): number {
    let quote = '';
    let brace = 0;
    for (let i = 0; i < value.length - 1; i++) {
      const ch = value.charAt(i);
      if (quote) {
        if (ch === quote && value.charAt(i - 1) !== '\\') quote = '';
        continue;
      }
      if (ch === '"' || ch === "'") { quote = ch; continue; }
      if (ch === '{') brace++;
      if (ch === '}') brace--;
      if (ch === ',' && brace === 0 && /^\s*\{/.test(value.substring(i + 1))) return i;
    }
    return -1;
  }

  private buildFallbackUrls(url: string): string[] {
    const urls: string[] = [];
    if (!url.startsWith('http://') && !url.startsWith('https://')) return urls;

    if (url.startsWith('https://')) {
      urls.push('http://' + url.substring('https://'.length));
    }

    const mirror = url.replace(/^(https?:\/\/)www\.([^/]+)/, (_: string, scheme: string, host: string) => {
      return `${scheme}www.x${host}`;
    });
    if (mirror !== url && !urls.includes(mirror)) urls.push(mirror);

    if (mirror.startsWith('https://')) {
      const httpMirror = 'http://' + mirror.substring('https://'.length);
      if (!urls.includes(httpMirror)) urls.push(httpMirror);
    }
    return urls;
  }

  private isUsableResponse(resp: HttpResponse): boolean {
    if (!resp.success || !resp.body) return false;
    if (resp.statusCode >= 300 && resp.statusCode < 400) return false;
    const sample = resp.body.substring(0, Math.min(resp.body.length, 1200)).toLowerCase();
    if (sample.includes('301 moved permanently') || sample.includes('302 found')) return false;
    if (sample.includes('sedoparking.com') || sample.includes('resources and information')) return false;
    return true;
  }
}
