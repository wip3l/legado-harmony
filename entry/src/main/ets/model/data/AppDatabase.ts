import relationalStore from '@ohos.data.relationalStore';
import { Book, BookChapter, BookSource, BookGroup, SearchKeyword } from './Book';
import { Context } from '@kit.AbilityKit';

interface ColumnMigration {
  table: string;
  column: string;
  definition: string;
}

export class AppDatabase {
  private static instance: AppDatabase | null = null;
  private store: relationalStore.RdbStore | null = null;
  private readonly DATABASE_NAME = 'legado.db';

  private constructor() {}

  static getInstance(): AppDatabase {
    if (!AppDatabase.instance) {
      AppDatabase.instance = new AppDatabase();
    }
    return AppDatabase.instance;
  }

  async init(context: Context): Promise<void> {
    const config: relationalStore.StoreConfig = {
      name: this.DATABASE_NAME,
      securityLevel: relationalStore.SecurityLevel.S1
    };

    this.store = await relationalStore.getRdbStore(context, config);
    await this.createTables();
    await this.initDefaultData();
  }

  async initWithContext(context: Context): Promise<void> {
    await this.init(context);
  }

  private async createTables(): Promise<void> {
    if (!this.store) return;

    await this.store.executeSql(`
      CREATE TABLE IF NOT EXISTS books (
        bookUrl TEXT PRIMARY KEY,
        tocUrl TEXT DEFAULT '',
        origin TEXT DEFAULT 'local',
        originName TEXT DEFAULT '',
        name TEXT DEFAULT '',
        author TEXT DEFAULT '',
        kind TEXT,
        customTag TEXT,
        coverUrl TEXT,
        customCoverUrl TEXT,
        intro TEXT,
        customIntro TEXT,
        charset TEXT,
        type INTEGER DEFAULT 0,
        groupId INTEGER DEFAULT 0,
        latestChapterTitle TEXT,
        latestChapterTime INTEGER DEFAULT 0,
        lastCheckTime INTEGER DEFAULT 0,
        lastCheckCount INTEGER DEFAULT 0,
        totalChapterNum INTEGER DEFAULT 0,
        durChapterTitle TEXT,
        durChapterIndex INTEGER DEFAULT 0,
        durChapterPos INTEGER DEFAULT 0,
        durChapterTime INTEGER DEFAULT 0,
        wordCount TEXT,
        canUpdate INTEGER DEFAULT 1,
        bookOrder INTEGER DEFAULT 0,
        originOrder INTEGER DEFAULT 0,
        variable TEXT,
        readConfig TEXT,
        syncTime INTEGER DEFAULT 0
      )
    `);

    await this.store.executeSql(`
      CREATE TABLE IF NOT EXISTS book_sources (
        bookSourceUrl TEXT PRIMARY KEY,
        bookSourceName TEXT DEFAULT '',
        bookSourceGroup TEXT DEFAULT '',
        bookSourceComment TEXT DEFAULT '',
        loginUrl TEXT DEFAULT '',
        loginUi TEXT,
        loginCheckJs TEXT DEFAULT '',
        bookUrlPattern TEXT DEFAULT '',
        searchUrl TEXT DEFAULT '',
        exploreUrl TEXT DEFAULT '',
        header TEXT DEFAULT '',
        bookListRule TEXT DEFAULT '{}',
        searchRule TEXT DEFAULT '{}',
        exploreRule TEXT DEFAULT '{}',
        bookInfoRule TEXT DEFAULT '{}',
        tocRule TEXT DEFAULT '{}',
        contentRule TEXT DEFAULT '{}',
        variableComment TEXT DEFAULT '',
        lastUpdateTime INTEGER DEFAULT 0,
        customOrder INTEGER DEFAULT 0,
        enabled INTEGER DEFAULT 1,
        enabledExplore INTEGER DEFAULT 1,
        weight INTEGER DEFAULT 0,
        concurrentRate TEXT DEFAULT ''
      )
    `);

    await this.store.executeSql(`
      CREATE TABLE IF NOT EXISTS book_chapters (
        url TEXT PRIMARY KEY,
        title TEXT DEFAULT '',
        bookUrl TEXT DEFAULT '',
        chapterIndex INTEGER DEFAULT 0,
        isVip INTEGER DEFAULT 0,
        isPay INTEGER DEFAULT 0,
        resourceUrl TEXT DEFAULT '',
        tag TEXT DEFAULT '',
        startOffset INTEGER DEFAULT 0,
        endOffset INTEGER DEFAULT 0,
        variable TEXT DEFAULT ''
      )
    `);

    await this.store.executeSql(`
      CREATE TABLE IF NOT EXISTS book_groups (
        groupId INTEGER PRIMARY KEY,
        groupName TEXT DEFAULT '',
        groupOrder INTEGER DEFAULT 0,
        show INTEGER DEFAULT 1,
        enableRefresh INTEGER DEFAULT 1
      )
    `);

    await this.store.executeSql(`
      CREATE TABLE IF NOT EXISTS search_keywords (
        keyword TEXT PRIMARY KEY,
        usage INTEGER DEFAULT 0,
        lastUseTime INTEGER DEFAULT 0
      )
    `);

    await this.migrateTables();
  }

