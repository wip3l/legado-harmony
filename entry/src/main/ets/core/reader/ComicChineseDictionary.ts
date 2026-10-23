/**
 * OpenCC ver.1.1.9 的 TSPhrases + TSCharacters 字典适配器。
 * 词组最长匹配，候选取第一项；只实现本功能所需的 t2s，不声称是完整 OpenCC 引擎。
 */
export class ComicChineseDictionary {
  private readonly entries: Map<string, string> = new Map();
  private maxLength: number = 1;

  constructor(characters: string, phrases: string) {
    this.add(characters);
    this.add(phrases);
    if (this.entries.size < 1000) throw new Error('简繁字典不完整');
  }

  private add(raw: string): void {
    for (const line of raw.split(/\r?\n/)) {
      if (!line || line.startsWith('#')) continue;
      const tab = line.indexOf('\t');
      if (tab <= 0) continue;
      const source = line.substring(0, tab);
      const target = line.substring(tab + 1).trim().split(' ')[0];
      if (!target) continue;
      this.entries.set(source, target);
      this.maxLength = Math.max(this.maxLength, source.length);
    }
  }

  convert(text: string): string {
    const output: string[] = [];
    for (let offset = 0; offset < text.length;) {
      let matched = false;
      for (let size = Math.min(this.maxLength, text.length - offset); size > 0; size--) {
        const target = this.entries.get(text.substring(offset, offset + size));
        if (target !== undefined) {
          output.push(target);
          offset += size;
          matched = true;
          break;
        }
      }
      if (!matched) {
        const code = text.codePointAt(offset);
        const size = code !== undefined && code > 0xFFFF ? 2 : 1;
        output.push(text.substring(offset, offset + size));
        offset += size;
      }
    }
    return output.join('');
  }
}
