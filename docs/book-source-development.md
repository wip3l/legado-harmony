# 书源规则开发文档

开源轻页和简听共用书源解析内核 [harmony-book-source-engine](https://github.com/wip3l/harmony-book-source-engine)。规则格式、字段、表达式、选择器及示例在内核仓库统一维护；本文说明当前轻页的接入情况、开发入口和操作流程。

- [当前内核的公共书源规则开发文档](../harmony-book-source-engine/docs/book-source-development.md)：第一部分原生书源（推荐），第二部分兼容书源（已过时）
- [开发流程](../harmony-book-source-engine/docs/book-source-development.md#开发流程)、[网页书站示例](../harmony-book-source-engine/docs/book-source-development.md#网页书站示例)、[综合示例](../harmony-book-source-engine/docs/book-source-development.md#综合示例)：从零写一个原生书源
- [字段速查](../harmony-book-source-engine/docs/book-source-development.md#字段速查)、[导入校验与常见报错](../harmony-book-source-engine/docs/book-source-development.md#导入校验与常见报错)、[从兼容书源改写](../harmony-book-source-engine/docs/book-source-development.md#从兼容书源改写)
- [JS 函数库 `js`](../harmony-book-source-engine/docs/book-source-development.md#js-函数库-js)：表达式调用、内置函数、参数与返回值、限制
- [后台脚本阶段 `script`](../harmony-book-source-engine/docs/book-source-development.md#脚本阶段-script)：请求、状态、登录、网页交互、完整示例与排错
- [封面解密 coverDecode](https://github.com/wip3l/harmony-book-source-engine/blob/main/docs/book-source-development.md#加密封面-coverdecode)：含封面请求头 `coverHeaders`
- [自定义图片字节脚本](../harmony-book-source-engine/docs/book-source-development.md#自定义图片字节脚本)：`content.imageDecode.script`，以及标准算法的 `ivPrefixBytes`、`keyEncoding`
- [宿主图片加载接入](https://github.com/wip3l/harmony-book-source-engine/blob/main/docs/cover-decoding.md)
- [内核 HAR 接入说明](https://github.com/wip3l/harmony-book-source-engine/blob/main/sourceengine/README.md)

本仓库以子模块 `harmony-book-source-engine/` 引用内核，克隆后先执行 `git submodule update --init`。轻页使用子模块固定的内核提交，内核新增的规则能力要等子模块升级后才在轻页里生效；[在线主分支文档](https://github.com/wip3l/harmony-book-source-engine/blob/main/docs/book-source-development.md)可能领先于当前应用。

## 原生 JS 开发路线

当前原生书源已经支持 JavaScript，无需打开“脚本引擎迁移”的灰度开关。按任务选择写法：

| 需求 | 写法 | 运行位置 |
| --- | --- | --- |
| 拼接地址、字段转换、选择器提取 | 声明式规则、表达式、`lib` | 原生规则解析器 |
| 签名、解密、复用纯 JS 算法 | 顶层 `js` 定义函数，在表达式或模板中按名调用 | 主线程同步 QuickJS；单次最多 300 ms，不能请求网络或写状态 |
| 先取令牌再请求、批量取详情、自行分页 | `search/explore/detail/toc/content.script` 指定 `js` 中的函数名 | 后台 QuickJS；同步写法调用 `http` 等宿主接口 |
| 多步登录、发送验证码 | `login.script`、`login.sendCode.script` | 后台脚本，表单值从 `ctx.form` 读取 |
| 设置页按钮、动态下拉选项 | `actions[].script`、`vars[].optionsScript` | 后台脚本；按钮返回提示，选项返回字符串数组 |

`js` 是 JSON 中的一段字符串，换行需要写成 `\n`，也可以先在编辑器里编写 JS 再用 `JSON.stringify` 转成 JSON 字符串。原生规则不使用兼容书源的 `@js:`、`<js>`、`jsLib` 或 `java.*` 写法。

脚本阶段返回的是供规则解析的页面或 JSON，不必手动构造应用的数据库对象。返回后仍可使用 `let`、`fail`、`list`、`fields` 和正文提取规则；返回数组且省略 `list` 时逐项解析。目录与正文的脚本要自行完成分页，`nextUrl` 不再生效。完整接口、状态作用域和可复制示例见公共文档，不在此维护第二套规范。

## 在轻页中开发与验证

1. 在「我的 → 书源管理 → 新建原生书源」编辑完整 JSON，先“校验”再“保存”。校验检查定义和函数等约束，不代表网站链路已经可用。
2. 打开“调试”，依次验证搜索、详情、目录、正文和发现；脚本请求、`log(...)` 与结果摘要出现在执行明细中，报错会带阶段和函数名。
3. 打开“书源设置”，分别验证变量保存、动态选项、登录、验证码和动作按钮。先保存手动修改的变量，再执行依赖这些变量的按钮；按钮执行时显示忙碌状态，结束后刷新登录状态和动作列表。
4. 实测需要验证的流程：搜索和发现提示“去验证”后，完成网页操作并重新发起请求；详情、目录、正文或设置页脚本调用 `browser.verify` 时，点网页右上角“完成”才会继续，返回或取消会报“网页操作已取消”。
5. 从仓库根目录运行下面的规则回归；在真机上通过「其他设置 → 兼容与诊断 → 脚本引擎迁移 → 后台脚本线程验证」检查原生运行时，再验收真实页面交互。

```powershell
node --experimental-strip-types harmony-book-source-engine/scripts/native-source-check.mjs
node --experimental-strip-types harmony-book-source-engine/scripts/native-js-check.mjs
node --experimental-strip-types harmony-book-source-engine/scripts/native-script-check.mjs
```

Node 检查使用替身，不会验证真机 QuickJS、系统网页控件或实际站点登录。遇到“表达式里不能发请求或读写状态”时，将流程移到阶段 `script`；遇到请求次数或运行时间超限时，减少请求、使用缓存或拆分流程。更多原因见公共文档的原生脚本排错表。

## 轻页的宿主差异

| 能力 | 轻页现状（4.3.928） |
| --- | --- |
| 原生书源 | 支持编辑、书源设置（变量、音色、账号登录、动作按钮）、搜索、发现、详情、目录、正文、听书、视频播放与漫画图片解密；书源管理和发现页的长按菜单可进入书源设置 |
| 原生 JS | `js` 函数库与 `script` 阶段已接入；`http`、变量、Cookie、缓存、凭据和详情书籍变量通过内核宿主接口处理，与兼容书源迁移开关独立 |
| 原生脚本界面交互 | 启动时通过 `NativeSourceInteraction.setHandler(new AppSourceInteraction(...))` 安装提示、发现缓存失效和网页处理器；`ui.toast` 显示书源名称与消息，`ui.refreshExplore` 清除该源发现缓存 |
| 原生网页交互 | `browser.verify` 沿用内置验证页，点“完成”返回 HTML 并保存 Cookie；搜索和发现只提示“去验证”。`browser.open` 打开网页但不等待结果；`browser.render` 使用内核网页抓取宿主 |
| 设置页脚本 | 动作按钮运行中显示状态并防止重复执行；动态选项获取失败时保留静态选项并显示原因；成功加载后若原值不在新列表中，会选中第一项并标记待保存 |
| 封面解密 `coverDecode` | 已接入：封面下载时识别 `SourceCoverUrl` 标记，从数据库取该书源后调用 `SourceCoverLoader` 解密并缓存到本地；书架、搜索与发现结果、详情页、听书页、目录面板、阅读统计、桌面卡片和朗读媒体卡片都显示解密后的封面，解密完成前显示占位。局域网阅读的封面接口同样转发解密后的图片。解密结果按封面地址缓存，书源改了 `coverDecode` 参数后，已缓存的封面不会自动重新解密 |
| 正文图片解密 | 漫画图片与正文插图下载后按 `content.imageDecode` 解密：支持标准算法、`ivPrefixBytes:16`、`keyEncoding`，以及在后台 QuickJS 里运行的 `imageDecode.script` 字节脚本；脚本结果按书源、脚本代码、配置和图片地址缓存，翻章或退出阅读时会取消未完成的解密 |
| 封面请求头 `coverHeaders` | 带请求头的封面经应用下载并缓存，请求头参与缓存标识 |
| 兼容脚本提示 `java.toast` | 详情、目录、正文阶段的提示显示为应用内提示，同一书源的同一条提示 15 秒内只显示一次；原生脚本使用 `ui.toast` |
| 网络错误 | 域名解析失败、超时、连接被拒等直接显示真实原因，不会误报“需要登录或网页验证” |
| 书源导入 | URL、剪贴板、本地文件（可一次多选，合并后统一勾选）和系统“打开方式” |
| 书籍类型 | 以详情阶段的结果为准：搜索或发现列表里标为有声、漫画、视频的书，如果详情接口返回的是小说信息，进入详情后按小说处理；书源的有声版与小说版不要共用同一个书籍 ID。有声书在详情页点“开始听书”直接进入听书页 |
| 可选宿主端口 `SourceEngineHost` | 不安装，按内核默认行为运行；这不影响独立安装的 `NativeSourceInteraction` 界面处理器与 `BookSourceRuntimeStore` 持久化 |

修改规则格式与开发说明请到内核仓库提交。轻页只维护自己的页面、导入与调试操作和宿主接入说明。

## 4.3.928 验收补充

- 发现页 `dynamicMenus` 可写 `script`：函数返回分类数组，或按行（或 `&&`）分隔的“名称::地址”文本，没有 `::` 的行是分组标题。
- 顶层 `headers` 在每个请求上按当前作用域求值（各阶段、分类、附加请求、动作按钮、登录和脚本里的 `http.*`），与本次请求的请求头合并，同名以本次请求为准；动态请求头可以直接写成表达式或模板。
- 写了 `optionsScript` 的变量，保存的值不再因不在静态 `options` 里而回退到默认值。
- 一章里单张图片下载或解密失败只影响这一张，原位显示原因；`data:` 内嵌图片也按 `imageDecode` 处理。含失败图片的章节不写入正文缓存。
- 正文缓存有 256 MiB 上限，自动清理只针对阅读和预缓存顺带写入的章节，“缓存全文”“缓存指定章节”写入的不会被清掉。

## 4.3.927 验收补充

- 验证漫画图片解密时分别检查标准算法、`ivPrefixBytes:16` 和 `imageDecode.script` 三种写法；脚本报错会带上 `content.imageDecode.script (函数名)`。
- 原生书源误用 `book.url` 时调试页会提示改用 `book.bookUrl`；分类菜单可单独设置 `list`、`fields`。
- 书源规则与脚本接口之外，本版主要是应用侧改动（会员与云同步、书架与阅读体验），不改变公共书源字段。

## 4.2.925 验收补充

- 原生书源的 JS 函数库与后台脚本阶段均已接入。验证登录、验证码、动态变量选项和动作按钮时，同时检查执行状态、失败提示及发现缓存刷新。
- 验证正文插图时，应确认下载缓存后的图片能够显示；多行 HTML 属性（例如 og:description）应完整提取。
- 书架关键词、标签和书源筛选属于应用侧功能，不改变公共书源字段或脚本接口。
