/** 正文段首缩进的字符数；旧设置未保存此项时保持两字符。 */
export class ReaderParagraphIndent {
  static readonly DEFAULT: number = 2;

  static normalize(value: number): number {
    return Number.isFinite(value) ? Math.max(0, Math.min(4, Math.round(value))) : ReaderParagraphIndent.DEFAULT;
  }

  /** 缩进改变了正文字符偏移，按相同行内的正文位置恢复阅读锚点。 */
  static remapOffset(source: string, target: string, offset: number): number {
    if (!source || source === target) return offset;
    const sourceLines = source.split('\n');
    const targetLines = target.split('\n');
    if (sourceLines.length !== targetLines.length) return offset;
    let sourceStart = 0;
    let targetStart = 0;
    for (let index = 0; index < sourceLines.length; index++) {
      const before = sourceLines[index];
      const after = targetLines[index];
      const beforeText = before.replace(/^[\t \u3000]+/, '');
      const afterText = after.replace(/^[\t \u3000]+/, '');
      if (beforeText !== afterText) return offset;
      if (offset <= sourceStart + before.length) {
        const contentOffset = offset - sourceStart - (before.length - beforeText.length);
        return targetStart + (contentOffset < 0 ? 0 : after.length - afterText.length + contentOffset);
      }
      sourceStart += before.length + 1;
      targetStart += after.length + 1;
    }
    return target.length;
  }
}
