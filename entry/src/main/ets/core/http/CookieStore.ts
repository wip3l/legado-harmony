import { webview } from '@kit.ArkWeb';

export class CookieStore {
  static getCookie(url: string): string {
    if (!url) return '';
    try {
      return webview.WebCookieManager.fetchCookieSync(url) || '';
    } catch (_) {
      return '';
    }
  }

  static setCookies(url: string, cookies: string): void {
    if (!url || !cookies) return;
    const values = this.splitSetCookie(cookies);
    for (const value of values) {
      try {
        webview.WebCookieManager.configCookieSync(url, value, false, true);
      } catch (_) {
        try {
          webview.WebCookieManager.configCookieSync(url, value);
        } catch (_) {}
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

  static saveAsync(): void {
    try {
      webview.WebCookieManager.saveCookieAsync();
    } catch (_) {}
  }

  private static splitSetCookie(cookies: string): string[] {
    if (!cookies) return [];
    if (!cookies.includes(',')) return [cookies.trim()].filter(v => v.length > 0);
    const values: string[] = [];
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
        values.push(cookies.substring(start, i).trim());
        start = i + 1;
      }
    }
    values.push(cookies.substring(start).trim());
    return values.filter(v => v.length > 0);
  }
}
