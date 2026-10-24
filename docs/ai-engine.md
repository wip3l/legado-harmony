# AI 子模块

仓库：[wip3l/harmony-book-ai-engine](https://github.com/wip3l/harmony-book-ai-engine)。
目录：`harmony-book-ai-engine/`，HarmonyOS HAR 包：`@legado/aiengine`。

着色、OCR、繁简字典、超分、彩色阅读调度、模型和相关测试已经移入子库。主项目保留阅读界面、会员规则、图片下载与缓存预算，`entry/src/main/ets/utils/AppAiHost.ets` 将这些能力注入 AI 库。

主程序在 `EntryAbility.onCreate` 安装宿主。`entry/src/main/ets/workers/ComicColorWorker.ets` 只启动子库 Worker；保留此入口以便 HarmonyOS 正确打包 Worker，其路径注册在 entry 构建配置中。HAR 原始资源自动合并，开源许可页仍可通过原 rawfile 路径读取许可证。

上线前 AI 试用由主应用 `account/AiAccessPolicy.ets` 管理，`AppAiHost.isAllowed` 统一接入：北京时间 **2026-11-01 00:00 前**，登录用户可免费使用 AI 超分、AI 着色和 AI 翻译（目前仅繁→简）；未登录用户引导登录。截止时刻起恢复有效会员校验，不修改账号会员身份、服务端权益或设备能力限制。阅读页、单页着色与繁简预览监听账号和活动状态，退出登录或到期时撤销试用，保留阅读开关设置。

试用时间优先复用账号快照的 `membership.serverNow`，没有校准值时使用设备时间；进程内用包含休眠时间的单调时钟推进。前台截止定时器和返回前台检查刷新界面，已确认的活动结束状态在本机持久保存。该方案不增加服务端接口，也不提供防篡改保证：清除应用数据或修改客户端仍可能绕过本地策略。用户需更新到包含此策略的版本，活动到期无需再发布版本。

当前着色链路为 **本地解码 → NNRT 加速／CPU 回退 → C++ 像素合成 → JPEG → 宿主缓存**。AI 子库包含动态 CPU 模型、横竖两个固定尺寸 NPU 模型和 `libcomic_pixels.so` 原生绑定；模型原始体积合计约 176.25 MiB。原生构建包含 arm64-v8a 与 x86_64，宿主执行 `ohpm install --all` 后随 HAR 打包，无需复制 `.so` 或模型。

2026-10-24 已在麒麟 9030 Pro 上验证 NPU：测试页连续着色约 2.1～2.2 秒，首次加载与 CPU 对照约 8.6～8.7 秒。其他设备按 NNRT 能力和实际校验选择后端；`backend=nnrt` 不代表整条流程全部在 NPU 执行。详细测量范围和兼容条件见 [漫画着色](comic-colorizer.md)。

边界检查允许的依赖只有子库自身的原生合成绑定，仍禁止反向导入主应用和书源内核。CI 必须运行完整 `npm test`，包含模块边界与原生依赖声明检查。若 AI 子库为私有仓库，主仓库 CI 还需配置有权读取它的只读凭据；缺少凭据会在检出子模块阶段失败。

主仓库的 `quality` 工作流使用 Actions Secret `AI_ENGINE_READ_TOKEN` 检出主库和子模块。可创建 fine-grained PAT，仓库范围选择 `qingye-reader`、`harmony-book-ai-engine` 和 `harmony-book-source-engine`，仅授予 `Contents: Read-only`，再将其保存到主仓库的 Settings → Secrets and variables → Actions。检出完成后不保留 Git 凭据。未配置时回退到默认 `github.token`，该令牌无法读取其他私有仓库；来自 fork 的 PR 不会获得此 Secret，仍无法检出私有 AI 子库。不要通过 `pull_request_target` 向不可信 PR 暴露凭据。

共用的 `TextTranslator` 提供小说和漫画文本繁→简入口，并预留 `TextTranslationProvider`。本次不增加小说阅读页面的翻译开关，不实现尚未提供的日韩翻译模型；原漫画功能与入口保持不变。

后续所有新增 AI 实现优先在子库开发，UI 和业务策略在主项目开发。先推送子库提交，再提交主项目 gitlink；构建和发布禁止指向仅存在于本机的子库提交。具体 API、独立构建、测试和开发流程见 [子库 README](../harmony-book-ai-engine/README.md)。

```sh
git submodule update --init --recursive
ohpm install --all
npm --prefix harmony-book-ai-engine test
node --experimental-strip-types scripts/comic-colorizer-check.mjs
node --experimental-strip-types scripts/comic-text-check.mjs
node --experimental-strip-types scripts/member-reader-settings-check.mjs
node --experimental-strip-types scripts/ai-trial-check.mjs
hvigorw --mode module -p module=entry@default -p product=default assembleHap --no-daemon
```
