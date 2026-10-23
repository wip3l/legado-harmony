import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { readEtsModule } from './lib/ets-module-staging.mjs';
import { loadNativeSourceModules } from '../harmony-book-source-engine/scripts/lib/load-native-source-modules.mjs';
import { imageScriptTestRuntime } from './lib/image-script-test-runtime.mjs';

const mods = await loadNativeSourceModules();
try {
  const files = new Map();
  let decrypts = 0;
  const budget = { touched: 0, writes: 0 };
  const scriptRuntime = imageScriptTestRuntime();
  const sandbox = vm.createContext({
    console, Uint8Array, ArrayBuffer,
    util: { TextEncoder: class { encodeInto(text) { return new TextEncoder().encode(text); } },
      Base64Helper: class { decodeSync(text) {
        if (!/^[A-Za-z0-9+/]*={0,2}$/.test(text)) throw new Error('bad base64');
        return new Uint8Array(Buffer.from(text, 'base64'));
      } } },
    NativeSourceSpec: mods.NativeSourceSpec,
    NativeImageScriptRunner: scriptRuntime.runner,
    digestHashHex: (algorithm, text) => crypto.createHash(algorithm).update(text).digest('hex'),
    HttpClient: { CANCELLED_ERROR: '书源请求已取消' },
    AppStorage: { get: () => '/cache' },
    ReaderCacheBudget: { touchComicFile() { budget.touched++; }, noteComicWrite() { budget.writes++; } },
    fs: { OpenMode: { CREATE: 1, WRITE_ONLY: 2, TRUNC: 4 }, mkdirSync() {},
      accessSync: path => files.has(path), openSync: path => ({ fd: path }), closeSync() {},
      writeSync: (fd, data) => files.set(fd, Buffer.from(data)) },
    NativeSourceCrypto: {
      decryptBytes() { throw new Error('Image pipeline must use asynchronous crypto'); },
      async decryptBytesAsync(algorithm, input, keyHex, ivHex) {
        decrypts++;
        const [family, mode, padding] = algorithm.toLowerCase().split('/');
        const key = Buffer.from(keyHex, 'hex');
        const cipherName = family === 'aes' ? `aes-${key.length * 8}-${mode}` : `des-ede3-${mode}`;
        const cipher = crypto.createDecipheriv(cipherName, key, mode === 'ecb' ? null : Buffer.from(ivHex, 'hex'));
        if (padding === 'nopadding') cipher.setAutoPadding(false);
        return new Uint8Array(Buffer.concat([cipher.update(input), cipher.final()]));
      }
    }
  });
  for (const file of ['core/nativesource/SourceImageDecoder.ts', 'core/book/ComicImagePipeline.ts',
    'core/book/ReaderImageMarker.ts']) {
    const code = stripTypeScriptTypes(readEtsModule(file).replace(/^import .*;\r?\n/gm, '').replace(/^export /gm, ''), {mode:'strip'});
    vm.runInContext(code, sandbox);
  }
  const { pipeline, decoder, marker } = vm.runInContext(
    '({pipeline:ComicImagePipeline,decoder:SourceImageDecoder,marker:ReaderImageMarker})',sandbox);
  const png = Buffer.from('89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000b49444154789c636000020000050001a5f645400000000049454e44ae426082','hex');
  const source = {bookSourceUrl:'https://example.com',contentRule:{imageDecode:''}};
  let downloads = 0;
  let response = png;
  const requests = [];
  const http = { async executeBinary(request,limit) {
    downloads++; requests.push({request,limit});
    return {success:true,statusCode:200,data:response};
  } };
  const raw = (name, decode, headers = {}) => `https://example.com/${name}.jpg,${JSON.stringify({decode,headers})}`;
  const encrypt = (plain,key,iv,mode='cbc') => {
    const cipher=crypto.createCipheriv(`aes-${key.length*8}-${mode}`,key,iv);
    return Buffer.concat([cipher.update(plain),cipher.final()]);
  };
  for(const length of [16,24,32]) {
    const key=crypto.randomBytes(length);
    for(let index=0;index<3;index++) {
      const iv=crypto.randomBytes(16);
      if(index===0) iv.write('BM'); // A random IV is not necessarily a BMP header.
      response=Buffer.concat([iv,encrypt(png,key,iv)]);
      const decode={algorithm:'AES/CBC/PKCS7Padding',key:key.toString('hex'),iv:'',ivPrefixBytes:16};
      const url=raw(`prefix-${length}-${index}`,decode,{'Accept-Language':'zh-CN'});
      const output=await pipeline.materialize(http,source,url,true);
      assert.deepEqual(files.get(output),png);
      assert.equal(requests.at(-1).request.headers['Accept-Language'],'zh-CN');
      assert.equal(requests.at(-1).limit,20*1024*1024);
      const before=downloads;
      assert.equal(await pipeline.materialize(http,source,url,true),output);
      assert.equal(downloads,before,'cache avoids another download/decrypt');
    }
  }
  const key=crypto.randomBytes(32),iv=crypto.randomBytes(16);
  const fixed={algorithm:'AES/CBC/PKCS5Padding',key:key.toString('hex'),iv:iv.toString('hex')};
  response=encrypt(png,key,iv);
  assert.deepEqual(files.get(await pipeline.materialize(http,source,raw('fixed',fixed))),png);
  response=encrypt(png,key,iv,'ctr');
  assert.deepEqual(files.get(await pipeline.materialize(http,source,raw('ctr',{...fixed,algorithm:'AES/CTR/NoPadding'}))),png);
  const tripleKey=crypto.randomBytes(24),tripleIv=crypto.randomBytes(8);
  const tripleCipher=crypto.createCipheriv('des-ede3-cbc',tripleKey,tripleIv);
  response=Buffer.concat([tripleCipher.update(png),tripleCipher.final()]);
  assert.deepEqual(files.get(await pipeline.materialize(http,source,raw('3des',{algorithm:'3DES/CBC/PKCS5Padding',key:tripleKey.toString('hex'),iv:tripleIv.toString('hex')}))),png);

  const prefix={...fixed,iv:'',ivPrefixBytes:16};
  for(const [name,bytes,ext] of [['png',png,'.png'], ['heic',Buffer.concat([Buffer.from([0,0,0,24]),Buffer.from('ftypheic'),Buffer.alloc(20)]),'.heic']]) {
    const before=decrypts; response=bytes;
    const result=await pipeline.materialize(http,source,raw(`plain-${name}`,prefix));
    assert.equal(decrypts,before,'ordinary images must bypass decryption');
    assert(result.endsWith(ext)); assert.deepEqual(files.get(result),bytes);
  }
  // A non-zero byteOffset must never leak adjacent bytes into the image file.
  const padded=Buffer.concat([Buffer.from('junk'),png,Buffer.from('trailing')]);
  response=padded.subarray(4,4+png.length);
  assert.deepEqual(files.get(await pipeline.materialize(http,source,raw('view',prefix))),png);
  for(const [name,bytes] of [['truncated',Buffer.alloc(17)],['not-image',Buffer.concat([iv,encrypt(Buffer.from('not an image'),key,iv)])]]) {
    response=bytes;
    await assert.rejects(pipeline.materialize(http,source,raw(name,prefix)),/正文图片解密失败/);
  }
  for(const decode of [{...prefix,ivPrefixBytes:8},{...prefix,iv:fixed.iv},{...prefix,algorithm:'3DES/CBC/PKCS5Padding'}]) {
    await assert.rejects(pipeline.materialize(http,source,raw('invalid',decode)),/解密配置无效/);
  }
  await assert.rejects(pipeline.materialize({executeBinary:async()=>({success:false,statusCode:403,data:new Uint8Array()})},source,raw('403',prefix)),/HTTP 403/);
  response=Buffer.concat([iv,encrypt(png,key,iv)]);
  await assert.rejects(pipeline.materialize(http,source,raw('wrong-key',{...prefix,key:'00'.repeat(32)})),/正文图片解密失败/);
  response=png;
  const original=await pipeline.materialize(http,source,raw('identity',prefix,{Referer:'https://a.example'}));
  const changed=await pipeline.materialize(http,source,raw('identity',fixed,{Referer:'https://a.example'}));
  const headersChanged=await pipeline.materialize(http,source,raw('identity',prefix,{Referer:'https://b.example'}));
  assert.notEqual(original,changed); assert.notEqual(original,headersChanged);
  await assert.rejects(decoder.decodeAsync(new Uint8Array(20*1024*1024+1),{...prefix,keyEncoding:'hex'},20*1024*1024),/byte limit/);
  // data: images become cache files without a download, and imageDecode applies to them as well.
  const beforeData=downloads;
  const dataUrl=`data:image/png;base64,${png.toString('base64')}`;
  const dataPath=await pipeline.materialize(http,source,dataUrl,true);
  assert(dataPath.startsWith('/cache/comic_images/') && dataPath.endsWith('.png'),dataPath);
  assert.deepEqual(files.get(dataPath),png);
  assert.equal(await pipeline.materialize(http,source,dataUrl,true),dataPath,'data: cache hit');
  const urlSafe=`data:image/png;base64,${png.toString('base64url')}`;
  assert.deepEqual(files.get(await pipeline.materialize(http,source,urlSafe,true)),png);
  const encryptedData=`data:image/jpeg;base64,${encrypt(png,key,iv).toString('base64')},${JSON.stringify({decode:fixed})}`;
  assert.deepEqual(files.get(await pipeline.materialize(http,source,encryptedData,true)),png);
  assert.equal(downloads,beforeData,'data: images never hit the network');
  await assert.rejects(pipeline.materialize(http,source,'data:image/png;base64,',true),/没有数据/);
  await assert.rejects(pipeline.materialize(http,source,'data:image/png;base64,@@@@',true),/Base64/);
  const svg=`data:image/svg+xml;base64,${Buffer.from('<svg/>').toString('base64')}`;
  assert.equal(await pipeline.materialize(http,source,svg,true),svg,'unrecognised embedded formats stay inline');
  // A failed image becomes a marker that carries its reason; such chapters are detected before caching.
  const failed=marker.create(marker.failureSource('正文图片解密失败：密钥为空 [x]'));
  assert.equal(marker.failureReason(marker.parse(failed).source),'正文图片解密失败：密钥为空 [x]');
  assert.ok(marker.hasFailure(`前文

${failed}

后文`));
  assert.ok(!marker.hasFailure(marker.create(dataPath)));
  assert.equal(marker.failureReason(dataPath),'');
  const definition = {nativeSource:1,name:'script',url:source.bookSourceUrl,type:'comic',
    search:{url:'/search',list:'$.items[*]',fields:{name:'$.name',bookUrl:'$.url'}},
    js:'function decodeImage(bytes,ctx){return bytes.subarray(ctx.params.offset)}',
    content:{images:'= data.images',imageDecode:{script:'decodeImage',params:{offset:4}}}};
  const scripted = {...source,jsLib:mods.NativeSourceSpec.pack(definition)};
  const decodeScript = {script:'decodeImage',params:{offset:4},processPlainImages:false};
  const scriptUrl = raw('script',decodeScript);
  response=Buffer.concat([Buffer.from('junk'),png]);
  const first = await pipeline.materialize(http,scripted,scriptUrl,true);
  assert.deepEqual(files.get(first),png);
  const count=downloads;
  assert.equal(await pipeline.materialize(http,scripted,scriptUrl,true),first);
  assert.equal(downloads,count);
  definition.js+='\n// new version'; scripted.jsLib=mods.NativeSourceSpec.pack(definition);
  const updated=await pipeline.materialize(http,scripted,scriptUrl,true);
  assert.notEqual(updated,first);
  const indexed=await pipeline.materialize(http,scripted,scriptUrl,true,()=>false,1);
  assert.notEqual(indexed,updated);
  const changedHeaders=await pipeline.materialize(http,scripted,raw('script',decodeScript,{Referer:'https://new.example'}),true);
  assert.notEqual(changedHeaders,updated);
  response=Buffer.concat([Buffer.from('junk!'),png]);
  const changedParams=await pipeline.materialize(http,scripted,raw('script',{...decodeScript,params:{offset:5}}),true);
  assert.notEqual(changedParams,updated); assert.deepEqual(files.get(changedParams),png);
  response=png;
  const beforeScripts=scriptRuntime.stats.created;
  await pipeline.materialize(http,scripted,raw('plain-script',decodeScript),true);
  assert.equal(scriptRuntime.stats.created,beforeScripts);
  definition.content.imageDecode.processPlainImages=true;
  definition.js='function decodeImage(bytes,ctx){return bytes}'; scripted.jsLib=mods.NativeSourceSpec.pack(definition);
  await pipeline.materialize(http,scripted,raw('plain-process',{...decodeScript,processPlainImages:true}),true);
  assert.equal(scriptRuntime.stats.created,beforeScripts+1);
  await assert.rejects(pipeline.materialize(http,scripted,scriptUrl,true),/已变更/);
  await assert.rejects(pipeline.materialize(http,source,scriptUrl,true),/当前书源定义/);
  await assert.rejects(pipeline.materialize(http,scripted,raw('bad-script',{script:5}),true),/函数名/);
  await assert.rejects(pipeline.materialize(http,scripted,raw('bad-params',{script:'decodeImage',params:[]}),true),/params/);
  await assert.rejects(pipeline.materialize(http,scripted,raw('mixed',{...decodeScript,algorithm:'AES/CBC/PKCS7Padding'}),true),/混用/);
  definition.js='function decodeImage(bytes,ctx){return new Uint8Array([1,2,3])}'; scripted.jsLib=mods.NativeSourceSpec.pack(definition);
  await assert.rejects(pipeline.materialize(http,scripted,raw('bad-output',{...decodeScript,processPlainImages:true}),true),/不是支持的图片/);
  let stop=false;
  const cancelHttp={executeBinary:async()=>{stop=true;return {success:true,statusCode:200,data:response}}};
  const fileCount=files.size;
  await assert.rejects(pipeline.materialize(cancelHttp,scripted,raw('cancel',decodeScript),true,()=>true),/已取消/);
  definition.content.imageDecode.processPlainImages=false; scripted.jsLib=mods.NativeSourceSpec.pack(definition);
  await assert.rejects(pipeline.materialize(cancelHttp,scripted,raw('cancel',decodeScript),true,()=>stop),/已取消/);
  assert.equal(files.size,fileCount);
  assert.ok(budget.writes > 0, 'new cache files must notify the comic cache budget');
  assert.ok(budget.touched > 0, 'cache hits must refresh the file usage time');
  console.log('comic-image-pipeline-check: per-image IVs, AES 128/192/256, fixed IV/CTR/3DES, plaintext/HEIF, data: images, cache identity, failure markers and failures passed');
} finally { mods.cleanup(); }
