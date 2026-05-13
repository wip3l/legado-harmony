import http from '@ohos.net.http';
import { CookieStore } from './CookieStore';

export interface HttpRequest {
  url: string;
  method: string;
  headers: Record<string, string>;
  body?: string;
  charset?: string;
  connectTimeout?: number;
  readTimeout?: number;
}

export interface HttpResponse {
  url: string;
  statusCode: number;
  headers: Record<string, string>;
  body: string;
  success: boolean;
  error?: string;
}

export class HttpClient {
  private timeout: number;
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
    if (!req.url || req.url.trim() === '') {
      return { url: '', statusCode: 0, headers: {}, body: '', success: false, error: 'empty url' };
    }
    const client = http.createHttp();
    try {
      const method = this.resolveMethod(req.method);
      const headers: Record<string, string> = { ...this.defaultHeaders, ...req.headers };
      const cookie = CookieStore.getCookie(req.url);
      if (cookie && !headers['Cookie']) {
        headers['Cookie'] = cookie;
      }
      const resp = await client.request(req.url, {
        method: method,
        header: headers,
        extraData: req.body,
        connectTimeout: req.connectTimeout || this.timeout,
        readTimeout: req.readTimeout || this.timeout,
        expectDataType: http.HttpDataType.STRING
      });

      const responseHeaders = (resp.header || {}) as Record<string, string>;
      const setCookie = this.findHeader(responseHeaders, 'set-cookie');
      if (setCookie) {
        CookieStore.setCookies(req.url, setCookie);
        CookieStore.saveAsync();
      }

      return {
        url: req.url,
        statusCode: resp.responseCode,
        headers: responseHeaders,
        body: typeof resp.result === 'string' ? resp.result as string : String(resp.result || ''),
        success: resp.responseCode >= 200 && resp.responseCode < 400
      };
    } catch (e) {
      return {
        url: req.url,
        statusCode: 0,
        headers: {},
        body: '',
        success: false,
        error: e instanceof Error ? e.message : String(e)
      };
    } finally {
      client.destroy();
    }
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

  private findHeader(headers: Record<string, string>, name: string): string {
    const lower = name.toLowerCase();
    for (const key in headers) {
      if (key.toLowerCase() === lower) return String(headers[key] || '');
    }
    return '';
  }
}
