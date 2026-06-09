import { BookSource } from '../../model/data/Book';
import { CookieStore } from './CookieStore';

export class VerificationSupport {
  static isChallengeResponse(body: string): boolean {
    if (!body) return false;
    const sample = body.substring(0, Math.min(body.length, 4000));
    return sample.includes('Just a moment') || sample.includes('cf-challenge') ||
      sample.includes('Cloudflare') || sample.includes('challenge-platform') ||
      sample.includes('error code: 522') || sample.includes('Error code: 522') ||
      sample.includes('sedoparking.com') || sample.includes('Resources and Information') ||
      sample.includes('确认您是真人') || sample.includes('人机验证') ||
      sample.includes('请输入验证码') || sample.includes('验证码') ||
      sample.includes('cookie 验证') || sample.includes('Cookie 验证') ||
      sample.includes('安全验证') || sample.includes('滑动验证');
  }

  static canBrowserVerify(rule: string): boolean {
    return !!rule && (rule.includes('startBrowserAwait') || rule.includes('getVerificationCode') ||
      rule.includes('Cloudflare') || rule.includes('Just a moment') || rule.includes('人机验证') ||
      rule.includes('验证码') || rule.includes('cookie.setCookie') || rule.includes('cookie.getCookie'));
  }

  static shouldRequestBrowserVerification(source: BookSource, body: string, statusCode: number, rule?: string): boolean {
    if (this.isChallengeResponse(body)) {
      return true;
    }
    if (statusCode === 0) {
      return this.hasBrowserVerifyHint(source, rule || '') || this.hasLoginEntry(source);
    }
    if (!(statusCode === 401 || statusCode === 403 || statusCode === 429 || statusCode === 521 || statusCode === 522 || statusCode === 523 || statusCode === 524)) {
      return false;
    }
    if (this.hasBrowserVerifyHint(source, rule || '')) {
      return true;
    }
    return !this.looksLikeApiSource(source);
  }

  static requestVerification(url: string, title: string, source?: BookSource): void {
    const cleanUrl = this.cleanUrl(url);
    if (!cleanUrl) return;
    AppStorage.setOrCreate('pendingVerificationUrl', cleanUrl);
    AppStorage.setOrCreate('pendingVerificationTitle', title || '网页验证');
    AppStorage.setOrCreate('pendingVerificationTime', Date.now());
    if (source) {
      AppStorage.setOrCreate('pendingVerificationSourceUrl', source.bookSourceUrl || '');
      AppStorage.setOrCreate('pendingVerificationLoginUrl', this.resolveBookSourceLoginUrl(source));
    }
  }

  static buildBookSourceLoginUrl(source: BookSource): string {
    const bookSourceUrl = encodeURIComponent(source.bookSourceUrl || '');
    return `legado://book-source-login?bookSourceUrl=${bookSourceUrl}`;
  }

  static isBookSourceLoginUrl(url: string): boolean {
    return (url || '').startsWith('legado://book-source-login');
  }

  static getBookSourceUrlFromLoginUrl(url: string): string {
    const match = (url || '').match(/[?&]bookSourceUrl=([^&]+)/);
    if (!match || !match[1]) return '';
    try {
      return decodeURIComponent(match[1]);
    } catch (_) {
      return match[1];
    }
  }

  static resolveBookSourceLoginUrl(source: BookSource): string {
    const loginUrl = this.cleanUrl(source.loginUrl || '');
    if (this.isHttpUrl(loginUrl)) return loginUrl;

    const host = this.firstScriptHost(source);
    if (host) return `${host.replace(/\/+$/, '')}/login`;

    const sourceUrl = this.cleanUrl(source.bookSourceUrl || '');
    if (this.isHttpUrl(sourceUrl)) return `${sourceUrl.replace(/\/+$/, '')}/login`;
    return '';
  }

  static clearVerification(): void {
    AppStorage.setOrCreate('pendingVerificationUrl', '');
    AppStorage.setOrCreate('pendingVerificationTitle', '');
    AppStorage.setOrCreate('pendingVerificationSourceUrl', '');
    AppStorage.setOrCreate('pendingVerificationLoginUrl', '');
  }

  static getPendingUrl(): string {
    return AppStorage.get<string>('pendingVerificationUrl') || '';
  }

