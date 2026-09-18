import { util } from '@kit.ArkTS';
import { webview } from '@kit.ArkWeb';
import { Book, BookChapter, BookSource } from '../../model/data/Book';
import { AppDatabase } from '../../model/data/AppDatabase';
import { CookieStore } from '../http/CookieStore';
import { HttpClient, HttpResponse } from '../http/HttpClient';
import { AnalyzeUrl } from '../rule/AnalyzeUrl';
import { AnalyzeRule } from '../rule/AnalyzeRule';
import { RuleContext } from '../rule/RuleContext';
import { SourceRuntimeStage } from './BookSourceRuntimeRouter';
import { BookSourceLoginCrypto } from './BookSourceLoginCrypto';
import { BookSourceExecutionJournal, BookSourceHostActionKind } from './BookSourceExecutionJournal';
import { BookSourceDebugContext } from './BookSourceDebugModels';

export class StageWebRuntimeRequest {
  source: BookSource = new BookSource();
  book: Book | null = null;
  chapter: BookChapter | null = null;
  code: string = '';
  content: string = '';
  contextContent: string = '';
  baseUrl: string = '';
  variables: Record<string, string> = {};
  readerActionMode: boolean = false;
  networkTimeoutMs: number = 20000;
  maxResponseBytes: number = 8 * 1024 * 1024;
  maxTotalResponseBytes: number = 16 * 1024 * 1024;
  maxInputBytes: number = 20 * 1024 * 1024;
  maxRequestCount: number = 12;
  stage: string = SourceRuntimeStage.URL;
  ownerId: string = '';
  debugContext: BookSourceDebugContext | null = null;

  applyStageBudget(stage: string): void {
    this.stage = stage || SourceRuntimeStage.URL;
    if (this.stage === SourceRuntimeStage.SEARCH || this.stage === SourceRuntimeStage.EXPLORE) {
      this.maxResponseBytes = 2 * 1024 * 1024;
      this.maxTotalResponseBytes = 4 * 1024 * 1024;
      this.maxInputBytes = 8 * 1024 * 1024;
      this.maxRequestCount = 6;
    } else if (this.stage === SourceRuntimeStage.BOOK_INFO) {
      this.maxResponseBytes = 4 * 1024 * 1024;
      this.maxTotalResponseBytes = 6 * 1024 * 1024;
      this.maxInputBytes = 12 * 1024 * 1024;
      this.maxRequestCount = 8;
    } else if (this.stage === SourceRuntimeStage.TOC) {
      this.maxResponseBytes = 4 * 1024 * 1024;
      this.maxTotalResponseBytes = 8 * 1024 * 1024;
      this.maxInputBytes = 16 * 1024 * 1024;
      this.maxRequestCount = 8;
    } else if (this.stage === SourceRuntimeStage.CONTENT ||
      this.stage === SourceRuntimeStage.READER_ACTION) {
      this.maxResponseBytes = 6 * 1024 * 1024;
      this.maxTotalResponseBytes = 10 * 1024 * 1024;
      this.maxInputBytes = 20 * 1024 * 1024;
      this.maxRequestCount = 8;
    } else {
      this.maxResponseBytes = 2 * 1024 * 1024;
      this.maxTotalResponseBytes = 4 * 1024 * 1024;
      this.maxInputBytes = 8 * 1024 * 1024;
      this.maxRequestCount = 4;
    }
  }
}

export class StageWebRuntimeResult {
  value: string = '';
  variable: string = '';
  bookVariable: string = '';
  bookType: string = '';
  chapterImgUrl: string = '';
  bookDurChapterIndex: string = '';
  bookImageStyle: string = '';
  requestedUrl: string = '';
  requestedHtml: string = '';
  toastMessage: string = '';
  errorMessage: string = '';
  // 'true' when the script called java.refreshExplore() / source.refreshExplore().
  refreshExploreRequested: string = '';
}

class StageWebRuntimeStep extends StageWebRuntimeResult {
  pendingAjax: string = '';
  pendingStringRules: string = '[]';
  inputFallbackUsed: boolean = false;
  pendingHeaders: string = '{}';
  pendingCookie: string = '';
  pendingCrypto: string = '';
  loginHeader: string = '';
  cookieOperations: string = '[]';
  cacheState: string = '{}';
  javaState: string = '{}';
  sourceState: string = '{}';
  logs: string = '[]';
}

class StageWebRuntimeCookieOperation {
  operation: string = '';
  url: string = '';
  value: string = '';
  name: string = '';
}

class StageWebRuntimeTask {
  request: StageWebRuntimeRequest = new StageWebRuntimeRequest();
  estimatedBytes: number = 0;
  resolve: ((value: StageWebRuntimeResult) => void) | null = null;
  reject: ((reason: Error) => void) | null = null;
}

/**
 * Shared ArkWeb host for complex non-login source scripts. Calls are serialized and every
 * network/cookie side effect is replayed through the native bridge before a result is accepted.
 */
export class BookSourceStageWebRuntime {
  private static readonly MAX_QUEUED_TASKS: number = 16;
  private static readonly MAX_QUEUED_BYTES: number = 24 * 1024 * 1024;
  private static readonly MAX_CACHE_SOURCES: number = 24;
  private static readonly MAX_CACHE_ENTRIES_PER_SOURCE: number = 128;
  private static readonly MAX_CACHE_BYTES_PER_SOURCE: number = 512 * 1024;
  private static readonly MAX_CACHE_BYTES_TOTAL: number = 4 * 1024 * 1024;
  // ArkWeb keeps native compiler/renderer allocations outside the ArkTS heap. Rebuilding the
  // hidden host frequently prevents a sequence of large user-supplied libraries from growing
  // those allocations until HarmonyOS reports a foreground THREAD_BLOCK freeze.
  private static readonly RECYCLE_TASK_INTERVAL: number = 3;
  // A wait that stays unsuccessful past this point is treated as a stuck host (missing
  // lifecycle callback or an unfinished reset) instead of a normal attach race.
  private static readonly RECOVERY_GRACE_MS: number = 1500;
  private static readonly RECOVERY_INTERVAL_MS: number = 3000;
  private static readonly RECOVERY_REBUILD_WAIT_MS: number = 6000;
  private static readonly PROBE_TIMEOUT_MS: number = 2500;
  private static readonly PROBE_NONE: number = 0;
  private static readonly PROBE_ADOPTED: number = 1;
  private static readonly PROBE_DEAD: number = 2;
  private static instance: BookSourceStageWebRuntime | null = null;
  private controller: webview.WebviewController | null = null;
  private controllers: webview.WebviewController[] = [];
  private readyControllers: Set<webview.WebviewController> = new Set<webview.WebviewController>();
  private ready: boolean = false;
  private tasks: StageWebRuntimeTask[] = [];
  private queuedBytes: number = 0;
  private running: boolean = false;
  private activeTask: StageWebRuntimeTask | null = null;
  private activeHttpClient: HttpClient | null = null;
  private cancelledOwners: Set<string> = new Set<string>();
  private caches: Record<string, Record<string, string>> = {};
  private cacheTouchedAt: Record<string, number> = {};
  private resetHandler: (() => void) | null = null;
  private resetHandlerController: webview.WebviewController | null = null;
  private resetRequested: boolean = false;
  private completedTaskCount: number = 0;
  private lastRecoveryAttemptAt: number = 0;
  private probeBusy: boolean = false;

  static get(): BookSourceStageWebRuntime {
    if (!BookSourceStageWebRuntime.instance) {
      BookSourceStageWebRuntime.instance = new BookSourceStageWebRuntime();
    }
    return BookSourceStageWebRuntime.instance;
  }

  setResetHandler(handler: (() => void) | null,
    controller: webview.WebviewController | null = this.controller): void {
    this.resetHandler = handler;
    this.resetHandlerController = handler ? controller : null;
  }

  clearResetHandler(controller: webview.WebviewController): void {
    if (this.resetHandlerController !== controller) return;
    this.resetHandler = null;
    this.resetHandlerController = null;
  }

  attach(controller: webview.WebviewController): void {
    this.controllers = this.controllers.filter((item: webview.WebviewController): boolean => item !== controller);
    this.controllers.push(controller);
    this.controller = controller;
    this.ready = this.readyControllers.has(controller);
    this.resetRequested = false;
    this.completedTaskCount = 0;
    console.info('[StageWebRuntime] attach, ' + this.describeState());
  }

  setReady(ready: boolean, controller: webview.WebviewController | null = null): void {
    const target = controller || this.controller;
    if (!target) return;
    if (ready) this.readyControllers.add(target);
    else this.readyControllers.delete(target);
    if (this.controller === target) this.ready = ready;
    // Drain queued tasks even when the recovered controller is not `this.controller`:
    // executeTask dispatches through findReadyController(), not this field.
    if (ready) this.startNext();
  }

  async waitUntilAvailable(timeoutMs: number = 5000): Promise<boolean> {
    if (this.isAvailable()) return true;
    const startedAt = Date.now();
    let deadline = startedAt + Math.max(100, timeoutMs);
    while (Date.now() < deadline) {
      await new Promise<void>((resolve) => setTimeout(resolve, 50));
      if (this.isAvailable()) return true;
      // Past the grace window a plain race is unlikely; recover a stuck host instead of
      // failing into the permanent "not ready" notice (see recoverAvailability).
      if (Date.now() - startedAt >= BookSourceStageWebRuntime.RECOVERY_GRACE_MS &&
        Date.now() - this.lastRecoveryAttemptAt >= BookSourceStageWebRuntime.RECOVERY_INTERVAL_MS) {
        this.lastRecoveryAttemptAt = Date.now();
        const rebuildRequested = await this.recoverAvailability();
        if (rebuildRequested) {
          deadline = Math.max(deadline, Date.now() + BookSourceStageWebRuntime.RECOVERY_REBUILD_WAIT_MS);
        }
      }
    }
    return this.isAvailable();
  }

