export class BookFieldSanitizer {
  static prefer(newValue: string, fallback: string): string {
    const cleaned = BookFieldSanitizer.clean(newValue);
    return cleaned || BookFieldSanitizer.clean(fallback);
  }

  static clean(value: string): string {
    const text = (value || '').trim();
    if (!text || BookFieldSanitizer.isUnresolved(text)) {
      return '';
    }
    return text
      .replace(/&nbsp;/gi, ' ')
      .replace(/&lrm;/gi, '')
      .replace(/<br\s*\/?>/gi, '\n')
      .replace(/<[^>]+>/g, '')
      .replace(/\n{3,}/g, '\n\n')
      .trim();
  }

  static isUnresolved(value: string): boolean {
    const text = (value || '').trim();
    if (!text) return true;
    return text.includes('{{') || text.includes('}}') || text.includes('@js:') || text.includes('java.') ||
      text.includes('result.replace') || /(^|[^\w])\$\.\.?[A-Za-z_]/.test(text);
  }
}
