import { BookSource } from '../../model/data/Book';
import { HttpClient, HttpRequest, HttpResponse } from '../http/HttpClient';

export interface UrlConfig {
  url: string;
  method: string;
  body: string;
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
    this.config = { url: '', method: 'GET', body: '', headers: {}, sourceHeaders: {} };
  }

  parse(urlTemplate: string): UrlConfig {
    this.config = { url: urlTemplate, method: 'GET', body: '', headers: {}, sourceHeaders: {} };
    if (!urlTemplate) return this.config;

    let url = urlTemplate.trim();

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
      if (opt['headers']) this.config.headers = opt['headers'] as Record<string, string>;
    } catch (e) {
      // 正则保底提取
      const m = optStr.match(/"method"\s*:\s*"(\w+)"/);
      if (m) this.config.method = m[1].toUpperCase();
      const b = optStr.match(/"body"\s*:\s*"([^"]*)"/);
      if (b) this.config.body = b[1];
    }
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
    if (url.startsWith('//')) return 'https:' + url;

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
    if (this.config.method === 'POST' && this.config.body && !merged['Content-Type']) {
      merged['Content-Type'] = 'application/x-www-form-urlencoded';
    }
    return {
      url: this.config.url,
      method: this.config.method,
      headers: merged,
      body: this.config.body
    };
  }

  async fetch(urlTemplate: string): Promise<HttpResponse> {
    this.parse(urlTemplate);
    const req = this.buildRequest();
    if (!req.url) {
      return { url: urlTemplate, statusCode: 0, headers: {}, body: '', success: false, error: 'empty url' };
    }
    return this.client.execute(req);
  }

  getConfig(): UrlConfig {
    return this.config;
  }
}