  detach(controller: webview.WebviewController): void {
    this.controllers = this.controllers.filter((item: webview.WebviewController): boolean => item !== controller);
    this.readyControllers.delete(controller);
    console.info('[StageWebRuntime] detach, ' + this.describeState());
    if (this.controller !== controller) return;
    this.controller = this.controllers.length > 0 ? this.controllers[this.controllers.length - 1] : null;
    this.ready = !!this.controller && this.readyControllers.has(this.controller);
    if (this.ready) this.startNext();
  }

  isAvailable(): boolean {
    return this.findReadyController() !== null;
  }

  execute(request: StageWebRuntimeRequest): Promise<StageWebRuntimeResult> {
    return new Promise<StageWebRuntimeResult>((resolve, reject) => {
      if (request.ownerId && this.cancelledOwners.has(request.ownerId)) {
        reject(new Error('书源脚本任务已取消'));
        return;
      }
      const estimatedBytes = this.estimateRequestBytes(request);
      const inputLimit = Math.max(256 * 1024,
        Math.min(request.maxInputBytes || 20 * 1024 * 1024, 24 * 1024 * 1024));
      if (estimatedBytes > inputLimit) {
        reject(new Error(`书源脚本输入过大(${Math.ceil(estimatedBytes / 1024)} KiB)`));
        return;
      }
      if (this.tasks.length >= BookSourceStageWebRuntime.MAX_QUEUED_TASKS ||
        this.queuedBytes + estimatedBytes > BookSourceStageWebRuntime.MAX_QUEUED_BYTES) {
        reject(new Error('书源脚本队列繁忙，请稍后重试'));
        return;
      }
      const task = new StageWebRuntimeTask();
      task.request = request;
      task.estimatedBytes = estimatedBytes;
      task.resolve = resolve;
      task.reject = reject;
      this.tasks.push(task);
      this.queuedBytes += estimatedBytes;
      this.startNext();
    });
  }

  cancelOwner(ownerId: string): void {
    if (!ownerId) return;
    this.cancelledOwners.add(ownerId);
    const remaining: StageWebRuntimeTask[] = [];
    for (const task of this.tasks) {
      if (task.request.ownerId === ownerId) {
        this.queuedBytes = Math.max(0, this.queuedBytes - task.estimatedBytes);
        if (task.reject) task.reject(new Error('书源脚本任务已取消'));
      } else {
        remaining.push(task);
      }
    }
    this.tasks = remaining;
    if (this.activeTask?.request.ownerId === ownerId && this.activeHttpClient) {
      this.activeHttpClient.cancelAll();
    }
  }

  clearOwner(ownerId: string): void {
    if (ownerId) this.cancelledOwners.delete(ownerId);
  }

  private scheduleIdleRecovery(): void {
    const now = Date.now();
    if (now - this.lastRecoveryAttemptAt < BookSourceStageWebRuntime.RECOVERY_INTERVAL_MS) return;
    this.lastRecoveryAttemptAt = now;
    this.recoverAvailability().catch((): void => {});
  }

  /**
   * A hidden ArkWeb host can become permanently unavailable in two ways that no lifecycle
   * callback ever fixes by itself: a rebuild whose onControllerAttached never fires leaves no
   * controller and a reset request nothing can complete, and a suspended renderer never
   * reaches onPageEnd. Probe attached controllers and force the host page to rebuild its Web
   * node. Returns true when a rebuild was requested and the caller should extend its wait.
   */
  private async recoverAvailability(): Promise<boolean> {
    if (this.isAvailable()) return false;
    const probeOutcome = await this.probeNotReadyControllers();
    if (probeOutcome === BookSourceStageWebRuntime.PROBE_ADOPTED) return false;
    const stuckReset = this.resetRequested;
    const deadRenderer = probeOutcome === BookSourceStageWebRuntime.PROBE_DEAD;
    // A host that is merely still attaching (cold start: no controller, no pending reset) must
    // not be remounted here, that would only prolong startup.
    if (stuckReset || deadRenderer) {
      this.forceHostRebuild();
      return true;
    }
    return false;
  }

  /** Outcome of probing attached-but-not-ready controllers: none attached, adopted, or dead. */
  private async probeNotReadyControllers(): Promise<number> {
    if (this.probeBusy) return BookSourceStageWebRuntime.PROBE_NONE;
    const candidates = this.controllers.filter((item: webview.WebviewController): boolean =>
      !this.readyControllers.has(item));
    if (candidates.length === 0) return BookSourceStageWebRuntime.PROBE_NONE;
    this.probeBusy = true;
    try {
      for (const controller of candidates) {
        const alive = await this.probeController(controller);
        if (this.controllers.indexOf(controller) < 0) continue; // detached while probing
        if (alive) {
          // Readiness only means "the JS context answers runJavaScript"; a resolved probe is
          // sufficient even when onPageEnd was missed.
          console.info('[StageWebRuntime] controller recovered by probe, ' + this.describeState());
          this.setReady(true, controller);
          return BookSourceStageWebRuntime.PROBE_ADOPTED;
        }
      }
      return BookSourceStageWebRuntime.PROBE_DEAD;
    } finally {
      this.probeBusy = false;
    }
  }

  private probeController(controller: webview.WebviewController): Promise<boolean> {
    return new Promise<boolean>((resolve) => {
      let settled = false;
      let timer = -1;
      const finish = (value: boolean): void => {
        if (settled) return;
        settled = true;
        if (timer >= 0) clearTimeout(timer);
        resolve(value);
      };
      timer = setTimeout((): void => finish(false), BookSourceStageWebRuntime.PROBE_TIMEOUT_MS);
      controller.runJavaScript('1')
        .then((): void => finish(true))
        .catch((): void => finish(false));
    });
  }

  /** Re-invoke the host page's reset handler. Each host guards re-entry itself. */
  private forceHostRebuild(): void {
    const handler = this.resetHandler;
    if (!handler) {
      console.warn('[StageWebRuntime] recovery impossible, no reset handler, ' + this.describeState());
      return;
    }
    this.resetRequested = true;
    console.warn('[StageWebRuntime] forced host rebuild, ' + this.describeState());
    handler();
  }

  private describeState(): string {
    return `hosts=${this.controllers.length} ready=${this.readyControllers.size}` +
      ` reset=${this.resetRequested} running=${this.running}` +
      ` queued=${this.tasks.length} done=${this.completedTaskCount}`;
  }

  private startNext(): void {
    if (this.running) return;
    if (!this.findReadyController()) {
      // Queued tasks with no usable controller would otherwise wait forever: nothing calls
      // setReady() once lifecycle callbacks have been missed. Nudge the recovery path.
      if (this.tasks.length > 0) this.scheduleIdleRecovery();
      return;
    }
    if (this.tasks.length === 0) return;
    const task = this.tasks.shift();
    if (!task) return;
    this.queuedBytes = Math.max(0, this.queuedBytes - task.estimatedBytes);
    this.running = true;
    this.activeTask = task;
    this.executeTask(task.request)
      .then((value: StageWebRuntimeResult): void => {
        if (task.resolve) task.resolve(value);
      })
      .catch((error: Error): void => {
        if (task.reject) task.reject(error);
      })
      .finally((): void => {
        this.activeTask = null;
        this.activeHttpClient = null;
        this.running = false;
        this.completedTaskCount++;
        if (this.maybeRecycleController()) return;
        this.startNext();
      });
  }

