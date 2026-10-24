// Run with: node --experimental-strip-types scripts/reader-comment-panel-check.mjs
// Exercise the actual reader methods with controlled Web callbacks and timers.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { ReaderCommentWebTheme } from '../entry/src/main/ets/core/reader/ReaderCommentWebTheme.ts';
import { NativeCommentPage } from '../harmony-book-source-engine/sourceengine/src/main/ets/core/nativesource/NativeCommentPage.ts';

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
    appDarkMode: true,
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
  page.updateReaderCommentPanelHeight(300);
  assert.equal(page.readerCommentPanelHeight, 300);
  page.updateReaderCommentPanelHeight(600);
  assert.equal(page.readerCommentPanelHeight, 600, 'expanded content uses expanded viewport');
  page.updateReaderCommentPanelHeight(400);
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

function inlineHarness() {
  const calls = [], toasts = [];
  const context = vm.createContext({ NativeCommentPage, Error, HttpClient: class {},
    NativeSourceService: { getCommentPage(...args) {
      return new Promise((resolve,reject) => calls.push({ args, resolve, reject }));
    } }, HdsFeedback: { showToast: text => toasts.push(text) } });
  const page = vm.runInContext(stripTypeScriptTypes(`({${method('openReaderInlinePage')}})`, {mode:'strip'}),context);
  Object.assign(page, { book:{bookUrl:'book'}, chapters:[{url:'chapter'}], currentChapterIndex:0,
    readerInlinePageSerial:0, currentReaderSource:()=>({bookSourceUrl:'source'}),
    closeReaderCommentPanel() { this.readerInlinePageSerial++; this.showReaderCommentPanel=false; },
    openReaderCommentPanel(url) { this.remote=url; this.readerInlinePageMode=false; } });
  return {page,calls,toasts,open:()=>page.openReaderInlinePage({bookSourceUrl:'source'},{url:'action'},'marker')};
}
{
  const h=inlineHarness(); const first=h.open();
  assert(h.page.readerInlinePageMode && h.page.readerCommentPanelLoading);
  h.page.closeReaderCommentPanel(); assert(h.calls[0].args[5](), 'closing cancels engine requests');
  h.calls[0].resolve(Object.assign(new NativeCommentPage(),{html:'old'})); await first;
  assert.equal(h.page.showReaderCommentPanel,false); assert.notEqual(h.page.readerInlinePage.html,'old');
}
{
  const h=inlineHarness(); const first=h.open(); const second=h.open();
  h.calls[1].resolve(Object.assign(new NativeCommentPage(),{html:'new',height:0.4})); await second;
  h.calls[0].resolve(Object.assign(new NativeCommentPage(),{html:'old'})); await first;
  assert.equal(h.page.readerInlinePage.html,'new'); assert.equal(h.page.readerInlinePage.height,0.4);
  assert.equal(h.page.readerCommentPanelLoading,false);
}
{
  const h=inlineHarness(); const pending=h.open(); h.page.chapters=[{url:'other'}];
  assert(h.calls[0].args[5]()); h.calls[0].resolve(new NativeCommentPage()); await pending;
  assert.equal(h.page.showReaderCommentPanel,false,'changed chapter closes stale loading sheet');
}
{
  const h=inlineHarness(); const pending=h.open();
  h.calls[0].resolve(Object.assign(new NativeCommentPage(),{fallbackUrl:'https://fallback.example',error:'empty'})); await pending;
  assert.equal(h.page.remote,'https://fallback.example'); assert.equal(h.toasts.length,1);
}
{
  const h=inlineHarness(); const pending=h.open(); h.calls[0].reject(Error('invalid context')); await pending;
  assert.equal(h.page.readerCommentPanelError,true); assert(h.toasts[0].includes('invalid context'));
}
const inlineView=fs.readFileSync(new URL('../entry/src/main/ets/components/NativeCommentPageView.ets',import.meta.url),'utf8');
for (const required of ['incognitoMode: true','.blockNetwork(true)','.fileAccess(false)', '.domStorageAccess(false)',
  '.databaseAccess(false)', '.geolocationAccess(false)', '.allowWindowOpenMethod(false)', '.onOverrideUrlLoading', '.onInterceptRequest']) {
  assert(inlineView.includes(required),required);
}
assert(!inlineView.includes('.javaScriptProxy('),'offline view has no native bridge');
function inlineWebHarness() {
  const timers=new Map(),loads=[];let id=0,ready='false',stopped=0;
  const names=['load','clearTimer','scheduleReady','fail','aboutToDisappear'];
  const methods=names.map(name=>{
    const start=new RegExp(`^  (?:private )?${name}\\(`,'m').exec(inlineView)?.index;
    assert.notEqual(start,undefined,name);
    return inlineView.slice(start,inlineView.indexOf('\n  }',start)+4).replace(/^  private /,'  ');
  });
  const context=vm.createContext({NativeCommentPage,Error,setTimeout:(fn,ms)=>{timers.set(++id,{fn,ms});return id;},clearTimeout:id=>timers.delete(id)});
  const view=vm.runInContext(stripTypeScriptTypes(`({${methods.join(',')}})`,{mode:'strip'}),context);
  Object.assign(view,{attached:true,serial:0,timer:-1,readyTimer:-1,page:Object.assign(new NativeCommentPage(),{html:'<p>test</p>'}),
    error:'',controller:{loadData:(...args)=>loads.push(args),runJavaScript:async()=>ready,stop:()=>stopped++}});
  return {view,timers,loads,ready:value=>{ready=value;},stopped:()=>stopped,async tick(ms){
    const [key,value]=[...timers].find(([,value])=>value.ms===ms)||[];assert(value,'expected timer');timers.delete(key);value.fn();
    for(let i=0;i<6;i++) await Promise.resolve();
  }};
}
{
  const h=inlineWebHarness();h.view.load();assert.equal(h.loads[0][3],'about:blank');assert(h.loads[0][0].includes('__NATIVE_PAGE_GENERATION__=1'));
  await h.tick(100);assert.equal(h.view.loading,true,'no page-end event is needed for readiness polling');
  h.ready('true');await h.tick(100);assert.equal(h.view.loading,false);assert.equal(h.timers.size,0);
}
{
  const h=inlineWebHarness();h.view.load();await h.tick(15000);assert.match(h.view.error,/15 秒/);
  assert.equal(h.view.attached,false);assert.equal(h.timers.size,0);assert.equal(h.stopped(),1);
}
{
  const h=inlineWebHarness();h.view.load();h.view.aboutToDisappear();assert.equal(h.timers.size,0);assert.equal(h.view.attached,false);
}
console.log('PASS inline comment panel: click, close cancellation, stale results, chapter changes, fallback and error handling; Web policy wiring');

