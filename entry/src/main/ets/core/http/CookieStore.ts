import { webview } from '@kit.ArkWeb';
import { util } from '@kit.ArkTS';

export class CookieStore {
  private static readonly TOMBSTONE_VALUE = '__removed__';

  static getCookie(url: string): string {
    if (!url) return '';
    for (const target of this.targetUrls(url)) {
      try {
        const value = webview.WebCookieManager.fetchCookieSync(target) || '';
        if (value) return this.withoutExpiredJwtCookies(value);
      } catch (_) {
      }
    }
    return '';
  }

  static setCookies(url: string, cookies: string): void {
    if (!url || !cookies) return;
    const values = this.splitSetCookie(cookies);
    for (const target of this.targetUrls(url)) {
      for (const value of values) {
        try {
          webview.WebCookieManager.configCookieSync(target, value, false, true);
        } catch (_) {
          try {
            webview.WebCookieManager.configCookieSync(target, value);
          } catch (_) {}
        }
      }
    }
  }

  static copyCookies(fromUrl: string, toUrl: string): void {
    if (!fromUrl || !toUrl) return;
    const cookies = this.getCookie(fromUrl);
    if (!cookies) return;
    for (const item of cookies.split(';')) {
      const pair = item.trim();
      if (!pair || !pair.includes('=')) continue;
      this.setCookies(toUrl, pair);
    }
    this.saveAsync();
  }

  static replaceCookies(url: string, cookies: string): void {
    if (!url) return;
    this.removeCookie(url);
    if (cookies) this.setCookies(url, cookies);
    this.saveAsync();
  }

  static getCookieValue(url: string, name: string): string {
    if (!name) return this.getCookie(url);
    for (const item of this.getCookie(url).split(';')) {
      const index = item.indexOf('=');
      if (index > 0 && item.substring(0, index).trim() === name) return item.substring(index + 1).trim();
    }
    return '';
  }

  static removeCookie(url: string, name?: string): void {
    if (!url) return;
    const current = this.getCookie(url);
    const names = name ? [name] : current.split(';').map(item => item.trim().split('=')[0]).filter(item => item.length > 0);
    for (const cookieName of names) {
      // ArkWeb refuses to store expired cookies ("if the cookie has expired, it will not be
      // stored"), so the classic Max-Age=0 write is a silent no-op and the cookie survives.
      // Verify after each step and escalate: first an empty-value tombstone (server sees an
      // anonymous session), then a placeholder value that is filtered out on every read.
      this.writeCookieVariants(url, `${cookieName}=; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Path=/`);
      if (this.getCookieValue(url, cookieName)) {
        this.writeCookieVariants(url, `${cookieName}=; Max-Age=31536000; Path=/`);
      }
      if (this.getCookieValue(url, cookieName)) {
        this.writeCookieVariants(url, `${cookieName}=${this.TOMBSTONE_VALUE}; Max-Age=31536000; Path=/`);
      }
    }
    this.saveAsync();
  }

  private static writeCookieVariants(url: string, value: string): void {
    for (const target of this.targetUrls(url)) {
      try {
        webview.WebCookieManager.configCookieSync(target, value, false, true);
        continue;
      } catch (_) {
      }
      try {
        webview.WebCookieManager.configCookieSync(target, value);
      } catch (_) {
      }
    }
  }

  static clearAll(): void {
    try {
      webview.WebCookieManager.clearAllCookiesSync();
    } catch (_) {}
  }

  static saveAsync(): void {
    try {
      webview.WebCookieManager.saveCookieAsync();
    } catch (_) {}
  }

  static saveSync(): void {
    try {
      webview.WebCookieManager.saveCookieSync();
    } catch (_) {
      this.saveAsync();
    }
  }

  private static splitSetCookie(cookies: string): string[] {
    if (!cookies) return [];
    const records: string[] = [];
    let quote = '';
    let start = 0;
    for (let i = 0; i < cookies.length; i++) {
      const ch = cookies.charAt(i);
      if (quote) {
        if (ch === quote) quote = '';
        continue;
      }
      if (ch === '"' || ch === "'") {
        quote = ch;
        continue;
      }
      if (ch === ',' && /\s*[A-Za-z0-9_.-]+=/.test(cookies.substring(i + 1))) {
        records.push(cookies.substring(start, i).trim());
        start = i + 1;
      }
    }
    records.push(cookies.substring(start).trim());

    const values: string[] = [];
    for (const record of records) {
      for (const value of this.splitCookieRecord(record)) {
        if (value) values.push(value);
      }
    }
    return values;
  }