  private async migrateTables(): Promise<void> {
    if (!this.store) return;

    const migrations: ColumnMigration[] = [
      { table: 'books', column: 'tocUrl', definition: "tocUrl TEXT DEFAULT ''" },
      { table: 'books', column: 'origin', definition: "origin TEXT DEFAULT 'local'" },
      { table: 'books', column: 'originName', definition: "originName TEXT DEFAULT ''" },
      { table: 'books', column: 'variable', definition: 'variable TEXT' },
      { table: 'book_sources', column: 'searchUrl', definition: "searchUrl TEXT DEFAULT ''" },
      { table: 'book_sources', column: 'exploreUrl', definition: "exploreUrl TEXT DEFAULT ''" },
      { table: 'book_chapters', column: 'variable', definition: "variable TEXT DEFAULT ''" }
    ];

    for (const migration of migrations) {
      await this.addColumnIfMissing(migration);
    }
  }

  private async addColumnIfMissing(migration: ColumnMigration): Promise<void> {
    if (!this.store) return;

    try {
      const resultSet = await this.store.querySql(`PRAGMA table_info(${migration.table})`);
      const nameIndex = resultSet.getColumnIndex('name');
      while (resultSet.goToNextRow()) {
        if (resultSet.getString(nameIndex) === migration.column) {
          return;
        }
      }
      await this.store.executeSql(`ALTER TABLE ${migration.table} ADD COLUMN ${migration.definition}`);
    } catch (e) {
    }
  }

  private async initDefaultData(): Promise<void> {
    if (!this.store) return;

    const resultSet = await this.store.querySql(`SELECT COUNT(*) as count FROM book_groups`);
    if (resultSet.rowCount === 0) {
      await this.store.executeSql(`
        INSERT INTO book_groups (groupId, groupName, groupOrder, show) 
        VALUES (${BookGroup.ID_ALL}, '全部', -10, 1)
      `);
      await this.store.executeSql(`
        INSERT INTO book_groups (groupId, groupName, groupOrder, enableRefresh, show) 
        VALUES (${BookGroup.ID_LOCAL}, '本地', -9, 0, 1)
      `);
      await this.store.executeSql(`
        INSERT INTO book_groups (groupId, groupName, groupOrder, show) 
        VALUES (${BookGroup.ID_AUDIO}, '音频', -8, 1)
      `);
      await this.store.executeSql(`
        INSERT INTO book_groups (groupId, groupName, groupOrder, show) 
        VALUES (${BookGroup.ID_NET_NONE}, '网络未分组', -7, 1)
      `);
      await this.store.executeSql(`
        INSERT INTO book_groups (groupId, groupName, groupOrder, show) 
        VALUES (${BookGroup.ID_LOCAL_NONE}, '本地未分组', -6, 0)
      `);
      await this.store.executeSql(`
        INSERT INTO book_groups (groupId, groupName, groupOrder, show) 
        VALUES (${BookGroup.ID_ERROR}, '更新失败', -1, 1)
      `);
    }
  }

