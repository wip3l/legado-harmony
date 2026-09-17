import { BookSource } from '../../model/data/Book';
import { util } from '@kit.ArkTS';

export class LoginRuntimeStep {
  pendingAjax: string = '';
  pendingCookie: string = '';
  pendingCrypto: string = '';
  pendingBrowserAwait: string = '';
  pendingBrowserTitle: string = '';
  pendingWebView: string = '';
  cookieOperations: string = '[]';
  variable: string = '';
  loginHeader: string = '';
  loginInfo: string = '{}';
  requestedUrl: string = '';
  requestedTitle: string = '';
  requestedHtml: string = '';
  requestedInjectJs: string = '';
  requestedSearchKeyword: string = '';
  refreshExploreRequested: boolean = false;
  refreshLoginRequested: boolean = false;
  toastMessage: string = '';
  logMessage: string = '';
  errorMessage: string = '';
  resultValue: string = '';
}

export class LoginCookieOperation {
  operation: string = '';
  url: string = '';
  value: string = '';
  name: string = '';
}

class LoginScriptFunction {
  name: string = '';
  start: number = 0;
  end: number = 0;
  source: string = '';
}

/** Runs loginUi actions in ArkWeb's real JavaScript engine with a sandboxed bridge. */
export class BookSourceLoginWebRuntime {
  private static readonly RUNTIME_STATE_KEY: string = '__legadoHarmonyRuntime';

