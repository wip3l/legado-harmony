/** 评论网页在首次绘制前接收主题，在样式完成绘制后才通知宿主撤掉加载层。 */
export class ReaderCommentWebTheme {
  static bootstrap(dark: boolean, inlineDocument: boolean = false): string {
    return `(function(){
      if(window.top!==window)return;
      ${ReaderCommentWebTheme.navigation()}
      var scheme=${JSON.stringify(dark ? 'dark' : 'light')};
      window.__LEGADO_COLOR_SCHEME__=scheme;
      window.__LEGADO_DARK_MODE__=${dark};
      ${inlineDocument ? 'window.__LEGADO_COMMENT_INLINE__=true;' : ''}
      try{localStorage.setItem('cmt-theme',scheme);}catch(_){}
      function prime(){
        var root=document.documentElement;if(!root)return false;
        root.style.colorScheme=scheme;
        root.setAttribute('data-legado-color-scheme',scheme);
        if(!document.getElementById('legado-theme-bootstrap')){
          var guard=document.createElement('style');guard.id='legado-theme-bootstrap';
          guard.textContent='html{background:${dark ? '#131313' : '#FFFFFF'}!important;}body{visibility:hidden!important;}';
          (document.head||root).appendChild(guard);
        }
        return true;
      }
      if(!prime()){
        var observer=new MutationObserver(function(){if(prime())observer.disconnect();});
        observer.observe(document,{childList:true,subtree:true});
      }
    })()`;
  }

  /** 网页没有浏览历史时，返回必须交给半模态宿主，而不是停在当前文档。 */
  static navigation(): string {
    return `if(!window.__LEGADO_COMMENT_NAV_BOUND__){
      window.__LEGADO_COMMENT_NAV_BOUND__=true;
      var originalBack=history.back.bind(history),originalGo=history.go.bind(history),originalClose=window.close.bind(window);
      history.back=function(){
        if(window.LegadoCommentHost){window.LegadoCommentHost.back();return;}
        return originalBack();
      };
      history.go=function(delta){
        if(Number(delta)===-1&&window.LegadoCommentHost){window.LegadoCommentHost.back();return;}
        return originalGo(delta);
      };
      window.close=function(){
        if(window.LegadoCommentHost){window.LegadoCommentHost.close();return;}
        return originalClose();
      };
    }`;
  }

  /** loadData 的启动文档也要带上主题，不能依赖 about:blank 的回调或注入时机。 */
  static prepareHtml(html: string, dark: boolean): string {
    const script = `<script>${ReaderCommentWebTheme.bootstrap(dark, true)}</script>`;
    const head = /<head\b[^>]*>/i.exec(html);
    if (head) {
      const offset = head.index + head[0].length;
      return html.substring(0, offset) + script + html.substring(offset);
    }
    const root = /<html\b[^>]*>/i.exec(html);
    if (root) {
      const offset = root.index + root[0].length;
      return html.substring(0, offset) + `<head>${script}</head>` + html.substring(offset);
    }
    const doctype = /^\s*<!doctype[^>]*>/i.exec(html);
    const offset = doctype ? doctype[0].length : 0;
    return html.substring(0, offset) + script + html.substring(offset);
  }

  /** 返回 1 表示当前文档的主题已跨过两次绘制帧；加载或绘制尚未完成时返回 0。 */
  static apply(dark: boolean, inlineDocument: boolean): string {
    return `(function(){
      var scheme=${JSON.stringify(dark ? 'dark' : 'light')},dark=${dark};
      var root=document.documentElement,body=document.body;
      if(!root||!body||document.readyState==='loading')return 0;
      if(${inlineDocument}&&!window.__LEGADO_COMMENT_INLINE__)return 0;
      if(!${inlineDocument}&&location.href==='about:blank')return 0;
      if(window.__LEGADO_THEME_PAINTED__===scheme)return 1;
      if(window.__LEGADO_THEME_APPLIED__===scheme)return 0;
      var guard=document.getElementById('legado-theme-bootstrap');
      if(guard)guard.remove();
      root.style.colorScheme=scheme;
      root.setAttribute('data-legado-color-scheme',scheme);
      var ownToggle=!!(document.getElementById('themeToggle')&&typeof window.toggleCmtTheme==='function');
      if(ownToggle){
        if(body.classList.contains('dark')!==dark)window.toggleCmtTheme();
        try{localStorage.setItem('cmt-theme',scheme);}catch(_){}
        body.classList.toggle('dark',dark);
      }
      window.__LEGADO_COLOR_SCHEME__=scheme;window.__LEGADO_DARK_MODE__=dark;
      window.dispatchEvent(new CustomEvent('legado-color-scheme-change',{detail:{colorScheme:scheme,dark:dark}}));
      var fallback=document.getElementById('legado-dark-fallback');
      if(fallback)fallback.remove();
      var canvas=document.getElementById('legado-comment-canvas');
      if(canvas)canvas.remove();
      if(dark&&!ownToggle){
        var rgb=function(value){
          var match=/rgba?\\(([^)]+)\\)/.exec(value||'');if(!match)return null;
          var p=match[1].split(',').map(function(v){return parseFloat(v);});
          if(p.length>3&&p[3]<0.5)return null;
          return (0.2126*p[0]+0.7152*p[1]+0.0722*p[2])/255;
        };
        var bodyStyle=getComputedStyle(body),rootStyle=getComputedStyle(root);
        var bg=rgb(bodyStyle.backgroundColor);if(bg===null)bg=rgb(rootStyle.backgroundColor);
        var light=bg!==null?bg>0.6:((rgb(bodyStyle.color)||0)<0.4);
        if(light){
          root.style.colorScheme='light';
          // 根画布不能参与反色：拖动扩容时尚未绘制的区域会暴露原始白底。
          var fill=rgb(bodyStyle.backgroundColor)!==null?bodyStyle.backgroundColor:
            (rgb(rootStyle.backgroundColor)!==null?rootStyle.backgroundColor:'#fff');
          var css='body{background-color:'+fill+'!important;filter:invert(.92) hue-rotate(180deg)!important;}' +
            'img,video,picture,canvas,iframe,embed,object,[style*="background-image"]{filter:invert(1) hue-rotate(180deg)!important;}';
          fallback=document.createElement('style');fallback.id='legado-dark-fallback';fallback.textContent=css;
          (document.head||root).appendChild(fallback);
        }
      }
      canvas=document.createElement('style');canvas.id='legado-comment-canvas';
      canvas.textContent='html{background:${dark ? '#131313' : '#FFFFFF'}!important;min-height:100%;}body{min-height:100vh;box-sizing:border-box;}';
      (document.head||root).appendChild(canvas);
      window.__LEGADO_THEME_PAINTED__='';window.__LEGADO_THEME_APPLIED__=scheme;
      requestAnimationFrame(function(){requestAnimationFrame(function(){
        if(window.__LEGADO_THEME_APPLIED__===scheme)window.__LEGADO_THEME_PAINTED__=scheme;
      });});
      return 0;
    })()`;
  }
}