  async insertBook(book: Book): Promise<void> {
    if (!this.store) return;
    const bucket: relationalStore.ValuesBucket = {
      bookUrl: book.bookUrl,
      tocUrl: book.tocUrl,
      origin: book.origin,
      originName: book.originName,
      name: book.name,
      author: book.author,
      kind: book.kind,
      customTag: book.customTag,
      coverUrl: book.coverUrl,
      customCoverUrl: book.customCoverUrl,
      intro: book.intro,
      customIntro: book.customIntro,
      charset: book.charset,
      type: book.type,
      groupId: book.group,
      latestChapterTitle: book.latestChapterTitle,
      latestChapterTime: book.latestChapterTime,
      lastCheckTime: book.lastCheckTime,
      lastCheckCount: book.lastCheckCount,
      totalChapterNum: book.totalChapterNum,
      durChapterTitle: book.durChapterTitle,
      durChapterIndex: book.durChapterIndex,
      durChapterPos: book.durChapterPos,
      durChapterTime: book.durChapterTime,
      wordCount: book.wordCount,
      canUpdate: book.canUpdate ? 1 : 0,
      bookOrder: book.order,
      originOrder: book.originOrder,
      variable: book.variable,
      readConfig: JSON.stringify(book.readConfig),
      syncTime: book.syncTime
    };

    await this.store.insert('books', bucket);
  }

  async updateBook(book: Book): Promise<void> {
    if (!this.store) return;
    const bucket: relationalStore.ValuesBucket = {
      tocUrl: book.tocUrl,
      origin: book.origin,
      originName: book.originName,
      name: book.name,
      author: book.author,
      kind: book.kind,
      customTag: book.customTag,
      coverUrl: book.coverUrl,
      customCoverUrl: book.customCoverUrl,
      intro: book.intro,
      customIntro: book.customIntro,
      charset: book.charset,
      type: book.type,
      groupId: book.group,
      latestChapterTitle: book.latestChapterTitle,
      latestChapterTime: book.latestChapterTime,
      lastCheckTime: book.lastCheckTime,
      lastCheckCount: book.lastCheckCount,
      totalChapterNum: book.totalChapterNum,
      durChapterTitle: book.durChapterTitle,
      durChapterIndex: book.durChapterIndex,
      durChapterPos: book.durChapterPos,
      durChapterTime: book.durChapterTime,
      wordCount: book.wordCount,
      canUpdate: book.canUpdate ? 1 : 0,
      bookOrder: book.order,
      originOrder: book.originOrder,
      variable: book.variable,
      readConfig: JSON.stringify(book.readConfig),
      syncTime: book.syncTime
    };

    const predicates = new relationalStore.RdbPredicates('books');
    predicates.equalTo('bookUrl', book.bookUrl);
    await this.store.update(bucket, predicates);
  }

  async deleteBook(bookUrl: string): Promise<void> {
    if (!this.store) return;
    const predicates = new relationalStore.RdbPredicates('books');
    predicates.equalTo('bookUrl', bookUrl);
    await this.store.delete(predicates);
  }

  async getBook(bookUrl: string): Promise<Book | null> {
    if (!this.store) return null;
    const predicates = new relationalStore.RdbPredicates('books');
    predicates.equalTo('bookUrl', bookUrl);
    const resultSet = await this.store.query(predicates, []);
    if (resultSet.rowCount === 0) return null;

    resultSet.goToFirstRow();
    return this.resultSetToBook(resultSet);
  }

  async getAllBooks(): Promise<Book[]> {
    if (!this.store) return [];
    const predicates = new relationalStore.RdbPredicates('books');
    predicates.orderByDesc('durChapterTime');
    const resultSet = await this.store.query(predicates, []);
    const books: Book[] = [];
    while (resultSet.goToNextRow()) {
      books.push(this.resultSetToBook(resultSet));
    }
    return books;
  }

