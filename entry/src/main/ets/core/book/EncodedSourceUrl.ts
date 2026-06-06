import { util } from '@kit.ArkTS';
import { HttpClient } from '../http/HttpClient';
import { CookieStore } from '../http/CookieStore';

export type EncodedJsonValue = string | number | boolean | Object | null;
export type EncodedJsonMap = Record<string, EncodedJsonValue>;

export class EncodedSourcePayload {
  raw: string = '';
  text: string = '';
  type: string = '';
  data: EncodedJsonMap = {};
  options: EncodedJsonMap = {};
}

export class EncodedSourceUrl {
  static readonly DEFAULT_HOSTS: string[] = [
    'http://219.154.201.122:5006',
    'https://api.langge.cf',
    'https://v2.czyl.cf',
    'https://20.langge.tk',
    'https://v4.czyl.cf',
    'https://v5.czyl.cf',
    'https://v7.czyl.cf',
    'https://v8.czyl.cf',
    'https://v9.czyl.cf',
    'https://v10.czyl.cf',
    'https://v1.gyks.cf',
    'https://v2.gyks.cf',
    'https://v3.gyks.cf',
    'https://v4.gyks.cf',
    'https://v5.gyks.cf',
    'https://v6.gyks.cf',
    'https://v7.gyks.cf',
    'http://101.35.133.34:8888'
  ];

  static isEncodedDataUrl(url: string): boolean {
    return (url || '').startsWith('data:;base64,');
  }

  static decode(url: string): EncodedSourcePayload | null {
    if (!EncodedSourceUrl.isEncodedDataUrl(url)) return null;
    const payload = new EncodedSourcePayload();
    payload.raw = url;
    const rest = url.substring('data:;base64,'.length);
    const split = EncodedSourceUrl.splitPayload(rest);
    const jsonText = EncodedSourceUrl.base64Decode(split[0]);
    payload.text = jsonText;
    try {
      payload.data = EncodedSourceUrl.asMap(JSON.parse(jsonText) as Object);
    } catch (_) {
      payload.data = {};
    }
    if (split[1]) {
      try {
        payload.options = EncodedSourceUrl.asMap(JSON.parse(split[1]) as Object);
      } catch (_) {
        payload.options = {};
      }
      payload.type = EncodedSourceUrl.str(payload.options['type']);
    }
    return payload;
  }

  static canHandle(url: string): boolean {
    const payload = EncodedSourceUrl.decode(url);
    if (!payload) return false;
    return payload.type === 'gysearch' || payload.type === 'gydetail' ||
      payload.type === 'gycatalog' || payload.type === 'gycontent' ||
      payload.type === 'qingtian' || payload.type === 'qingtian2' || payload.type === 'qingtian3' ||
      payload.type === 'mybxs' || payload.type === 'mybxc';
  }

  static async requestJsonForDataUrl(http: HttpClient, url: string, preferredHost?: string):
    Promise<EncodedJsonMap | null> {
    const payload = EncodedSourceUrl.decode(url);
    if (!payload) return null;
    return await EncodedSourceUrl.requestJsonForPayload(http, payload, preferredHost);
  }

  static async requestJsonForPayload(http: HttpClient, payload: EncodedSourcePayload, preferredHost?: string):
    Promise<EncodedJsonMap | null> {
    const req = EncodedSourceUrl.buildRequest(payload);
    if (!req.path) return null;
    return await EncodedSourceUrl.requestJson(http, req.path, req.method, req.body, preferredHost || req.host);
  }

  static buildSearchUrl(keyword: string, page: number = 1, tab: string = '小说', source: string = '全部'): string {
    return EncodedSourceUrl.encode({
      key: keyword,
      tab: tab,
      sourcesKey: source,
      page: String(page),
      disabled_sources: '0'
    }, 'gysearch');
  }

  static buildDetailUrl(bookId: string, source: string, tab: string, tocUrl: string = '', host: string = ''): string {
    return EncodedSourceUrl.encode({
      book_id: bookId,
      sources: source,
      source: source,
      tab: tab || '小说',
      url: tocUrl,
      toc_url: tocUrl,
      host: host
    }, 'gydetail');
  }

  static buildCatalogUrl(data: EncodedJsonMap, host: string = ''): string {
    const copy: EncodedJsonMap = { ...data };
    if (host) copy['host'] = host;
    return EncodedSourceUrl.encode(copy, 'gycatalog');
  }

  static buildContentUrl(data: EncodedJsonMap, host: string = ''): string {
    const copy: EncodedJsonMap = { ...data };
    if (host) copy['host'] = host;
    return EncodedSourceUrl.encode(copy, 'gycontent');
  }

  static encode(data: EncodedJsonMap, type: string): string {
    const encoded = EncodedSourceUrl.base64Encode(JSON.stringify(data));
    return `data:;base64,${encoded},{"type":"${type}"}`;
  }

