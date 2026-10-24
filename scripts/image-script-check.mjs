import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { readEtsModule } from './lib/ets-module-staging.mjs';
import { imageScriptTestRuntime } from './lib/image-script-test-runtime.mjs';

const { runner, stats } = imageScriptTestRuntime();
const ctx = { url: 'https://example.com/image', index: 3, params: { offset: 1 } };
const input = new Uint8Array([99, 1, 2, 3, 88]);
const run = (body, bytes = input, context = ctx, cancel) => runner.run(`function decode(bytes,ctx){${body}}`, 'decode', bytes, context, cancel);
assert.deepEqual(Array.from(await run('return bytes.subarray(ctx.params.offset,4)')), [1,2,3]);
assert.deepEqual(Array.from(await run('return bytes.slice(1,4).buffer')), [1,2,3]);
assert.deepEqual(Array.from(await run('return new Int8Array([-1,0,1])')), [255,0,1]);
assert.equal((await run('return Promise.resolve(bytes)')).length, input.length);
assert.equal((await run('globalThis.counter=(globalThis.counter||0)+1; return new Uint8Array([counter])'))[0], 1);
assert.equal((await run('globalThis.counter=(globalThis.counter||0)+1; return new Uint8Array([counter])'))[0], 1);
for (const body of ['return "text"','return [1,2]','return new Uint16Array([1])','return undefined']) {
  await assert.rejects(run(body), /ArrayBuffer|8-bit/);
}
await assert.rejects(run('return new Uint8Array()'), /1 字节至 20 MiB/);
await assert.rejects(run('return new Uint8Array(20*1024*1024+1)'), /20 MiB/);
await assert.rejects(run('return __host("http","{}")'), /stage host/);
await assert.rejects(run('throw new Error("bad image")'), /bad image/);
await assert.rejects(run('while(true){}'), /超时/);
await assert.rejects(runner.run('function ok(){}','x);evil(',input,ctx), /函数名/);
await assert.rejects(run('return bytes',new Uint8Array(20*1024*1024+1)), /20 MiB/);
assert.equal((await run('return bytes',new Uint8Array(20*1024*1024))).length,20*1024*1024);
const key = crypto.randomBytes(32), iv = crypto.randomBytes(16);
const data = crypto.randomBytes(256);
const encrypted = crypto.createCipheriv('aes-256-cbc',key,iv);
const ciphertext = Buffer.concat([iv,encrypted.update(data),encrypted.final()]);
const decoded = await run('const iv=Array.from(bytes.subarray(0,16),x=>x.toString(16).padStart(2,"0")).join(""); return image.decrypt("AES/CBC/PKCS7Padding",bytes.subarray(16),ctx.params.key,iv);',
  ciphertext,{...ctx,params:{key:key.toString('hex')}});
assert.deepEqual(Buffer.from(decoded),data);
assert.deepEqual(Buffer.from(await run('return image.hash("SHA256",bytes)')),crypto.createHash('sha256').update(input).digest());
assert.deepEqual(Buffer.from(await run('return image.hmac("SHA256",bytes,"010203")')),crypto.createHmac('sha256',Buffer.from([1,2,3])).update(input).digest());
await assert.rejects(run('for(let i=0;i<17;i++)image.hash("SHA256",bytes); return bytes'), /budget/);
stats.delay=80;
let cancelled=false;
const active=run('return bytes');
const waiting=run('return bytes',input,ctx,()=>cancelled);
const assertWaiting=assert.rejects(waiting,/已取消/);
cancelled=true;
await Promise.all([active,assertWaiting]);
let stop=false;
const busy=run('return bytes',input,ctx,()=>stop);
setTimeout(()=>{stop=true;},10);
await assert.rejects(busy,/已取消/);
const queued=Array.from({length:4},()=>run('return bytes'));
// A full queue makes the next image wait for room (current chapter plus a preloading neighbour), not fail.
let overflowCancelled=false;
const overflowCancel=run('return bytes',input,ctx,()=>overflowCancelled);
const overflow=run('return bytes');
const assertOverflowCancel=assert.rejects(overflowCancel,/已取消/);
overflowCancelled=true;
await assertOverflowCancel;
const drained=await Promise.all([...queued,overflow]);
assert.equal(drained.length,5);
assert.ok(drained.every((bytes)=>bytes[0]===99));
stats.delay=0;
assert.equal((await run('return bytes'))[0],99);
assert.equal(stats.maxActive,1);
assert.equal(stats.created,stats.released);
assert.equal(runner.queue.length,0);
// Exercise the real host whitelist and async framework adapter, not the prelude's test double.
let clears=0;
const cryptoFramework={
  CryptoMode:{DECRYPT_MODE:0,ENCRYPT_MODE:1},
  createSymKeyGenerator:()=>({async convertKey({data}){return {data:Buffer.from(data),clearMem(){clears++;}}}}),
  createMd:algorithm=>{const hash=crypto.createHash(algorithm);return {
    async update({data}){hash.update(data);},async digest(){return {data:new Uint8Array(hash.digest())};}};},
  createMac:algorithm=>{let hash;return {async init(key){hash=crypto.createHmac(algorithm,key.data);},
    async update({data}){hash.update(data);},async doFinal(){return {data:new Uint8Array(hash.digest())};}};},
  createCipher:transformation=>{let cipher;return {async init(mode,key,params){
    const [family,block,padding]=transformation.split('|');
    const name=family.startsWith('AES')?`aes-${key.data.length*8}-${block.toLowerCase()}`:`des-ede3-${block.toLowerCase()}`;
    cipher=(mode===0?crypto.createDecipheriv:crypto.createCipheriv)(name,key.data,params?.iv.data??null);
    cipher.setAutoPadding(padding!=='NoPadding');
  },async doFinal({data}){return {data:new Uint8Array(Buffer.concat([cipher.update(data),cipher.final()]))};}};}
};
const hostContext=vm.createContext({cryptoFramework,Uint8Array});
vm.runInContext(stripTypeScriptTypes(readEtsModule('core/nativesource/NativeSourceCrypto.ts')
  .replace(/^import .*;\r?\n/gm,'').replace(/^export /gm,''),{mode:'strip'}),hostContext);