  static buildScript(source: BookSource, action: string, responses: Record<string, string>,
    cookies: Record<string, string> = {}, fixedNow: number = Date.now(), randomSeed: number = 1,
    appliedCookieOperations: string[] = []): string {
    const state = JSON.stringify({
      variable: source.variable || '',
      loginHeader: source.loginHeader || '',
      loginInfo: this.parseRecord(source.loginInfo),
      runtime: this.parseRuntimeState(source.loginInfo),
      responses: responses || {},
      cookies: cookies || {},
      appliedCookieOperations: appliedCookieOperations || [],
      sourceUrl: source.bookSourceUrl || '',
      sourceName: source.bookSourceName || '',
      sourceHeader: source.header || '',
      loginUi: source.loginUi || '',
      fixedNow: fixedNow,
      randomSeed: randomSeed
    });
    const completeLibrary = `${source.jsLib || ''}\n${this.unwrapJsWrapper(source.loginUrl || '')}`;
    const actionLibrary = this.shouldIsolateActionScript(completeLibrary) ?
      this.selectActionScript(completeLibrary, action || '') : completeLibrary;
    const library = this.normalizeScript(actionLibrary);
    const exposeFunctions = this.functionExposeScript(library);
    // ArkWeb's runJavaScript transport can misparse very large quoted source strings containing
    // nested templates/HTML. Keep both payloads ASCII-only while crossing that boundary, then
    // restore their UTF-8 text inside the Web runtime before parsing or evaluating them.
    const stateBase64 = this.encodeBase64(state);
    const initializeVariable = `if(!source.getVariable()&&typeof csh==='function'){try{csh();}catch(e){}}`;
    const codeBase64 = this.encodeBase64(`${library}\n${exposeFunctions}\n${initializeVariable}\n${action || ''}` +
      '\n//# sourceURL=book-source-login.js');
    return `(function(){` +
      `function decodeUtf8(v){try{return decodeURIComponent(escape(atob(v)));}catch(e){return atob(v);}}` +
      `const S=JSON.parse(decodeUtf8('${stateBase64}'));` +
      `let pending='',pendingCookie='',pendingCrypto='',pendingBrowser='',pendingBrowserTitle='',pendingWebView='';` +
      `let url='',title='',html='',injectJs='',searchKeyword='',refreshExplore=false,refreshLogin=false,toast='',diagnostic='',error='';` +
      `const NativeDate=globalThis.Date;const FixedDate=function(){const a=Array.from(arguments);` +
      `if(new.target)return Reflect.construct(NativeDate,a.length?a:[S.fixedNow]);` +
      `return new NativeDate(S.fixedNow).toString();};FixedDate.now=function(){return S.fixedNow;};` +
      `FixedDate.parse=NativeDate.parse;FixedDate.UTC=NativeDate.UTC;FixedDate.prototype=NativeDate.prototype;` +
      `const Date=FixedDate;let randomState=(Number(S.randomSeed)||1)>>>0;` +
      `const Math=Object.create(globalThis.Math);Math.random=function(){randomState=(randomState*1664525+1013904223)>>>0;` +
      `return randomState/4294967296;};` +
      `const previousNames=Array.isArray(globalThis.__legadoHarmonyExposedNames)?` +
      `globalThis.__legadoHarmonyExposedNames:[];for(const oldName of previousNames){` +
      `try{delete globalThis[oldName];}catch(e){globalThis[oldName]=undefined;}}` +
      `globalThis.__legadoHarmonyExposedNames=[];` +
      `const runtime=S.runtime&&typeof S.runtime==='object'?S.runtime:{};` +
      `const vars=Object.assign({},runtime.java||{});` +
      `const sourceData=Object.assign({},runtime.source||{});` +
      `const cacheData=Object.assign({},runtime.cache||{});` +
      `const cookieData=Object.assign({},S.cookies||{});const cookieOps=[];` +
      `const appliedCookieOps=new Set(Array.isArray(S.appliedCookieOperations)?S.appliedCookieOperations:[]);` +
      `function cookieOpKey(operation,url,name,value){return String(operation||'')+'\\n'+String(url||'')+'\\n'+` +
      `String(name||'')+'\\n'+String(value||'');}` +
      `const loginMap=Object.assign({},S.loginInfo||{});` +
      `Object.defineProperty(loginMap,'get',{enumerable:false,value:function(k){return this[k]||'';}});` +
      `Object.defineProperty(loginMap,'put',{enumerable:false,value:function(k,v){this[k]=v;return v;}});` +
      `function normalizedLoginKey(v){return String(v??'').toLowerCase().replace(/[\\s\\p{P}\\p{S}]/gu,'');}` +
      `function loginInfoValue(k){if(Object.prototype.hasOwnProperty.call(loginMap,k))return loginMap[k]||'';` +
      `const wanted=normalizedLoginKey(k);for(const key of Object.keys(loginMap)){` +
      `if(normalizedLoginKey(key)===wanted)return loginMap[key]||'';}` +
      `if(/token|令牌/i.test(wanted)){const matches=Object.keys(loginMap).filter(function(key){` +
      `return /token|令牌/i.test(normalizedLoginKey(key))&&String(loginMap[key]??'').trim();});` +
      `if(matches.length===1)return loginMap[matches[0]]||'';}return '';}` +
      `const loginInfoView=new Proxy(loginMap,{get:function(target,key){if(typeof key!=='string')return target[key];` +
      `if(key in target)return target[key];return loginInfoValue(key);}});` +
      `const source={` +
      `bookSourceUrl:S.sourceUrl,bookSourceName:S.sourceName,loginUi:S.loginUi,header:S.sourceHeader,` +
      `getKey:function(){return S.sourceUrl;},getTag:function(){return S.sourceName;},` +
      `getSource:function(){return this;},` +
      `getVariable:function(){return S.variable||'';},` +
      `setVariable:function(v){S.variable=String(v??'');return S.variable;},` +
      `refreshExplore:function(){refreshExplore=true;return true;},` +
      `put:function(k,v){sourceData[String(k??'')]=v;return v;},get:function(k){k=String(k??'');` +
      `return Object.prototype.hasOwnProperty.call(sourceData,k)?sourceData[k]:'';},` +
      `getLoginHeader:function(){return S.loginHeader||'';},` +
      `putLoginHeader:function(v){S.loginHeader=String(v??'');return S.loginHeader;},` +
      `removeLoginHeader:function(){S.loginHeader='';return '';},` +
      `getLoginHeaderMap:function(){if(!S.loginHeader)return null;let v;try{v=JSON.parse(S.loginHeader);}catch(e){return null;}` +
      `if(!v||typeof v!=='object'||Array.isArray(v)||Object.keys(v).length===0)return null;for(const k of Object.keys(v)){` +
      `const m=String(v[k]??'').match(/^Bearer\\s+([A-Za-z0-9_-]+)\\.([A-Za-z0-9_-]+)\\./i);if(!m)continue;try{` +
      `let p=m[2].replace(/-/g,'+').replace(/_/g,'/');while(p.length%4)p+='=';const d=JSON.parse(b64d(p)||'{}');` +
      `if(Number(d.exp||0)>0&&Number(d.exp)*1000<=Number(S.fixedNow)+30000)return null;}catch(e){}}return v;},` +
      `getHeaderMap:function(){try{return JSON.parse(S.sourceHeader||'{}');}catch(e){return {};}} ,` +
      `getLoginInfoMap:function(){return loginInfoView;},` +
      `getLoginInfo:function(k){return arguments.length?(k?loginInfoValue(k):''):JSON.stringify(loginMap);},` +
      `putLoginInfo:function(a,b){if(arguments.length>1){loginMap[a]=b;return b;}` +
      `let next=a;if(typeof next==='string'){try{next=JSON.parse(next);}catch(e){return a;}}` +
      `if(next&&typeof next==='object'&&!Array.isArray(next)){Object.keys(loginMap).forEach(function(k){delete loginMap[k];});` +
      `Object.assign(loginMap,next);}return a;},` +
      `removeLoginInfo:function(){Object.keys(loginMap).forEach(function(k){delete loginMap[k];});return '';}` +
      `};` +
      `const nativeAtob=globalThis.atob;const nativeBtoa=globalThis.btoa;const NativeURL=globalThis.URL;` +
      `function byteArray(v){if(v instanceof Uint8Array)return Array.from(v);if(Array.isArray(v))return v.map(function(x){` +
      `return Number(x)&255;});return Array.from(new TextEncoder().encode(String(v??'')));}` +
      `function b64e(v){try{const bytes=byteArray(v);let binary='';for(const x of bytes)binary+=String.fromCharCode(x);` +
      `return nativeBtoa.call(globalThis,binary);}catch(e){return String(v??'');}}` +
      `function b64bytes(v){try{const binary=nativeAtob.call(globalThis,String(v??''));const bytes=[];for(let i=0;i<binary.length;i++)` +
      `bytes.push(binary.charCodeAt(i)&255);return bytes;}catch(e){return [];}}` +
      `function b64d(v){try{return new TextDecoder().decode(new Uint8Array(b64bytes(v)));}` +
      `catch(e){return String(v??'');}}` +
      `function b64ue(v){return b64e(v).replace(/\\+/g,'-').replace(/\\//g,'_').replace(/=+$/,'');}` +
      `function b64ud(v){v=String(v??'').replace(/-/g,'+').replace(/_/g,'/');while(v.length%4)v+='=';return b64d(v);}` +
      `function hexE(v){try{return Array.from(new TextEncoder().encode(String(v??''))).map(function(x){` +
      `return x.toString(16).padStart(2,'0');}).join('');}catch(e){return '';}}` +
      `function hexD(v){try{v=String(v??'').replace(/\\s+/g,'');const a=[];for(let i=0;i<v.length;i+=2)` +
      `a.push(parseInt(v.substring(i,i+2),16));return new TextDecoder().decode(new Uint8Array(a));}catch(e){return '';}}` +
      `function strBytes(v){try{return byteArray(v);}catch(e){return [];}}` +
      `function bytesStr(v){try{return new TextDecoder().decode(new Uint8Array(Array.isArray(v)?v:[]));}` +
      `catch(e){return String(v??'');}}` +
      `function uuid(){return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g,function(c){const r=Math.random()*16|0;` +
      `return (c==='x'?r:(r&3|8)).toString(16);});}` +
      `function stableDeviceId(){let value=String(vars.__legadoHarmonyDeviceId||'').trim();` +
      `if(!/^[0-9a-f]{16}$/i.test(value)){value=uuid().replace(/-/g,'').substring(0,16).toLowerCase();` +
      `vars.__legadoHarmonyDeviceId=value;}return value;}` +
      `function htmlE(v){const d=document.createElement('div');d.textContent=String(v??'');return d.innerHTML;}` +
      `function htmlD(v){const d=document.createElement('textarea');d.innerHTML=String(v??'');return d.value;}` +
      `function open(u,t,wait){const target=String(u??'');const label=String(t??'');` +
      `if(wait){const key='browser:'+target;if(Object.prototype.hasOwnProperty.call(S.responses,key)){` +
      `const body=S.responses[key]??'';return {body:function(){return body;}};}if(!pendingBrowser){` +
      `pendingBrowser=target;pendingBrowserTitle=label;}return {body:function(){return '';}};}` +
      `url=target;title=label;return {body:function(){return '';}};}` +
      `function webView(u,j){const request=JSON.stringify({url:String(u??''),script:String(j??'')});` +
      `const key='webview:'+request;if(Object.prototype.hasOwnProperty.call(S.responses,key))return S.responses[key]??'';` +
      `if(!pendingWebView)pendingWebView=request;return '';}` +
      `function requestSpec(method,u,b,h){const options={method:String(method||'GET').toUpperCase()};` +
      `if(b!==undefined&&b!==null)options.body=typeof b==='string'?b:JSON.stringify(b);` +
      `if(h&&typeof h==='object')options.headers=h;return String(u??'')+','+JSON.stringify(options);}` +
      `function specUrl(v){v=String(v??'');const i=v.indexOf(',{');return i>0?v.substring(0,i):v;}` +
      `function responseCookieList(v){const ignored={path:1,domain:1,expires:1,'max-age':1,secure:1,httponly:1,samesite:1,priority:1};` +
      `const values=[];const seen={};const re=/(?:^|[;,\\r\\n]\\s*)([A-Za-z0-9_.-]+)=([^;,\\r\\n]*)/g;let m;` +
      `while((m=re.exec(String(v??'')))!==null){const n=m[1],k=n.toLowerCase();if(ignored[k]||seen[k])continue;` +
      `seen[k]=1;values.push(n+'='+String(m[2]??'').trim());}return values.join(', ');}` +
      `function responseObject(v){v=String(v??'');let body='';` +
      `if(Object.prototype.hasOwnProperty.call(S.responses,v))body=S.responses[v]??'';else if(!pending)pending=v;` +
      `return {body:function(){return body;},code:function(){return body?200:599;},` +
      `isSuccessful:function(){return !!body;},headers:function(){return {};},cookies:function(){const u=specUrl(v);` +
      `const c=responseCookieList(cookieData[u]);return {toString:function(){return c;},size:function(){return c?c.split(',').length:0;}};},` +
      `toString:function(){return body;}};}` +
      `function cryptoOp(transformation,key,iv,method,data){const request=JSON.stringify({` +
      `transformation:String(transformation??''),key:Array.isArray(key)?key:String(key??''),` +
      `iv:Array.isArray(iv)?iv:String(iv??''),method:method,data:Array.isArray(data)?data:String(data??'')});` +
      `const responseKey='crypto:'+request;if(Object.prototype.hasOwnProperty.call(S.responses,responseKey)){` +
      `let response;try{response=JSON.parse(S.responses[responseKey]);}catch(e){throw new Error('加密桥接返回异常');}` +
      `if(!response||response.success!==true)throw new Error(response&&response.error?response.error:'加密桥接失败');` +
      `return response.value;}if(!pendingCrypto)pendingCrypto=request;return method.indexOf('Str')>=0||` +
      `method.indexOf('Base64')>=0||method.indexOf('Hex')>=0?'':[];}` +
      `const cache={get:function(k){return Object.prototype.hasOwnProperty.call(cacheData,k)?cacheData[k]:null;},` +
      `getFromMemory:function(k){return Object.prototype.hasOwnProperty.call(cacheData,k)?cacheData[k]:null;},` +
      `put:function(k,v){cacheData[k]=v;return v;},putMemory:function(k,v){cacheData[k]=v;return v;},` +
      `delete:function(k){delete cacheData[k];return true;}};` +
      `const cookie={getCookie:function(k){k=String(k??'');` +
      `if(Object.prototype.hasOwnProperty.call(cookieData,k))return cookieData[k]??'';` +
      `if(!pendingCookie)pendingCookie=k;return '';},getKey:function(k,n){` +
      `const value=this.getCookie(k);const m=String(value??'').match(new RegExp('(?:^|;\\\\s*)'+n+'=([^;]*)'));` +
      `return m?m[1]:'';},` +
      `setCookie:function(k,v){k=String(k??'');v=String(v??'');const op=cookieOpKey('set',k,'',v);` +
      `if(!appliedCookieOps.has(op)){cookieData[k]=v;cookieOps.push({operation:'set',url:k,value:v,name:''});}return v;},` +
      `replaceCookie:function(k,v){k=String(k??'');v=String(v??'');const op=cookieOpKey('replace',k,'',v);` +
      `if(!appliedCookieOps.has(op)){cookieData[k]=v;cookieOps.push({operation:'replace',url:k,value:v,name:''});}return v;},` +
      `removeCookie:function(k,n){k=String(k??'');n=String(n??'');` +
      `const op=cookieOpKey('remove',k,n,'');if(appliedCookieOps.has(op))return true;` +
      `cookieOps.push({operation:'remove',url:k,value:'',name:n});` +
      `if(!n){cookieData[k]='';}else{cookieData[k]=String(cookieData[k]??'').split(';').filter(function(x){` +
      `return x.trim().split('=')[0]!==n;}).join(';');}return true;}};` +
      `function javaMap(){const map={};Object.defineProperty(map,'get',{enumerable:false,value:function(k){` +
      `return Object.prototype.hasOwnProperty.call(this,k)?this[k]:null;}});` +
      `Object.defineProperty(map,'put',{enumerable:false,value:function(k,v){this[k]=v;return v;}});` +
      `Object.defineProperty(map,'remove',{enumerable:false,value:function(k){const v=this[k];delete this[k];return v;}});` +
      `Object.defineProperty(map,'putAll',{enumerable:false,value:function(v){if(v&&typeof v==='object')` +
      `Object.keys(v).forEach(function(k){map[k]=v[k];});return map;}});return map;}` +
      `const java={` +
      `ajax:function(v){v=String(v??'');if(Object.prototype.hasOwnProperty.call(S.responses,v))return S.responses[v];` +
      `if(!pending)pending=v;return '{"code":599,"message":"pending","data":null}';},` +
      `ajaxAll:function(v){const list=Array.isArray(v)?v:[v];return list.map(responseObject);},` +
      `post:function(u,b,h){return responseObject(requestSpec('POST',u,b,h));},` +
      `put:function(k,v){vars[k]=v;return v;},get:function(k,h){if(arguments.length>1)` +
      `return responseObject(requestSpec('GET',k,null,h));k=String(k??'');` +
      `return Object.prototype.hasOwnProperty.call(vars,k)?vars[k]:null;},` +
      `toast:function(v){toast=String(v??'');return toast;},longToast:function(v){toast=String(v??'');return toast;},` +
      `upLoginData:function(v){if(v&&typeof v==='object')Object.keys(v).forEach(function(k){` +
      `loginMap[k]=String(v[k]??'');});return true;},` +
      `startBrowser:function(u,t){return open(u,t,false);},startBrowserAwait:function(u,t){return open(u,t,true);},` +
      `startBrowserDp:function(u,t){return open(u,t,false);},showBrowser:function(u,c,j,o){` +
      `url=String(u??'');title='';html=c===undefined||c===null?'':String(c);injectJs=String(j??'');` +
      `return {body:function(){return html;}};},` +
      `showReadingBrowser:function(u,t){return open(u,t,false);},open:function(u,t){return open(u,t,false);},` +
      `openUrl:function(u){return open(u,'',false);},` +
      `webView:function(_html,u,j){return webView(u,j);},` +
      `base64Encode:b64e,base64EncodeToString:b64e,base64Decode:b64d,base64DecodeToString:b64d,` +
      `base64DecodeToByteArray:b64bytes,base64UrlEncode:b64ue,base64UrlDecode:b64ud,` +
      `hexEncodeToString:hexE,hexDecodeToString:hexD,strToBytes:strBytes,bytesToStr:bytesStr,` +
      `md5Encode:function(v){return cryptoOp('MD5','','','digestHex',v);},` +
      `md5Encode32:function(v){return cryptoOp('MD5','','','digestHex',v);},` +
      `md5Encode16:function(v){return String(cryptoOp('MD5','','','digestHex',v)).substring(8,24);},` +
      `urlEncode:function(v){return encodeURIComponent(String(v??''));},` +
      `urlDecode:function(v){try{return decodeURIComponent(String(v??''));}catch(e){return String(v??'');}},` +
      `encodeURI:function(v){return encodeURIComponent(String(v??''));},htmlEncode:htmlE,htmlDecode:htmlD,` +
      `androidId:stableDeviceId,deviceID:stableDeviceId,randomUUID:uuid,` +
      `getCookie:function(k){return cookie.getCookie(k);},lang:function(){return 'zh';},` +
      `reLoginView:function(){refreshLogin=true;return true;},` +
      `qread:function(){return '0';},log:function(){diagnostic=Array.from(arguments).map(function(v){return String(v??'');}).join(' ');` +
      `return diagnostic;},logType:function(){diagnostic=Array.from(arguments).map(function(v){return String(v??'');}).join(' ');` +
      `return diagnostic;},` +
      `refreshExplore:function(){refreshExplore=true;return true;},refreshBookToc:function(){return true;},` +
      `refreshContent:function(){return true;},upConfig:function(){return true;},` +
      `getString:function(k){k=String(k??'').replace(/^\$\.?/,'');let v=loginMap;` +
      `for(const p of k.split('.').filter(Boolean)){if(v===null||v===undefined)return '';v=v[p];}` +
      `return typeof v==='string'?v:JSON.stringify(v??'');},` +
      `searchBook:function(k){searchKeyword=String(k??'');return searchKeyword;},getWebViewUA:function(){return navigator.userAgent;},` +
      `timeFormat:function(v){try{return new Date(v).toISOString().replace('T',' ').replace('Z','');}` +
      `catch(e){return String(v??'');}},timeFormatUTC:function(v){try{return new Date(v).toISOString();}` +
      `catch(e){return String(v??'');}},evalJS:function(v){return (0,eval)(String(v??''));},` +
      `createSymmetricCrypto:function(transformation,key,iv){return {` +
      `encrypt:function(v){return cryptoOp(transformation,key,iv,'encrypt',v);},` +
      `encryptStr:function(v){return cryptoOp(transformation,key,iv,'encryptStr',v);},` +
      `encryptBase64:function(v){return cryptoOp(transformation,key,iv,'encryptBase64',v);},` +
      `encryptHex:function(v){return cryptoOp(transformation,key,iv,'encryptHex',v);},` +
      `decrypt:function(v){return cryptoOp(transformation,key,iv,'decrypt',v);},` +
      `decryptStr:function(v){return cryptoOp(transformation,key,iv,'decryptStr',v);}};}` +
      `};` +
      `const TimeoutCancellationException=function(){};` +
      `function markJavaClass(value,name){try{Object.defineProperty(value,'__simpleName',{value:name,` +
      `enumerable:false,configurable:true});}catch(e){}return value;}` +
      `const JavaBase64=markJavaClass({encodeToString:function(v){return b64e(v);}},'Base64');` +
      `const JavaString=markJavaClass(String,'String');try{if(typeof String.prototype.getBytes!=='function')` +
      `Object.defineProperty(String.prototype,'getBytes',{enumerable:false,configurable:true,value:function(){` +
      `return byteArray(String(this));}});}catch(e){}` +
      `const JavaURL=markJavaClass(function(v){const parsed=new NativeURL(String(v??''));return {` +
      `host:parsed.hostname,hostname:parsed.hostname,protocol:parsed.protocol,port:parsed.port,` +
      `path:parsed.pathname,toString:function(){return parsed.toString();}};},'URL');` +
      `function topPrivateDomain(v){try{const host=new NativeURL(String(v??'')).hostname.toLowerCase();` +
      `if(!host||/^\\d{1,3}(?:\\.\\d{1,3}){3}$/.test(host)||host.includes(':'))return null;` +
      `const labels=host.split('.').filter(Boolean);if(labels.length<2)return host;const country=labels[labels.length-1];` +
      `const second=labels[labels.length-2];const multipart=/^(?:com|net|org|gov|edu|ac|co)$/i.test(second)&&` +
      `/^(?:cn|uk|jp|au|nz|kr|za)$/i.test(country);return labels.slice(multipart?-3:-2).join('.');}` +
      `catch(e){return null;}}` +
      `const JavaHttpUrl=markJavaClass({parse:function(v){const raw=String(v??'');try{new NativeURL(raw);}` +
      `catch(e){return null;}return {topPrivateDomain:function(){return topPrivateDomain(raw);},` +
      `host:function(){return new NativeURL(raw).hostname;},toString:function(){return raw;}};}},'HttpUrl');` +
      `function JavaImporter(){const scope={};Object.defineProperty(scope,'importClass',{enumerable:false,` +
      `value:function(clazz){if(!clazz)return clazz;const name=String(clazz.__simpleName||clazz.name||'').trim();` +
      `if(name){this[name]=clazz;globalThis[name]=clazz;}return clazz;}});Object.defineProperty(scope,'importPackage',{enumerable:false,` +
      `value:function(pkg){if(pkg&&typeof pkg==='object')Object.keys(pkg).forEach(function(k){scope[k]=pkg[k];});` +
      `return pkg;}});for(let i=0;i<arguments.length;i++)scope.importClass(arguments[i]);return scope;}` +
      `const Packages={io:{legato:{kazusa:{utils:{TimeoutCancellationException:TimeoutCancellationException}}}},` +
      `java:{util:{HashMap:javaMap,LinkedHashMap:javaMap},lang:{String:JavaString,` +
      `Thread:{sleep:function(){return '';}}},net:{URL:JavaURL}},` +
      `android:{util:{Base64:JavaBase64}},okhttp3:{HttpUrl:JavaHttpUrl}};` +
      `globalThis.source=source;globalThis.java=java;globalThis.cache=cache;globalThis.cookie=cookie;` +
      `globalThis.Packages=Packages;globalThis.JavaImporter=JavaImporter;globalThis.result=loginMap;` +
      `let evaluatedResult;try{evaluatedResult=(function(){return eval(decodeUtf8('${codeBase64}'));}).call(globalThis);}` +
      `catch(e){error=String((e&&e.name?e.name+': ':'')+((e&&e.message)||e||'脚本执行失败')+` +
      `(e&&e.stack?'\\n'+e.stack:''));}` +
      `if(!error&&!toast&&/(?:异常|失败|错误|error|exception)/i.test(diagnostic))error=diagnostic;` +
      `function resultText(v){if(typeof v==='string')return v;if(v&&v!==loginMap&&typeof v==='object'){` +
      `try{return JSON.stringify(v);}catch(e){return '';}}return '';}` +
      `const resultValue=resultText(globalThis.result)||resultText(evaluatedResult);` +
      `const cleanInfo={};Object.keys(loginMap).forEach(function(k){cleanInfo[k]=String(loginMap[k]??'');});` +
      `cleanInfo['${this.RUNTIME_STATE_KEY}']=JSON.stringify({java:vars,source:sourceData,cache:cacheData});` +
      `return encodeURIComponent(JSON.stringify({pendingAjax:pending,pendingCookie:pendingCookie,` +
      `pendingCrypto:pendingCrypto,pendingBrowserAwait:pendingBrowser,pendingBrowserTitle:pendingBrowserTitle,pendingWebView:pendingWebView,` +
      `cookieOperations:JSON.stringify(cookieOps),variable:S.variable||'',` +
      `loginHeader:S.loginHeader||'',loginInfo:JSON.stringify(cleanInfo),requestedUrl:url,requestedTitle:title,` +
      `requestedHtml:html,requestedInjectJs:injectJs,requestedSearchKeyword:searchKeyword,` +
      `refreshExploreRequested:refreshExplore,refreshLoginRequested:refreshLogin,` +
      `toastMessage:toast,logMessage:diagnostic,errorMessage:error,resultValue:resultValue}));})()`;
  }

