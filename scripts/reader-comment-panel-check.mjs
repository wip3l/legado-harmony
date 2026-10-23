// Run with: node --experimental-strip-types scripts/reader-comment-panel-check.mjs
// Exercise the actual reader methods with controlled Web callbacks and timers.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { ReaderCommentWebTheme } from '../entry/src/main/ets/core/reader/ReaderCommentWebTheme.ts';

const source = fs.readFileSync(new URL('../entry/src/main/ets/pages/ReadBook.ets', import.meta.url), 'utf8');
function method(name) {
  const start = new RegExp(`^  (?:async )?${name}\\(`, 'm').exec(source)?.index;
  assert.notEqual(start, undefined, name);
  return source.slice(start, source.indexOf('\n  }', start) + 4);
}
function harness() {
  let id = 0;
  const timers = new Map();
  const context = vm.createContext({
    ReaderCommentWebTheme, console: { warn() {} },
    setTimeout: fn => { timers.set(++id, fn); return id; },
    clearTimeout: key => timers.delete(key)
  });
  const methods = ['updateReaderCommentPanelHeight', 'scheduleReaderCommentPanelHostReady',
    'backReaderCommentPanel', 'closeReaderCommentPanel', 'failReaderCommentPanelLoad', 'retryReaderCommentPanelLoad',
    'syncReaderCommentPanelWebTheme', 'loadReaderCommentPanelHtmlIfNeeded'];
  const page = vm.runInContext(stripTypeScriptTypes(`({${methods.map(method).join(',')}})`, { mode: 'strip' }), context);
  Object.assign(page, {
    showReaderCommentPanel: true, readerCommentPanelHeight: 0, readerCommentPanelLoadSerial: 1,
    readerCommentPanelReadyTimerId: -1, readerCommentPanelLoading: true, readerCommentPanelError: false,
    readerCommentPanelUrl: 'https://comments.example/', readerCommentPanelHtml: '',
    appDarkMode: true, getUIContext: () => ({ px2vp: px => px / 3 }),
    readerCommentPanelController: { runJavaScript: async () => '0' }
  });
  return { page, timers, async tick() {
    const [key, fn] = timers.entries().next().value || [];
    assert(fn, 'scheduled readiness check exists');
    timers.delete(key); fn();
    // Drain runJavaScript, theme status and host visibility continuations.
    for (let i = 0; i < 5; i++) await Promise.resolve();
  } };
}

{
  const { page } = harness();
  page.updateReaderCommentPanelHeight(900);
  assert.equal(page.readerCommentPanelHeight, 300);
  page.updateReaderCommentPanelHeight(1800);
  assert.equal(page.readerCommentPanelHeight, 600, 'expanded content uses expanded viewport');
  page.updateReaderCommentPanelHeight(1200);
  assert.equal(page.readerCommentPanelHeight, 400, 'collapse updates viewport too');
  for (const invalid of [0, -1, NaN, Infinity]) page.updateReaderCommentPanelHeight(invalid);
  assert.equal(page.readerCommentPanelHeight, 400);
  page.showReaderCommentPanel = false;
  page.updateReaderCommentPanelHeight(600);
  assert.equal(page.readerCommentPanelHeight, 400, 'closing animation keeps existing document size');
}
{
  const h = harness();
  h.page.scheduleReaderCommentPanelHostReady(0);
  await h.tick();
  assert.equal(h.page.readerCommentPanelLoading, true, 'unpainted document stays covered');
  h.page.readerCommentPanelController.runJavaScript = async () => '1';
  await h.tick();
  assert.equal(h.page.readerCommentPanelLoading, false, 'reveal only after themed frames are ready');
  assert.equal(h.timers.size, 0);
}
{
  const h = harness();
  let resolveOld;
  h.page.readerCommentPanelController.runJavaScript = () => new Promise(resolve => { resolveOld = resolve; });
  h.page.scheduleReaderCommentPanelHostReady(0);
  await h.tick();
  h.page.closeReaderCommentPanel();
  h.page.showReaderCommentPanel = true; // A new panel/document has started loading.
  resolveOld('1');
  for (let i = 0; i < 5; i++) await Promise.resolve();
  assert.equal(h.page.readerCommentPanelLoading, true, 'old document cannot reveal a reopened panel');
}
{
  const h = harness();
  h.page.readerCommentPanelController.runJavaScript = async () => { throw Error('controller not ready'); };
  h.page.scheduleReaderCommentPanelHostReady(0);
  for (let i = 0; i <= 60; i++) await h.tick();
  assert.equal(h.page.readerCommentPanelError, true);
  assert.equal(h.page.readerCommentPanelLoading, true, 'failed theme stays covered instead of flashing white');
  assert.equal(h.timers.size, 0, 'retries are bounded');
  let refreshed = false;
  h.page.readerCommentPanelController.refresh = () => { refreshed = true; };
  h.page.retryReaderCommentPanelLoad();
  assert(refreshed);
  assert.equal(h.page.readerCommentPanelError, false);
}
for (const previousUrl of [null, 'about:blank', 'https://comments.example/list']) {
  const { page } = harness();
  let wentBack = false;
  page.readerCommentPanelController.getBackForwardEntries = () => ({
    currentIndex: previousUrl === null ? 0 : 1,
    getItemAtIndex: () => ({ historyUrl: previousUrl })
  });
  page.readerCommentPanelController.backward = () => { wentBack = true; };
  page.backReaderCommentPanel();
  const hasHistory = previousUrl?.startsWith('https:') === true;
  assert.equal(wentBack, hasHistory, 'navigate real history only');
  assert.equal(page.showReaderCommentPanel, hasHistory, 'root/blank back closes sheet');
}
{
  const { page } = harness();
  page.readerCommentPanelController.getBackForwardEntries = () => { throw Error('not attached'); };
  page.backReaderCommentPanel();
  assert.equal(page.showReaderCommentPanel, false, 'back works during loading too');
}
{
  let backs = 0, closes = 0, forwards = 0;
  const window = { LegadoCommentHost: { back() { backs++; }, close() { closes++; } }, close() {} };
  const history = { back() { throw Error('must delegate to host'); }, go(delta) { forwards += delta; } };
  const context = vm.createContext({ window, history });
  vm.runInContext(ReaderCommentWebTheme.navigation(), context);
  vm.runInContext(ReaderCommentWebTheme.navigation(), context); // loadData/document-start double injection
  history.back(); history.go(-1); window.close(); history.go(1);
  assert.equal(backs, 2);
  assert.equal(closes, 1);
  assert.equal(forwards, 1, 'forward navigation remains unchanged');
}
for (const dark of [false, true]) {
  new vm.Script(ReaderCommentWebTheme.bootstrap(dark));
  new vm.Script(ReaderCommentWebTheme.apply(dark, true));
  const html = ReaderCommentWebTheme.prepareHtml('<!doctype html><html><head><script>pageInit()</script></head><body>评论</body></html>', dark);
  assert(html.startsWith('<!doctype html>'), 'preserve standards mode');
  assert(html.indexOf('__LEGADO_COMMENT_INLINE__') < html.indexOf('pageInit()'), 'theme precedes page scripts');
}
console.log('PASS comment panel: live resize, painted-theme reveal, stale callbacks, bounded failure/retry, early HTML theme, Web back/close bridge');