const host=vm.runInContext('NativeSourceCrypto',hostContext);
const operation=(name,bytes,options)=>host.imageOperation(name,bytes,JSON.stringify(options));
const aes={algorithm:'AES/CBC/PKCS7Padding',keyHex:key.toString('hex'),ivHex:iv.toString('hex')};
const encoded=await operation('encrypt',input,aes);
assert.deepEqual(Buffer.from(await operation('decrypt',encoded,aes)),Buffer.from(input));
assert.deepEqual(Buffer.from(await operation('hash',new Uint8Array(),{algorithm:'SHA256'})),crypto.createHash('sha256').digest());
assert.deepEqual(Buffer.from(await operation('hmac',input,{algorithm:'SHA256',keyHex:'010203'})),crypto.createHmac('sha256',Buffer.from([1,2,3])).update(input).digest());
const clearsBefore=clears;
await assert.rejects(operation('decrypt',new Uint8Array([1,2,3]),aes));
assert.equal(clears,clearsBefore+1,'keys are cleared after framework failure');
for (const options of [null,[],{algorithm:7},{...aes,keyHex:'x0'},{...aes,keyHex:'0'},
  {...aes,ivHex:''},{...aes,algorithm:'AES/ECB/NoPadding'},{...aes,algorithm:'AES/CBC/garbage'}]) {
  await assert.rejects(operation('decrypt',input,options));
}
await assert.rejects(operation('fetch',input,aes),/不支持/);
await assert.rejects(operation('hash',input,{algorithm:'unknown'}),/不支持/);
await assert.rejects(operation('hmac',input,{algorithm:'SHA256',keyHex:''}),/HMAC/);
await assert.rejects(operation('hash',new Uint8Array(20*1024*1024+1),{algorithm:'SHA256'}),/过大/);
// Actual HTTP adapter: cancellation destroys the in-flight request and propagates
// the binary size limit to the platform transport, without caching cookie headers.
let requestOptions, hanging=false, started=0, destroyed=0;
const httpContext=vm.createContext({console,Uint8Array,ArrayBuffer,setTimeout,clearTimeout,setInterval,clearInterval,
  deviceInfo:{sdkApiVersion:20},
  http:{HttpDataType:{ARRAY_BUFFER:1},HttpProtocol:{HTTP1_1:1},RequestMethod:{GET:'GET'},
    createHttp(){let rejectPending;return {
      request(_url,options){started++;requestOptions=options;
        return hanging?new Promise((_resolve,reject)=>{rejectPending=reject;}):
          Promise.resolve({responseCode:200,header:{},result:new Uint8Array([1,2,3]).buffer});},
      destroy(){destroyed++;if(rejectPending)rejectPending(new Error('destroyed'));}
    };}}
});
// Load the real HTTP dependencies too; only platform APIs are supplied by the fixture.
for (const module of ['HttpProtocolPolicy', 'HttpFinalUrlObserver', 'HttpClient']) {
  vm.runInContext(stripTypeScriptTypes(readEtsModule(`core/http/${module}.ts`)
    .replace(/^import .*;\r?\n/gm,'').replace(/^export /gm,''),{mode:'strip'}),httpContext);
}
const client=vm.runInContext('new HttpClient()',httpContext);
client.applyTlsTrust=()=>{}; client.endTransportTiming=()=>{};
client.decorateTlsError=(_url,error)=>error;
let abort=false;
const request={url:'https://example.com/a',method:'GET',headers:{},useCookieJar:false,cancelCheck:()=>abort};
assert.equal((await client.executeBinary(request,1024)).success,true);
assert.equal(requestOptions.maxLimit,1024);
assert.equal(client.activeClients.size,0);
hanging=true;
const pendingHttp=client.executeBinary(request,1024);
setTimeout(()=>{abort=true;},5);
const cancelledResponse=await pendingHttp;
assert.equal(cancelledResponse.error,'书源请求已取消');
assert.equal(client.activeClients.size,0); assert(destroyed>=2);
const startedBefore=started;
assert.equal((await client.executeBinary(request,1024)).error,'书源请求已取消');
assert.equal(started,startedBefore);
console.log('image-script-check: byte views, context, helpers, isolation, failures, limits, queue and cancellation passed (Node session adapter)');
