export class Book {
  bookUrl: string = '';
  tocUrl: string = '';
  origin: string = 'local';
  originName: string = '';
  name: string = '';
  author: string = '';
  kind: string = '';
  customTag: string = '';
  coverUrl: string = '';
  customCoverUrl: string = '';
  intro: string = '';
  customIntro: string = '';
  charset: string = '';
  type: number = 0;
  group: number = 0;
  latestChapterTitle: string = '';
  latestChapterTime: number = 0;
  lastCheckTime: number = 0;
  lastCheckCount: number = 0;
  totalChapterNum: number = 0;
  durChapterTitle: string = '';
  durChapterIndex: number = 0;
  durChapterPos: number = 0;
  durChapterTime: number = 0;
  wordCount: string = '';
  canUpdate: boolean = true;
  order: number = 0;
  originOrder: number = 0;
  variable: string = '';
  readConfig: ReadConfig | null = null;
  syncTime: number = 0;

  constructor() {
    this.latestChapterTime = Date.now();
    this.lastCheckTime = Date.now();
    this.durChapterTime = Date.now();
  }

  private _variableMap: Record<string, string> | null = null;

  get variableMap(): Record<string, string> {
    if (!this._variableMap) {
      try {
        this._variableMap = JSON.parse(this.variable || '{}') as Record<string, string>;
      } catch (e) {
        this._variableMap = {};
      }
    }
    return this._variableMap;
  }

  getVariable(key: string): string {
    return this.variableMap[key] || '';
  }

  putVariable(key: string, value: string): void {
    this.variableMap[key] = value;
    this.variable = JSON.stringify(this.variableMap);
  }

  getRealAuthor(): string {
    return this.author.replace(/[?？]/g, '');
  }

  getUnreadChapterNum(): number {
    return Math.max(this.totalChapterNum - this.durChapterIndex - 1, 0);
  }

  getDisplayCover(): string {
    if (this.customCoverUrl && this.customCoverUrl.length > 0) {
      return this.customCoverUrl;
    }
    return this.coverUrl;
  }

  getDisplayIntro(): string {
    if (this.customIntro && this.customIntro.length > 0) {
      return this.customIntro;
    }
    return this.intro;
  }

  getReverseToc(): boolean {
    return this.readConfig?.reverseToc ?? false;
  }

  setReverseToc(reverseToc: boolean): void {
    if (!this.readConfig) {
      this.readConfig = new ReadConfig();
    }
    this.readConfig.reverseToc = reverseToc;
  }

  getUseReplaceRule(): boolean {
    return this.readConfig?.useReplaceRule ?? true;
  }

  setUseReplaceRule(useReplaceRule: boolean): void {
    if (!this.readConfig) {
      this.readConfig = new ReadConfig();
    }
    this.readConfig.useReplaceRule = useReplaceRule;
  }

  getReSegment(): boolean {
    return this.readConfig?.reSegment ?? false;
  }

  setReSegment(reSegment: boolean): void {
    if (!this.readConfig) {
      this.readConfig = new ReadConfig();
    }
    this.readConfig.reSegment = reSegment;
  }

  getPageAnim(): number {
    return this.readConfig?.pageAnim ?? 0;
  }

  setPageAnim(pageAnim: number): void {
    if (!this.readConfig) {
      this.readConfig = new ReadConfig();
    }
    this.readConfig.pageAnim = pageAnim;
  }

  getImageStyle(): string {
    return this.readConfig?.imageStyle ?? 'DEFAULT';
  }

  setImageStyle(imageStyle: string): void {
    if (!this.readConfig) {
      this.readConfig = new ReadConfig();
    }
    this.readConfig.imageStyle = imageStyle;
  }
}

export class ReadConfig {
  reverseToc: boolean = false;
  pageAnim: number = 0;
  reSegment: boolean = false;
  imageStyle: string = 'DEFAULT';
  useReplaceRule: boolean = true;
  delTag: number = 0;
  ttsEngine: string = '';
  splitLongChapter: boolean = true;
  readSimulating: boolean = false;
  startDate: string = '';
  startChapter: number = 0;
  dailyChapters: number = 3;
}

