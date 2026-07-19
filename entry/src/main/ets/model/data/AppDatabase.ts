import relationalStore from '@ohos.data.relationalStore';
import { Book, BookChapter, BookSource, BookGroup, Bookmark, SearchKeyword } from './Book';
import { Context } from '@kit.AbilityKit';

interface ColumnMigration {
  table: string;
  column: string;
  definition: string;
}

export class ReaderPaginationCacheRecord {
  starts: number[] = [];
  ends: number[] = [];
}

export class AppDatabase {
  private static instance: AppDatabase | null = null;
  private store: relationalStore.RdbStore | null = null;
  private initialized: boolean = false;
  private initPromise: Promise<void> | null = null;
  private readonly DATABASE_NAME = 'legado.db';
  private readonly SCHEMA_VERSION = 6;

  private constructor() {}

  static getInstance(): AppDatabase {
    if (!AppDatabase.instance) {
      AppDatabase.instance = new AppDatabase();
    }
    return AppDatabase.instance;
  }

  async init(context: Context): Promise<void> {
    if (this.initialized && this.store) {
      return;
    }
    if (this.initPromise) {
      await this.initPromise;
      return;
    }

    this.initPromise = this.initInternal(context);
    try {
      await this.initPromise;
    } finally {
      this.initPromise = null;
    }
  }

