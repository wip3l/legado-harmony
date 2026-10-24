import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { readEtsModule } from './lib/ets-module-staging.mjs';

import '../harmony-book-ai-engine/scripts/comic-text-check.mjs';
function load(file, sandbox) {
  const code = readEtsModule(file).replace(/^import [^;]*;\r?\n/gm, '').replace(/^export /gm, '');
  vm.runInContext(stripTypeScriptTypes(code, { mode: 'strip' }), sandbox);
}
const context = vm.createContext({ Map, Set, Number, Math, Error, Array, Infinity });
load('core/reader/ComicTextRequests.ts', context);
const Requests = vm.runInContext('ComicTextRequests', context);
const firstRequest = Requests.put('data:image/png;base64,' + 'x'.repeat(200000));
assert.ok(firstRequest.length < 64);
assert.equal(Requests.take(firstRequest).length, 200022);
assert.equal(Requests.take(firstRequest), '', '路由交接后释放原始来源');
const oldest = Requests.put('old');
for (let index = 0; index < 4; index++) Requests.put(String(index));
assert.equal(Requests.take(oldest), '', '未打开的路由请求也有数量上限');
// 长按入口交接短路由 ID，不改变原有保存/分享/刷新按钮索引；加载中的图片不能送去 OCR。
let menuIndex = 3, routed = null, saved = 0, shared = 0, reloaded = 0, toast = '';
const menuContext = vm.createContext({
  Map, Set, Error,
  router: { async pushUrl(options) { routed = options; } },
  HdsFeedback: { showToast(value) { toast = value; } },
  ReaderImageMarker: { pendingRaw: value => value === 'pending' ? 'raw' : '', failureReason: () => '' },
  ReaderImageResults: { current: () => '' },
  ReaderComicImageExport: {
    async saveToAlbum() { saved++; return true; }, async share() { shared++; }
  }
});
load('core/reader/ComicTextRequests.ts', menuContext);
load('core/reader/ReaderComicImageActions.ets', menuContext);
const Actions = vm.runInContext('ReaderComicImageActions', menuContext);
const MenuRequests = vm.runInContext('ComicTextRequests', menuContext);
const actions = new Actions({
  uiContext: () => ({ getPromptAction: () => ({ async showActionMenu() { return { index: menuIndex }; } }) }),
  abilityContext: () => ({}), accentColor: () => '#007DFF',
  isLocalBook: () => true, currentChapter: () => 0, busy: () => false, refreshCurrentChapter() {}
});
await actions.showMenu('/input/a.png', () => reloaded++, '');
assert.equal(routed.url, 'pages/ComicText');
assert.equal(MenuRequests.take(routed.params.requestId), '/input/a.png');
assert.equal(routed.params.source, undefined);
for (menuIndex of [0, 1, 2]) await actions.showMenu('/input/a.png', () => reloaded++, '');
assert.deepEqual([saved, shared, reloaded], [1, 1, 1]);
routed = null;
menuIndex = 3;
await actions.showMenu('pending', () => reloaded++, '');
assert.equal(routed, null);
assert.equal(toast, '图片还在加载');
console.log('comic-text-check: passed (dictionary, geometry, colors, text layer, cache, engine reuse, cancellation, cleanup, reader menu)');
