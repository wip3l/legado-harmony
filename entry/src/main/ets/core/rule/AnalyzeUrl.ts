import { BookSource } from '../../model/data/Book';
import { HttpClient, HttpRequest, HttpResponse } from '../http/HttpClient';
import { VerificationSupport } from '../http/VerificationSupport';
import { RequestSessionConfig, RequestSessionSupport } from '../http/RequestSessionSupport';
import { BookSourceRateLimiter } from '../http/BookSourceRateLimiter';
import { util } from '@kit.ArkTS';
import { BookSourceDebugContext } from '../book/BookSourceDebugModels';
import { BookSourceHeaderRuntime } from '../book/BookSourceHeaderRuntime';

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
  bodyJs: string;
  rawBody: boolean;
  session: RequestSessionConfig;
}

export class AnalyzeUrl {
  private config: UrlConfig;
  private source: BookSource | null;
  private client: HttpClient;
  private runtimeSourceHeaders: Record<string, string>;
  private noTimeoutRetry: boolean = false;

  constructor(source: BookSource | null, client: HttpClient,
    runtimeSourceHeaders: Record<string, string> = {}) {
    this.source = source;
    this.client = client;
    this.runtimeSourceHeaders = runtimeSourceHeaders;
    this.config = this.emptyConfig('');
  }

  /** Marks bridge-issued requests to skip the doubled-timeout idempotent retry. */
  setNoTimeoutRetry(value: boolean): AnalyzeUrl {
    this.noTimeoutRetry = value;
    return this;
  }

