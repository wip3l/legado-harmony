import { BookSource, SearchBook, SearchRule } from '../data/Book';
import { appDb } from '../data/AppDatabase';
import { httpHelper } from '../http/HttpHelper';
import { JsEvaluator } from '../js/JsEvaluator';

export interface SearchCallback {
  onSearchStart: () => void;
  onSearchResult: (books: SearchBook[]) => void;
  onSearchFinish: (isEmpty: boolean) => void;
  onSearchError: (error: string) => void;
}

interface SearchRequest {
  url: string;
  method: string;
  body: string;
  headers: Record<string, string>;
}

export class SearchService {
  private static instance: SearchService | null = null;
  private isSearching: boolean = false;
  private searchId: number = 0;
  private searchBooks: SearchBook[] = [];
  private callback: SearchCallback | null = null;
  private threadCount: number = 8;

  private constructor() {}

  static getInstance(): SearchService {
    if (!SearchService.instance) {
      SearchService.instance = new SearchService();
    }
    return SearchService.instance;
  }

  setCallback(callback: SearchCallback) {
    this.callback = callback;
  }

  setThreadCount(count: number) {
    this.threadCount = Math.max(1, Math.min(count, 32));
  }

  async search(keyword: string, sources?: BookSource[]) {
    console.log('SearchService.search 被调用, keyword:', keyword, 'threads:', this.threadCount);

    if (this.isSearching) {
      this.cancelSearch();
    }

    if (!keyword) {
      console.log('关键词为空');
      this.callback?.onSearchError('请输入搜索关键词');
      return;
    }

    this.isSearching = true;
    this.searchId = Date.now();
    this.searchBooks = [];
    const currentSearchId = this.searchId;

    this.callback?.onSearchStart();

    try {
      const searchSources = sources || await appDb.getEnabledBookSources();
      console.log('启用的书源数量:', searchSources.length);

      if (searchSources.length === 0) {
        console.log('没有启用的书源');
        this.callback?.onSearchError('没有启用的书源，请先添加并启用书源');
        this.isSearching = false;
        return;
      }

      let hasResult = false;
      let completedCount = 0;
      const totalCount = searchSources.length;

      // 多线程并行搜索
      const chunks = this.chunkArray(searchSources, this.threadCount);

      for (const chunk of chunks) {
        if (currentSearchId !== this.searchId) {
          console.log('搜索被取消');
          return;
        }

        // 每个 chunk 内的书源并行搜索
        const promises = chunk.map(async (source: BookSource) => {
          if (currentSearchId !== this.searchId) return;

          try {
            const books = await this.searchFromSource(source, keyword);
            completedCount++;
            console.log(`书源 ${source.bookSourceName} 完成 (${completedCount}/${totalCount}), 找到 ${books.length} 本`);
            if (books.length > 0) {
              hasResult = true;
              this.searchBooks = [...this.searchBooks, ...books];
              this.callback?.onSearchResult(this.searchBooks);
            }
          } catch (e) {
            completedCount++;
            console.warn(`搜索书源 ${source.bookSourceName} 跳过:`, this.formatError(e));
          }
        });

        await Promise.all(promises);
      }

      console.log('搜索完成, hasResult:', hasResult, '总结果:', this.searchBooks.length);
      if (currentSearchId === this.searchId) {
        this.callback?.onSearchFinish(!hasResult);
      }
    } catch (e) {
      console.error('搜索失败:', e);
      if (currentSearchId === this.searchId) {
        this.callback?.onSearchError('搜索失败');
      }
    } finally {
      if (currentSearchId === this.searchId) {
        this.isSearching = false;
      }
    }
  }

  private chunkArray(array: BookSource[], chunkSize: number): BookSource[][] {
    const chunks: BookSource[][] = [];
    for (let i = 0; i < array.length; i += chunkSize) {
      chunks.push(array.slice(i, Math.min(i + chunkSize, array.length)));
    }
    return chunks;
  }

