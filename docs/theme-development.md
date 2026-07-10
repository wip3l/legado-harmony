# 主题开发指南

开源轻页的主题由编译期 `ThemePack`、运行时 `ThemeRuntime` 和持久化兼容层组成。主题选择只保存稳定的 `themeId` 与用户对强调色/按钮色的覆盖值；`Resource`、背景图片和图标由资源注册表解析，不进入 Preferences。

## 目录与职责

```text
entry/src/main/ets/theme/
├── ThemeModels.ets             # 主题包、浅深变体和设计令牌模型
├── BuiltinThemeRegistry.ets    # 内置主题与编译期主题注册入口
├── ThemeRuntime.ets            # 将主题发布为扁平 AppStorage 令牌
└── ThemeAssetRegistry.ets      # assetId / iconPackId 到 Resource 的映射

entry/src/main/resources/base/media/
├── reader_bg_*                 # 阅读背景 SVG
├── ic_theme_rounded_*          # 圆润导航图标包
└── ic_theme_ink_*              # 水墨导航图标包
```

`AppThemeSettingsStore` 是兼容桥：它继续读写原来的浅/深强调色与按钮色，同时保存 `appThemeId`，因此旧版本用户的自定义颜色不会在升级时丢失。

## ThemePack 内容

每个主题包含浅色和深色两个 `ThemeVariant`：

- App 颜色：页面、卡片、输入区、主/次文字、分割线、强调色、按钮色、危险色。
- 阅读外观：纯色回退、背景资源 ID、正文/辅助文字色、内容明暗。
- 正则强调：默认强调模式、气泡预设、强调色、气泡文字色。
- 排版：App 默认字体族。用户选择的自定义字体优先级更高。
- 导航：悬浮底栏图标包 ID。
- 形状：小/中/大圆角、卡片、按钮与气泡圆角。

有效值优先级为：

```text
正则规则级设置 > 用户颜色/字体覆盖 > 当前主题浅深变体 > 经典蓝回退
```

阅读页保留原有米黄、素白、青绿和自定义配色，并新增稳定索引 `APP_THEME_INDEX`。只有选择“应用主题”时，主题背景图与阅读文字色才生效。

## 新增编译期主题

ArkTS 严格模式下建议使用类实例赋值，不要依赖无类型对象字面量。可以在独立文件中创建 `ThemePack`，再在应用初始化前注册：

```ts
import { BuiltinThemeRegistry } from './BuiltinThemeRegistry';
import { ThemePack, ThemeVariant } from './ThemeModels';

const theme = new ThemePack();
theme.id = 'my-theme';
theme.name = '我的主题';
theme.description = '主题说明';
theme.typography.appFontFamily = 'sans-serif';
theme.navigation.iconPackId = 'rounded';

const light = new ThemeVariant();
light.colors.pageColor = '#F5F5F5';
light.colors.cardColor = '#FFFFFF';
light.colors.inputColor = '#F0F2F5';
light.colors.primaryTextColor = '#1F1F1F';
light.colors.subTextColor = '#777777';
light.colors.dividerColor = '#E0E0E0';
light.colors.accentColor = '#4C7DFF';
light.colors.buttonColor = '#3D6FE8';
light.colors.dangerColor = '#D94C4C';
light.reader.backgroundColor = '#F8F3E8';
light.reader.textColor = '#302A22';
light.reader.subTextColor = '#756B5E';
light.reader.contentTone = 'light';
light.regexEmphasis.emphasisMode = 'bubble';
light.regexEmphasis.bubbleStyle = 'qq-soft';
light.regexEmphasis.emphasisColor = '#DCE7FF';
light.regexEmphasis.emphasisTextColor = '#243B6B';
theme.light = light;

// 深色变体必须单独配置；不要直接复用 light 引用。
const dark = new ThemeVariant();
// ...填写 dark.colors / dark.reader / dark.regexEmphasis
theme.dark = dark;

BuiltinThemeRegistry.register(theme);
```

主题 ID 必须稳定且唯一。注册相同 ID 会替换已注册定义，便于模块化主题包覆盖默认值。

## 阅读背景资源

背景建议使用无外链、无脚本、无滤镜的本地 SVG，基准尺寸为 `1080 × 1920`。图案应保持低对比，正文区域不要放置密集细节。

1. 将浅/深资源放入 `entry/src/main/resources/base/media/`。
2. 在 `ThemeAssetRegistry.readerBackground()` 中增加稳定 `assetId` 映射。
3. 分别填写 `theme.light.reader.backgroundAssetId` 与 `theme.dark.reader.backgroundAssetId`。
4. 即使有图片，也必须提供 `backgroundColor` 作为加载、翻页和系统窗口回退色。
5. 正确填写 `contentTone`，阅读页据此决定系统栏图标和辅助内容明暗。

## 悬浮底栏图标包

图标包固定包含 `bookshelf`、`explore`、`search`、`mine` 四个 24×24 单色 SVG。路径使用纯黑填充，由 ArkUI 的 `fillColor` 注入主题色。

新增图标包后，在 `ThemeAssetRegistry.navigationIcon()` 增加映射，并把 `ThemePack.navigation.iconPackId` 指向新 ID。桌面 App 图标使用 HarmonyOS 动态图标能力，是独立的用户选择；主题切换不会静默修改桌面图标。

## 正则气泡

规则 schema v2 支持：

- `emphasisMode`：`inherit`、`none`、`text`、`highlight`、`bubble`。
- `bubbleStyleId`：`inherit`、`qq-soft`、`qq-solid`、`capsule`、`paper`、`neon`。
- `emphasisColor`：留空时跟随主题，设置后作为规则级覆盖。

旧的 `highlightColorEnabled` 与 `shadowColor` 仍会读取和输出，用于升级兼容。气泡使用行内 `Span.textBackgroundStyle` 和 `textShadow`，不会改变正文源文本或 TTS 索引；TTS 当前朗读高亮拥有最高显示优先级。

## 验证清单

- 浅色、深色、跟随系统三种模式均检查一次。
- 冷启动后主题 ID、颜色覆盖和自定义字体保持不变。
- 图片背景下检查当前页、进入页与横向翻页动画。
- 在旧正则 JSON、schema v2、非法正则、零长度正则下检查阅读页。
- 同时开启正则气泡与 TTS，确认 TTS 高亮覆盖气泡。
- API 23 的悬浮 HdsTabs 与兼容 Tabs 都检查四个图标。
- 运行调试 HAP 构建：

```powershell
$env:DEVECO_SDK_HOME = 'C:\Program Files\Huawei\DevEco Studio\sdk'
& 'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat' --mode module -p module=entry@default -p product=default assembleHap --no-daemon
```