  private resultSetToBook(resultSet: relationalStore.ResultSet): Book {
    const book = new Book();
    book.bookUrl = resultSet.getString(resultSet.getColumnIndex('bookUrl'));
    book.tocUrl = resultSet.getString(resultSet.getColumnIndex('tocUrl'));
    book.origin = resultSet.getString(resultSet.getColumnIndex('origin'));
    book.originName = resultSet.getString(resultSet.getColumnIndex('originName'));
    book.name = resultSet.getString(resultSet.getColumnIndex('name'));
    book.author = resultSet.getString(resultSet.getColumnIndex('author'));
    book.kind = resultSet.getString(resultSet.getColumnIndex('kind'));
    book.customTag = resultSet.getString(resultSet.getColumnIndex('customTag'));
    book.coverUrl = resultSet.getString(resultSet.getColumnIndex('coverUrl'));
    book.customCoverUrl = resultSet.getString(resultSet.getColumnIndex('customCoverUrl'));
    book.intro = resultSet.getString(resultSet.getColumnIndex('intro'));
    book.customIntro = resultSet.getString(resultSet.getColumnIndex('customIntro'));
    book.charset = resultSet.getString(resultSet.getColumnIndex('charset'));
    book.type = resultSet.getLong(resultSet.getColumnIndex('type'));
    book.group = resultSet.getLong(resultSet.getColumnIndex('groupId'));
    book.latestChapterTitle = resultSet.getString(resultSet.getColumnIndex('latestChapterTitle'));
    book.latestChapterTime = resultSet.getLong(resultSet.getColumnIndex('latestChapterTime'));
    book.lastCheckTime = resultSet.getLong(resultSet.getColumnIndex('lastCheckTime'));
    book.lastCheckCount = resultSet.getLong(resultSet.getColumnIndex('lastCheckCount'));
    book.totalChapterNum = resultSet.getLong(resultSet.getColumnIndex('totalChapterNum'));
    book.durChapterTitle = resultSet.getString(resultSet.getColumnIndex('durChapterTitle'));
    book.durChapterIndex = resultSet.getLong(resultSet.getColumnIndex('durChapterIndex'));
    book.durChapterPos = resultSet.getLong(resultSet.getColumnIndex('durChapterPos'));
    book.durChapterTime = resultSet.getLong(resultSet.getColumnIndex('durChapterTime'));
    book.wordCount = resultSet.getString(resultSet.getColumnIndex('wordCount'));
    book.canUpdate = resultSet.getLong(resultSet.getColumnIndex('canUpdate')) === 1;
    book.order = resultSet.getLong(resultSet.getColumnIndex('bookOrder'));
    book.originOrder = resultSet.getLong(resultSet.getColumnIndex('originOrder'));
    book.variable = resultSet.getString(resultSet.getColumnIndex('variable'));
    const readConfigStr = resultSet.getString(resultSet.getColumnIndex('readConfig'));
    if (readConfigStr) {
      try {
        book.readConfig = JSON.parse(readConfigStr);
      } catch (e) {
        book.readConfig = null;
      }
    }
    book.syncTime = resultSet.getLong(resultSet.getColumnIndex('syncTime'));
    return book;
  }

  async insertBookSource(source: BookSource): Promise<void> {
    if (!this.store) return;
    const bucket: relationalStore.ValuesBucket = {
      bookSourceUrl: source.bookSourceUrl,
      bookSourceName: source.bookSourceName,
      bookSourceGroup: source.bookSourceGroup,
      bookSourceComment: source.bookSourceComment,
      loginUrl: source.loginUrl,
      loginUi: source.loginUi,
      loginCheckJs: source.loginCheckJs,
      bookUrlPattern: source.bookUrlPattern,
      searchUrl: source.searchUrl,
      exploreUrl: source.exploreUrl,
      header: source.header,
      bookListRule: JSON.stringify(source.bookListRule),
      searchRule: JSON.stringify(source.searchRule),
      exploreRule: JSON.stringify(source.exploreRule),
      bookInfoRule: JSON.stringify(source.bookInfoRule),
      tocRule: JSON.stringify(source.tocRule),
      contentRule: JSON.stringify(source.contentRule),
      variableComment: source.variableComment,
      lastUpdateTime: source.lastUpdateTime,
      customOrder: source.customOrder,
      enabled: source.enabled ? 1 : 0,
      enabledExplore: source.enabledExplore ? 1 : 0,
      weight: source.weight,
      concurrentRate: source.concurrentRate
    };

    const predicates = new relationalStore.RdbPredicates('book_sources');
    predicates.equalTo('bookSourceUrl', source.bookSourceUrl);
    const resultSet = await this.store.query(predicates, []);
    if (resultSet.rowCount > 0) {
      await this.store.update(bucket, predicates);
    } else {
      await this.store.insert('book_sources', bucket);
    }
  }