  static encodeRaw(text: string, type: string, host: string = ''): string {
    const encoded = EncodedSourceUrl.base64Encode(text || '');
    const options = host ? `{"type":"${type}","host":"${host}"}` : `{"type":"${type}"}`;
    return `data:;base64,${encoded},${options}`;
  }

  static async requestJson(http: HttpClient, path: string, method: string = 'GET', body?: string, preferredHost?: string,
    extraHeaders?: Record<string, string>):
    Promise<EncodedJsonMap | null> {
    const hosts = EncodedSourceUrl.hosts(preferredHost);
    for (const host of hosts) {
      const resp = await http.execute({
        url: `${host}${path}`,
        method: method,
        headers: {
          'Accept': 'application/json, text/plain, */*',
          'Content-Type': 'application/x-www-form-urlencoded',
          ...EncodedSourceUrl.buildCookieHeaders(host),
          ...(extraHeaders || {})
        },
        body: body
      });
      if (!resp.success || !resp.body) continue;
      try {
        return EncodedSourceUrl.asMap(JSON.parse(resp.body) as Object);
      } catch (_) {
      }
    }
    return null;
  }

  static str(value: EncodedJsonValue | undefined): string {
    if (value === undefined || value === null) return '';
    return String(value).trim();
  }

  static hostFromData(data: EncodedJsonMap): string {
    return EncodedSourceUrl.str(data['host']) || EncodedSourceUrl.str(data['gyHost']);
  }

  static hostFromUrl(url: string): string {
    const match = (url || '').match(/^(https?:\/\/[^/]+)/);
    return match ? match[1] : '';
  }

  static getLoginUrl(host?: string): string {
    return `${host || EncodedSourceUrl.DEFAULT_HOSTS[0]}/login`;
  }

  static syncCookiesAcrossHosts(fromUrl: string): void {
    if (!fromUrl) return;
    const fromHost = EncodedSourceUrl.hostFromUrl(fromUrl) || fromUrl;
    const cookie = CookieStore.getCookie(fromUrl) || CookieStore.getCookie(fromHost);
    if (!cookie) return;
    for (const host of EncodedSourceUrl.DEFAULT_HOSTS) {
      if (!host.startsWith('http')) continue;
      CookieStore.setCookies(host, cookie);
      CookieStore.setCookies(`${host}/login`, cookie);
      CookieStore.setCookies(`${host}/user`, cookie);
      CookieStore.setCookies(`${host}/content`, cookie);
    }
    CookieStore.saveAsync();
  }

  static asMap(value: Object | undefined | null): EncodedJsonMap {
    if (!value || typeof value !== 'object' || Array.isArray(value)) return {};
    return value as EncodedJsonMap;
  }

  static asArray(value: EncodedJsonValue | undefined): Object[] {
    if (!Array.isArray(value)) return [];
    return value as Object[];
  }