  static pickVerificationUrl(source: BookSource, requestUrl: string, rule?: string): string {
    const fromRule = this.pickStartBrowserUrl(rule || '') ||
      this.pickStartBrowserUrl(source.searchUrl || '') ||
      this.pickStartBrowserUrl(source.bookInfoRule?.init || '') ||
      this.pickStartBrowserUrl(source.tocRule?.chapterList || '') ||
      this.pickStartBrowserUrl(source.contentRule?.content || '');
    if (fromRule) return this.resolveUrl(fromRule, source.bookSourceUrl);

    const loginUrl = this.cleanUrl(source.loginUrl || '');
    if (this.isHttpUrl(loginUrl) && this.shouldPreferLoginUrl(source, requestUrl)) {
      return loginUrl;
    }

    const resolvedLoginUrl = this.resolveBookSourceLoginUrl(source);
    if (resolvedLoginUrl && this.shouldPreferLoginUrl(source, requestUrl)) {
      return resolvedLoginUrl;
    }

    if (requestUrl && requestUrl.startsWith('http')) return this.cleanUrl(requestUrl);
    if (this.isHttpUrl(loginUrl)) return loginUrl;
    if (resolvedLoginUrl) return resolvedLoginUrl;
    return this.cleanUrl(source.bookSourceUrl);
  }

