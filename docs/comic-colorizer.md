# 本地漫画着色

入口：漫画阅读器 → **画面设置 → AI着色**，开启后当前画面优先，按书记忆。翻页模式准备后两跨页；条漫沿滚动方向准备约两屏，队列最多 32 个候选，快速跳转会移除过时任务。使用原图布局叠加彩色层，拖动或惯性滚动时推迟切换。

画面设置提供 AI着色开关，关闭后恢复原图；会话层保留暂停、对比和重试能力，当前界面不提供这些入口。长按 **本页着色（会员）** 在漫画阅读器内只处理该张；其他场景仍保留可保存、分享结果的独立着色页。日／韩翻译不在这一版中。

ReaderComicColorSession 每次只提交一个任务，后台、换书、权限失效及离开候选范围时协作取消；不强杀原生推理。与超分共用 ReaderComicComputeQueue，防止模式切换时两个模型重叠占用内存。开启彩色期间暂停超分、保留超分开关，关闭后恢复。

与漫画超分采用同一有效会员规则，复用 AccountSessionStore.activeMembershipSku()；非会员显示开通入口，跳转现有账户中心。服务层在出队、读取缓存前及推理完成后校验权限，推理中失效使用安全取消；页面监听账号变更和有效期，失效后恢复原图并停止彩色导出。设备不支持时不显示开通引导。以下真机推理测试需要使用有效会员账户，不修改或伪造设备账户授权。

## 本次修正

- 将最初的 CycleGAN 384 方形输入换为上游默认的 AlacGAN。按原图比例处理，短边最多 512、长边最多 768，仅补到 32 的倍数，避免整页挤进低分辨率方框。
- 去掉强行保留原图亮度的合成方式：白色皮肤和衣服现在能获得颜色与阴影；恢复原图高频灰度细节、保持黑色墨线。
- 缩略图与输出分别创建 ImageSource，避免小尺寸解码状态影响后续完整图像。预览显式使用图片宽高比。
- JPEG 编码明确声明输入缓冲区为 RGBA。HarmonyOS 的 srcPixelFormat 默认 BGRA，仅设置输出 pixelFormat 会交换红蓝通道。
- 缓存版本升级为 alac-fp16-v4，旧结果不会被当作新版使用。

## 运行方式与边界

模型随 HAP 打包，61,596,264 字节（约 58.74 MiB），第一次使用解包到应用私有目录。MindSpore Lite CPU 4 线程、preferred_fp16 计算、FP16 权重存储，没有使用 NPU 或 GPU。模型与像素处理在短生命周期 Worker 内完成，任务全局串行。

复用阅读器的图片来源，支持本地文件和 data URI；仅在原图为 HTTP 地址时下载原图。图片不发送到着色服务器。输出长边最多 2048、不放大原图。单文件最多 30 MiB，不支持动图和超过 4:1 的长条图。颜色由模型推测，不能保证原作配色、跨页一致或自动保护每个文字气泡。

退出或取消后立即更新界面，等待底层当前调用安全结束再销毁 Worker；180 秒超时也采用协作取消。已取消任务不发布结果。缓存按原图 SHA-256 和处理版本区分，共用漫画缓存预算。

## 页底彩虹纹修复与性能（v4）

手机缓存和分阶段输出确认：异常在模型 RGB 输出中已存在，不是阅读器拼接或 JPEG 解码造成的。旧模型转换时指定了固定的 768×512 输入形状，再在手机端 resize，部分尺寸输出错误：512×736 的整图平均绝对误差约 0.137，底部更严重；512×704、横版 768×512 也不能依靠补齐到 64 的倍数解决。

重新转换时保留动态 H/W，省略 converter 的固定 inputShape。该模型输出实际为 NCHW，Worker 显式校验并转为 RGB 交错排列。CPU 使用 preferred_fp16，保留原有输入尺寸和 2048 输出上限。优化合成时复用低分辨率颜色差与相邻插值行，消除逐像素反复采样及 Math 调用；与原算法的通道差不超过 1/255。

用户设备、同一 1350×1920 页面诊断实测：旧链路总计约 12.8 秒（推理 5.43 秒、后处理 6.69 秒），新链路约 6 秒（模型加载 0.06 秒、推理 3.56 秒、后处理 2.31 秒）。这些是单页测试值，连续阅读还受温度、前台负载、图片读取和队列等待影响。新版动态模型 FP16 与 ONNX 参考的平均绝对误差：竖版约 0.01194、横版约 0.01542；底部均通过单独校验。新版模型的 FP32 路径也已复测：整页平均误差 0.000143、底部 0.000031，确认修复来自动态模型转换，FP16 则进一步提速。

缓存升级为 alac-fp16-v4，旧异常图片不会继续命中，重新阅读时自动生成新结果。不会修改原始漫画或原作页底内容。

## 模型与复现