  private static buildRequest(payload: EncodedSourcePayload): { path: string, method: string, body: string, host: string } {
    const data = payload.data;
    const host = EncodedSourceUrl.hostFromData(data) || EncodedSourceUrl.str(payload.options['host']);
    if (payload.type === 'mybxs') {
      const bookId = payload.text || EncodedSourceUrl.str(data['book_id']) || EncodedSourceUrl.str(data['bookId']);
      return {
        path: `/bx/detail?book_id=${encodeURIComponent(bookId)}`,
        method: 'GET',
        body: '',
        host: host
      };
    }
    if (payload.type === 'mybxc') {
      const parts = (payload.text || '').split('/');
      const bookId = parts[0] || EncodedSourceUrl.str(data['book_id']) || EncodedSourceUrl.str(data['bookId']);
      const chapterId = parts[1] || EncodedSourceUrl.str(data['chapter_id']) || EncodedSourceUrl.str(data['chapterId']);
      return {
        path: `/bx/content?book_id=${encodeURIComponent(bookId)}&chapter_id=${encodeURIComponent(chapterId)}`,
        method: 'GET',
        body: '',
        host: host
      };
    }
    if (payload.type === 'gysearch') {
      const key = EncodedSourceUrl.str(data['key']);
      const tab = EncodedSourceUrl.str(data['tab']) || '小说';
      const source = EncodedSourceUrl.str(data['sourcesKey']) || EncodedSourceUrl.str(data['source']) || '全部';
      const page = EncodedSourceUrl.str(data['page']) || '1';
      const disabled = EncodedSourceUrl.str(data['disabled_sources']) || '0';
      return {
        path: `/search?title=${encodeURIComponent(key)}&tab=${encodeURIComponent(tab)}` +
          `&source=${encodeURIComponent(source)}&page=${encodeURIComponent(page)}` +
          `&disabled_sources=${encodeURIComponent(disabled)}`,
        method: 'GET',
        body: '',
        host: host
      };
    }
    if (payload.type === 'gydetail' || payload.type === 'qingtian') {
      const bookId = EncodedSourceUrl.str(data['book_id']) || EncodedSourceUrl.str(data['bookId']);
      const source = EncodedSourceUrl.str(data['sources']) || EncodedSourceUrl.str(data['source']);
      const tab = EncodedSourceUrl.str(data['tab']) || '小说';
      return {
        path: `/detail?book_id=${encodeURIComponent(bookId)}&source=${encodeURIComponent(source)}` +
          `&tab=${encodeURIComponent(tab)}`,
        method: 'GET',
        body: '',
        host: host
      };
    }
    if (payload.type === 'gycatalog' || payload.type === 'qingtian2') {
      const bookId = EncodedSourceUrl.str(data['book_id']) || EncodedSourceUrl.str(data['bookId']);
      const source = EncodedSourceUrl.str(data['sources']) || EncodedSourceUrl.str(data['source']);
      const tab = EncodedSourceUrl.str(data['tab']) || '小说';
      const variable = encodeURIComponent('{"custom":""}');
      return {
        path: `/catalog?book_id=${encodeURIComponent(bookId)}&source=${encodeURIComponent(source)}` +
          `&tab=${encodeURIComponent(tab)}&variable=${variable}`,
        method: 'POST',
        body: 'html=',
        host: host
      };
    }
    if (payload.type === 'gycontent' || payload.type === 'qingtian3') {
      const itemId = EncodedSourceUrl.str(data['item_id']) || EncodedSourceUrl.str(data['itemId']);
      const source = EncodedSourceUrl.str(data['sources']) || EncodedSourceUrl.str(data['source']);
      const tab = EncodedSourceUrl.str(data['tab']) || '小说';
      const bookId = EncodedSourceUrl.str(data['book_id']) || EncodedSourceUrl.str(data['bookId']);
      const variable = EncodedSourceUrl.str(data['variable']) || '{"custom":""}';
      const body = `html=&item_id=${encodeURIComponent(itemId)}&source=${encodeURIComponent(source)}` +
        `&tab=${encodeURIComponent(tab)}&tone_id=4&variable=${encodeURIComponent(variable)}&version=4.11.5.1` +
        (bookId ? `&book_id=${encodeURIComponent(bookId)}` : '');
      return {
        path: '/content',
        method: 'POST',
        body: body,
        host: host
      };
    }
    return { path: '', method: 'GET', body: '', host: host };
  }

  private static hosts(preferredHost?: string): string[] {
    const hosts: string[] = [];
    if (preferredHost) hosts.push(preferredHost);
    for (const host of EncodedSourceUrl.DEFAULT_HOSTS) {
      if (!hosts.includes(host)) hosts.push(host);
    }
    return hosts;
  }

  private static buildCookieHeaders(host: string): Record<string, string> {
    const qttoken = EncodedSourceUrl.findCookieValue(host, 'qttoken');
    if (!qttoken) return {};
    const deviceId = EncodedSourceUrl.findCookieValue(host, 'deviceId');
    return {
      'Cookie': `qttoken=${qttoken}${deviceId ? `;deviceId=${deviceId}` : ''};`
    };
  }

  private static findCookieValue(host: string, name: string): string {
    const urls = [host, `${host}/login`, `${host}/user`, `${host}/content`];
    for (const url of urls) {
      const cookie = CookieStore.getCookie(url);
      const value = EncodedSourceUrl.cookieValue(cookie, name);
      if (value) return value;
    }
    for (const otherHost of EncodedSourceUrl.DEFAULT_HOSTS) {
      const cookie = CookieStore.getCookie(otherHost);
      const value = EncodedSourceUrl.cookieValue(cookie, name);
      if (value) return value;
    }
    return '';
  }

  private static cookieValue(cookie: string, name: string): string {
    if (!cookie) return '';
    for (const item of cookie.split(';')) {
      const pair = item.trim();
      const eq = pair.indexOf('=');
      if (eq <= 0) continue;
      if (pair.substring(0, eq).trim() === name) return pair.substring(eq + 1).trim();
    }
    return '';
  }

  private static splitPayload(rest: string): string[] {
    const comma = rest.indexOf(',');
    if (comma < 0) return [rest, ''];
    return [rest.substring(0, comma), rest.substring(comma + 1)];
  }

  private static base64Encode(input: string): string {
    try {
      const e = new util.TextEncoder();
      return new util.Base64Helper().encodeToStringSync(e.encodeInto(input));
    } catch (_) {
      return input;
    }
  }

  private static base64Decode(input: string): string {
    try {
      const data = new util.Base64Helper().decodeSync(input);
      return util.TextDecoder.create('utf-8').decodeWithStream(data, { stream: false });
    } catch (_) {
      return input;
    }
  }
}
