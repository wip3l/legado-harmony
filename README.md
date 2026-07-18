# 开源轻页

开源轻页是一个面向 HarmonyOS NEXT 的本地阅读应用实验项目，使用 ArkTS / ArkUI 开发，目标是在移动端提供书架、搜索、发现、书源管理、阅读排版、朗读和个性化设置等完整阅读器体验。

当前版本：`2.6.709`。项目包名为 `io.legado.read`，支持 phone 和 tablet，当前以用户自行导入、且具备合法使用权限的书源规则为数据入口。

## 合规说明

- 本项目不内置、不托管、不分发任何小说正文、章节内容、封面图片、付费资源或书源订阅。
- 本项目不推荐、维护或背书任何第三方内容站点。
- 用户导入书源前，应自行确认书源来源、目标站点协议、内容授权和所在地法律法规要求。
- 本项目仅按用户配置的规则发起访问和解析，不以破解付费内容、绕过登录、绕过访问控制、规避反爬机制或批量抓取受保护内容为目标。
- 根目录中的 `debug_source.json` 仅用于本地规则兼容调试，使用或替换前请确认来源和目标站点授权。

## 功能概览

### 书架

- 管理已加入书籍，支持继续阅读、删除书籍和本地状态刷新。
- 支持最近阅读记录，并接入桌面快捷项和桌面服务卡片。
- 书架展示配置可按偏好调整。

### 搜索

- 基于已启用书源进行并发搜索，解析书名、作者、分类、封面、简介和详情地址。
- 支持搜索进度展示、结果封面显示、标签显示、搜索后返回书架提示等设置。
- 支持精准搜索，并可配置精准搜索时是否同时匹配作者。
- 支持书源分组筛选，搜索设置与发现设置集中在搜索/发现配置页。
- 对异常书源结果做了容错处理，包括空地址过滤、模板残留清理、回调隔离和部分 `result + ...` 拼接地址修复。
- 搜索链路会识别需要网页验证或登录 Cookie 的响应，并引导到内置验证页完成 Cookie 同步。

### 发现

- 读取书源中的发现入口，按站点、分类和榜单浏览内容。
- 发现页顶部使用书源下拉框与刷新按钮，书源切换与当前发现内容联动。
- 支持启用/禁用发现书源，并可对启用发现的书源进行拖动排序。
- 发现页书源下拉顺序与发现设置中的书源排序保持一致。

### 书源管理

- 支持从 URL、剪贴板或本地文本文件导入 JSON 书源。
- 支持选择模式下批量删除、启用发现、禁用发现。
- 支持书源编辑、保存、返回时未保存变更提示。
- 支持登录检测 JS、验证页、Cookie 同步和书源调试，便于排查搜索、发现、详情、目录和正文规则。
- 针对部分特殊 `dataUrl`、编码地址、聚合源登录地址和跨域 Cookie 做了兼容处理。

### 阅读

- 支持书籍详情解析、章节目录解析、正文解析和本地章节缓存。
- 支持字号、行距、段落间距、页面边距、背景、深色模式、点击翻页和翻页方式设置。
- 支持阅读过程中的章节预缓存，默认开启并预缓存下一章，可自定义预缓存章节数或关闭。
- 阅读设置中的排版滑块、朗读倍速滑块、目录选中态等强调色与全局强调色联动。
- 支持自定义字体、封面图库和沉浸式阅读布局。

### 朗读

- 接入系统 TTS 朗读能力，支持语速、后台朗读和阅读页内控制。
- 支持自定义 HTTP TTS 音源，可导入原版 `HttpTTS` JSON，配置请求 URL、请求头、Content-Type、并发数、登录地址、登录检查 JS、脚本库和 Cookie jar。
- 自定义音源支持列表管理、搜索过滤、批量选择、URL 导入和手动编辑。
- 自定义 HTTP TTS 通过 PCM 音频播放、预取和播放状态保护提升连续朗读稳定性。

### 个性化

- 支持浅色/深色模式。
- 支持经典蓝、暖纸、林雾、水墨、霓虹等主题包，统一 App 字体、语义色、阅读背景、正则气泡、圆角与悬浮底栏图标。
- 支持按钮色、强调色的主题级默认值与用户微调。
- 正则字体支持跟随主题、文字强调、高亮色块，以及 QQ 柔和、QQ 实色、胶囊、纸笺、霓虹等强调气泡。
- 支持自定义字体、阅读字体、封面图库和应用图标设置。
- 主要页面和设置项会跟随全局按钮色与强调色更新。

