import { BookSource } from '../../model/data/Book';
import { HttpClient, HttpRequest, HttpResponse } from '../http/HttpClient';
import { VerificationSupport } from '../http/VerificationSupport';

export interface UrlConfig {
  url: string;
  method: string;
  body: string;
  charset: string;
  headers: Record<string, string>;
  sourceHeaders: Record<string, string>;
}

export class AnalyzeUrl {
  private config: UrlConfig;
  private source: BookSource | null;
  private client: HttpClient;

  constructor(source: BookSource | null, client: HttpClient) {
    this.source = source;
    this.client = client;
    this.config = { url: '', method: 'GET', body: '', charset: '', headers: {}, sourceHeaders: {} };
  }

  parse(urlTemplate: string): UrlConfig {
    this.config = { url: urlTemplate, method: 'GET', body: '', charset: '', headers: {}, sourceHeaders: {} };
    if (!urlTemplate) return this.config;

    let url = urlTemplate.trim();
    url = this.stripLeadingJs(url);

    // 1. 解析 URL 选项 JSON: url,{"method":"POST","body":"...","headers":{...}}
    const optIndex = url.indexOf(',{');
    if (optIndex > 0) {
      const optStr = url.substring(optIndex + 1);
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
    this.config.url = this.resolveUrl(url.trim());

    return this.config;
  }

  private parseOption(optStr: string): void {
    try {
      const opt = JSON.parse(optStr.replace(/'/g, '"')) as Record<string, Object>;
      if (opt['method']) this.config.method = String(opt['method']).toUpperCase();
      if (opt['body']) this.config.body = String(opt['body']);
      if (opt['charset']) this.config.charset = String(opt['charset']);
      if (opt['headers']) this.config.headers = opt['headers'] as Record<string, string>;
    } catch (e) {
      // 正则保底提取
      const m = optStr.match(/"method"\s*:\s*"(\w+)"/);
      if (m) this.config.method = m[1].toUpperCase();
      const b = optStr.match(/"body"\s*:\s*"([^"]*)"/);
      if (b) this.config.body = b[1];
      const c = optStr.match(/"charset"\s*:\s*"([^"]*)"/);
      if (c) this.config.charset = c[1];
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
    for (const line of hdr.split(/[\n\r]+/)) {
      const idx = line.indexOf(':');
      if (idx > 0) {
        this.config.headers[line.substring(0, idx).trim()] = line.substring(idx + 1).trim();
      }
    }
  }

  private loadSourceHeaders(): Record<string, string> {
    if (!this.source?.header) return {};
    try {
      return JSON.parse(this.source.header.replace(/'/g, '"')) as Record<string, string>;
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
    if (this.config.method === 'POST' && this.config.body && !merged['Content-Type']) {
      merged['Content-Type'] = 'application/x-www-form-urlencoded';
    }
    return {
      url: this.config.url,
      method: this.config.method,
      headers: merged,
      body: this.config.body,
      charset: this.config.charset
    };
  }

  async fetch(urlTemplate: string): Promise<HttpResponse> {
    this.parse(urlTemplate);
    const req = this.buildRequest();
    if (!req.url) {
      return { url: urlTemplate, statusCode: 0, headers: {}, body: '', success: false, error: 'empty url' };
    }
    const resp = await this.fetchFollowingRedirects(req);
    if (this.isUsableResponse(resp)) return resp;

    const fallbackUrls = this.buildFallbackUrls(req.url);
    for (const url of fallbackUrls) {
      const fallbackResp = await this.fetchFollowingRedirects({ ...req, url: url });
      if (this.isUsableResponse(fallbackResp)) {
        return fallbackResp;
      }
    }
    return resp;
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
      currentReq = { ...currentReq, url: nextUrl };
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