const panel = source.slice(source.indexOf('  readerCommentPanel()'), source.indexOf('  readerFloatingTopMenu()'));
assert.match(panel, /scrollForward: NestedScrollMode.SELF_ONLY/);
assert.match(panel, /scrollBackward: NestedScrollMode.SELF_ONLY/);
assert.doesNotMatch(panel, /hitTestBehavior\(HitTestMode.Block\)/, 'no inert overlay can cover the system drag handle');
const sheetContext = vm.createContext({ SheetSize: { LARGE: 'large' }, ScrollSizeMode: { CONTINUOUS: 'continuous' } });
const sheetPage = vm.runInContext(stripTypeScriptTypes(`({${method('readerCommentSheetOptions')}})`, { mode: 'strip' }), sheetContext);
sheetPage.readerCommentPanelWebBackground = () => '#FFFFFF';
const sheet = sheetPage.readerCommentSheetOptions();
assert.equal(sheet.dragBar, true, 'native sheet owns the functional drag handle');
assert.deepEqual(Array.from(sheet.detents), ['60%', 'large']);
assert.equal(sheet.scrollSizeMode, 'continuous');
assert.equal(sheet.onHeightDidChange, undefined, 'whole-sheet height must not be used as Web viewport height');
const resizeHandler = panel.match(/\.onSizeChange\((\(_oldValue: SizeOptions, newValue: SizeOptions\) => \{[\s\S]*?\n    \})\)/)?.[1];
assert(resizeHandler, 'measure the content viewport below the native handle');
const resizeHarness = harness();
const resize = vm.runInContext(stripTypeScriptTypes(resizeHandler, { mode: 'strip' }), vm.createContext(resizeHarness.page));
for (const height of [320, 640, 420]) {
  resize({ height: 0 }, { height });
  assert.equal(resizeHarness.page.readerCommentPanelHeight, height, 'native drag resizes Web in vp without including the handle');
}
console.log('PASS: native drag handle enabled; Web scroll isolated; content viewport follows available height');
