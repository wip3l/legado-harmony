# 第三方开源软件声明

本项目及其发行的 HAP 包含下列第三方开源软件。项目自身的 GPL-3.0 许可证不替代这些组件各自的许可证、版权声明或免责声明。

## ohos_quickjs

- 组件：`@devzeng/quickjs` / `ohos_quickjs`
- 上游项目：https://github.com/hhtczengjing/ohos_quickjs
- 许可证：MIT
- 版权所有：Copyright (c) 2026 zengjing

本项目对该组件进行了 HarmonyOS 集成、稳定性和能力扩展方面的修改。该组件随书源解析内核一起放在子模块 `harmony-book-source-engine/quickjs/`，原始 MIT 许可见 [harmony-book-source-engine/quickjs/LICENSE](harmony-book-source-engine/quickjs/LICENSE)，发行包内许可合集见 [THIRD_PARTY_LICENSES.txt](entry/src/main/resources/rawfile/licenses/THIRD_PARTY_LICENSES.txt)。

## QuickJS

- 组件：QuickJS JavaScript Engine
- 上游项目：https://bellard.org/quickjs/
- 许可证：MIT
- 版权所有：Copyright (c) 2017-2021 Fabrice Bellard；Copyright (c) 2017-2021 Charlie Gordon

## OpenHarmony / Huawei N-API 封装代码

- 组件：带有 Huawei Device Co., Ltd. 版权头的 N-API 封装源文件
- 许可证：Apache License 2.0
- 版权所有：Copyright (c) 2021-2022 Huawei Device Co., Ltd.

本项目修改过的相关文件继续保留原始版权和许可证头；修改内容主要包括 QuickJS 运行时适配、句柄安全、受限执行和 HarmonyOS 应用集成。

## OpenCC 繁简字典

- 上游：https://github.com/BYVoid/OpenCC/tree/ver.1.1.9
- 版本：ver.1.1.9；作者：BYVoid and OpenCC contributors
- 文件：TSCharacters.txt、TSPhrases.txt（未修改）
- 许可证：Apache-2.0
- 用途：漫画识别文本的繁→简转换，应用自行实现词组最长匹配适配器，不包含完整 OpenCC 引擎。
- 字典、来源校验及完整许可证见 `entry/src/main/resources/rawfile/opencc/`，随 HAP 分发，应用开源许可页面显示许可全文。

## 完整许可文本

为确保源码和二进制发行均携带必要声明，MIT 与 Apache-2.0 的完整许可文本统一存放于：

- [entry/src/main/resources/rawfile/licenses/THIRD_PARTY_LICENSES.txt](entry/src/main/resources/rawfile/licenses/THIRD_PARTY_LICENSES.txt)

该文件会作为 rawfile 打包进入最终 HAP，并可在应用“关于 → 开源许可”中查看。
