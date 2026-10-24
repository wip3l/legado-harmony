import assert from 'node:assert/strict';
import fs from 'node:fs';
import crypto from 'node:crypto';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';

const code = fs.readFileSync(new URL('../entry/src/main/ets/core/reader/ComicColorPixels.ts', import.meta.url), 'utf8');
const context = vm.createContext({ Uint8Array, Float32Array, Math, Number, Error });
vm.runInContext(stripTypeScriptTypes(code.replace(/^export /gm, ''), { mode: 'strip' }), context);
const pixels = vm.runInContext('ComicColorPixels', context);
assert.deepEqual(JSON.parse(JSON.stringify(pixels.fit(1200, 1800, 384))), { width: 256, height: 384 });
assert.throws(() => pixels.fit(1000, 16000, 384), /长条图/);
assert.throws(() => pixels.fit(Infinity, 200, 384));
assert.deepEqual(JSON.parse(JSON.stringify(pixels.modelSize(1350, 1920))), { width: 512, height: 728 });
assert.deepEqual(JSON.parse(JSON.stringify(pixels.modelSize(1920, 1350))), { width: 728, height: 512 });
assert.deepEqual(JSON.parse(JSON.stringify(pixels.padded({width: 512, height: 728}))), {width: 512, height: 736});
// Stride, alpha and the five-channel hint contract are independent of decoder alignment.
const gray = new Uint8Array([0,0,0,255, 255,255,255,255, 99,99,99,99, 0,0,0,0, 128,128,128,255, 99,99,99,99]);
const input = pixels.input(gray, 2, 2, 12, 32, 32);
assert.deepEqual([...input.slice(0, 10)], [0,0,0,0,0,1,0,0,0,0]);
assert.deepEqual([...input.slice(32 * 5, 32 * 5 + 5)], [1,0,0,0,0]);
assert.ok(Math.abs(input[(32 + 1) * 5] - 128 / 255) < 1e-6);
assert.equal(input[100], 1);
assert.throws(() => pixels.validateOutput(new Float32Array(4), 32, 32));
const colors = new Float32Array(32 * 32 * 3);
for (let i = 0; i < colors.length; i += 3) { colors[i] = 0.8; colors[i+1] = -0.2; colors[i+2] = -0.6; }
const original = new Uint8Array([0,0,0,255, 255,255,255,255, 128,128,128,255]);
const hints = pixels.input(original, 3, 1, 12, 32, 32);
const blended = pixels.blend(original, 3, 1, 12, colors, hints, 3, 1, 32, 32);
assert.deepEqual([...blended.slice(0,4)], [0,0,0,255], 'original black text survives');
assert.ok(blended[4] > blended[5] && blended[5] > blended[6], 'white skin/clothes receive model color');
assert.ok(Math.abs(blended[4]-230) <= 1, 'original white must not erase the predicted shading');
assert.ok(blended[8] > blended[9] && blended[9] > blended[10], 'RGB channels are not swapped');
// Crop padding: no white border is introduced when sampling the unpadded rectangle.
const edge = new Uint8Array([255,255,255,255]);
const cropped = pixels.blend(edge, 1, 1, 4, colors, hints, 3, 1, 32, 32);
assert.ok(cropped[0] > cropped[2]);
colors[0] = NaN;
assert.throws(() => pixels.validateOutput(colors, 32, 32));
// Nonuniform RGB/gray, alpha, odd dimensions, row stride and padded borders exercise separable interpolation.
{
  const w=19,h=23,sw=7,sh=9,mw=32,mh=32,stride=w*4+12;
  const rgba=new Uint8Array(stride*h), rgb=new Float32Array(mw*mh*3), hint=new Float32Array(mw*mh*5);
  for(let y=0;y<h;y++) for(let x=0;x<w;x++) {
    const at=y*stride+x*4; rgba.set([(x*43)%256,(y*29)%256,((x+y)*17)%256,(x*31+y*13)%256],at);
  }
  for(let i=0;i<rgb.length;i++)rgb[i]=Math.sin(i/19);
  for(let i=0;i<hint.length;i+=5)hint[i]=(i%127)/127;
  const actual=pixels.blend(rgba,w,h,stride,rgb,hint,sw,sh,mw,mh);
  const interpolate=(a,channels,c,sx,sy)=>{
    const x0=Math.floor(sx),y0=Math.floor(sy),x1=Math.min(sw-1,x0+1),y1=Math.min(sh-1,y0+1);
    const fx=sx-x0,fy=sy-y0;
    return a[(y0*mw+x0)*channels+c]*(1-fx)*(1-fy)+a[(y0*mw+x1)*channels+c]*fx*(1-fy)+
      a[(y1*mw+x0)*channels+c]*(1-fx)*fy+a[(y1*mw+x1)*channels+c]*fx*fy;
  };
  for(let y=0;y<h;y++)for(let x=0;x<w;x++){
    const sx=Math.max(0,Math.min(sw-1,(x+.5)*sw/w-.5)),sy=Math.max(0,Math.min(sh-1,(y+.5)*sh/h-.5));
    const at=y*stride+x*4,alpha=rgba[at+3]/255;
    const lum=(rgba[at]*.299+rgba[at+1]*.587+rgba[at+2]*.114)*alpha+255*(1-alpha);
    for(let c=0;c<3;c++){
      const expected=Math.round(Math.max(0,Math.min(255,(interpolate(rgb,3,c,sx,sy)+1)*127.5+lum-
        interpolate(hint,5,0,sx,sy)*255))*Math.min(1,lum/32));
      assert.ok(Math.abs(actual[(y*w+x)*4+c]-expected)<=1,`blend drift at ${x},${y},${c}`);
    }
    assert.equal(actual[(y*w+x)*4+3],255);
  }
  assert.throws(()=>pixels.blend(rgba,w,h,stride,rgb,hint,33,sh,mw,mh),/采样尺寸/);
}
const model = fs.readFileSync(new URL('../entry/src/main/resources/rawfile/comic-colorizer/alac.ms', import.meta.url));
assert.equal(crypto.createHash('sha256').update(model).digest('hex'),
  'c212815a335a006b4bbf336af1c25c6158aaeac077f35f2775af381b83fe9934');
