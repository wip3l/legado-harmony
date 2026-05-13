# 开源阅读纯净版

开源阅读纯净版是一个网络小说阅读应用，目标是实现类似「阅读 / Legado」的书源导入、搜索、发现、详情解析、目录解析和正文阅读体验。

项目使用 ArkTS 和 ArkUI 开发，当前包名为 `io.legado.read`，支持 phone 和 tablet。

## 功能概览

- 书架：管理已加入书籍，支持打开阅读、删除书籍和本地状态刷新。
- 搜索：基于已启用书源进行并发搜索，解析书名、作者、分类、封面和简介。
- 发现：读取 Legado 书源中的发现入口，按站点和分类浏览内容。
- 书源管理：支持从 URL、剪贴板或文本导入 Legado JSON 书源，支持启用、编辑和调试。
- 书籍详情：解析详情页信息，并支持加入书架和继续阅读。
- 目录解析：按书源规则获取章节列表，支持目录刷新和本地缓存。
- 正文解析：按章节加载正文，完成基础清洗、分页和阅读展示。
- 阅读设置：支持字号、行距、段落间距、阅读背景、深色模式、翻页方式、点击翻页和状态栏扩展。
- 沉浸阅读：阅读页适配顶部状态栏安全区和底部页码栏，支持正文区域扩展至状态栏。
- 悬浮底栏：主页面使用胶囊式悬浮底部操作栏，并接入 API 23 的系统自适应材质能力。

## 当前状态

这是一个正在迭代中的阅读应用项目，核心目标是让常见 Legado 书源在移动端可用。

当前已经重点适配过以下能力：

- HTTP GET / POST 请求、请求头、请求体和 URL 模板。
- JSONPath 常见写法，例如 `$.data`、`$.result.books[*]`、`{{$.book_id}}`。
- CSS 选择器常见写法，例如 `.book-item`、`#list a`、`a.0@href`。
- Legado 旧式链式规则，例如 `class.xxx.0@tag.li`、`id.xxx.0@tag.a`。
- 属性提取，例如 `a[data-bid]@data-bid`、`@href`、`@text`。
- 规则后处理，例如 `##regex##replacement`。
- 正则捕获组，例如 `$1`、`$2`、`$3`。
- 搜索、发现、详情、目录、正文链路的基础日志。

复杂 `<js>` 规则、浏览器 Cookie、人机验证、动态页面和强反爬站点仍可能需要继续补齐运行时能力。

## 开发环境

- DevEco Studio
- SDK `6.1.0(23)`
- ArkTS / ArkUI
- hvigor

应用配置：

- 应用模块：`entry`
- 入口 Ability：`EntryAbility`
- 支持设备：`phone`、`tablet`
- 权限：`ohos.permission.INTERNET`
- 开源协议：`GPL-3.0`

## 构建

推荐使用 DevEco Studio 打开项目后直接构建和安装。

也可以使用命令行构建 HAP：

```powershell
[Environment]::SetEnvironmentVariable("DEVECO_SDK_HOME", "C:\Program Files\Huawei\DevEco Studio\sdk", "Process")
& "C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat" --mode module -p module=entry@default -p product=default assembleHap
```

构建产物：

```text
entry/build/default/outputs/default/entry-default-signed.hap
```

## 使用说明

1. 安装应用后进入「我的」。
2. 打开「书源管理」。
3. 导入 Legado JSON 书源。
4. 返回首页后使用「搜索」查找书籍。
5. 进入书籍详情，加入书架或直接阅读。
6. 在阅读页点击中间区域呼出菜单，进入阅读设置调整排版和翻页方式。

发现页依赖书源中的 `exploreUrl` / `ruleExplore` 配置。若某个书源没有发现规则，或发现规则依赖站点动态能力，该书源可能不会在发现页返回内容。

## 书源调试

项目在关键链路中输出了调试日志，便于定位书源兼容问题：

- `[SC]`：搜索请求、响应、列表命中和首条结果。
- `[ExploreCoordinator]`：发现站点、分类、请求响应和列表命中。
- `[WS]`：书籍详情、目录和正文请求。
- `[RE]`：阅读引擎打开书籍、刷新目录和加载章节。

建议按以下顺序排查书源：

1. 搜索是否有结果。
2. 详情页是否能解析书籍信息。
3. 目录是否能解析章节列表。
4. 正文是否能读取章节内容。
5. 发现页是否能拿到站点、分类和分类下内容。

项目根目录保留了 `debug_source.json`，可用于本地调试书源兼容。

## 目录结构

```text
.
├── AppScope/                         # 应用级配置
├── entry/                            # 主模块
│   └── src/main/
│       ├── ets/
│       │   ├── components/           # 可复用组件
│       │   ├── core/
│       │   │   ├── book/             # 搜索、发现、详情、目录、正文服务
│       │   │   ├── http/             # HTTP 请求封装
│       │   │   └── rule/             # Legado URL 和规则解析
│       │   ├── entryability/         # 应用入口
│       │   ├── model/                # 数据模型、书源模型、本地数据库
│       │   └── pages/                # 页面
│       ├── module.json5              # 模块声明
│       └── resources/                # 资源文件
├── hvigor/                           # hvigor 配置
├── build-profile.json5               # 构建配置
├── oh-package.json5                  # 包信息
├── debug_source.json                 # 本地调试书源
└── README.md
```

## 核心模块

- `SearchCoordinator`：书源并发搜索、搜索进度和搜索结果汇总。
- `ExploreCoordinator`：发现页入口解析、分类切换和分类结果解析。
- `WebBookService`：书籍详情、章节目录和正文加载。
- `ReadBookEngine`：阅读状态、目录缓存、正文加载和阅读页协作。
- `AnalyzeUrl`：Legado URL、请求方法、请求头和请求体解析。
- `AnalyzeRule`：JSONPath、CSS、链式规则、正则和基础 XPath 解析。
- `JsRuntime` / `JsEngine`：书源规则中 JavaScript 能力的基础运行支持。
- `AppDatabase`：书源、书籍、章节、搜索历史等本地存储。

## 已知限制

- 尚未完整模拟 Android 版 Legado 的 JavaScript、Cookie、WebView 和动态页面环境。
- 需要人机验证、浏览器指纹、复杂加密或强反爬的站点可能无法直接访问。
- 部分书源的编码、分页正文、多段正文和特殊 XPath 写法仍需按实际站点继续补齐。
- Reader Kit 深度能力仍在接入和验证中，当前阅读体验以自研 ArkUI 阅读页为主。
- UI 仍在快速迭代，部分视觉和交互会继续调整。

## 免责声明

本项目仅用于阅读应用能力学习、技术验证和开源交流。项目不内置受版权保护的小说内容，也不对第三方书源内容负责。使用第三方书源时请遵守当地法律法规和对应网站协议。

## 致谢

感谢 Legado / 阅读项目及其社区书源生态。本项目的书源规则兼容目标来自该生态，相关实现仍在持续补齐中。

## 许可证

本项目使用 GPL-3.0 许可证，详见 [LICENSE](LICENSE)。
