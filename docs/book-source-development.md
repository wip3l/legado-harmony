# Legado Harmony 书源开发指南

> 适用版本：`3.9.903`（2026-09-04）。本文以当前工作区代码为准；规则能力、字段消费方式和限制可能随版本继续调整。

本文面向为开源轻页编写、迁移和调试书源的开发者，描述项目当前代码中**已经实现并实际调用**的规则能力。

| 项目 | 信息 |
| --- | --- |
| 适用项目 | `legado-harmony` |
| 适用版本 | `3.9.903`（以 `AppScope/app.json5` 为准） |
| 最后核对 | 2026-09-04 |
| 文档性质 | 当前实现参考，不是 Android「阅读」全部规则的等价清单 |

> [!IMPORTANT]
> 示例只使用 `example.com`、本地测试服务和虚构数据。请勿向公共仓库提交真实站点的私有接口、账号、Cookie、Token、设备标识或未获授权的内容规则。

## 阅读路线

- **第一次编写书源**：从[快速入门](#快速入门)开始，再阅读[数据格式与请求](#数据格式与请求)、[规则语法](#规则语法)和[各阶段规则](#各阶段规则)。
- **迁移 Android 阅读书源**：重点阅读 [JavaScript 兼容层](#javascript-兼容层)、[登录与网页验证](#登录cookie-与网页验证)和[兼容性与迁移](#兼容性与迁移)。
- **定位运行问题**：直接查看[开发与验证](#开发与验证)中的验收清单、故障表和批量校验状态。
- **扩展应用能力**：从[实现索引](#实现索引)进入对应 ArkTS 模块。

文档中的能力状态按以下口径描述：

- **已支持/已使用**：当前通用执行链已经读取并产生实际行为。
- **可导入/可编辑**：字段能保存和导出，但不代表通用执行链会消费。
- **部分兼容**：仅覆盖文中列出的语法、阶段或受控桥接，不应推断为完整 Android、Java、WebView 或浏览器环境。

当前规则执行由几类职责不同的组件共同完成：

| 组件 | 当前状态 | 负责范围 |
| --- | --- | --- |
| 原生选择器与规则解析器 | 正式执行 | JSONPath、CSS、基础 XPath、模板、正则、URL 和字段提取。 |
| 轻量 JavaScript 兼容引擎 | 正式执行且结果有效 | 常见表达式、Android/Java 别名及已映射的 `java/source/book/cache/cookie` 主机函数。 |
| 分阶段 ArkWeb | 按能力路由正式执行 | 搜索、发现、详情、目录、正文和登录中的复杂 ECMAScript，以及受控异步主机桥。 |
| 隐藏 ArkWeb 请求传输 | 仅在 URL 显式配置时执行 | `webView: true` 的 HTTP(S) GET/POST 页面加载、DOM 返回及 `webJs`。 |
| 原生 QuickJS | 默认 `SHADOW`，支持灰度 | 启动自检后持久化比对无副作用短纯表达式；合格指纹可灰度接管，异常自动回退和熔断。 |

因此，“已经接入 QuickJS”不表示所有书源 JavaScript 都由 QuickJS 执行，也不表示选择器或 WebView 规则需要改写成 JavaScript。网络、Cookie、持久化、DOM 和应用对象仍必须经过对应的受控主机桥。

## 快速入门

### 书源与执行模型

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
  -> content / images 提取正文、漫画图片或音频地址
  -> replaceRegex 净化
  -> 交互后处理（可选：段评、本章说、图片、视频/媒体动作）
  -> 文本阅读 / 漫画阅读 / 有声书播放
```

书源可以使用 `data:`/Base64 地址承载文本或显式请求元数据。应用只解码书源给出的值，或执行其中明确声明的 HTTP(S) 请求；不会选择镜像、补造第三方接口或执行站点专用解密。普通 HTTP/HTML/JSON 书源沿用同一通用解析路径。

这里最重要的概念是“当前元素”：

- `bookList`、`chapterList` 在完整响应上运行，返回多个元素；
- 书名、作者、章节名等子规则分别在单个元素上运行；
- JSON、HTML 元素、正则捕获组和 JavaScript 对象会以带类型的中间值进入字段规则，直到公开字符串结果边界才转换；HTML 元素保留完整外层 HTML，JSON/JS 对象进入脚本时保持对象结构；
- 所以子规则通常从 `$.字段` 或元素内部的 CSS 选择器开始，而不必重复列表的完整路径。

### 最小可用书源

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
      "wordCount": "$.wordCount",
      "status": "$.status",
      "updateTime": "$.updateTime"
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
      "wordCount": "$.wordCount",
      "status": "$.status",
      "updateTime": "$.updateTime"
    },
    "ruleBookInfo": {
      "init": "$.data",
      "name": "$.title",
      "author": "$.author",
      "coverUrl": "$.cover",
      "intro": "$.intro",
      "kind": "$.category",
      "status": "$.status",
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

## 数据格式与请求

### 导入格式与持久化

应用支持四种常见导入外壳：

```json
[{ "bookSourceUrl": "...", "bookSourceName": "..." }]
```

```json
{ "value": [{ "bookSourceUrl": "...", "bookSourceName": "..." }] }
```

```json
{ "bookSourceUrl": "...", "bookSourceName": "..." }
```

以及剪贴板或分享文本中的 HTTP/HTTPS 导入地址。URL 导入不是简单调用一次下载接口，而是按顺序尝试：

1. 应用 HTTP 客户端（含 HTTPS 候选和响应大小限制）；
2. 明文 HTTP 的受控 TCP 兜底；
3. ArkWeb 下载回调；
4. HarmonyOS 系统下载服务。

每一层都会先校验响应确实是 JSON 对象或数组，错误信息会尽量保留 HTTP、网络或下载服务原因，而不是显示 `[object Object]`。导入对话框提交后会主动收起键盘。

只有同时具有 `bookSourceUrl` 和 `bookSourceName` 的项目才会被写入数据库。`bookSourceUrl` 也是书源的唯一身份标识；修改它通常会被视为另一个书源。导入后会重新读取数据库并核对原始 JSON、脚本库、登录配置、各规则组和运行字段，避免“提示成功但复杂字段被截断或漏存”。

应用同时保存导入对象的完整 `rawSourceJson`。已识别字段进入结构化数据库列；尚未映射的未来字段仍保留在原始对象中，导出时再与当前结构化值合并。因此“完整保存”不等于“所有未知字段都已具备执行语义”。

#### 多书源导入选择

当文件或 URL 返回 JSON 数组、`{"value":[...]}` 等包含多个有效书源的内容时，解析完成后会打开书源选择面板，不会直接把全部项目写入数据库。面板默认全部勾选，可逐项取消或通过“全选/取消全选”批量操作；点击“导入所选”后才执行写入，点击“取消”则放弃本次导入。只有一个有效书源时仍直接导入。

选择状态以 `bookSourceUrl`（书源唯一身份）为键；同一地址的重复项目会视为同一书源。导入结果中的成功、失败、锁定和需登录数量只统计最终选中的项目。

#### 管理列表的快捷操作

在 API 26 及以上设备，书源管理页使用 HDS 滑动列表提供启用/禁用和删除快捷操作；搜索结果列表也提供加入/移出书架和进入阅读的滑动操作。API 25 及以下设备显示等价的按钮操作。进入选择模式、批量处理期间或书源已锁定时会关闭对应快捷操作，快捷操作不会绕过锁定和批量操作限制。

规则组导出时也会先保留原始规则对象中的未知键，再覆盖当前结构化字段，减少编辑后扩展规则丢失。

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

### 顶层字段

| JSON 字段 | 编辑器名称 | 类型/默认值 | 当前作用 |
| --- | --- | --- | --- |
| `bookSourceName` | 书源名称 | 字符串，必填 | UI 展示名称。 |
| `bookSourceUrl` | 书源地址 | 字符串，必填 | 书源唯一键，也是相对请求地址的基础地址。建议写协议和主机，不带末尾业务路径。 |
| `bookSourceType` | 书源类型 | 数字，默认 `0` | `0` 普通书，`1` 有声书，`2` 漫画，`3` 文本/Web 文件；还会结合书籍 `type`、标签和编码协议推断。 |
| `bookSourceGroup` | 书源分组 | 字符串 | 搜索筛选和管理分组。 |
| `bookSourceComment` | 书源备注 | 字符串 | 管理页说明，也会注入规则上下文。 |
| `loginUrl` | 登录地址 | 字符串 | 网页登录/验证入口。检测到登录或验证页时可打开该地址并同步 Cookie。 |
| `loginUi` | 登录界面 | JSON 字符串或动态 JS | 管理页可渲染文本、密码、开关、选择项和按钮；控件值、开关状态与按钮状态可持久化。 |
| `loginCheckJs` | 登录检测JS | 字符串 | 导入、保存及登录能力识别；登录检查和登录动作复用 ArkWeb JavaScript/受控主机桥。 |
| `loginHeader` | 登录密钥 | 字符串 | 可用于特定登录源；通用请求头仍应写在 `header`。 |
| `loginInfo` | 登录运行信息 | JSON 字符串 | 保存登录控件值及受控运行状态。导出公共书源时不应携带账号、Token 或 Cookie。 |
| `bookUrlPattern` | URL正则 | 字符串 | 保存和导入支持，用于描述书籍 URL；当前主解析链不依赖它。 |
| `searchUrl` | 搜索地址 | 字符串 | 搜索请求模板。 |
| `exploreUrl` | 发现地址 | 字符串 | 发现分类及请求模板。 |
| `jsLib` | JS库 | 字符串 | 搜索、发现、详情、目录、正文和登录动作共用。简单代码走轻量引擎，复杂语义可按阶段路由到 ArkWeb，但只开放受控主机能力。 |
| `header` | 请求头 | 字符串 | 书源全局 HTTP 请求头。支持 JSON/宽松对象或每行一个 `名称: 值`。 |
| `variableComment` | 暂无编辑项 | 字符串 | 书源变量的说明文本。 |
| `variable` | 书源变量 | 字符串 | 作为 `source.variable` 注入上下文并独立持久化，登录按钮可通过 `source.setVariable()` 修改。 |
| `enabledCookieJar` | 启用 Cookie | 布尔，默认 `true` | 导入并保存 Cookie 偏好；登录 Cookie 仍按实际请求域名隔离和附加。 |
| `enabled` | 启用书源 | 布尔，默认 `true` | 是否参与搜索和书源选择。 |
| `enabledExplore` | 启用发现 | 布尔，默认 `true` | 是否显示此源的发现入口。 |
| `weight` | 权重 | 数字，默认 `0` | 搜索相关度相同时，权重较大者优先。 |
| `customOrder` | 暂无编辑项 | 数字 | 可导入、保存和导出，并作为结果排序的次级依据。 |
| `lastUpdateTime` | 暂无编辑项 | 数字 | 可导入、保存和导出；缺失时使用导入时间。 |
| `respondTime` | 暂无编辑项 | 数字，默认 `180000` | 可导入、保存和导出，作为书源响应时间/超时相关运行字段。 |
| `concurrentRate` | 暂无编辑项 | 字符串 | 导入并保存；`次数/毫秒窗口`，例如 `20/60000`。普通 HTTP 请求、重试和重定向都会按书源限流。 |
| `isPinned` / `isLocked` | 置顶/锁定 | 布尔 | 可导入并持久化；锁定源不会被同地址导入直接覆盖。 |
| `customButton` / `eventListener` | 扩展标记 | 布尔 | 可导入、保存和导出；目前主要用于保留 Android 阅读书源元数据。 |

原始 JSON 中的其他未知字段会被保留，但只有进入模型、规则组或专用兼容层的字段才会影响执行。

### URL 与 HTTP 请求

#### 相对地址

请求地址可以是：

- 完整地址：`https://api.example.com/search`；
- 协议相对地址：`//cdn.example.com/cover.jpg`，解析为 HTTPS；
- 根相对地址：`/search`，拼到 `bookSourceUrl` 的主机；
- 普通相对地址：`search`，拼到基础地址后；
- 查询相对地址：`?name=book&page=1`，保留当前文档路径，只替换查询字符串；
- 片段相对地址：`#chapter-1`，保留当前文档 URL，只替换片段；
- `data:` URL，支持普通百分号编码和 Base64 内容。

列表中提取的详情地址、封面地址和章节地址也会按响应最终 URL 解析相对路径。HTTP 3xx 最多跟随 3 次；301、302、303 对非 GET/HEAD 请求会切换为 GET。

例如当前响应 URL 为 `https://example.com/read.php?name=old&page=1`，目录链接为 `?name=new&page=1`，最终地址应为 `https://example.com/read.php?name=new&page=1`，不能把路径退回站点根目录而丢掉 `read.php`。书源规则不需要手工补路径。

章节、正文和封面地址不会被应用统一自动套用 `encodeURI`。只有规则显式调用 `encodeURI`、`encodeURIComponent`、`java.urlEncode` 或 `java.encodeURI` 时才会编码。`encodeURI` 适合保留 URL 分隔符的完整地址；`encodeURIComponent` 只应编码单个参数值，不能对完整 URL 使用，否则会破坏 `https://`、`/`、`?`、`&` 和 `=`。

为了避免不同阶段对“普通相对路径”的基准处理差异，书源地址建议只写站点根地址，业务请求和规则生成的 URL 优先写 `/` 开头的根相对地址；尤其是详情规则的 `tocUrl`，不要依赖 `chapters/list` 这类无前导斜杠的路径。

#### 搜索变量

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

#### 发现变量与分类格式

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

这类分组会按两级结构显示：无 URL 的标题作为一级“源站/平台”，其后的有 URL 条目作为该站点内的二级分类。一级标题发生变化后，后续分类归入新的分组。例如：

```json
[
  { "title": "示例源站 A", "url": "" },
  { "title": "热门", "url": "/a/hot?page={{page}}" },
  { "title": "完结", "url": "/a/finished?page={{page}}" },
  { "title": "示例源站 B", "url": "" },
  { "title": "新书", "url": "/b/new?page={{page}}" }
]
```

动态发现脚本返回的 `select` 控件也可映射为原生筛选。控件只需具有非空标题，候选值来自 `chars`；使用 `show(值, '变量名')` 写入书源变量后，应用会重新执行该源的发现规则。复杂脚本仍需逐源验证，不应只依赖标题推断。

发现页会一次查询已启用书源的轻量元数据，以便排序、搜索和恢复选择；下拉菜单使用 `LazyForEach`，只为可见项创建 ArkUI 组件。这里的“按需加载”是界面虚拟化，不是把书源数据库拆成网络分页。

#### URL 选项对象

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
| `webView` | 为 `true` 时，HTTP(S) GET/POST 请求交给隐藏 ArkWeb，沿用书源 URL、Cookie 与 UA（GET 也传入可用的额外 Header），等待页面脚本渲染稳定后返回 DOM。 |
| `webJs` | 与 `webView: true` 配合，在已加载页面上下文执行；有效返回值作为响应正文，否则使用页面 DOM。 |
| `session` | 可选的通用会话规则；仅操作当前请求目标的 Cookie，并可在未声明 Referer 时按规则补充。详见下文。 |

选项对象支持单引号、无引号键和尾逗号等宽松写法，但推荐使用标准 JSON，减少转义差异。

`webView` 请求在同一个隐藏 ArkWeb 中串行执行，默认约 20 秒超时（实现会把单次超时限制在 3～60 秒），最多排队 32 个任务。页面需达到 `document.readyState === 'complete'` 且 DOM 连续稳定后才返回。隐藏 ArkWeb 必须已随当前应用页面挂载；若提示“抓取环境未挂载”，重新进入搜索、发现或相关页面后重试。

页面宿主切换时，尚未完成的请求会迁移到新宿主继续执行，并忽略新宿主首次 `about:blank` 回调；请求超时后仍需按普通失败流程重试。

该选项只负责执行书源明确给出的页面请求，不会自动点击验证码、替用户选择不受信任证书、伪造浏览器指纹或保证通过所有反自动化挑战。需要用户交互的登录/验证仍应使用验证页或 `startBrowserAwait`，并遵守目标服务的授权与访问规则。

POST 还有一种简写：地址以 `@` 开头，`?` 后内容作为 body。

```text
@/api/search?keyword={{searchKeyRaw}}&page={{page}}
```

表单 body 会编码为空格使用 `+` 的形式。未显式提供 `Content-Type` 时：JSON 对象 body 使用 `application/json; charset=utf-8`，其他 body 使用 `application/x-www-form-urlencoded`。

#### 请求头

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

普通请求头的合并顺序是“书源全局请求头 → 本次请求头”，因此本次请求头优先。若未显式设置 Cookie，应用会按请求地址从登录/验证 Cookie 存储中补充。配置 `session` 后，Cookie 的最终优先级见下一节；已有 Referer 始终优先于 `session.referer`。

#### 通用会话选项 `session`

需要匿名会话、查询令牌与 Cookie 对照校验的接口，可在 URL 选项中显式声明 `session`。请求层不识别站点名称，也不会为任何平台内置 Cookie 名称或接口路径。

```text
/api/list?csrfToken={{csrf}},
{"session":{"queryCookies":["csrfToken"],"generatedCookies":{"visitorId":"@uuid"},"referer":"origin"}}
```

完整结构如下，所有字段均可省略：

```json
{
  "session": {
    "queryCookies": {
      "cookieToken": "queryToken"
    },
    "generatedCookies": {
      "visitorId": "@timestamp_random"
    },
    "referer": "origin"
  }
}
```

支持字段：

| 字段 | 说明 |
| --- | --- |
| `queryCookies` | 字符串、字符串数组，或 `{ "Cookie名": "查询参数名" }` 映射。读取本次 URL 的非空查询值并同步到当前目标域 Cookie；数组形式表示二者同名。 |
| `generatedCookies` | `{ "Cookie名": "生成规则" }`。仅在当前目标域和显式 Cookie 请求头都缺少该 Cookie 时生成，并按一年有效期写入；支持 `@uuid`、`@timestamp_random`、`@random`，也可直接填写书源产生的值。 |
| `referer` | `origin` 表示当前目标源，`request` 表示完整请求地址，也可填写书源明确给出的地址；已有 Referer 不会被覆盖。 |

`queryCookies` 的映射方向固定为“Cookie 名 → URL 查询参数名”。例如：

```json
{
  "session": {
    "queryCookies": {
      "csrfCookie": "csrfQuery"
    }
  }
}
```

当请求地址包含 `?csrfQuery=abc` 时，本次请求会携带 `csrfCookie=abc`，同时写入当前目标域的 Cookie 容器。同名场景可简写为字符串或数组：

```json
{"session":{"queryCookies":"csrfToken"}}
```

```json
{"session":{"queryCookies":["csrfToken","requestToken"]}}
```

Cookie 合并顺序为：当前目标域 Cookie 容器 → 书源/本次请求显式 Cookie → `queryCookies` 对应的查询值；`generatedCookies` 只补缺失项，不覆盖以上任何值。Cookie 名只接受字母、数字、下划线、点和连字符，查询参数不存在或值为空时不会写入。

`session` 是显式会话操作：即使书源关闭了普通 Cookie Jar，只要本次 URL 仍声明 `session`，声明的会话规则就会执行。若请求必须完全无 Cookie，不要配置 `session`，也不要在请求头中声明 Cookie。

会话规则只对声明它的这次请求生效，Cookie 读取和写入均以请求 URL 为作用域，不会从其他域复制；发生跨主机重定向时，Cookie、Authorization、Proxy-Authorization、Host、Origin 和 Referer 等目标相关请求头会先被移除，再由新目标自己的 Cookie 容器处理。同一主机内重定向会保留本次会话头。

若接口需要签名、固定设备标识或服务端发放的会话值，应由书源脚本或登录流程取得，不能依赖 `generatedCookies` 猜测。历史书源如果曾依赖请求层自动补充某个平台的字段，应把相应名称和值迁移到 URL 的 `session`、`headers` 或登录脚本中；应用不再保留隐式站点规则。

## 规则语法

一个字段规则通常由三部分构成：

```text
提取规则##正则##替换文本@js:后处理
```

并非每部分都必须存在。执行顺序是先提取，再执行 `@js:` 后处理，最后执行 `##` 正则替换。尽量让规则保持单一职责，复杂转换分成 `init`、字段提取和净化三步。

### JSONPath

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

### CSS 选择器

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
text.下一页@href
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
- 旧式 `text.关键字` 从当前 HTML 中查找自身直接文本包含该关键字的元素；只存在于后代节点中的文字不算命中，可继续追加 `@text`、`@ownText`、`@html` 或属性提取。

#### 元素索引与排除简写

选择器末尾可以使用点号选择索引，或使用感叹号排除索引。索引从 `0` 开始，负数从末尾倒数（`-1` 表示最后一个元素）。多个索引使用冒号分隔：

```text
span.0:1:2:3@text
span!0:-1:-2:-3@text
```

上面的第一条规则只返回第 0、1、2、3 个 `span` 的文本；第二条规则排除第 0、倒数第 1、倒数第 2、倒数第 3 个 `span`，再返回剩余文本。索引列表可以按需要混合正数和负数，也可以只写一个索引：

```text
span.0@text
span!0@text
```

为兼容原有书源，只有两个数字的形式仍表示范围：`span.0:5@text` 返回索引 0（含）到 5（不含）的元素。三个及以上数字才表示显式索引列表，因此不会与旧范围写法冲突。`@text` 是提取后缀；“选取”“排除”等说明文字不要写入规则本身。

`text.下一页@href` 是 Android 阅读书源中常见的正文翻页写法。它按“自身文本包含”匹配，而不是精确相等，因此“下一页”“下一页继续阅读”都可命中，URL 字段取第一个非空 `href` 并按当前响应最终地址补全相对路径。如果链接文字全部包在 `<span>` 等后代节点中，元素自身文本为空，这条规则不会命中；此时应改用稳定的 CSS，例如 `a.next@href`，或在确实需要后代文字匹配时使用 `a:contains(下一页)@href`。

未写提取后缀时，普通 CSS 字段默认返回文本；列表规则会保留完整元素供子规则继续解析属性、文本或正则。明确的列表规则没有命中时返回空列表，不再把整页响应伪装成一个列表元素。

常用提取后缀：

| 后缀 | 结果 |
| --- | --- |
| `@text` | 去标签后的全部文本。 |
| `@ownText` | 元素自身直接文本，尽量排除子元素内容。 |
| `@textNodes` | 直接文本节点按换行连接。 |
| `@html` | 完整元素 HTML。 |
| `@href`、`@src`、`@content`、`@title` 等 | 对应属性值。自定义合法属性名也可提取。 |

选择器解析由项目内轻量解析器完成，并非完整浏览器 DOM/CSS 引擎。不要依赖复杂嵌套伪类、`an+b` 形式的 `nth-child`、伪元素或现代 CSS 全集。单个 HTML 响应超过 4 MiB 时，列表 CSS/正则解析会受保护性限制；大接口优先使用 JSONPath 或缩小响应。

### 基础 XPath

支持一部分可转换为 CSS 的 XPath：

```text
//div[@class='book']/a/text()
//a[contains(@href,'book')]/@href
//li[contains(.,'完结')]
//ul/li[1]
//li[last()]
```

支持属性相等、`contains(@attr, ...)`、`starts-with(@attr, ...)`、文本包含、数字位置、`last()`、属性存在以及末尾 `/@attr`、`/text()`。复杂轴、函数、变量和完整 XPath 表达式不受支持；新源推荐 JSONPath 或 CSS。

### 组合规则

| 运算符 | 行为 | 示例 |
| --- | --- | --- |
| `规则1||规则2` | 依次尝试，返回第一个非空结果。 | `.title@text||h1@text` |
| `规则1&&规则2` | 将各规则的结果顺序拼接为一个结果列表。 | `.name@text&&.alias@text` |
| `规则1%%规则2` | 按索引交错合并多个结果列表。 | `.name@text%%.url@href` |

分隔符在引号、圆括号、方括号和花括号内不会拆分，因此 JSONPath 过滤器中的 `&&`、`||` 可以正常使用。

普通字符串字段会与 Android 阅读保持一致，把同一规则的多个命中项（包括 `&&` 合并后的结果）用换行连接；例如 `.content@p@html` 会保留全部 `p`。URL 字段只使用第一个非空命中项。

### 模板拼接

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

模板表达式中的 `@@选择器` 会按当前 HTML 元素继续执行普通提取规则，而不是作为 JavaScript 文本处理。例如 `{{@@a@href}}` 可读取当前卡片内链接。

详情、目录、正文阶段还会注入 `book.bookUrl`、`bookUrl`，并尽量从详情 URL 提取 `book`、`book_id`、`id`。

### 正则提取与替换

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

正则以 JavaScript `RegExp` 的全局模式执行。第三段省略时替换为空字符串；替换文本支持 `$1` 等捕获组引用。字面量 `##` 可写成 `\##`。以 `:` 开头的直接正则链还兼容 Java/Kotlin 常见的前置内联标志 `(?i)`、`(?m)`、`(?s)`、组合标志和 `(?-i)` 一类关闭标志，并转换为 JavaScript 正则选项。

规则可直接以 `##正则##替换` 开头，此时处理输入是完整当前元素。尾部再加 `###` 时只处理首个命中的子串，并返回替换后的该子串，而不是返回周围的原文本。

还支持直接正则规则：

- 以 `%` 开头时，对完整内容运行一次非全局正则，并返回完整匹配和捕获组；
- 以 `:` 开头时，可用 `&&` 串联全量正则；中间正则先拼接所有完整匹配，最后一条为每个匹配保留 `$0`、`$1` 等捕获组，供字段规则继续读取；
- 普通“像正则”的规则会以全局模式运行。有捕获组时，每个匹配会变为 `{"$0":"...","$1":"..."}`，后续可用 `$['$1']` 一类路径读取。

直接正则的兼容行为较特殊，稳定书源更适合用 CSS/JSONPath 提取后再用 `##` 净化。

### 上下文变量 `@put` / `@get`

可以在规则中保存并读取字符串变量：

```text
@put:{bookId:$.id}$.title
@get:{bookId}
/chapter/@get:{bookId}/{{$.id}}
```

`@put:{key:value}` 中可用逗号或分号分隔多项；值会先按普通规则求值。上下文会从搜索结果保存到书籍，并在详情、目录和正文阶段恢复，因此可用于跨阶段携带站点 ID。章节还会保存其解析时的 `baseUrl`。

注意：列表中的每个搜索/发现元素会创建自己的规则上下文，搜索得到的变量会写入该书籍；目录中的章节共用书籍上下文。避免用相同键保存会在章节之间互相覆盖的临时值。

### JavaScript 兼容层

规则支持以下形态：

```text
<js>表达式</js>
$.status@js:result.replace(/1/g, "连载")
@js:'https://example.com/chapter/'+$.id
js:表达式
```

字段规则还支持 `基础规则<js>处理脚本</js>后续规则`。执行顺序为：先按基础规则取得 `result`，再运行内嵌脚本，最后把脚本结果交给尾部规则继续解析。例如：

```text
$.data<js>result.items</js>$.books[*]
```

尾部规则为空时直接采用脚本结果；列表字段仍按列表语义处理。内嵌脚本及尾部规则均受当前阶段的超时、取消和输出大小限制。

普通 HTTP 抓取只解析响应文本，不会为了一个字段执行页面内的 `<script>`。例如页面使用 `renderCount('4152836')` 配合 `document.write` 显示字数时，`@text` 可能得到脚本源码，而不是浏览器最终显示的 `415万字`。可直接从局部 HTML 中提取参数并转换：

```text
.word-count@html<js>var m=result.match(/renderCount\('([0-9]+)'\)/);return m?String(Math.round(Number(m[1])/10000))+'万字':'';</js>
```

`wordCount` 是最终展示字符串，应用不会统一把裸数字自动换算为“万字”，因为不同接口可能已经携带单位或使用其他口径。仅当字段必须依赖完整页面 JavaScript、异步渲染或全局状态时，才在对应请求 URL 中显式使用 `webView: true` / `webJs`；不要为了简单的数值换算启用网页抓取。

这类组合规则会先做能力判断。普通表达式继续在每个列表元素自己的 `AnalyzeRule` 上下文中执行，以保留既有的当前元素、变量读写和尾部处理顺序；只有使用箭头函数、模板字符串插值、`try`、数组高阶函数、`Set/Map`、解构或超大脚本等完整 JavaScript 语义时，才会批量路由到分阶段 ArkWeb。不要因为规则中出现 `<js>` 就假定它一定由 ArkWeb 执行。

复杂组合规则在 ArkWeb 执行失败时，如果能力分析确认脚本没有网络请求、Cookie 修改或持久化写入等可观察副作用，会回退到逐元素兼容解析，不会把该字段直接当成空值。包含副作用的脚本不会再交给第二个引擎重试，以免重复请求或重复修改状态。

当前不是“所有代码统一交给一个 JavaScript 引擎”，而是按职责分层：

1. **轻量规则/JavaScript 兼容引擎**：正式处理模板、简单表达式和常见 Android/Java 别名，当前返回值直接参与书源执行；
2. **分阶段 ArkWeb 引擎**：能力路由器发现箭头函数、模板字符串、`try`、数组高阶函数、`Set/Map`、解构或较大脚本时，仅将相应阶段交给 ArkWeb 的真实 JavaScript 引擎；
3. **QuickJS 迁移运行时**：应用启动后先做原生自检，再在 TaskPool 中执行可证明无主机副作用的短纯表达式。默认 `SHADOW` 只比较结果；`CANARY` 仅接管累计至少 4 次一致且零差异、零失败的表达式指纹；`PREFER_QUICKJS` 对候选表达式优先使用 QuickJS。正式模式均保留原执行路径作为失败回退，连续 3 次路由失败会熔断 5 分钟。

搜索、发现、详情、目录和正文分别路由，启用某一阶段的 ArkWeb 不会把所有书源或所有阶段一起改道。无副作用的失败可以回退轻量引擎；含网络、Cookie 或持久化写入的动作会避免双重执行。`jsLib` 中声明的顶层函数会暴露给当前阶段规则，并在下一书源执行前清理，防止跨源污染。

QuickJS 候选当前限制为最多 4096 字符、最多 64 个绑定和 128 KiB 绑定数据，并使用 16 MiB 内存、512 KiB 栈及 10～250 ms 的受限执行。JSON 安全的对象和数组会保持结构化绑定，因此纯表达式可读取 `$.field` 或数组下标；绑定转换另有 32 层、20000 节点保护。包含赋值、语句块、循环、函数/类声明、`new`、`Date`、随机数，或 `java/source/book/chapter/cookie/fetch/webView` 等主机对象的表达式不会进入 QuickJS。迁移诊断只持久化不可逆表达式指纹、计数和耗时，不保存书源代码、变量或解析结果。

可在“其他设置 → 脚本引擎迁移 → 书源脚本回归测试”中多选书源与搜索、发现、详情、目录、正文阶段。该工具只抽取符合上述安全边界的 `{{…}}`、独立 `<js>…</js>`、`@js:`/`js:` 纯表达式，以三组固定输入在原有表达式运行时和 TaskPool QuickJS 中分别执行并报告一致、差异或失败；它不会请求书源网站，也不会读取或修改 Cookie、登录信息、书源变量或迁移统计。异步纯脚本由统一异步路由提交，仍保留原执行结果作为失败回退。单次最多加载 50 个书源并测试 300 个候选表达式。

离线一致不会直接授权 QuickJS 接管。报告会保存候选的书源、阶段、字段和不可逆指纹，但不保存脚本、运行绑定或结果值。当前已接入异步路由的独立纯脚本会进入“待真实验证”；`{{…}}` URL/字段模板及 `@js:` 后处理表达式仍标记为“仅离线通过”，在对应同步解析链路完成异步化前不会被错误晋级。点击“开始真实验证”后，应用切回 `SHADOW`，用户照常搜索、浏览发现或阅读；命中的可路由候选使用真实上下文在 TaskPool 中后台比对，旧引擎结果始终生效。每个候选累计至少 4 次真实一致且零差异、零失败后才显示“灰度合格”，此时页面才允许开启 `CANARY`。真实差异或失败会阻止该候选晋级；清除迁移统计也会同步清除真实验证进度。该流程是渐进迁移门禁，仍不能代替书源功能、网络与登录流程的人工验收。

复杂脚本的网络、Cookie、密码学和持久化动作采用引擎无关的“动作请求 → 原生统一执行 → 结果回放”协议，并由执行日志去重。请求仍通过通用 `AnalyzeUrl/HttpClient`，Cookie 仍按目标域隔离；QuickJS 不直接获得这些宿主能力，也不存在按站点名称开放的专用接口。

QuickJS 不能直接替代 JSONPath/CSS/XPath：选择器需要解析 HTML/JSON 节点和维护“当前元素”上下文，而 QuickJS 影子运行时故意不开放 DOM、网络、Cookie、文件或平台对象。需要这些能力时，应继续使用原生选择器、受控主机函数或分阶段 ArkWeb，而不是把规则整体转写为 JavaScript。

轻量层和桥接层合计覆盖的常用能力包括：

- `java.timeFormat(value, pattern)` 按设备本地时区格式化时间；
- `java.timeFormatUTC(value, pattern, zone)` 先按给定小时偏移调整时间，再使用 UTC 字段输出 `yyyy`、`MM`、`dd`、`HH`、`mm`、`ss`；
- `java.put(key, java.timeFormatUTC(java.getString(path), pattern, zone))` 等嵌套调用会先计算内层取值和格式化结果，再写入共享规则上下文。

- 字符串拼接和简单变量赋值；
- `result.replace(/正则/g, "文本")` 等常见替换链；
- 简单数值 `+ - * / %` 和 `Math.round/floor/ceil`；
- `Date.now()`、部分 `new Date()` 取值；
- `encodeURIComponent`、`encodeURI`；
- `java.urlEncode/urlDecode`；
- Base64、Hex、MD5、SHA-1、SHA-256；
- SHA-512、Base64 URL、HTML 实体编解码；
- AES、DES/3DES 的常见 Base64 加解密；
- `java.getString`、`java.getStringList` 读取当前 JSON；
- `java.timeFormat`；
- `java.getCookie`、`cookie.getCookie/setCookie/removeCookie`；
- `java.randomUUID()`、`java.androidId()`；
- `java.put/get`、`source.get/put/getVariable/setVariable`、`book.getVariable/putVariable`；
- `baseUrl` 会随当前规则解析地址注入；分阶段 ArkWeb 还提供带 `get/put/save` 的临时 `infoMap`；
- `source.getLoginInfo/getLoginInfoMap/putLoginInfo`、`source.getLoginHeader` 和 `cache.get/put/delete`；
- `android.util.Base64`、`java.util.Base64`、`URLEncoder/URLDecoder`、`System.currentTimeMillis` 等常见 Java/Android 别名；
- `StringBuilder`、`HashMap`、`ArrayList` 及常用 Java 字符串/集合方法；
- 使用 `MessageDigest` 或 `Cipher/SecretKeySpec/IvParameterSpec` 封装的常见摘要、AES、DES/3DES 函数。

ArkWeb 提供真实 ECMAScript 语义，但**不等于完整 Android、Rhino、Node.js 或无限制浏览器环境**。阶段脚本的网络必须经过 `java.ajax` 等受控桥接；`fetch`、`XMLHttpRequest`、`WebSocket` 会被判定为未托管网络。任意 Java 导入、文件、进程、反射、系统组件和第三方原生库不会自动可用。DOM 主要用于登录面板生成的页面；普通搜索/目录/正文规则不应假定目标网页已在可操作 DOM 中。

能力路由会分析 `java`、`source`、`cache` 和 `cookie` 方法，并在登录动作失败时提示缺少的桥接方法。复杂源仍应逐阶段实机验证；书源中的私有函数、接口和凭据始终属于该书源配置，不会成为应用内置 API。

### 编码 `data:` 地址与显式请求

应用支持标准 `data:` 文本以及 `data:;base64,<负载>,{...}` 形式。Base64 负载和尾部选项会分别解析，避免把请求选项误当成正文；编码章节地址中的 `/` 或形似 `name=value` 的 Base64 片段不会再被旧式虚拟章节参数解析截断。

编码请求只有在选项明确使用通用 `type: "request"`，并明确提供 HTTP(S) `url`/`requestUrl` 时才会执行。方法、请求体和请求头也必须来自书源配置。应用不会：

- 根据书源名称、平台名或负载类型推断内容站点；
- 选择内置聚合后端、镜像、代理或回退主机；
- 自动加入第三方 API Key、账号、设备标识或平台参数；
- 把一个站点的 Cookie 自动复制到另一个站点；
- 在规则之外实现第三方接口签名、付费内容解密或评论接口适配。

请求层只提供 URL 选项中的通用 `session` 能力，且必须由书源显式声明。应用没有目标主机名单，不会因地址属于某个平台而自动补充 Cookie 名称、访客标识、Referer 或查询参数。

需要加密、摘要、Cookie、音频或图片处理时，应把相应逻辑和有权使用的参数明确写在书源规则中。`BookSourceInteractionPostProcessor` 不再识别具体平台，只保留规则已经产出的正文。

## 各阶段规则

### 搜索规则 `ruleSearch`

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
| `wordCount` | 否 | 单个书籍元素 | 搜索结果字数；常规搜索链会解析并写入结果，精简校验模式会省略该展示字段。 |
| `status` | 否 | 单个书籍元素 | 书籍状态/连载状态文本。 |
| `updateTime` | 否 | 单个书籍元素 | 书籍更新时间文本；写入搜索结果，并可在详情和书架中显示。 |

每个源常规搜索最多保留 50 条有效结果，总搜索最多保留 1000 条，并按“来源 + URL”去重。搜索并发数最大为 12；后台结果每约 500 ms 合并一次，避免每条回调都打断列表手势，因此搜索未结束时仍可滑动已出现的结果。搜索会清理超长或异常字段；书名约 120 字符、作者约 120、简介约 1200、URL 约 2048 字符。

主页面中的搜索组件在书架、发现、搜索和“我的”之间切换时不会主动清空结果；发起下一次搜索或清除单书源模式时才重置。本行为是页面会话缓存，不是长期数据库搜索快照，应用进程结束后不保证恢复。

### 发现规则 `ruleExplore`

至少需要：`exploreUrl`、`bookList`、`name`、`bookUrl`。字段语义与搜索相同。发现链会读取 `wordCount`、`status` 和 `updateTime`，并按“来源 + 详情 URL”去重。

搜索/发现通用卡片显示书名、作者、状态/分类标签、字数、最新章节、更新时间、来源和封面。详情页会再次请求 `ruleBookInfo`，用详情结果补全列表缺失字段。如果 `.author@text` 同时命中“作者、字数、阅读量”等多个同 class 节点，解析器会用换行连接它们，卡片看起来像是在显示三个独立字段，实际它们都属于 `author`。语义正确的书源应尽量分别提取作者和字数；若为兼容现有卡片而有意把多行元数据放进 `author`，必须先把 `renderCount(...)` 一类脚本文本转换为最终可读值，并接受作者聚合、书籍匹配和入架元数据可能受到影响的代价。

当 `ruleExplore` 为 `null`、空数组、空对象或缺少必要字段时，会自动回退到 `ruleSearch`。`exploreUrl` 以 `@js:` / `js:` 开头时会按能力路由执行，结果应为分类对象数组的 JSON 字符串；简单表达式可由轻量引擎处理，完整脚本或带 `jsLib` 函数的模板可进入分阶段 ArkWeb。阶段脚本返回 `/api/...` 等相对地址时会以 `bookSourceUrl` 补全后再请求。两条路径都有代码、输出、操作或响应大小限制。

### 详情规则 `ruleBookInfo`

详情请求地址来自搜索/发现的 `bookUrl`。

| 字段 | 当前用途 |
| --- | --- |
| `init` | 先在完整详情响应上执行；非空结果成为其余详情字段的新解析内容。适合 `$.data` 或 `.book-info@html`。 |
| `name` | 更新书名；空结果保留列表页值。 |
| `author` | 更新作者；空结果保留列表页值。 |
| `coverUrl` | 补充封面。当前逻辑优先保留列表页已有封面。 |
| `intro` | 更新简介，经过字段清理后择优保留。 |
| `kind` | 更新分类。 |
| `status` | 更新连载/完结等状态；作为独立字段保存，不要求混入 `kind`。旧书源若仍将状态写在 `kind` 中，仍会按分类标签兼容显示。 |
| `lastChapter` | 更新最新章节。 |
| `wordCount` | 更新字数。 |
| `updateTime` | 详情链会写入 `Book.updateTime`，保存到书架数据库并用于显示最后更新时间；旧书没有该字段时会保留列表阶段已有值。 |
| `tocUrl` | 目录请求地址；以 URL 模式解析相对地址。为空时会尝试依据书籍 URL 和规则模板兜底。 |

#### 书籍元数据字段兼容映射

搜索、发现和详情阶段使用同一套书籍元数据语义。书源规则中的字段名与应用对象的映射如下：

| 书源字段 | 书籍对象 | 搜索/发现列表 | 详情页 | 书架 |
| --- | --- | --- | --- | --- |
| `name` | `Book.name` / `SearchBook.name` | 显示 | 更新 | 显示 |
| `author` | `author` | 显示 | 更新 | 显示 |
| `kind` | `kind` | 分类标签 | 更新 | 分类标签 |
| `status` | `status` | 状态标签 | 更新 | 状态标签 |
| `wordCount` | `wordCount` | 元数据行 | 标签/元数据 | 可用于详情 |
| `lastChapter` | `latestChapterTitle` | 最新章节元数据 | 最新章节区块 | 书架最新章节 |
| `intro` | `intro` | 进入详情后显示 | 简介区块 | 详情/阅读上下文 |
| `updateTime` | `updateTime` | 更新时间元数据 | 更新时间标签 | 最后更新时间 |

`lastChapter` 是 Android 阅读书源中常见的旧字段，本项目继续接受它，并统一写入 `latestChapterTitle`。`status` 不再需要借用 `kind`；不过旧书源把“连载中/完结”等文本放入 `kind` 时仍可正常显示。`updateTime` 应返回站点原始的日期或时间文本，应用不会擅自把它转换成时间戳或替换成设备本地时间。

HTML 书源示例：

```json
{
  "ruleSearch": {
    "bookList": ".book-item",
    "name": ".title@text",
    "author": ".author@text",
    "kind": ".category@text",
    "status": ".status@text",
    "wordCount": ".word-count@text",
    "lastChapter": ".latest@text",
    "intro": ".intro@text",
    "updateTime": ".updated@text",
    "bookUrl": "a.detail@href"
  },
  "ruleBookInfo": {
    "status": ".book-status@text",
    "lastChapter": ".last-chapter@text",
    "wordCount": ".word-count@text",
    "intro": ".description@text",
    "updateTime": ".update-time@text"
  }
}
```

JSON 书源示例：

```json
{
  "ruleExplore": {
    "bookList": "$.data.books[*]",
    "name": "$.title",
    "author": "$.author",
    "kind": "$.category",
    "status": "$.status",
    "wordCount": "$.wordCount",
    "lastChapter": "$.latestChapter",
    "intro": "$.intro",
    "updateTime": "$.updatedAt",
    "bookUrl": "$.url"
  },
  "ruleBookInfo": {
    "status": "$.status",
    "lastChapter": "$.latestChapter",
    "wordCount": "$.wordCount",
    "intro": "$.description",
    "updateTime": "$.updatedAt",
    "tocUrl": "$.catalogUrl"
  }
}
```

如果接口字段名不同，只需把右侧 JSONPath/CSS 选择器替换为实际字段；不要把多个语义字段都写到 `author`。状态和更新时间为空时，详情链会保留列表阶段已有值，不会用空值覆盖已有数据。

`init` 返回的是字符串。如果 JSONPath 命中对象，会被序列化成 JSON，因此后续仍可用 JSONPath；如果 CSS 命中元素，建议显式用 `@html` 保留 HTML。

封面规则应返回可直接加载的图片地址，而不是详情页地址、包裹图片的 HTML 或尚未执行的脚本。常见写法包括 `img.cover@data-src`、`img.cover@src`、`meta[property=og:image]@content`，也可根据当前元素中的书籍 ID 用模板或 `<js>` 构造地址。搜索/发现阶段会按响应最终 URL 补全相对封面地址；JSON 项的显式 `coverUrl` 为空或未解析时，还会尝试通用键 `cover`、`cover_url`、`image`、`imageUrl`、`img`、`pic`、`thumbnail`。HTML 不会猜测任意图片节点。

详情阶段只会在列表封面为空时用 `ruleBookInfo.coverUrl` 补充，**不会用详情封面覆盖一个非空但错误的列表封面**。发现页封面错误时，应先修正 `ruleExplore.coverUrl`；如果列表页没有可靠封面，可将它留空，让详情规则补齐。

### 目录规则 `ruleToc`

| 字段 | 必需 | 当前用途 |
| --- | --- | --- |
| `chapterList` | 是 | 在完整目录响应中选出章节元素。 |
| `chapterName` | 建议 | 章节标题；空时自动使用“第 N 章”。 |
| `chapterUrl` | 是 | 正文请求地址；空地址的章节会被丢弃。 |
| `nextTocUrl` | 否 | 当前目录页的下一页地址；逐页请求、按章节 URL 去重，遇到空地址、重复页或 1000 页保护上限时停止。全链路校验可另传章节抽样上限提前停止。 |
| `isVip` | 否 | `true`、`1`、`yes`、`vip`、`pay`、`paid`、`付费`、`收费` 会标记为 VIP。 |
| `isPay` | 否 | 普通目录链会按与 `isVip` 相同的布尔规则写入 `BookChapter.isPay`；直接返回完整章节数组的 ArkWeb 脚本仍需实机验证付费元数据。 |
| `updateTime` | 否 | 通用目录和 ArkWeb 目录结果会解析，并保存到章节变量 `updateTime`。 |
| `chapterListAddition` | 否 | 模型字段；当前导入映射和通用目录链未使用。 |

目录规则产生的顺序就是阅读目录顺序。负索引、切片或 CSS 位置规则可用于排除卷名、广告项。章节标题会清理多余空白。

首次打开且本地没有可用目录时，如果正式 `chapterList` 规则没有结果（包括显式 CSS、XPath、JSONPath 或直接正则规则 0 匹配），阅读链可从**首个普通 HTML 目录响应**中临时识别章节链接。该通用兜底会比较命名目录容器与全页候选；当所谓目录容器实际只是较短的“最新章节”区块时，会优先使用明显更完整的全页候选。之后先去掉页面顶部“最新章节”重复块，再按 URL 去重，并只在章节数字呈现出强烈倒序证据时调整顺序。

兜底结果会标记为临时目录，不覆盖数据库中已有的正式目录；本地已有目录时，正式规则刷新失败也不会用通用结果替换它。换源和“发现/阅读链路”书源校验会禁用该兜底，因此校验通过仍表示书源自身的目录规则有效。通用兜底只用于避免首次打开完全不可读，不是 `ruleToc` 的替代能力，也不能保证所有站点的卷结构、付费状态和更新时间正确。

### 正文规则 `ruleContent`

| 字段 | 当前用途 |
| --- | --- |
| `content` | 小说正文提取规则；纯漫画书源可留空并配置 `images`。 |
| `replaceRegex` | 对提取后的正文做全局正则替换。 |
| `title` | 可导入和编辑，当前正文返回链不读取。 |
| `images` | 漫画图片提取规则；支持返回单个地址、地址列表或图片标签，相对地址会按章节响应地址补全。 |
| `sourceRegex` | 有声书 WebView 媒体请求匹配规则；仅当目录 `chapterUrl` 的请求选项显式设置 `webView: true` 时，用于从页面资源中筛选最终音频 URL。 |
| `nextContentUrl` | 正文下一页地址；逐页解析并拼接，遇到空地址、重复页、50 页或 8 MiB 正文上限时停止。 |
| `imageDecode` | 图片二进制解密规则；当前允许受限的 AES-CBC-PKCS5/PKCS7 解密，不执行文件、进程或反射 API。 |
| `imageStyle` | `FULL`、`comic`、`manga`、`webtoon` 会让阅读器优先使用连续全宽漫画模式。 |
| `payAction` | 紧凑规则可导入到模型，当前通用正文链不执行。 |

阅读页或书架全文缓存取消任务时，取消信号会传入正文获取链，在缓存读取、书源刷新、HTTP 响应、分页循环、交互后处理和字段规则批处理之间检查，并取消当前 HTTP 客户端及对应的规则执行任务。被取消的结果不会写入章节缓存。这是运行控制行为，不增加书源字段，也不改变 `content`、`images` 或 `nextContentUrl` 的解析顺序。

多页正文会在每一页响应上重新执行 `content`、`nextContentUrl` 和 `images`，再按页序用空行拼接正文。普通 HTML 的常见配置是：

```jsonc
"ruleContent": {
  "content": "#chapter-content@html",
  "nextContentUrl": "text.下一页@href",
  "replaceRegex": ""
}
```

这只能跟随响应中真实存在的下一页链接。如果首屏 HTML 本身就是截断的 SSR 内容，完整正文只保存在页面 JavaScript 状态或异步渲染后的 DOM 中，`nextContentUrl` 不会自动找回缺失部分。此时应让目录的 `chapterUrl` 显式使用 `webView: true`，并用 `webJs` 返回完整正文 HTML/文本，再让 `ruleContent.content` 提取。例如：

```text
/chapter/{{$.id}}, {"webView":true,"webJs":"document.querySelector('#chapter-content')?.innerHTML||''"}
```

若站点把完整正文放在页面全局状态中，也可以由 `webJs` 读取该状态；返回值会作为本页响应正文继续进入 `content` 规则。网页抓取串行且成本高，应只用于普通 HTTP 确实拿不到完整正文的页面。

`replaceRegex` 支持两种形式：

```text
广告正则
广告正则##替换文本
```

之后应用还会执行基本 HTML 清理：`<br>` 转换为换行、`</p>` 转换为双换行、移除其他标签、解码部分实体、压缩连续空行。正文中的 `img`/SVG `image`、Markdown 图片和独立图片地址会保留为阅读器图片页；配置 `images` 时优先按该规则返回的图片顺序分页。其他复杂 HTML 布局通常不会原样保留。

在 HTML 清理前，以下交互标记会转换为阅读器内部动作，而不是作为代码显示：

```html
<p>一段正文<comment ident="https://example.com/comments" count="12" /></p>
<p><img ident="https://example.com/god-comment" src="data:image/svg+xml;base64,..." /></p>
```

阅读页会把动作显示为跟随段落的可点击气泡/入口；分页器会保证标记不被切断，TTS 和快速朗读面板会剥离内部动作编码。点击动作会打开内置动作页面或媒体播放器。普通 HTML `onclick`、任意 DOM 事件和任意 JavaScript URL 不会直接执行。

朗读送入 TTS 前还会过滤整行的装饰性符号，例如连续的 `*`、`#`、`&`、`=`、横线、下划线、波浪线、圆点、竖线、斜杠及其常见全角形式；长度不限，过滤时以等长空格替换，保证朗读分块和页面高亮偏移仍能对应原正文。只要该行含有普通文字，就不会因包含 `*`、`#`、`&` 而整行删除。这个处理只影响朗读，不修改阅读页显示内容；若正文页面本身也不应显示分隔符，仍应在 `replaceRegex` 中由书源明确清理。`p:求推荐` 一类含文字的推广语也不会被装饰符过滤自动删除。

为了避免异常书源把超长脚本或大量交互元数据塞入正文，单个动作标记最多约 16 KiB，单章最多保留 320 个有效动作，并限制标签、标题和 URL 长度。损坏、超长或超过单章预算的标记会被当作元数据丢弃，不会回退成正文、图片或朗读文本。书源应让动作只携带完成交互所需的最小参数，不要嵌入整页响应或大段 Base64 数据。

漫画图片支持阅读书源常见的请求参数写法：

```text
https://img.example/page.jpg,{"headers":{"Referer":"https://example.com/"}}
```

带参数或 `imageDecode` 的图片由应用 HTTP 客户端携带 Cookie/白名单请求头下载，在最多 20 MiB 的限制内完成解密并写入应用缓存，再以本地文件交给阅读器。单章图片按最多 4 路并发处理。

## 示例与特殊场景

### HTML 书源示例

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
  "wordCount": "",
  "status": ""
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
  "nextContentUrl": "text.下一页@href",
  "replaceRegex": "请收藏本站|最新网址.*"
}
```

当当前元素本身就是 `<a>` 时，`text` 和 `href` 可直接操作当前元素；也可以写 `@text`、`@href` 风格，但推荐在可读性更高时写完整选择器。

### JSON API 开发要点

公开仓库不提供指向真实第三方站点的完整可导入书源。开发和测试时，请使用 `https://example.com`、本地测试服务器或开发者自行控制且明确获得授权的服务，并使用虚构数据验证以下能力：

- 搜索和发现地址可使用 `{{key}}`、`{{page}}`；
- `$.data` 可直接取得数组，列表解析器会将数组元素逐项转成当前 JSON 元素；
- 详情 `init` 可用 `$.data` 把解析根缩到实际书籍对象；
- `/api/books/{{$.book_id}}` 可在元素上下文中构造详情 URL；
- `##` 可用于清理或格式化测试文本；
- `@js:result.replace(...)` 可用于转换合成状态码。

完整字段骨架见本文末尾的模板；模板故意不包含可用的真实站点地址、接口、凭据或内容规则。

### 登录、Cookie 与网页验证

应用会综合 HTTP 状态、响应内容、规则中的验证提示以及登录字段判断是否需要网页验证。常见流程：

1. 为书源设置 `loginUrl`；
2. 搜索、发现、详情、目录或正文命中登录/验证页；
3. 应用打开验证页面；
4. 用户在 WebView 中完成登录或验证；
5. Cookie 同步到书源请求；
6. 返回后重试原操作。

#### `loginUi` 控件

静态 `loginUi` 通常是控件数组，当前识别：

| `type` | 显示/行为 |
| --- | --- |
| `text`、`input`、`email`、`number` | 普通输入框。 |
| `password` | 密码输入框。 |
| `toggle` | 开关，使用 `chars` 的第 1/2 项作为关闭/开启值。 |
| `select` | 选择框，候选值来自 `chars`。 |
| `button` 或其他带 `action` 的项 | 执行登录/接口动作。 |

控件可使用 `name`、`viewName`、`placeholder`、`value`、`default`/`defaultValue`、`chars`、`action` 和 `style`。输入、开关与选择值写入 `source.loginInfo`；重新打开面板会恢复。对于原书源把开关伪装成按钮的情况，应用还会根据名称、动作及脚本持久化状态推断“已开启/已关闭”，但新书源应优先使用明确的 `toggle`/`select`。

`loginUi` 也可以是动态 `@js:`/`<js>` 脚本，返回控件数组 JSON。动态控件生成和按钮动作均有超时、输出大小和网络响应限制。

#### 登录动作 ArkWeb 桥

登录动作使用独立 ArkWeb 运行环境，不会让搜索或正文自动改走登录页面。当前桥接包括：

- `java.ajax` 的受控 HTTP 请求与逐步响应回填；
- `source.variable`、`loginHeader`、`loginInfo`、`source.get/put` 和 `cache` 状态；
- Cookie 获取、设置、替换、按名称删除及网页 Cookie 回写；
- Base64/Base64URL、Hex、URL/HTML 编解码、字节数组和 UUID；
- `createSymmetricCrypto` 的 AES/DES/3DES 常见变换；
- `startBrowser`、`startBrowserAwait`、`showBrowser`、`openUrl`；
- 登录动作中的 `java.webView`（加载指定 URL 并执行脚本后回传结果）；
- `searchBook`、`refreshExplore`、`reLoginView` 等 UI 动作。

`startBrowserAwait` 会暂停当前脚本，打开网页，用户点击完成后将页面返回值交回同一动作继续执行。浏览器关闭、取消、网络失败或脚本超时会结束执行并恢复按钮状态，不应永久停在“执行中”。用于“书源更新”的按钮可以打开源提供的更新页面；页面是否真正更新配置取决于该脚本是否返回并保存了新数据，不能仅凭打开网页判定更新成功。

请求规则中的 `<js>startBrowserAwait(...)`、`getVerificationCode(...)` 等提示也可触发验证逻辑，但不是完整 Android WebView/Activity API。需要账号口令签名、动态参数或复杂验证码的网站，必须实机确认。应用不按站点名称提供私有接口适配，全部请求参数和解析逻辑应来自书源本身。

登录动作会通过确定性脚本重放完成多次 `java.ajax` 和网页等待。Cookie 写入、替换和删除操作会记录并去重，避免重放时重复修改会话；`cookie.setCookie()` 传入 `token=...; deviceId=...` 这类请求头形式时，会区分真正的 Cookie 属性并把多个键分别写入 ArkWeb。脚本在 AJAX 前写入的 `source`/`loginInfo` 状态会合并到当前请求上下文。`getLoginInfo`/`getLoginInfoMap` 对空格、标点差异的键名做兼容，只有一个可用 Token 类字段时也可作为回退值。

### 有声书源与音色

有声书源可通过 `bookSourceType: 1`、书籍 `type` 的音频位，或书源明确提供的类型/标签元数据标记。正文规则应最终返回一个可播放的 HTTP/HTTPS 音频地址。若 `content` 为空或只是基础地址规则，目录中的 `chapterUrl` 可直接作为播放地址；签名流不要求具有音频文件扩展名。

当目录的 `chapterUrl` 规则显式带有 `webView: true` 且直接地址不可播放时，应用可在隔离 ArkWeb 中加载书源给出的章节页，并从 `<audio>`、`<source>`、`<video>` 或页面资源中提取候选媒体 URL；失败后仍回退普通正文规则。该行为不包含站点专用接口或解密。播放页支持：

- 播放/暂停、进度、倍速、上一章/下一章和目录跳转；
- 定时停止；
- 音色代码输入，留空表示书源默认值；
- 将音色写入 `book.getVariable('custom')`，刷新当前音频地址；
- 返回书架或进入后台继续播放，并通过全局胶囊/系统 AVSession 控制；听书页和全局朗读面板可切换目录正序/倒序，切换只改变展示索引，不改变章节的规范索引和 `chapterUrl`。

目录正序/倒序、当前章节自动定位、简介文本选择和返回书架后的阅读进度刷新属于阅读器/播放器界面行为，不需要书源增加字段，也不会改变 `chapterList`、`chapterName`、`chapterUrl` 或音频地址的解析顺序。书源只需继续返回稳定的规范章节顺序，应用在界面层进行展示排序。

音色代码只有在书源规则实际读取 `book.getVariable('custom')` 或编码协议把该值带入音频请求时才会生效。若音频接口要求账号、Token、设备 ID 或购买权限，空音色或更换音色不能替代登录；应先确认接口返回的是真实音频而不是 401/JSON 错误页。

不要把账号、密码、长期 Token 直接提交到公共书源 JSON。优先通过登录页获取短期 Cookie，或仅在本机编辑 `loginHeader`。

## 开发与验证

### 先确认接口

记录每一阶段：

- 请求 URL、方法、query、body；
- 必须的 User-Agent、Referer、Cookie、Content-Type；
- 响应编码；
- 搜索列表路径和唯一书籍 ID；
- 详情页到目录的关系；
- 章节 ID、正文路径；
- 是否有重定向、登录、验证码、签名、加密。

优先选择站点公开且稳定的 JSON 接口；HTML 结构常改，复杂 JS 签名和反爬验证的维护成本最高。

### 按阶段增量开发

1. 只写顶层字段、`searchUrl` 和 `ruleSearch`；确保至少出现一条有书名、有详情 URL 的结果。
2. 写 `ruleBookInfo`；确认详情信息和 `tocUrl` 正确。
3. 写 `ruleToc`；确认章节数、顺序、名称、URL。
4. 写 `ruleContent`；先只提正文，再添加净化正则。
5. 最后复制/调整搜索规则为发现规则，补充分类和分页。
6. 再处理登录、Cookie、字符集、加密和 JS 兼容表达式。

### 应用内验收清单

书源可从文件或 URL 导入，也可在“我的 → 书源管理 → 新建书源”逐字段填写。完整验收清单：

- [ ] JSON 可导入，书源名称和地址正确；
- [ ] 导出后 `jsLib`、`loginUrl`、`loginUi`、五组规则和原始扩展字段没有丢失；
- [ ] 启用书源后能搜索到结果；
- [ ] 搜索未结束时可以滑动结果，停止搜索后不会继续追加旧会话结果；
- [ ] 搜索中文、空格、特殊字符时编码正确；
- [ ] 书名和详情 URL 不为空；
- [ ] 相对详情 URL 和封面 URL 能正确补全；
- [ ] 搜索、发现和详情封面均为实际图片地址；列表页错误的非空封面不会指望详情规则自动覆盖；
- [ ] `author` 没有因宽泛选择器混入字数、阅读量或脚本源码，`wordCount` 已返回带正确单位的最终字符串；
- [ ] 详情字段不会被登录页或错误页污染；
- [ ] 目录 URL 正确，章节数和顺序合理；
- [ ] 目录页同时存在“最新章节”和完整目录时，没有重复或把最新章节倒插到最前面；正式规则失败时不把临时通用目录误认为校验通过；
- [ ] 第一章、中间章、最后一章都能加载；
- [ ] 随机抽查存在正文翻页的章节，确认 `nextContentUrl` 能拼接全部页面且不会循环；
- [ ] 正文没有导航、广告、脚本或整页错误信息；
- [ ] 开启段评后气泡跟随正确段落、可点击，翻页没有异常大空行；关闭段评后正文排版恢复；
- [ ] 朗读文本不包含 `LEGADO_READER_ACTION`、`<comment>` 或其他内部代码；
- [ ] 朗读不会逐个念出整行 `*****`、`#####`、`&&&&&` 等装饰符；含普通文字的特殊字符仍被保留；
- [ ] 漫画源图片顺序、请求头、长图宽度和上一/下一章行为正确；
- [ ] 有声书源能播放、暂停、切章、目录跳转、切换音色，并在后台/书架胶囊中继续控制；
- [ ] 发现分类可打开，翻页后内容变化；
- [ ] 登录/验证后 Cookie 能继续用于后续请求；
- [ ] 登录面板中的输入、开关、选择项和按钮状态关闭后重开仍保持；
- [ ] `startBrowserAwait` 完成或取消后按钮不会一直显示“执行中”；
- [ ] 站点 301/302、HTTP/HTTPS 或镜像变化时行为可接受。

运行应用时，搜索、发现和 WebBook 服务会输出包含 `[SC]`、`[ExploreCoordinator]`、`[WS]` 的日志，可重点查看：最终 URL、状态码、响应长度、列表命中数量和第一条结果。

### 单书源调试

书源管理页的操作菜单提供“调试”，书源编辑页在填写有效的 `bookSourceUrl` 后也可以直接进入调试页。调试页支持以下阶段：

- **搜索**：输入测试关键词，执行当前书源的搜索请求和列表字段解析。
- **发现**：输入可选关键词，使用第一个发现分类执行列表解析。
- **详情**：输入书籍或详情 URL，检查 `ruleBookInfo` 字段和 `tocUrl`。
- **目录**：输入书籍或目录 URL，最多抽样 32 章，检查章节名和章节地址。
- **正文**：输入章节 URL，检查正文规则返回的内容。
- **全链路**：从搜索或发现取得候选书，再依次执行详情、目录和首章正文。

执行明细会记录网络请求的最终地址、状态码、响应大小和摘要，以及每个字段的规则类型、输入数、匹配数、耗时、输出预览和错误。调试信息只用于当前诊断会话，不改变书源规则；调试阶段仍使用应用的正常请求、Cookie、登录和 ArkWeb 路由，因此不能替代真实账号状态下的最终验收。正文阶段的输入是章节 URL，详情和目录阶段的输入应是书源能够处理的书籍/目录 URL。

调试完成后可点击“导出报告”，通过系统文件选择器保存 JSON 诊断文件。报告包含执行阶段、网络轨迹、规则匹配和错误信息；导出时会对来源地址等字段执行脱敏处理，但规则内容和响应摘要仍可能包含站点或个人敏感信息，提交前应人工检查并删除 Cookie、Token、账号及其他私密数据。调试页和书源编辑页会监听系统键盘避让区域，输入规则时自动为底部内容预留空间。

当出现“请求成功但字段为空”时，先查看对应字段的匹配数和输出预览；当出现地址未解析、目录为空或正文为空时，按网络请求 → URL 规则 → 字段规则的顺序检查。调试日志中若出现 401/403、验证码或登录页，应先完成书源登录/网页验证，再重新运行对应阶段。

### 常见故障定位

| 现象 | 优先检查 |
| --- | --- |
| 书源完全不参与搜索 | `enabled`，以及 `searchUrl`、`bookList`、`name`、`bookUrl` 是否都非空。 |
| 浏览器能下载 JSON，但 URL 导入失败 | 确认返回体不是 HTML 跳转页；查看错误来自应用 HTTP、TCP、ArkWeb 下载还是系统下载；必要时改用本地文件导入。 |
| 导入提示 `[object Object]` | 当前版本会展开 `message/msg/reason/code`；若仍出现，保留完整错误和 URL，检查服务是否返回了非标准对象或空下载错误。 |
| HTTP 成功但列表为 0 | 响应实际是 JSON 还是 HTML；列表规则是否在完整响应运行；字符集和登录页。 |
| 列表命中但无结果 | 子规则上下文是否错误；最常见是 `name` 或 `bookUrl` 为空。 |
| 中文搜索乱码 | 使用 `{{searchKeyRaw}}` 并在 URL 选项中指定 `gb2312`/`gbk`。 |
| URL 中出现 `%257B`、关键字双重编码 | 不要预编码 `{{key}}`，或改用 `{{searchKeyRaw}}`。 |
| 详情能开但无目录 | `tocUrl` 是否在 `init` 后的上下文解析；是否错误拼到详情页目录；相对地址基准是否正确。 |
| 目录链接包含 `?name=...`，正文地址少了 `read.php` | 这是查询相对链接；应以章节列表响应的最终 URL 为基准。当前版本会保留文档路径；规则不要把完整 URL 再套 `encodeURIComponent`，只对参数值编码。 |
| 目录有标题但章节被丢弃 | `chapterUrl` 为空或仍含未解析的模板/JSONPath。 |
| 正文多个段落被合并、行间出现很长空白 | 检查正文规则是否提取了 HTML 块而丢失段落边界。当前版本会把 `</p>`、`</div>` 转成段落分隔，并按独立段落渲染；不要在规则中把整段 HTML 先压成单行或插入大量普通空格。 |
| 正式目录规则失败但阅读页仍有目录 | 首次打开可能正在使用临时通用 HTML 目录；查看 `[WS] 通用目录兜底` 日志或“正式目录规则未匹配”提示。修好 `chapterList`，不要把临时结果当作书源有效。 |
| 目录末尾章节出现在最前面或重复 | 页面可能先渲染“最新章节”再渲染完整目录；优先让 `chapterList` 精确限制在完整目录容器，通用兜底只在正式规则 0 匹配时生效。 |
| 发现页显示 `renderCount('...')万字` | 普通 HTTP 不执行页面内脚本；从局部 `@html` 提取数字并用 `<js>` 换算，或在确实依赖渲染时使用 `webView`/`webJs`。同时确认它来自 `wordCount`，而不是宽泛的 `author` 多命中。 |
| `wordCount`、`lastChapter` 或 `updateTime` 已解析但卡片没有显示 | 确认使用的是当前版本的搜索/发现组件，并检查字段规则是否返回空字符串；卡片会以元数据行显示字数、最新章节和更新时间。不要误把多个同 class 元素都塞进 `author`，除非明确接受元数据污染。 |
| 发现有封面、详情后封面仍错误 | 详情规则不会覆盖非空列表封面；先修正 `ruleSearch`/`ruleExplore.coverUrl`，或让不可靠的列表封面返回空值。 |
| 正文返回整页文字 | `content` 选择器太宽；先缩到正文容器，再用 `replaceRegex`。 |
| 正文是空字符串 | 请求失败、被验证拦截、提取规则为空，或提取结果被净化正则全部删除。 |
| `text.下一页@href` 没有继续翻页 | 检查链接的“下一页”是否为 `<a>` 自身直接文本；若文字包在子元素中，改用稳定 CSS 或 `:contains()`。还要确认下一页不是 JavaScript 点击事件。 |
| 有下一页规则但正文仍不完整 | `nextContentUrl` 只能跟随真实分页链接；若服务端 HTML 已截断而完整正文位于页面脚本状态/渲染 DOM，改用显式 `webView: true` / `webJs` 返回完整内容。 |
| 正文显示 `JSON.parse(undefined)` | 检查脚本变量是否由 `data:` 负载、`java.ajax` 或上一条规则提供；不要假定不存在的字段会自动变成 `{}`。 |
| 朗读一直念星号、井号或与号 | 当前版本会过滤只由常见装饰符组成的整行，也会静音正文中的长重复装饰符号（URL 中的 `://` 会保留）；若符号与推广文字混在同一行，仍可使用 `replaceRegex` 精确清理该站文本。 |
| 开启段评后正文显示内部代码 | 确认返回的是 `<comment ident count>` 或 `<img ident>` 支持格式，并在正文清理前进入统一交互后处理；TTS 必须使用剥离动作标记后的文本。 |
| 段评气泡存在但无法点击 | `ident` 必须是完整或可补全 URL，并包含正确书籍/章节 ID；同时检查段评开关、登录 Cookie 和后端返回。 |
| 登录按钮脚本超时 | 检查动作是否等待未完成的网页、反复请求同一 URL、调用未映射的主机方法，或超过网络/脚本限制；错误提示中的“缺少兼容能力”优先处理。 |
| 登录面板开关没有状态 | 新源使用 `type: "toggle"`/`"select"`、`chars` 和默认值；旧按钮式开关需确保动作把状态写入 `source`、`java` 或 `loginInfo`。 |
| 有声书有目录但不能播放 | 确认 `chapterUrl` 已返回可播放地址；若使用页面抓取，确认其请求选项显式包含 `webView: true` 且 `sourceRegex` 能匹配页面媒体请求；同时检查登录、Token、音色代码和响应是否为 401/JSON 错误。 |
| CSS 在小页面可用、大页面失效 | HTML 超过 4 MiB 保护阈值；寻找 JSON API 或减少响应。 |
| Android 阅读中可用、此处不可用 | 查看该阶段是否路由 ArkWeb、是否调用未映射 `java/source/cache/cookie` 方法、浏览器直连网络、复杂 XPath/CSS 或未消费字段。 |

### 批量书源校验状态

书源管理提供两种校验模式：

- **搜索能力**：使用固定测试关键字检查搜索请求和最小结果字段，速度较快；只有该模式允许对“明确失败”项自动禁用或删除。
- **发现/阅读链路**：逐源执行真实的“发现分类 → 最多前 8 个分类 → 最多 4 本候选书 → 详情 → 目录抽样 → 最多 3 个非 VIP/非付费章节”。目录最多抽样 32 章，并根据书籍类型确认正文非空、漫画至少有图片或有声书得到 HTTP(S) 播放地址。该模式只报告，不自动处理书源。

校验不是简单的“成功/失败”二值：

| 状态 | 含义 |
| --- | --- |
| 通过 | 搜索模式解析出至少一条有效书籍；或发现/阅读模式完整通过发现、详情、目录和内容样本。 |
| 失败 | 缺少必要规则、明确的 4xx 请求错误、规则/选择器语法错误或预检判定不安全。 |
| 无结果 | 请求和规则执行完成，但测试关键字、发现分类或候选样本没有有效结果。 |
| 需要验证 | HTTP 401/403，响应被识别为登录/验证码页面，或全链路样本只有 VIP/付费章节而无法安全测试。 |
| 暂时异常 | 超时、取消、429、5xx、空响应、响应过大或其他暂时网络问题。 |

校验模式使用更保守的限制：并发 1、单响应 512 KiB、单条可执行规则 32 KiB、书源脚本配置 512 KiB，并拒绝高风险嵌套正则。日常搜索允许更大的响应和聚合脚本，因此“校验失败：配置过大”不必然等于日常链路完全不能运行，但仍应缩小测试脚本或按阶段验证。401/403 应归类为“需要验证”，不应批量禁用或删除。

校验完成后，结果面板提供两类处理方式：

- **批量禁用**：只对明确失败的书源执行，锁定书源不会被自动处理；
- **删除失败项**：批量删除明确失败的书源，锁定书源会被跳过。

“无结果”“需要验证”和“暂时异常”不会自动进入失败项，避免因为测试关键字、登录状态或临时网络问题误删书源。校验进度只展示已校验数量、状态和自动处理结果，不以“命中 X 本”作为用户可见结论。

在 API 18 及以上设备上，若普通 HTTP 客户端明确报告证书校验错误，结果页可由用户选择仅信任报错的精确主机并重试。该例外只保存在本机，不扩展到子域、同级域名或重定向主机，并可从书源操作菜单撤销。跳过证书校验会增加连接被冒充或监听的风险，不能作为书源的默认配置，也不适用于隐藏 ArkWeb 的浏览器证书页面。

### 编写质量建议

- 只使用目标站授权或允许访问的内容，并遵守服务条款、版权和访问频率限制。
- `bookSourceUrl` 使用稳定的站点根地址，不要把搜索参数当作唯一键。
- 规则尽量短、确定；优先明确 ID/class/JSON 字段，少用跨整页的贪婪正则。
- 列表规则只负责选元素，字段规则只负责取字段，净化规则只负责清理文本。
- 必填字段不要依赖兜底逻辑；应用不会按站点名称补造接口、参数或解密，通用容错也不是书源 API。
- 请求头只保留必要项。伪造过多浏览器安全头可能比缺省更容易失效。
- `replaceRegex` 从小到大增加，并用第一章、VIP 章、最后一章验证，避免误删全文。
- 对 JSON 中的反斜杠进行双重转义。例如正则 `\s+` 在 JSON 字符串中写作 `"\\s+"`。
- 提交公共书源前删除 Cookie、Token、账号、设备标识和调试接口。
- 在备注中说明源类型、登录要求、已知限制和维护日期。

## 兼容性与迁移

### 字段能力矩阵

| 状态 | 字段/能力 |
| --- | --- |
| 通用链已实际使用 | 搜索/发现的列表、书名、作者、封面、简介、分类、状态、最新章节、字数、更新时间、详情 URL；发现两级分组和动态原生筛选；`jsLib` URL 构建和持久化源变量；分阶段 ArkWeb；显式 `webView`/`webJs` 请求；动态登录输入/开关/选择/按钮、同站点 Cookie、幂等 Cookie 重放、浏览器等待；详情 `init`、书籍字段、状态、`updateTime`、目录 URL；目录列表、章节名、章节 URL、下一页、VIP、付费状态、更新时间；正文内容、图片、图片请求头、书源规则内图片解码、漫画模式、下一页、净化正则和 JS；普通书/漫画/有声书类型；书源请求限流。 |
| 已接入并可安全灰度 | QuickJS 启动自检、持久化纯表达式比对、合格指纹灰度接管、失败回退和熔断；不直接执行主机函数，也不替代选择器或复杂 ArkWeb 脚本。 |
| 编码数据已实际使用 | 标准 `data:` 文本、Base64 负载，以及带明确 HTTP(S) URL 的通用 `type: "request"` 请求描述。应用不提供平台协议、候选后端或站点专用会话补丁。 |
| 可导入/编辑，但通用链目前未消费 | 正文 `title`。 |
| 模型或紧凑格式存在，但通用导入/UI/执行不完整 | `chapterListAddition`、`payAction`、`bookListRule` 等。 |
| 不应假定与 Android 版等价 | 任意 Java/Android 类导入、全部 `java.*` API、完整 XPath/CSS、付费购买动作、交互式验证码自动处理及非白名单二进制解码流程。 |

### 通用兜底边界

当前项目只保留与站点无关的容错和显式能力，例如清理模板残留、解析标准相对 URL、从通用字段回退详情地址、提取可读 HTML、处理明确的编码数据，以及由书源声明的 `session` 会话规则。应用不会根据站点名称或私有接口提供自动修复；书源应完整声明请求和解析规则。

### 与 Android 阅读书源互导

导入 Android 阅读书源时建议：

1. 保留标准对象形式的 `ruleSearch` 等规则组；
2. 删除当前不需要的字段，先验证最小链路；
3. 将复杂 XPath 改为 JSONPath/CSS；
4. 简单 JS 优先改为模板或 `##`；确需完整语义时确认该阶段已路由 ArkWeb，且只调用已桥接主机方法；
5. 普通 HTTP 可直接完成时优先使用 HTTP；页面必须执行脚本时可在该 URL 选项设置 `webView: true`，交互式验证码仍通过验证页由用户完成；
6. 对登录、Cookie、加密源逐项实机验证；
7. 对普通书、漫画、有声书和段评分别验证正文后处理与播放器；
8. 不以“导入成功”或“校验通过”作为全链路兼容的证明。

## 完整模板

下面模板列出当前可导入的主要字段，复制后删除不需要的项：

```json
[
  {
    "bookSourceName": "",
    "bookSourceUrl": "https://example.com",
    "bookSourceType": 0,
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
    "enabledCookieJar": true,
    "isPinned": false,
    "isLocked": false,
    "weight": 0,
    "customOrder": 0,
    "respondTime": 180000,
    "concurrentRate": "",
    "customButton": false,
    "eventListener": false,
    "ruleSearch": {
      "bookList": "",
      "name": "",
      "author": "",
      "coverUrl": "",
      "intro": "",
      "kind": "",
      "lastChapter": "",
      "bookUrl": "",
      "wordCount": "",
      "status": "",
      "updateTime": ""
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
      "wordCount": "",
      "status": "",
      "updateTime": ""
    },
    "ruleBookInfo": {
      "init": "",
      "name": "",
      "author": "",
      "coverUrl": "",
      "intro": "",
      "kind": "",
      "status": "",
      "lastChapter": "",
      "wordCount": "",
      "updateTime": "",
      "tocUrl": ""
    },
    "ruleToc": {
      "chapterList": "",
      "chapterName": "",
      "chapterUrl": "",
      "nextTocUrl": "",
      "isVip": "",
      "isPay": "",
      "updateTime": "",
      "chapterListAddition": ""
    },
    "ruleContent": {
      "content": "",
      "title": "",
      "images": "",
      "sourceRegex": "",
      "nextContentUrl": "",
      "replaceRegex": "",
      "imageDecode": "",
      "imageStyle": "",
      "payAction": ""
    }
  }
]
```

## 实现索引

需要继续扩展规则能力时，可从这些实现入口核对：

- 数据模型：`entry/src/main/ets/model/data/Book.ts`
- JSON 导入兼容：`entry/src/main/ets/pages/BookSource.ets`
- 书源与搜索结果列表快捷操作：`entry/src/main/ets/pages/BookSource.ets`、`entry/src/main/ets/components/book/SearchBookResultList.ets`
- URL 相对地址解析：`entry/src/main/ets/core/book/BookUrlResolver.ts`
- 编辑器字段：`entry/src/main/ets/pages/BookSourceEdit.ets`
- URL 和请求选项：`entry/src/main/ets/core/rule/AnalyzeUrl.ts`
- 通用规则解析：`entry/src/main/ets/core/rule/AnalyzeRule.ts`
- 规则中间值与执行目标：`entry/src/main/ets/core/rule/RuleValue.ts`
- JSONPath：`entry/src/main/ets/core/rule/JsonPathEvaluator.ts`
- JS 兼容层：`entry/src/main/ets/core/rule/JsRuntime.ts`
- QuickJS 迁移运行时：`entry/src/main/ets/core/script/QuickJsScriptRuntime.ts`、`QuickJsAsyncRouter.ts`、`QuickJsMigrationStore.ts`、`QuickJsRuntimeStatus.ts`、`QuickJsShadowExecutor.ets`
- 分阶段运行路由：`entry/src/main/ets/core/book/BookSourceRuntimeRouter.ts`
- 搜索/发现/详情/目录/正文 ArkWeb：`entry/src/main/ets/core/book/BookSourceStageWebRuntime.ts`
- 显式 `webView` 请求：`entry/src/main/ets/core/book/WebBookFetchRuntime.ts`
- 阶段规则识别：`entry/src/main/ets/core/book/BookSourceStageRuleSupport.ts`
- 登录面板 ArkWeb：`entry/src/main/ets/core/book/BookSourceLoginWebRuntime.ts`
- 搜索流程：`entry/src/main/ets/core/book/SearchCoordinator.ts`
- 发现流程：`entry/src/main/ets/core/book/ExploreCoordinator.ts`
- 详情、目录、正文：`entry/src/main/ets/core/book/WebBookService.ts`
- 编码地址与快捷协议：`entry/src/main/ets/core/book/BookSourceDataUrlSupport.ts`、`entry/src/main/ets/core/book/EncodedSourceUrl.ts`
- 正文交互后处理：`entry/src/main/ets/core/book/BookSourceInteractionPostProcessor.ts`、`entry/src/main/ets/core/book/ReaderActionMarker.ts`
- 书籍类型识别：`entry/src/main/ets/core/book/BookTypeSupport.ts`
- 有声书页面与后台播放：`entry/src/main/ets/pages/AudioBook.ets`、`entry/src/main/ets/utils/RemoteAudioPlayback.ets`、`entry/src/main/ets/utils/ReaderTtsFloatingSession.ets`
- 数据库存储：`entry/src/main/ets/model/data/AppDatabase.ts`
- 阅读器 V2 文档、分页和交互：`entry/src/main/ets/core/reader/ReaderV2Document.ets`、`ReaderV2Paginator.ets`、`ReaderV2RenderNode.ets`、`ReaderV2Interaction.ets`
- 阅读打开链路追踪：`entry/src/main/ets/utils/ReaderOpenTrace.ts`

书源校验与批量处理入口：

- 书源管理页及导入、校验、批量操作：`entry/src/main/ets/pages/BookSource.ets`
- 校验状态和后台校验任务：`BookSource.ets` 中的 `startCheckSources`、`bookSourceCheckProgressText`、`deleteFailedCheckedSources`
- 单书源调试页及阶段执行：`entry/src/main/ets/pages/BookSourceDebug.ets`、`entry/src/main/ets/core/book/BookSourceDebugModels.ts`
- 调试请求和规则轨迹：`HttpClient.ts`、`RuleExecutionService.ts`、`BookSourceStageWebRuntime.ts` 中的 `BookSourceDebugContext`
- 发现/阅读全链路校验：`entry/src/main/ets/core/book/ExploreReadingValidator.ts`
- 用户控制的精确主机证书例外：`entry/src/main/ets/core/http/TlsTrustStore.ts`
- 规则执行快照与阅读交互桥接：`entry/src/main/ets/core/book/BookSourceRuntimeSnapshot.ts`、`entry/src/main/ets/core/book/ReaderInteractionProvider.ts`
