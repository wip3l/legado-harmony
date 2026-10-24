# AI 子模块

仓库：[wip3l/harmony-book-ai-engine](https://github.com/wip3l/harmony-book-ai-engine)。
目录：`harmony-book-ai-engine/`，HarmonyOS HAR 包：`@legado/aiengine`。

着色、OCR、繁简字典、超分、彩色阅读调度、模型和相关测试已经移入子库。主项目保留阅读界面、会员规则、图片下载与缓存预算，`entry/src/main/ets/utils/AppAiHost.ets` 将这些能力注入 AI 库。

主程序在 `EntryAbility.onCreate` 安装宿主。`entry/src/main/ets/workers/ComicColorWorker.ets` 只启动子库 Worker；保留此入口以便 HarmonyOS 正确打包 Worker，其路径注册在 entry 构建配置中。HAR 原始资源自动合并，开源许可页仍可通过原 rawfile 路径读取许可证。

当前着色链路为 **本地解码 → NNRT 加速／CPU 回退 → C++ 像素合成 → JPEG → 宿主缓存**。AI 子库包含动态 CPU 模型、横竖两个固定尺寸 NPU 模型和 `libcomic_pixels.so` 原生绑定；模型原始体积合计约 176.25 MiB。原生构建包含 arm64-v8a 与 x86_64，宿主执行 `ohpm install --all` 后随 HAR 打包，无需复制 `.so` 或模型。

2026-10-24 已在麒麟 9030 Pro 上验证 NPU：测试页连续着色约 2.1～2.2 秒，首次加载与 CPU 对照约 8.6～8.7 秒。其他设备按 NNRT 能力和实际校验选择后端；`backend=nnrt` 不代表整条流程全部在 NPU 执行。详细测量范围和兼容条件见 [漫画着色](comic-colorizer.md)。

边界检查允许的依赖只有子库自身的原生合成绑定，仍禁止反向导入主应用和书源内核。CI 必须运行完整 `npm test`，包含模块边界与原生依赖声明检查。若 AI 子库为私有仓库，主仓库 CI 还需配置有权读取它的只读凭据；缺少凭据会在检出子模块阶段失败。

共用的 `TextTranslator` 提供小说和漫画文本繁→简入口，并预留 `TextTranslationProvider`。本次不增加小说阅读页面的翻译开关，不实现尚未提供的日韩翻译模型；原漫画功能与入口保持不变。

后续所有新增 AI 实现优先在子库开发，UI 和业务策略在主项目开发。先推送子库提交，再提交主项目 gitlink；构建和发布禁止指向仅存在于本机的子库提交。具体 API、独立构建、测试和开发流程见 [子库 README](../harmony-book-ai-engine/README.md)。

```sh
git submodule update --init --recursive
ohpm install --all
npm --prefix harmony-book-ai-engine test
node --experimental-strip-types scripts/comic-colorizer-check.mjs
node --experimental-strip-types scripts/comic-text-check.mjs
node --experimental-strip-types scripts/member-reader-settings-check.mjs
hvigorw --mode module -p module=entry@default -p product=default assembleHap --no-daemon
```
