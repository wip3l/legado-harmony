# Legado Harmony 书源开发文档

> 适用范围：`legado-harmony` 当前书源实现（基准提交 `b608cd4`，2026-07-16）。  
> 本文描述的是本项目**已经实现并实际调用**的规则，而不是 Android「阅读」全部规则的等价清单。导入其他项目的书源时，应特别留意[兼容性与当前限制](#兼容性与当前限制)。

## 1. 书源是什么

书源是一份 JSON 配置。它告诉应用：

1. 去哪里搜索书籍；
2. 如何从搜索或发现响应中找出每一本书；
3. 如何打开详情页并提取书籍信息和目录地址；
4. 如何从目录响应中提取章节；
5. 如何请求章节并提取、净化正文。

一条书源的典型数据流如下：

```text
搜索地址 / 发现地址
  -> HTTP 响应
  -> bookList 选出“书籍元素”
  -> 在每个元素内解析 name / author / bookUrl 等
  -> 请求 bookUrl
  -> init 可选地缩小详情解析范围
  -> 解析详情字段和 tocUrl
  -> 请求 tocUrl
  -> chapterList 选出“章节元素”
  -> 在每个元素内解析 chapterName / chapterUrl
  -> 请求 chapterUrl
  -> content 提取正文
  -> replaceRegex 净化
  -> HTML 转纯文本
```

这里最重要的概念是“当前元素”：

- `bookList`、`chapterList` 在完整响应上运行，返回多个元素；
- 书名、作者、章节名等子规则分别在单个元素上运行；
- JSON 元素会被序列化为 JSON 字符串，HTML 元素会保留该元素的完整 HTML；
- 所以子规则通常从 `$.字段` 或元素内部的 CSS 选择器开始，而不必重复列表的完整路径。

## 2. 最小可用书源

下面是一个 JSON API 书源骨架。实际开发时优先从这种小配置开始，先跑通“搜索 → 详情 → 目录 → 正文”，再补发现和可选字段。

```json
[
  {
    "bookSourceName": "示例小说",
    "bookSourceGroup": "API",
    "bookSourceUrl": "https://api.example.com",
    "enabled": true,
    "enabledExplore": true,
    "header": "{\"User-Agent\":\"Mozilla/5.0\"}",
    "searchUrl": "/search?keyword={{key}}&page={{page}}",
    "exploreUrl": "热门::/books/hot?page={{page}}",
    "ruleSearch": {
      "bookList": "$.data.books[*]",
      "name": "$.title",
      "author": "$.author",
      "coverUrl": "$.cover",
      "intro": "$.intro",
      "kind": "$.category",
      "lastChapter": "$.lastChapter",
      "bookUrl": "/book/{{$.id}}",
      "wordCount": "$.wordCount"
    },
    "ruleExplore": {
      "bookList": "$.data.books[*]",
      "name": "$.title",
      "author": "$.author",
      "coverUrl": "$.cover",
      "intro": "$.intro",
      "kind": "$.category",
      "lastChapter": "$.lastChapter",
      "bookUrl": "/book/{{$.id}}",
      "wordCount": "$.wordCount"
    },
    "ruleBookInfo": {
      "init": "$.data",
      "name": "$.title",
      "author": "$.author",
      "coverUrl": "$.cover",
      "intro": "$.intro",
      "kind": "$.category",
      "lastChapter": "$.lastChapter",
      "wordCount": "$.wordCount",
      "updateTime": "$.updateTime",
      "tocUrl": "/book/{{$.id}}/chapters"
    },
    "ruleToc": {
      "chapterList": "$.data.chapters[*]",
      "chapterName": "$.title",
      "chapterUrl": "/chapter/{{$.id}}",
      "isVip": "$.isVip",
      "isPay": "$.isPay",
      "updateTime": "$.updateTime"
    },
    "ruleContent": {
      "content": "$.data.content",
      "replaceRegex": "本章未完，请点击下一页继续阅读"
    }
  }
]
```

搜索阶段目前固定使用第 1 页，因此 `{{page}}` 在搜索地址中为 `1`；发现页会传入实际页码。

## 3. JSON 顶层结构与导入格式

应用支持三种导入外壳：

```json
[{ "bookSourceUrl": "...", "bookSourceName": "..." }]
```

```json
{ "value": [{ "bookSourceUrl": "...", "bookSourceName": "..." }] }
```

```json
{ "bookSourceUrl": "...", "bookSourceName": "..." }
```

只有同时具有 `bookSourceUrl` 和 `bookSourceName` 的项目才会被写入数据库。`bookSourceUrl` 也是书源的唯一身份标识；修改它通常会被视为另一个书源。

规则组推荐使用 Android 阅读常见的导出键名：

- `ruleSearch`
- `ruleExplore`
- `ruleBookInfo`
- `ruleToc`
- `ruleContent`

导入器也接受本项目内部键名 `searchRule`、`exploreRule`、`bookInfoRule`、`tocRule`、`contentRule`。规则组既可为对象，也可为紧凑字符串；为便于审阅、转义和版本管理，推荐使用对象。

紧凑字符串示例：

```text
@{bookList=$.data;name=$.title;author=$.author;bookUrl=/book/{{$.id}}}
```

字段以顶层分号分隔，字段名和值以第一个 `=` 分隔。复杂 JS、正则或包含分号的值更容易产生歧义，不建议新书源使用此格式。

## 4. 顶层字段

| JSON 字段 | 编辑器名称 | 类型/默认值 | 当前作用 |
| --- | --- | --- | --- |
| `bookSourceName` | 书源名称 | 字符串，必填 | UI 展示名称。 |
| `bookSourceUrl` | 书源地址 | 字符串，必填 | 书源唯一键，也是相对请求地址的基础地址。建议写协议和主机，不带末尾业务路径。 |
| `bookSourceGroup` | 书源分组 | 字符串 | 搜索筛选和管理分组。 |
| `bookSourceComment` | 书源备注 | 字符串 | 管理页说明，也会注入规则上下文。 |
| `loginUrl` | 登录地址 | 字符串 | 网页登录/验证入口。检测到登录或验证页时可打开该地址并同步 Cookie。 |
| `loginUi` | 暂无编辑项 | 字符串 | 导入和保存支持；用于判断该源存在登录能力。 |
| `loginCheckJs` | 登录检测JS | 字符串 | 导入、保存及登录能力识别支持；当前不是通用完整 JS 登录框架。 |
| `loginHeader` | 登录密钥 | 字符串 | 可用于特定登录源；通用请求头仍应写在 `header`。 |
| `bookUrlPattern` | URL正则 | 字符串 | 保存和导入支持，用于描述书籍 URL；当前主解析链不依赖它。 |
| `searchUrl` | 搜索地址 | 字符串 | 搜索请求模板。 |
| `exploreUrl` | 发现地址 | 字符串 | 发现分类及请求模板。 |
| `jsLib` | JS库 | 字符串 | 注入规则上下文，部分兼容逻辑会读取；不是浏览器中的任意 JavaScript 运行环境。 |
| `header` | 请求头 | 字符串 | 书源全局 HTTP 请求头。支持 JSON/宽松对象或每行一个 `名称: 值`。 |
| `variableComment` / `variable` | 暂无编辑项 | 字符串 | 作为 `source.variable` 注入上下文，兼容部分源变量。 |
| `enabled` | 启用书源 | 布尔，默认 `true` | 是否参与搜索和书源选择。 |
| `enabledExplore` | 启用发现 | 布尔，默认 `true` | 是否显示此源的发现入口。 |
| `weight` | 权重 | 数字，默认 `0` | 搜索相关度相同时，权重较大者优先。 |
| `customOrder` | 暂无编辑项 | 数字 | 模型和数据库可保存，并作为结果排序的次级依据；当前 JSON 导入器不映射该字段。 |
| `lastUpdateTime` | 暂无编辑项 | 数字 | 导入时会重置为当前时间。 |
| `concurrentRate` | 暂无编辑项 | 字符串 | 模型和数据库可保存，但当前 JSON 导入器不映射，书源搜索调度也不按此字段限流。 |

诸如 `bookSourceType`、`enabledCookieJar`、`respondTime` 等常见导出字段可以出现在 JSON 中，但当前通用书源导入器不会将它们映射到 `BookSource` 模型。Cookie 会由项目的 Cookie 存储和验证流程按请求 URL 自动附加，不依赖 `enabledCookieJar`。

## 5. URL 与 HTTP 请求规则

### 5.1 相对地址

请求地址可以是：

- 完整地址：`https://api.example.com/search`；
- 协议相对地址：`//cdn.example.com/cover.jpg`，解析为 HTTPS；
- 根相对地址：`/search`，拼到 `bookSourceUrl` 的主机；
- 普通相对地址：`search`，拼到基础地址后；
- `data:` URL，支持普通百分号编码和 Base64 内容。

列表中提取的详情地址、封面地址和章节地址也会按响应最终 URL 解析相对路径。HTTP 3xx 最多跟随 3 次；301、302、303 对非 GET/HEAD 请求会切换为 GET。

为了避免不同阶段对“普通相对路径”的基准处理差异，书源地址建议只写站点根地址，业务请求和规则生成的 URL 优先写 `/` 开头的根相对地址；尤其是详情规则的 `tocUrl`，不要依赖 `chapters/list` 这类无前导斜杠的路径。

### 5.2 搜索变量

搜索地址可使用：

| 模板 | 值 |
| --- | --- |
| `{{key}}` | `encodeURIComponent` 编码后的关键字。 |
| `{{searchKey}}` | 同 `key`。 |
| `{{keyword}}` | 同 `key`。 |
| `{{searchKeyRaw}}` | 未编码的原始关键字。最终 URL 参数仍会按请求字符集编码。 |
| `{{page}}` | 当前实现为 `1`。 |
| `{{source.bookSourceUrl}}` | 当前书源地址。 |
| `{{source.bookSourceName}}` | 当前书源名称。 |
| `{{source.bookSourceGroup}}` | 当前书源分组。 |

示例：

```text
/search?q={{key}}&page={{page}}
/search.asp?word={{searchKeyRaw}},{"charset":"gb2312"}
```

避免对 `{{key}}` 再手工 URL 编码，否则可能双重编码。目标站要求 GBK/GB2312 时，使用 `searchKeyRaw` 配合 `charset`。

### 5.3 发现变量与分类格式

发现页支持 `{{page}}` 和 `{{pageIndex}}`。最稳定的配置是一行一个分类：

```text
热门::/rank/hot?page={{page}}
完结::/rank/finished?page={{page}}
```

也支持 JSON 数组：

```json
[
  { "title": "排行榜", "url": "" },
  { "title": "热门", "url": "/rank/hot?page={{page}}" },
  { "title": "完结", "url": "/rank/finished?page={{page}}" }
]
```

数组中没有 `url` 的条目会成为后续条目的分组标题。指向“我的书架”、用户页或登录页的个人入口会被过滤。

### 5.4 URL 选项对象

在 URL 后追加逗号和对象可配置请求：

```text
/api/search,{"method":"POST","body":"keyword={{searchKeyRaw}}&page={{page}}","charset":"utf-8","headers":{"Referer":"https://example.com/"},"retry":1}
```

支持的选项：

| 选项 | 说明 |
| --- | --- |
| `method` | HTTP 方法，默认 `GET`。 |
| `body` | 字符串或对象；对象会 JSON 序列化。 |
| `charset` | URL 查询和表单编码字符集，如 `utf-8`、`gbk`、`gb2312`、`gb18030`、`escape`。 |
| `headers` | 本次请求头；同名项覆盖书源全局请求头。 |
| `retry` | 响应不可用时的额外重试次数。 |
| `type` | 会被解析并保存到请求配置，当前 HTTP 执行链没有额外分支行为。 |
| `webView` | 会被解析为布尔值，当前通用请求仍走 HTTP 客户端。 |
| `webJs` | 会被解析并保存，当前通用请求不会执行。 |

选项对象支持单引号、无引号键和尾逗号等宽松写法，但推荐使用标准 JSON，减少转义差异。

POST 还有一种简写：地址以 `@` 开头，`?` 后内容作为 body。

```text
@/api/search?keyword={{searchKeyRaw}}&page={{page}}
```

表单 body 会编码为空格使用 `+` 的形式。未显式提供 `Content-Type` 时：JSON 对象 body 使用 `application/json; charset=utf-8`，其他 body 使用 `application/x-www-form-urlencoded`。

### 5.5 请求头

推荐 JSON：

```json
{
  "User-Agent": "Mozilla/5.0",
  "Accept": "application/json",
  "Referer": "https://example.com/"
}
```

也支持逐行格式：

```text
User-Agent: Mozilla/5.0
Accept: application/json
```

URL 内还支持：

```text
/path@Header:{"Referer":"https://example.com/"}@End
```

合并顺序是“书源全局请求头 → 本次请求头”，因此本次请求头优先。若未显式设置 Cookie，应用会按请求地址从登录/验证 Cookie 存储中补充。

## 6. 通用解析语法

一个字段规则通常由三部分构成：

```text
提取规则##正则##替换文本@js:后处理
```

并非每部分都必须存在。执行顺序是先提取，再执行 `@js:` 后处理，最后执行 `##` 正则替换。尽量让规则保持单一职责，复杂转换分成 `init`、字段提取和净化三步。

### 6.1 JSONPath

JSON 响应优先使用 JSONPath：

```text
$.data.books[*]
$.title
$['data']['title']
$..chapters[*]
$.items[0]
$.items[-1]
$.items[0,2,4]
$.items[1:5]
$.items[::-1]
$.items[?(@.status == 1)]
$.items[?(@.name =~ /小说/i)]
```

当前支持：

- 点号属性、方括号引号属性；
- `*` 通配；
- `..` 递归属性和递归通配；
- 正负数组下标、下标列表；
- `[start:end:step]` 切片；
- 过滤器中的 `&&`、`||`、`!`；
- 比较操作 `==`、`!=`、`>`、`<`、`>=`、`<=`；
- 正则比较 `=~ /pattern/i`；
- 属性是否存在判断。

`@.field` 会按当前 JSON 对象的 `$.field` 处理。JSON 内容中还允许 `.field` 或简单裸字段 `field`，但推荐显式写 `$.field`，可读性和可移植性更好。`@json:路径` 可以强制按 JSONPath 解析。

### 6.2 CSS 选择器

HTML 响应优先使用 CSS 风格规则：

```text
.book-item
.book-item .title@text
a.detail@href
img.cover@data-src
meta[name=description]@content
ul.list > li
li:contains(完结)
li:has(a[href*=book])
a:not(.disabled)
a:not([rel=nofollow])
li:first
li:last
li:eq(2)
li:lt(5)
li:gt(2)
li:nth-child(2)
li:nth-of-type(2)
```

已实现的主要能力：

- 标签、`#id`、`.class`，可组合多个 class；
- 后代和直接子代 `>`；
- 逗号分组；
- 属性存在及 `=`、`^=`、`$=`、`*=`、`~=`、`|=`；
- `:contains()`、单层 `:has()`、`:not()`；
- `:first`、`:last`、`:eq(n)`、`:lt(n)`、`:gt(n)`；
- 数字形式的 `:nth-child(n)`、`:nth-of-type(n)`；
- `@text`、`@html`、`@ownText`、`@textNodes` 和属性提取。

未写提取后缀时，普通 CSS 字段默认返回文本；列表规则会保留完整元素供子规则继续解析。

常用提取后缀：

| 后缀 | 结果 |
| --- | --- |
| `@text` | 去标签后的全部文本。 |
| `@ownText` | 元素自身直接文本，尽量排除子元素内容。 |
| `@textNodes` | 直接文本节点按换行连接。 |
| `@html` | 完整元素 HTML。 |
| `@href`、`@src`、`@content`、`@title` 等 | 对应属性值。自定义合法属性名也可提取。 |

选择器解析由项目内轻量解析器完成，并非完整浏览器 DOM/CSS 引擎。不要依赖复杂嵌套伪类、`an+b` 形式的 `nth-child`、伪元素或现代 CSS 全集。单个 HTML 响应超过 4 MiB 时，列表 CSS/正则解析会受保护性限制；大接口优先使用 JSONPath 或缩小响应。

### 6.3 基础 XPath

支持一部分可转换为 CSS 的 XPath：

```text
//div[@class='book']/a/text()
//a[contains(@href,'book')]/@href
//li[contains(.,'完结')]
//ul/li[1]
//li[last()]
```

支持属性相等、`contains(@attr, ...)`、`starts-with(@attr, ...)`、文本包含、数字位置、`last()`、属性存在以及末尾 `/@attr`、`/text()`。复杂轴、函数、变量和完整 XPath 表达式不受支持；新源推荐 JSONPath 或 CSS。

### 6.4 组合规则

| 运算符 | 行为 | 示例 |
| --- | --- | --- |
| `规则1||规则2` | 依次尝试，返回第一个非空结果。 | `.title@text||h1@text` |
| `规则1&&规则2` | 将各规则的结果顺序拼接为一个结果列表。 | `.name@text&&.alias@text` |
| `规则1%%规则2` | 按索引交错合并多个结果列表。 | `.name@text%%.url@href` |

分隔符在引号、圆括号、方括号和花括号内不会拆分，因此 JSONPath 过滤器中的 `&&`、`||` 可以正常使用。

### 6.5 模板拼接

双花括号会在当前元素中求值：

```text
/book/{{$.book_id}}
{{$.category}},{{$.status}}
https://cdn.example.com/{{$.cover}}
```

同时兼容部分单花括号 JSONPath：

```text
/book/{$.book_id}
```

模板中可读取上下文变量：

```text
{{source.bookSourceUrl}}
{{source.bookSourceName}}
{{source.bookSourceGroup}}
{{source.bookSourceComment}}
{{source.getKey()}}
{{source.getVariable()}}
```

详情、目录、正文阶段还会注入 `book.bookUrl`、`bookUrl`，并尽量从详情 URL 提取 `book`、`book_id`、`id`。

### 6.6 正则提取与替换

字段后处理使用：

```text
原规则##正则##替换文本
原规则##正则
```

示例：

```text
$.author##^作者：
title@text##^《|》$
$.status##^1$##连载
```

正则以 JavaScript `RegExp` 的全局模式执行。第三段省略时替换为空字符串；替换文本支持 `$1` 等捕获组引用。字面量 `##` 可写成 `\##`。

还支持直接正则规则：

- 以 `%` 开头时，对完整内容运行一次非全局正则，并返回完整匹配和捕获组；
- 普通“像正则”的规则会以全局模式运行。有捕获组时，每个匹配会变为 `{"$0":"...","$1":"..."}`，后续可用 `$['$1']` 一类路径读取。

直接正则的兼容行为较特殊，稳定书源更适合用 CSS/JSONPath 提取后再用 `##` 净化。

### 6.7 上下文变量 `@put` / `@get`

可以在规则中保存并读取字符串变量：

```text
@put:{bookId:$.id}$.title
@get:{bookId}
/chapter/@get:{bookId}/{{$.id}}
```

`@put:{key:value}` 中可用逗号或分号分隔多项；值会先按普通规则求值。上下文会从搜索结果保存到书籍，并在详情、目录和正文阶段恢复，因此可用于跨阶段携带站点 ID。章节还会保存其解析时的 `baseUrl`。

注意：列表中的每个搜索/发现元素会创建自己的规则上下文，搜索得到的变量会写入该书籍；目录中的章节共用书籍上下文。避免用相同键保存会在章节之间互相覆盖的临时值。

### 6.8 JavaScript 兼容层

规则支持以下形态：

```text
<js>表达式</js>
$.status@js:result.replace(/1/g, "连载")
@js:'https://example.com/chapter/'+$.id
js:表达式
```

但这里不是浏览器、Node.js 或完整 JavaScript 引擎，而是面向常见书源表达式的兼容执行器。已覆盖的常用能力包括：

- 字符串拼接和简单变量赋值；
- `result.replace(/正则/g, "文本")` 等常见替换链；
- 简单数值 `+ - * / %` 和 `Math.round/floor/ceil`；
- `Date.now()`、部分 `new Date()` 取值；
- `encodeURIComponent`、`encodeURI`；
- `java.urlEncode/urlDecode`；
- Base64、Hex、MD5、SHA-1、SHA-256；
- AES、DES/3DES 的常见 Base64 加解密；
- `java.getString`、`java.getStringList` 读取当前 JSON；
- `java.timeFormat`；
- `java.getCookie`、`cookie.getCookie/setCookie/removeCookie`；
- `java.randomUUID()`、`java.androidId()`；
- 部分 `java.put/get` 和 source 变量调用。

不要假定支持任意函数定义、网络请求、DOM API、Promise、第三方库或复杂 JavaScript 语义。复杂源应先用一个最小表达式实机验证；若规则依赖完整 JS 环境，当前版本可能需要代码级适配。

## 7. 各阶段规则字段

### 7.1 搜索规则 `ruleSearch`

当前要让书源参与搜索，至少必须配置：`searchUrl`、`bookList`、`name`、`bookUrl`。

| 字段 | 必需 | 解析上下文 | 当前用途 |
| --- | --- | --- | --- |
| `bookList` | 是 | 完整搜索响应 | 选出书籍元素。 |
| `name` | 是 | 单个书籍元素 | 书名；空书名的结果会被丢弃。 |
| `author` | 否 | 单个书籍元素 | 作者。 |
| `coverUrl` | 否 | 单个书籍元素 | 封面；相对地址会解析。 |
| `intro` | 否 | 单个书籍元素 | 简介。 |
| `kind` | 否 | 单个书籍元素 | 分类/标签。 |
| `lastChapter` | 否 | 单个书籍元素 | 最新章节标题。 |
| `bookUrl` | 是 | 单个书籍元素 | 详情页；空地址的结果会被丢弃。 |
| `wordCount` | 否 | 单个书籍元素 | 字段可导入，但当前常规搜索链没有赋值；可在详情规则补全。 |

每个源常规搜索最多保留 100 条有效结果，并按 URL 去重。搜索会清理超长或异常字段；书名约 120 字符、作者约 120、简介约 1200、URL 约 2048 字符。

### 7.2 发现规则 `ruleExplore`

至少需要：`exploreUrl`、`bookList`、`name`、`bookUrl`。字段语义与搜索相同。发现链会读取 `wordCount`，并按“来源 + 详情 URL”去重。

### 7.3 详情规则 `ruleBookInfo`

详情请求地址来自搜索/发现的 `bookUrl`。

| 字段 | 当前用途 |
| --- | --- |
| `init` | 先在完整详情响应上执行；非空结果成为其余详情字段的新解析内容。适合 `$.data` 或 `.book-info@html`。 |
| `name` | 更新书名；空结果保留列表页值。 |
| `author` | 更新作者；空结果保留列表页值。 |
| `coverUrl` | 补充封面。当前逻辑优先保留列表页已有封面。 |
| `intro` | 更新简介，经过字段清理后择优保留。 |
| `kind` | 更新分类。 |
| `lastChapter` | 更新最新章节。 |
| `wordCount` | 更新字数。 |
| `updateTime` | 字段可导入和编辑，但当前通用详情链尚未写入书籍。 |
| `tocUrl` | 目录请求地址；以 URL 模式解析相对地址。为空时会尝试依据书籍 URL 和规则模板兜底。 |

`init` 返回的是字符串。如果 JSONPath 命中对象，会被序列化成 JSON，因此后续仍可用 JSONPath；如果 CSS 命中元素，建议显式用 `@html` 保留 HTML。

### 7.4 目录规则 `ruleToc`

| 字段 | 必需 | 当前用途 |
| --- | --- | --- |
| `chapterList` | 是 | 在完整目录响应中选出章节元素。 |
| `chapterName` | 建议 | 章节标题；空时自动使用“第 N 章”。 |
| `chapterUrl` | 是 | 正文请求地址；空地址的章节会被丢弃。 |
| `isVip` | 否 | 只有解析结果严格等于字符串 `true` 时标记 VIP。 |
| `isPay` | 否 | 可导入和编辑，当前通用目录链未消费。 |
| `updateTime` | 否 | 可导入和编辑，当前通用目录链未消费。 |
| `chapterListAddition` | 否 | 模型字段；当前导入映射和通用目录链未使用。 |

目录规则产生的顺序就是阅读目录顺序。负索引、切片或 CSS 位置规则可用于排除卷名、广告项。章节标题会清理多余空白。

### 7.5 正文规则 `ruleContent`

| 字段 | 当前用途 |
| --- | --- |
| `content` | 正文提取规则，核心必填项。 |
| `replaceRegex` | 对提取后的正文做全局正则替换。 |
| `title` | 可导入和编辑，当前正文返回链不读取。 |
| `images` | 可导入和编辑，当前正文返回链不读取。 |
| `imageStyle` | 可导入和编辑，当前正文返回链不读取。 |
| `payAction` | 紧凑规则可导入到模型，当前通用正文链不执行。 |

`replaceRegex` 支持两种形式：

```text
广告正则
广告正则##替换文本
```

之后应用还会执行基本 HTML 清理：`<br>` 转换为换行、`</p>` 转换为双换行、移除其他标签、解码部分实体、压缩连续空行。因此当前阅读链以纯文本正文为目标，不能依靠 `content` 保留复杂 HTML 布局或图片。

## 8. HTML 书源示例

假设搜索页结构：

```html
<div class="book-item">
  <a class="title" href="/book/123">《示例书》</a>
  <span class="author">作者：张三</span>
  <img class="cover" data-src="/cover/123.jpg">
  <p class="intro">内容简介</p>
</div>
```

对应搜索规则：

```jsonc
"ruleSearch": {
  "bookList": ".book-item",
  "name": ".title@text##^《|》$",
  "author": ".author@text##^作者：",
  "coverUrl": ".cover@data-src",
  "intro": ".intro@text",
  "kind": "",
  "lastChapter": "",
  "bookUrl": ".title@href",
  "wordCount": ""
}
```

假设详情、目录、正文分别为常见 HTML：

```jsonc
"ruleBookInfo": {
  "init": ".book-detail@html",
  "name": "h1@text",
  "author": ".author@text##^作者：",
  "coverUrl": "img.cover@src",
  "intro": ".intro@text",
  "kind": ".tags a@text",
  "lastChapter": ".latest@text",
  "wordCount": ".word-count@text",
  "updateTime": "",
  "tocUrl": ".catalog-link@href"
},
"ruleToc": {
  "chapterList": ".chapter-list a[href*=chapter]",
  "chapterName": "text",
  "chapterUrl": "href",
  "isVip": "",
  "isPay": "",
  "updateTime": ""
},
"ruleContent": {
  "content": "#chapter-content@html",
  "replaceRegex": "请收藏本站|最新网址.*"
}
```

当当前元素本身就是 `<a>` 时，`text` 和 `href` 可直接操作当前元素；也可以写 `@text`、`@href` 风格，但推荐在可读性更高时写完整选择器。

## 9. JSON API 书源示例解析

仓库中的 [`docs/book-sources/kuwo-novel.json`](book-sources/kuwo-novel.json) 是完整可导入示例。其关键点：

- 搜索和发现地址使用 `{{key}}`、`{{page}}`；
- `$.data` 直接取得数组，列表解析器会将数组元素逐项转成当前 JSON 元素；
- 详情 `init` 用 `$.data` 把解析根缩到实际书籍对象；
- `/novels/api/book/{{$.book_id}}` 在元素上下文中构造详情 URL；
- `##` 用于清理卷名和格式化简介；
- `@js:result.replace(...)` 用于把状态码转为“连载/完结”。

开发新 API 源时可复制该文件，再逐阶段替换地址和路径。

## 10. 登录、Cookie 与网页验证

应用会综合 HTTP 状态、响应内容、规则中的验证提示以及登录字段判断是否需要网页验证。常见流程：

1. 为书源设置 `loginUrl`；
2. 搜索、发现、详情、目录或正文命中登录/验证页；
3. 应用打开验证页面；
4. 用户在 WebView 中完成登录或验证；
5. Cookie 同步到书源请求；
6. 返回后重试原操作。

请求规则中的 `<js>startBrowserAwait(...)`、`getVerificationCode(...)` 等提示可触发兼容验证逻辑，但不是完整 Android WebView JS API。需要账号口令签名、动态参数或复杂验证码的网站，必须实机确认；部分已知站点在项目代码中有专用适配，不能据此推断所有同类源都通用支持。

不要把账号、密码、长期 Token 直接提交到公共书源 JSON。优先通过登录页获取短期 Cookie，或仅在本机编辑 `loginHeader`。

## 11. 开发与调试流程

### 11.1 先在浏览器/抓包工具确认接口

记录每一阶段：

- 请求 URL、方法、query、body；
- 必须的 User-Agent、Referer、Cookie、Content-Type；
- 响应编码；
- 搜索列表路径和唯一书籍 ID；
- 详情页到目录的关系；
- 章节 ID、正文路径；
- 是否有重定向、登录、验证码、签名、加密。

优先选择站点公开且稳定的 JSON 接口；HTML 结构常改，复杂 JS 签名和反爬验证的维护成本最高。

### 11.2 按阶段增量开发

1. 只写顶层字段、`searchUrl` 和 `ruleSearch`；确保至少出现一条有书名、有详情 URL 的结果。
2. 写 `ruleBookInfo`；确认详情信息和 `tocUrl` 正确。
3. 写 `ruleToc`；确认章节数、顺序、名称、URL。
4. 写 `ruleContent`；先只提正文，再添加净化正则。
5. 最后复制/调整搜索规则为发现规则，补充分类和分页。
6. 再处理登录、Cookie、字符集、加密和 JS 兼容表达式。

### 11.3 在应用内验证

书源可从文件或 URL 导入，也可在“我的 → 书源管理 → 新建书源”逐字段填写。完整验收清单：

- [ ] JSON 可导入，书源名称和地址正确；
- [ ] 启用书源后能搜索到结果；
- [ ] 搜索中文、空格、特殊字符时编码正确；
- [ ] 书名和详情 URL 不为空；
- [ ] 相对详情 URL 和封面 URL 能正确补全；
- [ ] 详情字段不会被登录页或错误页污染；
- [ ] 目录 URL 正确，章节数和顺序合理；
- [ ] 第一章、中间章、最后一章都能加载；
- [ ] 正文没有导航、广告、脚本或整页错误信息；
- [ ] 发现分类可打开，翻页后内容变化；
- [ ] 登录/验证后 Cookie 能继续用于后续请求；
- [ ] 站点 301/302、HTTP/HTTPS 或镜像变化时行为可接受。

运行应用时，搜索、发现和 WebBook 服务会输出包含 `[SC]`、`[ExploreCoordinator]`、`[WS]` 的日志，可重点查看：最终 URL、状态码、响应长度、列表命中数量和第一条结果。

### 11.4 常见故障定位

| 现象 | 优先检查 |
| --- | --- |
| 书源完全不参与搜索 | `enabled`，以及 `searchUrl`、`bookList`、`name`、`bookUrl` 是否都非空。 |
| HTTP 成功但列表为 0 | 响应实际是 JSON 还是 HTML；列表规则是否在完整响应运行；字符集和登录页。 |
| 列表命中但无结果 | 子规则上下文是否错误；最常见是 `name` 或 `bookUrl` 为空。 |
| 中文搜索乱码 | 使用 `{{searchKeyRaw}}` 并在 URL 选项中指定 `gb2312`/`gbk`。 |
| URL 中出现 `%257B`、关键字双重编码 | 不要预编码 `{{key}}`，或改用 `{{searchKeyRaw}}`。 |
| 详情能开但无目录 | `tocUrl` 是否在 `init` 后的上下文解析；是否错误拼到详情页目录；相对地址基准是否正确。 |
| 目录有标题但章节被丢弃 | `chapterUrl` 为空或仍含未解析的模板/JSONPath。 |
| 正文返回整页文字 | `content` 选择器太宽；先缩到正文容器，再用 `replaceRegex`。 |
| 正文是空字符串 | 请求失败、被验证拦截、提取规则为空，或提取结果被净化正则全部删除。 |
| CSS 在小页面可用、大页面失效 | HTML 超过 4 MiB 保护阈值；寻找 JSON API 或减少响应。 |
| Android 阅读中可用、此处不可用 | 检查是否依赖完整 JS、WebView、复杂 XPath/CSS、未消费字段或 Android 专用 `java.*` API。 |

## 12. 编写质量建议

- 只使用目标站授权或允许访问的内容，并遵守服务条款、版权和访问频率限制。
- `bookSourceUrl` 使用稳定的站点根地址，不要把搜索参数当作唯一键。
- 规则尽量短、确定；优先明确 ID/class/JSON 字段，少用跨整页的贪婪正则。
- 列表规则只负责选元素，字段规则只负责取字段，净化规则只负责清理文本。
- 必填字段不要依赖兜底逻辑；应用中的站点特例主要用于兼容已有源，不是稳定 API。
- 请求头只保留必要项。伪造过多浏览器安全头可能比缺省更容易失效。
- `replaceRegex` 从小到大增加，并用第一章、VIP 章、最后一章验证，避免误删全文。
- 对 JSON 中的反斜杠进行双重转义。例如正则 `\s+` 在 JSON 字符串中写作 `"\\s+"`。
- 提交公共书源前删除 Cookie、Token、账号、设备标识和调试接口。
- 在备注中说明源类型、登录要求、已知限制和维护日期。

## 13. 兼容性与当前限制

### 13.1 字段能力矩阵

| 状态 | 字段/能力 |
| --- | --- |
| 通用链已实际使用 | 搜索/发现的列表、书名、作者、封面、简介、分类、最新章节、详情 URL；发现字数；详情 `init`、书籍字段、目录 URL；目录列表、章节名、章节 URL、VIP；正文内容、净化正则。 |
| 可导入/编辑，但通用链目前未消费 | 详情 `updateTime`；目录 `isPay`、`updateTime`；正文 `title`、`images`、`imageStyle`；`webView`、`webJs` URL 选项。 |
| 模型或紧凑格式存在，但通用导入/UI/执行不完整 | `chapterListAddition`、`payAction`、`bookListRule`、`concurrentRate` 等。 |
| 不应假定与 Android 版等价 | 任意 JavaScript、完整 XPath/CSS、WebView JS、全部 `java.*` API、动态登录 UI、付费购买动作、图片正文排版。 |

### 13.2 实现中的自动兜底

当前项目对部分站点、URL 模式和异常规则具有自动修复或专用兼容，例如从常见字段回退详情 URL、修复个别目录 URL、识别特殊数据 URL、提取可读 HTML 等。这些逻辑可能让某条旧源“碰巧可用”，但新书源不应依赖它们。文档中的推荐写法以通用解析路径为准。

### 13.3 与 Android 阅读书源互导

导入 Android 阅读书源时建议：

1. 保留标准对象形式的 `ruleSearch` 等规则组；
2. 删除当前不需要的字段，先验证最小链路；
3. 将复杂 XPath 改为 JSONPath/CSS；
4. 将任意 JS 改为模板、`##` 或已支持的简单 `@js:`；
5. 将 WebView 请求改成普通 HTTP 接口，若无法改写则判定为当前不兼容；
6. 对登录、Cookie、加密源逐项实机验证；
7. 不以“导入成功”作为“规则兼容”的证明。

## 14. 完整模板

下面模板列出当前可导入的主要字段，复制后删除不需要的项：

```json
[
  {
    "bookSourceName": "",
    "bookSourceUrl": "https://example.com",
    "bookSourceGroup": "",
    "bookSourceComment": "",
    "loginUrl": "",
    "loginUi": "",
    "loginCheckJs": "",
    "loginHeader": "",
    "bookUrlPattern": "",
    "searchUrl": "",
    "exploreUrl": "",
    "jsLib": "",
    "header": "{}",
    "variableComment": "",
    "enabled": true,
    "enabledExplore": true,
    "weight": 0,
    "ruleSearch": {
      "bookList": "",
      "name": "",
      "author": "",
      "coverUrl": "",
      "intro": "",
      "kind": "",
      "lastChapter": "",
      "bookUrl": "",
      "wordCount": ""
    },
    "ruleExplore": {
      "bookList": "",
      "name": "",
      "author": "",
      "coverUrl": "",
      "intro": "",
      "kind": "",
      "lastChapter": "",
      "bookUrl": "",
      "wordCount": ""
    },
    "ruleBookInfo": {
      "init": "",
      "name": "",
      "author": "",
      "coverUrl": "",
      "intro": "",
      "kind": "",
      "lastChapter": "",
      "wordCount": "",
      "updateTime": "",
      "tocUrl": ""
    },
    "ruleToc": {
      "chapterList": "",
      "chapterName": "",
      "chapterUrl": "",
      "isVip": "",
      "isPay": "",
      "updateTime": ""
    },
    "ruleContent": {
      "content": "",
      "title": "",
      "images": "",
      "replaceRegex": "",
      "imageStyle": ""
    }
  }
]
```

## 15. 实现索引

需要继续扩展规则能力时，可从这些实现入口核对：

- 数据模型：`entry/src/main/ets/model/data/Book.ts`
- JSON 导入兼容：`entry/src/main/ets/pages/BookSource.ets`
- 编辑器字段：`entry/src/main/ets/pages/BookSourceEdit.ets`
- URL 和请求选项：`entry/src/main/ets/core/rule/AnalyzeUrl.ts`
- 通用规则解析：`entry/src/main/ets/core/rule/AnalyzeRule.ts`
- JSONPath：`entry/src/main/ets/core/rule/JsonPathEvaluator.ts`
- JS 兼容层：`entry/src/main/ets/core/rule/JsRuntime.ts`
- 搜索流程：`entry/src/main/ets/core/book/SearchCoordinator.ts`
- 发现流程：`entry/src/main/ets/core/book/ExploreCoordinator.ts`
- 详情、目录、正文：`entry/src/main/ets/core/book/WebBookService.ts`
