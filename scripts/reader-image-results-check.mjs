import assert from 'node:assert/strict';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { readEtsModule } from './lib/ets-module-staging.mjs';

// 渐进加载的图片结果登记：同图去重、被取消后可重来、订阅通知、可见计数、整章补完后换成最终来源。
const context = vm.createContext({ Promise, Error, Map, encodeURIComponent, decodeURIComponent, setInterval, clearInterval,
  HttpClient: { CANCELLED_ERROR: '书源请求已取消' } });
for (const file of ['core/book/ReaderImageMarker.ts', 'core/book/ReaderImageScheduler.ts', 'core/book/ReaderImageResults.ts']) {
  vm.runInContext(stripTypeScriptTypes(readEtsModule(file)
    .replace(/^import .*;\r?\n/gm, '').replace(/^export /gm, ''), { mode: 'strip' }), context);
}
const Marker = vm.runInContext('ReaderImageMarker', context);
const Results = vm.runInContext('ReaderImageResults', context);
const Scheduler = vm.runInContext('ReaderImageScheduler', context);
const CANCELLED = new Error('书源请求已取消');

function deferred() {
  let resolve, reject;
  const promise = new Promise((ok, fail) => { resolve = ok; reject = fail; });
  return { promise, resolve, reject };
}

// 待加载标记只在内存正文里出现，能识别出原始值。
const raw = 'https://img.example.com/1.jpg,{"headers":{"Referer":"https://a/"},"imageIndex":0}';
const marker = Marker.create(Marker.pendingSource(raw));
assert.equal(Marker.pendingRaw(Marker.parse(marker).source), raw);
assert.equal(Marker.hasPending(`前文\n\n${marker}`), true);
assert.equal(Marker.hasPending(Marker.create('/cache/a.jpg')), false);
assert.equal(Marker.hasFailure(marker), false);

// 同一张图处理中再次提交：只跑一次，订阅者拿到结果。
{
  let runs = 0;
  const gate = deferred();
  const seen = [];
  const unsubscribe = Results.subscribe(raw, (source) => seen.push(source));
  const first = Results.load(raw, async () => { runs++; return await gate.promise; });
  const second = Results.load(raw, async () => { runs++; return 'never'; });
  assert.equal(Results.isAlive(raw), true);
  gate.resolve('/cache/1.jpg');
  await Promise.all([first, second]);
  assert.equal(runs, 1);
  assert.deepEqual(seen, ['/cache/1.jpg']);
  assert.equal(Results.current(raw), '/cache/1.jpg');
  unsubscribe();
}

// 前一次被取消、没有结果：后来的提交自己再处理一次；取消本身不让 load 失败。
{
  const key = 'https://img.example.com/2.jpg';
  const gate = deferred();
  const cancelled = Results.load(key, async () => await gate.promise);
  const retry = Results.load(key, async () => '/cache/2.jpg');
  gate.reject(CANCELLED);
  await cancelled;
  await retry;
  assert.equal(Results.current(key), '/cache/2.jpg');
}

// 整章补完：等进行中的图片，换成本地路径或失败来源；有图片被取消就返回空串。
{
  const a = 'https://img.example.com/a.jpg';
  const b = 'https://img.example.com/b.jpg';
  const text = [a, b].map((value) => Marker.create(Marker.pendingSource(value))).join('\n\n');
  const gateA = deferred();
  Results.load(a, async () => await gateA.promise);
  Results.load(b, async () => Marker.failureSource('下载失败'));
  const finalizing = Results.finalize(text);
  gateA.resolve('/cache/a.jpg');
  const finalText = await finalizing;
  assert.equal(Marker.hasPending(finalText), false);
  assert.ok(finalText.includes(Marker.create('/cache/a.jpg')));
  assert.equal(Marker.hasFailure(finalText), true);

  const c = 'https://img.example.com/c.jpg';
  const gateC = deferred();
  Results.load(c, async () => await gateC.promise);
  const pendingC = Results.finalize(Marker.create(Marker.pendingSource(c)));
  gateC.reject(CANCELLED);
  assert.equal(await pendingC, '');
  assert.equal(Results.isAlive(c), false, '被取消且没有结果的图片不再算可等');
  assert.equal(await Results.finalize('纯文本'), '纯文本');
}

// 可见计数：屏幕上的图片登记后算可见，全部离开后恢复。
{
  const key = 'https://img.example.com/v.jpg';
  Results.load(key, () => new Promise(() => {}));
  Results.setVisible(key, true);
  Results.setVisible(key, true);
  assert.equal(Results.isVisible(key), true);
  Results.setVisible(key, false);
  assert.equal(Results.isVisible(key), true);
  Results.setVisible(key, false);
  assert.equal(Results.isVisible(key), false);
  Results.setVisible(key, false);
  assert.equal(Results.isVisible(key), false, '计数不会减成负数');
}

// 调度优先级：屏幕上 > 屏幕附近 > 本章默认；离开后回到默认。
{
  const key = 'https://img.example.com/p.jpg';
  const base = () => Scheduler.FOREGROUND;
  Results.load(key, () => new Promise(() => {}));
  assert.equal(Results.priority(key, base), Scheduler.FOREGROUND);
  Results.setNear(key, true);
  assert.equal(Results.priority(key, base), Scheduler.NEAR);
  Results.setVisible(key, true);
  assert.equal(Results.priority(key, base), Scheduler.VISIBLE);
  Results.setVisible(key, false);
  Results.setNear(key, false);
  assert.equal(Results.priority(key, () => Scheduler.BACKGROUND), Scheduler.BACKGROUND);
  assert.ok(Scheduler.VISIBLE < Scheduler.NEAR && Scheduler.NEAR < Scheduler.FOREGROUND);
}

console.log('reader-image-results-check: ok');
