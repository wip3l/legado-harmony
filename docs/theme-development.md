# 主题开发指南

本文面向为开源轻页新增或修改主题的开发者，说明主题模块的代码结构、`ThemePack` 字段、资源规范和新增主题的步骤。

主题由三层组成：

- **编译期主题包** `ThemePack`：一个主题的全部设计令牌，在 `BuiltinThemeRegistry` 中注册。
- **运行时** `ThemeRuntime`：把当前主题展开为扁平的 `AppStorage` 令牌，供组件读取。
- **持久化** `AppThemeSettingsStore`：保存 `themeId`、主题封面开关和用户颜色覆盖值。

`Resource`、背景图片、封面和图标由 `ThemeAssetRegistry` 按 ID 解析，不写入 Preferences。

桌面图标由 `AppIconManager` 单独管理，使用 API 26 的 `bundleManager.getAlternateIcons()` /
`setAlternateIcon()`，资源位于 `AppScope/resources/base/media`，并在 `app.json5` 的
`alternateIcons` 中声明。新增主题时必须同时添加同名图标选项；现有图标 ID 保持稳定。
应用主题弹窗的“应用主题图标”默认选中（自定义方案使用“自定义主题”图标），关闭则保留当前桌面图标。
低于 API 26 的设备尝试切换时提示“该能力需要鸿蒙7及以上”，其余主题内容仍正常应用。
主题详情显示配套图标预览，当前使用卡片显示系统实际启用的桌面图标。
新增的 12 套主题桌面图标（含自定义主题）已使用即梦重绘为 1024×1024 PNG，直接注册到 `alternateIcons`，预览和桌面共用同一资源。
星愿魔法来自 `dreamina` CLI，其余 11 套来自画布 CLI；模型、提示词、任务与资源标识、裁切和校验摘要记录在 `docs/theme-icon-generation.json`。
`node scripts/generate-theme-desktop-icons.mjs` 仅生成缺少 PNG 的矢量回退资源；脚本会跳过已有 PNG 的主题，避免覆盖已重绘素材。
运行 `node scripts/app-icon-check.mjs` 检查图标注册、主题覆盖、版本门控和切换状态。

## 目录与职责

```text
entry/src/main/ets/theme/
├── ThemeModels.ets             # ThemeIds、ThemePack、浅深变体和各类令牌模型
├── BuiltinThemeRegistry.ets    # 内置主题定义与编译期注册入口
├── ThemeRuntime.ets            # 将主题发布为扁平 AppStorage 令牌
├── ThemeAssetRegistry.ets      # assetId / iconPackId / styleId 到 Resource 的映射
└── TtsPanelThemeStyles.ets     # 各主题朗读/有声书面板背景的插画与配色

entry/src/main/ets/utils/AppThemeSettingsStore.ets   # 主题选择与颜色覆盖的持久化
entry/src/main/ets/account/ThemeAccessPolicy.ets     # 主题与专属气泡样式的归属关系
entry/src/main/ets/components/ReaderThemeBackground.ets  # 阅读页主题背景组件
entry/src/main/ets/components/TtsPanelThemeBackground.ets  # 朗读/有声书面板主题背景组件

entry/src/main/resources/base/media/
├── reader_decor_*              # 阅读背景角落装饰 SVG（480 × 480）
├── reader_bg_*                 # 旧版 9:16 阅读背景 SVG（1080 × 1920，兼容资源）
├── tts_panel_*                 # 朗读/有声书面板背景插画 SVG（720 × 520）
├── theme_cover_*               # 主题书籍封面
├── theme_frame_*               # 书架封面装饰边框
├── theme_folder_art_*          # 平铺模式分组文件夹插画（450 × 660）
├── theme_logo_*                # 主题标识 SVG（64 × 64）
├── theme_startup_*             # 启动封面
├── ic_theme_<pack>_*           # 导航图标包，每包四个 24 × 24 SVG
└── regex_frame_* / regex_cap_* # 主题专属正则气泡的边框与端饰
```

## 内置主题

`neon-harbor`（霓港来信）为原创复古都市动画主题，含 11 张即梦位图、浅深阅读角饰、导航和桌面图标、`harbor-postcard` 正则及段评气泡。其听书背景使用 720 × 520 JPG，与现有 SVG 共用资源接口和渐隐组件。设计、生成记录、迁移与验证见 [霓港来信说明](neon-harbor-theme.md)。