  private static encodeBase64(value: string): string {
    const bytes = new util.TextEncoder().encodeInto(value || '');
    return new util.Base64Helper().encodeToStringSync(bytes);
  }

  /**
   * Legado wraps loginUrl JavaScript in `<js>...</js>` (or a leading `@js:`). Inside a composed
   * script those wrappers are parsed as comparison operators / an unterminated regex literal, so
   * the login functions the source actually defines never come into scope. Plain URL loginUrl
   * values pass through unchanged.
   */
  private static unwrapJsWrapper(raw: string): string {
    const text = (raw || '').trim();
    if (/^<js>/i.test(text)) return text.replace(/^<js>\s*/i, '').replace(/\s*<\/js>$/i, '');
    if (/^@?js:/i.test(text)) return text.replace(/^@?js:\s*/i, '');
    return text;
  }

  private static normalizeScript(script: string): string {    // Some ArkWeb versions reject an unparenthesized object literal that is indexed directly
    // in a variable initializer: `const value = { a: 1 }[key]`. Parentheses are equivalent and
    // are accepted by both the Web engine and the JavaScript dialect used by Android Legado.
    return (script || '')
      .replace(/=\s*\{([^{}]*)\}\s*\[([A-Za-z_$][A-Za-z0-9_$]*)\]/g,
        (_match: string, body: string, key: string): string => `= ({${body}})[${key}]`)
      // Rhino accepts redeclaring a function parameter while assigning its default value,
      // whereas Chromium rejects the duplicate lexical declaration. Preserve the assignment.
      .replace(/\b(?:let|const)\s+([A-Za-z_$][A-Za-z0-9_$]*)\s*=\s*\1\s*\|\|/g,
        (_match: string, name: string): string => `${name} = ${name} ||`);
  }

