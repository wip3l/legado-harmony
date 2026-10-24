import assert from 'node:assert/strict';
import fs from 'node:fs';
import crypto from 'node:crypto';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';

import '../harmony-book-ai-engine/scripts/comic-colorizer-check.mjs';
import '../harmony-book-ai-engine/scripts/comic-color-backend-check.mjs';
// Exercise the actual long-press dispatch: new action retains the existing indices and only routes a short ID.
let selected = 4, routed, reloaded = 0;
const menu = vm.createContext({ Map, Set, Error,
  router: { async pushUrl(options) { routed = options; } }, HdsFeedback: { showToast() {} },
  ReaderImageMarker: { pendingRaw: () => '', failureReason: () => '' }, ReaderImageResults: {},
  ReaderComicImageExport: { async saveToAlbum() { return true; }, async share() {} }
});
for (const file of ['ComicTextRequests.ts', 'ReaderComicImageActions.ets']) {
  const source = fs.readFileSync(new URL('../entry/src/main/ets/core/reader/' + file, import.meta.url), 'utf8');
  vm.runInContext(stripTypeScriptTypes(source.replace(/^import [^;]*;\r?\n/gm, '').replace(/^export /gm, ''),
    { mode: 'strip' }), menu);
}
const Actions = vm.runInContext('ReaderComicImageActions', menu);
const Requests = vm.runInContext('ComicTextRequests', menu);
const actions = new Actions({
  uiContext: () => ({ getPromptAction: () => ({ async showActionMenu() { return { index: selected }; } }) }),
  abilityContext: () => ({}), accentColor: () => '#007DFF', busy: () => false
});
await actions.showMenu('/comic/original.png', () => reloaded++, '');
assert.equal(routed.url, 'pages/ComicColor');
assert.equal(Requests.take(routed.params.requestId), '/comic/original.png');
assert.equal(routed.params.source, undefined);
selected = 3;
await actions.showMenu('/comic/original.png', () => reloaded++, '');
assert.equal(routed.url, 'pages/ComicText');
selected = 2;
await actions.showMenu('/comic/original.png', () => reloaded++, '');
assert.equal(reloaded, 1);
selected = 4;
let inPlaceSource = '';
const inPlace = new Actions({
  uiContext: () => ({ getPromptAction: () => ({ async showActionMenu() { return { index: selected }; } }) }),
  abilityContext: () => ({}), accentColor: () => '#007DFF', busy: () => false,
  colorPage: source => { inPlaceSource = source; return true; }
});
routed = null;
await inPlace.showMenu('/comic/current.png', () => {}, '');
assert.equal(inPlaceSource, '/comic/current.png');
assert.equal(routed, null, 'reader single-page coloring stays in the reader');
console.log('Comic color: long-press color/OCR/reload routing passed.');
