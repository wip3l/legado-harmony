import { BookSource } from '../../model/data/Book';

export class VerificationSupport {
  static isChallengeResponse(body: string): boolean {
    if (!body) return false;
    const sample = body.substring(0, Math.min(body.length, 4000));
    return sample.includes('Just a moment') || sample.includes('cf-challenge') ||
      sample.includes('Cloudflare') || sample.includes('challenge-platform') ||
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
    if (!(statusCode === 401 || statusCode === 403)) {
      return false;
    }
    if (this.hasBrowserVerifyHint(source, rule || '')) {
      return true;
    }
    return !this.looksLikeApiSource(source);
  }

  static requestVerification(url: string, title: string): void {
    const cleanUrl = this.cleanUrl(url);
    if (!cleanUrl) return;
    AppStorage.setOrCreate('pendingVerificationUrl', cleanUrl);
    AppStorage.setOrCreate('pendingVerificationTitle', title || '网页验证');
    AppStorage.setOrCreate('pendingVerificationTime', Date.now());
  }

  static clearVerification(): void {
    AppStorage.setOrCreate('pendingVerificationUrl', '');
    AppStorage.setOrCreate('pendingVerificationTitle', '');
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
    if (requestUrl && requestUrl.startsWith('http')) return this.cleanUrl(requestUrl);
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

  private static looksLikeApiSource(source: BookSource): boolean {
    const url = (source.bookSourceUrl || '').toLowerCase();
    const header = (source.header || '').toLowerCase();
    return url.includes('://api.') || url.includes('/api') ||
      header.includes('authorization') || header.includes('client-name') ||
      header.includes('client-version') || header.includes('okhttp');
  }

  private static cleanUrl(url: string): string {
    if (!url) return '';
    let clean = url.replace(/##[\s\S]*$/, '').split(',{')[0].trim();
    if (clean.startsWith('//')) clean = 'https:' + clean;
    return clean;
  }

  private static resolveUrl(url: string, base: string): string {
    if (!url) return '';
    if (url === 'baseUrl') return this.cleanUrl(base);
    if (url.startsWith('http://') || url.startsWith('https://')) return this.cleanUrl(url);
    if (url.startsWith('//')) return 'https:' + url;
    const cleanBase = this.cleanUrl(base);
    if (url.startsWith('/')) {
      const match = cleanBase.match(/^(https?:\/\/[^/]+)/);
      return match ? match[0] + url : cleanBase + url;
    }
    return cleanBase.endsWith('/') ? cleanBase + url : cleanBase + '/' + url;
  }
}
