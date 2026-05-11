import http from '@ohos.net.http';

export interface HttpRequest {
  url: string;
  method: string;
  headers: Record<string, string>;
  body?: string;
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
      const resp = await client.request(req.url, {
        method: method,
        header: req.headers,
        extraData: req.body,
        connectTimeout: req.connectTimeout || this.timeout,
        readTimeout: req.readTimeout || this.timeout,
        expectDataType: http.HttpDataType.STRING
      });

      return {
        url: req.url,
        statusCode: resp.responseCode,
        headers: (resp.header || {}) as Record<string, string>,
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
}