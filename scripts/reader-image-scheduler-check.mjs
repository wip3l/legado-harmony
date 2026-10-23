import assert from 'node:assert/strict';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { readEtsModule } from './lib/ets-module-staging.mjs';

// 全局正文图片名额：总数 4；当前章有图时后台最多 1、没有时最多 2；优先级每次分配时重读；排队中取消会及时放掉。
const CANCELLED = '书源请求已取消';
const context = vm.createContext({ setInterval, clearInterval, setTimeout, Promise, Error,
  HttpClient: { CANCELLED_ERROR: CANCELLED } });
const code = stripTypeScriptTypes(readEtsModule('core/book/ReaderImageScheduler.ts')
  .replace(/^import .*;\r?\n/gm, '').replace(/^export /gm, ''), { mode: 'strip' });
vm.runInContext(code, context);
const Scheduler = vm.runInContext('ReaderImageScheduler', context);
const FG = () => Scheduler.FOREGROUND;
const BG = () => Scheduler.BACKGROUND;
const never = () => false;

function deferred() {
  let resolve;
  const promise = new Promise((r) => { resolve = r; });
  return { promise, resolve };
}
const tick = () => new Promise((resolve) => setTimeout(resolve, 0));

// 后台 3 张先提交、当前章 6 张随后提交：空闲时后台先拿 2 个，当前章拿其余名额，之后空出的名额都先给当前章。
{
  let active = 0, maxActive = 0, activeBg = 0, maxBg = 0;
  const started = [];
  const gates = new Map();
  const job = (name, bg) => async () => {
    started.push(name);
    active++; maxActive = Math.max(maxActive, active);
    if (bg) { activeBg++; maxBg = Math.max(maxBg, activeBg); }
    const gate = deferred();
    gates.set(name, gate);
    await gate.promise;
    active--;
    if (bg) activeBg--;
    return name;
  };
  const all = [];
  for (let i = 0; i < 3; i++) all.push(Scheduler.run(BG, never, job(`b${i}`, true)));
  for (let i = 0; i < 6; i++) all.push(Scheduler.run(FG, never, job(`f${i}`, false)));
  await tick();
  assert.deepEqual(started, ['b0', 'b1', 'f0', 'f1']);
  gates.get('b0').resolve();
  await tick(); await tick();
  assert.equal(started[4], 'f2', '当前章还有图时，后台空出的名额先给当前章');
  for (let round = 0; round < 12; round++) {
    for (const [name, gate] of gates) { gate.resolve(); gates.delete(name); }
    await tick(); await tick();
  }
  const results = await Promise.all(all);
  assert.equal(results.length, 9);
  assert.equal(maxActive, 4);
  assert.equal(maxBg, 2);
}

// 当前章有图在下载时后台只得 1 个名额；当前章做完后后台增加到 2 个。
{
  const fgGates = [];
  const fg = [];
  for (let i = 0; i < 4; i++) {
    fg.push(Scheduler.run(FG, never, async () => { const gate = deferred(); fgGates.push(gate); await gate.promise; }));
  }
  let activeBg = 0;
  const bgGates = [];
  const bg = [];
  for (let i = 0; i < 3; i++) {
    bg.push(Scheduler.run(BG, never, async () => {
      activeBg++; const gate = deferred(); bgGates.push(gate); await gate.promise; activeBg--;
    }));
  }
  await tick();
  assert.equal(activeBg, 0, '名额被当前章占满');
  fgGates.shift().resolve();
  await tick(); await tick();
  assert.equal(activeBg, 1, '当前章还在下载，后台只得 1 个');
  fgGates.shift().resolve();
  await tick(); await tick();
  assert.equal(activeBg, 1, '当前章还在下载，后台不再增加');
  fgGates.splice(0).forEach((gate) => gate.resolve());
  await tick(); await tick();
  assert.equal(activeBg, 2, '当前章做完后后台可用 2 个');
  await Promise.all(fg);
  while (bgGates.length || activeBg) { bgGates.splice(0).forEach((gate) => gate.resolve()); await tick(); await tick(); }
  await Promise.all(bg);
}

// 预加载的章节变成当前章：优先级每次分配都重读，剩下的图片不再受后台 1 个名额的限制。
{
  let current = false;
  const priority = () => (current ? Scheduler.FOREGROUND : Scheduler.BACKGROUND);
  let active = 0, maxActive = 0;
  const gates = [];
  const tasks = [];
  for (let i = 0; i < 5; i++) {
    tasks.push(Scheduler.run(priority, never, async () => {
      active++; maxActive = Math.max(maxActive, active);
      const gate = deferred(); gates.push(gate); await gate.promise; active--;
    }));
  }
  await tick();
  assert.equal(active, 2, '后台且当前章空闲时占 2 个名额');
  current = true;
  gates.shift().resolve();
  await tick(); await tick();
  assert.equal(active, 4, '变成当前章后用满 4 个名额');
  while (gates.length || active) { gates.splice(0).forEach((gate) => gate.resolve()); await tick(); await tick(); }
  await Promise.all(tasks);
  assert.equal(maxActive, 4);
}

// 名额全满时排队的任务被取消：不等慢图结束，定时清理就以取消错误结束，任务本身不执行。
{
  const blockers = [];
  const running = [];
  for (let i = 0; i < 4; i++) {
    running.push(Scheduler.run(FG, never, async () => { const gate = deferred(); blockers.push(gate); await gate.promise; }));
  }
  await tick();
  let cancelled = false;
  let executed = false;
  const queued = Scheduler.run(FG, () => cancelled, async () => { executed = true; });
  cancelled = true;
  const startedAt = Date.now();
  await assert.rejects(queued, (e) => e.message === CANCELLED);
  assert.ok(Date.now() - startedAt < 1000, '排队中取消应在一次清理间隔内结束');
  assert.equal(executed, false);
  blockers.forEach((gate) => gate.resolve());
  await Promise.all(running);
  await assert.rejects(Scheduler.run(FG, () => true, async () => 1), (e) => e.message === CANCELLED);
}

// 任务抛错也要归还名额。
{
  await assert.rejects(Scheduler.run(FG, never, async () => { throw new Error('boom'); }), /boom/);
  const values = await Promise.all([1, 2, 3, 4, 5].map((n) => Scheduler.run(FG, never, async () => n)));
  assert.deepEqual(values, [1, 2, 3, 4, 5]);
}

console.log('reader-image-scheduler-check: ok');
process.exit(0);