主题 ID 定义在 `ThemeIds`，是写入设置、云同步和服务端主题目录的稳定标识，发布后不能改名。

| ID | 说明 |
| --- | --- |
| `plain-default` | 默认主题，`BuiltinThemeRegistry.DEFAULT_THEME_ID`，也是所有令牌的回退来源。 |
| `classic-blue`、`warm-paper`、`forest-mist`、`ink-wash`、`neon-night`、`strawberry-cream`、`crimson-archive`、`plum-tea`、`rose-letter`、`moon-crane` | 内置主题。 |
| `sword-frost`、`qingluan-water`、`cat-pipi`、`azure-mecha`、`starwish-magic`、`letterpress-page` | 带整套位图资源的主题，`theme-framework-check` 会逐个校验其资源文件和尺寸。 |
| `custom` | 自定义主题，不是独立的主题包：`BuiltinThemeRegistry.customTheme()` 以某个内置主题为基底克隆，再由 `ThemeComponentSourceIds` 按浅色、深色分别指定各部件来自哪个主题。 |

`BuiltinThemeRegistry.isFree()` 只对 `plain-default` 返回 `true`。

## ThemePack 字段

`ThemePack.schemaVersion` 当前为 `3`。每个主题包含浅色和深色两个 `ThemeVariant`，其余令牌浅深共用。

| 字段 | 类型 | 内容 |
| --- | --- | --- |
| `id` / `name` / `description` | 字符串 | 稳定 ID、显示名和说明。 |
| `light` / `dark` | `ThemeVariant` | 浅色、深色变体，见下表。 |
| `typography` | `ThemeTypographyTokens` | `appFontFamily`。用户选择的自定义字体优先级更高。 |
| `readerLayout` | `ThemeReaderLayoutTokens` | 阅读页推荐的 `fontSize`、`letterSpacing`、`lineHeight`、`paragraphSpacing` 和四边 `margin*`。 |
| `book` | `ThemeBookTokens` | `coverAssetId`、`shelfFrameAssetId`、`shelfFolderAssetId`。 |
| `navigation` | `ThemeNavigationTokens` | 悬浮底栏的 `iconPackId`。 |
| `startup` | `ThemeStartupTokens` | 启动封面的 `styleId`。 |
| `radius` | `ThemeRadiusTokens` | `small`、`medium`、`large`、`card`、`button`、`bubble` 圆角。 |
| `glass` | `ThemeGlassTokens` | 玻璃材质：`panel`、`popover`、`button`、`overlay`、`menu` 五种表面各自的模糊半径和圆角，以及浅深色的着色透明度、边框和阴影。 |

`ThemeVariant` 的三组令牌：

| 分组 | 字段 |
| --- | --- |
| `colors` | `pageColor`、`cardColor`、`inputColor`、`primaryTextColor`、`subTextColor`、`dividerColor`、`accentColor`、`buttonColor`、`dangerColor`。 |
| `reader` | `backgroundColor`、`backgroundAssetId`、`backgroundImageFit`、`textColor`、`subTextColor`、`contentTone`（`light` / `dark`）。 |
| `regexEmphasis` | `emphasisMode`、`bubbleStyle`、`emphasisColor`、`emphasisTextColor`。 |

有效值优先级：

```text
正则规则级设置 > 用户颜色/字体覆盖 > 当前主题浅深变体 > plain-default 回退
```

`ThemeRuntime.applyPack()` 发布令牌时，主题中缺失或非法的值会逐项回退到 `plain-default`，并递增 `KEY_THEME_REVISION` 通知组件刷新。组件应通过 `ThemeRuntime.pageColor(darkMode)`、`ThemeRuntime.glassBlur(surface)` 这类访问器读取令牌，不要直接读取 `ThemePack`。

阅读页保留原有的米黄、素白、青绿和自定义配色，“应用主题”对应稳定索引 `ReaderThemeHelper.APP_THEME_INDEX`。只有选中该项时，主题的阅读背景和阅读文字色才生效。

## 新增内置主题

1. 在 `ThemeModels.ets` 的 `ThemeIds` 中增加 ID 常量。
2. 在 `BuiltinThemeRegistry.ets` 中新增一个返回 `ThemePack` 的私有方法，并在 `createThemes()` 里 `themes.push(...)`。
3. 按下文的资源规范添加资源文件，并在 `ThemeAssetRegistry` 中补全映射；朗读/有声书面板背景见下文“朗读/有声书面板背景”。
4. 新增一个 `server/migrations/` 迁移，把主题 ID 写入 `theme_catalog`。
5. 更新 `scripts/theme-framework-check.mjs`：把主题 ID 加入 `redeemableThemeIds`，并把新迁移文件加入 `serverThemeCatalog` 读取的文件。脚本会检查列表中的每个主题都存在于服务端主题目录中，缺失会直接失败。
6. 运行 `node scripts/theme-framework-check.mjs`。

