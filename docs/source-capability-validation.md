# 书源能力改进验证记录

对应 [实施计划](source-capability-implementation-plan.md)，2026-10-24。覆盖工作区实现，不表示旧安装包已具有新能力。没有进行站点速度或鸿蒙真机验收，不采用外部建议中的加速倍数作为结果。

最终结果：下列 15 个检查脚本通过；原生规则 250 项、JS 函数库 34 项、脚本阶段 106 项。最后一次功能修改后完整 HAP 构建通过（57 个任务），两个仓库的 `git diff --check` 通过。构建仍有工程既有的弃用 API 和异常处理等警告。

## 验证范围

| 要求 | 实现及验证证据 |
|---|---|
| HTTP/1.1 设置恢复、可控协议降级、错误分类 | NetworkSettingsStore、HttpProtocolPolicy、NetworkErrorText；设置恢复／写入失败／竞态及真实 HttpClient 逻辑的模拟 SDK 回归 |
| 最终地址与明确超时 | HttpFinalUrlObserver、AnalyzeUrl、NativeScriptHost、WebBookFetchRuntime；自动／手动跳转、API 不支持时为空、文本／二进制／网页及限流等待的超时回归 |
| 图片 4/8/12 并发与前台保留名额 | ReaderImageScheduler；后台先到、前台提权、可见图片优先、取消、运行中调高／调低上限测试 |
| 批量请求配置 | 工作线程执行真实脚本宿主：并发、滑动补位、按原顺序返回、逐项 timeout、无效配置、请求预算和取消 |
| 原生内联评论页 | NativeSourceSpec、NativeSourceRunner、NativeSourceService；page/chapterPage、按点击取数、暖缓存／冷重建／过期、书源／变量／账号／书籍／章节及段落身份检查、HTTP URL 回退 |
| 大小与时间预算 | UTF-8 HTML 256 KiB、data 64 KiB、上下文 2 MiB；真实 NativeHost 的 8 次请求／响应总量 2 MiB／剩余 deadline 传递测试；生成与渲染各 15 秒计时器 |
| 安全注入与页面隔离 | NativeCommentPage 安全序列化及不授予同源权限的沙箱 iframe；Chromium/Edge 实际加载生成 HTML，验证 CSP 拦截外部资源、无外部请求、站点 Cookie／存储不可见、恶意 script 闭合文本不执行、本地按钮正常；验证无法借父窗口或空白子窗口的 WebRTC 接口绕过禁用 |
| 阅读器交互 | 执行阅读器实际方法，验证关闭取消、并发点击的旧结果被丢弃、换章关闭等待面板、失败提示和备用 URL；实际组件方法验证无 page-end 回调时仍轮询就绪、超时和销毁清理；专用离线 Web 不注册脚本桥 |
| 调试预览和公开示例 | 调试页记录入口、按点击生成、HTML/data 大小和失败结果；共享隔离组件；离线示例通过导入校验、脚本执行、页面求值及 Chromium 预览 |
| 兼容与整体构建 | 原生规则／JS／脚本阶段、图片管线和旧评论面板回归；完整 assembleHap，含 ArkTS 编译与签名 |

## 可复现命令

在仓库根目录执行，Node 需要支持 TypeScript 类型剥离。浏览器测试需要已安装的 Playwright 与 Chromium 或 Edge，不会自动下载浏览器。

```powershell
node scripts/network-compatibility-check.mjs
node scripts/network-settings-check.mjs
node scripts/web-request-deadline-check.mjs
node scripts/reader-image-scheduler-check.mjs
node scripts/reader-image-results-check.mjs
node scripts/comic-image-pipeline-check.mjs
node scripts/reader-comment-panel-check.mjs
node scripts/native-comment-page-browser-check.mjs
node scripts/native-comment-page-service-check.mjs
node harmony-book-source-engine/scripts/native-source-check.mjs
node harmony-book-source-engine/scripts/native-js-check.mjs
node harmony-book-source-engine/scripts/native-script-check.mjs
node harmony-book-source-engine/scripts/native-comment-page-check.mjs
node harmony-book-source-engine/scripts/neutral-source-engine-check.mjs
$env:DEVECO_HOME='C:/Program Files/Huawei/DevEco Studio'
node harmony-book-source-engine/scripts/web-book-fetch-wait-check.cjs
git diff --check
git -C harmony-book-source-engine diff --check
```

构建使用工程配置的 SDK 和 JBR：

```powershell
foreach ($taskProxyName in @('HTTP_PROXY','HTTPS_PROXY','ALL_PROXY','http_proxy','https_proxy','all_proxy')) {
  [Environment]::SetEnvironmentVariable($taskProxyName,$null,'Process')
}
$env:JAVA_HOME='C:/Program Files/Huawei/DevEco Studio/jbr'
& 'C:/Program Files/Huawei/DevEco Studio/tools/hvigor/bin/hvigorw.bat' --mode module -p product=default -p module=entry@default assembleHap --no-daemon --no-incremental
```

本机生成资源中的只读属性会影响重复构建；仅对已核对位于 `entry/build/` 内的生成资源清除只读属性，不操作源资源。最终构建日志保存在 `.codex_tmp/source-capabilities-final-build.log`，回归输出在 `.codex_tmp/source-capabilities-regression.log`。浏览器预览截图在 `.codex_tmp/inline-comment-preview.png`，仅用于本地验证，不打入安装包。

## 平台边界与真机验收方法

Node 的网络 SDK、持久化和页面控制器是替身；浏览器安全测试运行的是桌面 Chromium/Edge。它们验证实现逻辑、生成文档及接线，不替代鸿蒙网络栈、ArkWeb、系统弹层或真实站点的端到端行为。

1. 导入 [离线示例](../harmony-book-source-engine/docs/examples/native-inline-comments.json)，搜索任意词，打开示例章节。两个气泡分别显示当前段落数据，章末显示总数 3，按钮可点击。
2. 书源调试运行全链路，逐个预览气泡与章末入口；检查标题、字节数、0.7 高度、拖动展开、关闭与重新打开。此示例无 HTTP 请求。
3. 给示例 page.fetch 加可控慢接口：等待时关闭、返回、切换章节和重新打开；迟到结果不得覆盖新页面。修改书源或登录变量后，旧入口提示刷新。
4. 在测试源中分别尝试 fetch、外链脚本／样式／图片、iframe、跳转、文件选择、定位和权限请求；通过设备网络日志确认无页面侧出站请求，不出现权限或文件选择界面。页面不得读取已登录远程评论页的 Cookie。
5. 让页面 HTML/data 超限、返回空串或请求失败，分别检查有备用 URL 和无备用 URL 的行为；不支持新字段的旧宿主仅使用真实 HTTP(S) URL 回退，page-only 不承诺可导入。
6. API 20/21 的 finalUrl 应为空，API 22+ 需对照实际跳转链验证；图片测速按 [专用步骤](image-concurrency-validation.md)跨站点测量首图、可见区域与整章耗时。

镜像候选列表、裁剪／模糊、取消后台配额以及永久协议降级未纳入本次实现，原因保留在实施计划中。