  async updateBookSource(source: BookSource): Promise<void> {
    if (!this.store) return;
    const bucket: relationalStore.ValuesBucket = {
      bookSourceName: source.bookSourceName,
      bookSourceGroup: source.bookSourceGroup,
      bookSourceComment: source.bookSourceComment,
      loginUrl: source.loginUrl,
      loginUi: source.loginUi,
      loginCheckJs: source.loginCheckJs,
      bookUrlPattern: source.bookUrlPattern,
      searchUrl: source.searchUrl,
      exploreUrl: source.exploreUrl,
      header: source.header,
      bookListRule: JSON.stringify(source.bookListRule),
      searchRule: JSON.stringify(source.searchRule),
      exploreRule: JSON.stringify(source.exploreRule),
      bookInfoRule: JSON.stringify(source.bookInfoRule),
      tocRule: JSON.stringify(source.tocRule),
      contentRule: JSON.stringify(source.contentRule),
      variableComment: source.variableComment,
      lastUpdateTime: source.lastUpdateTime,
      customOrder: source.customOrder,
      enabled: source.enabled ? 1 : 0,
      enabledExplore: source.enabledExplore ? 1 : 0,
      weight: source.weight,
      concurrentRate: source.concurrentRate
    };

    const predicates = new relationalStore.RdbPredicates('book_sources');
    predicates.equalTo('bookSourceUrl', source.bookSourceUrl);
    await this.store.update(bucket, predicates);
  }

  async deleteBookSource(bookSourceUrl: string): Promise<void> {
    if (!this.store) return;
    const predicates = new relationalStore.RdbPredicates('book_sources');
    predicates.equalTo('bookSourceUrl', bookSourceUrl);
    await this.store.delete(predicates);
  }

  async getBookSource(bookSourceUrl: string): Promise<BookSource | null> {
    if (!this.store) return null;
    const predicates = new relationalStore.RdbPredicates('book_sources');
    predicates.equalTo('bookSourceUrl', bookSourceUrl);
    const resultSet = await this.store.query(predicates, []);
    if (resultSet.rowCount === 0) return null;

    resultSet.goToFirstRow();
    return this.resultSetToBookSource(resultSet);
  }

  async getAllBookSources(): Promise<BookSource[]> {
    if (!this.store) return [];
    const predicates = new relationalStore.RdbPredicates('book_sources');
    predicates.orderByAsc('customOrder');
    const resultSet = await this.store.query(predicates, []);
    const sources: BookSource[] = [];
    while (resultSet.goToNextRow()) {
      sources.push(this.resultSetToBookSource(resultSet));
    }
    return sources;
  }

  async getEnabledBookSources(): Promise<BookSource[]> {
    if (!this.store) return [];
    const predicates = new relationalStore.RdbPredicates('book_sources');
    predicates.equalTo('enabled', 1);
    predicates.orderByAsc('customOrder');
    const resultSet = await this.store.query(predicates, []);
    const sources: BookSource[] = [];
    while (resultSet.goToNextRow()) {
      sources.push(this.resultSetToBookSource(resultSet));
    }
    return sources;
  }

  async searchBookSources(keyword: string): Promise<BookSource[]> {
    if (!this.store) return [];
    const predicates = new relationalStore.RdbPredicates('book_sources');
    predicates.like('bookSourceName', `%${keyword}%`);
    predicates.orderByAsc('customOrder');
    const resultSet = await this.store.query(predicates, []);
    const sources: BookSource[] = [];
    while (resultSet.goToNextRow()) {
      sources.push(this.resultSetToBookSource(resultSet));
    }
    return sources;
  }

