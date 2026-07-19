export class ReaderImageMarker {
  static readonly PREFIX: string = '[[LEGADO_EPUB_IMAGE:';
  static readonly SUFFIX: string = ']]';

  static create(source: string): string {
    const value = (source || '').trim();
    if (!value) return '';
    return `${ReaderImageMarker.PREFIX}${encodeURIComponent(value)}${ReaderImageMarker.SUFFIX}`;
  }
}