  /**
   * ArkWeb accepts one RFC 6265 Set-Cookie value per configCookieSync call. Legado source
   * scripts, however, commonly pass a Cookie request-header value such as
   * `token=...; deviceId=...` to cookie.setCookie(). A second name/value pair is not a cookie
   * attribute; forwarding the whole string makes ArkWeb reject it and silently loses the login
   * token. Preserve real Set-Cookie attributes, but emit every additional cookie separately.
   */
  private static splitCookieRecord(record: string): string[] {
    const parts = this.splitOnSemicolons(record);
    const values: string[] = [];
    let current = '';
    for (const rawPart of parts) {
      const part = rawPart.trim();
      if (!part) continue;
      const separator = part.indexOf('=');
      const name = (separator >= 0 ? part.substring(0, separator) : part).trim().toLowerCase();
      if (!current) {
        current = part;
      } else if (this.isCookieAttribute(name, separator >= 0)) {
        current += `; ${part}`;
      } else if (separator > 0) {
        values.push(current);
        current = part;
      } else {
        current += `; ${part}`;
      }
    }
    if (current) values.push(current);
    return values;
  }

  private static splitOnSemicolons(value: string): string[] {
    const result: string[] = [];
    let quote = '';
    let start = 0;
    for (let i = 0; i < value.length; i++) {
      const ch = value.charAt(i);
      if (quote) {
        if (ch === quote && value.charAt(i - 1) !== '\\') quote = '';
        continue;
      }
      if (ch === '"' || ch === "'") {
        quote = ch;
      } else if (ch === ';') {
        result.push(value.substring(start, i));
        start = i + 1;
      }
    }
    result.push(value.substring(start));
    return result;
  }

  private static isCookieAttribute(name: string, hasValue: boolean): boolean {
    if (hasValue) {
      return name === 'domain' || name === 'path' || name === 'expires' || name === 'max-age' ||
        name === 'samesite' || name === 'priority' || name === 'version' || name === 'comment';
    }
    return name === 'secure' || name === 'httponly' || name === 'partitioned';
  }

  /**
   * WebCookieManager can retain a session cookie after the JWT carried by that cookie has
   * expired. Sending it again may prevent an authentication bootstrap endpoint from issuing a
   * replacement. Filter only self-describing JWT cookie values whose `exp` is unequivocally in
   * the past; opaque cookies and malformed values are preserved unchanged.
   */
  private static withoutExpiredJwtCookies(cookies: string): string {
    const valid: string[] = [];
    for (const item of (cookies || '').split(';')) {
      const pair = item.trim();
      const separator = pair.indexOf('=');
      if (separator <= 0) continue;
      const value = pair.substring(separator + 1).trim();
      if (this.isExpiredJwt(value)) continue;
      // Tombstones written by removeCookie() when ArkWeb would not drop the cookie outright.
      if (value === this.TOMBSTONE_VALUE) continue;
      valid.push(pair);
    }
    return valid.join('; ');
  }

  private static isExpiredJwt(value: string): boolean {
    const segments = (value || '').split('.');
    if (segments.length !== 3 || !segments[1]) return false;
    try {
      let payload = segments[1].replace(/-/g, '+').replace(/_/g, '/');
      while (payload.length % 4 !== 0) payload += '=';
      const bytes = new util.Base64Helper().decodeSync(payload);
      const text = util.TextDecoder.create('utf-8').decodeWithStream(bytes, { stream: false });
      const parsed = JSON.parse(text) as Record<string, Object>;
      const expiresAt = Number(parsed['exp'] || 0) * 1000;
      return Number.isFinite(expiresAt) && expiresAt > 0 && expiresAt <= Date.now();
    } catch (_) {
      return false;
    }
  }

  private static targetUrls(url: string): string[] {
    const value = (url || '').trim();
    if (!value) return [];
    const result: string[] = [value];
    if (!/^https?:\/\//i.test(value) && /^[A-Za-z0-9.-]+(?::\d+)?(?:\/.*)?$/.test(value) && value.includes('.')) {
      result.push(`https://${value}`);
    }
    return result;
  }
}
