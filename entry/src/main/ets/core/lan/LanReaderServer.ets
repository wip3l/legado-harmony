import socket from '@ohos.net.socket';
import connection from '@ohos.net.connection';
import { common, wantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { Context } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { appDb } from '../../model/data/AppDatabase';
import { Book, BookChapter, BookSource, SearchBook } from '../../model/data/Book';
import { ReadBookEngine } from '../book/ReadBookEngine';
import { HttpClient } from '../http/HttpClient';
import { BookTypeSupport } from '../book/BookTypeSupport';
import { SearchCoordinator } from '../book/SearchCoordinator';
import { ExploreCoordinator, ExploreEntry } from '../book/ExploreCoordinator';
import { SearchBookShelfHelper } from '../../utils/SearchBookShelfHelper';

interface LanHttpResponse {
  status: number;
  contentType: string;
  body: string | ArrayBuffer;
}

interface LanHttpRequest {
  method: string;
  path: string;
  query: Map<string, string>;
  headers: Map<string, string>;
  body: string;
}

interface LanMediaInfo {
  type: string;
  label: string;
  supported: boolean;
}

class LanBookDto {
  id: string = '';
  name: string = '';
  author: string = '';
  intro: string = '';
  cover: string = '';
  chapterIndex: number = 0;
  chapterPos: number = 0;
  chapterTime: number = 0;
  chapterTitle: string = '';
  totalChapterNum: number = 0;
  group: number = 0;
  groupName: string = '';
  groupOrder: number = 0;
  mediaType: string = 'novel';
  mediaLabel: string = '小说';
  browserSupported: boolean = true;
}

class LanChapterDto {
  index: number = 0;
  title: string = '';
  cached: boolean = false;
}

class LanContentDto {
  index: number = 0;
  title: string = '';
  content: string = '';
  total: number = 0;
  chapterTime: number = 0;
  mediaType: string = 'novel';
  images: string[] = [];
}

class LanProgressResult {
  accepted: boolean = false;
  reason: string = '';
  chapterTime: number = 0;
}

class LanHealthDto {
  ok: boolean = true;
  ip: string = '';
  port: number = 0;
  serverTime: number = 0;
}

class LanAuthDto {
  ok: boolean = false;
  token: string = '';
  message: string = '';
}

class LanSourceDto {
  name: string = '';
  url: string = '';
  group: string = '';
  search: boolean = false;
  explore: boolean = false;
  platforms: string[] = [];
}

class LanResultDto {
  id: string = '';
  name: string = '';
  author: string = '';
  kind: string = '';
  status: string = '';
  intro: string = '';
  cover: string = '';
  coverUrl: string = '';
  bookUrl: string = '';
  tocUrl: string = '';
  origin: string = '';
  originName: string = '';
  type: number = 0;
  mediaType: string = 'novel';
  mediaLabel: string = '\u5c0f\u8bf4';
  browserSupported: boolean = true;
  latestChapterTitle: string = '';
  updateTime: string = '';
  wordCount: string = '';
}

class LanExploreEntryDto {
  title: string = '';
  url: string = '';
  sourceUrl: string = '';
  sourceName: string = '';
  groupTitle: string = '';
}

class LanAddResultDto {
  ok: boolean = false;
  message: string = '';
  id: string = '';
}

/** Lightweight HTTP reader for devices on the same LAN. A password is optional;
 * the internal bearer token is kept only as an in-memory session credential. */
export class LanReaderServer {
  private static instance: LanReaderServer | null = null;
  private tcpServer: socket.TCPSocketServer | null = null;
  private context: Context | null = null;
  private enabled: boolean = false;
  private ipAddress: string = '';
  private port: number = 18080;
  private token: string = '';
  private password: string = '';
  private refreshTimer: number = -1;
  private backgroundRunning: boolean = false;
  private readonly connections: Map<number, socket.TCPSocketConnection> = new Map();
  private readonly buffers: Map<number, string> = new Map();
  private readonly bookIds: Map<string, string> = new Map();
  private readonly idBooks: Map<string, string> = new Map();
  private readonly httpClient: HttpClient = new HttpClient(12000);

  private constructor() {
  }

  static getInstance(): LanReaderServer {
    if (!LanReaderServer.instance) {
      LanReaderServer.instance = new LanReaderServer();
    }
    return LanReaderServer.instance;
  }

  isRunning(): boolean {
    return this.tcpServer !== null && this.ipAddress.length > 0;
  }

  async start(context: Context): Promise<void> {
    this.context = context;
    this.enabled = true;
    this.password = AppStorage.get<string>('lanReaderPassword') || '';
    if (!this.token) {
      this.token = this.createToken();
      AppStorage.setOrCreate('lanReaderToken', this.token);
    }
    await appDb.initWithContext(context);
    await this.rebind(true);
    await this.startBackgroundTask(context);
    if (this.refreshTimer < 0) {
      this.refreshTimer = setInterval(() => {
        this.refreshNetworkBinding().catch(() => undefined);
      }, 5000);
    }
  }

  async stop(): Promise<void> {
    this.enabled = false;
    if (this.refreshTimer >= 0) {
      clearInterval(this.refreshTimer);
      this.refreshTimer = -1;
    }
    await this.stopBackgroundTask();
    await this.closeServer();
    this.token = '';
    this.ipAddress = '';
    AppStorage.setOrCreate('lanReaderAddress', '');
    AppStorage.setOrCreate('lanReaderStatus', '已关闭');
    AppStorage.setOrCreate('lanReaderToken', '');
  }

  setPassword(password: string): void {
    const next = password.trim().substring(0, 64);
    this.password = next;
    AppStorage.setOrCreate('lanReaderPassword', next);
    // Invalidate any browser sessions when the access password changes.
    if (this.enabled) {
      this.token = this.createToken();
      AppStorage.setOrCreate('lanReaderToken', this.token);
    }
  }

  hasPassword(): boolean {
    return this.password.length > 0;
  }

  private async refreshNetworkBinding(): Promise<void> {
    if (!this.enabled) return;
    const nextIp = await this.findLanIp();
    if (nextIp !== this.ipAddress) {
      await this.rebind(false);
    }
  }

  private async rebind(force: boolean): Promise<void> {
    const nextIp = await this.findLanIp();
    if (!force && nextIp === this.ipAddress && this.tcpServer) return;
    await this.closeServer();
    this.ipAddress = nextIp;
    if (!nextIp) {
      AppStorage.setOrCreate('lanReaderAddress', '');
      AppStorage.setOrCreate('lanReaderStatus', '等待局域网地址');
      return;
    }
    const candidates: number[] = [18080, 18081, 18082, 18083, 18084];
    let lastError: Error | null = null;
    for (const candidate of candidates) {
      const server = socket.constructTCPSocketServerInstance();
      try {
        await server.listen({ address: nextIp, family: 1, port: candidate });
        // Network Kit requires the connect listener to be registered after listen succeeds.
        // Registering it before listen can leave the port in LISTEN state while accepted
        // connections never reach the ArkTS callback.
        server.on('connect', (client: socket.TCPSocketConnection) => this.accept(client));
        server.on('error', (error: Error) => {
          console.warn('[LanReader] socket error', error);
        });
        this.tcpServer = server;
        this.port = candidate;
        AppStorage.setOrCreate('lanReaderAddress', `http://${nextIp}:${candidate}`);
        AppStorage.setOrCreate('lanReaderStatus', '运行中');
        return;
      } catch (error) {
        lastError = error as Error;
        try {
          await server.close();
        } catch (_) {
        }
      }
    }
    this.tcpServer = null;
    AppStorage.setOrCreate('lanReaderAddress', '');
    AppStorage.setOrCreate('lanReaderStatus', lastError ? '端口绑定失败' : '启动失败');
  }

  private async closeServer(): Promise<void> {
    const server = this.tcpServer;
    this.tcpServer = null;
    this.connections.forEach((client: socket.TCPSocketConnection) => {
      client.close().catch(() => undefined);
    });
    this.connections.clear();
    this.buffers.clear();
    if (server) {
      try {
        await server.close();
      } catch (_) {
      }
    }
  }

  private async startBackgroundTask(context: Context): Promise<void> {
    if (this.backgroundRunning) return;
    try {
      const abilityContext = context as common.UIAbilityContext;
      const agent = await wantAgent.getWantAgent({
        wants: [{
          bundleName: abilityContext.abilityInfo.bundleName,
          abilityName: 'EntryAbility',
          parameters: { lanReader: true }
        }],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: 18080,
        actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      });
      await backgroundTaskManager.startBackgroundRunning(abilityContext, ['dataTransfer'], agent);
      this.backgroundRunning = true;
      AppStorage.setOrCreate('lanReaderBackgroundStatus', '后台任务运行中');
    } catch (error) {
      // The server remains available in the foreground if the device rejects a continuous task.
      this.backgroundRunning = false;
      AppStorage.setOrCreate('lanReaderBackgroundStatus', '前台运行（后台任务未获准）');
      console.warn('[LanReader] background task unavailable', error);
    }
  }

  private async stopBackgroundTask(): Promise<void> {
    if (!this.backgroundRunning || !this.context) return;
    this.backgroundRunning = false;
    try {
      await backgroundTaskManager.stopBackgroundRunning(this.context as common.UIAbilityContext);
    } catch (error) {
      console.warn('[LanReader] stop background task failed', error);
    }
  }

  private accept(client: socket.TCPSocketConnection): void {
    if (this.connections.size >= 16) {
      client.close().catch(() => undefined);
      return;
    }
    const id = client.clientId;
    this.connections.set(id, client);
    this.buffers.set(id, '');
    client.on('message', (info: socket.SocketMessageInfo) => {
      const previous = this.buffers.get(id) || '';
      const text = util.TextDecoder.create('utf-8').decodeWithStream(
        new Uint8Array(info.message), { stream: false });
      const next = previous + text;
      if (next.length > 1024 * 1024) {
        client.close().catch(() => undefined);
        return;
      }
      this.buffers.set(id, next);
      this.tryHandleRequest(client, id).catch(async (error: Object) => {
        console.warn('[LanReader] request handling failed', error);
        try {
          await this.sendResponse(client, {
            status: 500,
            contentType: 'text/plain; charset=utf-8',
            body: 'Internal Server Error'
          });
        } catch (_) {
          client.close().catch(() => undefined);
        }
      });
    });
    client.on('close', () => this.cleanupConnection(id));
    client.on('error', () => this.cleanupConnection(id));
  }

  private cleanupConnection(id: number): void {
    this.connections.delete(id);
    this.buffers.delete(id);
  }

  private async tryHandleRequest(client: socket.TCPSocketConnection, id: number): Promise<void> {
    const raw = this.buffers.get(id) || '';
    const separator = raw.indexOf('\r\n\r\n');
    if (separator < 0) return;
    const head = raw.substring(0, separator);
    const firstLine = head.split('\r\n')[0] || '';
    const parts = firstLine.split(' ');
    if (parts.length < 2) {
      await this.sendResponse(client, { status: 400, contentType: 'text/plain; charset=utf-8', body: 'Bad Request' });
      return;
    }
    const headers = new Map<string, string>();
    for (const line of head.split('\r\n').slice(1)) {
      const colon = line.indexOf(':');
      if (colon > 0) headers.set(line.substring(0, colon).trim().toLowerCase(), line.substring(colon + 1).trim());
    }
    const parsedLength = Number(headers.get('content-length') || 0);
    const contentLength = Number.isFinite(parsedLength) ? Math.min(Math.max(parsedLength, 0), 256 * 1024) : 0;
    const bodyStart = separator + 4;
    const bodyText = raw.substring(bodyStart);
    // Network Kit's TextEncoder API specifies undefined for encodeInto('')
    // (the normal case for a GET body). Keep parsing safe for empty bodies and
    // still honor Content-Length when a byte array is returned.
    const encodedBody = new util.TextEncoder().encodeInto(bodyText);
    const bodyByteLength = encodedBody ? encodedBody.byteLength : bodyText.length;
    if (bodyByteLength < contentLength) return;
    const request = this.parseRequest(parts[0], parts[1], headers, bodyText);
    this.buffers.delete(id);
    const response = await this.route(request);
    await this.sendResponse(client, response);
  }

  private parseRequest(method: string, target: string, headers: Map<string, string>, body: string): LanHttpRequest {
    const query = new Map<string, string>();
    const question = target.indexOf('?');
    const path = question >= 0 ? target.substring(0, question) : target;
    const queryText = question >= 0 ? target.substring(question + 1) : '';
    for (const pair of queryText.split('&')) {
      if (!pair) continue;
      const equals = pair.indexOf('=');
      const key = equals >= 0 ? pair.substring(0, equals) : pair;
      const value = equals >= 0 ? pair.substring(equals + 1) : '';
      try {
        query.set(decodeURIComponent(key), decodeURIComponent(value));
      } catch (_) {
      }
    }
    return { method: method.toUpperCase(), path, query, headers, body };
  }

  private async route(request: LanHttpRequest): Promise<LanHttpResponse> {
    const supplied = request.query.get('token') || this.authorizationToken(request.headers.get('authorization') || '');
    if (request.method === 'POST' && request.path === '/api/auth') {
      try {
        const payload = JSON.parse(request.body || '{}') as Record<string, Object>;
        const candidate = String(payload['password'] || '');
        if (this.password.length > 0 && candidate === this.password) {
          const result = new LanAuthDto();
          result.ok = true;
          result.token = this.token;
          return this.jsonResponse(result);
        }
      } catch (_) {
      }
      return { status: 401, contentType: 'application/json; charset=utf-8', body: JSON.stringify({ ok: false, message: '密码错误' }) };
    }
    // The document shell is intentionally public; it contains no book data and
    // presents the password form when one has been configured. APIs remain protected.
    if (request.method === 'GET' && request.path === '/') return this.htmlResponse();
    // With no password configured the LAN reader is intentionally open, so
    // direct ip:port access does not depend on a generated token or a stale
    // browser session. Password mode keeps all APIs session-protected.
    if (this.password.length > 0 && (!this.token || supplied !== this.token)) {
      return { status: 401, contentType: 'text/plain; charset=utf-8', body: 'Unauthorized' };
    }
    if (request.method === 'GET' && request.path === '/api/health') {
      const health = new LanHealthDto();
      health.ip = this.ipAddress;
      health.port = this.port;
      health.serverTime = Date.now();
      return this.jsonResponse(health);
    }
    if (request.method === 'GET' && request.path === '/api/search/sources') {
      return await this.searchSourcesResponse();
    }
    if (request.method === 'GET' && request.path === '/api/search') {
      return await this.searchResponse(request.query.get('q') || '', request.query.get('source') || '');
    }
    if (request.method === 'POST' && request.path === '/api/search/add') {
      return await this.addSearchBookResponse(request.body);
    }
    if (request.method === 'GET' && request.path === '/api/discover/sources') {
      return await this.discoverSourcesResponse();
    }
    if (request.method === 'GET' && request.path === '/api/discover/entries') {
      return await this.discoverEntriesResponse(request.query.get('source') || '', request.query.get('platform') || '');
    }
    if (request.method === 'GET' && request.path === '/api/discover') {
      return await this.discoverResponse(request.query.get('source') || '', request.query.get('entry') || '',
        Number(request.query.get('page') || 1));
    }
    if (request.method === 'GET' && request.path === '/api/books') return this.booksResponse();
    const segments = request.path.split('/').filter((part: string) => part.length > 0);
    if (segments.length >= 3 && segments[0] === 'api' && segments[1] === 'books') {
      const id = segments[2];
      if (segments.length === 4 && segments[3] === 'chapters' && request.method === 'GET') {
        return await this.chaptersResponse(id);
      }
      if (segments.length === 5 && segments[3] === 'chapters' && request.method === 'GET') {
        return await this.contentResponse(id, Number(segments[4]));
      }
      if (segments.length === 6 && segments[3] === 'chapters' && segments[5] === 'images' && request.method === 'GET') {
        return await this.imagesResponse(id, Number(segments[4]));
      }
      if (segments.length === 4 && segments[3] === 'progress' && request.method === 'POST') {
        return await this.progressResponse(id, request.body);
      }
    }
    if (segments.length === 3 && segments[0] === 'api' && segments[1] === 'covers' && request.method === 'GET') {
      return await this.coverResponse(segments[2]);
    }
    if (segments.length === 3 && segments[0] === 'api' && segments[1] === 'images' && segments[2] === 'proxy' && request.method === 'GET') {
      return await this.imageProxyResponse(request.query.get('url') || '');
    }
    return { status: 404, contentType: 'text/plain; charset=utf-8', body: 'Not Found' };
  }

  private authorizationToken(value: string): string {
    const prefix = 'bearer ';
    return value.toLowerCase().startsWith(prefix) ? value.substring(prefix.length).trim() : '';
  }

  private async booksResponse(): Promise<LanHttpResponse> {
    const books = await appDb.getAllBooks();
    const groups = await appDb.getCustomBookGroups();
    const groupNames = new Map<number, string>();
    const groupOrders = new Map<number, number>();
    for (const group of groups) {
      groupNames.set(group.groupId, group.groupName);
      groupOrders.set(group.groupId, group.order);
    }
    const result: LanBookDto[] = [];
    for (const book of books) {
      const id = this.bookId(book.bookUrl);
      const dto = new LanBookDto();
      dto.id = id;
      dto.name = book.name;
      dto.author = book.author;
      dto.intro = book.getDisplayIntro();
      dto.cover = book.getDisplayCover() ? `/api/covers/${id}?token=${encodeURIComponent(this.token)}` : '';
      dto.chapterIndex = book.durChapterIndex;
      dto.chapterPos = book.durChapterPos;
      dto.chapterTime = book.durChapterTime;
      dto.chapterTitle = book.durChapterTitle;
      dto.totalChapterNum = book.totalChapterNum;
      dto.group = book.group;
      dto.groupName = groupNames.get(book.group) || (book.group > 0 ? `分组 ${book.group}` : '未分组');
      dto.groupOrder = groupOrders.get(book.group) || (book.group > 0 ? book.group : 0);
      const media = this.mediaInfo(book);
      dto.mediaType = media.type;
      dto.mediaLabel = media.label;
      dto.browserSupported = media.supported;
      result.push(dto);
    }
    return this.jsonResponse(result);
  }

  private sourceResultDto(book: SearchBook): LanResultDto {
    const dto = new LanResultDto();
    dto.id = this.bookId(book.bookUrl || `${book.origin}\n${book.name}\n${book.author}`);
    dto.name = book.name || '';
    dto.author = book.author || '';
    dto.kind = book.kind || '';
    dto.status = book.status || '';
    dto.intro = book.intro || '';
    dto.bookUrl = book.bookUrl || '';
    dto.tocUrl = book.tocUrl || '';
    dto.origin = book.origin || '';
    dto.originName = book.originName || '';
    dto.type = Number(book.type || 0);
    dto.cover = book.coverUrl ? `/api/images/proxy?url=${encodeURIComponent(book.coverUrl)}&token=${encodeURIComponent(this.token)}` : '';
    dto.coverUrl = book.coverUrl || '';
    dto.latestChapterTitle = book.latestChapterTitle || '';
    dto.updateTime = book.updateTime || '';
    dto.wordCount = book.wordCount || '';
    if (BookTypeSupport.isAudio(book)) {
      dto.mediaType = 'audio'; dto.mediaLabel = '\u6709\u58f0\u4e66'; dto.browserSupported = false;
    } else if (BookTypeSupport.isImage(book)) {
      dto.mediaType = 'comic'; dto.mediaLabel = '\u6f2b\u753b'; dto.browserSupported = false;
    } else {
      dto.mediaType = 'novel'; dto.mediaLabel = '\u5c0f\u8bf4';
    }
    return dto;
  }

  private async searchSourcesResponse(): Promise<LanHttpResponse> {
    const sources = await appDb.getEnabledBookSourcesForSearch();
    const result: LanSourceDto[] = [];
    for (const source of sources) {
      if (!source.bookSourceUrl || !source.bookSourceName || !source.searchUrl || !source.searchRule?.bookList) continue;
      const dto = new LanSourceDto();
      dto.name = source.bookSourceName; dto.url = source.bookSourceUrl;
      dto.group = (source.bookSourceGroup || '').trim(); dto.search = true;
      result.push(dto);
    }
    return this.jsonResponse(result);
  }

  private async searchResponse(keyword: string, sourceUrl: string): Promise<LanHttpResponse> {
    const query = keyword.trim();
    if (!query || query.length > 80) return { status: 400, contentType: 'text/plain; charset=utf-8', body: 'Invalid search keyword' };
    const sources = await appDb.getEnabledBookSourcesForSearch();
    const target = sourceUrl ? sources.filter((source: BookSource): boolean => source.bookSourceUrl === sourceUrl) : sources;
    if (target.length === 0) return this.jsonResponse([]);
    const coordinator = new SearchCoordinator(4);
    const books = await coordinator.search(query, () => undefined, {
      targetSources: target, maxResultsPerSource: 20, maxTotalResults: 120, stopAfterResults: 120
    });
    return this.jsonResponse(books.map((book: SearchBook): LanResultDto => this.sourceResultDto(book)));
  }

  private async addSearchBookResponse(body: string): Promise<LanHttpResponse> {
    try {
      const raw = JSON.parse(body) as Record<string, Object>;
      const book = new SearchBook();
      book.bookUrl = String(raw['bookUrl'] || ''); book.tocUrl = String(raw['tocUrl'] || '');
      book.origin = String(raw['origin'] || ''); book.originName = String(raw['originName'] || '');
      book.name = String(raw['name'] || ''); book.author = String(raw['author'] || '');
      book.kind = String(raw['kind'] || ''); book.status = String(raw['status'] || '');
      book.intro = String(raw['intro'] || ''); book.coverUrl = String(raw['coverUrl'] || '');
      book.latestChapterTitle = String(raw['latestChapterTitle'] || ''); book.updateTime = String(raw['updateTime'] || '');
      book.wordCount = String(raw['wordCount'] || ''); book.variable = String(raw['variable'] || '');
      book.type = Number(raw['type'] || 0);
      if (!book.bookUrl || !this.context) return { status: 400, contentType: 'text/plain; charset=utf-8', body: 'Invalid book' };
      const change = await SearchBookShelfHelper.addToShelf(this.context, book);
      const result = new LanAddResultDto(); result.ok = !!change.shelfKey; result.id = this.bookId(book.bookUrl);
      result.message = result.ok ? 'added' : 'unable to add';
      return this.jsonResponse(result);
    } catch (_) {
      return { status: 400, contentType: 'text/plain; charset=utf-8', body: 'Invalid book' };
    }
  }

  private async discoverSourcesResponse(): Promise<LanHttpResponse> {
    const coordinator = new ExploreCoordinator();
    const sources = await coordinator.getExploreSources();
    const result: LanSourceDto[] = [];
    for (const source of sources) {
      const dto = new LanSourceDto(); dto.name = source.sourceName; dto.url = source.sourceUrl;
      dto.group = source.sourceGroup; dto.explore = true; dto.platforms = source.platforms || [];
      result.push(dto);
    }
    return this.jsonResponse(result);
  }

  private async discoverEntriesResponse(sourceUrl: string, platform: string): Promise<LanHttpResponse> {
    const coordinator = new ExploreCoordinator();
    const entries = await coordinator.getEntries(platform, sourceUrl);
    return this.jsonResponse(entries.map((entry: ExploreEntry): LanExploreEntryDto => {
      const dto = new LanExploreEntryDto(); dto.title = entry.title; dto.url = entry.url;
      dto.sourceUrl = entry.sourceUrl; dto.sourceName = entry.sourceName; dto.groupTitle = entry.groupTitle || '';
      return dto;
    }));
  }

  private async discoverResponse(sourceUrl: string, entryUrl: string, page: number): Promise<LanHttpResponse> {
    if (!sourceUrl || !entryUrl || entryUrl.length > 4096) return { status: 400, contentType: 'text/plain; charset=utf-8', body: 'Invalid discover request' };
    const coordinator = new ExploreCoordinator();
    const sources = await coordinator.getEntries('', sourceUrl);
    const entry = sources.find((item: ExploreEntry): boolean => item.url === entryUrl);
    if (!entry) return { status: 404, contentType: 'text/plain; charset=utf-8', body: 'Discover entry not found' };
    const books = await coordinator.explore(entry, Number.isFinite(page) ? Math.max(1, Math.min(50, page)) : 1, 30);
    return this.jsonResponse(books.map((book: SearchBook): LanResultDto => this.sourceResultDto(book)));
  }

  private async chaptersResponse(id: string): Promise<LanHttpResponse> {
    const bookUrl = this.idBooks.get(id);
    if (!bookUrl) return { status: 404, contentType: 'text/plain; charset=utf-8', body: 'Book Not Found' };
    const book = await appDb.getBook(bookUrl);
    if (!book) return { status: 404, contentType: 'text/plain; charset=utf-8', body: 'Book Not Found' };
    const chapters = await this.ensureBookChapters(book);
    const result: LanChapterDto[] = [];
    for (const chapter of chapters) {
      const dto = new LanChapterDto();
      dto.index = chapter.index;
      dto.title = chapter.title;
      dto.cached = chapter.cacheDate > 0;
      result.push(dto);
    }
    return this.jsonResponse(result);
  }

  private async contentResponse(id: string, index: number): Promise<LanHttpResponse> {
    const bookUrl = this.idBooks.get(id);
    if (!bookUrl || !Number.isFinite(index)) return { status: 404, contentType: 'text/plain; charset=utf-8', body: 'Chapter Not Found' };
    const book = await appDb.getBook(bookUrl);
    if (!book) return { status: 404, contentType: 'text/plain; charset=utf-8', body: 'Book Not Found' };
    const media = this.mediaInfo(book);
    if (!media.supported) return { status: 415, contentType: 'text/plain; charset=utf-8', body: 'This media type is not supported in browser reader' };
    const chapters = await this.ensureBookChapters(book);
    if (index < 0 || index >= chapters.length) return { status: 404, contentType: 'text/plain; charset=utf-8', body: 'Chapter Not Found' };
    let content = await appDb.getCachedChapterContent(bookUrl, index);
    if (!content) {
      const engine = ReadBookEngine.createBackgroundWorker();
      await engine.openBook(book);
      content = await engine.loadContent(index);
    }
    const result = new LanContentDto();
    result.index = index;
    result.title = chapters[index].title;
    result.content = content;
    result.total = chapters.length;
    result.chapterTime = book.durChapterTime;
    result.mediaType = media.type;
    result.images = media.type === 'comic' ? this.extractImageUrls(content).map((url: string) =>
      `/api/images/proxy?url=${encodeURIComponent(url)}&token=${encodeURIComponent(this.token)}`) : [];
    return this.jsonResponse(result);
  }

  private async imagesResponse(id: string, index: number): Promise<LanHttpResponse> {
    const bookUrl = this.idBooks.get(id);
    if (!bookUrl || !Number.isFinite(index)) return { status: 404, contentType: 'text/plain; charset=utf-8', body: 'Chapter Not Found' };
    const book = await appDb.getBook(bookUrl);
    if (!book) return { status: 404, contentType: 'text/plain; charset=utf-8', body: 'Book Not Found' };
    if (!BookTypeSupport.isImage(book)) return this.jsonResponse([]);
    const chapters = await this.ensureBookChapters(book);
    if (index < 0 || index >= chapters.length) return { status: 404, contentType: 'text/plain; charset=utf-8', body: 'Chapter Not Found' };
    let content = await appDb.getCachedChapterContent(bookUrl, index);
    if (!content) {
      const engine = ReadBookEngine.createBackgroundWorker();
      await engine.openBook(book);
      content = await engine.loadContent(index);
    }
    const urls = this.extractImageUrls(content);
    return this.jsonResponse(urls.map((url: string) => `/api/images/proxy?url=${encodeURIComponent(url)}&token=${encodeURIComponent(this.token)}`));
  }

  /** Some books have shelf metadata before their catalog has ever been cached.
   * Resolve the catalog through the normal reader engine when the chapter table
   * is empty so browser reading behaves like opening the book inside the App. */
  private async ensureBookChapters(book: Book): Promise<BookChapter[]> {
    const cached = await appDb.getBookChapters(book.bookUrl);
    if (cached.length > 0 || book.origin === 'local') return cached;
    try {
      const engine = ReadBookEngine.createBackgroundWorker();
      await engine.openBook(book);
      if (engine.chapters.length > 0) return engine.chapters;
    } catch (error) {
      console.warn('[LanReader] catalog refresh failed', error);
    }
    return cached;
  }

  private extractImageUrls(content: string): string[] {
    const result: string[] = [];
    const regex = /<(?:img|image)[^>]+(?:src|data-src|data-original|data-url)\s*=\s*["']([^"']+)["']/gi;
    let match: RegExpExecArray | null = null;
    while ((match = regex.exec(content || '')) !== null && result.length < 200) {
      const value = String(match[1] || '').trim();
      if ((value.startsWith('http://') || value.startsWith('https://')) && result.indexOf(value) < 0) result.push(value);
    }
    return result;
  }

  private mediaInfo(book: Book): LanMediaInfo {
    if (BookTypeSupport.isAudio(book)) return { type: 'audio', label: '\u6709\u58f0\u4e66', supported: false };
    if (BookTypeSupport.isImage(book)) return { type: 'comic', label: '\u6f2b\u753b', supported: false };
    return { type: 'novel', label: '\u5c0f\u8bf4', supported: true };
  }

  private async progressResponse(id: string, body: string): Promise<LanHttpResponse> {
    const bookUrl = this.idBooks.get(id);
    if (!bookUrl) return { status: 404, contentType: 'text/plain; charset=utf-8', body: 'Book Not Found' };
    try {
      const value = JSON.parse(body) as Record<string, Object>;
      const updatedAt = Number(value['updatedAt'] || 0);
      const chapterIndex = Number(value['chapterIndex'] || 0);
      const chapterPos = Number(value['chapterPos'] || 0);
      const current = await appDb.getBook(bookUrl);
      if (!current) return { status: 404, contentType: 'text/plain; charset=utf-8', body: 'Book Not Found' };
      if (!Number.isFinite(updatedAt) || updatedAt <= current.durChapterTime) {
        const stale = new LanProgressResult();
        stale.accepted = false;
        stale.reason = 'stale';
        stale.chapterTime = current.durChapterTime;
        return this.jsonResponse(stale);
      }
      await appDb.updateBookReadingProgress(bookUrl, String(value['chapterTitle'] || ''), chapterIndex,
        chapterPos, updatedAt, String(value['variable'] || '{}'), true);
      const accepted = new LanProgressResult();
      accepted.accepted = true;
      accepted.chapterTime = updatedAt;
      return this.jsonResponse(accepted);
    } catch (_) {
      return { status: 400, contentType: 'text/plain; charset=utf-8', body: 'Invalid progress' };
    }
  }

  private async coverResponse(id: string): Promise<LanHttpResponse> {
    const bookUrl = this.idBooks.get(id);
    if (!bookUrl) return { status: 404, contentType: 'text/plain; charset=utf-8', body: 'Book Not Found' };
    const book = await appDb.getBook(bookUrl);
    const url = book?.getDisplayCover() || '';
    if (!url || (!url.startsWith('http://') && !url.startsWith('https://'))) {
      return { status: 404, contentType: 'text/plain; charset=utf-8', body: 'Cover Not Found' };
    }
    const response = await this.httpClient.executeBinary({ url, method: 'GET', headers: {}, maxResponseBytes: 8 * 1024 * 1024 });
    if (!response.success || response.data.byteLength === 0) {
      return { status: 404, contentType: 'text/plain; charset=utf-8', body: 'Cover Not Found' };
    }
    const contentType = this.header(response.headers, 'content-type') || 'image/jpeg';
    return { status: 200, contentType, body: response.data.buffer as ArrayBuffer };
  }

  private async imageProxyResponse(url: string): Promise<LanHttpResponse> {
    if (!/^https?:\/\//i.test(url) || this.isPrivateProxyTarget(url)) {
      return { status: 400, contentType: 'text/plain; charset=utf-8', body: 'Invalid image URL' };
    }
    const response = await this.httpClient.executeBinary({ url, method: 'GET', headers: {}, maxResponseBytes: 12 * 1024 * 1024 });
    if (!response.success || response.data.byteLength === 0) {
      return { status: 404, contentType: 'text/plain; charset=utf-8', body: 'Image Not Found' };
    }
    const contentType = this.header(response.headers, 'content-type') || 'image/jpeg';
    return { status: 200, contentType, body: response.data.buffer as ArrayBuffer };
  }

  private isPrivateProxyTarget(url: string): boolean {
    try {
      const host = url.replace(/^https?:\/\//i, '').split(/[/?#:]/)[0];
      if (!host || host === 'localhost' || host === '::1') return true;
      return this.isPrivateIpv4(host) || host.endsWith('.local') || host.endsWith('.lan');
    } catch (_) {
      return true;
    }
  }

  private htmlResponse(): LanHttpResponse {
    // Never embed the internal session token when a password is configured;
    // it must only be issued by /api/auth after successful verification.
    const token = this.escapeHtml(this.password.length > 0 ? '' : this.token);
    const passwordRequired = this.hasPassword() ? 'true' : 'false';
    const html = `<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>开源轻页</title><style>
      :root{color-scheme:light;--bg:#f5f6f8;--card:#fff;--text:#202124;--muted:#6b7280;--accent:#2563eb}*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font-family:system-ui,-apple-system,"Noto Sans SC",sans-serif}body.dark{color-scheme:dark;--bg:#111827;--card:#1f2937;--text:#f3f4f6;--muted:#9ca3af}header{position:sticky;top:0;z-index:2;padding:14px max(16px,calc((100vw - 1100px)/2));background:color-mix(in srgb,var(--card) 92%,transparent);backdrop-filter:blur(12px);display:flex;gap:10px;align-items:center}header h1{font-size:20px;margin:0;flex:1}button,input{font:inherit;border:1px solid #d1d5db;border-radius:10px;padding:8px 12px;background:var(--card);color:var(--text)}button{cursor:pointer}main{max-width:1100px;margin:auto;padding:18px}.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(180px,1fr));gap:14px}.shelf-group{margin-bottom:28px}.shelf-group h2{font-size:18px;margin:0 0 12px;color:var(--text)}.group-count{font-size:13px;color:var(--muted);font-weight:normal;margin-left:8px}.card{background:var(--card);border-radius:16px;padding:12px;box-shadow:0 4px 18px #0000000d;cursor:pointer}.card.disabled{opacity:.58;cursor:not-allowed}.cover-wrap{position:relative}.cover{width:100%;aspect-ratio:3/4;object-fit:cover;border-radius:10px;background:#dbeafe}.type-badge{position:absolute;left:8px;top:8px;padding:3px 7px;border-radius:999px;background:#2563eb;color:#fff;font-size:12px}.type-badge.comic{background:#7c3aed}.type-badge.audio{background:#d97706}.card h3{font-size:16px;margin:10px 0 4px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.muted{color:var(--muted);font-size:13px}.hidden{display:none}.reader{max-width:860px;margin:auto}.reader h2{font-size:22px}.content{white-space:pre-wrap;text-indent:2em;line-height:1.9;font-size:var(--reader-size,20px);letter-spacing:.02em;word-break:break-word;background:var(--card);border-radius:16px;padding:clamp(18px,4vw,48px);min-height:50vh}.comic-images{display:flex;flex-direction:column;gap:14px}.comic-images img{width:100%;height:auto;border-radius:10px;background:#e5e7eb}.chapter-next{text-align:center;margin:24px 0 12px}.chapter-next button{min-width:180px;padding:12px 26px;border:0;border-radius:999px;background:var(--accent);color:#fff;font-size:16px}.toolbar{display:flex;gap:8px;flex-wrap:wrap;margin:12px 0}.chapters{display:grid;grid-template-columns:repeat(auto-fill,minmax(220px,1fr));gap:8px}.chapters button{text-align:left;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.back{margin-bottom:12px}@media(max-width:600px){main{padding:12px}.grid{grid-template-columns:repeat(2,minmax(0,1fr));gap:10px}.card{padding:9px}.content{padding:18px;font-size:var(--reader-size,18px)}}
    </style></head><body><header><h1>开源轻页</h1><input id="search" placeholder="搜索书名" oninput="renderBooks()"><select id="typeFilter" onchange="renderBooks()"><option value="all">全部类型</option><option value="novel">小说</option><option value="comic">漫画</option><option value="audio">有声书</option></select><select id="sortFilter" onchange="renderBooks()"><option value="recent">最近阅读</option><option value="name">书名排序</option><option value="progress">阅读进度</option></select><button id="themeButton" onclick="toggleTheme()"><span id="themeIcon">☾</span><span id="themeLabel">夜间</span></button></header><div id="login" class="login hidden"><h2>访问密码</h2><p class="muted">请输入 App 中设置的浏览器看书密码</p><input id="accessPassword" type="password" placeholder="输入密码"><button onclick="loginWithPassword()">进入书架</button><p id="loginStatus" class="muted"></p></div><main id="appMain"><section id="shelf"><div id="books"></div></section><section id="detail" class="hidden"><button class="back" onclick="showShelf()">← 返回书架</button><h2 id="bookTitle"></h2><p id="bookMeta" class="muted"></p><div id="chapters" class="chapters"></div></section><section id="reader" class="hidden reader"><div class="toolbar"><button onclick="showDetail()">← 章节</button><button onclick="previousChapter()">上一章</button><button onclick="nextChapter()">下一章</button><button onclick="changeFont(-1)">A−</button><button onclick="changeFont(1)">A+</button></div><h2 id="chapterTitle"></h2><article id="content" class="content"></article><div id="images" class="comic-images hidden"></div><div id="chapterNext" class="chapter-next hidden"><button onclick="nextChapter()">下一章</button></div></section></main><script>
      const initialToken='${token}';const passwordRequired=${passwordRequired};let token=sessionStorage.getItem('lanReaderToken')||(!passwordRequired?initialToken:'');if(!passwordRequired)sessionStorage.setItem('lanReaderToken',token);if(location.search.includes('token=')){history.replaceState(null,document.title,location.pathname)}let books=[],current=null,chapters=[],chapterIndex=0,fontSize=20;const api=async(p,o={})=>{const options=Object.assign({},o,{headers:Object.assign({},o.headers||{}, {'Authorization':'Bearer '+token})});const r=await fetch(p,options);if(!r.ok)throw Error(await r.text());return r.json()};function showLogin(message){document.getElementById('login').classList.remove('hidden');document.getElementById('appMain').classList.add('hidden');if(message)document.getElementById('loginStatus').textContent=message}async function loginWithPassword(){const input=document.getElementById('accessPassword');const status=document.getElementById('loginStatus');const password=input.value||'';if(!password){status.textContent='请输入密码';return}status.textContent='验证中...';try{const r=await fetch('/api/auth',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({password})});const data=await r.json();if(!r.ok||!data.token)throw Error(data.message||'密码错误');token=data.token;sessionStorage.setItem('lanReaderToken',token);document.getElementById('login').classList.add('hidden');document.getElementById('appMain').classList.remove('hidden');loadBooks().catch(e=>showLogin(e.message))}catch(e){status.textContent=e.message||'密码错误'}}async function ensureAuth(){if(!passwordRequired){return true}if(!token){showLogin('请输入 App 中设置的访问密码');return false}try{await api('/api/health');return true}catch(e){sessionStorage.removeItem('lanReaderToken');token='';showLogin('密码已失效，请重新输入');return false}}
      async function loadBooks(){books=await api('/api/books');renderBooks()}function renderBooks(){const q=(document.getElementById('search').value||'').toLowerCase();const type=(document.getElementById('typeFilter').value||'all');const sort=(document.getElementById('sortFilter').value||'recent');const visible=books.filter(b=>(b.name+' '+(b.author||'')).toLowerCase().includes(q)).filter(b=>type==='all'||b.mediaType===type).slice();if(sort==='name')visible.sort((a,b)=>String(a.name||'').localeCompare(String(b.name||'')));if(sort==='progress')visible.sort((a,b)=>Number(b.chapterIndex||0)-Number(a.chapterIndex||0));const groupIds=[];visible.forEach(b=>{const id=Number(b.group||0);if(groupIds.indexOf(id)<0)groupIds.push(id)});groupIds.sort((a,b)=>{if(a===0)return -1;if(b===0)return 1;const ao=(visible.find(x=>Number(x.group||0)===a)||{}).groupOrder||a;const bo=(visible.find(x=>Number(x.group||0)===b)||{}).groupOrder||b;return ao-bo});document.getElementById('books').innerHTML=groupIds.map(gid=>{const items=visible.filter(b=>Number(b.group||0)===gid);const name=(items[0]&&items[0].groupName)||(gid===0?'未分组':'分组 '+gid);return '<section class="shelf-group"><h2>'+esc(name)+'<span class="group-count">('+items.length+')</span></h2><div class="grid">'+items.map(b=>'<div class="card'+(b.browserSupported===false?' disabled':'')+'" data-book-id="'+escAttr(b.id)+'" data-supported="'+(b.browserSupported===false?'0':'1')+'"><div class="cover-wrap"><img class="cover" loading="lazy" src="'+escAttr(b.cover||'')+'"><span class="type-badge '+escAttr(b.mediaType||'novel')+'">'+esc(b.mediaLabel||'小说')+'</span></div><h3>'+esc(b.name)+'</h3><div class="muted">'+esc(b.author||'')+' · '+(b.chapterIndex+1)+'章</div>'+(b.browserSupported===false?'<div class="muted unsupported">浏览器阅读暂不支持</div>':'')+'</div>').join('')+'</div></section>'}).join('')||'<p class="muted">书架暂无内容</p>'}function esc(v){const d=document.createElement('div');d.textContent=v||'';return d.innerHTML}function escAttr(v){return esc(v).replace(/"/g,'&quot;')}document.getElementById('books').addEventListener('click',function(e){const card=e.target.closest('.card');if(card.getAttribute('data-supported')==='0'){const badge=card.querySelector('.type-badge');alert((badge?badge.textContent:'此类型')+'暂不支持浏览器阅读，请在 App 内使用对应功能');return}openBook(card.getAttribute('data-book-id')||'')})
      async function openBook(id){current=books.find(b=>b.id===id);if(!current)return;chapters=await api('/api/books/'+id+'/chapters');document.getElementById('shelf').classList.add('hidden');document.getElementById('reader').classList.add('hidden');document.getElementById('detail').classList.remove('hidden');document.getElementById('bookTitle').textContent=current.name;document.getElementById('bookMeta').textContent=(current.author||'')+' · '+chapters.length+'章';document.getElementById('chapters').innerHTML=chapters.map(c=>'<button data-chapter-index="'+c.index+'">'+esc(c.title)+(c.cached?' ✓':'')+'</button>').join('');document.getElementById('chapters').onclick=function(e){const button=e.target.closest('button');if(button)openChapter(Number(button.getAttribute('data-chapter-index')||0))}}
      async function openChapter(i){chapterIndex=i;const data=await api('/api/books/'+current.id+'/chapters/'+i);document.getElementById('detail').classList.add('hidden');document.getElementById('reader').classList.remove('hidden');document.getElementById('chapterTitle').textContent=data.title;const content=document.getElementById('content');const images=document.getElementById('images');if(data.mediaType==='comic'&&data.images&&data.images.length){content.classList.add('hidden');images.classList.remove('hidden');images.innerHTML=data.images.map(src=>'<img loading="lazy" src="'+escAttr(src)+'" onerror="this.alt=\'图片加载失败\'">').join('')}else{images.classList.add('hidden');content.classList.remove('hidden');content.textContent=data.content||'章节内容为空'}const chapterNext=document.getElementById('chapterNext');chapterNext.classList.toggle('hidden',chapterIndex>=chapters.length-1);document.documentElement.style.setProperty('--reader-size',fontSize+'px');window.scrollTo(0,0);saveProgress()}
      function showShelf(){document.getElementById('detail').classList.add('hidden');document.getElementById('reader').classList.add('hidden');document.getElementById('shelf').classList.remove('hidden')}function showDetail(){document.getElementById('reader').classList.add('hidden');document.getElementById('detail').classList.remove('hidden')}function previousChapter(){if(chapterIndex>0)openChapter(chapterIndex-1)}function nextChapter(){if(chapterIndex<chapters.length-1)openChapter(chapterIndex+1)}function changeFont(d){fontSize=Math.max(14,Math.min(32,fontSize+d));document.documentElement.style.setProperty('--reader-size',fontSize+'px');localStorage.setItem('lanReaderFontSize',String(fontSize))}function applyTheme(){const dark=document.body.classList.contains('dark');document.getElementById('themeIcon').textContent=dark?'☀':'☾';document.getElementById('themeLabel').textContent=dark?'日间':'夜间'}function toggleTheme(){document.body.classList.toggle('dark');localStorage.setItem('lanReaderDark',document.body.classList.contains('dark')?'1':'0');applyTheme()}let progressTimer=0;async function saveProgress(){if(!current)return;try{await api('/api/books/'+current.id+'/progress',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({chapterIndex,chapterPos:document.documentElement.scrollTop||0,chapterTitle:chapters[chapterIndex]?.title||'',updatedAt:Date.now(),variable:'{}'})})}catch(e){console.warn(e)}}window.addEventListener('scroll',()=>{if(progressTimer)clearTimeout(progressTimer);progressTimer=setTimeout(saveProgress,700)});window.addEventListener('beforeunload',saveProgress);fontSize=Number(localStorage.getItem('lanReaderFontSize')||20);if(localStorage.getItem('lanReaderDark')==='1')document.body.classList.add('dark');ensureAuth().then(ok=>{if(ok)loadBooks().catch(e=>showLogin(e.message))});
    </script></body></html>`;
    const nav = '<nav class="page-nav"><button onclick="showPage(\'shelf\')">&#x4e66;&#x67b6;</button><button onclick="showPage(\'discover\')">&#x53d1;&#x73b0;</button><button onclick="showPage(\'searchPage\')">&#x641c;&#x7d22;</button></nav>';
    const discover = '<section id="discover" class="hidden"><div class="toolbar"><h2 style="margin:0;flex:1">&#x53d1;&#x73b0;</h2><select id="discoverSource"><option value="">&#x9009;&#x62e9;&#x4e66;&#x6e90;</option></select><select id="discoverPlatform" class="hidden"></select></div><div id="discoverEntries" class="entry-list"></div><div id="discoverBooks" class="grid"></div><p id="discoverStatus" class="muted"></p></section>';
    const searchPage = '<section id="searchPage" class="hidden"><div class="toolbar"><h2 style="margin:0;flex:1">&#x641c;&#x7d22;</h2><input id="remoteQuery" placeholder="&#x8f93;&#x5165;&#x4e66;&#x540d;&#x6216;&#x4f5c;&#x8005;" maxlength="80"><select id="remoteSource"><option value="">&#x5168;&#x90e8;&#x4e66;&#x6e90;</option></select><button onclick="runRemoteSearch()">&#x641c;&#x7d22;</button></div><div id="searchStatus" class="muted"></div><div id="searchResults" class="grid"></div></section>';
     const extraCss = '<style>header h1{flex:0 0 auto}.page-nav{display:flex;gap:6px;margin:0;padding:0;white-space:nowrap}header>input{margin-left:auto}.theme-select{min-width:112px}.entry-list{display:flex;gap:8px;flex-wrap:wrap;margin:10px 0}.entry-list button.active{background:var(--accent);color:#fff}.result-actions{display:flex;gap:6px;margin-top:8px}.result-actions button{flex:1;font-size:13px}.login{max-width:420px;margin:15vh auto;padding:28px 22px;text-align:center;background:var(--card);border-radius:16px;box-shadow:0 8px 30px rgba(0,0,0,.12)}.login input{display:block;width:100%;box-sizing:border-box;margin:18px 0 12px;padding:12px;border:1px solid #d1d5db;border-radius:8px;background:var(--card);color:inherit}.login button{width:100%;padding:11px;border:0;border-radius:8px;background:var(--accent);color:#fff;font-size:15px}body.word-theme{--bg:#e5e7eb;--card:#fff;--text:#1f2937;--muted:#64748b;--accent:#185abd;background:#e5e7eb;color:#1f2937;font-family:"Calibri","Aptos","Microsoft YaHei",sans-serif}body.word-theme header{background:#185abd;color:#fff;backdrop-filter:none}body.word-theme header h1{color:#fff}body.word-theme header input,body.word-theme header select,body.word-theme header button{background:#fff;color:#1f2937;border-color:#cbd5e1}body.word-theme main{background:#e5e7eb}body.word-theme .reader{background:#fff;box-shadow:0 2px 12px rgba(15,23,42,.18);padding:38px 52px;max-width:900px}body.word-theme .reader .toolbar{border-bottom:1px solid #d1d5db;padding-bottom:12px}body.word-theme .content{border-radius:2px;box-shadow:none;padding:10px 0 34px;min-height:60vh;font-family:"SimSun","宋体","Times New Roman",serif;line-height:2;font-size:var(--reader-size,20px)}body.word-theme .reader h2{font-family:"Microsoft YaHei","Calibri",sans-serif;font-weight:600;color:#111827}body.word-theme .chapter-next button{background:#185abd}@media(max-width:600px){header{flex-wrap:wrap}header h1{width:auto;flex:0 0 auto}.page-nav{max-width:calc(100% - 110px);overflow:auto}header>input{margin-left:0;max-width:none;flex:1}body.word-theme .reader{padding:22px 20px}.login{margin:12vh 16px}}</style>';
    const extraJs = `
      function applyReaderTheme(){const value=localStorage.getItem('lanReaderTheme')||'default';document.body.classList.toggle('word-theme',value==='word');const select=document.getElementById('themeSelect');if(select)select.value=value}
      function setReaderTheme(value){const theme=value==='word'?'word':'default';localStorage.setItem('lanReaderTheme',theme);applyReaderTheme()}
      applyReaderTheme();
      window.addEventListener('error',function(e){const n=document.getElementById('books');if(n&&!n.innerText)n.innerHTML='<p class="muted">页面脚本错误：'+esc(e.message||'unknown')+'</p>'});
      document.addEventListener('click',function(e){const b=e.target&&e.target.closest?e.target.closest('.entry-button'):null;if(b)loadDiscoverBooks(b,b.getAttribute('data-url')||'')});
      function showPage(page){['shelf','discover','searchPage','detail','reader'].forEach(id=>{const el=document.getElementById(id);if(el)el.classList.toggle('hidden',id!==page)});if(page==='discover')loadDiscoverSources();if(page==='searchPage')loadSearchSources()}
      function sourceCard(b){const disabled=b.browserSupported===false||b.mediaType==='comic'||b.mediaType==='audio';return '<div class="card'+(disabled?' disabled':'')+'"><div class="cover-wrap">'+(b.cover?'<img class="cover" loading="lazy" src="'+escAttr(b.cover)+'">':'<div class="cover"></div>')+'<span class="type-badge '+escAttr(b.mediaType||'novel')+'">'+esc(b.mediaLabel||'\\u5c0f\\u8bf4')+'</span></div><h3>'+esc(b.name||'')+'</h3><div class="muted">'+esc(b.author||'')+' · '+esc(b.originName||'')+'</div><div class="muted">'+esc(b.latestChapterTitle||b.intro||'')+'</div>'+(disabled?'<div class="muted unsupported">\\u6d4f\\u5668\\u9605\\u8bfb\\u6682\\u4e0d\\u652f\\u6301</div>':'')+'<div class="result-actions">'+(disabled?'':'<button onclick="event.stopPropagation();addRemoteBook('+JSON.stringify(b).replace(/"/g,'&quot;')+')">\\u52a0\\u5165\\u4e66\\u67b6</button>')+'</div></div>'}
      async function loadSearchSources(){if(document.getElementById('remoteSource').options.length>1)return;try{const ss=await api('/api/search/sources');document.getElementById('remoteSource').innerHTML='<option value="">\\u5168\\u90e8\\u4e66\\u6e90</option>'+ss.map(s=>'<option value="'+escAttr(s.url)+'">'+esc(s.name)+'</option>').join('')}catch(e){document.getElementById('searchStatus').textContent=e.message}}
      async function runRemoteSearch(){const q=(document.getElementById('remoteQuery').value||'').trim();if(!q){document.getElementById('searchStatus').textContent='\\u8bf7\\u5148\\u8f93\\u5165\\u5173\\u952e\\u8bcd';return}document.getElementById('searchStatus').textContent='\\u641c\\u7d22\\u4e2d...';document.getElementById('searchResults').innerHTML='';try{const source=document.getElementById('remoteSource').value||'';const data=await api('/api/search?q='+encodeURIComponent(q)+'&source='+encodeURIComponent(source));document.getElementById('searchStatus').textContent='\\u627e\\u5230 '+data.length+' \\u672c';document.getElementById('searchResults').innerHTML=data.map(sourceCard).join('')||'<p class="muted">\\u672a\\u627e\\u5230\\u7ed3\\u679c</p>'}catch(e){document.getElementById('searchStatus').textContent=e.message}}
      async function addRemoteBook(book){try{const r=await api('/api/search/add',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(book)});alert(r.ok?'\\u5df2\\u52a0\\u5165\\u4e66\\u67b6':r.message);if(r.ok)loadBooks()}catch(e){alert(e.message)}}
      async function loadDiscoverSources(){if(document.getElementById('discoverSource').options.length>1)return;try{const ss=await api('/api/discover/sources');const sel=document.getElementById('discoverSource');sel.innerHTML='<option value="">\\u9009\\u62e9\\u4e66\\u6e90</option>'+ss.map(s=>'<option value="'+escAttr(s.url)+'">'+esc(s.name)+'</option>').join('');if(ss.length){sel.value=ss[0].url;loadDiscoverEntries()}}catch(e){document.getElementById('discoverStatus').textContent=e.message}}
      async function loadDiscoverEntries(){const source=document.getElementById('discoverSource').value||'';if(!source)return;const platform=document.getElementById('discoverPlatform').value||'';document.getElementById('discoverStatus').textContent='\\u6b63\\u5728\\u52a0\\u8f7d\\u53d1\\u73b0\\u5206\\u7c7b...';try{const ss=await api('/api/discover/sources');const selected=ss.find(s=>s.url===source);const ps=document.getElementById('discoverPlatform');if(selected&&selected.platforms&&selected.platforms.length){ps.classList.remove('hidden');ps.innerHTML=selected.platforms.map(p=>'<option value="'+escAttr(p)+'">'+esc(p)+'</option>').join('')}const entries=await api('/api/discover/entries?source='+encodeURIComponent(source)+'&platform='+encodeURIComponent(platform));document.getElementById('discoverEntries').innerHTML=entries.map((e,i)=>'<button class="entry-button'+(i===0?' active':'')+'" data-url="'+escAttr(e.url)+'" onclick="loadDiscoverBooks(this,\''+escAttr(e.url)+'\')">'+esc(e.title)+'</button>').join('');document.getElementById('discoverBooks').innerHTML='';document.getElementById('discoverStatus').textContent=entries.length?'':'\\u6682\\u65e0\\u53d1\\u73b0\\u5206\\u7c7b';if(entries.length)loadDiscoverBooks(null,entries[0].url)}catch(e){document.getElementById('discoverStatus').textContent=e.message}}
      async function loadDiscoverBooks(button,url){if(button){document.querySelectorAll('.entry-button').forEach(x=>x.classList.remove('active'));button.classList.add('active')}const source=document.getElementById('discoverSource').value||'';document.getElementById('discoverStatus').textContent='\\u6b63\\u5728\\u52a0\\u8f7d...';try{const data=await api('/api/discover?source='+encodeURIComponent(source)+'&entry='+encodeURIComponent(url)+'&page=1');document.getElementById('discoverBooks').innerHTML=data.map(sourceCard).join('')||'<p class="muted">\\u6682\\u65e0\\u4e66\\u7c4d</p>';document.getElementById('discoverStatus').textContent='\\u627e\\u5230 '+data.length+' \\u672c'}catch(e){document.getElementById('discoverStatus').textContent=e.message}}
    `;
    const safeExtraJs = extraJs.replace(/onclick="loadDiscoverBooks\(this,[^"]*"/g, '');
    const enhanced = html.replace('</style></head>', '</style>'+extraCss+'</head>')
      .replace('</button></header>', '</button><select id="themeSelect" class="theme-select" title="切换主题" onchange="setReaderTheme(this.value)"><option value="default">默认主题</option><option value="word">Word 主题</option></select></header>')
      .replace('<header><h1>开源轻页</h1>', '<header><h1>开源轻页</h1>'+nav)
      .replace('</section><section id="detail"', '</section>'+discover+searchPage+'<section id="detail"')
      .replace(/\s+onerror="[^"]*"/g, '')
      .replace('</script></body>', safeExtraJs+'</script></body>');
    return { status: 200, contentType: 'text/html; charset=utf-8', body: enhanced };
  }

  private async sendResponse(client: socket.TCPSocketConnection, response: LanHttpResponse): Promise<void> {
    // TextEncoder.encodeInto('') is specified to return undefined. Send textual
    // responses as one UTF-8 string and delimit the body by closing
    // the connection, avoiding a byte-length calculation that can produce an
    // empty response or throw before anything is written to the socket.
    if (typeof response.body === 'string') {
      const header = `HTTP/1.1 ${response.status} ${this.statusText(response.status)}\r\n` +
        `Content-Type: ${response.contentType}\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n`;
      console.info(`[LanReader] sending HTTP ${response.status} text response`);
      await client.send({ data: header + response.body, encoding: 'UTF-8' });
      await client.close();
      return;
    }
    const body = new Uint8Array(response.body);
    const header = `HTTP/1.1 ${response.status} ${this.statusText(response.status)}\r\n` +
      `Content-Type: ${response.contentType}\r\nContent-Length: ${body.byteLength}\r\n` +
      `Cache-Control: no-store\r\nConnection: close\r\n\r\n`;
    console.info(`[LanReader] sending HTTP ${response.status}, ${body.byteLength} bytes`);
    await client.send({ data: header, encoding: 'UTF-8' });
    if (body.byteLength > 0) await client.send({ data: body.buffer as ArrayBuffer });
    await client.close();
  }

  private jsonResponse(value: Object): LanHttpResponse {
    return { status: 200, contentType: 'application/json; charset=utf-8', body: JSON.stringify(value) };
  }

  private statusText(status: number): string {
    if (status === 200) return 'OK';
    if (status === 400) return 'Bad Request';
    if (status === 401) return 'Unauthorized';
    if (status === 404) return 'Not Found';
    return 'Error';
  }

  private header(headers: Record<string, string>, name: string): string {
    const lower = name.toLowerCase();
    for (const key of Object.keys(headers)) if (key.toLowerCase() === lower) return String(headers[key] || '');
    return '';
  }

  private bookId(bookUrl: string): string {
    const existing = this.bookIds.get(bookUrl);
    if (existing) return existing;
    let hash = 2166136261;
    for (let i = 0; i < bookUrl.length; i++) hash = Math.imul(hash ^ bookUrl.charCodeAt(i), 16777619);
    let id = `b${(hash >>> 0).toString(36)}`;
    let suffix = 1;
    while (this.idBooks.has(id) && this.idBooks.get(id) !== bookUrl) id = `b${(hash >>> 0).toString(36)}_${suffix++}`;
    this.bookIds.set(bookUrl, id);
    this.idBooks.set(id, bookUrl);
    return id;
  }

  private async findLanIp(): Promise<string> {
    try {
      const net = await connection.getDefaultNet();
      if (!net) return '';
      const properties = await connection.getConnectionProperties(net);
      let fallback = '';
      for (const item of properties.linkAddresses || []) {
        const address = item.address?.address || '';
        if (!address || address.includes(':') || address === '127.0.0.1') continue;
        if (!fallback) fallback = address;
        if (this.isPrivateIpv4(address)) return address;
      }
      return fallback;
    } catch (error) {
      console.warn('[LanReader] get network address failed', error);
      return '';
    }
  }

  private isPrivateIpv4(ip: string): boolean {
    const parts = ip.split('.').map((item: string) => Number(item));
    if (parts.length !== 4 || parts.some((item: number) => !Number.isFinite(item))) return false;
    return parts[0] === 10 || (parts[0] === 172 && parts[1] >= 16 && parts[1] <= 31) ||
      (parts[0] === 192 && parts[1] === 168) || parts[0] === 169 && parts[1] === 254;
  }

  private createToken(): string {
    const seed = `${Date.now()}-${Math.random()}-${Math.random()}`;
    let value = 0;
    for (let i = 0; i < seed.length; i++) value = Math.imul(value ^ seed.charCodeAt(i), 16777619);
    return `${(value >>> 0).toString(36)}${Date.now().toString(36)}`;
  }

  private escapeHtml(value: string): string {
    return value.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }
}

export const lanReaderServer = LanReaderServer.getInstance();
