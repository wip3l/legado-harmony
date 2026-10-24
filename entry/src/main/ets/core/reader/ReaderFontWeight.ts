/** Shared numeric weights for typography controls, persistence and layout. */
export class ReaderFontWeight {
  static readonly DEFAULT: number = 400;
  static readonly MIN: number = 50;
  static readonly MAX: number = 900;
  static readonly STEP: number = 50;

  static normalize(value: number): number {
    if (!Number.isFinite(value)) return ReaderFontWeight.DEFAULT;
    return Math.max(ReaderFontWeight.MIN, Math.min(ReaderFontWeight.MAX,
      Math.round(value)));
  }
}
