export class ReaderImageMarkerInfo {
  source: string = '';
  width: number = 0;
  height: number = 0;
}

export class ReaderImageMarker {
  static readonly PREFIX: string = '[[LEGADO_EPUB_IMAGE:';
  static readonly SUFFIX: string = ']]';
  // encodeURIComponent 会转义 "|"，因此它可以无歧义地分隔来源与可选的原始尺寸。
  private static readonly SIZE_SEPARATOR: string = '|';

  static create(source: string, width: number = 0, height: number = 0): string {
    const value = (source || '').trim();
    if (!value) return '';
    const safeWidth = Math.round(width);
    const safeHeight = Math.round(height);
    const size = safeWidth > 0 && safeHeight > 0 ?
      `${ReaderImageMarker.SIZE_SEPARATOR}${safeWidth}x${safeHeight}` : '';
    return `${ReaderImageMarker.PREFIX}${encodeURIComponent(value)}${size}${ReaderImageMarker.SUFFIX}`;
  }

  /**
   * 下载或解密失败的图片：来源写成这个前缀加失败原因，阅读器显示原因而不是去加载它。
   * 只出现在内存里的章节正文中，带有它的章节不写入正文缓存，下次打开会重新获取。
   */
  static readonly FAILURE_SCHEME: string = 'legado-image-error:';

  static failureSource(reason: string): string {
    return `${ReaderImageMarker.FAILURE_SCHEME}${(reason || '图片加载失败').trim()}`;
  }

  /** 失败图片的原因；不是失败图片时为空串。 */
  static failureReason(source: string): string {
    const value = source || '';
    return value.startsWith(ReaderImageMarker.FAILURE_SCHEME) ?
      (value.substring(ReaderImageMarker.FAILURE_SCHEME.length) || '图片加载失败') : '';
  }

  static hasFailure(text: string): boolean {
    return (text || '').includes(
      `${ReaderImageMarker.PREFIX}${encodeURIComponent(ReaderImageMarker.FAILURE_SCHEME)}`);
  }

  /**
   * 渐进加载中还没处理好的图片：来源写成这个前缀加原始图片值，阅读器按原始值等 ReaderImageResults 给出结果。
   * 同样只出现在内存里的章节正文中，整章图片都有结果后才把换成本地路径的正文写入缓存。
   */
  static readonly PENDING_SCHEME: string = 'legado-image-pending:';

  static pendingSource(raw: string): string {
    return `${ReaderImageMarker.PENDING_SCHEME}${raw || ''}`;
  }

  /** 待加载图片的原始图片值；不是待加载图片时为空串。 */
  static pendingRaw(source: string): string {
    const value = source || '';
    return value.startsWith(ReaderImageMarker.PENDING_SCHEME) ?
      value.substring(ReaderImageMarker.PENDING_SCHEME.length) : '';
  }

  static hasPending(text: string): boolean {
    return (text || '').includes(
      `${ReaderImageMarker.PREFIX}${encodeURIComponent(ReaderImageMarker.PENDING_SCHEME)}`);
  }

  static isMarker(value: string): boolean {
    const text = (value || '').trim();
    return text.startsWith(ReaderImageMarker.PREFIX) && text.endsWith(ReaderImageMarker.SUFFIX);
  }

  static parse(value: string): ReaderImageMarkerInfo {
    const info = new ReaderImageMarkerInfo();
    const text = (value || '').trim();
    if (!ReaderImageMarker.isMarker(text)) return info;
    let payload = text.substring(ReaderImageMarker.PREFIX.length, text.length - ReaderImageMarker.SUFFIX.length);
    const separator = payload.lastIndexOf(ReaderImageMarker.SIZE_SEPARATOR);
    if (separator >= 0) {
      const size = /^(\d{1,6})x(\d{1,6})$/.exec(payload.substring(separator + 1));
      if (size) {
        info.width = parseInt(size[1], 10);
        info.height = parseInt(size[2], 10);
        payload = payload.substring(0, separator);
      }
    }
    try {
      info.source = decodeURIComponent(payload);
    } catch (_) {
      info.source = payload;
    }
    return info;
  }
}
