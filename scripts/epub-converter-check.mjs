#!/usr/bin/env node
// EPUB XHTML → 阅读器正文转换、目录切章与图片标记的回归检查。
// 直接加载 entry 下的纯 TS 模块（EpubHtmlConverter / EpubChapterPlanner / ReaderImageMarker），
// 因此测到的就是应用实际运行的代码。
// Usage: node --experimental-strip-types scripts/epub-converter-check.mjs

import { loadReaderModules } from './lib/load-reader-modules.mjs';

const { EpubHtmlConverter, EpubImageRef, EpubChapterPlanner, EpubTocEntry, ReaderImageMarker, cleanup } =
  await loadReaderModules();

let failures = 0;
const check = (condition, message, detail = '') => {
  if (condition) {
    console.log(`  ok - ${message}`);
  } else {
    failures++;
    console.error(`  FAIL - ${message}${detail ? `\n         ${detail}` : ''}`);
  }
};
const equal = (actual, expected, message) =>
  check(actual === expected, message, `expected ${JSON.stringify(expected)}\n         actual   ${JSON.stringify(actual)}`);

// 图片解析桩：路径即 src，尺寸由表给出。
const sizes = { 'cover.jpg': [1200, 1800], 'gaiji.png': [32, 32], 'divider.png': [600, 40] };
const resolve = (src) => {
  if (src === 'missing.jpg') return null;
  const ref = new EpubImageRef();
  ref.path = `/book/${src}`;
  const size = sizes[src];
  if (size) {
    ref.width = size[0];
    ref.height = size[1];
  }
  return ref;
};
const convert = (body, startId = '', endId = '') =>
  EpubHtmlConverter.convert(`<html><head><title>T</title><style>p{}</style></head><body>${body}</body></html>`,
    resolve, startId, endId);
const marker = (src) => {
  const size = sizes[src] || [0, 0];
  return ReaderImageMarker.create(`/book/${src}`, size[0], size[1]);
};

