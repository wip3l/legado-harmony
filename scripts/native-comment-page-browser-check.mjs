// Chromium verifies the generated document's CSP and injection. ArkWeb integration still requires a device.
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import fs from 'node:fs';
import { NativeCommentPage } from '../harmony-book-source-engine/sourceengine/src/main/ets/core/nativesource/NativeCommentPage.ts';
const require = createRequire(import.meta.url);
const { chromium } = require('playwright');
for (const name of ['HTTP_PROXY','HTTPS_PROXY','ALL_PROXY','http_proxy','https_proxy','all_proxy']) delete process.env[name];
const browser = await chromium.launch({headless:true,args:['--no-proxy-server'],
  ...(fs.existsSync(chromium.executablePath()) ? {} : {channel:'msedge'})});
try {
  const context = await browser.newContext({viewport:{width:430,height:650}});
  const outbound=[];
  await context.route('**/*',async route=>{outbound.push(route.request().url());await route.abort();});
  await context.addCookies([{name:'secret',value:'not-for-inline-pages',domain:'example.com',path:'/'}]);
  const page=await context.newPage();
  const result=new NativeCommentPage();
  result.dataJson=JSON.stringify({text:'</script><script>window.injected=true</script>中文😀'});
  result.html=`<style>body{font:18px sans-serif;padding:20px}button{padding:12px}</style>
    <h2>内联评论预览</h2><p id="data"></p><button id="local" onclick="this.textContent='本地交互成功'">测试本地交互</button>
    <script>
    window.violations=[];addEventListener('securitypolicyviolation',e=>violations.push(e.violatedDirective));
    document.getElementById('data').textContent=window.__NATIVE_PAGE_DATA__.text;
    window.fetchResult='pending';fetch('https://network.invalid/read').then(()=>fetchResult='unexpected',()=>fetchResult='blocked');
    try{window.savedCookie=document.cookie}catch(e){window.savedCookie='inaccessible'}
    try{window.stored=localStorage.getItem('secret')}catch(e){window.stored='inaccessible'}
    </script>
    <meta http-equiv="Content-Security-Policy" content="default-src * 'unsafe-inline'">
    <script src="https://network.invalid/script.js"></script>
    <link rel="stylesheet" href="https://network.invalid/style.css">
    <img src="https://network.invalid/image.png"><iframe src="https://network.invalid/frame"></iframe>
    <object data="https://network.invalid/object"></object>`;
  await page.setContent(NativeCommentPage.document(result));
  await page.waitForFunction(()=>window.__NATIVE_PAGE_READY__===true);
  const frame=page.frames().find(f=>f.parentFrame()===page.mainFrame());
  assert(frame,'sandboxed source frame exists');
  await frame.waitForFunction(()=>window.fetchResult==='blocked' && window.violations.length>=4);
  assert.equal(await frame.locator('#data').textContent(),JSON.parse(result.dataJson).text);
  assert.equal(await frame.evaluate(()=>window.injected),undefined);
  assert(['','inaccessible'].includes(await frame.evaluate(()=>window.savedCookie)));
  assert.equal(await frame.evaluate(()=>window.stored),'inaccessible');
  assert.equal(await frame.evaluate(()=>typeof window.LegadoCommentHost),'undefined');
  assert.equal(await frame.evaluate(()=>typeof window.RTCPeerConnection),'undefined');
  assert.equal(await frame.evaluate(()=>Object.getOwnPropertyDescriptor(window,'RTCPeerConnection').configurable),false);
  assert.equal(await frame.evaluate(()=>{try{return typeof parent.RTCPeerConnection}catch(_){return 'blocked'}}),'blocked');
  assert.equal(await frame.evaluate(()=>{
    const child=document.createElement('iframe');document.body.appendChild(child);
    try{return typeof child.contentWindow.RTCPeerConnection}catch(_){return 'blocked'}
  }),'blocked','blank-frame constructor bypass must be blocked by an opaque sandbox origin');
  assert.deepEqual(outbound,[],'CSP rejects external resources before a network request');
  await frame.locator('#local').click();
  assert.equal(await frame.locator('#local').textContent(),'本地交互成功');
  const example=JSON.parse(fs.readFileSync(new URL('../harmony-book-source-engine/docs/examples/native-inline-comments.json',import.meta.url),'utf8'));
  const demo=new NativeCommentPage(); demo.html=example.content.comments.page.html;
  demo.dataJson=JSON.stringify({paragraph:'第一段：点击段尾气泡。',count:2});
  await page.setContent(NativeCommentPage.document(demo));
  const demoFrame=page.frameLocator('#native-comment-content');
  assert.equal(await demoFrame.locator('#count').textContent(),'评论数：2');
  await demoFrame.getByRole('button',{name:'测试本地交互'}).click();
  assert.equal(await demoFrame.getByRole('button').textContent(),'已点击');
  fs.mkdirSync(new URL('../.codex_tmp/',import.meta.url),{recursive:true});
  await page.screenshot({path:new URL('../.codex_tmp/inline-comment-preview.png',import.meta.url).pathname.replace(/^\/([A-Z]:)/i,'$1')});
  console.log('native-comment-page-browser-check: actual Chromium CSP, no outbound resource requests, safe injection, opaque-origin storage isolation, local interaction and example preview passed');
} finally {await browser.close();}