export class BookChapter {
  url: string = '';
  title: string = '';
  bookUrl: string = '';
  index: number = 0;
  isVip: boolean = false;
  isPay: boolean = false;
  resourceUrl: string = '';
  tag: string = '';
  start: number = 0;
  end: number = 0;
  variable: string = '';

  getDisplayTitle(replaceRules: ReplaceRule[], useReplace: boolean): string {
    if (!useReplace || !replaceRules || replaceRules.length === 0) {
      return this.title;
    }
    let title = this.title;
    for (const rule of replaceRules) {
      if (rule.isRegex) {
        try {
          const regex = new RegExp(rule.pattern, rule.replacement);
          title = title.replace(regex, rule.replacement);
        } catch (e) {
          // 忽略无效的正则表达式
        }
      } else {
        title = title.split(rule.pattern).join(rule.replacement);
      }
    }
    return title;
  }
}

export class BookSource {
  bookSourceUrl: string = '';
  bookSourceName: string = '';
  bookSourceGroup: string = '';
  bookSourceComment: string = '';
  loginUrl: string = '';
  loginUi: string = '';
  loginCheckJs: string = '';
  bookUrlPattern: string = '';
  searchUrl: string = '';
  exploreUrl: string = '';
  header: string = '';
  bookListRule: BookListRule = new BookListRule();
  searchRule: SearchRule = new SearchRule();
  exploreRule: ExploreRule = new ExploreRule();
  bookInfoRule: BookInfoRule = new BookInfoRule();
  tocRule: TocRule = new TocRule();
  contentRule: ContentRule = new ContentRule();
  variableComment: string = '';
  lastUpdateTime: number = 0;
  customOrder: number = 0;
  enabled: boolean = true;
  enabledExplore: boolean = true;
  weight: number = 0;
  concurrentRate: string = '';

  getSearchRule(): SearchRule {
    return this.searchRule;
  }

  getExploreRule(): ExploreRule {
    return this.exploreRule;
  }

  getBookInfoRule(): BookInfoRule {
    return this.bookInfoRule;
  }

  getTocRule(): TocRule {
    return this.tocRule;
  }

  getContentRule(): ContentRule {
    return this.contentRule;
  }
}

export class BookListRule {
  bookList: string = '';
  name: string = '';
  author: string = '';
  coverUrl: string = '';
  intro: string = '';
  kind: string = '';
  lastChapter: string = '';
  bookUrl: string = '';
  wordCount: string = '';
}

export class SearchRule {
  bookList: string = '';
  name: string = '';
  author: string = '';
  coverUrl: string = '';
  intro: string = '';
  kind: string = '';
  lastChapter: string = '';
  bookUrl: string = '';
  wordCount: string = '';
}

export class ExploreRule {
  bookList: string = '';
  name: string = '';
  author: string = '';
  coverUrl: string = '';
  intro: string = '';
  kind: string = '';
  lastChapter: string = '';
  bookUrl: string = '';
  wordCount: string = '';
}

export class BookInfoRule {
  init: string = '';
  name: string = '';
  author: string = '';
  coverUrl: string = '';
  intro: string = '';
  kind: string = '';
  lastChapter: string = '';
  wordCount: string = '';
  updateTime: string = '';
  tocUrl: string = '';
}

export class TocRule {
  chapterList: string = '';
  chapterName: string = '';
  chapterUrl: string = '';
  isVip: string = '';
  isPay: string = '';
  updateTime: string = '';
  chapterListAddition: string = '';
}

export class ContentRule {
  content: string = '';
  title: string = '';
  images: string = '';
  replaceRegex: string = '';
  imageStyle: string = '';
  payAction: string = '';
}