assert.deepEqual([...pixels.interleave(new Float32Array([1,.5,0,-.5,-1,.25]),2,1)],
  [1,0,-1,.5,-.5,.25], 'dynamic NCHW output is interleaved without swapping channels');
assert.throws(()=>pixels.interleave(new Float32Array(5),2,1),/输出尺寸/);
console.log('Comic color: adaptive geometry, hint channels, stride, alpha, white-region coloring, ink, invalid output and model hash passed.');

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

// Cancellation must not tear down a VM with a pending native inference callback (verified on device).
let runningWorker, tick, isActive = true, fileOffset = 0, member = true;
class FakeWorker {
  messages = [];
  terminated = false;
  constructor() { runningWorker = this; }
  postMessage(message) { this.messages.push(message); }
  terminate() { this.terminated = true; }
}
const service = vm.createContext({ Promise, Error, Date, ArrayBuffer, Uint8Array,
  ComicColorPixels: pixels,
  AccountSessionStore: { activeMembershipSku: () => member ? 'MONTHLY' : '' },
  canIUse: () => true,
  worker: { ThreadWorker: FakeWorker },
  setInterval(callback) { tick = callback; return 1; }, clearInterval() {},
  fs: {
    OpenMode: { READ_ONLY: 0 },
    async open() { fileOffset = 0; return { fd: 1 }; }, async close() {},
    async stat() { return { size: 6 }; },
    async read(_fd, buffer, options) {
      assert.equal(options.offset, undefined, 'read uses the advancing file pointer, not a doubled offset');
      const bytes = new Uint8Array([1,2,3,4,5,6]).slice(fileOffset, fileOffset + 2);
      new Uint8Array(buffer).set(bytes); fileOffset += bytes.length; return bytes.length;
    }
  }
});
for (const file of ['ReaderComicComputeQueue.ts', 'ComicColorTypes.ts', 'ComicColorizer.ets']) {
  const source = fs.readFileSync(new URL('../entry/src/main/ets/core/reader/' + file, import.meta.url), 'utf8');
  vm.runInContext(stripTypeScriptTypes(source.replace(/^import [^;]*;\r?\n/gm, '').replace(/^export /gm, ''),
    { mode: 'strip' }), service);
}
const Colorizer = vm.runInContext('ComicColorizer', service);
const pending = Colorizer.execute({ imageBytes: new ArrayBuffer(1) }, () => isActive, () => {});
isActive = false;
tick();
assert.equal(runningWorker.terminated, false, 'native computation must finish before worker termination');
assert.equal(runningWorker.messages.at(-1).cancel, true);
runningWorker.onmessage({ data: { status: 'finishing native work' } });
assert.equal(runningWorker.terminated, false);
runningWorker.onmessage({ data: { error: '已取消着色' } });
await assert.rejects(pending, /已取消着色/);
assert.equal(runningWorker.terminated, true, 'safe completion releases the worker');
assert.deepEqual([...await Colorizer.bytes('/partial-read.png')], [1,2,3,4,5,6]);
console.log('Comic color: cooperative native cancellation and partial file reads passed.');

// Authorization is checked before reading source/cache, including when a queued job starts.
member = false;
await assert.rejects(Colorizer.colorize({}, '/must-not-read.jpg', () => true, () => {}), /会员专享/);
member = true;
let releaseQueue;
Colorizer.queue = new Promise(resolve => { releaseQueue = resolve; });
const queued = Colorizer.colorize({}, '/must-not-read-cached.jpg', () => true, () => {});
member = false;
releaseQueue();
await assert.rejects(queued, /会员专享/, 'membership may expire while waiting in the queue');
// Revocation does not kill native inference; a late output is rejected after safe completion.
member = true;
const revoked = Colorizer.execute({ imageBytes: new ArrayBuffer(1) }, () => true, () => {});
member = false;
tick();
assert.equal(runningWorker.terminated, false);
assert.equal(runningWorker.messages.at(-1).cancel, true);
runningWorker.onmessage({data:{jpeg:new ArrayBuffer(3)}});
await assert.rejects(revoked, /会员专享/);
assert.equal(runningWorker.terminated, true);
console.log('Comic color: nonmember denial, expiry while queued, and safe in-flight revocation passed.');
member = true;
Colorizer.bytes = async () => new Uint8Array([1,2,3]);
Colorizer.hash = async () => 'cached-page';
service.fs.accessSync = () => true;
service.fs.stat = async () => { member = false; return { size: 3 }; };
await assert.rejects(Colorizer.run({cacheDir:'/cache'}, '/cached.jpg', () => true, () => {}), /会员专享/,
  'expiry during async cache lookup must not return a cached color image');
console.log('Comic color: membership revoked during cache lookup is rejected.');
