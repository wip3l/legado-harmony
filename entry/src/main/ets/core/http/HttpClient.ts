import http from '@ohos.net.http';
import { util } from '@kit.ArkTS';
import { CookieStore } from './CookieStore';
import { TlsTrustStore } from './TlsTrustStore';
import { WebBookFetchRuntime } from '../book/WebBookFetchRuntime';
import { BookSourceDebugContext, BookSourceDebugNetworkTrace } from '../book/BookSourceDebugModels';

export interface HttpRequest {
  url: string;
  method: string;
  headers: Record<string, string>;
  body?: string;
  bodyBytes?: ArrayBuffer;
  charset?: string;
  useCookieJar?: boolean;
  connectTimeout?: number;
  readTimeout?: number;
  contentType?: string;
  maxResponseBytes?: number;
  useWebView?: boolean;
  webJs?: string;
  debugContext?: BookSourceDebugContext;
  // Script-bridge requests run inside a serial runtime: a hung request stalls every queued
  // task, so the doubled-timeout idempotent retry is skipped for them (caller re-runs instead).
  noTimeoutRetry?: boolean;
}

export interface HttpResponse {
  url: string;
  statusCode: number;
  headers: Record<string, string>;
  body: string;
  success: boolean;
  error?: string;
}

export interface HttpBinaryResponse {
  url: string;
  statusCode: number;
  headers: Record<string, string>;
  data: Uint8Array;
  success: boolean;
  error?: string;
}

export class HttpClient {
  private timeout: number;
  private activeClients: Set<http.HttpRequest> = new Set<http.HttpRequest>();
  private defaultHeaders: Record<string, string> = {
    'User-Agent': 'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': '*/*',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    'Connection': 'keep-alive'
  };

  constructor(timeout: number = 8000) {
    this.timeout = timeout;
  }

  async execute(req: HttpRequest): Promise<HttpResponse> {
    const startedAt = Date.now();
    let response: HttpResponse;
    try {
      response = await this.executeInternal(req);
    } catch (error) {
      response = { url: req.url || '', statusCode: 0, headers: {}, body: '', success: false,
        error: error instanceof Error ? error.message : String(error || 'network error') };
    }
    if (req.debugContext) {
      const trace = new BookSourceDebugNetworkTrace();
      trace.method = req.method || 'GET';
      trace.url = req.url || '';
      trace.finalUrl = response.url || req.url || '';
      trace.statusCode = response.statusCode || 0;
      trace.responseBytes = response.body ? response.body.length : 0;
      trace.bodyPreview = response.body || '';
      trace.elapsedMs = Math.max(0, Date.now() - startedAt);
      trace.error = response.success ? '' : (response.error || 'request failed');
      req.debugContext.addNetwork(trace);
    }
    return response;
  }

  private async executeInternal(req: HttpRequest): Promise<HttpResponse> {
    if (!req.url || req.url.trim() === '') {
      return { url: '', statusCode: 0, headers: {}, body: '', success: false, error: 'empty url' };
    }
    if (req.useWebView) {
      const runtime = WebBookFetchRuntime.get();
      // Only wait for the hidden ArkWeb host to attach. A busy host is healthy: fetch() queues
      // subsequent requests and runs them in order instead of misreporting it as "not ready".
      const attached = await runtime.waitUntilAttached(8000);
      if (!attached) {
        return { url: req.url, statusCode: 0, headers: {}, body: '', success: false,
          error: 'WebView 抓取环境未挂载，请重新进入当前页面' };
      }
      return await runtime.fetch({
        url: req.url,
        method: req.method,
        headers: { ...this.defaultHeaders, ...req.headers },
        body: req.body,
        webJs: req.webJs,
        timeoutMs: Math.max(req.connectTimeout || 0, req.readTimeout || 0, this.timeout),
        maxResponseBytes: req.maxResponseBytes
      });
    }
    const response = await this.executeWithProtocol(req, false);
    if (!response.success && this.shouldRetryWithHttp1(req.url, response.error || '')) {
      console.info('[HttpClient] HTTP/2 failed; retrying once with HTTP/1.1:', this.hostForLog(req.url));
      return await this.executeWithProtocol(req, true);
    }
    if (!response.success && !req.noTimeoutRetry && this.shouldRetryTimeout(req, response.error || '')) {
      const retryTimeout = Math.min(30000, Math.max(this.timeout * 2, 15000));
      console.info('[HttpClient] idempotent request timed out; retrying once:', this.hostForLog(req.url));
      return await this.executeWithProtocol({
        ...req,
        connectTimeout: Math.max(req.connectTimeout || 0, retryTimeout),
        readTimeout: Math.max(req.readTimeout || 0, retryTimeout)
      }, true);
    }
    return response;
  }

