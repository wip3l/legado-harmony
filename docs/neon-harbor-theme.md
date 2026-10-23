# 霓港来信 · Neon Harbor

原创复古都市动画主题，稳定 ID 为 `neon-harbor`。设计与接入完成于 2026-10-23。

## 设计

以八十年代手绘赛璐璐动画的墨线、硬边阴影和轻微胶片颗粒表现港湾城市。主视觉是三位成年女性朋友在屋顶书店的日常：银灰短发的建筑摄影师、赤褐低发髻的唱片店主、黑色齐颈短发的夜班电台编辑。衣装分别采用象牙夹克、海盐青西装、陶土色风衣，以书、唱片和信件串联场景。

借鉴方向限于年代质感与都市时尚氛围。人物关系、发型、职业、服装、场景和标识均重新设计；未使用现有作品截图、角色参考图、名称、标志或招牌服装。生成提示词未使用作品名或作者名。应用内显示名为「霓港来信」。

浅色是象牙书纸与暗莓红，深色是靛蓝与柔珊瑚；海盐青只作为插画和边饰的辅助色。人物集中在启动页和书封，正文区使用低对比的书店窗景、港湾角饰。避免用高饱和整幅插画铺在正文背后。

| 部件 | 实现 |
| --- | --- |
| 启动画 | 三人屋顶书店插画，841 × 1870，底部留白用于应用文案 |
| 六张书封 | 摄影师、唱片店主、电台编辑、雨巷书店、海上慢信、末班电车，各 450 × 660 |
| 分组插画 | 雨夜窗台的书、台灯与信封，450 × 660 |
| 听书面板 | 独立生成晨间、午夜电台插画，各 720 × 520；复用已有渐隐背景组件 |
| 桌面图标 | 即梦绘制的书页海浪、珊瑚日落，1024 × 1024 |
| 阅读装饰 | 浅深两套独立左上、右下角饰；适应分屏、横屏和不同窗口尺寸 |
| 导航 | 书脊、罗盘、书页放大镜、信封人物，纯黑填充 SVG，由 ArkUI 着色 |
| 书框与标识 | 珊瑚、青碧双线书框；日落书页主题标识 |
| 正则气泡 | `harbor-postcard`「港湾邮笺」，邮笺边线与信封端饰 |
| 段评与本章说 | 同主题配色、小信封装饰；书源自定义设置继续优先 |
| 排版与玻璃 | 正文 20，行距 14，段距 8，四边距 24；克制圆角，高不透明度玻璃 |

全部 11 张位图由 `dreamina` CLI 默认 5.0 模型、2k 档生成，三张人物封面通过启动画进行图生图。项目接入只做中心裁切、缩放和编码，不借用其他主题的插画。14 个 SVG 是便于着色、缩放的原创代码矢量部件，其中包含两个旧阅读背景接口的纯色兼容资源。

## 配色与阅读验证

| 用途 | 浅色 | 深色 |
| --- | --- | --- |
| 页面 | `#F7F1EA` | `#131A2C` |
| 卡片 | `#FFFBF5` | `#1E263B` |
| 主要文字 | `#27283D` | `#F5EADF` |
| 次要文字 | `#70646D` | `#B9ACB8` |
| 强调 | `#9C4058` | `#F4A595` |
| 阅读底色 | `#FAF3E9` | `#182032` |
| 阅读文字 | `#303043` | `#E5DFD8` |
| 气泡底色 / 文字 | `#EEDBD7` / `#643244` | `#3B3048` / `#FFE5D5` |

阅读正文对比度为浅色 **11.70:1**、深色 **12.29:1**。页面与卡片上的主要、次要、强调文字均通过 4.5:1 检查；按钮前景按既有 `onAccentColor` 机制选择。装饰图的实际叠加效果仍需结合设备显示检查。

## 接入与发布

`ThemeModels`、`BuiltinThemeRegistry`、`ThemeAssetRegistry`、`ThemeRuntime`、`TtsPanelThemeStyles` 已注册完整资源。自定义主题部件选择沿用现有注册表。新增气泡同时接入规则编解码、运行时正常化与回退白名单、设置页、权限归属和段评绘制。

桌面图标已写入 `AppScope/app.json5` 与 `AppIconManager`，沿用 API 26 门控。主题沿用普通主题授权、试用和会员主题库规则。

服务端迁移为 `server/migrations/024_neon_harbor_theme.sql`，定价已确认为 **90 轻页积分**，有效期沿用现有配置的 365 天，`ON CONFLICT DO NOTHING`。迁移尚未执行到线上；发布时应按项目既有数据库发布流程执行。客户端无需新增接口。

## 资源记录与续作

- `docs/neon-harbor-generation.json`：最终 11 张素材的提示词、任务 ID、参考关系、原图尺寸、SHA-256、接入路径，以及一次失败记录。
- `output/neon-harbor/generation.json`：本机任务状态与原图路径，不入库。
- `output/neon-harbor/contact-sheet.png`：全部素材总览。
- `output/neon-harbor/design-preview.png`：使用项目实际素材和配色制作的布局预览，非真机截图。
- `output/neon-harbor/build.log`：本次 HAP 编译日志。

初始积分余额为 567，生成结束读取为 534。十一张成功任务各报告 3 积分；一张渡轮图曾返回 `InputTextRisk`，改成简化的港湾静物描述后成功。余额变化只记录读取事实，不作为结算或退款账本。

生成脚本持久化任务身份并防止同一状态文件被并发写入；正常续作先查询已有任务，不重复提交成功任务。CLI 进程内清除失效代理配置，不修改系统设置。每次新生成仍消耗积分。

```powershell
# 只查询已有任务并下载，保留原 submit_id
node scripts/generate-neon-harbor-art.mjs query
# 创建状态中尚不存在的素材；需已明确要生成，命令会消耗积分
node scripts/generate-neon-harbor-art.mjs submit
# 启动画完成并下载后，再 submit 才会创建依赖它的三张人物封面
node scripts/prepare-neon-harbor-art.mjs
node scripts/generate-neon-harbor-vectors.mjs
node scripts/preview-neon-harbor.mjs
```

网络结果不确定或存在 `submitting` 状态时，应先核对 CLI 历史，不要删除状态后重新付费提交。若进程被强制终止留下 `generation.lock`，确认没有运行中的生成/查询进程后再清理该锁。

## 验证结果

- `node scripts/theme-framework-check.mjs`：通过。
- `node scripts/neon-harbor-check.mjs`：通过，覆盖真实主题应用→阅读上下文→原生文字气泡、段评绘制、无效值回退、资源路由、权限回退、对比度与媒体 SHA-256。
- `node scripts/app-icon-check.mjs`：通过。
- `node scripts/obsidian-reader-bubbles-check.mjs`：通过，已有主题气泡未回归。
- `node scripts/membership-theme-check.mjs`：10 项通过。
- DevEco `assembleHap --no-daemon`：成功，约 41 秒；现有弃用警告仍存在。
- `git diff --check`：通过。

调试包在 `entry/build/default/outputs/default/entry-default-signed.hap`。本轮未安装到设备，真机冷启动、系统桌面图标切换、横屏翻页和 TTS 交互需在设备验收。
