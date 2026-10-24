# 本地漫画着色

AI 实现、模型、转换工具与维护文档已迁移到独立子模块：

- [模型、处理流程、复现与真机诊断](../harmony-book-ai-engine/docs/comic-colorizer.md)
- [AI 能力库接入和开发约定](../harmony-book-ai-engine/README.md)

主应用只保留页面、会员策略、`AppAiHost` 适配器和 Worker 启动入口。主应用的 `scripts/comic-colorizer-check.mjs` 同时执行子库回归与页面菜单集成检查。