  private async executeWithProtocol(req: HttpRequest, forceHttp1: boolean): Promise<HttpResponse> {
    const client = http.createHttp();
    this.activeClients.add(client);
    let responseTooLarge = false;
    try {
      const method = this.resolveMethod(req.method);
      const headers: Record<string, string> = { ...this.defaultHeaders, ...req.headers };
      const requestData = this.requestData(req);
      const cookie = req.useCookieJar === false ? '' : CookieStore.getCookie(req.url);
      if (cookie && !headers['Cookie']) {
        headers['Cookie'] = cookie;
      }
      const maxResponseBytes = req.maxResponseBytes || 0;
      if (maxResponseBytes > 0) {
        const chunks: ArrayBuffer[] = [];
        let receivedBytes = 0;
        let streamedHeaders: Record<string, string> = {};
        const onHeadersReceive = (value: Object): void => {
          streamedHeaders = (value || {}) as Record<string, string>;
          const contentLength = Number(this.findHeader(streamedHeaders, 'content-length') || '0');
          if (contentLength > maxResponseBytes) {
            responseTooLarge = true;
            client.destroy();
          }
        };
        const onDataReceive = (chunk: ArrayBuffer): void => {
          if (responseTooLarge) return;
          receivedBytes += chunk.byteLength;
          if (receivedBytes > maxResponseBytes) {
            responseTooLarge = true;
            chunks.length = 0;
            client.destroy();
            return;
          }
          chunks.push(chunk);
        };
        client.on('headersReceive', onHeadersReceive);
        client.on('dataReceive', onDataReceive);
        let responseCode = 0;
        let streamError = '';
        try {
          const options: http.HttpRequestOptions = {
            method: method,
            header: headers,
            extraData: requestData,
            connectTimeout: req.connectTimeout || this.timeout,
            readTimeout: req.readTimeout || this.timeout
          };
          this.applyTlsTrust(options, req.url);
          if (forceHttp1) options.usingProtocol = http.HttpProtocol.HTTP1_1;
          responseCode = await client.requestInStream(req.url, options);
        } catch (error) {
          streamError = this.decorateTlsError(req.url, this.describeError(error as Object));
        } finally {
          client.off('headersReceive', onHeadersReceive);
          client.off('dataReceive', onDataReceive);
        }
        if (responseTooLarge) {
          return {
            url: req.url,
            statusCode: responseCode,
            headers: streamedHeaders,
            body: '',
            success: false,
            error: `response too large: >${maxResponseBytes}`
          };
        }
        const result = this.mergeArrayBuffers(chunks, receivedBytes);
        const streamedResponse = this.buildResponse(req, responseCode, streamedHeaders, result);
        if (streamError) {
          // Some servers finish a chunked response and then close the connection in a way
          // Network Kit reports as 2300056. Preserve the received body so callers can
          // validate and use a complete payload instead of losing it with the socket error.
          streamedResponse.success = false;
          streamedResponse.error = streamError;
        }
        return streamedResponse;
      }

      const options: http.HttpRequestOptions = {
        method: method,
        header: headers,
        extraData: requestData,
        connectTimeout: req.connectTimeout || this.timeout,
        readTimeout: req.readTimeout || this.timeout,
        expectDataType: http.HttpDataType.ARRAY_BUFFER
      };
      this.applyTlsTrust(options, req.url);
      if (forceHttp1) options.usingProtocol = http.HttpProtocol.HTTP1_1;
      const resp = await client.request(req.url, options);

      const responseHeaders = (resp.header || {}) as Record<string, string>;
      return this.buildResponse(req, resp.responseCode, responseHeaders, resp.result);
    } catch (e) {
      return {
        url: req.url,
        statusCode: 0,
        headers: {},
        body: '',
        success: false,
        error: responseTooLarge ? `response too large: >${req.maxResponseBytes}` :
          this.decorateTlsError(req.url, this.describeError(e as Object))
      };
    } finally {
      this.activeClients.delete(client);
      client.destroy();
    }
  }

  async executeBinary(req: HttpRequest, maxResponseBytes: number = 20 * 1024 * 1024):
    Promise<HttpBinaryResponse> {
    if (!req.url || req.url.trim() === '') {
      return { url: '', statusCode: 0, headers: {}, data: new Uint8Array(), success: false, error: 'empty url' };
    }
    const response = await this.executeBinaryWithProtocol(req, maxResponseBytes, false);
    if (!response.success && this.shouldRetryWithHttp1(req.url, response.error || '')) {
      console.info('[HttpClient] binary HTTP/2 failed; retrying once with HTTP/1.1:', this.hostForLog(req.url));
      return await this.executeBinaryWithProtocol(req, maxResponseBytes, true);
    }
    return response;
  }

