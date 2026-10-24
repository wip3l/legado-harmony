# 本地漫画着色

AI 实现、模型、转换工具与维护文档已迁移到独立子模块：

- [模型、处理流程、复现与真机诊断](../harmony-book-ai-engine/docs/comic-colorizer.md)
- [AI 能力库接入和开发约定](../harmony-book-ai-engine/README.md)

## 当前状态（2026-10-24）

已在 Huawei Pura X Max／麒麟 9030 Pro（16+512、API 26）验证本机 NPU 执行。系统通过 NNRT 开放的加速设备、页面尺寸、输出质量和速度检查均满足时自动启用；不满足时回退 MindSpore Lite CPU。部分算子仍可能由 CPU 执行，其他机型尚未完成真机验证。

连续页复用 NPU 模型，并使用 C++ 合成线稿与颜色。1350×1920 原页及旋转横页的 Worker 完整着色实测分别为 **2.103 秒、2.241 秒**；CPU 回退分别为 **5.012 秒、5.059 秒**。首次加载和 CPU 对照校验约 8.6～8.7 秒。上述计时包含解码、推理、合成和 JPEG 编码，不含下载、模型资源解包、队列等待及缓存写入，也不代表所有漫画页的固定耗时。

三份模型原始体积合计约 176.25 MiB，随应用打包后解包到私有目录；图片不上传到着色服务。输出长边最多 2048，JPEG 质量 95。尺寸范围、运行流程、日志说明、历史问题和复现方法统一维护在 [子库着色文档](../harmony-book-ai-engine/docs/comic-colorizer.md)。

## 宿主边界与检查

主应用保留页面、会员策略、`AppAiHost` 适配器、Worker 启动入口和设备测试。NPU 选择、CPU 回退、模型与原生合成在 AI 子库内实现。完整检查执行 `npm --prefix harmony-book-ai-engine test`；主应用的 `scripts/comic-colorizer-check.mjs` 另外覆盖页面菜单集成。Node 检查不替代 NPU 和 C++ 真机验证。