  private static shouldIsolateActionScript(script: string): boolean {
    // `[removed]` is produced by privacy/sanitizing pipelines when a template expression is
    // stripped. Some pipelines also remove its closing backtick, making an otherwise unrelated
    // function invalidate the whole login library. Clean sources keep their exact full script.
    // Large aggregation sources commonly bundle tens of thousands of lines of unrelated HTML,
    // parsers and account actions. Evaluating the whole bundle for a one-line switch both delays
    // every click and lets an unrelated optional function break all buttons. The dependency
    // selector preserves the shared prelude plus the called function graph.
    return (script || '').includes('[removed]') || (script || '').length > 64 * 1024;
  }

  private static selectActionScript(script: string, action: string): string {
    const functions = this.extractFunctions(script || '');
    if (functions.length === 0) return script || '';

    // Preserve top-level constants and setup statements, but remove every unneeded function body.
    // Replacing removed spans with a line break also prevents adjacent comments/tokens merging.
    let prelude = '';
    let cursor = 0;
    for (const block of functions) {
      if (block.start < cursor) continue;
      prelude += script.substring(cursor, block.start) + '\n';
      cursor = block.end;
    }
    prelude += script.substring(cursor);

    // The preserved prelude is executable code, not merely declarations. Large aggregation
    // sources commonly initialize settings through helpers such as getArgument() at top level.
    // Starting the closure from the clicked action alone retained that call site while removing
    // its helper declaration, so an unrelated-looking "getArgument is not defined" was raised
    // before or after the requested action. Treat both executable roots alike, then recursively
    // include every named source helper they reference.
    const required: string[] = [];
    const pending: string[] = this.scriptIdentifiers(`${action || ''}\n${prelude}`);
    while (pending.length > 0) {
      const name = pending.shift() || '';
      if (!name || required.includes(name)) continue;
      const block = functions.find((item: LoginScriptFunction): boolean =>
        item.name === name && !!item.source);
      if (!block) continue;
      required.push(name);
      for (const dependency of this.scriptIdentifiers(block.source)) {
        if (!required.includes(dependency) && !pending.includes(dependency)) pending.push(dependency);
      }
    }

    if (required.length === 0) return prelude;
    let selected = prelude;
    for (const block of functions) {
      if (required.includes(block.name)) selected += `\n${block.source}\n`;
    }
    return selected;
  }