  private async executeBinaryWithProtocol(req: HttpRequest, maxResponseBytes: number,
    forceHttp1: boolean): Promise<HttpBinaryResponse> {
    const client = http.createHttp();
    this.activeClients.add(client);
    try {
      const headers: Record<string, string> = { ...this.defaultHeaders, ...req.headers };
      const requestData = this.requestData(req);
      const cookie = req.useCookieJar === false ? '' : CookieStore.getCookie(req.url);
      if (cookie && !headers['Cookie']) headers['Cookie'] = cookie;
      const options: http.HttpRequestOptions = {
        method: this.resolveMethod(req.method),
        header: headers,
        extraData: requestData,
        connectTimeout: req.connectTimeout || this.timeout,
        readTimeout: req.readTimeout || this.timeout,
        expectDataType: http.HttpDataType.ARRAY_BUFFER
      };
      this.applyTlsTrust(options, req.url);
      if (forceHttp1) options.usingProtocol = http.HttpProtocol.HTTP1_1;
      const resp = await client.request(req.url, options);
      const responseHeaders = (resp.header || {}) as Record<string, string>;
      const setCookie = this.findHeader(responseHeaders, 'set-cookie');
      if (setCookie) {
        CookieStore.setCookies(req.url, setCookie);
        CookieStore.saveAsync();
      }
      const data = resp.result instanceof ArrayBuffer ?
        new Uint8Array(resp.result as ArrayBuffer) :
        new util.TextEncoder().encodeInto(String(resp.result || ''));
      if (data.byteLength > maxResponseBytes) {
        return {
          url: req.url,
          statusCode: resp.responseCode,
          headers: responseHeaders,
          data: new Uint8Array(),
          success: false,
          error: `response too large: >${maxResponseBytes}`
        };
      }
      return {
        url: req.url,
        statusCode: resp.responseCode,
        headers: responseHeaders,
        data: data,
        success: resp.responseCode >= 200 && resp.responseCode < 300
      };
    } catch (e) {
      return {
        url: req.url,
        statusCode: 0,
        headers: {},
        data: new Uint8Array(),
        success: false,
        error: this.decorateTlsError(req.url, this.describeError(e as Object))
      };
    } finally {
      this.activeClients.delete(client);
      client.destroy();
    }
  }

  cancelAll(): void {
    this.activeClients.forEach((client: http.HttpRequest) => {
      try {
        client.destroy();
      } catch (e) {
      }
    });
    this.activeClients.clear();
  }

  private resolveMethod(method: string): http.RequestMethod {
    switch (method.toUpperCase()) {
      case 'POST': return http.RequestMethod.POST;
      case 'PUT': return http.RequestMethod.PUT;
      case 'DELETE': return http.RequestMethod.DELETE;
      case 'HEAD': return http.RequestMethod.HEAD;
      default: return http.RequestMethod.GET;
    }
  }

  private requestData(req: HttpRequest): string | ArrayBuffer {
    const method = (req.method || 'GET').toUpperCase();
    if (method === 'GET' || method === 'HEAD') return '';
    return req.bodyBytes || req.body || '';
  }

  private findHeader(headers: Record<string, string>, name: string): string {
    const lower = name.toLowerCase();
    for (const key in headers) {
      if (key.toLowerCase() === lower) return String(headers[key] || '');
    }
    return '';
  }

  private buildResponse(req: HttpRequest, responseCode: number, responseHeaders: Record<string, string>,
    result: string | Object): HttpResponse {
    const setCookie = this.findHeader(responseHeaders, 'set-cookie');
    if (setCookie) {
      CookieStore.setCookies(req.url, setCookie);
      CookieStore.saveAsync();
    }
    const charset = req.charset || this.responseCharset(responseHeaders);
    const body = this.decodeBody(result, charset);
    const finalBody = req.charset ? body : this.decodeBodyWithMetaCharset(result, body, charset);
    return {
      url: req.url,
      statusCode: responseCode,
      headers: responseHeaders,
      body: finalBody,
      success: responseCode >= 200 && responseCode < 300
    };
  }

  private mergeArrayBuffers(chunks: ArrayBuffer[], totalBytes: number): ArrayBuffer {
    if (chunks.length === 1) return chunks[0];
    const merged = new Uint8Array(totalBytes);
    let offset = 0;
    for (const chunk of chunks) {
      const bytes = new Uint8Array(chunk);
      merged.set(bytes, offset);
      offset += bytes.byteLength;
    }
    return merged.buffer as ArrayBuffer;
  }

