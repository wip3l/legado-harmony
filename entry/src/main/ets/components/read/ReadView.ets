@Component
export struct ReadView {
  @Prop content: string = '';
  @Prop fontSize: number = 20;
  @Prop lineHeight: number = 1.5;
  @Prop textColor: string = '#333333';
  @Prop backgroundColor: string = '#F5F5F5';
  @Link currentPage: number;
  @Link totalPages: number;
  
  private pages: string[] = [];
  private viewWidth: number = 0;
  private viewHeight: number = 0;

  aboutToAppear() {
    this.paginate();
  }

  aboutToDisappear() {
    // 清理资源
  }

  onAreaChange(oldValue: Area, newValue: Area) {
    this.viewWidth = newValue.width as number;
    this.viewHeight = newValue.height as number;
    this.paginate();
  }

  build() {
    Column() {
      if (this.pages.length > 0 && this.currentPage < this.pages.length) {
        Text(this.pages[this.currentPage])
          .fontSize(this.fontSize)
          .lineHeight(this.fontSize * this.lineHeight)
          .fontColor(this.textColor)
          .padding({ left: 16, right: 16, top: 16, bottom: 16 })
          .width('100%')
          .height('100%')
      } else {
        Text('暂无内容')
          .fontSize(16)
          .fontColor('#999')
          .width('100%')
          .height('100%')
          .textAlign(TextAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.backgroundColor)
    .gesture(
      PanGesture({ direction: PanDirection.Horizontal })
        .onActionStart((event: GestureEvent) => {
          // 手势开始
        })
        .onActionUpdate((event: GestureEvent) => {
          // 手势更新
        })
        .onActionEnd((event: GestureEvent) => {
          if (event.offsetX < -50) {
            // 向左滑动，下一页
            this.nextPage();
          } else if (event.offsetX > 50) {
            // 向右滑动，上一页
            this.prevPage();
          }
        })
    )
  }

  private paginate() {
    if (!this.content || this.viewWidth <= 0 || this.viewHeight <= 0) {
      this.pages = [];
      this.totalPages = 0;
      return;
    }

    this.pages = [];
    const text = this.content;
    const padding = 32; // 左右各16
    const availableWidth = this.viewWidth - padding;
    const availableHeight = this.viewHeight - 32; // 上下各16
    const charWidth = this.fontSize * 0.6; // 估算字符宽度
    const lineHeight = this.fontSize * this.lineHeight;
    const charsPerLine = Math.floor(availableWidth / charWidth);
    const linesPerPage = Math.floor(availableHeight / lineHeight);
    const charsPerPage = charsPerLine * linesPerPage;

    let remaining = text;
    while (remaining.length > 0) {
      if (remaining.length <= charsPerPage) {
        this.pages.push(remaining);
        remaining = '';
      } else {
        // 找到合适的断行位置
        let breakPoint = charsPerPage;
        const lastNewline = remaining.lastIndexOf('\n', charsPerPage);
        if (lastNewline > charsPerPage * 0.7) {
          breakPoint = lastNewline + 1;
        }
        this.pages.push(remaining.substring(0, breakPoint));
        remaining = remaining.substring(breakPoint);
      }
    }

    this.totalPages = this.pages.length;
    if (this.currentPage >= this.totalPages) {
      this.currentPage = Math.max(0, this.totalPages - 1);
    }
  }

  nextPage() {
    if (this.currentPage < this.totalPages - 1) {
      this.currentPage++;
    }
  }

  prevPage() {
    if (this.currentPage > 0) {
      this.currentPage--;
    }
  }

  goToPage(page: number) {
    if (page >= 0 && page < this.totalPages) {
      this.currentPage = page;
    }
  }
}

@Component
export struct PageIndicator {
  @Prop currentPage: number = 0;
  @Prop totalPages: number = 0;

  build() {
    Row() {
      Text(`${this.currentPage + 1}/${this.totalPages}`)
        .fontSize(12)
        .fontColor('#999')
    }
    .width('100%')
    .height(24)
    .justifyContent(FlexAlign.Center)
  }
}

@Component
export struct ChapterTitle {
  @Prop title: string = '';

  build() {
    Row() {
      Text(this.title)
        .fontSize(14)
        .fontColor('#666')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height(24)
    .padding({ left: 16, right: 16 })
  }
}

export class ReadConfig {
  fontSize: number = 20;
  lineHeight: number = 1.5;
  textColor: string = '#333333';
  backgroundColor: string = '#F5F5F5';
  pageAnim: number = 0;
  brightness: number = 1;
  volumeKeyTurn: boolean = false;
  fullScreen: boolean = true;
  keepScreenOn: boolean = true;

  static fromJson(json: string): ReadConfig {
    try {
      return JSON.parse(json) as ReadConfig;
    } catch (e) {
      return new ReadConfig();
    }
  }

  toJson(): string {
    return JSON.stringify(this);
  }
}

export class TextPage {
  lines: TextLine[] = [];
  title: string = '';
  pagePosition: number = 0;

  getContent(): string {
    return this.lines.map(line => line.text).join('\n');
  }
}

export class TextLine {
  text: string = '';
  isTitle: boolean = false;
  isImage: boolean = false;
  imageUrl: string = '';
  height: number = 0;
  width: number = 0;
}

export class TextChapter {
  title: string = '';
  pages: TextPage[] = [];
  chapterIndex: number = 0;
  isCompleted: boolean = false;

  getPageCount(): number {
    return this.pages.length;
  }

  getPage(index: number): TextPage | null {
    if (index >= 0 && index < this.pages.length) {
      return this.pages[index];
    }
    return null;
  }
}

export class ChapterProvider {
  static async layoutChapter(
    content: string,
    title: string,
    width: number,
    height: number,
    fontSize: number,
    lineHeight: number
  ): Promise<TextChapter> {
    const chapter = new TextChapter();
    chapter.title = title;
    
    if (!content) {
      chapter.isCompleted = true;
      return chapter;
    }

    const padding = 32;
    const availableWidth = width - padding;
    const availableHeight = height - 32;
    const charWidth = fontSize * 0.6;
    const lineH = fontSize * lineHeight;
    const charsPerLine = Math.floor(availableWidth / charWidth);
    const linesPerPage = Math.floor(availableHeight / lineH);

    const lines = this.splitIntoLines(content, charsPerLine);
    
    let currentPage = new TextPage();
    let lineCount = 0;

    for (const line of lines) {
      if (lineCount >= linesPerPage) {
        chapter.pages.push(currentPage);
        currentPage = new TextPage();
        lineCount = 0;
      }

      const textLine = new TextLine();
      textLine.text = line;
      textLine.height = lineH;
      currentPage.lines.push(textLine);
      lineCount++;
    }

    if (currentPage.lines.length > 0) {
      chapter.pages.push(currentPage);
    }

    chapter.isCompleted = true;
    return chapter;
  }

  private static splitIntoLines(content: string, charsPerLine: number): string[] {
    const lines: string[] = [];
    const paragraphs = content.split('\n');

    for (const paragraph of paragraphs) {
      if (paragraph.length <= charsPerLine) {
        lines.push(paragraph);
      } else {
        let remaining = paragraph;
        while (remaining.length > 0) {
          if (remaining.length <= charsPerLine) {
            lines.push(remaining);
            remaining = '';
          } else {
            lines.push(remaining.substring(0, charsPerLine));
            remaining = remaining.substring(charsPerLine);
          }
        }
      }
    }

    return lines;
  }
}