  private async initInternal(context: Context): Promise<void> {
    const config: relationalStore.StoreConfig = {
      name: this.DATABASE_NAME,
      securityLevel: relationalStore.SecurityLevel.S1
    };

    this.store = await relationalStore.getRdbStore(context, config);
    await this.createTables();
    await this.initDefaultData();
    this.initialized = true;
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
        loginHeader TEXT DEFAULT '',
        bookUrlPattern TEXT DEFAULT '',
        searchUrl TEXT DEFAULT '',
        exploreUrl TEXT DEFAULT '',
        jsLib TEXT DEFAULT '',
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
        isLocked INTEGER DEFAULT 0,
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
      CREATE TABLE IF NOT EXISTS book_contents (
        bookUrl TEXT DEFAULT '',
        chapterIndex INTEGER DEFAULT 0,
        chapterUrl TEXT DEFAULT '',
        chapterName TEXT DEFAULT '',
        content TEXT DEFAULT '',
        cacheDate INTEGER DEFAULT 0,
        PRIMARY KEY (bookUrl, chapterIndex)
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

    await this.store.executeSql(`
      CREATE TABLE IF NOT EXISTS reader_pagination_cache (
        bookUrl TEXT DEFAULT '',
        chapterIndex INTEGER DEFAULT 0,
        layoutKey TEXT DEFAULT '',
        starts TEXT DEFAULT '[]',
        ends TEXT DEFAULT '[]',
        updateTime INTEGER DEFAULT 0,
        PRIMARY KEY (bookUrl, chapterIndex, layoutKey)
      )
    `);

    await this.store.executeSql(`
      CREATE TABLE IF NOT EXISTS bookmarks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        bookUrl TEXT DEFAULT '',
        bookName TEXT DEFAULT '',
        bookAuthor TEXT DEFAULT '',
        chapterIndex INTEGER DEFAULT 0,
        chapterName TEXT DEFAULT '',
        pageIndex INTEGER DEFAULT 0,
        startPos INTEGER DEFAULT 0,
        endPos INTEGER DEFAULT 0,
        content TEXT DEFAULT '',
        createTime INTEGER DEFAULT 0,
        UNIQUE(bookUrl, chapterIndex, pageIndex)
      )
    `);

    await this.store.executeSql(`
      CREATE TABLE IF NOT EXISTS schema_meta (
        key TEXT PRIMARY KEY,
        value INTEGER DEFAULT 0
      )
    `);

    const schemaVersion = await this.getSchemaVersion();
    if (schemaVersion < this.SCHEMA_VERSION) {
      await this.migrateTables();
      await this.setSchemaVersion(this.SCHEMA_VERSION);
    }
  }

  private async getSchemaVersion(): Promise<number> {
    if (!this.store) return 0;

    try {
      const resultSet = await this.store.querySql(`SELECT value FROM schema_meta WHERE key = 'schema_version'`);
      if (resultSet.goToFirstRow()) {
        return resultSet.getLong(resultSet.getColumnIndex('value'));
      }
    } catch (e) {
    }
    return 0;
  }

  private async setSchemaVersion(version: number): Promise<void> {
    if (!this.store) return;

    try {
      await this.store.executeSql(`DELETE FROM schema_meta WHERE key = 'schema_version'`);
      await this.store.executeSql(`INSERT INTO schema_meta (key, value) VALUES ('schema_version', ${version})`);
    } catch (e) {
    }
  }

  private async migrateTables(): Promise<void> {
    if (!this.store) return;

    const migrations: ColumnMigration[] = [
      { table: 'books', column: 'tocUrl', definition: "tocUrl TEXT DEFAULT ''" },
      { table: 'books', column: 'origin', definition: "origin TEXT DEFAULT 'local'" },
      { table: 'books', column: 'originName', definition: "originName TEXT DEFAULT ''" },
      { table: 'books', column: 'kind', definition: "kind TEXT DEFAULT ''" },
      { table: 'books', column: 'customTag', definition: "customTag TEXT DEFAULT ''" },
      { table: 'books', column: 'coverUrl', definition: "coverUrl TEXT DEFAULT ''" },
      { table: 'books', column: 'customCoverUrl', definition: "customCoverUrl TEXT DEFAULT ''" },
      { table: 'books', column: 'intro', definition: "intro TEXT DEFAULT ''" },
      { table: 'books', column: 'customIntro', definition: "customIntro TEXT DEFAULT ''" },
      { table: 'books', column: 'charset', definition: "charset TEXT DEFAULT ''" },
      { table: 'books', column: 'type', definition: 'type INTEGER DEFAULT 0' },
      { table: 'books', column: 'groupId', definition: 'groupId INTEGER DEFAULT 0' },
      { table: 'books', column: 'latestChapterTitle', definition: "latestChapterTitle TEXT DEFAULT ''" },
      { table: 'books', column: 'latestChapterTime', definition: 'latestChapterTime INTEGER DEFAULT 0' },
      { table: 'books', column: 'lastCheckTime', definition: 'lastCheckTime INTEGER DEFAULT 0' },
      { table: 'books', column: 'lastCheckCount', definition: 'lastCheckCount INTEGER DEFAULT 0' },
      { table: 'books', column: 'totalChapterNum', definition: 'totalChapterNum INTEGER DEFAULT 0' },
      { table: 'books', column: 'durChapterTitle', definition: "durChapterTitle TEXT DEFAULT ''" },
      { table: 'books', column: 'durChapterIndex', definition: 'durChapterIndex INTEGER DEFAULT 0' },
      { table: 'books', column: 'durChapterPos', definition: 'durChapterPos INTEGER DEFAULT 0' },
      { table: 'books', column: 'durChapterTime', definition: 'durChapterTime INTEGER DEFAULT 0' },
      { table: 'books', column: 'wordCount', definition: "wordCount TEXT DEFAULT ''" },
      { table: 'books', column: 'canUpdate', definition: 'canUpdate INTEGER DEFAULT 1' },
      { table: 'books', column: 'bookOrder', definition: 'bookOrder INTEGER DEFAULT 0' },
      { table: 'books', column: 'originOrder', definition: 'originOrder INTEGER DEFAULT 0' },
      { table: 'books', column: 'variable', definition: 'variable TEXT' },
      { table: 'books', column: 'readConfig', definition: 'readConfig TEXT' },
      { table: 'books', column: 'syncTime', definition: 'syncTime INTEGER DEFAULT 0' },
      { table: 'book_sources', column: 'searchUrl', definition: "searchUrl TEXT DEFAULT ''" },
      { table: 'book_sources', column: 'exploreUrl', definition: "exploreUrl TEXT DEFAULT ''" },
      { table: 'book_sources', column: 'jsLib', definition: "jsLib TEXT DEFAULT ''" },
      { table: 'book_sources', column: 'loginHeader', definition: "loginHeader TEXT DEFAULT ''" },
      { table: 'book_sources', column: 'isLocked', definition: 'isLocked INTEGER DEFAULT 0' },
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

  async updateBookReadingProgress(bookUrl: string, chapterTitle: string, chapterIndex: number,
    chapterPos: number, chapterTime: number, variable: string): Promise<void> {
    if (!this.store || !bookUrl) return;
    const bucket: relationalStore.ValuesBucket = {
      durChapterTitle: chapterTitle,
      durChapterIndex: chapterIndex,
      durChapterPos: chapterPos,
      durChapterTime: chapterTime,
      variable: variable
    };
    const predicates = new relationalStore.RdbPredicates('books');
    predicates.equalTo('bookUrl', bookUrl);
    await this.store.update(bucket, predicates);
  }

  async deleteBook(bookUrl: string): Promise<void> {
    if (!this.store) return;
    const predicates = new relationalStore.RdbPredicates('books');
    predicates.equalTo('bookUrl', bookUrl);
    await this.store.delete(predicates);
    await this.deleteBookChapters(bookUrl);
    await this.deleteBookCachedContent(bookUrl);
    await this.deleteBookBookmarks(bookUrl);
  }

  async insertBookmark(bookmark: Bookmark): Promise<number> {
    if (!this.store) return 0;
    const bucket: relationalStore.ValuesBucket = {
      bookUrl: bookmark.bookUrl,
      bookName: bookmark.bookName,
      bookAuthor: bookmark.bookAuthor,
      chapterIndex: bookmark.chapterIndex,
      chapterName: bookmark.chapterName,
      pageIndex: bookmark.pageIndex,
      startPos: bookmark.startPos,
      endPos: bookmark.endPos,
      content: bookmark.content,
      createTime: bookmark.createTime
    };
    return await this.store.insert('bookmarks', bucket);
  }

  async getBookmarks(bookUrl: string): Promise<Bookmark[]> {
    const bookmarks: Bookmark[] = [];
    if (!this.store || !bookUrl) return bookmarks;
    const predicates = new relationalStore.RdbPredicates('bookmarks');
    predicates.equalTo('bookUrl', bookUrl);
    predicates.orderByDesc('createTime');
    const resultSet = await this.store.query(predicates, []);
    while (resultSet.goToNextRow()) {
      bookmarks.push(this.resultSetToBookmark(resultSet));
    }
    return bookmarks;
  }

  async getBookmarkAt(bookUrl: string, chapterIndex: number, pageIndex: number): Promise<Bookmark | null> {
    if (!this.store || !bookUrl) return null;
    const predicates = new relationalStore.RdbPredicates('bookmarks');
    predicates.equalTo('bookUrl', bookUrl);
    predicates.equalTo('chapterIndex', chapterIndex);
    predicates.equalTo('pageIndex', pageIndex);
    const resultSet = await this.store.query(predicates, []);
    if (!resultSet.goToFirstRow()) return null;
    return this.resultSetToBookmark(resultSet);
  }

  async deleteBookmark(id: number): Promise<void> {
    if (!this.store || id <= 0) return;
    const predicates = new relationalStore.RdbPredicates('bookmarks');
    predicates.equalTo('id', id);
    await this.store.delete(predicates);
  }

  async deleteBookmarks(ids: number[]): Promise<void> {
    if (!this.store || ids.length === 0) return;
    for (const id of ids) {
      if (id <= 0) continue;
      const predicates = new relationalStore.RdbPredicates('bookmarks');
      predicates.equalTo('id', id);
      await this.store.delete(predicates);
    }
  }

  async deleteBookBookmarks(bookUrl: string): Promise<void> {
    if (!this.store || !bookUrl) return;
    const predicates = new relationalStore.RdbPredicates('bookmarks');
    predicates.equalTo('bookUrl', bookUrl);
    await this.store.delete(predicates);
  }

  private resultSetToBookmark(resultSet: relationalStore.ResultSet): Bookmark {
    const bookmark = new Bookmark();
    bookmark.id = resultSet.getLong(resultSet.getColumnIndex('id'));
    bookmark.bookUrl = resultSet.getString(resultSet.getColumnIndex('bookUrl'));
    bookmark.bookName = resultSet.getString(resultSet.getColumnIndex('bookName'));
    bookmark.bookAuthor = resultSet.getString(resultSet.getColumnIndex('bookAuthor'));
    bookmark.chapterIndex = resultSet.getLong(resultSet.getColumnIndex('chapterIndex'));
    bookmark.chapterName = resultSet.getString(resultSet.getColumnIndex('chapterName'));
    bookmark.pageIndex = resultSet.getLong(resultSet.getColumnIndex('pageIndex'));
    bookmark.startPos = resultSet.getLong(resultSet.getColumnIndex('startPos'));
    bookmark.endPos = resultSet.getLong(resultSet.getColumnIndex('endPos'));
    bookmark.content = resultSet.getString(resultSet.getColumnIndex('content'));
    bookmark.createTime = resultSet.getLong(resultSet.getColumnIndex('createTime'));
    return bookmark;
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

  async getCustomBookGroups(): Promise<BookGroup[]> {
    const groups: BookGroup[] = [];
    if (!this.store) return groups;
    const resultSet = await this.store.querySql(
      'SELECT groupId, groupName, groupOrder, show, enableRefresh FROM book_groups WHERE groupId > 0 ORDER BY groupOrder, groupId'
    );
    while (resultSet.goToNextRow()) {
      const group = new BookGroup();
      group.groupId = resultSet.getLong(resultSet.getColumnIndex('groupId'));
      group.groupName = resultSet.getString(resultSet.getColumnIndex('groupName'));
      group.order = resultSet.getLong(resultSet.getColumnIndex('groupOrder'));
      group.show = resultSet.getLong(resultSet.getColumnIndex('show')) === 1;
      group.enableRefresh = resultSet.getLong(resultSet.getColumnIndex('enableRefresh')) === 1;
      groups.push(group);
    }
    return groups;
  }

  async addBookGroup(groupName: string): Promise<BookGroup | null> {
    if (!this.store || !groupName.trim()) return null;
    const name = groupName.trim();
    const duplicate = await this.store.querySql('SELECT groupId FROM book_groups WHERE groupName = ?', [name]);
    if (duplicate.rowCount > 0) return null;
    const maxResult = await this.store.querySql('SELECT MAX(groupId) AS maxId FROM book_groups WHERE groupId > 0');
    maxResult.goToFirstRow();
    const maxId = maxResult.getLong(maxResult.getColumnIndex('maxId'));
    const group = new BookGroup();
    group.groupId = Math.max(0, maxId) + 1;
    group.groupName = name;
    group.order = group.groupId;
    await this.store.insert('book_groups', {
      groupId: group.groupId, groupName: group.groupName, groupOrder: group.order, show: 1, enableRefresh: 1
    });
    return group;
  }

  async renameBookGroup(groupId: number, groupName: string): Promise<boolean> {
    if (!this.store || groupId <= 0 || !groupName.trim()) return false;
    const name = groupName.trim();
    const duplicate = await this.store.querySql(
      'SELECT groupId FROM book_groups WHERE groupName = ? AND groupId != ?', [name, groupId]
    );
    if (duplicate.rowCount > 0) return false;
    const predicates = new relationalStore.RdbPredicates('book_groups');
    predicates.equalTo('groupId', groupId);
    await this.store.update({ groupName: name }, predicates);
    return true;
  }

  async updateBooksGroup(bookUrls: string[], groupId: number): Promise<void> {
    if (!this.store) return;
    for (const bookUrl of bookUrls) {
      const predicates = new relationalStore.RdbPredicates('books');
      predicates.equalTo('bookUrl', bookUrl);
      await this.store.update({ groupId: groupId }, predicates);
    }
  }

  async deleteBookGroup(groupId: number): Promise<void> {
    if (!this.store || groupId <= 0) return;
    const bookPredicates = new relationalStore.RdbPredicates('books');
    bookPredicates.equalTo('groupId', groupId);
    await this.store.update({ groupId: 0 }, bookPredicates);
    const groupPredicates = new relationalStore.RdbPredicates('book_groups');
    groupPredicates.equalTo('groupId', groupId);
    await this.store.delete(groupPredicates);
  }

  private resultSetToBook(resultSet: relationalStore.ResultSet): Book {
    const book = new Book();
    book.bookUrl = this.getStringColumn(resultSet, 'bookUrl');
    book.tocUrl = this.getStringColumn(resultSet, 'tocUrl');
    book.origin = this.getStringColumn(resultSet, 'origin', 'local');
    book.originName = this.getStringColumn(resultSet, 'originName');
    book.name = this.getStringColumn(resultSet, 'name');
    book.author = this.getStringColumn(resultSet, 'author');
    book.kind = this.getStringColumn(resultSet, 'kind');
    book.customTag = this.getStringColumn(resultSet, 'customTag');
    book.coverUrl = this.getStringColumn(resultSet, 'coverUrl');
    book.customCoverUrl = this.getStringColumn(resultSet, 'customCoverUrl');
    book.intro = this.getStringColumn(resultSet, 'intro');
    book.customIntro = this.getStringColumn(resultSet, 'customIntro');
    book.charset = this.getStringColumn(resultSet, 'charset');
    book.type = this.getLongColumn(resultSet, 'type');
    book.group = this.getLongColumn(resultSet, 'groupId');
    book.latestChapterTitle = this.getStringColumn(resultSet, 'latestChapterTitle');
    book.latestChapterTime = this.getLongColumn(resultSet, 'latestChapterTime');
    book.lastCheckTime = this.getLongColumn(resultSet, 'lastCheckTime');
    book.lastCheckCount = this.getLongColumn(resultSet, 'lastCheckCount');
    book.totalChapterNum = this.getLongColumn(resultSet, 'totalChapterNum');
    book.durChapterTitle = this.getStringColumn(resultSet, 'durChapterTitle');
    book.durChapterIndex = this.getLongColumn(resultSet, 'durChapterIndex');
    book.durChapterPos = this.getLongColumn(resultSet, 'durChapterPos');
    book.durChapterTime = this.getLongColumn(resultSet, 'durChapterTime');
    book.wordCount = this.getStringColumn(resultSet, 'wordCount');
    book.canUpdate = this.getLongColumn(resultSet, 'canUpdate', 1) === 1;
    book.order = this.getLongColumn(resultSet, 'bookOrder');
    book.originOrder = this.getLongColumn(resultSet, 'originOrder');
    book.variable = this.getStringColumn(resultSet, 'variable');
    const readConfigStr = this.getStringColumn(resultSet, 'readConfig');
    if (readConfigStr) {
      try {
        book.readConfig = JSON.parse(readConfigStr);
      } catch (e) {
        book.readConfig = null;
      }
    }
    book.syncTime = this.getLongColumn(resultSet, 'syncTime');
    return book;
  }

  private getStringColumn(resultSet: relationalStore.ResultSet, column: string, fallback: string = ''): string {
    const index = resultSet.getColumnIndex(column);
    if (index < 0) {
      return fallback;
    }
    return resultSet.getString(index) || fallback;
  }

  private getLongColumn(resultSet: relationalStore.ResultSet, column: string, fallback: number = 0): number {
    const index = resultSet.getColumnIndex(column);
    if (index < 0) {
      return fallback;
    }
    return resultSet.getLong(index);
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
      loginHeader: source.loginHeader,
      bookUrlPattern: source.bookUrlPattern,
      searchUrl: source.searchUrl,
      exploreUrl: source.exploreUrl,
      jsLib: source.jsLib,
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
      isLocked: source.isLocked ? 1 : 0,
      weight: source.weight,
      concurrentRate: source.concurrentRate
    };

    const predicates = new relationalStore.RdbPredicates('book_sources');
    predicates.equalTo('bookSourceUrl', source.bookSourceUrl);
    const resultSet = await this.store.query(predicates, []);
    if (resultSet.rowCount > 0) {
      resultSet.goToFirstRow();
      if (this.getLongColumn(resultSet, 'isLocked') === 1) {
        return;
      }
      await this.store.update(bucket, predicates);
    } else {
      await this.store.insert('book_sources', bucket);
    }
  }

  async updateBookSource(source: BookSource): Promise<void> {
    if (!this.store) return;
    if (await this.isBookSourceLocked(source.bookSourceUrl)) return;
    const bucket: relationalStore.ValuesBucket = {
      bookSourceName: source.bookSourceName,
      bookSourceGroup: source.bookSourceGroup,
      bookSourceComment: source.bookSourceComment,
      loginUrl: source.loginUrl,
      loginUi: source.loginUi,
      loginCheckJs: source.loginCheckJs,
      loginHeader: source.loginHeader,
      bookUrlPattern: source.bookUrlPattern,
      searchUrl: source.searchUrl,
      exploreUrl: source.exploreUrl,
      jsLib: source.jsLib,
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
      isLocked: source.isLocked ? 1 : 0,
      weight: source.weight,
      concurrentRate: source.concurrentRate
    };

    const predicates = new relationalStore.RdbPredicates('book_sources');
    predicates.equalTo('bookSourceUrl', source.bookSourceUrl);
    await this.store.update(bucket, predicates);
  }

  async deleteBookSource(bookSourceUrl: string): Promise<void> {
    if (!this.store) return;
    if (await this.isBookSourceLocked(bookSourceUrl)) return;
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

  /** 列表只读取轻量字段；规则详情在实际使用时再按主键加载。 */
  async getBookSourceSummaries(): Promise<BookSource[]> {
    if (!this.store) return [];
    const predicates = new relationalStore.RdbPredicates('book_sources');
    predicates.orderByAsc('customOrder');
    const columns = [
      'bookSourceUrl', 'bookSourceName', 'bookSourceGroup', 'loginUrl', 'loginUi',
      'loginCheckJs', 'loginHeader', 'customOrder', 'enabled', 'enabledExplore', 'isLocked'
    ];
    const resultSet = await this.store.query(predicates, columns);
    const sources: BookSource[] = [];
    while (resultSet.goToNextRow()) {
      const source = new BookSource();
      source.bookSourceUrl = resultSet.getString(resultSet.getColumnIndex('bookSourceUrl'));
      source.bookSourceName = resultSet.getString(resultSet.getColumnIndex('bookSourceName'));
      source.bookSourceGroup = resultSet.getString(resultSet.getColumnIndex('bookSourceGroup'));
      source.loginUrl = resultSet.getString(resultSet.getColumnIndex('loginUrl'));
      source.loginUi = resultSet.getString(resultSet.getColumnIndex('loginUi'));
      source.loginCheckJs = resultSet.getString(resultSet.getColumnIndex('loginCheckJs'));
      source.loginHeader = resultSet.getString(resultSet.getColumnIndex('loginHeader'));
      source.customOrder = resultSet.getLong(resultSet.getColumnIndex('customOrder'));
      source.enabled = resultSet.getLong(resultSet.getColumnIndex('enabled')) === 1;
      source.enabledExplore = resultSet.getLong(resultSet.getColumnIndex('enabledExplore')) === 1;
      source.isLocked = this.getLongColumn(resultSet, 'isLocked') === 1;
      sources.push(source);
    }
    return sources;
  }

  async updateBookSourceListFields(bookSourceUrl: string, fields: Record<string, string | number>): Promise<void> {
    if (!this.store) return;
    if (await this.isBookSourceLocked(bookSourceUrl)) return;
    const bucket: relationalStore.ValuesBucket = {};
    if (fields['bookSourceGroup'] !== undefined) bucket['bookSourceGroup'] = fields['bookSourceGroup'];
    if (fields['enabled'] !== undefined) bucket['enabled'] = fields['enabled'];
    if (fields['enabledExplore'] !== undefined) bucket['enabledExplore'] = fields['enabledExplore'];
    bucket['lastUpdateTime'] = Date.now();
    const predicates = new relationalStore.RdbPredicates('book_sources');
    predicates.equalTo('bookSourceUrl', bookSourceUrl);
    await this.store.update(bucket, predicates);
  }

  async setBookSourceLocked(bookSourceUrl: string, locked: boolean): Promise<void> {
    if (!this.store) return;
    const predicates = new relationalStore.RdbPredicates('book_sources');
    predicates.equalTo('bookSourceUrl', bookSourceUrl);
    await this.store.update({ isLocked: locked ? 1 : 0 }, predicates);
  }

  private async isBookSourceLocked(bookSourceUrl: string): Promise<boolean> {
    if (!this.store || !bookSourceUrl) return false;
    const predicates = new relationalStore.RdbPredicates('book_sources');
    predicates.equalTo('bookSourceUrl', bookSourceUrl);
    const resultSet = await this.store.query(predicates, ['isLocked']);
    if (!resultSet.goToFirstRow()) return false;
    return this.getLongColumn(resultSet, 'isLocked') === 1;
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
    const loginHeaderIndex = resultSet.getColumnIndex('loginHeader');
    source.loginHeader = loginHeaderIndex >= 0 ? resultSet.getString(loginHeaderIndex) : '';
    source.bookUrlPattern = resultSet.getString(resultSet.getColumnIndex('bookUrlPattern'));
    const searchUrlIndex = resultSet.getColumnIndex('searchUrl');
    source.searchUrl = searchUrlIndex >= 0 ? resultSet.getString(searchUrlIndex) : '';
    const exploreUrlIndex = resultSet.getColumnIndex('exploreUrl');
    source.exploreUrl = exploreUrlIndex >= 0 ? resultSet.getString(exploreUrlIndex) : '';
    const jsLibIndex = resultSet.getColumnIndex('jsLib');
    source.jsLib = jsLibIndex >= 0 ? resultSet.getString(jsLibIndex) : '';
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
    source.isLocked = this.getLongColumn(resultSet, 'isLocked') === 1;
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
    if (!this.store || chapters.length === 0) return;
    const buckets: relationalStore.ValuesBucket[] = [];
    for (const chapter of chapters) {
      buckets.push({
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
      });
    }
    await this.store.batchInsert('book_chapters', buckets);
  }

  async insertBookChaptersWithContents(bookUrl: string, chapters: BookChapter[], contents: string[]): Promise<void> {
    if (!this.store || !bookUrl || chapters.length === 0 || chapters.length !== contents.length) return;
    const cacheDate = Date.now();
    const chapterBuckets: relationalStore.ValuesBucket[] = [];
    const contentBuckets: relationalStore.ValuesBucket[] = [];
    for (let i = 0; i < chapters.length; i++) {
      const chapter = chapters[i];
      chapterBuckets.push({
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
      });
      contentBuckets.push({
        bookUrl: bookUrl,
        chapterIndex: chapter.index,
        chapterUrl: chapter.url,
        chapterName: chapter.title,
        content: contents[i] || ' ',
        cacheDate: cacheDate
      });
      chapter.cacheDate = cacheDate;
    }
    await this.store.batchInsert('book_chapters', chapterBuckets);
    await this.store.batchInsert('book_contents', contentBuckets);
  }

  async deleteBookChapters(bookUrl: string): Promise<void> {
    if (!this.store) return;
    const predicates = new relationalStore.RdbPredicates('book_chapters');
    predicates.equalTo('bookUrl', bookUrl);
    await this.store.delete(predicates);
    await this.deleteReaderPaginationCache(bookUrl);
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
    const cacheDates = await this.getBookChapterCacheDateMap(bookUrl);
    for (const chapter of chapters) {
      chapter.cacheDate = cacheDates.get(chapter.index) || 0;
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

  async getCachedChapterContent(bookUrl: string, chapterIndex: number): Promise<string> {
    if (!this.store) return '';
    const predicates = new relationalStore.RdbPredicates('book_contents');
    predicates.equalTo('bookUrl', bookUrl);
    predicates.equalTo('chapterIndex', chapterIndex);
    const resultSet = await this.store.query(predicates, ['content']);
    if (resultSet.rowCount === 0) return '';
    resultSet.goToFirstRow();
    return resultSet.getString(resultSet.getColumnIndex('content')) || '';
  }

  async saveCachedChapterContent(bookUrl: string, chapter: BookChapter, content: string): Promise<void> {
    if (!this.store || !bookUrl || !content) return;
    const cacheDate = Date.now();
    const bucket: relationalStore.ValuesBucket = {
      bookUrl: bookUrl,
      chapterIndex: chapter.index,
      chapterUrl: chapter.url,
      chapterName: chapter.title,
      content: content,
      cacheDate: cacheDate
    };
    const predicates = new relationalStore.RdbPredicates('book_contents');
    predicates.equalTo('bookUrl', bookUrl);
    predicates.equalTo('chapterIndex', chapter.index);
    const resultSet = await this.store.query(predicates, []);
    if (resultSet.rowCount > 0) {
      await this.store.update(bucket, predicates);
    } else {
      await this.store.insert('book_contents', bucket);
    }
    chapter.cacheDate = cacheDate;
  }

  async deleteBookCachedContent(bookUrl: string): Promise<void> {
    if (!this.store) return;
    const predicates = new relationalStore.RdbPredicates('book_contents');
    predicates.equalTo('bookUrl', bookUrl);
    await this.store.delete(predicates);
    await this.deleteReaderPaginationCache(bookUrl);
  }

  async deleteCachedChapterContent(bookUrl: string, chapterIndex: number): Promise<void> {
    if (!this.store) return;
    const predicates = new relationalStore.RdbPredicates('book_contents');
    predicates.equalTo('bookUrl', bookUrl);
    predicates.equalTo('chapterIndex', chapterIndex);
    await this.store.delete(predicates);
    await this.deleteReaderPaginationCache(bookUrl, chapterIndex);
  }

  async getReaderPaginationCache(bookUrl: string, chapterIndex: number,
    layoutKey: string): Promise<ReaderPaginationCacheRecord | null> {
    if (!this.store || !bookUrl || !layoutKey) return null;
    const predicates = new relationalStore.RdbPredicates('reader_pagination_cache');
    predicates.equalTo('bookUrl', bookUrl);
    predicates.equalTo('chapterIndex', chapterIndex);
    predicates.equalTo('layoutKey', layoutKey);
    const resultSet = await this.store.query(predicates, ['starts', 'ends']);
    if (!resultSet.goToFirstRow()) return null;
    try {
      const starts = JSON.parse(resultSet.getString(resultSet.getColumnIndex('starts'))) as number[];
      const ends = JSON.parse(resultSet.getString(resultSet.getColumnIndex('ends'))) as number[];
      if (!Array.isArray(starts) || !Array.isArray(ends) || starts.length === 0 || starts.length !== ends.length) {
        return null;
      }
      const record = new ReaderPaginationCacheRecord();
      record.starts = starts;
      record.ends = ends;
      return record;
    } catch (_) {
      return null;
    }
  }

  async saveReaderPaginationCache(bookUrl: string, chapterIndex: number, layoutKey: string,
    starts: number[], ends: number[]): Promise<void> {
    if (!this.store || !bookUrl || !layoutKey || starts.length === 0 || starts.length !== ends.length) return;
    await this.deleteReaderPaginationCache(bookUrl, chapterIndex);
    const bucket: relationalStore.ValuesBucket = {
      bookUrl: bookUrl,
      chapterIndex: chapterIndex,
      layoutKey: layoutKey,
      starts: JSON.stringify(starts),
      ends: JSON.stringify(ends),
      updateTime: Date.now()
    };
    await this.store.insert('reader_pagination_cache', bucket);
  }

  async deleteReaderPaginationCache(bookUrl: string, chapterIndex: number = -1): Promise<void> {
    if (!this.store || !bookUrl) return;
    const predicates = new relationalStore.RdbPredicates('reader_pagination_cache');
    predicates.equalTo('bookUrl', bookUrl);
    if (chapterIndex >= 0) predicates.equalTo('chapterIndex', chapterIndex);
    await this.store.delete(predicates);
  }

  async getBookChapterCacheDateMap(bookUrl: string): Promise<Map<number, number>> {
    const cacheDates: Map<number, number> = new Map();
    if (!this.store) return cacheDates;
    const predicates = new relationalStore.RdbPredicates('book_contents');
    predicates.equalTo('bookUrl', bookUrl);
    const resultSet = await this.store.query(predicates, ['chapterIndex', 'cacheDate']);
    while (resultSet.goToNextRow()) {
      cacheDates.set(
        resultSet.getLong(resultSet.getColumnIndex('chapterIndex')),
        resultSet.getLong(resultSet.getColumnIndex('cacheDate'))
      );
    }
    return cacheDates;
  }

  async getBookCachedChapterIndices(bookUrl: string): Promise<number[]> {
    const indices: number[] = [];
    const cacheDates = await this.getBookChapterCacheDateMap(bookUrl);
    cacheDates.forEach((_cacheDate: number, index: number) => {
      indices.push(index);
    });
    return indices;
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

  async deleteSearchKeyword(keyword: string): Promise<void> {
    if (!this.store) return;
    const predicates = new relationalStore.RdbPredicates('search_keywords');
    predicates.equalTo('keyword', keyword);
    await this.store.delete(predicates);
  }
}

export const appDb = AppDatabase.getInstance();