  static pickStartBrowserUrl(rule: string): string {
    if (!rule) return '';
    const match = rule.match(/startBrowserAwait\(\s*([^,\)]+)(?:\s*,\s*['"][^'"]*['"])?/);
    if (!match) return '';
    const raw = match[1].trim();
    if (raw === 'baseUrl') return '';
    return raw.replace(/^['"]|['"]$/g, '');
  }

  private static hasBrowserVerifyHint(source: BookSource, rule: string): boolean {
    return this.canBrowserVerify(rule) || this.canBrowserVerify(source.searchUrl || '') ||
      this.canBrowserVerify(source.loginUrl || '') ||
      this.canBrowserVerify(source.bookInfoRule?.init || '') ||
      this.canBrowserVerify(source.tocRule?.chapterList || '') ||
      this.canBrowserVerify(source.contentRule?.content || '');
  }

  private static hasLoginEntry(source: BookSource): boolean {
    const loginUrl = this.cleanUrl(source.loginUrl || '');
    return !!loginUrl && (loginUrl.startsWith('http://') || loginUrl.startsWith('https://')) &&
      !this.looksLikeApiSource(source);
  }

  private static looksLikeApiSource(source: BookSource): boolean {
    const url = (source.bookSourceUrl || '').toLowerCase();
    const header = (source.header || '').toLowerCase();
    return url.includes('://api.') || url.includes('/api') ||
      header.includes('authorization') || header.includes('client-name') ||
      header.includes('client-version') || header.includes('okhttp');
  }

  private static firstScriptHost(source: BookSource): string {
    const raw = `${source.jsLib || ''}\n${source.loginUrl || ''}\n${source.exploreUrl || ''}\n${source.searchUrl || ''}`;
    const hostBlock = raw.match(/\bhosts?\s*=\s*\[([\s\S]*?)\]/);
    const body = hostBlock ? hostBlock[1] : raw;
    const match = body.match(/["'](https?:\/\/[^"'`\s,)]+)["']/i);
    return match ? this.cleanUrl(match[1]) : '';
  }

  static sourceCookieHeader(source: BookSource, requestUrl: string): string {
    if (!source || !requestUrl) return '';
    const existing = CookieStore.getCookie(requestUrl);
    if (existing) return existing;

    const loginUrl = this.cleanUrl(source.loginUrl || '');
    const loginCookie = CookieStore.getCookie(loginUrl) || CookieStore.getCookie(this.originOf(loginUrl));
    if (!loginCookie) return '';

    const requestHost = this.hostOf(requestUrl);
    const sourceHost = this.hostOf(source.bookSourceUrl || '');
    const loginHost = this.hostOf(loginUrl);
    if (!requestHost || !loginHost) return '';
    if (requestHost === loginHost || requestHost === sourceHost || this.isFanqieRelatedHost(requestHost, source)) {
      return loginCookie;
    }
    return '';
  }

  static syncLoginCookiesToSourceHosts(sourceUrl: string, loginUrl: string, currentUrl: string): void {
    const fromUrls = [
      currentUrl,
      loginUrl,
      this.originOf(currentUrl),
      this.originOf(loginUrl),
      'https://fanqienovel.com'
    ].filter((item: string) => this.isHttpUrl(item));
    let fromUrl = '';
    for (const item of fromUrls) {
      if (CookieStore.getCookie(item)) {
        fromUrl = item;
        break;
      }
    }
    if (!fromUrl) return;

    const targets = [
      sourceUrl,
      this.originOf(sourceUrl),
      loginUrl,
      this.originOf(loginUrl),
      'https://fanqienovel.com',
      'https://novel.snssdk.com',
      'https://api5-normal-sinfonlineb.fqnovel.com'
    ].filter((item: string) => this.isHttpUrl(item));
    for (const target of targets) {
      CookieStore.copyCookies(fromUrl, target);
      CookieStore.copyCookies(fromUrl, `${target}/`);
      CookieStore.copyCookies(fromUrl, `${target}/api`);
      CookieStore.copyCookies(fromUrl, `${target}/content`);
      CookieStore.copyCookies(fromUrl, `${target}/info`);
    }
    CookieStore.saveAsync();
  }

  private static shouldPreferLoginUrl(source: BookSource, requestUrl: string): boolean {
    const cleanRequest = this.cleanUrl(requestUrl || '');
    if (!this.isHttpUrl(cleanRequest)) return true;
    if (this.looksLikeApiRequestUrl(cleanRequest)) return true;

    const loginHost = this.hostOf(source.loginUrl || '');
    const sourceHost = this.hostOf(source.bookSourceUrl || '');
    const requestHost = this.hostOf(cleanRequest);
    return !!loginHost && !!sourceHost && !!requestHost && loginHost !== requestHost && sourceHost === requestHost;
  }

  private static looksLikeApiRequestUrl(url: string): boolean {
    const clean = (url || '').toLowerCase();
    return clean.includes('/api/') || clean.includes('/bookapi/') ||
      /\/(?:search|content|info)(?:\?|$)/.test(clean) ||
      clean.includes('format=json') || clean.endsWith('.json');
  }

  private static isFanqieRelatedHost(host: string, source: BookSource): boolean {
    const raw = `${source.bookSourceUrl || ''}\n${source.loginUrl || ''}\n${source.searchUrl || ''}\n${source.exploreUrl || ''}`.toLowerCase();
    return raw.includes('fanqie') || raw.includes('fq-book') || raw.includes('snssdk') ||
      host.includes('fanqie') || host.includes('fqnovel') || host.includes('snssdk') || host.includes('fq-book');
  }

  private static hostOf(url: string): string {
    const match = this.cleanUrl(url || '').match(/^https?:\/\/([^/:?#]+)/i);
    return match ? match[1].toLowerCase() : '';
  }

  private static originOf(url: string): string {
    const match = this.cleanUrl(url || '').match(/^(https?:\/\/[^/:?#]+(?::\d+)?)/i);
    return match ? match[1] : '';
  }

  private static isHttpUrl(url: string): boolean {
    return (url || '').startsWith('http://') || (url || '').startsWith('https://');
  }

  private static cleanUrl(url: string): string {
    if (!url) return '';
    let clean = url.replace(/##[\s\S]*$/, '').split(',{')[0].trim();
    if (/^\/\/[A-Za-z0-9.-]+(?::\d+)?(?:[/?#]|$)/.test(clean)) clean = 'https:' + clean;
    return clean;
  }

  private static resolveUrl(url: string, base: string): string {
    if (!url) return '';
    if (url === 'baseUrl') return this.cleanUrl(base);
    if (url.startsWith('http://') || url.startsWith('https://')) return this.cleanUrl(url);
    if (/^\/\/[A-Za-z0-9.-]+(?::\d+)?(?:[/?#]|$)/.test(url)) return 'https:' + url;
    const cleanBase = this.cleanUrl(base);
    if (url.startsWith('/')) {
      const match = cleanBase.match(/^(https?:\/\/[^/]+)/);
      return match ? match[0] + url : cleanBase + url;
    }
    return cleanBase.endsWith('/') ? cleanBase + url : cleanBase + '/' + url;
  }
}