try {
  console.log('whitespace');
  equal(convert('<p>It was the best of times,\n   it was the worst of times,\n   it was the age.</p>').content,
    'It was the best of times, it was the worst of times, it was the age.',
    '源码硬换行折叠为空格，不再拆成多个段落');
  equal(convert('<p>这是第一行\n    这是第二行</p>').content, '这是第一行这是第二行', '中文之间的源码换行不产生空格');
  equal(convert('<p>one</p>\n\n\n<p>two</p>   <div>three</div>').content, 'one\n\ntwo\n\nthree', '块级元素各成一段，段落之间是空行');
  equal(convert('<p>　　全角缩进保留</p>').content, '　　全角缩进保留', '段首全角缩进不被裁掉');
  equal(convert('<p>a<br/>b</p>').content, 'a\nb', '<br> 是块内换行，只输出单个换行');
  equal(convert('<pre>line 1\nline 2</pre>').content, 'line 1\n\nline 2', '<pre> 内的换行保留');
  equal(convert('<p>a<span>b</span><em>c</em> d</p>').content, 'abc d', '行内标签不引入空格');
  equal(convert('<h2>Chapter One</h2><p>Yes</p><p>No</p><p>诗一行<br/>诗二行<br/><img src="cover.jpg"/>诗三行</p>').content,
    `Chapter One\n\nYes\n\nNo\n\n诗一行\n诗二行\n\n${marker('cover.jpg')}\n\n诗三行`,
    '标题与短段落之间是空行（不会被阅读器当作软换行合并），块内 <br> 仍是单换行');

  console.log('semantics');
  equal(convert('<p><ruby>漢字<rp>(</rp><rt>かんじ</rt><rp>)</rp></ruby>を読む</p>').content, '漢字を読む',
    'ruby 注音不混入正文');
  equal(convert('<table><tr><td>a</td><td>b</td></tr><tr><td>c</td><td>d</td></tr></table>').content,
    'a | b\n\nc | d', '表格按行输出，单元格之间有分隔');
  equal(convert('<ul><li>one</li><li><p>two</p></li></ul>').content, '　• one\n\ntwo', '列表项带圆点，空圆点行被丢弃');
  equal(convert('<figure><img src="cover.jpg"/><figcaption>图注</figcaption></figure><p>正文</p>').content,
    `${marker('cover.jpg')}\n\n图注\n\n正文`, 'figcaption 独立成段');
  equal(convert('<dl><dt>词</dt><dd>释义</dd></dl>').content, '词\n\n释义', 'dt/dd 分行');
  equal(convert('<!-- <p>注释</p> --><p>正文</p><script>var a = "<p>x</p>";</script>').content, '正文',
    '注释与脚本不输出');
  equal(convert('<h2>第一章 <small>开端</small></h2><p>正文</p>').headingText, '第一章 开端', '提取第一个标题文本');
  equal(JSON.stringify(convert('<h1>卷一</h1><p>甲</p><h3><img src="gaiji.png"/>第一节</h3><h2></h2>').headings),
    JSON.stringify([{ level: 1, text: '卷一' }, { level: 3, text: '第一节' }]), '收集全部标题及其层级，忽略空标题');
  equal(convert('<p>水是 H<sub>2</sub>O，见注<sup>12</sup>，<sup><a href="#n">3</a></sup>，x<sup>n</sup></p>').content,
    '水是 H₂O，见注¹²，³，xn', '纯数字上下标转为 Unicode 上下标字符');

  console.log('entities');
  equal(convert('<p>&ldquo;Hi&rdquo;&mdash;he said&hellip; caf&eacute; &Eacute;cole &amp; &lt;b&gt;</p>').content,
    '“Hi”—he said… café École & <b>', '常见命名实体与大写变体');
  equal(convert('<p>&#x1F600;&#128512;&#xD800;&unknown;</p>').content, '\u{1F600}\u{1F600}&#xD800;&unknown;',
    '补充平面码点正确解码，非法实体原样保留');
  equal(convert('<p>a&nbsp;&nbsp;b</p>').content, 'a b', 'nbsp 按空白处理');

  console.log('images');
  equal(convert('<p>前文</p><div><img src="cover.jpg" alt="封面"/></div><p>后文</p>').content,
    `前文\n\n${marker('cover.jpg')}\n\n后文`, '块级图片输出带尺寸的标记');
  const info = ReaderImageMarker.parse(marker('cover.jpg'));
  check(info.source === '/book/cover.jpg' && info.width === 1200 && info.height === 1800, '标记可解析出路径与尺寸');
  equal(ReaderImageMarker.parse(ReaderImageMarker.create('https://a.b/c|d.jpg')).source, 'https://a.b/c|d.jpg',
    '无尺寸标记兼容旧格式（含 | 的地址不被误判）');
  equal(convert('<p>他写下了<img src="gaiji.png" alt="𠮷"/>这个字。</p>').content, '他写下了𠮷这个字。',
    '行内外字图片用 alt 顶替，段落不被截断');
  equal(convert('<p>他写下了<img src="gaiji.png"/>这个字。</p>').content, '他写下了这个字。', '无 alt 的行内小图被省略');
  equal(convert('<p><img src="gaiji.png"/></p>').content, marker('gaiji.png'), '独占一行的小图仍然是图片块');
  equal(convert('<p>说明文字<img src="cover.jpg"/>继续</p>').content,
    `说明文字\n\n${marker('cover.jpg')}\n\n继续`, '与文字同行的大图仍然独立成块');
  equal(convert('<p>a<img src="missing.jpg"/>b<img src="https://x/y.png"/>c</p>').content, 'a b c',
    '不存在或远程的图片被忽略');
  equal(convert('<svg><image xlink:href="cover.jpg" width="100%"/></svg>').content, marker('cover.jpg'),
    'SVG 包裹的封面图');
  equal(convert('<object data="cover.jpg" type="image/jpeg"></object><object data="a.swf"></object>').content,
    marker('cover.jpg'), 'object 只接受图片类型');
  check(convert('<img src="cover.jpg"/><img src="cover.jpg"/>').imagePaths.length === 1 &&
    !convert('<img src="cover.jpg"/>').hasText, 'imagePaths 去重，纯图片段 hasText=false');

  console.log('charset & paths');
  const bytes = (text) => Uint8Array.from(Buffer.from(text, 'latin1'));
  equal(EpubHtmlConverter.sniffCharset(bytes('<?xml version="1.0" encoding="GBK"?><html>')), 'gb18030', 'XML 声明 GBK');
  equal(EpubHtmlConverter.sniffCharset(bytes('<html><head><meta charset="Shift_JIS">')), 'shift_jis', 'meta charset');
  equal(EpubHtmlConverter.sniffCharset(bytes('<html><head><meta http-equiv="Content-Type" content="text/html; charset=big5">')),
    'big5', 'http-equiv 中的 charset');
  equal(EpubHtmlConverter.sniffCharset(Uint8Array.from([0xFF, 0xFE, 0x3C, 0x00])), 'utf-16le', 'UTF-16 BOM');
  equal(EpubHtmlConverter.sniffCharset(bytes('<html><body>plain</body></html>')), '', '未声明时返回空');
  equal(EpubHtmlConverter.resolvePath('/root/OEBPS/text', '../images/my%20pic.jpg#x', '/root'),
    '/root/OEBPS/images/my pic.jpg', '相对路径解码并归一化');
  equal(EpubHtmlConverter.resolvePath('/root/OEBPS/text', '/images/a.jpg', '/root'), '/root/images/a.jpg',
    '以 / 开头的引用相对容器根目录');

  console.log('anchors');
  const multi = '<h1 id="c1">一</h1><p>甲</p><h1 id="c2">二</h1><p>乙</p><div><a name="c3"></a><h1>三</h1><p>丙</p></div>';
  equal(convert(multi, 'c1', 'c2').content, '一\n\n甲', '按锚点切出第一段');
  equal(convert(multi, 'c2', 'c3').content, '二\n\n乙', '按锚点切出中间段');
  equal(convert(multi, 'c3', '').content, '三\n\n丙', 'name 锚点与文件结尾');
  equal(convert(multi, 'nope', '').content, convert(multi).content, '找不到起始锚点时退回整个文件');

  console.log('toc');
  const nav = `<nav epub:type="toc"><ol>
    <li><a href="text/ch1.xhtml">第一章</a><ol><li><a href="text/ch1.xhtml#s2">第二节</a></li></ol></li>
    <li><a href="text/ch%202.xhtml#top">第二章 &amp; 续</a></li>
    <li><a href="https://example.com">外链</a></li></ol></nav>
    <nav epub:type="landmarks"><a href="text/cover.xhtml">Cover</a></nav>`;
  const navEntries = EpubChapterPlanner.parseNavToc(nav, '/root/OEBPS', '/root');
  check(navEntries.length === 3 && navEntries[1].fragment === 's2' &&
    navEntries[2].path === '/root/OEBPS/text/ch 2.xhtml' && navEntries[2].title === '第二章 & 续',
    'nav 目录：嵌套条目、锚点、实体、忽略外链与 landmarks', JSON.stringify(navEntries));
  const ncx = `<ncx><navMap>
    <navPoint id="a"><navLabel><text>卷一</text></navLabel><content src="v1.xhtml"/>
      <navPoint id="b"><navLabel><text>第一章</text></navLabel><content src="v1.xhtml#c1"/></navPoint>
      <navPoint id="c"><navLabel><text>第二章</text></navLabel><content src="c2.xhtml"/></navPoint>
    </navPoint>
    <navPoint id="d"><navLabel><text>后记</text></navLabel><content src="end.xhtml"/></navPoint></navMap></ncx>`;
  const ncxEntries = EpubChapterPlanner.parseNcxToc(ncx, '/root', '/root');
  equal(ncxEntries.map((entry) => entry.title).join(','), '卷一,第一章,第二章,后记', 'NCX 嵌套 navPoint 的第一个子项不再丢失');

  console.log('chapter planning');
  const toc = (path, fragment, title) => {
    const entry = new EpubTocEntry();
    entry.path = path;
    entry.fragment = fragment;
    entry.title = title;
    return entry;
  };
  const plan = (files, tocEntries) => {
    const grouped = EpubChapterPlanner.groupTocByPath(tocEntries);
    const planner = new EpubChapterPlanner(grouped.size > 0);
    for (const file of files) {
      planner.beginFile();
      for (const cut of EpubChapterPlanner.planFileCuts(file.body, grouped.get(file.path) || [])) {
        planner.addPiece(file.path, cut.startId, cut.endId, cut.title,
          EpubHtmlConverter.convertBody(file.body, resolve, cut.startId, cut.endId), file.title || '');
      }
      planner.endFile();
    }
    return planner;
  };

  // 一个文件多章 + 被拆分工具切开的章节 + 未入目录的插图页
  const book = plan([
    { path: '/b/cover.xhtml', body: '<img src="cover.jpg"/>' },
    { path: '/b/v1.xhtml', body: '<div id="c1"><h1>第一章</h1><p>甲</p></div><div id="c2"><h1>第二章</h1><p>乙</p></div>' },
    { path: '/b/v1_split_001.xhtml', body: '<p>乙的后半</p>' },
    { path: '/b/illus.xhtml', body: '<img src="cover.jpg"/>' },
    { path: '/b/c3.xhtml', body: '<h1>第三章</h1><p>丙</p>' },
  ], [toc('/b/v1.xhtml', '', '卷一'), toc('/b/v1.xhtml', 'c1', '第一章'), toc('/b/v1.xhtml', 'c2', '第二章'),
    toc('/b/c3.xhtml', '', '第三章')]);
  equal(book.chapters.map((chapter) => chapter.title).join(','), '封面,卷一 第一章,第二章,第三章',
    '按目录切章：指向同一位置的条目合并标题，无目录条目的文件不单独成章');
  check(book.chapters[2].segments.length === 3 && book.chapters[2].content.includes('乙的后半') &&
    book.chapters[2].content.endsWith(marker('cover.jpg')), '拆分文件与插图页并入前一章',
    JSON.stringify(book.chapters[2]));
  check(book.chapters[1].segments[0].endId === 'c2' && book.chapters[2].segments[0].startId === 'c2',
    '片段记录锚点范围');
  check(!book.isComicDominant() && book.spineFileCount === 5 && book.imageOnlyFileCount === 2,
    '少量插图页不识别为漫画');
  equal(EpubChapterPlanner.chapterIndexForPath(book.chapters, '/b/illus.xhtml'), 2, '按文件迁移阅读进度（并入的文件）');
  equal(EpubChapterPlanner.chapterIndexForPath(book.chapters, '/b/v1.xhtml#c2'), 1, '按文件迁移阅读进度（多章文件取第一章）');
  equal(EpubChapterPlanner.chapterIndexForPath(book.chapters, '/b/gone.xhtml'), -1, '找不到文件返回 -1');

  const encoded = EpubChapterPlanner.encodeVariable(book.chapters[2].segments, book.chapters[2].headings);
  equal(JSON.stringify(EpubChapterPlanner.decodeSegments(encoded)), JSON.stringify(book.chapters[2].segments),
    '片段列表可往返序列化');
  equal(JSON.stringify(EpubChapterPlanner.decodeHeadings(encoded)), JSON.stringify([{ level: 1, text: '第二章' }]),
    '章内标题随章节保存并可还原');
  equal(EpubChapterPlanner.decodeHeadings(EpubChapterPlanner.encodeVariable(book.chapters[0].segments)).length, 0,
    '没有标题的章节不写入标题列表');
  equal(EpubChapterPlanner.decodeSegments('').length + EpubChapterPlanner.decodeSegments('{"k":1}').length +
    EpubChapterPlanner.decodeSegments('{"epubSegments":').length, 0, '非法 variable 返回空片段');

  // 锚点之前的内容归上一章
  const leading = plan([
    { path: '/b/a.xhtml', body: '<p>甲</p>' },
    { path: '/b/b.xhtml', body: '<p>甲的结尾</p><h1 id="x">乙章</h1><p>乙</p>' },
  ], [toc('/b/a.xhtml', '', '甲章'), toc('/b/b.xhtml', 'x', '乙章')]);
  check(leading.chapters.length === 2 && leading.chapters[0].content === '甲\n\n甲的结尾' &&
    leading.chapters[1].content === '乙章\n\n乙', '第一个锚点之前的内容并入上一章', JSON.stringify(leading.chapters));

  // 没有目录：一个文件一章，取标题或 <title>
  const noToc = plan([
    { path: '/b/1.xhtml', body: '<img src="cover.jpg"/>' },
    { path: '/b/2.xhtml', body: '<h2>序</h2><p>甲</p>' },
    { path: '/b/3.xhtml', body: '<p>乙</p>', title: '文档标题' },
    { path: '/b/4.xhtml', body: '<p>丙</p>' },
    { path: '/b/5.xhtml', body: '  <p> </p> ' },
  ], []);
  equal(noToc.chapters.map((chapter) => chapter.title).join(','), '封面,序,文档标题,第4节',
    '无目录时一个文件一章，空文件被跳过');

  // 目录残缺：超过长度上限后另起续篇
  const long = '<p>' + '字'.repeat(70000) + '</p>';
  const sparse = plan([
    { path: '/b/1.xhtml', body: '<p>开始</p>' }, { path: '/b/2.xhtml', body: long },
    { path: '/b/3.xhtml', body: long }, { path: '/b/4.xhtml', body: long },
  ], [toc('/b/1.xhtml', '', '正文')]);
  equal(sparse.chapters.map((chapter) => chapter.title).join(','), '正文,正文（2）,正文（3）',
    '目录残缺的长内容按长度上限拆成续篇');

  // 漫画识别
  const comic = plan([1, 2, 3, 4, 5].map((n) => ({ path: `/b/${n}.xhtml`, body: '<img src="cover.jpg"/>' })), []);
  check(comic.isComicDominant(), '纯图 spine 识别为漫画');

  // 锚点索引：与逐个正则查找的结果一致
  {
    const body = `<p>id="fake"</p><div class="x" id="a1">一</div><a name='n1'></a>` +
      '<span xml:id="x1">二</span><p id="a1">重复</p><h2 title="t" id="h-1.2">三</h2><br/>';
    equal(EpubHtmlConverter.findAnchorOffset(body, 'a1'), body.indexOf('<div class="x"'), '同名 id 取第一次出现');
    equal(EpubHtmlConverter.findAnchorOffset(body, 'n1'), body.indexOf('<a name='), 'name 属性与单引号');
    equal(EpubHtmlConverter.findAnchorOffset(body, 'x1'), body.indexOf('<span'), 'xml:id');
    equal(EpubHtmlConverter.findAnchorOffset(body, 'h-1.2'), body.indexOf('<h2'), '含正则特殊字符的 id');
    equal(EpubHtmlConverter.findAnchorOffset(body, 'fake'), -1, '正文文字里的 id= 不算锚点');
    equal(EpubHtmlConverter.findAnchorOffset(body, ' a1 '), body.indexOf('<div class="x"'), '查找前去掉首尾空白');
    equal(EpubHtmlConverter.findAnchorOffset(body, ''), 0, '空 id 表示文件开头');
    equal(EpubHtmlConverter.findAnchorOffset('<p id="z">另一个文件</p>', 'a1'), -1, '换了 body 重新建索引');
    equal(EpubHtmlConverter.findAnchorOffset(body, 'x1'), body.indexOf('<span'), '切回原 body 仍正确');
  }

  // 单文件上千章：按锚点切章不再随章数平方增长
  {
    const count = 3000;
    const parts = [];
    const entries = [];
    for (let n = 1; n <= count; n++) {
      parts.push(`<h2 id="c${n}">第${n}章</h2><p>${'正文'.repeat(40)}</p>`);
      entries.push(toc('/big.xhtml', `c${n}`, `第${n}章`));
    }
    const started = performance.now();
    const planned = plan([{ path: '/big.xhtml', body: parts.join('') }], entries);
    const elapsed = performance.now() - started;
    equal(planned.chapters.length, count, '单文件 3000 个目录锚点切成 3000 章');
    equal(planned.chapters[count - 1].title, `第${count}章`, '最后一章标题正确');
    // 改前同一用例约 1.4 秒（每切一章都从头正则扫描整个文件），改后约 50ms。
    check(elapsed < 800, `单文件 3000 章切章耗时 ${elapsed.toFixed(0)}ms`);
  }
} finally {
  cleanup();
}

console.log(failures === 0 ? '\nALL CHECKS PASSED' : `\n${failures} CHECK(S) FAILED`);
process.exit(failures === 0 ? 0 : 1);