来源：[BinitDOX/Manga-Colorizer](https://github.com/BinitDOX/Manga-Colorizer/tree/623f5a2a9dc3bb4fc0c8edbfa2d22de43f8f6ea7)，固定提交 623f5a2a9dc3bb4fc0c8edbfa2d22de43f8f6ea7。使用 Backend/networks/alac_gan.py 和 extractor.py，权重来自该项目 README 的 [Generator 下载](https://drive.google.com/file/d/1qmxUEKADkEM4iYLp1fpPLLKnfZ6tcF-t/view)。模型原始参数约 3214 万，导出仅保留主 RGB 输出，剪掉未使用的辅助解码分支。仓库 MIT 许可保存在模型目录并在应用开源许可页展示。

开发环境：Python 3.12、PyTorch 2.6.0 CPU、ONNX 1.17.0、ONNX Runtime 1.20.1、NumPy，以及 [MindSpore Lite 2.3.0 Windows 转换工具](https://ms-release.obs.cn-north-4.myhuaweicloud.com/2.3.0/MindSpore/lite/release/windows/mindspore-lite-2.3.0-win-x64.zip)。

把源码放在 tmp/comic-colorizer/networks/，权重保存为 tmp/comic-colorizer/generator.zip（它是 PyTorch 权重，不需要解压）：

```powershell
python scripts/comic-colorizer/export_model.py --upstream tmp/comic-colorizer --output tmp/comic-colorizer/export
# tools/converter/lib 加入当前进程 PATH 后：
converter_lite.exe --fmk=ONNX --modelFile=tmp/comic-colorizer/export/alac.onnx --outputFile=tmp/comic-colorizer/export/alac --inputDataFormat=NHWC --outputDataFormat=NHWC --fp16=on --saveType=MINDIR_LITE
# runtime/lib、runtime/third_party/glog 加入 PATH 后：
benchmark.exe --modelFile=tmp/comic-colorizer/export/alac.ms --inDataFile=tmp/comic-colorizer/export/alac_input.bin --inputShapes=1,768,512,5 --benchmarkDataFile=tmp/comic-colorizer/export/alac_expected.txt --accuracyThreshold=0.5 --numThreads=4
```

导出脚本校验源码和权重哈希。PyTorch／ONNX 最大绝对误差约 1.48e-6。新版动态模型在电脑端实际页输入的官方 benchmark 平均偏差约 0.278448%。模型尺寸在 Worker 内通过 model.resize 调整到当前页面所需的 32 倍数。转换命令中不得重新加入固定 inputShape；动态转换时 outputDataFormat 参数不会把输出改成 NHWC，校验文件及 Worker 必须按 NCHW 处理。

复制 alac.ms 到 entry/src/main/resources/rawfile/comic-colorizer/ 后清除 Windows 只读属性。更改模型需同步 model.json、服务中的长度／哈希、缓存版本及测试哈希。转换中间文件与漫画样例不随应用分发。

## 验证

可选的 `ComicColor#diagnoseEdges` 为仅测试包提供的分阶段诊断：把复现原图放入应用测试上下文 cache/comic-color-visual-fixture.jpg，输出 comic-edge-input.bin、comic-edge-output.bin 和 comic-edge-result.jpg。可用 cache/comic-edge-config.txt 指定模型宽、高、解码宽、高、线程数、precisionMode；可选 comic-edge-custom.ms 用于对照转换版本。这些入口不包含在发布包中，也不修改账户授权。

把诊断文件取回后运行 `scripts/comic-colorizer/check_device_output.py --onnx <导出的ONNX> --input <输入bin> --output <输出bin> --width <模型宽> --height <模型高>`；整页与最后 20% 行分别要求平均绝对误差不超过 0.03，避免只检查四角漏掉底部色带。

```powershell
node --experimental-strip-types scripts/comic-colorizer-check.mjs
node --experimental-strip-types scripts/comic-color-reading-check.mjs
node --experimental-strip-types scripts/comic-text-check.mjs
node --experimental-strip-types scripts/comic-image-pipeline-check.mjs
hvigorw --mode module -p module=entry@default -p product=default assembleHap --no-daemon
hvigorw --mode module -p module=entry@ohosTest -p product=default assembleHap --no-daemon
# 安装主 HAP 与 ohosTest HAP 后：
hdc shell aa test -b io.legado.read -m entry_test -s unittest OpenHarmonyTestRunner -s timeout 180000 -w 180
```

设备测试生成 1350×1920 JPEG，覆盖完整尺寸、四角黑框不缩入白画布、缓存、本地文件／data URI 一致、取消及队列恢复。另经实际 JPEG 编解码检查红绿蓝通道。可将开发者明确提供的测试图放入应用 base/cache/comic-color-visual-fixture.jpg，测试会输出同目录 comic-color-visual-result.jpg；不会扫描用户书籍。

在连接设备 HOP-AL10 / API 26 上，最终版本 1350×1920 测试图总耗时 12,733 ms，模型 6,098 ms，中途取消后的恢复 13,824 ms。上游 bw2.jpg 真机样例 9,843 ms，其中模型 6,318 ms；已取回实际 JPEG 检查肤色、衣服、墨线和整页范围。红蓝通道编解码、四角完整性、缓存和取消恢复均通过。性能数据仅代表这些样例，不保证任意页面或持续运行速度；连续运行温升与内存峰值仍未完成系统测量。