export class ReplaceRule {
  id: number = 0;
  pattern: string = '';
  replacement: string = '';
  isRegex: boolean = false;
  isEnabled: boolean = true;
  name: string = '';
  group: string = '';
  order: number = 0;
}

export class BookGroup {
  groupId: number = 0;
  groupName: string = '';
  order: number = 0;
  show: boolean = true;
  enableRefresh: boolean = true;

  static readonly ID_ALL: number = -2147483648;
  static readonly ID_LOCAL: number = -2147483647;
  static readonly ID_AUDIO: number = -2147483646;
  static readonly ID_NET_NONE: number = -2147483645;
  static readonly ID_LOCAL_NONE: number = -2147483644;
  static readonly ID_ERROR: number = -2147483643;
}

export class Bookmark {
  id: number = 0;
  bookUrl: string = '';
  bookName: string = '';
  bookAuthor: string = '';
  chapterIndex: number = 0;
  chapterName: string = '';
  pageIndex: number = 0;
  startPos: number = 0;
  endPos: number = 0;
  content: string = '';
  createTime: number = 0;
}

export class SearchBook {
  bookUrl: string = '';
  origin: string = '';
  originName: string = '';
  type: number = 0;
  name: string = '';
  author: string = '';
  kind: string = '';
  coverUrl: string = '';
  intro: string = '';
  latestChapterTitle: string = '';
  wordCount: string = '';
  tocUrl: string = '';
  variable: string = '';
  bookSourceComment: string = '';
  customOrder: number = 0;
  weight: number = 0;
}

export class SearchKeyword {
  keyword: string = '';
  usage: number = 0;
  lastUseTime: number = 0;
}

export class Cookie {
  url: string = '';
  cookie: string = '';
}

export class RssSource {
  sourceUrl: string = '';
  sourceName: string = '';
  sourceGroup: string = '';
  sourceComment: string = '';
  sourceIcon: string = '';
  enabled: boolean = true;
  customOrder: number = 0;
  lastUpdateTime: number = 0;
}

export class RssArticle {
  origin: string = '';
  title: string = '';
  content: string = '';
  description: string = '';
  link: string = '';
  image: string = '';
  pubDate: string = '';
  author: string = '';
  categories: string = '';
  read: boolean = false;
  star: boolean = false;
}

export class RssStar {
  origin: string = '';
  title: string = '';
  content: string = '';
  description: string = '';
  link: string = '';
  image: string = '';
  pubDate: string = '';
  author: string = '';
  categories: string = '';
  starTime: number = 0;
}

export class ReadRecord {
  bookName: string = '';
  readTime: number = 0;
  dailyReadTime: number = 0;
  lastReadTime: number = 0;
}

export class HttpTTS {
  id: number = 0;
  name: string = '';
  url: string = '';
  concurrentRate: string = '';
  loginUrl: string = '';
  loginUi: string = '';
  loginCheckJs: string = '';
  header: string = '';
  jsEngine: string = '';
  customOrder: number = 0;
  enabled: boolean = true;
}

export class Cache {
  bookUrl: string = '';
  chapterIndex: number = 0;
  chapterName: string = '';
  cacheDate: number = 0;
}

export class RuleSub {
  id: number = 0;
  name: string = '';
  url: string = '';
  type: number = 0;
  autoRefresh: boolean = false;
  customOrder: number = 0;
  lastUpdateTime: number = 0;
}

export class DictRule {
  id: number = 0;
  name: string = '';
  url: string = '';
  js: string = '';
  body: string = '';
  formatUrl: string = '';
  formatBody: string = '';
  bookSourceUrl: string = '';
  enabled: boolean = true;
  customOrder: number = 0;
}

export class KeyboardAssist {
  id: number = 0;
  type: number = 0;
  key: string = '';
  value: string = '';
  serialNo: number = 0;
}

export class Server {
  id: number = 0;
  type: number = 0;
  name: string = '';
  url: string = '';
  token: string = '';
  enabled: boolean = true;
  customOrder: number = 0;
}
