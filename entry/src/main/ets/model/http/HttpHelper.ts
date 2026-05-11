import http from '@ohos.net.http';

export interface HttpRequestOptions {
  method?: string;
  headers?: Record<string, string>;
  body?: string;
  connectTimeout?: number;
  readTimeout?: number;
}

export interface HttpResponse {
  statusCode: number;
  header: Record<string, string>;
  cookies: string;
  body: string;
}

export class HttpHelper {
  private static instance: HttpHelper | null = null;
  private defaultHeaders: Record<string, string> = {
    'User-Agent': 'Mozilla/5.0 (Linux; Android 14; HarmonyOS) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': '*/*',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    'Accept-Encoding': 'gzip, deflate',
    'Connection': 'keep-alive'
  };

  private constructor() {}

  static getInstance(): HttpHelper {
    if (!HttpHelper.instance) {
      HttpHelper.instance = new HttpHelper();
    }
    return HttpHelper.instance;
  }

  setDefaultHeader(key: string, value: string): void {
    this.defaultHeaders[key] = value;
  }

  async request(url: string, options: HttpRequestOptions = {}): Promise<HttpResponse> {
    const httpRequest = http.createHttp();

    try {
      const headers: Record<string, string> = { ...this.defaultHeaders, ...options.headers };

      let method: http.RequestMethod;
      switch (options.method) {
        case 'POST':
          method = http.RequestMethod.POST;
          break;
        case 'PUT':
          method = http.RequestMethod.PUT;
          break;
        case 'DELETE':
          method = http.RequestMethod.DELETE;
          break;
        case 'HEAD':
          method = http.RequestMethod.HEAD;
          break;
        default:
          method = http.RequestMethod.GET;
          break;
      }

      const requestOptions: http.HttpRequestOptions = {
        method: method,
        header: headers,
        connectTimeout: options.connectTimeout || 10000,
        readTimeout: options.readTimeout || 10000,
        expectDataType: http.HttpDataType.STRING
      };

      if (options.body) {
        requestOptions.extraData = options.body;
        if (!headers['Content-Type']) {
          headers['Content-Type'] = 'application/json';
        }
      }

      console.log('HTTP请求:', url, options.method || 'GET');

      const response = await httpRequest.request(url, requestOptions);

      console.log('HTTP响应状态:', response.responseCode);

      const bodyStr = typeof response.result === 'string' ? response.result : String(response.result || '');

      const result: HttpResponse = {
        statusCode: response.responseCode,
        header: response.header as Record<string, string>,
        cookies: response.cookies || '',
        body: bodyStr
      };

      return result;
    } catch (e) {
      console.warn('HTTP请求跳过:', this.formatError(e));
      throw e;
    } finally {
      httpRequest.destroy();
    }
  }

  async get(url: string, headers?: Record<string, string>): Promise<HttpResponse> {
    return this.request(url, { method: 'GET', headers });
  }

  async post(url: string, body?: string, headers?: Record<string, string>): Promise<HttpResponse> {
    return this.request(url, { method: 'POST', body, headers });
  }

  async getBody(url: string, headers?: Record<string, string>): Promise<string> {
    const response = await this.get(url, headers);
    console.log('getBody状态码:', response.statusCode, '内容长度:', response.body.length);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response.body;
    }
    throw new Error(`HTTP ${response.statusCode}`);
  }

  async postBody(url: string, body?: string, headers?: Record<string, string>): Promise<string> {
    const response = await this.post(url, body, headers);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response.body;
    }
    throw new Error(`HTTP ${response.statusCode}`);
  }

  private formatError(error: Object): string {
    if (!error) return '';
    try {
      const err = error as Record<string, Object>;
      const code = err['code'] !== undefined ? String(err['code']) : '';
      const message = err['message'] !== undefined ? String(err['message']) : String(error);
      return code ? `${message} (${code})` : message;
    } catch (e) {
      return String(error);
    }
  }
}

export const httpHelper = HttpHelper.getInstance();