主题扩展方式、字段优先级和资源规范见 [主题开发指南](docs/theme-development.md)。

书源 JSON 结构、请求格式、解析语法、字段兼容性和调试流程见 [书源开发文档](docs/book-source-development.md)。

## 架构概览

项目主体位于 `entry` 模块，核心代码在 `entry/src/main/ets` 下。

```text
entry/src/main/ets
├── components/              # 通用 ArkUI 组件
├── core/
│   ├── book/                # 搜索、发现、详情、目录、正文和阅读协调逻辑
│   ├── http/                # HTTP 请求、Cookie、网页验证和登录态同步
│   └── rule/                # URL、JSONPath、CSS、XPath、正则和 JS 规则解析
├── entryability/            # 应用入口 Ability
├── model/                   # 数据模型、本地数据库、书源和书籍实体
├── pages/                   # 主页面、设置页、书源管理页、阅读页、验证页等
├── theme/                   # 主题模型、注册表、资源映射和运行时令牌
└── utils/                   # 设置存储、主题、TTS、音频播放、缓存和工具函数
```

核心模块：

- `SearchCoordinator`：书源并发搜索、搜索进度、结果汇总、结果清洗和网页验证触发。
- `ExploreCoordinator`：发现入口解析、分类切换和发现结果解析。
- `WebBookService`：书籍详情、章节目录、正文加载、章节缓存和验证响应识别。
- `ReadBookEngine`：阅读状态、目录缓存、正文加载和阅读页协作。
- `AnalyzeUrl`：URL 模板、请求方法、请求头、请求体、Cookie 注入和编码规则解析。
- `AnalyzeRule`：JSONPath、CSS、链式规则、XPath、正则替换、`<js>` 规则和主机函数兼容。
- `JsRuntime` / `JsEngine` / `ScriptEngine`：书源规则 JavaScript 的 ArkTS 兼容运行层和专用兜底实现。
- `CookieStore` / `VerificationSupport`：Cookie 持久化、WebView Cookie 同步、登录页跳转和验证状态管理。
- `BookSourceDataUrlSupport` / `EncodedSourceUrl`：特殊书源地址、编码地址和聚合源兼容。
- `SystemTtsReader` / `HttpTtsReader` / `TtsPcmAudioPlayer`：系统 TTS、自定义 HTTP TTS、PCM 播放和预取。
- `AppDatabase`：书源、书籍、章节、搜索历史和本地设置存储。

## 当前兼容能力

当前重点适配了以下书源规则能力：

- HTTP GET / POST、请求头、请求体、URL 模板、Cookie 注入和 `Set-Cookie` 保存。
- JSONPath 常见写法，例如 `$.data`、`$.result.books[*]`、`{{$.book_id}}`。
- CSS 选择器常见写法，例如 `.book-item`、`#list a`、`a.0@href`。
- 旧式链式规则，例如 `class.xxx.0@tag.li`、`id.xxx.0@tag.a`。
- 属性提取，例如 `a[data-bid]@data-bid`、`@href`、`@text`。
- 基础 XPath、规则分段、数组返回、正文/目录分页和生成式目录列表的部分兼容。
- 规则后处理，例如 `##regex##replacement`。
- 正则捕获组，例如 `$1`、`$2`、`$3`。
- `<js>` 混合执行：优先保留现有规则解析和主机能力，复杂表达式交给脚本兼容层处理。
- 常见 `java.xxx` 主机函数，包括 base64、hex、MD5、SHA、URL 编解码、AES/DES、Cookie 读取、字符串提取和列表提取。
- `java.ajax`、登录 Cookie、浏览器验证、验证码/验证页跳转和跨地址 Cookie 同步的部分兼容。
- 搜索、发现、详情、目录、正文链路的调试日志和离线规则验证基础。


## 开发环境

- DevEco Studio
- HarmonyOS SDK `6.1.0(23)`
- ArkTS / ArkUI
- hvigor

应用配置：