  private async executeTask(request: StageWebRuntimeRequest): Promise<StageWebRuntimeResult> {
    this.ensureNotCancelled(request);
    // Coordinators may hold a source snapshot while the login/editor page saves a new token.
    // Refresh missing runtime fields before executing so a stale empty snapshot cannot issue an
    // unauthenticated request or overwrite the newly saved state when the stage completes.
    const persistedAtStart = await AppDatabase.getInstance().getBookSource(request.source.bookSourceUrl);
    if (persistedAtStart) {
      if (!request.source.variable && persistedAtStart.variable) request.source.variable = persistedAtStart.variable;
      if (!request.source.loginHeader && persistedAtStart.loginHeader) {
        request.source.loginHeader = persistedAtStart.loginHeader;
      }
      if ((!request.source.loginInfo || request.source.loginInfo === '{}') && persistedAtStart.loginInfo) {
        request.source.loginInfo = persistedAtStart.loginInfo;
      }
    }
    const sourceKey = request.source.bookSourceUrl || request.source.bookSourceName || 'source';
    const journal = new BookSourceExecutionJournal();
    const responses: Record<string, string> = journal.responses;
    // java.getString()/getStringList() accept the full Legado rule syntax (CSS, @text/@html,
    // ## 替换链), which only the native rule engine implements. The ArkWeb bridge records every
    // distinct rule here and replays the script once the values are available, exactly like the
    // java.ajax/cookie/crypto host actions.
    const stringResults: Record<string, string> = {};
    const cookies: Record<string, string> = {};
    let cacheState = this.caches[sourceKey] || {};
    const fixedNow = Date.now();
    const randomSeed = Math.max(1, Math.floor(Math.random() * 0x7fffffff));
    let requestCount = 0;
    let totalResponseBytes = 0;
    let lastResponseBody = '';
    for (let stepIndex = 0; stepIndex < 20; stepIndex++) {
      this.ensureNotCancelled(request);
      const script = this.buildScript(request, responses, stringResults, cookies, cacheState,
        fixedNow, randomSeed, journal.responseHeaders);
      const raw = await this.runJavaScript(script);
      this.ensureNotCancelled(request);
      const step = this.parseStep(raw);
      if (request.debugContext && step.logs) {
        try {
          const logs = JSON.parse(step.logs) as Object[];
          for (const item of logs || []) {
            const record = item as Record<string, Object>;
            request.debugContext.addLog(String(record['level'] || 'info'), String(record['message'] || ''));
          }
        } catch (_) {
        }
      }
      request.source.variable = step.variable;
      request.source.loginHeader = step.loginHeader;
      // java.ajax() is synchronous from the source script's point of view, while this bridge fulfils it by
      // replaying the script after each native request. Source/java mutations made before that AJAX therefore
      // belong to the next replay and to the request currently being issued. Carry them in the task-local source
      // snapshot immediately, but do not persist them to the database until the script reaches a completed pass.
      //
      // This is also required by sources that discover a per-account API domain, store it with source.put(), and
      // then call java.ajax() on that domain. AnalyzeUrl scopes login headers to trusted source-state URLs; without
      // this task-local merge, the freshly selected domain is not trusted until after the request has already
      // returned 401. Cache state remains deliberately deferred below because caching a speculative empty AJAX
      // result can poison later passes.
      request.source.loginInfo = this.mergeRuntimeState(request.source.loginInfo || '',
        step.javaState, step.sourceState);
      if (request.book) {
        request.book.variable = step.bookVariable;
        const bookType = Number(step.bookType);
        if (step.bookType && Number.isFinite(bookType)) request.book.type = bookType;
        const durChapterIndex = Number(step.bookDurChapterIndex);
        if (step.bookDurChapterIndex && Number.isFinite(durChapterIndex) && durChapterIndex >= 0) {
          request.book.durChapterIndex = Math.round(durChapterIndex);
        }
        if (step.bookImageStyle) request.book.setImageStyle(step.bookImageStyle);
      }
      if (request.chapter && step.chapterImgUrl) {
        request.chapter.variable = this.setVariableValue(request.chapter.variable, 'imgUrl', step.chapterImgUrl);
      }
      let nextCacheState: Record<string, string> = {};
      try {
        nextCacheState = JSON.parse(step.cacheState || '{}') as Record<string, string>;
      } catch (_) {
        nextCacheState = {};
      }
      this.applyCookieOperations(step.cookieOperations, journal);
      if (step.pendingCookie) {
        cookies[step.pendingCookie] = CookieStore.getCookie(step.pendingCookie);
        continue;
      }
      if (step.pendingCrypto) {
        const responseKey = `crypto:${step.pendingCrypto}`;
        if (journal.markRequestStarted(`${BookSourceHostActionKind.CRYPTO_REQUEST}\n${step.pendingCrypto}`)) {
          journal.recordResponse(responseKey, await BookSourceLoginCrypto.execute(step.pendingCrypto));
        }
        continue;
      }
      if (step.pendingAjax) {
        requestCount++;
        const requestLimit = Math.max(1, Math.min(request.maxRequestCount || 12, 12));
        if (requestCount > requestLimit) throw new Error('书源脚本网络请求次数过多');
        journal.markRequestStarted(`${BookSourceHostActionKind.HTTP_REQUEST}\n${step.pendingAjax}`);
        const response = await this.fetch(request, step.pendingAjax, step.pendingHeaders);
        this.ensureNotCancelled(request);
        if (!response.success && response.statusCode === 0) {
          throw new Error(response.error || '书源脚本网络请求失败');
        }
        // A UTF-8 BOM is transport metadata, not part of the JavaScript-facing response body.
        // Some imported source helpers feed java.ajax() directly into JSON.parse(), where ArkWeb
        // does not consistently discard U+FEFF. Normalize it once at the native bridge boundary.
        const responseBody = (response.body || '').replace(/^\uFEFF/, '');
        lastResponseBody = responseBody;
        // A content rule that hides its failures behind a fallback selector would otherwise leave no
        // trace of *why* nothing was extracted. Record the server's own message in the debug log.
        if (request.debugContext && request.stage === SourceRuntimeStage.CONTENT) {
          const apiMessage = this.responseMessage(responseBody);
          if (apiMessage) request.debugContext.addLog('warn', `接口返回：${apiMessage}`);
        }
        // ArkTS/ArkWeb exchange response bodies as UTF-16 strings. Count their in-memory
        // footprint instead of only character count so the cumulative guard remains useful.
        totalResponseBytes += responseBody.length * 2;
        const responseLimit = Math.max(64 * 1024,
          Math.min(request.maxResponseBytes || 8 * 1024 * 1024, 8 * 1024 * 1024));
        const totalLimit = Math.max(responseLimit,
          Math.min(request.maxTotalResponseBytes || 16 * 1024 * 1024, 16 * 1024 * 1024));
        if (totalResponseBytes > totalLimit) {
          throw new Error('书源脚本累计响应过大');
        }
        journal.recordResponse(step.pendingAjax, responseBody);
        journal.recordResponseHeaders(step.pendingAjax, response.headers);
        this.captureResponseCookies(cookies, step.pendingAjax, response.url || '', response.headers);
        continue;
      }
      if (step.pendingStringRules && step.pendingStringRules !== '[]') {
        this.resolvePendingStringRules(request, step.pendingStringRules, stringResults);
        continue;
      }
      if (step.errorMessage) throw new Error(this.smallApiError(lastResponseBody) || step.errorMessage);
      // The bridge evaluates `text(evaluated) || text(globalThis.result)`, so an empty script
      // result silently becomes the rule's *input* content. For a content rule that is the chapter
      // page itself: the reader then shows the page navigation instead of the article, and a failed
      // java.ajax() looks like "the script fetched the wrong page". Surface the real reason instead
      // of returning the input page, and always leave a warning for the other stages.
      if (step.inputFallbackUsed) {
        const fallbackReason = this.responseMessage(lastResponseBody) ||
          '脚本未返回内容，已放弃把输入内容当作规则结果';
        if (request.debugContext) request.debugContext.addLog('warn', fallbackReason);
        if (request.stage === SourceRuntimeStage.CONTENT) throw new Error(fallbackReason);
      }
      // A pass that requests async work is speculative: java.ajax()/cookie/crypto return a
      // placeholder and the complete script is evaluated again after the result arrives. Commit
      // script cache/runtime state only after a pass finishes, otherwise a placeholder can poison
      // the next evaluation (for example, caching an empty paragraph-comment summary).
      cacheState = this.storeCache(sourceKey, nextCacheState);
      const persistedBeforeSave = await AppDatabase.getInstance().getBookSource(request.source.bookSourceUrl);
      if (persistedBeforeSave) {
        // Empty state from a non-login task is never an explicit logout. Preserve a token/header
        // that another page saved while this asynchronous task was running.
        request.source.variable = step.variable || persistedBeforeSave.variable || '';
        request.source.loginHeader = request.source.loginHeader || persistedBeforeSave.loginHeader || '';
        request.source.loginInfo = this.mergeRuntimeState(
          persistedBeforeSave.loginInfo || request.source.loginInfo || '',
          step.javaState, step.sourceState);
      }
      await AppDatabase.getInstance().updateBookSourceLoginRuntime(request.source.bookSourceUrl,
        request.source.variable || '', request.source.loginHeader || '', request.source.loginInfo || '');
      return step;
    }
    throw new Error('书源脚本执行步骤过多');
  }

  private smallApiError(body: string): string {
    const value = (body || '').trim();
    if (!value || value.length > 4096 || !value.startsWith('{')) return '';
    try {
      const root = JSON.parse(value) as Record<string, Object>;
      if (!root || typeof root !== 'object' || Array.isArray(root)) return '';
      const success = root['success'];
      const code = String(root['code'] === undefined ? root['status'] || '' : root['code']);
      if (success === true || code === '0' || code === '200') return '';
      for (const key of ['error', 'message', 'msg', 'detail']) {
        const message = String(root[key] || '').trim();
        if (message && !/^(?:ok|success|成功)$/i.test(message)) return message;
      }
      return '';
    } catch (_) {
      return '';
    }
  }

  /**
   * Evaluate `java.getString()` / `java.getStringList()` rules requested by the ArkWeb bridge.
   * The bridge collects the distinct rules of a pass and returns a placeholder; the native rule
   * engine then produces the values and the script is replayed. Results are keyed by shape+rule so
   * the same rule/text and rule/list pair resolve once per stage execution.
   */
  private resolvePendingStringRules(request: StageWebRuntimeRequest, raw: string,
    stringResults: Record<string, string>): void {
    let items: Object[] = [];
    try {
      const parsed = JSON.parse(raw || '[]') as Object;
      if (Array.isArray(parsed)) items = parsed as Object[];
    } catch (_) {
      items = [];
    }
    if (items.length === 0) return;
    // The bridge evaluates java.getString() against S.contextContent || S.content; mirror that
    // exactly so host-resolved rules see the same document as JSON path lookups.
    const content = request.contextContent && request.contextContent !== request.content ?
      request.contextContent : request.content;
    const analyzer = new AnalyzeRule(content || '', request.baseUrl || '',
      this.buildStringRuleContext(request));
    for (const item of items) {
      if (!item || typeof item !== 'object' || Array.isArray(item)) continue;
      const record = item as Record<string, Object>;
      const rule = String(record['rule'] || '');
      if (!rule) continue;
      const asList = String(record['list']) === 'true';
      const key = `${asList ? 'L' : 'S'}:${rule}`;
      if (Object.prototype.hasOwnProperty.call(stringResults, key)) continue;
      try {
        stringResults[key] = asList ? JSON.stringify(analyzer.getStringList(rule)) :
          analyzer.getString(rule);
      } catch (_) {
        stringResults[key] = asList ? '[]' : '';
      }
    }
  }