`theme_catalog` 中已发布的记录不要删除，下架时设置 `enabled = FALSE`，以保留已有权益和历史账本。目录的字段和写入方式见 `server/README.md` 的“主题目录运营”。

### 在独立模块中注册

主题也可以在独立文件中创建，并在应用初始化前注册。ArkTS 严格模式下使用类实例赋值，不要依赖无类型对象字面量：

```ts
import { BuiltinThemeRegistry } from './BuiltinThemeRegistry';
import { ThemePack, ThemeVariant } from './ThemeModels';

const theme = new ThemePack();
theme.id = 'my-theme';
theme.name = '我的主题';
theme.description = '主题说明';
theme.typography.appFontFamily = 'sans-serif';
theme.navigation.iconPackId = 'rounded';
theme.readerLayout.fontSize = 20;
theme.readerLayout.lineHeight = 13;
theme.readerLayout.paragraphSpacing = 11;
theme.readerLayout.marginLeft = 22;
theme.readerLayout.marginRight = 22;
theme.readerLayout.marginTop = 22;
theme.readerLayout.marginBottom = 22;
theme.book.coverAssetId = 'my-theme';
theme.book.shelfFrameAssetId = 'my-theme';
theme.book.shelfFolderAssetId = 'my-theme';

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

`register()` 的行为：

- `id` 为空，或缺少 `light` / `dark` 时返回 `false`，不注册。
- 注册相同 ID 会替换已有定义。
- 注册表保存的是克隆副本，注册后再修改传入对象不会生效。`findById()` 和 `all()` 返回的同样是副本。

## 资源规范

所有 SVG 资源必须是自包含的本地文件：不得包含 `<script>`、`<image>`、`<use>`、`<filter>`、`href=` 或 `url(`。`theme-framework-check` 会按此规则扫描。

| 资源 | 命名 | 规格 | 映射方法 |
| --- | --- | --- | --- |
| 阅读背景装饰 | `reader_decor_<id>_light.svg` / `_dark.svg` | `viewBox="0 0 480 480"`，透明底 | `readerBackgroundDecoration()` |
| 阅读背景右下角装饰 | `reader_decor_<id>_trailing_light.svg` / `_dark.svg` | `viewBox="0 0 480 480"`，透明底，图案贴右下角 | `readerBackgroundTrailingDecoration()` |
| 朗读/有声书面板背景 | `tts_panel_<id>_light.svg` / `_dark.svg` | `viewBox="0 0 720 520"`，透明底 | `TtsPanelThemeStyles.resolve()` |
| 主题封面 | `theme_cover_<id>_NN` | 450 × 660 JPG；内置主题封面均为即梦位图 | `themeBookCovers()` |
| 书架边框 | `theme_frame_<id>.svg` | 中心透明，只画外框和角花 | `themeShelfFrame()` |
| 分组文件夹插画 | `theme_folder_art_<id>.jpg` | 450 × 660 | `themeShelfFolder()` |
| 主题标识 | `theme_logo_<id>.svg` | `viewBox="0 0 64 64"` | `themeLogo()` |
| 启动封面 | `theme_startup_<id>` | 841 × 1870 JPG 竖屏插画；底部约 1/5 叠加文案，不放主体 | `startupBackground()` |
| 导航图标包 | `ic_theme_<pack>_<tab>.svg` | `viewBox="0 0 24 24"`，单色纯黑填充 | `navigationIcon()` |
| 正则气泡边框 / 端饰 | `regex_frame_<style>.svg` / `regex_cap_<style>.svg` | — | `regexBubbleFrame()` / `regexBubbleCap()` |

### 阅读背景

内置主题使用“主题底色 + 自适应边框 + 角落装饰”的结构，由 `ReaderThemeBackground` 组件绘制。

1. 添加浅色、深色两个 `reader_decor_*` 左上角装饰资源，以及两个 `reader_decor_*_trailing_*` 右下角装饰资源。图案保持低对比，正文区域不要放置密集细节。右下角是单独绘制的另一幅图，与左上角构成同一场景，不要用左上角图案镜像；在 `scripts/generate-reader-trailing-ornaments.py` 中添加绘制函数和浅深配色后运行脚本生成。
2. 在 `ThemeAssetRegistry` 中增加背景 `assetId` 常量，并在 `normalizeBackgroundAssetId()`、`readerBackgroundDecoration()` 和 `readerBackgroundTrailingDecoration()` 中补上映射，同时把名称加入 `theme-framework-check.mjs` 的右下角装饰列表。
3. 分别填写 `theme.light.reader.backgroundAssetId` 和 `theme.dark.reader.backgroundAssetId`。
4. 必须提供 `backgroundColor`：它是实际铺满任意分辨率、横竖屏和分屏窗口的阅读底色。
5. 正确填写 `contentTone`，阅读页据此决定系统栏图标和辅助内容的明暗。

可选的调整点：

- `readerBackgroundTrailingRotation()`：有独立右下角图案时返回 0；只有未登记右下角图案的资源才回退为左上角装饰旋转 180°。

装饰锚定在左上和右下的正方形区域，使用 `ImageFit.Contain`。不要把内置主题改回 `Cover` 全屏壁纸，`theme-framework-check` 会检查这一点。旧版 `reader_bg_*` 仅作为兼容资源保留。

### 朗读/有声书面板背景

朗读面板和有声书面板共用 `ReaderTtsPlayerPanel`，背景由 `TtsPanelThemeBackground` 绘制，与阅读页背景相互独立。结构是“顶部插画 + 天空渐变 + 面板底色 + 播放区柔光”：插画贴顶、按宽度等比缩放，下半部分渐隐到面板底色，控件始终落在干净的底色上。

1. 在 `scripts/generate-tts-panel-backgrounds.py` 中为主题写一个绘制函数，并在 `THEMES` 里登记浅色、深色两套配色，然后运行脚本生成 `tts_panel_<id>_light.svg` 和 `_dark.svg`。同一主题的浅深两张图共用一份图形，只换配色。
2. 在 `TtsPanelThemeStyles.resolve()` 中增加分支，填写插画资源、`skyColor`（插画背后的天空色）、`surfaceColor`（不透明的面板底色，取接近主题 `pageColor` 的颜色以保证文字对比度）和 `glowColor`（带透明度的强调色）。
3. 把主题名加入 `theme-framework-check.mjs` 的 `ttsPanelThemeNames`。

生效范围：

- 首页朗读浮层和听书页始终使用当前应用主题的面板背景。
- 阅读页的朗读面板沿用阅读配色的文字色，只有阅读配色选中“应用主题”时才使用主题面板背景，其余配色保持玻璃面板。
- 自定义主题通过部件来源 `ThemeComponentSourceIds.ttsPanelThemeId` 选择面板背景来自哪个主题（`ThemeRuntime.ttsPanelThemeId()`）。该字段是后加的，旧方案里为空，读取时回退到 `readerThemeId`。

### 主题封面与书架边框

1. 添加封面、边框和文件夹插画资源。封面底图是完整插画，不叠加书名或作者。
2. 在 `themeBookCovers()`、`themeShelfFrame()` 和 `themeShelfFolder()` 中增加映射。同一个 `coverAssetId` 可以映射多张封面，书架会按书籍稳定打乱并轮播；`themeBookCover()` 返回其中第一张。
3. 配置 `theme.book.coverAssetId`、`shelfFrameAssetId` 和 `shelfFolderAssetId`。

是否启用主题封面由 `appThemeBookCoverEnabled` 持久化；是否套用主题排版由 `appThemeApplyLayoutEnabled` 持久化。

### 导航图标包

图标包固定包含 `bookshelf`、`explore`、`search`、`mine` 四个图标，路径使用纯黑填充，由 ArkUI 的 `fillColor` 注入主题色。

新增图标包时：

1. 在 `ThemeAssetRegistry` 中增加 `ICON_PACK_*` 常量。
2. 在 `normalizeIconPackId()` 中放行该 ID，否则会回退到 `classic`。
3. 在 `navigationIcon()` 的分支中增加映射。
4. 把 `ThemePack.navigation.iconPackId` 指向新 ID。

当前可用的图标包 ID：`classic`、`rounded`、`ink`、`strawberry`、`crimson`、`plum`、`rose`、`crane`、`sword-frost`、`qingluan-water`、`cat-pipi`、`azure-mecha`、`starwish-magic`、`letterpress-page`。

桌面应用图标由 `AppIconManager` 独立管理，不随主题切换。

## 正则气泡

正则字体规则的数据结构是 `ReaderRegexFontRulesData`，`schemaVersion` 为 `3`，编解码统一走 `ReaderRegexFontCodec`。

强调模式分两层，取值不同：

| 层级 | 字段 | 取值 |
| --- | --- | --- |
| 主题 | `ThemeRegexEmphasisTokens.emphasisMode` | `none`、`text`、`highlight`、`bubble` |
| 规则 | `ReaderRegexFontRule.emphasisMode` | `inherit`、`none`、`custom` |

- 规则为 `inherit` 时，使用当前主题的强调模式、气泡形状、端饰和颜色，忽略规则中残留的样式字段。
- 规则为 `custom` 时，规则自己的 `customTextColorEnabled`、`customHighlightEnabled`、`customBubbleEnabled` 及对应颜色、`bubbleStyleId` 才生效。
- 旧数据里规则级的 `text`、`highlight`、`bubble`、`accent` 会被归一化为 `custom`。
- `highlightColorEnabled` 和 `shadowColor` 是为 schema v2 保留的兼容字段，仍会读取和输出。

气泡样式 ID 定义在 `ThemeBubbleStyles`：

- 通用样式：`qq-soft`、`qq-solid`、`capsule`、`paper`、`neon`。
- 主题专属样式：`classic-glass`、`warm-scroll`、`forest-dew`、`ink-brush`、`neon-pulse`、`strawberry-ribbon`、`crimson-stamp`、`celadon-slip`、`rose-frame`、`moon-halo`、`sword-talisman`、`qingluan-jade`、`pipi-soft-paw`、`mecha-comm`、`starwish-ribbon`、`pencil-mark`。

新增主题专属气泡样式时：

1. 在 `ThemeBubbleStyles` 中增加常量。
2. 在 `ReaderRegexFontRule.ets` 的编解码与样式解析中支持该 ID，并在 `ReaderFontSettings.ets` 中提供选择项。把新 ID 加入 `theme-framework-check.mjs` 的 `bubbleStyles` 列表后，脚本会检查这三处都包含它。
3. 添加 `regex_frame_*` / `regex_cap_*` 资源，并在 `regexBubbleFrame()` / `regexBubbleCap()` 中映射。
4. 在 `ThemeAccessPolicy` 中声明该样式归属于哪个主题。

渲染约束：

- 气泡命中统一使用行内 `ContainerSpan`，命中文字、背景、阴影和左右端饰属于同一个行内单元。
- 强调效果不改变正文源文本和 TTS 索引；TTS 当前朗读高亮的显示优先级最高。
- 匹配循环必须处理零长度匹配，避免死循环。

## 验证

### 终身超级会员领取型主题

`obsidian-archive`（曜金藏书）是手动领取型主题，不能套用普通主题的点数购买、会员主题库自动授权或试用逻辑。它使用 `gilded-orbit` 气泡、配套浅深阅读角饰及独立即梦位图。授权同时要求终身超级会员身份和一年内的有效领取记录；到期后才能再次领取。

修改相关入口时，保持 `ThemeAccessPolicy`、自定义部件选择、`ThemeTrialManager`、`AppIconManager` 和 `MembershipThemeGuard` 的一致性。详细规则、资源记录和数据库迁移顺序见 [专属主题说明](membership/super-exclusive-theme.md)。

运行主题回归脚本：

```powershell
node scripts/theme-framework-check.mjs
```

它检查主题 ID 与注册、服务端主题目录、资源映射是否指向存在的文件、SVG 的 `viewBox` 与安全限制、位图尺寸、气泡样式在模型和设置页中的覆盖，以及阅读背景组件的接入方式。

脚本不能覆盖的部分需要真机检查：

- 浅色、深色、跟随系统三种模式各检查一次。
- 冷启动后主题 ID、颜色覆盖和自定义字体保持不变。
- 图片背景下检查当前页、进入页和横向翻页动画。
- 用旧正则 JSON、schema v2、非法正则和零长度正则检查阅读页。
- 同时开启正则气泡与 TTS，确认 TTS 高亮覆盖气泡。
- 悬浮 `HdsTabs` 与兼容 `Tabs` 两种底栏都检查四个图标。

构建调试 HAP 的命令见 [README 的命令行构建](../README.md#命令行构建)。
