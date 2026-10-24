import assert from 'node:assert/strict';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { readEtsModule } from './lib/ets-module-staging.mjs';

function fixture() {
  const loaded = []; let stopped = 0;
  const context = vm.createContext({ console, setTimeout, clearTimeout });
  vm.runInContext(stripTypeScriptTypes(readEtsModule('core/book/WebBookFetchRuntime.ts')
    .replace(/^import .*;\r?\n/gm, '').replace(/^export /gm, ''), {mode:'strip'}), context);
  const Runtime = vm.runInContext('WebBookFetchRuntime', context);
  const runtime = new Runtime();
  const controller = () => ({loadUrl: url => loaded.push(url), stop: () => stopped++});
  return {runtime, loaded, controller, stopped: () => stopped};
}
const req = (name, deadlineAt) => ({url:'https://example.org/' + name, method:'GET', headers:{}, timeoutMs:5000, deadlineAt});
{
  const f = fixture(); const controller = f.controller(); f.runtime.attach(controller);
  const active = f.runtime.fetch(req('active'));
  const queued = await f.runtime.fetch(req('queued', Date.now()+80));
  assert.match(queued.error, /2300028/);
  assert.deepEqual(f.loaded, ['https://example.org/active'], 'expired queued page must never navigate');
  f.runtime.detach(controller); await active;
}
{
  const f = fixture(); const first = f.controller(); const second = f.controller(); f.runtime.attach(first);
  const start = Date.now(); const pending = f.runtime.fetch(req('migrate', start+120));
  await new Promise(resolve => setTimeout(resolve, 40)); f.runtime.attach(second);
  const result = await pending;
  assert.match(result.error, /2300028/);
  assert.ok(Date.now()-start < 600, 'moving to a new controller must not reset the request deadline');
  assert.ok(f.stopped() > 0, 'timed-out active navigation is stopped');
  f.runtime.detach(second);
}
{
  const f = fixture(); const controller = f.controller(); f.runtime.attach(controller);
  assert.match((await f.runtime.fetch(req('expired', Date.now()-1))).error, /2300028/);
  assert.equal(f.loaded.length, 0);
  const pending = f.runtime.fetch(req('success', Date.now()+1000));
  f.runtime.finishActive({url:'https://example.org/success', statusCode:200, success:true, body:'ok', headers:{}});
  assert.equal((await pending).body, 'ok'); f.runtime.detach(controller);
}
console.log('web-request-deadline-check: queue expiry, controller migration, active stop, expired requests and completion passed');
