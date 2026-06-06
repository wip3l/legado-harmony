import { HttpResponse } from '../http/HttpClient';

export class BookUrlResolver {
  static cleanBaseUrl(url: string): string {
    if (!url) return '';
    const hashIndex = url.indexOf('##');
    return (hashIndex >= 0 ? url.substring(0, hashIndex) : url).trim();
  }

  static effectiveBase(response: HttpResponse | null, requestUrl: string, fallbackUrl: string): string {
    const respUrl = this.cleanBaseUrl(response?.url || '');
    if (this.isHttpUrl(respUrl)) return respUrl;
    const req = this.cleanBaseUrl(requestUrl);
    if (this.isHttpUrl(req)) return req;
    return this.cleanBaseUrl(fallbackUrl);
  }

  static resolve(url: string, base: string): string {
    const value = (url || '').trim();
    if (!value || value.startsWith('http://') || value.startsWith('https://') || value.startsWith('data:')) return value;
    if (value.startsWith('//')) return 'https:' + value;

    const cleanBase = this.cleanBaseUrl(base);
    if (!cleanBase) return value;
    if (value.startsWith('/')) {
      const m = cleanBase.match(/^(https?:\/\/[^/]+)/);
      return m ? m[0] + value : cleanBase + value;
    }

    const queryIndex = cleanBase.indexOf('?');
    const withoutQuery = queryIndex >= 0 ? cleanBase.substring(0, queryIndex) : cleanBase;
    const baseDir = withoutQuery.endsWith('/') ? withoutQuery : withoutQuery.replace(/\/[^/]*$/, '/');
    return baseDir + value;
  }

  static setVariableJson(raw: string, key: string, value: string): string {
    const data = this.parseVariableJson(raw);
    data[key] = value;
    return JSON.stringify(data);
  }

  static getVariableJson(raw: string, key: string): string {
    return this.parseVariableJson(raw)[key] || '';
  }

  private static isHttpUrl(url: string): boolean {
    return url.startsWith('http://') || url.startsWith('https://');
  }

  private static parseVariableJson(raw: string): Record<string, string> {
    try {
      return JSON.parse(raw || '{}') as Record<string, string>;
    } catch (_) {
      return {};
    }
  }
}