- 应用模块：`entry`
- 入口 Ability：`EntryAbility`
- 应用版本：`2.6.707`
- `versionCode` / `buildVersion`：`260707`
- `minAPIVersion`：`12`
- `targetAPIVersion`：`23`
- 支持设备：`phone`、`tablet`
- 权限：`ohos.permission.INTERNET`、`ohos.permission.KEEP_BACKGROUND_RUNNING`
- 开源协议：`GPL-3.0`

## 构建

推荐使用 DevEco Studio 打开项目后构建和安装。

命令行构建默认 APP：

```powershell
$env:DEVECO_SDK_HOME = "C:\Program Files\Huawei\DevEco Studio\sdk"
& "C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat" assembleApp --no-daemon
```

命令行构建调试 HAP：

```powershell
$env:DEVECO_SDK_HOME = "C:\Program Files\Huawei\DevEco Studio\sdk"
& "C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat" --mode module -p module=entry@default -p product=default assembleHap --no-daemon
```

命令行构建 release APP：

```powershell
$env:DEVECO_SDK_HOME = "C:\Program Files\Huawei\DevEco Studio\sdk"
& "C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat" --mode project -p product=release assembleApp --no-daemon
```

`DEVECO_SDK_HOME` 应指向 DevEco SDK 根目录，例如 `...\DevEco Studio\sdk`。release 打包依赖 `build-profile.json5` 中的签名配置。若本地签名证书、Profile 或 keystore 路径不同，请先更新对应配置。

## 使用流程

1. 安装应用后进入「我的」。
2. 打开「书源管理」，导入自有或已获授权的 JSON 书源。
3. 根据需要启用搜索、启用发现、编辑书源或验证书源。
4. 遇到需要登录或验证的书源时，按提示进入验证页完成登录和 Cookie 同步。
5. 返回首页后使用「搜索」查找书籍，或在「发现」中浏览已启用发现的书源。
6. 进入书籍详情，加入书架或直接阅读。
7. 在阅读页呼出菜单，进入阅读设置调整排版、朗读、预缓存和主题。
8. 需要自定义朗读时，在朗读设置中进入自定义音源管理，导入或编辑 `HttpTTS` 音源。

## 调试日志

项目在关键链路中输出了调试日志，便于定位书源兼容问题：

- `[SC]`：搜索请求、响应、列表命中、结果清洗和首条结果。
- `[ExploreCoordinator]`：发现站点、分类、请求响应和列表命中。
- `[WS]`：书籍详情、目录、正文请求和验证响应识别。
- `[RE]`：阅读引擎打开书籍、刷新目录和加载章节。
- `[TTS]` / `[HttpTtsReader]`：朗读音源、HTTP TTS 请求、音频预取和播放状态。

建议按以下顺序排查书源：

1. 搜索是否有结果。
2. 搜索结果的详情地址是否有效。
3. 详情页是否能解析书籍信息。
4. 目录是否能解析章节列表。
5. 正文是否能读取章节内容。
6. 发现页是否能拿到站点、分类和分类下内容。
7. 如遇验证页，先完成登录或验证码，再重试链路。

## 已知限制

- JS、Cookie、网页验证和 `java.xxx` 已有兼容层，但仍不是完整 Android Java/WebView 环境。
- 需要浏览器指纹、复杂动态渲染、强反爬、付费权限或私有登录流程的站点不保证支持。
- 部分书源的编码、分页正文、多段正文、特殊 XPath、复杂 `<js>` 和站点私有加密仍需按真实书源继续补齐。
- 自定义 HTTP TTS 依赖音源服务接口、授权方式、Cookie 和返回音频格式，不能保证所有第三方音源可用。
- Reader Kit 深度能力仍在接入和验证中，当前阅读体验以自研 ArkUI 阅读页为主。
- UI 和设置项仍在快速迭代，部分视觉和交互会继续调整。

## 免责声明

本项目仅用于阅读器能力学习、技术验证和开源交流。项目不内置受版权保护的小说内容，不提供内容分发、内容推荐、书源订阅或资源代取服务，也不对用户自行导入的第三方规则及其访问结果负责。使用本项目时，请遵守当地法律法规、目标网站协议和内容权利人的授权要求。

## 许可证

本项目使用 GPL-3.0 许可证，详见 [LICENSE](LICENSE)。
