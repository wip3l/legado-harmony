# AI 子模块

仓库：[wip3l/harmony-book-ai-engine](https://github.com/wip3l/harmony-book-ai-engine)。
目录：`harmony-book-ai-engine/`，HarmonyOS HAR 包：`@legado/aiengine`。

着色、OCR、繁简字典、超分、彩色阅读调度、模型和相关测试已经移入子库。主项目保留阅读界面、会员规则、图片下载与缓存预算，`entry/src/main/ets/utils/AppAiHost.ets` 将这些能力注入 AI 库。

主程序在 `EntryAbility.onCreate` 安装宿主。`entry/src/main/ets/workers/ComicColorWorker.ets` 只启动子库 Worker；保留此入口以便 HarmonyOS 正确打包 Worker，其路径注册在 entry 构建配置中。HAR 原始资源自动合并，开源许可页仍可通过原 rawfile 路径读取许可证。

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