  private static extractFunctions(script: string): LoginScriptFunction[] {
    const result: LoginScriptFunction[] = [];
    // Search a same-length lexical mask instead of the raw source. Aggregation sources often
    // embed browser scripts/HTML containing text such as `function foo(` inside quoted strings.
    // Treating those bytes as declarations removes unrelated spans and produces an invalid
    // action library even though the imported JavaScript itself is valid.
    const searchable = this.maskFunctionSearchText(script || '');
    const regex = /\bfunction\s+([A-Za-z_$][A-Za-z0-9_$]*)\s*\(/g;
    let match: RegExpExecArray | null;
    while ((match = regex.exec(searchable)) !== null) {
      const parametersOpen = regex.lastIndex - 1;
      const parametersClose = this.findMatchingDelimiter(script, parametersOpen, '(', ')');
      if (parametersClose < 0) {
        const invalid = this.invalidFunctionBlock(script, searchable, match[1] || '', match.index, regex.lastIndex);
        result.push(invalid);
        regex.lastIndex = invalid.end;
        continue;
      }
      let bodyOpen = parametersClose + 1;
      while (bodyOpen < script.length && /\s/.test(script.charAt(bodyOpen))) bodyOpen++;
      if (script.charAt(bodyOpen) !== '{') {
        const invalid = this.invalidFunctionBlock(script, searchable, match[1] || '', match.index, regex.lastIndex);
        result.push(invalid);
        regex.lastIndex = invalid.end;
        continue;
      }
      const bodyClose = this.findMatchingDelimiter(script, bodyOpen, '{', '}');
      if (bodyClose < 0) {
        // A damaged, unrelated source function must not poison every loginUi button. Isolate it
        // up to the next named declaration; if the button needs it, the action gets a clear
        // missing-function error instead of a parser failure in unrelated code.
        const invalid = this.invalidFunctionBlock(script, searchable, match[1] || '', match.index, regex.lastIndex);
        result.push(invalid);
        regex.lastIndex = invalid.end;
        continue;
      }
      const block = new LoginScriptFunction();
      block.name = match[1] || '';
      block.start = match.index;
      block.end = bodyClose + 1;
      block.source = script.substring(block.start, block.end);
      result.push(block);
      regex.lastIndex = block.end;
    }
    return result;
  }

  private static invalidFunctionBlock(script: string, searchable: string, name: string, start: number,
    searchFrom: number): LoginScriptFunction {
    const nextRegex = /\bfunction\s+[A-Za-z_$][A-Za-z0-9_$]*\s*\(/g;
    nextRegex.lastIndex = Math.max(searchFrom, start + 1);
    const next = nextRegex.exec(searchable);
    const block = new LoginScriptFunction();
    block.name = name;
    block.start = start;
    block.end = next ? next.index : script.length;
    block.source = '';
    return block;
  }

  /** Masks strings, comments and regex literals while preserving every source offset. */
  private static maskFunctionSearchText(script: string): string {
    let result = '';
    let quote = '';
    let lineComment = false;
    let blockComment = false;
    let regexLiteral = false;
    let regexClass = false;
    for (let index = 0; index < script.length; index++) {
      const current = script.charAt(index);
      const next = index + 1 < script.length ? script.charAt(index + 1) : '';
      const masked = current === '\n' || current === '\r' ? current : ' ';
      if (lineComment) {
        if (current === '\n' || current === '\r') lineComment = false;
        result += masked;
        continue;
      }
      if (blockComment) {
        if (current === '*' && next === '/') {
          blockComment = false;
          result += '  ';
          index++;
        } else {
          result += masked;
        }
        continue;
      }
      if (quote) {
        if (current === '\\') {
          result += ' ';
          if (index + 1 < script.length) {
            result += next === '\n' || next === '\r' ? next : ' ';
            index++;
          }
        } else {
          if (current === quote) quote = '';
          result += masked;
        }
        continue;
      }
      if (regexLiteral) {
        if (current === '\\') {
          result += ' ';
          if (index + 1 < script.length) {
            result += next === '\n' || next === '\r' ? next : ' ';
            index++;
          }
        } else {
          if (current === '[') regexClass = true;
          else if (current === ']') regexClass = false;
          else if (current === '/' && !regexClass) regexLiteral = false;
          result += masked;
        }
        continue;
      }
      if (current === '/' && next === '/') {
        lineComment = true;
        result += '  ';
        index++;
      } else if (current === '/' && next === '*') {
        blockComment = true;
        result += '  ';
        index++;
      } else if (current === '/' && this.isRegexLiteralStart(script, index)) {
        regexLiteral = true;
        regexClass = false;
        result += ' ';
      } else if (current === '\'' || current === '"' || current === '`') {
        quote = current;
        result += ' ';
      } else {
        result += current;
      }
    }
    return result;
  }

  private static findMatchingDelimiter(script: string, start: number, open: string, close: string): number {
    let depth = 0;
    let quote = '';
    let lineComment = false;
    let blockComment = false;
    let regexLiteral = false;
    let regexClass = false;
    for (let index = start; index < script.length; index++) {
      const current = script.charAt(index);
      const next = index + 1 < script.length ? script.charAt(index + 1) : '';
      if (lineComment) {
        if (current === '\n' || current === '\r') lineComment = false;
        continue;
      }
      if (blockComment) {
        if (current === '*' && next === '/') {
          blockComment = false;
          index++;
        }
        continue;
      }
      if (quote) {
        if (current === '\\') {
          index++;
        } else if (current === quote) {
          quote = '';
        }
        continue;
      }
      if (regexLiteral) {
        if (current === '\\') {
          index++;
        } else if (current === '[') {
          regexClass = true;
        } else if (current === ']') {
          regexClass = false;
        } else if (current === '/' && !regexClass) {
          regexLiteral = false;
        }
        continue;
      }
      if (current === '/' && next === '/') {
        lineComment = true;
        index++;
        continue;
      }
      if (current === '/' && next === '*') {
        blockComment = true;
        index++;
        continue;
      }
      if (current === '/' && this.isRegexLiteralStart(script, index)) {
        regexLiteral = true;
        regexClass = false;
        continue;
      }
      if (current === '\'' || current === '"' || current === '`') {
        quote = current;
        continue;
      }
      if (current === open) depth++;
      if (current === close) {
        depth--;
        if (depth === 0) return index;
      }
    }
    return -1;
  }

  private static isRegexLiteralStart(script: string, slashIndex: number): boolean {
    let index = slashIndex - 1;
    while (index >= 0 && /\s/.test(script.charAt(index))) index--;
    if (index < 0) return true;
    const previous = script.charAt(index);
    if ('([{:;,=!?&|+-*%^~<>'.includes(previous)) return true;
    let end = index + 1;
    while (index >= 0 && /[A-Za-z_$]/.test(script.charAt(index))) index--;
    const word = script.substring(index + 1, end);
    return word === 'return' || word === 'case' || word === 'throw' || word === 'typeof' ||
      word === 'delete' || word === 'void' || word === 'new' || word === 'in' || word === 'of';
  }

  private static scriptIdentifiers(script: string): string[] {
    const clean = this.stripScriptStrings(script || '');
    const result: string[] = [];
    const regex = /\b[A-Za-z_$][A-Za-z0-9_$]*\b/g;
    let match: RegExpExecArray | null;
    while ((match = regex.exec(clean)) !== null) {
      const name = match[0] || '';
      if (name && !result.includes(name)) result.push(name);
    }
    return result;
  }

  private static stripScriptStrings(script: string): string {
    let result = '';
    let quote = '';
    let lineComment = false;
    let blockComment = false;
    let regexLiteral = false;
    let regexClass = false;
    for (let index = 0; index < script.length; index++) {
      const current = script.charAt(index);
      const next = index + 1 < script.length ? script.charAt(index + 1) : '';
      if (lineComment) {
        if (current === '\n' || current === '\r') {
          lineComment = false;
          result += current;
        } else {
          result += ' ';
        }
        continue;
      }
      if (blockComment) {
        if (current === '*' && next === '/') {
          blockComment = false;
          result += '  ';
          index++;
        } else {
          result += current === '\n' || current === '\r' ? current : ' ';
        }
        continue;
      }
      if (quote) {
        if (current === '\\') {
          result += quote === '`' ? current + next : '  ';
          index++;
        } else if (current === quote) {
          quote = '';
          result += ' ';
        } else {
          result += quote === '`' ? current : (current === '\n' || current === '\r' ? current : ' ');
        }
        continue;
      }
      if (regexLiteral) {
        if (current === '\\') {
          result += '  ';
          index++;
        } else if (current === '[') {
          regexClass = true;
          result += ' ';
        } else if (current === ']') {
          regexClass = false;
          result += ' ';
        } else if (current === '/' && !regexClass) {
          regexLiteral = false;
          result += ' ';
        } else {
          result += current === '\n' || current === '\r' ? current : ' ';
        }
        continue;
      }
      if (current === '/' && next === '/') {
        lineComment = true;
        result += '  ';
        index++;
      } else if (current === '/' && next === '*') {
        blockComment = true;
        result += '  ';
        index++;
      } else if (current === '/' && this.isRegexLiteralStart(script, index)) {
        regexLiteral = true;
        regexClass = false;
        result += ' ';
      } else if (current === '\'' || current === '"' || current === '`') {
        quote = current;
        result += ' ';
      } else {
        result += current;
      }
    }
    return result;
  }

  static parseResult(raw: string): LoginRuntimeStep {
    let value = (raw || '').trim();
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
      value = value.substring(1, value.length - 1);
    }
    try {
      const record = JSON.parse(decodeURIComponent(value)) as Record<string, Object>;
      const result = new LoginRuntimeStep();
      result.pendingAjax = String(record['pendingAjax'] || '');
      result.pendingCookie = String(record['pendingCookie'] || '');
      result.pendingCrypto = String(record['pendingCrypto'] || '');
      result.pendingBrowserAwait = String(record['pendingBrowserAwait'] || '');
      result.pendingBrowserTitle = String(record['pendingBrowserTitle'] || '');
      result.pendingWebView = String(record['pendingWebView'] || '');
      result.cookieOperations = String(record['cookieOperations'] || '[]');
      result.variable = String(record['variable'] || '');
      result.loginHeader = String(record['loginHeader'] || '');
      result.loginInfo = String(record['loginInfo'] || '{}');
      result.requestedUrl = String(record['requestedUrl'] || '');
      result.requestedTitle = String(record['requestedTitle'] || '');
      result.requestedHtml = String(record['requestedHtml'] || '');
      result.requestedInjectJs = String(record['requestedInjectJs'] || '');
      result.requestedSearchKeyword = String(record['requestedSearchKeyword'] || '');
      result.refreshExploreRequested = record['refreshExploreRequested'] === true;
      result.refreshLoginRequested = record['refreshLoginRequested'] === true;
      result.toastMessage = String(record['toastMessage'] || '');
      result.logMessage = String(record['logMessage'] || '');
      result.errorMessage = String(record['errorMessage'] || '');
      result.resultValue = String(record['resultValue'] || '');
      return result;
    } catch (_) {
      const result = new LoginRuntimeStep();
      result.errorMessage = '登录脚本返回格式异常';
      return result;
    }
  }

  static parseRecord(json: string): Record<string, string> {
    try {
      const parsed = JSON.parse(json || '{}') as Record<string, Object>;
      const result: Record<string, string> = {};
      if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
        for (const key in parsed) {
          if (key !== this.RUNTIME_STATE_KEY) result[key] = String(parsed[key] || '');
        }
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  static mergeRecord(json: string, values: Record<string, string>): string {
    const merged: Record<string, Object> = {};
    for (const key in values) merged[key] = values[key];
    const runtime = this.parseRuntimeState(json);
    let hasRuntime = false;
    for (const key in runtime) {
      if (key) hasRuntime = true;
    }
    if (hasRuntime) {
      merged[this.RUNTIME_STATE_KEY] = JSON.stringify(runtime);
    }
    return JSON.stringify(merged);
  }

  static runtimeState(json: string): Record<string, Object> {
    return this.parseRuntimeState(json);
  }

  static parseCookieOperations(json: string): LoginCookieOperation[] {
    const result: LoginCookieOperation[] = [];
    try {
      const parsed = JSON.parse(json || '[]') as Object[];
      if (!Array.isArray(parsed)) return result;
      for (const item of parsed) {
        if (!item || typeof item !== 'object' || Array.isArray(item)) continue;
        const record = item as Record<string, Object>;
        const operation = new LoginCookieOperation();
        operation.operation = String(record['operation'] || '');
        operation.url = String(record['url'] || '');
        operation.value = String(record['value'] || '');
        operation.name = String(record['name'] || '');
        if (operation.url && (operation.operation === 'set' || operation.operation === 'remove')) {
          result.push(operation);
        }
      }
    } catch (_) {}
    return result;
  }

  private static parseRuntimeState(json: string): Record<string, Object> {
    const empty: Record<string, Object> = {};
    try {
      const parsed = JSON.parse(json || '{}') as Record<string, Object>;
      if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) return empty;
      let value = parsed[this.RUNTIME_STATE_KEY];
      if (typeof value === 'string') value = JSON.parse(value) as Object;
      if (value && typeof value === 'object' && !Array.isArray(value)) {
        return value as Record<string, Object>;
      }
    } catch (_) {}
    return empty;
  }

  private static functionExposeScript(script: string): string {
    const names: string[] = [];
    const regex = /\bfunction\s+([A-Za-z_$][A-Za-z0-9_$]*)\s*\(/g;
    let match: RegExpExecArray | null;
    while ((match = regex.exec(script || '')) !== null) {
      const name = match[1] || '';
      if (name && !names.includes(name)) names.push(name);
    }
    let code = `globalThis.__legadoHarmonyExposedNames=${JSON.stringify(names)};`;
    for (const name of names) {
      code += `if(typeof ${name}==='function')globalThis[${JSON.stringify(name)}]=${name};`;
    }
    return code;
  }
}
