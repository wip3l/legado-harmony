export class ReaderCustomFontItem {
  familyName: string = '';
  filePath: string = '';
  sourceName: string = '';
}

export class ReaderCustomFontData {
  fonts: ReaderCustomFontItem[] = [];
}

export class ReaderTxtCharsetOption {
  value: string = '';
  label: string = '';
  description: string = '';
  constructor(value: string, label: string, description: string) {
    this.value = value;
    this.label = label;
    this.description = description;
  }
}