  private resultSetToBookSource(resultSet: relationalStore.ResultSet): BookSource {
    const source = new BookSource();
    source.bookSourceUrl = resultSet.getString(resultSet.getColumnIndex('bookSourceUrl'));
    source.bookSourceName = resultSet.getString(resultSet.getColumnIndex('bookSourceName'));
    source.bookSourceGroup = resultSet.getString(resultSet.getColumnIndex('bookSourceGroup'));
    source.bookSourceComment = resultSet.getString(resultSet.getColumnIndex('bookSourceComment'));
    source.loginUrl = resultSet.getString(resultSet.getColumnIndex('loginUrl'));
    source.loginUi = resultSet.getString(resultSet.getColumnIndex('loginUi'));
    source.loginCheckJs = resultSet.getString(resultSet.getColumnIndex('loginCheckJs'));
    source.bookUrlPattern = resultSet.getString(resultSet.getColumnIndex('bookUrlPattern'));
    const searchUrlIndex = resultSet.getColumnIndex('searchUrl');
    source.searchUrl = searchUrlIndex >= 0 ? resultSet.getString(searchUrlIndex) : '';
    const exploreUrlIndex = resultSet.getColumnIndex('exploreUrl');
    source.exploreUrl = exploreUrlIndex >= 0 ? resultSet.getString(exploreUrlIndex) : '';
    source.header = resultSet.getString(resultSet.getColumnIndex('header'));
    try {
      source.bookListRule = JSON.parse(resultSet.getString(resultSet.getColumnIndex('bookListRule')));
    } catch (e) {}
    try {
      source.searchRule = JSON.parse(resultSet.getString(resultSet.getColumnIndex('searchRule')));
    } catch (e) {}
    try {
      source.exploreRule = JSON.parse(resultSet.getString(resultSet.getColumnIndex('exploreRule')));
    } catch (e) {}
    try {
      source.bookInfoRule = JSON.parse(resultSet.getString(resultSet.getColumnIndex('bookInfoRule')));
    } catch (e) {}
    try {
      source.tocRule = JSON.parse(resultSet.getString(resultSet.getColumnIndex('tocRule')));
    } catch (e) {}
    try {
      source.contentRule = JSON.parse(resultSet.getString(resultSet.getColumnIndex('contentRule')));
    } catch (e) {}
    source.variableComment = resultSet.getString(resultSet.getColumnIndex('variableComment'));
    source.lastUpdateTime = resultSet.getLong(resultSet.getColumnIndex('lastUpdateTime'));
    source.customOrder = resultSet.getLong(resultSet.getColumnIndex('customOrder'));
    source.enabled = resultSet.getLong(resultSet.getColumnIndex('enabled')) === 1;
    source.enabledExplore = resultSet.getLong(resultSet.getColumnIndex('enabledExplore')) === 1;
    source.weight = resultSet.getLong(resultSet.getColumnIndex('weight'));
    source.concurrentRate = resultSet.getString(resultSet.getColumnIndex('concurrentRate'));
    return source;
  }

  async insertBookChapter(chapter: BookChapter): Promise<void> {
    if (!this.store) return;
    const bucket: relationalStore.ValuesBucket = {
      url: chapter.url,
      title: chapter.title,
      bookUrl: chapter.bookUrl,
      chapterIndex: chapter.index,
      isVip: chapter.isVip ? 1 : 0,
      isPay: chapter.isPay ? 1 : 0,
      resourceUrl: chapter.resourceUrl,
      tag: chapter.tag,
      startOffset: chapter.start,
      endOffset: chapter.end,
      variable: chapter.variable
    };

    await this.store.insert('book_chapters', bucket);
  }

  async insertBookChapters(chapters: BookChapter[]): Promise<void> {
    if (!this.store) return;
    for (const chapter of chapters) {
      await this.insertBookChapter(chapter);
    }
  }

