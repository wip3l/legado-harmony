/** Paragraph bubble size in percent; chapter comments retain their original size. */
export class ReaderCommentBubbleSize {
  static readonly DEFAULT: number = 100;
  static readonly MIN: number = 10;
  static readonly MAX: number = 200;

  static normalize(value: number): number {
    if (!Number.isFinite(value)) return ReaderCommentBubbleSize.DEFAULT;
    return Math.max(ReaderCommentBubbleSize.MIN, Math.min(ReaderCommentBubbleSize.MAX, Math.round(value)));
  }

  static scale(label: string, size: number): number {
    return label.includes('本章说') ? 1 : ReaderCommentBubbleSize.normalize(size) / 100;
  }
}
