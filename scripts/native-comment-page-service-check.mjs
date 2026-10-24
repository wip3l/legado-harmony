import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
const code=fs.readFileSync(new URL('../harmony-book-source-engine/sourceengine/src/main/ets/core/nativesource/NativeSourceService.ts',import.meta.url),'utf8');
const start=code.indexOf('  static async getCommentPage(');
assert(start>=0);
const method=code.slice(start,code.indexOf('\n  }',start)+4);
function harness() {
  let now=1000,resolve,reject,cancelled=false,host,check;
  const timers=new Map();
  const context=vm.createContext({Error,Promise,Date:{now:()=>now},
    setTimeout:(fn,ms)=>{timers.set(1,{fn,ms});return 1;},clearTimeout:id=>timers.delete(id),
    NativeHost:class {constructor(_source,_http,cancel,max){host=this;this.cancel=cancel;this.max=max;}limitCommentPage(deadline){this.deadline=deadline;}},
    NativeSourceRunner:class {setCancelCheck(fn){check=fn;return this;}setCredential(){return this;}
      commentPage(){return new Promise((r,j)=>{resolve=r;reject=j;});}}
  });
  const service=vm.runInContext(stripTypeScriptTypes(`class NativeSourceService {${method}}
    NativeSourceService.definitionOf=()=>({}); NativeSourceService.storedVars=()=>({});
    NativeSourceService.credential=()=>({}); NativeSourceService.bookInput=()=>({}); NativeSourceService;`,{mode:'strip'}),context);
  const work=service.getCommentPage({}, {}, {}, {url:'/chapter',title:'title',index:1},'action',()=>cancelled);
  return {work,timers,host,check,resolve:val=>resolve(val),reject:error=>reject(error),cancel:()=>{cancelled=true;},advance:ms=>{now+=ms;}};
}
{
  const h=harness();assert.equal(h.host.max,1024*1024);assert.equal(h.host.deadline,16000);assert.equal(h.timers.get(1).ms,15000);
  h.resolve({html:'ok'});assert.equal((await h.work).html,'ok');assert.equal(h.timers.size,0);assert(h.check(),'completed operation stops any leftover work');
}
{
  const h=harness();h.advance(15000);h.timers.get(1).fn();await assert.rejects(h.work,/15 秒/);
  assert(h.host.cancel());assert.equal(h.timers.size,0);h.resolve({html:'late'});
}
{
  const h=harness();h.cancel();h.resolve({html:'late'});await assert.rejects(h.work,/取消/);assert(h.check());
}
{
  const h=harness();h.advance(15001);h.resolve({html:'late before timer callback'});await assert.rejects(h.work,/15 秒/);
}
{
  const h=harness();h.reject(Error('bad rules'));await assert.rejects(h.work,/bad rules/);assert(h.check());assert.equal(h.timers.size,0);
}
console.log('native-comment-page-service-check: generation deadline, cancellation, late completion, response cap and timer cleanup passed');