  async deleteBookChapters(bookUrl: string): Promise<void> {
    if (!this.store) return;
    const predicates = new relationalStore.RdbPredicates('book_chapters');
    predicates.equalTo('bookUrl', bookUrl);
    await this.store.delete(predicates);
  }

  async getBookChapters(bookUrl: string): Promise<BookChapter[]> {
    if (!this.store) return [];
    const predicates = new relationalStore.RdbPredicates('book_chapters');
    predicates.equalTo('bookUrl', bookUrl);
    predicates.orderByAsc('chapterIndex');
    const resultSet = await this.store.query(predicates, []);
    const chapters: BookChapter[] = [];
    while (resultSet.goToNextRow()) {
      chapters.push(this.resultSetToBookChapter(resultSet));
    }
    return chapters;
  }

  async getBookChapterCount(bookUrl: string): Promise<number> {
    if (!this.store) return 0;
    const predicates = new relationalStore.RdbPredicates('book_chapters');
    predicates.equalTo('bookUrl', bookUrl);
    const resultSet = await this.store.query(predicates, []);
    return resultSet.rowCount;
  }

  private resultSetToBookChapter(resultSet: relationalStore.ResultSet): BookChapter {
    const chapter = new BookChapter();
    chapter.url = resultSet.getString(resultSet.getColumnIndex('url'));
    chapter.title = resultSet.getString(resultSet.getColumnIndex('title'));
    chapter.bookUrl = resultSet.getString(resultSet.getColumnIndex('bookUrl'));
    chapter.index = resultSet.getLong(resultSet.getColumnIndex('chapterIndex'));
    chapter.isVip = resultSet.getLong(resultSet.getColumnIndex('isVip')) === 1;
    chapter.isPay = resultSet.getLong(resultSet.getColumnIndex('isPay')) === 1;
    chapter.resourceUrl = resultSet.getString(resultSet.getColumnIndex('resourceUrl'));
    chapter.tag = resultSet.getString(resultSet.getColumnIndex('tag'));
    chapter.start = resultSet.getLong(resultSet.getColumnIndex('startOffset'));
    chapter.end = resultSet.getLong(resultSet.getColumnIndex('endOffset'));
    chapter.variable = resultSet.getString(resultSet.getColumnIndex('variable'));
    return chapter;
  }

  async getSearchKeywords(): Promise<SearchKeyword[]> {
    if (!this.store) return [];
    const predicates = new relationalStore.RdbPredicates('search_keywords');
    predicates.orderByDesc('lastUseTime');
    const resultSet = await this.store.query(predicates, []);
    const keywords: SearchKeyword[] = [];
    while (resultSet.goToNextRow()) {
      const keyword = new SearchKeyword();
      keyword.keyword = resultSet.getString(resultSet.getColumnIndex('keyword'));
      keyword.usage = resultSet.getLong(resultSet.getColumnIndex('usage'));
      keyword.lastUseTime = resultSet.getLong(resultSet.getColumnIndex('lastUseTime'));
      keywords.push(keyword);
    }
    return keywords;
  }

  async saveSearchKeyword(keyword: string): Promise<void> {
    if (!this.store) return;

    const predicates = new relationalStore.RdbPredicates('search_keywords');
    predicates.equalTo('keyword', keyword);
    const resultSet = await this.store.query(predicates, []);

    if (resultSet.rowCount > 0) {
      resultSet.goToFirstRow();
      const usage = resultSet.getLong(resultSet.getColumnIndex('usage')) + 1;
      const bucket: relationalStore.ValuesBucket = {
        usage: usage,
        lastUseTime: Date.now()
      };
      await this.store.update(bucket, predicates);
    } else {
      const bucket: relationalStore.ValuesBucket = {
        keyword: keyword,
        usage: 1,
        lastUseTime: Date.now()
      };
      await this.store.insert('search_keywords', bucket);
    }
  }

  async clearSearchKeywords(): Promise<void> {
    if (!this.store) return;
    await this.store.executeSql('DELETE FROM search_keywords');
  }
}

export const appDb = AppDatabase.getInstance();
