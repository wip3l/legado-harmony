# 测试书源说明

本目录提供上架审核和功能测试用书源。当前内置文件：

- `kuwo-novel.json`：测试书源配置。

## 方式一：新建书源

1. 打开应用，进入「我的」。
2. 进入「书源管理」。
3. 点击「新建书源」。
4. 按下面字段填写：

| 字段 | 内容 |
| --- | --- |
| 书源名称 | 酷我小说 |
| 书源分组 | API |
| 书源地址 | `http://appi.kuwo.cn` |
| 搜索地址 | `/novels/api/book/search?keyword={{key}}&pi={{page}}&ps=30` |
| 请求头 | `{"Accept":"*/*","Connection":"Close","User-Agent":"Dalvik/2.1.0 (Linux; U; Android 8.0.0; LND-AL40 Build/HONORLND-AL40)"}` |
| 搜索列表 | `$.data` |
| 搜索书名 | `$.title` |
| 搜索作者 | `$.author_name` |
| 搜索封面 | `$.cover_url` |
| 搜索简介 | `$.intro` |
| 搜索详情页 | `/novels/api/book/{{$.book_id}}` |
| 详情初始化 | `$.data` |
| 详情书名 | `$.title` |
| 详情作者 | `$.author_name` |
| 详情封面 | `$.cover_url` |
| 详情简介 | `$.intro##(^|[。！？]+[”」）】]?)##$1<br>` |
| 目录地址 | `/novels/api/book/{{$.book_id}}/chapters?paging=0` |
| 目录列表 | `$.data` |
| 章节名称 | `$.chapter_title##正文卷.|正文.|VIP卷.|默认卷.|卷_|VIP章节.|免费章节.|章节目录.|最新章节.|[\\(（【].*?[求更票谢乐发订合补加架字修Kk].*?[】）\\)]` |
| 章节地址 | `/novels/api/book/{{$.book_id}}/chapters/{{$.chapter_id}}` |
| 正文规则 | `$.data.content` |

5. 保存书源。
6. 回到「搜索」，搜索任意书名，例如「龙族」，选择「酷我小说」结果打开。
7. 进入详情页后可加入书架并开始阅读。

## 方式二：从 URL 导入

1. 使用 raw 文件地址导入：

```text
https://raw.githubusercontent.com/wip3l/legado-harmony/main/docs/book-sources/kuwo-novel.json
```

2. 打开应用，进入「我的」。
3. 进入「书源管理」。
4. 点击「从 URL 导入」。
5. 粘贴上面的 URL，确认导入。
6. 提示成功导入 1 个书源后，进入「搜索」验证。

如果当前上架审核包对应的代码不在 `main` 分支，请将 URL 中的 `main` 替换为实际分支名或 tag。

## 方式三：从剪切板导入

1. 打开工程文件 `docs/book-sources/kuwo-novel.json`。
2. 复制文件中的全部 JSON 内容。
3. 打开应用，进入「我的」。
4. 进入「书源管理」。
5. 点击「从剪切板导入」。
6. 提示成功导入 1 个书源后，进入「搜索」验证。

## 审核测试建议

推荐测试流程：

1. 导入「酷我小说」书源。
2. 进入「搜索」，搜索「龙族」。
3. 打开任意搜索结果。
4. 点击「加入书架」。
5. 点击「开始阅读」，确认目录和正文能够正常加载。