  private buildStringRuleContext(request: StageWebRuntimeRequest): RuleContext {
    const ctx = new RuleContext();
    const source = request.source;
    ctx.put('source.bookSourceUrl', source.bookSourceUrl || '');
    ctx.put('bookSourceUrl', source.bookSourceUrl || '');
    ctx.put('source.bookSourceName', source.bookSourceName || '');
    ctx.put('bookSourceName', source.bookSourceName || '');
    ctx.put('source.jsLib', source.jsLib || '');
    ctx.put('jsLib', source.jsLib || '');
    ctx.put('source.variable', source.variable || '');
    if (request.book) {
      ctx.put('book.name', request.book.name || '');
      ctx.put('book.author', request.book.author || '');
      ctx.put('book.bookUrl', request.book.bookUrl || '');
    }
    if (request.chapter) {
      ctx.put('chapter.title', request.chapter.title || '');
      ctx.put('chapter.url', request.chapter.url || '');
      ctx.put('chapterTitle', request.chapter.title || '');
    }
    return ctx;
  }

  /**
   * Extract a server-provided failure message. Unlike smallApiError() this must not assume the
   * `code === 0` success convention: it is only called after the script already produced nothing,
   * so any message field is a better diagnostic than a generic placeholder.
   */
  private responseMessage(body: string): string {
    const value = (body || '').trim();
    if (!value || value.length > 4096 || !value.startsWith('{')) return '';
    try {
      const root = JSON.parse(value) as Record<string, Object>;
      if (!root || typeof root !== 'object' || Array.isArray(root)) return '';
      for (const key of ['error', 'message', 'msg', 'detail']) {
        const message = String(root[key] || '').trim();
        if (message && !/^(?:ok|success|成功|获取成功)$/i.test(message)) return message;
      }
    } catch (_) {
    }
    return '';
  }

