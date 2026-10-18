# discourse-ingenic-theme

Ingenic 社区论坛的主题，与 `discourse-ingenic` 插件配套；文档、下载、开发板和悬赏的数据都由插件提供，主题负责呈现。

它有意**不是**任何现成 Discourse 主题的副本。布局只使用 Discourse 公开的主题 API 搭建，因此可以跨版本升级继续工作。

论坛建成后怎么用——会员功能、后台页面和它们背后的设置——见插件的使用指南：
[English](https://github.com/aishangletaohua/discourse-ingenic-plugin/blob/main/docs/usage.md)
· [中文](https://github.com/aishangletaohua/discourse-ingenic-plugin/blob/main/docs/usage.zh-CN.md)。

English: [README.md](README.md).

## 提供什么

- 侧边栏的 Ingenic 导航，分三组：顶部是论坛本身（发帖、首页、论坛自己的分区），中间是带标题的开发者资源（在线文档、开源项目、下载、开发板），底部是会员赚到或托管的东西（悬赏、积分）。只有中间一组画标题，上下两组是纯列表，这正是把悬赏和积分留在开发者资源之外的方式。每一组都注册为真正的 Discourse 侧边栏分区，因此继承核心已经实现的移动端抽屉、分区筛选、折叠状态和当前链接高亮——并且位于侧边栏**内部**而不是旁边。Discourse 自己的分类、标签和访客自建的分区保持原样。
- 三个社区链接，位于论坛列表和 Discourse 自己的 **More** 抽屉之间：**MCP**（仅在 `mcp_server_enabled` 开启时出现）、**Site Feedback** 和 **All Categories**。它们是社区分区的链接，所以共享该组的折叠状态和高亮。
- 管理员可配置的导航条目（名称、图标、目标、分组、顺序、可见性）
- 可以把侧边栏移到左边或右边，并在主题设置里调整宽度
- 由区块组装、管理员可配置的首页
- 文档阅读器：两级产品选择器（先选系列，再弹出该系列下的芯片）、版本选择、全文检索、可折叠目录树、渲染后的 Markdown 正文和上一页／下一页导航
- 下载中心，带产品／类型／版本／平台筛选，并为三种访问级别分别显示正确的提示和按钮——需要积分的资源还会显示 **用 N 积分解锁**（余额足够时）或 **需要 N 积分**（不足时）
- 开发板目录，类型、系列、芯片三行按钮式筛选，以及跳转到外部的申请／购买链接
- `/ingenic/points` 积分页，显示读者自己的余额、论坛为什么付积分以及自己的记录——只读，且看不到别人的记录
- `/ingenic/bounties` 的**高分悬赏**板：全站正在悬赏的问题，金额从高到低，带问题、金额和剩余时间。在话题页上，同一个功能是帖子顶部的横幅——有效悬赏，有权限的人可以撤回；答案被采纳后，显示付了多少、付给了谁
- `/ingenic/mcp` 的 **MCP 服务器**页面：要加到 AI 客户端里的地址、连接的三步、给 Claude Code、VS Code 以及其他支持远程 MCP 的客户端的现成配置片段，以及已批准的客户端能看到什么。它读取 `mcp_server_enabled`，服务器关闭时显示「尚未启用」；侧边栏里的链接同时隐藏
- 右下角的**浮动助手**：一个机器人启动按钮，打开一个小面板说明助手的用途，并引导进入 AI 机器人的会话页。仅在 `ai_bot_enabled` 开启时出现；未登录读者看到的按钮会变成登录链接，登录后回到助手
- 中英文字符串，结构上支持以后添加更多语言

## 安装

主题从 Git 仓库安装：

```bash
cd /var/discourse
./launcher enter app
rails c
```

```ruby
Theme.create_from_git_url(
  url: "https://github.com/aishangletaohua/discourse-ingenic-theme.git",
  branch: "main"
)
```

也可以在后台界面操作：**后台 → 自定义 → 主题 → 安装 → 从 Git 仓库安装**。

安装后把它设为默认主题，并选择 **Ingenic Light** 配色方案。

有两个核心功能是可选的，直接读取站点设置：

- **MCP** —— `/ingenic/mcp` 页面及其侧边栏链接需要 `mcp_server_enabled`（后台 → 设置 → MCP）。关闭时页面会说明服务器尚未启用，链接隐藏。
- **助手** —— 浮动启动按钮需要 `discourse-ai` 插件的 `ai_bot_enabled`。它会链接到该插件的会话页；没有安装插件时保持隐藏，而不是指向一个不存在的页面。

## 主题设置

| 设置 | 用途 |
| --- | --- |
| `ingenic_locales` | 顶部语言切换器提供的语言，按顺序排列。少于两个时隐藏 |
| `ingenic_sidebar_width` | 桌面端导航侧边栏宽度，单位像素 |
| `ingenic_sidebar_position` | `left` 或 `right` |
| `ingenic_nav_order` | `first` 把 Ingenic 导航放在 Discourse 自己的侧边栏分区（分类、标签、访客自建）之上 |
| `ingenic_nav_title` | 开发者资源组的标题；留空显示 *Developer Resources*（中文为「开发者资源」）。上下两个列表按设计不带标题 |
| `ingenic_hero_title` | 首页区块上方的可选大标题 |
| `ingenic_hero_subtitle` | 大标题下方的可选说明行 |

顶部的语言切换器还需要两个 Discourse 自身的站点设置：`allow_user_locale`（默认开启）和 `set_locale_from_cookie`。没有第二个，未登录读者的选择会写进一个服务端不会读回的 cookie，看起来就像开关不起作用。

没有用于显示／隐藏侧边栏或折叠侧边栏的主题设置：Discourse 界面里已经有这两个功能，再加一个控件会和访客熟悉的那个打架。强调色也不是主题设置——它是本主题自带的 **Ingenic Light** 配色方案，用标准的管理员取色器修改。

## 配色

整套颜色是浅天蓝，分布在两个地方：

- **`about.json`** —— **Ingenic Light** 配色方案：强调色（`tertiary`）、文字色（`primary`）、页头、搜索高亮，以及语义红、绿、粉。这些是管理员有理由修改的颜色，Discourse 已经为它们提供了取色器。
- **`common/common.scss`** 的 `:root` 块——配色方案没有对应槽位的浅色：提示框的底色、它周围的分隔线、图片加载前的淡蓝色底。`--ingenic-surface-tint` 和 `--ingenic-surface-border` 是主题自己的表面使用的变量。

这个块之外没有任何地方直接写颜色，所以整个主题的色调只在这两个地方修改，别处不用动。

强调色是 `#2FC1FF`：比 `#0CBBFF` 浅一档的天蓝，后者是主题本来要用的色调。那个色调是表面，不是文字——在白底上作文字只有 2.4:1，白字放在它上面是 1.9:1——所以两处必须被读出来的地方单独命名：

- `--ingenic-link`，`#0f7fa8` —— 同一色相降一档，在白底上是 4.5:1。链接、悬停状态和 eyebrow 都用它，同时写入 `--d-link-color` 和 `--d-nav-color--*`，让整个论坛而不只是主题自己的组件都有清晰可读的链接。
- `--ingenic-accent-ink` —— 放在强调色填充**上面**的颜色。它解析为 `primary`，所以填充按钮是浅天蓝底配深藏青字，而不是读不清的白字。写入 `--d-button-primary-*`。

两者都跟随配色方案：移动 `tertiary`，它们会一起移动，因为它们是同一色相在两侧的取值。主题样式表在配色方案之后加载，所以这里的 `:root` 块会覆盖配色方案自己的变量。

字体和间距使用 Discourse 自己的尺度（`--font-up-*`、`--space-*`、`--font-family`），不是主题发明的，因此会跟随站点的字体设置，也与其他 Discourse 站点一致，不需要第二套设计规范。

## 布局配置

导航条目和首页区块放在**插件**设置里（`ingenic_nav_items` 和 `ingenic_homepage_blocks`），内容编辑不需要碰主题就能修改。两者都通过站点序列化器发送到客户端。

导航条目结构：

```json
{
  "key": "documentation",
  "label": "Documentation",
  "icon": "book",
  "href": "/ingenic/docs",
  "section": "resources",
  "position": 4,
  "enabled": true,
  "external": false
}
```

`section` 决定条目画在三个侧边栏分组中的哪一个：`forum`（顶部的纯列表）、`resources`（主题标题下的一组）或 `member`（底部的纯列表）。`position` 决定条目在自己组内的顺序；三个组本身的顺序始终不变。不认识的分组名会按 `forum` 读取，所以写错一个字母只会让条目换一行，而不会消失。

用 `"category": "technical-discussions"` 代替 `href` 可以指向某个 Discourse 分类；它会自动解析为分类路由。

留空时，主题自带一份同样分三组的列表：发帖、首页、官方公告、技术讨论 · 在线文档、开源项目、SDK 与固件下载、开发板 · 悬赏、积分。配置过的列表会**整体替换**它而不是合并，所以在悬赏板上线之前就配置过导航的站点没有「悬赏」条目，也不会自己长出来——需要手动加上，或者清空设置。

链接会在它指向的整个子树内保持高亮，所以 `/ingenic/docs/t32pro/2.1.0/overview` 仍然把「在线文档」显示为当前项。外部链接永远不高亮。

首页区块结构：

```json
{
  "type": "discussions",
  "position": 2,
  "limit": 10,
  "category": "technical-discussions",
  "title": "Latest discussions",
  "enabled": true
}
```

支持的区块类型：`announcements`、`discussions`、`downloads`、`boards`、`bounties`、`promotions`、`categories`、`html`。

`categories` 区块是让页面成为首页而不是摘要的那一块：它把论坛分区列为卡片，每张卡片链接到对应分类。给它 `"categories": ["announcements", "technical-discussions"]` 可以指定显示哪些分区及顺序；不写则取最活跃的顶级分区，最多 `limit` 个（默认 8）。`"show_all": false` 会去掉区块标题末尾的 **All sections** 链接。

`bounties` 区块列出金额最高的有效悬赏，最多 `limit` 个（默认 5），每个都链接到承载它的问题。没有悬赏时它什么都不画——没有标题，也没有空行——这才让它可以留在尚未流行悬赏的论坛首页上。

留空时，首页显示 `categories` 区块，下面接 `bounties` 面板：分区网格是任何人在决定哪些分区值得占一行之前首页需要的东西，再加上一个开着也不花成本的区块。与导航列表不同，这里的默认值只是默认值：配置过的区块列表会替换它。

## 首页

首页不是主题盖在话题列表上的一层。它是一个**注册首页**：插件把它作为 `default_homepage` 的选项之一交给 Discourse，由 Discourse 自己挂到 `/`。这就是为什么在导航里选「最新」不会再清空页面——首页和话题列表是两个独立的目的地，而不是一个带开关的页面。

要使用它，把站点的 **`default_homepage`** 设置（后台 → 设置 → 界面）设为 Ingenic 首页；存储的值是 `ingenic-home`。该选项只在插件启用时出现在列表里；选中过它的站点在插件关闭后会回退到普通首页。它自己的地址是 `/ingenic/home`，可以写进链接，刷新时直接返回页面而不是重定向到最新话题。

页面在浏览器里用站点已经发送的数据组装（`site.json` 里的分类列表、插件提供的首页区块），所以背后的服务端动作只渲染应用外壳。不存在需要同步的第二份分类。

## 添加语言

语言文件放在 `locales/`。把 `locales/en.yml` 复制为 `locales/<locale>.yml`，翻译值、保持键不变。Discourse 把主题翻译注册在主题自己的命名空间下，所以每次查找都通过 `themePrefix`——直接写 `i18n("ingenic.docs.version")` 会去核心翻译里找，什么也找不到。

文件名必须是 Discourse 已经提供的语言代码（`zh_CN`、`pt_BR`），不能自己发明，否则访客无法选择它。

内容层面的翻译由插件处理，它为每个文档页面、下载和开发板保存一个 `locale`。内容使用相同的语言代码，所以翻译过的页面会出现在界面语言匹配的读者面前，其余由默认语言补齐。