  private async searchFromSource(source: BookSource, keyword: string): Promise<SearchBook[]> {
    try {
      const request = this.buildSearchRequest(source, keyword, 1);
      console.log('搜索URL:', request.url);

      if (!request.url) {
        return [];
      }

      const headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        ...this.parseHeader(source.header),
        ...request.headers
      };
      if (request.method === 'POST' && request.body && !headers['Content-Type']) {
        headers['Content-Type'] = 'application/x-www-form-urlencoded';
      }

      console.log('发送请求...');
      const response = request.method === 'POST'
        ? await httpHelper.post(request.url, request.body, headers)
        : await httpHelper.get(request.url, headers);
      console.log('响应状态:', response.statusCode);

      if (response.statusCode !== 200) {
        console.log('响应状态码不是200');
        return [];
      }

      console.log('响应内容长度:', response.body.length);
      if (response.body.length < 500) {
        console.log('搜索响应:', response.body);
      }
      const books = this.parseSearchResult(response.body, source);
      console.log('解析到书籍数量:', books.length);
      return books;
    } catch (e) {
      console.warn(`搜索书源 ${source.bookSourceName} 跳过:`, this.formatError(e));
      return [];
    }
  }

  private buildSearchRequest(source: BookSource, keyword: string, page: number): SearchRequest {
    const headers: Record<string, string> = {};
    let url = source.searchUrl || '';
    const encodedKeyword = encodeURIComponent(keyword);
    const baseUrl = this.cleanBaseUrl(source.bookSourceUrl);

    if (!url) {
      url = `${baseUrl}/search?q={{key}}`;
    }

    // 使用 JS 求值引擎解析 {{...}} 模板
    if (url.includes('{{') && url.includes('}}')) {
      const evaluator = new JsEvaluator();
      evaluator.setVariable('key', encodedKeyword);
      evaluator.setVariable('searchKey', encodedKeyword);
      evaluator.setVariable('page', String(page));
      evaluator.setVariable('encodedKeyword', encodedKeyword);
      url = evaluator.evalTemplate(url);
    }

    if (url.startsWith('<js>') && url.endsWith('</js>')) {
      url = url.substring(4, url.length - 5);
    }

    if (url.startsWith('@js:')) {
      url = this.parseSimpleJsSearchUrl(url, baseUrl);
      if (!url) {
        return {
          url: '',
          method: 'GET',
          body: '',
          headers: headers
        };
      }
    }

    url = url
      .replace(/\{\{key\}\}/g, encodedKeyword)
      .replace(/\{\{searchKey\}\}/g, encodedKeyword)
      .replace(/\{key\}/g, encodedKeyword)
      .replace(/\{searchKey\}/g, encodedKeyword)
      .replace(/\{\{page\}\}/g, String(page))
      .replace(/\{page\}/g, String(page));

    const option = this.extractUrlOption(url);
    url = option.url;
    let method = option.method;
    let body = option.body;
    Object.assign(headers, option.headers);

    const headerStart = url.indexOf('@Header:');
    if (headerStart >= 0) {
      const headerEnd = url.indexOf('@End', headerStart);
      if (headerEnd > headerStart) {
        const headerStr = url.substring(headerStart + 8, headerEnd);
        Object.assign(headers, this.parseHeader(headerStr));
        url = url.substring(0, headerStart) + url.substring(headerEnd + 4);
      }
    }

    if (url.startsWith('@')) {
      method = 'POST';
      url = url.substring(1);
      const questionIndex = url.indexOf('?');
      if (questionIndex >= 0) {
        body = url.substring(questionIndex + 1);
        url = url.substring(0, questionIndex);
      }
    }

    url = this.resolveUrl(url, baseUrl);

    return {
      url: url.trim(),
      method: method,
      body: body,
      headers: headers
    };
  }

  private parseSimpleJsSearchUrl(searchUrl: string, baseUrl: string): string {
    const baseConcatMatch = searchUrl.match(/baseUrl\s*\+\s*["']([^"']+)["']/);
    if (baseConcatMatch) {
      return `${baseUrl}${baseConcatMatch[1]}`;
    }

    const relativeOptionMatch = searchUrl.match(/["'](\/[^"']+,\{[\s\S]+?\})["']/);
    if (relativeOptionMatch) {
      return relativeOptionMatch[1];
    }

    const directUrlMatch = searchUrl.match(/["'](https?:\/\/[^"']+)["']/);
    if (directUrlMatch) {
      return directUrlMatch[1];
    }

    return '';
  }

  private extractUrlOption(url: string): SearchRequest {
    const request: SearchRequest = {
      url: url,
      method: 'GET',
      body: '',
      headers: {}
    };

    const optionIndex = url.indexOf(",{");
    if (optionIndex < 0) {
      return request;
    }

    request.url = url.substring(0, optionIndex);
    const optionText = url.substring(optionIndex + 1);

    try {
      // 尝试直接解析
      const option = JSON.parse(optionText) as Record<string, Object>;
      if (option['method'] !== undefined && option['method'] !== null) {
        request.method = String(option['method']).toUpperCase();
      }
      if (option['body'] !== undefined && option['body'] !== null) {
        request.body = String(option['body']);
      }
      if (option['headers'] && typeof option['headers'] === 'object') {
        request.headers = option['headers'] as Record<string, string>;
      }
    } catch (e) {
      // 尝试替换单引号后再解析
      try {
        const fixed = optionText.replace(/'([^']*)'/g, '"$1"');
        const option = JSON.parse(fixed) as Record<string, Object>;
        if (option['method']) request.method = String(option['method']).toUpperCase();
        if (option['body']) request.body = String(option['body']);
        if (option['headers']) request.headers = option['headers'] as Record<string, string>;
      } catch (e2) {
        // 正则提取关键字段
        const methodMatch = optionText.match(/"method"\s*:\s*"([^"]+)"/);
        if (methodMatch) request.method = methodMatch[1].toUpperCase();
        const bodyMatch = optionText.match(/"body"\s*:\s*"([^"]*)"/);
        if (bodyMatch) request.body = bodyMatch[1];
        console.warn('解析搜索地址选项失败，按普通地址继续:', this.formatError(e2));
      }
    }

    return request;
  }

  private parseHeader(headerStr: string): Record<string, string> {
    const headers: Record<string, string> = {};
    if (!headerStr) return headers;

    try {
      const parsed = JSON.parse(headerStr);
      if (typeof parsed === 'object') {
        return parsed as Record<string, string>;
      }
    } catch (e) {
      const lines = headerStr.split('\n');
      for (const line of lines) {
        const colonIndex = line.indexOf(':');
        if (colonIndex > 0) {
          const key = line.substring(0, colonIndex).trim();
          const value = line.substring(colonIndex + 1).trim();
          headers[key] = value;
        }
      }
    }

    return headers;
  }

  private parseSearchResult(html: string, source: BookSource): SearchBook[] {
    const books: SearchBook[] = [];

    try {
      const jsonData = this.parseJsonBody(html);
      if (jsonData !== null) {
        const books = this.parseJsonResult(jsonData, source);
        if (books.length > 0) {
          return books;
        }
      }

      return this.parseDefaultResult(html, source);
    } catch (e) {
      console.error('解析搜索结果失败:', e);
      return books;
    }
  }

  private parseDefaultResult(html: string, source: BookSource): SearchBook[] {
    const books: SearchBook[] = [];

    try {
      const trimmed = html.trim();
      if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
        const jsonArr = JSON.parse(trimmed) as Object[];
        return this.parseBookItems(jsonArr, source, source.searchRule);
      }
    } catch (e) {
      console.warn('解析默认搜索结果跳过:', this.formatError(e));
    }

    return books;
  }

  private formatError(error: Object): string {
    if (!error) return '';
    try {
      const err = error as Record<string, Object>;
      const code = err['code'] !== undefined ? String(err['code']) : '';
      const message = err['message'] !== undefined ? String(err['message']) : String(error);
      return code ? `${message} (${code})` : message;
    } catch (e) {
      return String(error);
    }
  }

  private parseJsonResult(data: Object, source: BookSource): SearchBook[] {
    const searchRule = source.searchRule;
    let items: Object[] = [];

    if (searchRule && searchRule.bookList) {
      items = this.getJsonArray(data, searchRule.bookList);
    }

    if (items.length === 0) {
      items = this.findBookArray(data);
    }

    return this.parseBookItems(items, source, searchRule);
  }

  private parseBookItems(items: Object[], source: BookSource, searchRule: SearchRule): SearchBook[] {
    const books: SearchBook[] = [];

    try {
      for (const rawItem of items) {
        if (!rawItem || typeof rawItem !== 'object') {
          continue;
        }

        const item = rawItem as Record<string, Object>;
        const book = new SearchBook();
        book.name = this.getRuleOrKeys(item, searchRule.name, ['name', 'bookName', 'title', 'book_name']);
        book.author = this.getRuleOrKeys(item, searchRule.author, ['author', 'bookAuthor', 'writer', 'authorName', 'author_name']);
        book.coverUrl = this.getRuleOrKeys(item, searchRule.coverUrl, ['coverUrl', 'cover', 'cover_url', 'img', 'image', 'pic']);
        book.intro = this.getRuleOrKeys(item, searchRule.intro, ['intro', 'description', 'summary', 'desc']);
        book.kind = this.getRuleOrKeys(item, searchRule.kind, ['kind', 'category', 'category_name', 'type', 'className']);
        book.latestChapterTitle = this.getRuleOrKeys(item, searchRule.lastChapter, ['latestChapter', 'lastChapter', 'lastChapterName', 'latest']);
        book.bookUrl = this.getRuleOrKeys(item, searchRule.bookUrl, ['bookUrl', 'url', 'link', 'href']);
        book.wordCount = this.getRuleOrKeys(item, searchRule.wordCount, ['wordCount', 'words', 'all_words']);
        book.origin = source.bookSourceUrl;
        book.originName = source.bookSourceName;
        book.tocUrl = '';

        if (book.name) {
          if (!book.bookUrl) {
            // 尝试从 item 的 id 字段构造 URL
            const idValue = this.getRuleOrKeys(item, '', ['id', 'bookId', 'Id', 'bid', 'novelId']);
            if (idValue) {
              book.bookUrl = `${source.bookSourceUrl}book/${idValue}`;
            }
          }
          if (book.bookUrl) {
            book.bookUrl = this.resolveUrl(book.bookUrl, source.bookSourceUrl);
            // 清理 search 参数
            book.bookUrl = book.bookUrl.replace(/[?&]isSearch=\d+/g, '')
              .replace(/[?&]search=\d+/g, '')
              .replace(/\?$/g, '');
            if (!book.tocUrl) {
              book.tocUrl = book.bookUrl;
            }
            if (books.length === 0) {
              console.log('[Search] 第一条结果:', 'name:', book.name, 'bookUrl:', book.bookUrl, 'tocUrl:', book.tocUrl);
            }
            books.push(book);
          }
        }
      }
    } catch (e) {
      console.error('解析规则搜索结果失败:', e);
    }

    return books;
  }

  private parseJsonBody(body: string): Object | null {
    try {
      return JSON.parse(body) as Object;
    } catch (e) {
    }

    const arrayMatch = body.match(/\[[\s\S]*\]/);
    if (arrayMatch) {
      try {
        return JSON.parse(arrayMatch[0]) as Object;
      } catch (e) {
      }
    }

    return null;
  }

  private getJsonArray(root: Object, rule: string): Object[] {
    const rules = this.splitAlternativeRules(rule);
    for (const itemRule of rules) {
      const value = this.getByPath(root, this.stripRuleProcessor(itemRule));
      if (Array.isArray(value)) {
        return value as Object[];
      }
      if (value && typeof value === 'object') {
        return [value];
      }
    }

    return [];
  }

  private findBookArray(root: Object): Object[] {
    if (Array.isArray(root)) {
      return root as Object[];
    }

    if (!root || typeof root !== 'object') {
      return [];
    }

    const obj = root as Record<string, Object>;
    const preferredKeys = ['data', 'list', 'books', 'bookList', 'items', 'result', 'results', 'rows', 'records'];
    for (const key of preferredKeys) {
      const value = obj[key];
      if (Array.isArray(value)) {
        return value as Object[];
      }
      if (value && typeof value === 'object') {
        const nested = this.findBookArray(value);
        if (nested.length > 0) {
          return nested;
        }
      }
    }

    for (const key in obj) {
      const nested = this.findBookArray(obj[key]);
      if (nested.length > 0) {
        return nested;
      }
    }

    return [];
  }

  private getRuleOrKeys(item: Record<string, Object>, rule: string, keys: string[]): string {
    const ruleValue = this.getJsonValue(item, rule);
    if (ruleValue) {
      return ruleValue;
    }

    for (const key of keys) {
      const value = item[key];
      if (value !== undefined && value !== null) {
        return String(value);
      }
    }

    return '';
  }

  private getJsonValue(item: Record<string, Object>, rule: string): string {
    if (!rule) return '';

    // 去掉开头的 <js>...</js> 部分，提取其中的变量存储操作
    let jsResult: string = '';
    const jsMatch = rule.match(/^<js>([\s\S]*?)<\/js>/);
    if (jsMatch) {
      rule = rule.substring(jsMatch[0].length);
      // 提取 java.put('key', value) 操作中的 key
      const putMatch = jsMatch[1].match(/java\.put\s*\(\s*['"]([^'"]+)['"]\s*,\s*([^)]+)\)/);
      if (putMatch) {
        const putKey = putMatch[1];
        const putExpr = putMatch[2].trim();
        // 计算表达式中的 {{...}} 值
        const resolvedExpr = this.resolveTemplateExpr(putExpr, item);
        // 尝试计算数学表达式
        if (resolvedExpr) {
          const numResult = this.evalMathExpr(resolvedExpr);
          jsResult = numResult !== undefined ? String(numResult) : resolvedExpr;
          // 将计算结果存入 item 以便后续 {{result}} 可以引用
          (item as Record<string, Object>)['__jsResult'] = jsResult;
        }
      }
    }

    if (rule.includes('{{') && rule.includes('}}')) {
      return this.applyTemplate(rule, item);
    }

    const value = this.getByPath(item, this.stripRuleProcessor(rule));
    return value === undefined || value === null ? '' : String(value);
  }

  private resolveTemplateExpr(expr: string, item: Record<string, Object>): string {
    // 替换 {{$.Id}} 等模板变量
    const matches = expr.match(/\{\{[^}]+\}\}/g) || [];
    let result = expr;
    for (const match of matches) {
      const rule = match.substring(2, match.length - 2);
      const value = this.getByPath(item, this.stripRuleProcessor(rule));
      result = result.replace(match, value === undefined || value === null ? '0' : String(value));
    }
    return result;
  }

  private evalMathExpr(expr: string): number | undefined {
    try {
      // 只支持简单表达式: Math.floor(x/y)+z
      const floorMatch = expr.match(/Math\.floor\s*\(\s*(\d+)\s*\/\s*(\d+)\s*\)/);
      if (floorMatch) {
        const dividend = parseInt(floorMatch[1]);
        const divisor = parseInt(floorMatch[2]);
        let result = Math.floor(dividend / divisor);
        // 检查是否有后续的 +offset
        const addMatch = expr.substring(floorMatch[0].length).match(/\+\s*(\d+)/);
        if (addMatch) {
          result += parseInt(addMatch[1]);
        }
        return result;
      }
      return undefined;
    } catch (e) {
      return undefined;
    }
  }

  private applyTemplate(template: string, item: Record<string, Object>): string {
    let result = template;
    const matches = template.match(/\{\{[^}]+\}\}/g) || [];
    for (const match of matches) {
      const rule = match.substring(2, match.length - 2);
      let value: string;
      if (rule === 'result' || rule === 'jsResult') {
        value = String(item['__jsResult'] || '');
      } else {
        const pathValue = this.getByPath(item, this.stripRuleProcessor(rule));
        value = pathValue === undefined || pathValue === null ? '' : String(pathValue);
      }
      result = result.replace(match, value);
    }
    return result;
  }

  private getByPath(root: Object, rule: string): Object | string | number | boolean | null | undefined {
    if (!rule) return undefined;

    let path = rule.trim();
    if (path.startsWith('<js>')) {
      const endIndex = path.indexOf('</js>');
      if (endIndex >= 0) {
        path = path.substring(endIndex + 5).trim();
      }
    }
    if (path.startsWith('$..')) {
      return this.findDeepValue(root, path.substring(3));
    }
    if (path.startsWith('@.')) {
      path = path.substring(2);
    } else if (path.startsWith('$.')) {
      path = path.substring(2);
    } else if (path.startsWith('$')) {
      path = path.substring(1);
    }

    if (path.startsWith('.')) {
      path = path.substring(1);
    }

    if (!path) {
      return root;
    }

    const parts = path.split('.');
    let current: Object | string | number | boolean | null | undefined = root;

    for (const rawPart of parts) {
      if (current === undefined || current === null) {
        return undefined;
      }

      let part = rawPart;
      let arrayAll = false;
      let arrayIndex = -1;

      if (part.endsWith('[*]')) {
        arrayAll = true;
        part = part.substring(0, part.length - 3);
      } else if (part.includes('[') && part.endsWith(']')) {
        const bracketIndex = part.indexOf('[');
        const indexText = part.substring(bracketIndex + 1, part.length - 1);
        arrayIndex = parseInt(indexText);
        part = part.substring(0, bracketIndex);
      }

      if (part) {
        current = (current as Record<string, Object>)[part];
      }

      if (arrayAll) {
        return current;
      }

      if (arrayIndex >= 0) {
        current = Array.isArray(current) ? (current as Object[])[arrayIndex] : undefined;
      }
    }

    return current;
  }

  private findDeepValue(root: Object | string | number | boolean | null | undefined, path: string): Object | string | number | boolean | null | undefined {
    if (root === undefined || root === null || !path) return undefined;

    if (typeof root === 'object') {
      const direct = this.getByPath(root as Object, path);
      if (direct !== undefined) {
        return direct;
      }
    }

    if (Array.isArray(root)) {
      for (const item of root as Object[]) {
        const value = this.findDeepValue(item, path);
        if (value !== undefined) {
          return value;
        }
      }
      return undefined;
    }

    if (typeof root === 'object') {
      const obj = root as Record<string, Object>;
      for (const key in obj) {
        const value = this.findDeepValue(obj[key], path);
        if (value !== undefined) {
          return value;
        }
      }
    }

    return undefined;
  }

  private splitAlternativeRules(rule: string): string[] {
    if (!rule) return [];

    const parts: string[] = [];
    for (const andPart of rule.split('&&')) {
      for (const orPart of andPart.split('||')) {
        const trimmed = orPart.trim();
        if (trimmed) {
          if (trimmed.startsWith('<js>')) {
            const endIndex = trimmed.indexOf('</js>');
            if (endIndex >= 0) {
              const afterJs = trimmed.substring(endIndex + 5).trim();
              if (afterJs) parts.push(afterJs);
            }
          } else {
            parts.push(trimmed);
          }
        }
      }
    }
    return parts;
  }

  private stripRuleProcessor(rule: string): string {
    const processorIndex = rule.indexOf('##');
    return processorIndex >= 0 ? rule.substring(0, processorIndex) : rule;
  }

  private cleanBaseUrl(baseUrl: string): string {
    const commentIndex = baseUrl.indexOf('##');
    return commentIndex >= 0 ? baseUrl.substring(0, commentIndex) : baseUrl;
  }

  private resolveUrl(url: string, baseUrl: string): string {
    baseUrl = this.cleanBaseUrl(baseUrl);

    if (!url || url.startsWith('http')) {
      return url;
    }

    if (url.startsWith('//')) {
      return `https:${url}`;
    }

    if (url.startsWith('/')) {
      const match = baseUrl.match(/^(https?:\/\/[^/]+)/);
      return match ? `${match[1]}${url}` : `${baseUrl}${url}`;
    }

    const cleanBase = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    return `${cleanBase}/${url}`;
  }

  cancelSearch() {
    this.searchId = Date.now();
    this.isSearching = false;
  }

  isSearchInProgress(): boolean {
    return this.isSearching;
  }

  getSearchResults(): SearchBook[] {
    return this.searchBooks;
  }
}

export const searchService = SearchService.getInstance();