  private async fetch(request: StageWebRuntimeRequest, requestUrl: string,
    runtimeHeadersRaw: string = '{}'): Promise<HttpResponse> {
    const timeout = Math.max(3000, Math.min(request.networkTimeoutMs || 20000, 30000));
    const responseLimit = Math.max(64 * 1024,
      Math.min(request.maxResponseBytes || 8 * 1024 * 1024, 8 * 1024 * 1024));
    const client = new HttpClient(timeout);
    this.activeHttpClient = client;
    try {
      let runtimeHeaders: Record<string, string> = {};
      try {
        const parsed = JSON.parse(runtimeHeadersRaw || '{}') as Record<string, Object>;
        if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
          for (const key of Object.keys(parsed)) {
            const name = String(key || '').trim();
            const value = parsed[key];
            if (name && value !== undefined && value !== null && typeof value !== 'object') {
              runtimeHeaders[name] = String(value);
            }
          }
        }
      } catch (_) {
      }
      return await new AnalyzeUrl(request.source, client, runtimeHeaders).fetch(requestUrl, responseLimit,
        request.debugContext);
    } finally {
      if (this.activeHttpClient === client) this.activeHttpClient = null;
    }
  }

  private captureResponseCookies(target: Record<string, string>, requestSpec: string,
    responseUrl: string, responseHeaders: Record<string, string>): void {
    const urls: string[] = [];
    const requestUrl = this.requestUrlFromSpec(requestSpec);
    for (const value of [requestUrl, responseUrl]) {
      const clean = (value || '').trim();
      if (!clean || !/^https?:\/\//i.test(clean) || urls.includes(clean)) continue;
      urls.push(clean);
      const origin = clean.match(/^(https?:\/\/[^/?#]+)/i);
      if (origin && origin[1] && !urls.includes(origin[1])) urls.push(origin[1]);
    }
    let setCookie = '';
    for (const key of Object.keys(responseHeaders || {})) {
      if (key.toLowerCase() === 'set-cookie') {
        setCookie = String(responseHeaders[key] || '');
        break;
      }
    }
    for (const url of urls) target[url] = setCookie || CookieStore.getCookie(url);
  }

  private requestUrlFromSpec(spec: string): string {
    const value = (spec || '').trim();
    const optionAt = value.indexOf(',{');
    return optionAt > 0 ? value.substring(0, optionAt).trim() : value;
  }

  private ensureNotCancelled(request: StageWebRuntimeRequest): void {
    if (request.ownerId && this.cancelledOwners.has(request.ownerId)) {
      throw new Error('书源脚本任务已取消');
    }
  }

  private async runJavaScript(script: string): Promise<string> {
    let controller = this.findReadyController();
    // A routed detail page can mount its hidden Web host while the Index host is still alive.
    // During onControllerAttached -> onPageBegin -> onPageEnd, `this.controller` temporarily
    // points at an unready controller although another attached controller is usable. Also, the
    // database refresh at the start of a task gives that lifecycle race a chance to happen after
    // the queue has already accepted the task. Resolve a ready attached controller at the actual
    // execution point and wait for remount/recycle recovery when none is ready.
    if (!controller) {
      const available = await this.waitUntilAvailable(5000);
      if (available) controller = this.findReadyController();
    }
    if (!controller) {
      console.warn('[StageWebRuntime] unavailable after wait, ' + this.describeState());
      throw new Error('书源脚本运行环境未就绪');
    }
    return this.runJavaScriptOnController(controller, script);
  }

  private runJavaScriptOnController(controller: webview.WebviewController, script: string): Promise<string> {
    return new Promise<string>((resolve, reject) => {
      let completed = false;
      const timer = setTimeout(() => {
        if (completed) return;
        completed = true;
        this.quarantineController(controller, '书源脚本引擎响应超时');
        reject(new Error('书源脚本引擎响应超时'));
      }, 20000);
      controller.runJavaScript(script)
        .then((value: string): void => {
          if (completed) return;
          completed = true;
          clearTimeout(timer);
          resolve(value);
        })
        .catch((error: Error): void => {
          if (completed) return;
          completed = true;
          clearTimeout(timer);
          reject(error);
        });
    });
  }

  private findReadyController(): webview.WebviewController | null {
    if (this.controller && this.readyControllers.has(this.controller)) return this.controller;
    for (let index = this.controllers.length - 1; index >= 0; index--) {
      const candidate = this.controllers[index];
      if (this.readyControllers.has(candidate)) return candidate;
    }
    return null;
  }

  /** A timed-out renderer must not receive the next queued script. Rebuild the hidden Web host first. */
  private quarantineController(controller: webview.WebviewController, reason: string): void {
    console.warn('[StageWebRuntime] quarantine: ' + reason + ', ' + this.describeState());
    this.readyControllers.delete(controller);
    this.controllers = this.controllers.filter((item: webview.WebviewController): boolean => item !== controller);
    if (this.controller === controller) {
      this.controller = this.controllers.length > 0 ? this.controllers[this.controllers.length - 1] : null;
      this.ready = !!this.controller && this.readyControllers.has(this.controller);
    }
    if (this.ready || this.resetRequested || !this.resetHandler ||
      this.resetHandlerController !== controller) return;
    this.resetRequested = true;
    console.warn('[StageWebRuntime] reset requested:', reason);
    this.resetHandler();
  }

  private maybeRecycleController(): boolean {
    if (this.completedTaskCount < BookSourceStageWebRuntime.RECYCLE_TASK_INTERVAL ||
      this.resetRequested || !this.controller || !this.resetHandler ||
      this.resetHandlerController !== this.controller) {
      return false;
    }
    const controller = this.controller;
    const handler = this.resetHandler;
    this.readyControllers.delete(controller);
    this.controllers = this.controllers.filter((item: webview.WebviewController): boolean => item !== controller);
    this.controller = this.controllers.length > 0 ? this.controllers[this.controllers.length - 1] : null;
    this.ready = !!this.controller && this.readyControllers.has(this.controller);
    this.resetRequested = true;
    this.completedTaskCount = 0;
    console.info('[StageWebRuntime] recycle requested after task budget');
    handler();
    return true;
  }

  private estimateRequestBytes(request: StageWebRuntimeRequest): number {
    let total = this.utf16Bytes(request.content);
    if (request.contextContent && request.contextContent !== request.content) {
      total += this.utf16Bytes(request.contextContent);
    }
    total += this.utf16Bytes(request.code);
    total += this.utf16Bytes(request.source.jsLib);
    total += this.utf16Bytes(request.source.header);
    total += this.utf16Bytes(request.source.loginHeader);
    total += this.utf16Bytes(request.source.loginInfo);
    total += this.utf16Bytes(request.source.variable);
    try {
      total += this.utf16Bytes(JSON.stringify(request.variables || {}));
    } catch (_) {}
    return total;
  }

  private utf16Bytes(value: string): number {
    return (value || '').length * 2;
  }

  private storeCache(sourceKey: string, rawState: Record<string, string>): Record<string, string> {
    const state: Record<string, string> = {};
    const keys = Object.keys(rawState || {});
    const selectedKeys: string[] = [];
    let bytes = 0;
    for (let i = keys.length - 1; i >= 0 &&
      selectedKeys.length < BookSourceStageWebRuntime.MAX_CACHE_ENTRIES_PER_SOURCE; i--) {
      const key = keys[i];
      const value = String(rawState[key] || '');
      const entryBytes = this.utf16Bytes(key) + this.utf16Bytes(value);
      if (entryBytes > BookSourceStageWebRuntime.MAX_CACHE_BYTES_PER_SOURCE ||
        bytes + entryBytes > BookSourceStageWebRuntime.MAX_CACHE_BYTES_PER_SOURCE) {
        continue;
      }
      selectedKeys.unshift(key);
      bytes += entryBytes;
    }
    for (const key of selectedKeys) state[key] = String(rawState[key] || '');
    this.caches[sourceKey] = state;
    this.cacheTouchedAt[sourceKey] = Date.now();
    this.pruneCaches();
    return this.caches[sourceKey] || {};
  }

  private pruneCaches(): void {
    const sourceKeys = Object.keys(this.caches);
    sourceKeys.sort((left: string, right: string): number =>
      (this.cacheTouchedAt[left] || 0) - (this.cacheTouchedAt[right] || 0));
    let totalBytes = 0;
    const sizes: Record<string, number> = {};
    for (const sourceKey of sourceKeys) {
      let sourceBytes = 0;
      const state = this.caches[sourceKey] || {};
      for (const key of Object.keys(state)) {
        sourceBytes += this.utf16Bytes(key) + this.utf16Bytes(String(state[key] || ''));
      }
      sizes[sourceKey] = sourceBytes;
      totalBytes += sourceBytes;
    }
    while (sourceKeys.length > BookSourceStageWebRuntime.MAX_CACHE_SOURCES ||
      totalBytes > BookSourceStageWebRuntime.MAX_CACHE_BYTES_TOTAL) {
      const oldest = sourceKeys.shift();
      if (!oldest) break;
      totalBytes = Math.max(0, totalBytes - (sizes[oldest] || 0));
      delete this.caches[oldest];
      delete this.cacheTouchedAt[oldest];
    }
  }

  private buildScript(request: StageWebRuntimeRequest, responses: Record<string, string>,
    stringResults: Record<string, string>, cookies: Record<string, string>,
    cacheState: Record<string, string>, fixedNow: number, randomSeed: number,
    responseHeaders: Record<string, string> = {}): string {
    const bookVariables = this.parseRecord(request.book ? request.book.variable : '');
    const loginInfo = this.parseLoginInfo(request.source.loginInfo || '');
    const javaState = this.parseRuntimeJavaState(request.source.loginInfo || '');
    const sourceState = this.parseRuntimeObjectState(request.source.loginInfo || '', 'source');
    const contextContent = request.contextContent && request.contextContent !== request.content ?
      request.contextContent : '';
    const state = JSON.stringify({
      sourceUrl: request.source.bookSourceUrl || '',
      sourceName: request.source.bookSourceName || '',
      sourceHeader: request.source.header || '',
      sourceLoginHeader: request.source.loginHeader || '',
      sourceLoginUrl: request.source.loginUrl || '',
      variable: request.source.variable || '',
      content: request.content || '',
      contextContent: contextContent,
      baseUrl: request.baseUrl || request.source.bookSourceUrl || '',
      variables: request.variables || {},
        bookVariables: bookVariables,
        bookType: request.book ? request.book.type : 0,
        bookState: request.book ? {
          bookUrl: request.book.bookUrl, tocUrl: request.book.tocUrl, origin: request.book.origin,
          originName: request.book.originName, name: request.book.name, author: request.book.author,
          kind: request.book.kind, coverUrl: request.book.coverUrl, intro: request.book.intro,
          totalChapterNum: request.book.totalChapterNum, durChapterTitle: request.book.durChapterTitle,
          durChapterIndex: request.book.durChapterIndex, durChapterPos: request.book.durChapterPos,
          order: request.book.order, originOrder: request.book.originOrder,
          imageStyle: request.book.getImageStyle()
        } : {},
        chapterTitle: request.chapter ? request.chapter.title : '',
        chapterImgUrl: request.chapter ? this.variableValue(request.chapter.variable, 'imgUrl') : '',
        chapterState: request.chapter ? {
          url: request.chapter.url, title: request.chapter.title, bookUrl: request.chapter.bookUrl,
          index: request.chapter.index, isVip: request.chapter.isVip, isPay: request.chapter.isPay,
          resourceUrl: request.chapter.resourceUrl, tag: request.chapter.tag
        } : {},
      responses: responses || {},
      responseHeaders: responseHeaders || {},
      stringResults: stringResults || {},
      cookies: cookies || {},
      cache: cacheState || {},
      fixedNow: fixedNow,
      randomSeed: randomSeed,
      loginInfo: loginInfo,
      javaState: javaState,
      sourceState: sourceState,
      readerActionMode: request.readerActionMode
    });
    const library = this.normalizeScript(request.source.jsLib || '');
    const exposeFunctions = this.functionExposeScript(library);
    const stageCode = this.normalizeScript(request.code || '');
    const code = `${library}\n${exposeFunctions}\n${stageCode}\n//# sourceURL=book-source-stage.js`;
    const stateBase64 = this.encodeBase64(state);
    const codeBase64 = this.encodeBase64(code);
    return `(function(){` +
      `function dec(v){try{return decodeURIComponent(escape(atob(v)));}catch(e){return atob(v);}}` +
      `const S=JSON.parse(dec('${stateBase64}'));let pending='',pendingHeaders='{}',pendingCookie='',pendingCrypto='',pendingStringRules=[],url='',browserHtml='',toast='',error='',logs=[],refreshExploreRequested=false;` +
      `const cookieOps=[];const sourceData=Object.assign({},S.sourceState||{});` +
      `const cacheData=Object.assign({},S.cache||{});` +
      `const infoMap=Object.create(null);` +
      `Object.defineProperty(infoMap,'get',{enumerable:false,value:function(k){return this[String(k??'')]??'';}});` +
      `Object.defineProperty(infoMap,'put',{enumerable:false,value:function(k,v){this[String(k??'')]=v;return v;}});` +
      `Object.defineProperty(infoMap,'save',{enumerable:false,value:function(){return true;}});` +
      `const javaData=Object.assign({},S.javaState||{});const loginMap=Object.assign({},S.loginInfo||{});` +
      `Object.defineProperty(loginMap,'get',{enumerable:false,value:function(k){return this[k]??'';}});` +
      `Object.defineProperty(loginMap,'put',{enumerable:false,value:function(k,v){this[k]=v;return v;}});` +
      `const bookData=Object.assign({},S.bookVariables||{});` +
      `const NativeDate=globalThis.Date;const FixedDate=function(){const a=Array.from(arguments);` +
      `if(new.target)return Reflect.construct(NativeDate,a.length?a:[S.fixedNow]);return new NativeDate(S.fixedNow).toString();};` +
      `FixedDate.now=function(){return S.fixedNow;};FixedDate.parse=NativeDate.parse;FixedDate.UTC=NativeDate.UTC;` +
      `FixedDate.prototype=NativeDate.prototype;const Date=FixedDate;let randomState=(Number(S.randomSeed)||1)>>>0;` +
      `const Math=Object.create(globalThis.Math);Math.random=function(){randomState=(randomState*1664525+1013904223)>>>0;` +
      `return randomState/4294967296;};` +
      `const previousNames=Array.isArray(globalThis.__legadoHarmonyStageExposedNames)?` +
      `globalThis.__legadoHarmonyStageExposedNames:[];for(const oldName of previousNames){` +
      `try{delete globalThis[oldName];}catch(e){globalThis[oldName]=undefined;}}` +
      `globalThis.__legadoHarmonyStageExposedNames=[];` +
      `function bytes(v){if(v instanceof Uint8Array)return Array.from(v);if(Array.isArray(v))return v;` +
      `return Array.from(new TextEncoder().encode(String(v??'')));}` +
      `function b64e(v){try{let s='';for(const x of bytes(v))s+=String.fromCharCode(Number(x)&255);return btoa(s);}catch(e){return '';}}` +
      `function b64d(v){try{const s=atob(String(v??''));const a=[];for(let i=0;i<s.length;i++)a.push(s.charCodeAt(i)&255);` +
      `return new TextDecoder().decode(new Uint8Array(a));}catch(e){return '';}}` +
      `function hexD(v){try{v=String(v??'').replace(/\\s+/g,'');const a=[];for(let i=0;i<v.length;i+=2)` +
      `a.push(parseInt(v.substring(i,i+2),16));return new TextDecoder().decode(new Uint8Array(a));}catch(e){return '';}}` +
      `function hexE(v){return bytes(v).map(function(x){return Number(x).toString(16).padStart(2,'0');}).join('');}` +
      `function cryptoOp(transformation,key,iv,method,data){const request=JSON.stringify({` +
      `transformation:String(transformation??''),key:Array.isArray(key)?key:String(key??''),` +
      `iv:Array.isArray(iv)?iv:String(iv??''),method:method,data:Array.isArray(data)?data:String(data??'')});` +
      `const responseKey='crypto:'+request;if(Object.prototype.hasOwnProperty.call(S.responses,responseKey)){` +
      `let response;try{response=JSON.parse(S.responses[responseKey]);}catch(e){throw new Error('加密桥接返回异常');}` +
      `if(!response||response.success!==true)throw new Error(response&&response.error?response.error:'加密桥接失败');` +
      `return response.value;}if(!pendingCrypto)pendingCrypto=request;return method.indexOf('Str')>=0||` +
      `method.indexOf('Base64')>=0||method.indexOf('Hex')>=0?'':[];}` +
      `let contextValue=S.contextContent||S.content;function pathValue(path){try{let value=typeof contextValue==='string'?JSON.parse(contextValue):contextValue;` +
      `const parts=String(path??'').replace(/^\\$\\.?/,'').split('.').filter(Boolean);for(const p of parts){` +
      `if(value===null||value===undefined)return '';value=value[p];}return value===null||value===undefined?'':value;}catch(e){return '';}}` +
      `function ruleResultValue(k,list){k=String(k??'');const store=S.stringResults||{};const key=(list?'L:':'S:')+k;` +
      `if(Object.prototype.hasOwnProperty.call(store,key)){const raw=store[key]??'';if(!list)return raw;` +
      `try{const parsed=JSON.parse(raw);return Array.isArray(parsed)?parsed:(raw===''?[]:[raw]);}catch(e){return [];}}` +
      `const direct=pathValue(k);if(direct!==''&&direct!==null&&direct!==undefined){` +
      `if(list)return Array.isArray(direct)?direct:[direct];return typeof direct==='string'?direct:JSON.stringify(direct);}` +
      `if(!pendingStringRules.some(function(r){return r.rule===k&&r.list===list;}))pendingStringRules.push({rule:k,list:list});` +
      `return list?[]:'';}` +
      `function decodeEntities(v){return String(v??'').replace(/&(nbsp|lt|gt|quot|apos|amp|#39|#x27);/gi,function(_,n){` +
      `n=String(n).toLowerCase();if(n==='nbsp')return ' ';if(n==='lt')return '<';if(n==='gt')return '>';` +
      `if(n==='quot')return String.fromCharCode(34);if(n==='amp')return '&';return String.fromCharCode(39);});}` +
      `function elementText(html){return decodeEntities(String(html??'').replace(/<(script|style)[\\s\\S]*?<\\/(script|style)>/gi,' ')` +
      `.replace(/<[^>]*>/g,' ')).replace(/\\s+/g,' ').trim();}` +
      `function elementOwnText(html){var inner=String(html??'').replace(/^<[^>]*>/,'').replace(/<[^>]*>$/,'');` +
      `return decodeEntities(inner.replace(/<[a-zA-Z][^>]*>[\\s\\S]*?<\\/[a-zA-Z][^>]*>/g,' ').replace(/<[^>]*>/g,' '))` +
      `.replace(/\\s+/g,' ').trim();}` +
      `function elementAttrs(html){var start=String(html??'').match(/^<([a-zA-Z][a-zA-Z0-9_-]*)((?:\\s[^<>]*?)?)\\/?>/);` +
      `var attrs={};if(start&&start[2]){var re=/([A-Za-z_:][-A-Za-z0-9_:.]*)\\s*=\\s*(?:"([^"]*)"|'([^']*)'|([^\\s"'=<>` + "`" + `]+))/g;var m;` +
      `while((m=re.exec(start[2]))!==null){attrs[m[1].toLowerCase()]=m[2]!=null?m[2]:(m[3]!=null?m[3]:(m[4]!=null?m[4]:''));}}return attrs;}` +
      `function elementFromHtml(html){var attrs=elementAttrs(html);` +
      `return {attr:function(n){var v=attrs[String(n??'').toLowerCase()];return v===undefined?'':v;},` +
      `hasAttr:function(n){return attrs[String(n??'').toLowerCase()]!==undefined;},` +
      `text:function(){return elementText(html);},ownText:function(){return elementOwnText(html);},` +
      `html:function(){return html;},toString:function(){return elementText(html);}};}` +
      `function getElementList(k){var list=ruleResultValue(String(k??'')+'@html',true);` +
      `return list.map(function(item){return elementFromHtml(item);});}` +
      `const cookieData=Object.assign({},S.cookies||{});const cookie={getCookie:function(k){k=String(k??'');` +
      `if(Object.prototype.hasOwnProperty.call(cookieData,k))return cookieData[k]??'';if(!pendingCookie)pendingCookie=k;return '';},` +
      `getKey:function(k,n){const v=this.getCookie(k);const m=String(v).match(new RegExp('(?:^|;\\\\s*)'+n+'=([^;]*)'));return m?m[1]:'';},` +
      `setCookie:function(k,v){k=String(k??'');v=String(v??'');cookieData[k]=v;cookieOps.push({operation:'set',url:k,value:v,name:''});return v;},` +
      `replaceCookie:function(k,v){k=String(k??'');v=String(v??'');cookieData[k]=v;cookieOps.push({operation:'replace',url:k,value:v,name:''});return v;},` +
      `removeCookie:function(k,n){k=String(k??'');n=String(n??'');cookieOps.push({operation:'remove',url:k,value:'',name:n});` +
      `cookieData[k]='';return true;}};` +
      `function loginHeaderMap(){if(!S.sourceLoginHeader)return null;let v;try{v=JSON.parse(S.sourceLoginHeader);}catch(e){return null;}` +
      `if(!v||typeof v!=='object'||Array.isArray(v)||Object.keys(v).length===0)return null;for(const k of Object.keys(v)){` +
      `const m=String(v[k]??'').match(/^Bearer\\s+([A-Za-z0-9_-]+)\\.([A-Za-z0-9_-]+)\\./i);if(!m)continue;try{` +
      `let p=m[2].replace(/-/g,'+').replace(/_/g,'/');while(p.length%4)p+='=';const d=JSON.parse(b64d(p)||'{}');` +
      `if(Number(d.exp||0)>0&&Number(d.exp)*1000<=Number(S.fixedNow)+30000)return null;}catch(e){}}return v;}` +
      `const source={bookSourceUrl:S.sourceUrl,bookSourceName:S.sourceName,header:S.sourceHeader,loginUrl:S.sourceLoginUrl||'',` +
      `getKey:function(){return S.sourceUrl;},getTag:function(){return S.sourceName;},getSource:function(){return this;},` +
      `getLoginHeader:function(){return S.sourceLoginHeader||'';},` +
      `getLoginHeaderMap:loginHeaderMap,` +
      `putLoginHeader:function(v){S.sourceLoginHeader=typeof v==='string'?v:JSON.stringify(v??'');return S.sourceLoginHeader;},` +
      `removeLoginHeader:function(){S.sourceLoginHeader='';return '';},` +
      `getHeaderMap:function(){try{return JSON.parse(S.sourceHeader||'{}');}catch(e){return {};}} ,` +
      `getVariable:function(){return S.variable||'';},setVariable:function(v){S.variable=String(v??'');return S.variable;},` +
      `refreshExplore:function(){refreshExploreRequested=true;return true;},` +
      `get:function(k){return sourceData[String(k??'')]??'';},put:function(k,v){sourceData[String(k??'')]=v;return v;},` +
      `putLoginInfo:function(v){if(typeof v==='string'){try{v=JSON.parse(v);}catch(e){return v;}}` +
      `if(v&&typeof v==='object')Object.assign(loginMap,v);return v;},` +
      `getLoginInfo:function(k){return arguments.length?(loginMap[k]??''):JSON.stringify(loginMap);},` +
      `getLoginInfoMap:function(){return loginMap;}};` +
      `const book=Object.assign({},S.bookState||{});book.type=Number(S.bookType||book.type||0);` +
      `book.getVariable=function(k){return bookData[String(k??'')]??'';};` +
      `book.putVariable=function(k,v){bookData[String(k??'')]=String(v??'');return v;};` +
      `book.setVariable=book.putVariable;book.setUseReplaceRule=function(v){` +
      `if(!this.readConfig||typeof this.readConfig!=='object')this.readConfig={};` +
      `this.readConfig.useReplaceRule=!!v;return !!v;};` +
      `if(!book.readConfig||typeof book.readConfig!=='object')book.readConfig={};` +
      `Object.defineProperty(book,'variable',{configurable:true,get:function(){return JSON.stringify(bookData);},` +
      `set:function(v){let next={};try{next=JSON.parse(String(v||'{}'));}catch(e){}for(const k of Object.keys(bookData))delete bookData[k];` +
      `if(next&&typeof next==='object')Object.assign(bookData,next);}});book.abstract=book.intro||book.abstract||'';` +
      `const chapter=Object.assign({},S.chapterState||{});chapter.title=String(S.chapterTitle||chapter.title||'');` +
      `chapter.imgUrl=String(S.chapterImgUrl||chapter.imgUrl||'');` +
      `chapter.update=function(){return true;};` +
      `const cache={get:function(k){return cacheData[k]??null;},getFromMemory:function(k){return cacheData[k]??null;},` +
      `put:function(k,v){cacheData[k]=v;return v;},putMemory:function(k,v){cacheData[k]=v;return v;},` +
      `delete:function(k){delete cacheData[k];return true;}};` +
      `function stableDeviceId(){let value=String(javaData.__legadoHarmonyDeviceId||'').trim();` +
      `if(!/^[0-9a-f]{16}$/i.test(value)){value='';for(let i=0;i<16;i++)value+=Math.floor(Math.random()*16).toString(16);` +
      `javaData.__legadoHarmonyDeviceId=value;}return value;}` +
      `function specUrl(v){v=String(v??'');const i=v.indexOf(',{');return i>0?v.substring(0,i):v;}` +
      `function responseCookieList(v){const ignored={path:1,domain:1,expires:1,'max-age':1,secure:1,httponly:1,samesite:1,priority:1};` +
      `const values=[];const seen={};const re=/(?:^|[;,\\r\\n]\\s*)([A-Za-z0-9_.-]+)=([^;,\\r\\n]*)/g;let m;` +
      `while((m=re.exec(String(v??'')))!==null){const n=m[1],k=n.toLowerCase();if(ignored[k]||seen[k])continue;` +
      `seen[k]=1;values.push(n+'='+String(m[2]??'').trim());}return values.join(', ');}` +
      `function responseObject(v){v=String(v??'');let body='';` +
      `if(Object.prototype.hasOwnProperty.call(S.responses,v))body=S.responses[v]??'';else if(!pending)pending=v;` +
      `return {body:function(){return body;},code:function(){return body?200:599;},` +
      `isSuccessful:function(){return !!body;},headers:function(){var map={};` +
      `try{map=JSON.parse((S.responseHeaders||{})[v]||'{}');}catch(e){map={};}` +
      `var upper={};for(var hk in map){upper[String(hk).toUpperCase()]=String(map[hk]);}` +
      `return {get:function(n){var name=String(n??'');if(map[name]!==undefined&&map[name]!==null)return String(map[name]);` +
      `var u=upper[name.toUpperCase()];return u===undefined?null:u;},` +
      `names:function(){return Object.keys(map);}};},` +
      `cookies:function(){const u=specUrl(v);` +
      `const c=responseCookieList(cookieData[u]);return {toString:function(){return c;},size:function(){return c?c.split(',').length:0;}};},` +
      `toString:function(){return body;}};}` +
      `function requestSpec(method,u,b,h){const options={method:String(method||'GET').toUpperCase()};` +
      `if(b!==undefined&&b!==null)options.body=typeof b==='string'?b:JSON.stringify(b);` +
      `if(h&&typeof h==='object')options.headers=h;return String(u??'')+','+JSON.stringify(options);}` +
      `function headerObject(v){if(!v)return {};if(typeof v==='string'){const s=v.trim();if(!s)return {};` +
      `try{v=JSON.parse(s);}catch(e){const o={};for(const line of s.split(/[\\r\\n]+/)){const i=line.indexOf(':');` +
      `if(i>0)o[line.substring(0,i).trim()]=line.substring(i+1).trim();}return o;}}` +
      `if(!v||typeof v!=='object'||Array.isArray(v))return {};const o={};for(const k of Object.keys(v)){` +
      `const x=v[k];if(x!==undefined&&x!==null&&typeof x!=='object')o[String(k)]=String(x);}return o;}` +
      `function sourceHeaders(){const raw=String(S.sourceHeader||'').trim();if(!raw)return {};` +
      `if(/^@?js\\s*:/i.test(raw)){try{return headerObject((0,eval)(raw.replace(/^@?js\\s*:/i,'')));}catch(e){return {};}}` +
      `return headerObject(raw);}` +
      `function browserDocument(h,p){let html=typeof h==='string'?h:'';const preload=typeof p==='string'?p:'';` +
      `if(!preload)return html;const safe=preload.replace(/<\\/script/gi,'<\\\\/script');` +
      `const bridge='<script>(function(){var memory={};var java=window.java||{ajax:function(u){` +
      `var x=new XMLHttpRequest();x.open("GET",String(u||""),false);x.send(null);` +
      `if(x.status!==0&&(x.status<200||x.status>=400))throw new Error("HTTP "+x.status);return x.responseText||"";},` +
      `get:function(u){var b=this.ajax(u);return {body:function(){return b;}};},` +
      `log:function(){},toast:function(){},longToast:function(){}};` +
      `var cache=window.cache||{get:function(k){return memory[String(k)]||null;},` +
      `put:function(k,v){memory[String(k)]=v;return v;},getMemory:function(k){return memory[String(k)]||null;},` +
      `putMemory:function(k,v){memory[String(k)]=v;return v;}};'+safe+'})();<\\/script>';` +
      `const head=html.match(/<head\\b[^>]*>/i);return head?html.replace(head[0],head[0]+bridge):bridge+html;}` +
      `const java={ajax:function(v){v=String(v??'');if(Object.prototype.hasOwnProperty.call(S.responses,v))return S.responses[v];` +
      `if(!pending){pending=v;pendingHeaders=JSON.stringify(sourceHeaders());}return '{}';},` +
      `ajaxAll:function(v){const list=Array.isArray(v)?v:[v];return list.map(responseObject);},` +
      `post:function(u,b,h){return responseObject(requestSpec('POST',u,b,h));},` +
      `put:function(k,v){javaData[String(k??'')]=v;return v;},` +
      `get:function(k,h){if(arguments.length>1)return responseObject(requestSpec('GET',k,null,h));` +
      `k=String(k??'');return Object.prototype.hasOwnProperty.call(javaData,k)?javaData[k]:null;},` +
      `log:function(v){logs.push({level:'info',message:String(v??'')});return v===undefined?'':v;},` +
      `logType:function(v){logs.push({level:'info',message:String(v??'')});return v===undefined?'':v;},` +
      `toast:function(v){toast=String(v??'');return toast;},longToast:function(v){toast=String(v??'');return toast;},` +
      `androidId:stableDeviceId,deviceID:function(){if(S.readerActionMode)return stableDeviceId();` +
      `throw new Error('deviceID unavailable');},qread:function(){throw new Error('qread unavailable');},` +
      `base64Encode:b64e,base64EncodeToString:b64e,base64Decode:b64d,base64DecodeToString:b64d,` +
      `base64DecodeToByteArray:function(v){try{const s=atob(String(v??''));const a=[];` +
      `for(let i=0;i<s.length;i++)a.push(s.charCodeAt(i)&255);return a;}catch(e){return [];}} ,` +
      `hexDecodeToString:hexD,hexEncodeToString:hexE,getCookie:function(k,n){` +
      `return arguments.length>1?cookie.getKey(k,n):cookie.getCookie(k);},` +
      `md5Encode:function(v){return cryptoOp('MD5','','','digestHex',v);},` +
      `md5Encode32:function(v){return cryptoOp('MD5','','','digestHex',v);},` +
      `md5Encode16:function(v){return String(cryptoOp('MD5','','','digestHex',v)).substring(8,24);},` +
      `__setContextContent:function(v){contextValue=v;if(v&&typeof v==='object'){const raw=JSON.stringify(v);` +
      `try{Object.defineProperty(v,'toString',{configurable:true,enumerable:false,value:function(){return raw;}});}catch(e){}` +
      `try{Object.defineProperty(v,Symbol.toPrimitive,{configurable:true,enumerable:false,value:function(){return raw;}});}catch(e){}` +
      `globalThis.result=v;}else{globalThis.result=v==null?'':v;}return true;},` +
      `getString:function(k){return ruleResultValue(k,false);},` +
      `getStringList:function(k){return ruleResultValue(k,true);},` +
      `getElement:function(k){return getElementList(k);},` +
      `setContent:function(v){this.__setContextContent(typeof v==='string'?v:JSON.stringify(v??''));return true;},` +
      `timeFormat:function(v){try{return new NativeDate(Number(v)).toISOString().replace('T',' ').replace('Z','');}catch(e){return String(v??'');}},` +
      `timeFormatUTC:function(v){try{return new NativeDate(Number(v)).toISOString();}catch(e){return String(v??'');}},` +
      `startBrowser:function(u){url=String(u??'');return {body:function(){return '';}};},` +
      `startBrowserAwait:function(u){url=String(u??'');return {body:function(){return '';}};},` +
      `startBrowserDp:function(u){url=String(u??'');return {body:function(){return '';}};},` +
      `showReadingBrowser:function(u){url=String(u??'');return {body:function(){return '';}};},` +
      // Sources call showBrowser in two shapes: showBrowser(url, html, preloadJs) wants a built
      // document, while paragraph-comment bubbles call showBrowser(url, null, null, config) where
      // the trailing object only describes the host sheet. With no html there is nothing to build:
      // keep requestedHtml empty so the reader opens the URL itself instead of a blank document
      // that would inject the config JSON as if it were script.
      `showBrowser:function(u,h,p){url=String(u??'');` +
      `browserHtml=(typeof h==='string'&&h)?browserDocument(h,p):'';` +
      `return {body:function(){return browserHtml;}};},` +
      `open:function(u){url=String(u??'');return url;},webView:function(){throw new Error('java.webView仅登录动作可用');},` +
      `getWebViewUA:function(){return 'Mozilla/5.0 (Linux; HarmonyOS) AppleWebKit/537.36 Mobile Safari/537.36';},` +
      `getAppVariant:function(){return 'harmony';},` +
      `refreshExplore:function(){refreshExploreRequested=true;return true;},refreshBookToc:function(){return true;},` +
      `refreshContent:function(){return true;},upConfig:function(){return true;},searchBook:function(){return true;}};` +
      `function TimeoutCancellationException(){}const Packages={io:{legato:{kazusa:{utils:{` +
      `TimeoutCancellationException:TimeoutCancellationException}}}}};` +
      `function JavaImporter(){return {importClass:function(){return true;},importPackage:function(){return true;}};}` +
      `function importClass(){return true;}function importPackage(){return true;}` +
      `globalThis.source=source;globalThis.book=book;globalThis.chapter=chapter;globalThis.java=java;` +
      `globalThis.cache=cache;globalThis.cookie=cookie;globalThis.infoMap=infoMap;` +
      `const runtimeScope=Object.create(globalThis);runtimeScope.source=source;runtimeScope.book=book;` +
      `runtimeScope.chapter=chapter;runtimeScope.java=java;runtimeScope.cache=cache;runtimeScope.cookie=cookie;` +
      `runtimeScope.infoMap=infoMap;` +
      `globalThis.__legadoHarmonyStageScope=runtimeScope;` +
      `globalThis.Packages=Packages;globalThis.baseUrl=S.baseUrl;globalThis.result=S.content;globalThis.src=S.content;` +
      `globalThis.title=S.chapterTitle||'';Object.keys(bookData).forEach(function(k){` +
      `if(/^[A-Za-z_$][A-Za-z0-9_$]*$/.test(k)&&globalThis[k]===undefined)globalThis[k]=bookData[k];});` +
      `Object.keys(S.variables||{}).forEach(function(k){globalThis[k]=S.variables[k];});` +
      `let evaluated;try{evaluated=(function(){return eval(dec('${codeBase64}'));}).call(globalThis);}` +
      `catch(e){error=String((e&&e.name?e.name+': ':'')+((e&&e.message)||e||'脚本执行失败')+(e&&e.stack?'\\n'+e.stack:''));}` +
      `function text(v){if(typeof v==='string')return v;if(v===undefined||v===null)return '';try{return JSON.stringify(v);}catch(e){return String(v);}}` +
      `const evaluatedText=text(evaluated);const fallbackText=text(globalThis.result);` +
      `const usedInputFallback=!evaluatedText&&!error&&fallbackText===String(S.content||'');` +
      `const value=evaluatedText||fallbackText;` +
      `return encodeURIComponent(JSON.stringify({pendingAjax:pending,pendingStringRules:JSON.stringify(pendingStringRules),inputFallbackUsed:usedInputFallback,pendingHeaders:pendingHeaders,pendingCookie:pendingCookie,pendingCrypto:pendingCrypto,` +
      `cookieOperations:JSON.stringify(cookieOps),variable:S.variable||'',loginHeader:S.sourceLoginHeader||'',` +
      `bookVariable:JSON.stringify(bookData),bookType:String(book.type??''),chapterImgUrl:String(chapter.imgUrl??''),` +
      `bookDurChapterIndex:String(book.durChapterIndex??''),bookImageStyle:String(book.imageStyle??''),` +
      `cacheState:JSON.stringify(cacheData),javaState:JSON.stringify(javaData),sourceState:JSON.stringify(sourceData),logs:JSON.stringify(logs),` +
      `refreshExploreRequested:refreshExploreRequested?'true':'false',` +
      `value:value,requestedUrl:url,requestedHtml:browserHtml,toastMessage:toast,errorMessage:error}));})()`;
  }

  private parseStep(raw: string): StageWebRuntimeStep {
    let value = (raw || '').trim();
    // ArkWeb serializes a JavaScript string result as a JSON string on some system versions.
    // Decode that wrapper with JSON.parse so escaped quotes/backslashes survive.  The old
    // substring approach happened to work for simple payloads, but corrupts a result as soon as
    // it contains the JSON-encoded dynamic source headers used by authenticated sources.
    if (value.startsWith('"') && value.endsWith('"')) {
      try {
        value = String(JSON.parse(value));
      } catch (_) {
        value = value.substring(1, value.length - 1);
      }
    } else if (value.startsWith("'") && value.endsWith("'")) {
      value = value.substring(1, value.length - 1);
    }
    try {
      const record = JSON.parse(decodeURIComponent(value)) as Record<string, Object>;
      const step = new StageWebRuntimeStep();
      step.pendingAjax = String(record['pendingAjax'] || '');
      step.pendingStringRules = String(record['pendingStringRules'] || '[]');
      step.inputFallbackUsed = String(record['inputFallbackUsed'] || '') === 'true';
      step.pendingHeaders = String(record['pendingHeaders'] || '{}');
      step.pendingCookie = String(record['pendingCookie'] || '');
      step.pendingCrypto = String(record['pendingCrypto'] || '');
      step.cookieOperations = String(record['cookieOperations'] || '[]');
      step.variable = String(record['variable'] || '');
      step.loginHeader = String(record['loginHeader'] || '');
      step.bookVariable = String(record['bookVariable'] || '{}');
      step.bookType = String(record['bookType'] || '');
      step.chapterImgUrl = String(record['chapterImgUrl'] || '');
      step.bookDurChapterIndex = String(record['bookDurChapterIndex'] || '');
      step.bookImageStyle = String(record['bookImageStyle'] || '');
      step.cacheState = String(record['cacheState'] || '{}');
      step.javaState = String(record['javaState'] || '{}');
      step.sourceState = String(record['sourceState'] || '{}');
      step.logs = String(record['logs'] || '[]');
      step.value = String(record['value'] || '');
      step.requestedUrl = String(record['requestedUrl'] || '');
      step.requestedHtml = String(record['requestedHtml'] || '');
      step.toastMessage = String(record['toastMessage'] || '');
      step.errorMessage = String(record['errorMessage'] || '');
      step.refreshExploreRequested = String(record['refreshExploreRequested'] || '');
      return step;
    } catch (error) {
      // Never print the returned value: it can contain credentials or copyrighted content.
      console.warn('[StageWebRuntime] invalid result envelope, length=' + value.length +
        ', encoded=' + String(value.indexOf('%7B') >= 0 || value.indexOf('%7b') >= 0) +
        ', error=' + String(error));
      const step = new StageWebRuntimeStep();
      step.errorMessage = '书源脚本返回格式异常';
      return step;
    }
  }

  private variableValue(raw: string, key: string): string {
    try {
      const record = JSON.parse(raw || '{}') as Record<string, Object>;
      return String(record[key] || '');
    } catch (_) {
      return '';
    }
  }

  private setVariableValue(raw: string, key: string, value: string): string {
    let record: Record<string, Object> = {};
    try {
      record = JSON.parse(raw || '{}') as Record<string, Object>;
    } catch (_) {
      record = {};
    }
    record[key] = value;
    return JSON.stringify(record);
  }

  private functionExposeScript(script: string): string {
    const names: string[] = [];
    const regex = /\bfunction\s+([A-Za-z_$][A-Za-z0-9_$]*)\s*\(/g;
    let match: RegExpExecArray | null;
    while ((match = regex.exec(script || '')) !== null) {
      const name = match[1] || '';
      if (name && !names.includes(name)) names.push(name);
    }
    let code = `globalThis.__legadoHarmonyStageExposedNames=${JSON.stringify(names)};`;
    for (const name of names) {
      // Legado jsLib helpers use `this` as the runtime scope (`this.source`, `this.java`, ...).
      // ArkWeb can supply an intermediate function receiver after a packed script aliases a
      // helper. Keep a single Rhino-compatible global scope for every exposed source function.
      code += `if(typeof ${name}==='function'){let original=${name};${name}=function(){return original.apply(` +
        `(globalThis.__legadoHarmonyStageScope||globalThis),arguments);};` +
        `globalThis[${JSON.stringify(name)}]=${name};}`;
    }
    return code;
  }

  private normalizeScript(script: string): string {
    // Rhino/Legado sources sometimes redeclare a function argument while applying a default:
    // `function f(sourceUrl) { let sourceUrl = sourceUrl || host; }`. Chromium correctly rejects
    // this as a duplicate lexical declaration. Rewriting only the self-fallback declaration keeps
    // the intended assignment and also covers the same legacy pattern with other argument names.
    return (script || '')
      .replace(/\b(?:let|const)\s+([A-Za-z_$][A-Za-z0-9_$]*)\s*=\s*\1\s*\|\|/g,
        (_match: string, name: string): string => `${name} = ${name} ||`)
      // Rhino accepts a destructuring parameter without the parentheses required by ECMAScript,
      // for example `.map([title, list] => ...)`.  Limit the compatibility rewrite to callback
      // methods so array literals and ordinary arrow functions are not changed accidentally.
      .replace(/(\b(?:map|flatMap|filter|forEach|find|some|every|reduce)\s*\(\s*)(\[[^\]\r\n]+\]|\{[^}\r\n]+\})\s*=>/g,
        (_match: string, prefix: string, parameter: string): string => `${prefix}(${parameter}) =>`);
  }

  private applyCookieOperations(raw: string, journal: BookSourceExecutionJournal): void {
    let records: Object[] = [];
    try {
      const value = JSON.parse(raw || '[]') as Object;
      if (Array.isArray(value)) records = value;
    } catch (_) {}
    for (const item of records) {
      if (!item || typeof item !== 'object' || Array.isArray(item)) continue;
      const record = item as Record<string, Object>;
      const operation = new StageWebRuntimeCookieOperation();
      operation.operation = String(record['operation'] || '');
      operation.url = String(record['url'] || '');
      operation.value = String(record['value'] || '');
      operation.name = String(record['name'] || '');
      const key = `${operation.operation}\n${operation.url}\n${operation.name}\n${operation.value}`;
      if (!operation.url || !journal.markOperationApplied(BookSourceHostActionKind.COOKIE_MUTATION, key)) continue;
      if (operation.operation === 'set') CookieStore.setCookies(operation.url, operation.value);
      if (operation.operation === 'replace') CookieStore.replaceCookies(operation.url, operation.value);
      if (operation.operation === 'remove') CookieStore.removeCookie(operation.url, operation.name || undefined);
    }
    if (records.length > 0) CookieStore.saveAsync();
  }

  private parseRecord(raw: string): Record<string, string> {
    try {
      const value = JSON.parse(raw || '{}') as Record<string, Object>;
      const result: Record<string, string> = {};
      for (const key of Object.keys(value)) result[key] = String(value[key] || '');
      return result;
    } catch (_) {
      return {};
    }
  }

  private parseLoginInfo(raw: string): Record<string, string> {
    try {
      const value = JSON.parse(raw || '{}') as Record<string, Object>;
      const result: Record<string, string> = {};
      for (const key of Object.keys(value)) {
        if (key !== '__legadoHarmonyRuntime') result[key] = String(value[key] || '');
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  private parseRuntimeJavaState(raw: string): Record<string, Object> {
    return this.parseRuntimeObjectState(raw, 'java');
  }

  private parseRuntimeObjectState(raw: string, stateKey: string): Record<string, Object> {
    try {
      const loginInfo = JSON.parse(raw || '{}') as Record<string, Object>;
      let runtime = loginInfo['__legadoHarmonyRuntime'];
      if (typeof runtime === 'string') runtime = JSON.parse(runtime) as Object;
      if (!runtime || typeof runtime !== 'object' || Array.isArray(runtime)) return {};
      const state = (runtime as Record<string, Object>)[stateKey];
      if (!state || typeof state !== 'object' || Array.isArray(state)) return {};
      return state as Record<string, Object>;
    } catch (_) {
      return {};
    }
  }

  private mergeRuntimeState(raw: string, javaStateRaw: string, sourceStateRaw: string): string {
    let loginInfo: Record<string, Object> = {};
    try {
      const parsed = JSON.parse(raw || '{}') as Object;
      if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
        loginInfo = parsed as Record<string, Object>;
      }
    } catch (_) {}
    let runtime: Record<string, Object> = {};
    const existingRuntime = loginInfo['__legadoHarmonyRuntime'];
    try {
      const parsedRuntime = typeof existingRuntime === 'string' ? JSON.parse(existingRuntime) as Object : existingRuntime;
      if (parsedRuntime && typeof parsedRuntime === 'object' && !Array.isArray(parsedRuntime)) {
        runtime = parsedRuntime as Record<string, Object>;
      }
    } catch (_) {}
    runtime['java'] = this.parseObjectState(javaStateRaw);
    runtime['source'] = this.parseObjectState(sourceStateRaw);
    // Script cache is a bounded in-memory acceleration structure. Persisting it inside loginInfo
    // duplicated potentially large values in the database and in every later runtime request.
    delete runtime['cache'];
    loginInfo['__legadoHarmonyRuntime'] = JSON.stringify(runtime);
    return JSON.stringify(loginInfo);
  }

  private parseObjectState(raw: string): Record<string, Object> {
    try {
      const parsed = JSON.parse(raw || '{}') as Object;
      if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
        return parsed as Record<string, Object>;
      }
    } catch (_) {}
    return {};
  }

  private encodeBase64(value: string): string {
    const bytes = new util.TextEncoder().encodeInto(value || '');
    return new util.Base64Helper().encodeToStringSync(bytes);
  }
}