  parse(urlTemplate: string): UrlConfig {
    this.config = this.emptyConfig(urlTemplate);
    if (!urlTemplate) return this.config;

    let url = urlTemplate.trim();
    url = this.stripLeadingJs(url);

    // 1. 解析 URL 选项 JSON: url,{"method":"POST","body":"...","headers":{...}}
    // Everything after the first comma in a data URL is payload. In particular, source rules may
    // append their own metadata object after a base64 payload and consume it in a later rule stage.
    // Treating that object as HTTP request options strips source-owned data before the rule runs.
    const optIndex = url.startsWith('data:') ? -1 : this.findOptionIndex(url);
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

    // 4. 解决相对 URL
    this.config.url = this.encodeUrl(this.resolveUrl(url.trim()));
    // 5. 动态登录 Header 必须按目标站点限定作用域，避免覆盖第三方站点自己的 Cookie。
    this.config.sourceHeaders = this.loadSourceHeaders(this.config.url);
    if (this.config.method === 'POST' && this.config.body && !this.config.rawBody &&
      !this.looksLikeStructuredBody(this.config.body)) {
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
      // Some Legado-compatible sources use a harmless placeholder URL and produce the actual
      // response body in a post-request script.  Keep that script as source-owned data; the
      // coordinator executes it in the same bounded runtime used by the other rule stages.
      if (opt['bodyJs']) this.config.bodyJs = String(opt['bodyJs']);
      if (opt['rawBody'] !== undefined) this.config.rawBody = String(opt['rawBody']).toLowerCase() !== 'false';
      if (opt['session'] !== undefined) this.config.session = RequestSessionSupport.parseConfig(opt['session']);
    } catch (e) {
      // 正则保底提取
      const m = optStr.match(/['"]?method['"]?\s*:\s*['"]?(\w+)['"]?/i);
      if (m) this.config.method = m[1].toUpperCase();
      const b = optStr.match(/['"]?body['"]?\s*:\s*(['"])([\s\S]*?)\1/i);
      if (b) this.config.body = b[2];
      const c = optStr.match(/['"]?charset['"]?\s*:\s*(['"])([\s\S]*?)\1/i);
      if (c) this.config.charset = c[2];
      const bodyJs = optStr.match(/['"]?bodyJs['"]?\s*:\s*(['"])([\s\S]*?)\1/i);
      if (bodyJs) this.config.bodyJs = bodyJs[2];
      const rawBody = optStr.match(/['"]?rawBody['"]?\s*:\s*(true|false)/i);
      if (rawBody) this.config.rawBody = rawBody[1].toLowerCase() === 'true';
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

  private loadSourceHeaders(requestUrl: string = ''): Record<string, string> {
    const headers: Record<string, string> = {};
    if (!this.source) return headers;
    this.mergeSourceHeaderText(headers, this.source.header || '');
    // Legado login scripts persist dynamic authentication headers separately from the source's
    // static header. They must participate in every normal AnalyzeUrl request; otherwise login
    // validation can succeed inside the script while the following AJAX request is anonymous.
    if (this.shouldApplyLoginHeaders(requestUrl)) {
      this.mergeSourceHeaderText(headers, this.source.loginHeader || '');
    }
    // Complex source scripts can compute their header rule using functions from jsLib and the
    // current login state. The bounded stage runtime evaluates that source-owned expression and
    // passes only its scalar result here. Runtime headers are source-site scoped: a dynamic
    // Cookie/Referer must not reach third-party hosts. URL-local explicit headers still win.
    if (this.isTrustedRequestHost(requestUrl)) {
      for (const key of Object.keys(this.runtimeSourceHeaders)) {
        const name = String(key || '').trim();
        if (name) headers[name] = String(this.runtimeSourceHeaders[key] || '');
      }
    }
    return headers;
  }

  private shouldApplyLoginHeaders(requestUrl: string): boolean {
    if (!this.source || !this.source.loginHeader) return false;
    return this.isTrustedRequestHost(requestUrl);
  }

  /**
   * Source-owned dynamic headers (login header, runtime-evaluated @js: header rule) may only be
   * sent to the source's own hosts. Third-party hosts reached through the same source (content
   * proxies, image CDNs) must not receive the source's credentials.
   */
  private isTrustedRequestHost(requestUrl: string): boolean {
    if (!this.source) return false;
    const requestHost = this.urlHost(requestUrl);
    if (!requestHost) return true;
    const trustedUrls: string[] = [this.source.bookSourceUrl || '', this.source.loginUrl || ''];
    try {
      const loginInfo = JSON.parse(this.source.loginInfo || '{}') as Record<string, Object>;
      const rawRuntime = loginInfo['__legadoHarmonyRuntime'];
      let runtime: Record<string, Object> = {};
      if (typeof rawRuntime === 'string') {
        runtime = JSON.parse(rawRuntime || '{}') as Record<string, Object>;
      } else if (rawRuntime && typeof rawRuntime === 'object' && !Array.isArray(rawRuntime)) {
        runtime = rawRuntime as Record<string, Object>;
      }
      const rawSource = runtime['source'];
      if (rawSource && typeof rawSource === 'object' && !Array.isArray(rawSource)) {
        const sourceState = rawSource as Record<string, Object>;
        for (const key of Object.keys(sourceState)) {
          const value = String(sourceState[key] || '');
          if (/^https?:\/\//i.test(value)) trustedUrls.push(value);
        }
      }
    } catch (_) {
    }
    for (const trustedUrl of trustedUrls) {
      const trustedHost = this.urlHost(trustedUrl);
      if (trustedHost && this.hostsShareSite(requestHost, trustedHost)) return true;
    }
    return false;
  }

  private urlHost(url: string): string {
    const match = /^https?:\/\/([^/:?#]+)/i.exec((url || '').trim());
    return match && match[1] ? match[1].toLowerCase() : '';
  }

  private hostsShareSite(first: string, second: string): boolean {
    if (!first || !second) return false;
    if (first === second || first.endsWith(`.${second}`) || second.endsWith(`.${first}`)) return true;
    return this.siteKey(first) === this.siteKey(second);
  }

  private siteKey(host: string): string {
    const value = (host || '').toLowerCase();
    if (!value || /^\d+(?:\.\d+){3}$/.test(value) || value === 'localhost') return value;
    const labels = value.split('.').filter((item: string): boolean => item.length > 0);
    if (labels.length <= 2) return value;
    const suffix = labels.slice(-2).join('.');
    const multiLevelSuffix = /^(?:com|net|org|gov|edu)\.cn$|^(?:com|net|org)\.hk$|^co\.(?:uk|jp|kr|nz)$|^com\.au$/;
    return labels.slice(multiLevelSuffix.test(suffix) ? -3 : -2).join('.');
  }

  private mergeSourceHeaderText(target: Record<string, string>, raw: string): void {
    const text = (raw || '').trim();
    if (!text) return;
    // Legado permits a header rule such as `@js: JSON.stringify({...})`. Most imported sources
    // use that form only to combine literal credentials with the WebView user agent. Resolve that
    // safe, declarative subset here so every native request receives the same headers; arbitrary
    // source JavaScript remains in the bounded stage runtime.
    if (/^@?js\s*:/i.test(text)) {
      const property = /["']([^"']+)["']\s*:\s*(?:(["'])((?:\\.|(?!\2)[\s\S])*?)\2|java\.getWebViewUA\s*\(\s*\))/g;
      let match: RegExpExecArray | null;
      let found = false;
      while ((match = property.exec(text)) !== null) {
        const name = (match[1] || '').trim();
        if (!name) continue;
        let value = match[3] || '';
        if (!match[2]) {
          value = 'Mozilla/5.0 (Linux; HarmonyOS) AppleWebKit/537.36 Mobile Safari/537.36';
        } else {
          value = value.replace(/\\([\\"'])/g, '$1');
        }
        target[name] = value;
        found = true;
      }
      if (found) return;
    }
    try {
      const parsed = this.parseLooseObject(text);
      if (parsed) {
        for (const key in parsed) target[key] = String(parsed[key]);
        return;
      }
    } catch (_) {}
    // A raw access token or query fragment is not a header block. Only accept the traditional
    // multi-line "Name: value" representation when a real header separator is present.
    for (const line of text.split(/[\n\r]+/)) {
      const idx = line.indexOf(':');
      if (idx <= 0) continue;
      const name = line.substring(0, idx).trim();
      if (name && /^[A-Za-z0-9-]+$/.test(name)) target[name] = line.substring(idx + 1).trim();
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
      // SearchCoordinator keeps the historical Legado behavior of exposing {{key}}
      // as an UTF-8 percent-encoded value. Legacy sites that declare GBK/GB2312
      // must decode that intermediate value before applying their own charset,
      // otherwise "%E6..." is sent literally and the site returns an empty result.
      return this.percentEncode(this.safeDecode(value), charset, !isQuery);
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
      // Preserve valid JSON verbatim. Rewriting single-quoted fragments first can corrupt a
      // double-quoted JavaScript option whose body legitimately contains apostrophes.
      return JSON.parse(value) as Record<string, Object>;
    } catch (_) {}
    try { return JSON.parse(this.normalizeLooseJson(value)) as Record<string, Object>; } catch (_) { return null; }
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
    const cookieHeaderName = this.headerName(merged, 'cookie');
    if (this.source && this.source.enabledCookieJar !== false && !cookieHeaderName) {
      const cookie = VerificationSupport.sourceCookieHeader(this.source, this.config.url);
      if (cookie) merged['Cookie'] = cookie;
    }
    RequestSessionSupport.apply(this.config.url, merged, this.config.session);
    if (this.config.method === 'POST' && this.config.body && !this.findHeader(merged, 'content-type')) {
      merged['Content-Type'] = this.looksLikeStructuredBody(this.config.body) && this.config.body.trim().startsWith('{') ?
        'application/json; charset=utf-8' : 'application/x-www-form-urlencoded';
    }
    const request: HttpRequest = {
      url: this.config.url,
      method: this.config.method,
      headers: merged,
      body: this.config.body,
      charset: this.config.charset,
      useCookieJar: this.source ? this.source.enabledCookieJar !== false : true,
      useWebView: this.config.useWebView,
      webJs: this.config.webJs || undefined,
      noTimeoutRetry: this.noTimeoutRetry || undefined
    };
    if (this.config.rawBody && this.config.body) {
      const charset = this.normalizeCharset(this.config.charset || 'utf-8');
      request.bodyBytes = new util.TextEncoder(charset).encodeInto(this.config.body).buffer as ArrayBuffer;
    }
    return request;
  }

  async fetch(urlTemplate: string, maxResponseBytes?: number,
    debugContext: BookSourceDebugContext | null = null): Promise<HttpResponse> {
    // A `@js:` header rule may compute dynamic values (Referer/Origin/Cookie from source state).
    // Resolve the complete header map before parsing so those values can join the request; the
    // result is cached per source+variable and still scoped per host in loadSourceHeaders().
    if (this.source && /^@?js\s*:/i.test((this.source.header || '').trim())) {
      this.runtimeSourceHeaders = await BookSourceHeaderRuntime.resolve(this.source);
    }
    this.parse(urlTemplate);
    const req = this.buildRequest();
    if (maxResponseBytes !== undefined) {
      req.maxResponseBytes = maxResponseBytes;
    }
    req.debugContext = debugContext || undefined;
    if (!req.url) {
      return { url: urlTemplate, statusCode: 0, headers: {}, body: '', success: false, error: 'empty url' };
    }
    if (req.url.startsWith('data:')) return this.decodeDataUrl(req.url, maxResponseBytes);
    const resp = await this.fetchWithRetry(req);
    if (this.isUsableResponse(resp)) return resp;

    // A small group of IIS/legacy hosts intermittently fail before HarmonyOS Network Kit can
    // produce an HTTP response (for example 2300003/2300056/2300999). The same URL remains
    // reachable from ArkWeb because it uses the browser network stack. Keep native HTTP as the
    // fast default and retry only safe, body-less reads through the already isolated WebView
    // fetch host. This is destination-agnostic and preserves the source's URL, headers and cookie
    // scope exactly; normal HTTP status failures are never hidden by the fallback.
    if (this.shouldRetryWithWebView(req, resp)) {
      console.info('[AnalyzeUrl] native transport failed; retrying with WebView:', this.urlHost(req.url));
      const webResponse = await this.client.execute({ ...req, useWebView: true });
      if (this.isUsableResponse(webResponse)) return webResponse;
    }

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

  private decodeDataUrl(url: string, maxResponseBytes?: number): HttpResponse {
    try {
      const comma = url.indexOf(',');
      if (comma < 0) throw new Error('invalid data url');
      const meta = url.substring(5, comma);
      const rawPayload = url.substring(comma + 1);
      // Legado permits an optional request/options object after a base64 data payload, for example:
      // data:;base64,<payload>,{"type":"..."}.  That object belongs to the source rule and is not
      // part of the base64 body.  Decode only the source-supplied payload so data URLs can travel
      // through the ordinary rule pipeline without any site-specific interpretation here.
      const base64 = /;base64(?:;|$)/i.test(meta);
      const optionIndex = base64 ? rawPayload.indexOf(',') : -1;
      const payload = optionIndex >= 0 ? rawPayload.substring(0, optionIndex) : rawPayload;
      if (maxResponseBytes && this.estimatedDataUrlBytes(payload, base64) > maxResponseBytes) {
        return {
          url: url, statusCode: 0, headers: { 'Content-Type': meta }, body: '', success: false,
          error: `response too large: >${maxResponseBytes}`
        };
      }
      let body = '';
      if (base64) {
        const bytes = new util.Base64Helper().decodeSync(payload);
        if (optionIndex >= 0) {
          // Legado's synthetic data URL form appends a source-owned options object. Its rule
          // pipeline exposes the decoded bytes as a hexadecimal string, which the following
          // user rule commonly consumes with java.hexDecodeToString(result). Standard data URLs
          // without that object retain normal UTF-8 semantics.
          for (let index = 0; index < bytes.length; index++) {
            body += Number(bytes[index]).toString(16).padStart(2, '0');
          }
        } else {
          body = util.TextDecoder.create('utf-8').decodeWithStream(bytes, { stream: false });
        }
      } else {
        body = decodeURIComponent(payload);
      }
      return { url: url, statusCode: 200, headers: { 'Content-Type': meta }, body: body, success: true };
    } catch (e) {
      return { url: url, statusCode: 0, headers: {}, body: '', success: false, error: String(e) };
    }
  }

  private headerName(headers: Record<string, string>, name: string): string {
    const lower = (name || '').toLowerCase();
    for (const key of Object.keys(headers)) {
      if (key.toLowerCase() === lower) return key;
    }
    return '';
  }

  private estimatedDataUrlBytes(payload: string, base64: boolean): number {
    if (base64) {
      const cleanLength = payload.replace(/\s/g, '').length;
      return Math.ceil(cleanLength * 3 / 4);
    }
    return payload.length;
  }

  private async fetchFollowingRedirects(req: HttpRequest): Promise<HttpResponse> {
    let currentReq = req;
    await BookSourceRateLimiter.acquire(this.source);
    let lastResp = await this.client.execute(currentReq);
    for (let i = 0; i < 3; i++) {
      if (lastResp.statusCode < 300 || lastResp.statusCode >= 400) return lastResp;
      const location = this.findHeader(lastResp.headers, 'location');
      if (!location) return lastResp;
      const nextUrl = this.resolveRedirectUrl(location, currentReq.url);
      if (!nextUrl || nextUrl === currentReq.url) return lastResp;
      const switchToGet = (lastResp.statusCode === 301 || lastResp.statusCode === 302 || lastResp.statusCode === 303) &&
        currentReq.method.toUpperCase() !== 'GET' && currentReq.method.toUpperCase() !== 'HEAD';
      const redirectHeaders = this.headersForRedirect(currentReq.headers, currentReq.url, nextUrl);
      currentReq = switchToGet ?
        { ...currentReq, url: nextUrl, method: 'GET', body: '', headers: redirectHeaders } :
        { ...currentReq, url: nextUrl, headers: redirectHeaders };
      await BookSourceRateLimiter.acquire(this.source);
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
      retry: 0, type: '', useWebView: false, webJs: '', bodyJs: '', rawBody: false,
      session: RequestSessionSupport.emptyConfig()
    };
  }

  private headersForRedirect(headers: Record<string, string>, fromUrl: string,
    toUrl: string): Record<string, string> {
    if (this.urlHost(fromUrl) === this.urlHost(toUrl)) return { ...headers };
    const result: Record<string, string> = {};
    const destinationScoped = ['cookie', 'authorization', 'proxy-authorization', 'host', 'origin', 'referer'];
    for (const key of Object.keys(headers || {})) {
      if (!destinationScoped.includes(key.toLowerCase())) result[key] = headers[key];
    }
    return result;
  }

  private normalizeCharset(charset: string): string {
    const value = (charset || '').toLowerCase().replace(/["']/g, '').trim();
    if (value === 'gbk' || value === 'gb2312') return 'gb18030';
    return value || 'utf-8';
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
    // A reader must not invent mirrors or silently downgrade HTTPS.  Alternate endpoints are
    // executed only when the imported source explicitly declares them in its own rule/script.
    return [];
  }

  private shouldRetryWithWebView(req: HttpRequest, resp: HttpResponse): boolean {
    if (req.useWebView || resp.statusCode !== 0 || !/^https?:\/\//i.test(req.url || '')) return false;
    const method = (req.method || 'GET').toUpperCase();
    if (method !== 'GET' && method !== 'HEAD') return false;
    const error = String(resp.error || '');
    return /2300056|2300999|curl(?:_|\s*)code\s*(?:result\s*)?[=:]?\s*(?:35|56)\b|connection\s+reset|failed\s+to\s+receive\s+data|ssl\s+connect/i.test(error);
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