  private responseCharset(headers: Record<string, string>): string {
    const contentType = this.findHeader(headers, 'content-type');
    const match = contentType.match(/charset\s*=\s*["']?([^;\s"']+)/i);
    return match ? match[1].trim().toLowerCase() : 'utf-8';
  }

  private decodeBody(result: string | Object, charset?: string): string {
    if (typeof result === 'string') return result as string;
    if (result instanceof ArrayBuffer) {
      try {
        return util.TextDecoder.create(this.normalizeCharset(charset || 'utf-8'))
          .decodeWithStream(new Uint8Array(result as ArrayBuffer), { stream: false });
      } catch (_) {
        return String(result || '');
      }
    }
    return String(result || '');
  }

  private decodeBodyWithMetaCharset(result: string | Object, decoded: string, charset: string): string {
    if (!(result instanceof ArrayBuffer)) return decoded;
    const metaCharset = this.findMetaCharset(decoded);
    if (!metaCharset || this.normalizeCharset(metaCharset) === this.normalizeCharset(charset || 'utf-8')) {
      return decoded;
    }
    return this.decodeBody(result, metaCharset);
  }

  private findMetaCharset(html: string): string {
    const head = (html || '').substring(0, 4096);
    const direct = head.match(/<meta[^>]+charset\s*=\s*["']?\s*([A-Za-z0-9_-]+)/i);
    if (direct) return direct[1].trim().toLowerCase();
    const contentType = head.match(/<meta[^>]+http-equiv\s*=\s*["']?content-type["']?[^>]+content\s*=\s*["'][^"']*charset\s*=\s*([^;"'\s>]+)/i);
    return contentType ? contentType[1].trim().toLowerCase() : '';
  }

  private normalizeCharset(charset: string): string {
    const value = charset.toLowerCase().replace(/["']/g, '').trim();
    if (value === 'gb2312' || value === 'gbk') return 'gb18030';
    return value || 'utf-8';
  }

  private describeError(error: Object): string {
    if (error instanceof Error && this.isReadableErrorText(error.message)) return error.message;
    if (typeof error === 'string' && this.isReadableErrorText(error as string)) return error as string;
    if (error && typeof error === 'object') {
      const record = error as Record<string, Object>;
      const rawMessage = record['message'] || record['msg'] || record['reason'];
      let message = typeof rawMessage === 'string' ? (rawMessage as string).trim() : '';
      if (!this.isReadableErrorText(message) && rawMessage && typeof rawMessage === 'object') {
        const nested = rawMessage as Record<string, Object>;
        message = String(nested['message'] || nested['msg'] || nested['reason'] || '').trim();
      }
      const code = String(record['code'] || record['errorCode'] || '').trim();
      if (this.isReadableErrorText(message)) return code ? `${message} (${code})` : message;
      try {
        const json = JSON.stringify(error);
        if (json && json !== '{}') return json;
      } catch (_) {
      }
    }
    const fallback = String(error || '').trim();
    return this.isReadableErrorText(fallback) ? fallback : '未知网络错误';
  }

  private isReadableErrorText(value: string): boolean {
    const text = (value || '').trim().toLowerCase();
    return !!text && !text.includes('[object object]') && text !== 'object object' && text !== '{}';
  }

  private shouldRetryWithHttp1(url: string, error: string): boolean {
    if (!/^https:\/\//i.test(url || '')) return false;
    return /2300016|2300999|http\/?2|http2|framing layer|curl(?:_|\s*)code\s*[=:]?\s*92/i.test(error || '');
  }

  private shouldRetryTimeout(req: HttpRequest, error: string): boolean {
    const method = (req.method || 'GET').toUpperCase();
    if (method !== 'GET' && method !== 'HEAD') return false;
    return /2300028|operation\s+timeout|timed?\s*out|timeout/i.test(error || '');
  }

  private applyTlsTrust(options: http.HttpRequestOptions, url: string): void {
    if (TlsTrustStore.isRemoteValidationSupported() && TlsTrustStore.isTrustedUrl(url)) {
      options.remoteValidation = 'skip';
    }
  }

  private decorateTlsError(url: string, error: string): string {
    if (!TlsTrustStore.isCertificateError(error) || /证书主机\s*[：:]/.test(error || '')) return error;
    const host = TlsTrustStore.hostFromUrl(url);
    return host ? `证书校验失败（证书主机：${host}）：${error}` : error;
  }

  private hostForLog(url: string): string {
    const match = (url || '').match(/^https?:\/\/([^/:?#]+)/i);
    return match && match[1] ? match[1] : '(unknown host)';
  }
}
