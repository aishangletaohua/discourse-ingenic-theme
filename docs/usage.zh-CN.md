# Ingenic 主题配置指南

本文面向论坛的管理员：哪些外观由主题设置控制、哪些由插件后台控制，以及每一处如何
在不发版的情况下修改。

会员侧的功能 —— 文档阅读器、下载权限、悬赏、积分 —— 见插件的使用指南：
[English](https://github.com/aishangletaohua/discourse-ingenic-plugin/blob/develop/docs/usage.md)
· [中文](https://github.com/aishangletaohua/discourse-ingenic-plugin/blob/develop/docs/usage.zh-CN.md)。

English: [usage.md](usage.md).

---

## 1. 各部分由谁负责

| 看到的内容 | 在哪里配置 |
| --- | --- |
| 侧边栏条目（名称、图标、顺序、显隐） | 插件设置 `ingenic_nav_items` |
| 开发者资源分组的标题 | 主题设置 `ingenic_nav_title` |
| 首页区块及其顺序 | 插件后台 **Ingenic → Site content → Home page**（存储于 `ingenic_homepage_blocks`） |
| 首页栏目卡片 | 插件后台 **Site content → Home cards** |
| 右栏推广位 | 插件后台 **Site content → Promotions** |
| 页脚链接栏目、合作平台、外链按钮 | 插件后台 **Site content → Footer columns / Partner platforms / External buttons** |
| 侧栏宽度与位置、主标题、语言 | 主题设置 |
| 颜色 | **Ingenic Light** 配色方案与主题的 `common.scss` |
| 标签胶囊配色 | 主题默认，可在 **Ingenic → Tag colours** 覆盖 |
| 文档、下载、开发板本身 | 插件各自的管理页 |

这样拆分是有意的：编辑每周都要改的内容存放在插件数据库里，改它不需要动任何一个
仓库；属于设计决定的内容放在主题里，随主题发版更新。

---

## 2. 主题设置

后台 → Customize → Themes → **Ingenic Community** → *Theme settings*；如果主题已被
选中，也可以在 后台 → Settings → Themes 里修改。

| 设置 | 默认 | 作用 |
| --- | --- | --- |
| `ingenic_sidebar_width` | `288` | 桌面端导航侧栏宽度（像素）。超过 288 会被限制，以保证内容栏的宽度。 |
| `ingenic_sidebar_position` | `left` | `left` 或 `right`。窄屏下侧栏变为抽屉，此项不生效。 |
| `ingenic_nav_order` | `first` | `first` 让 Ingenic 导航位于 Discourse 自带侧栏分组之上；`last` 则放在其下。 |
| `ingenic_nav_title` | *(空)* | 开发者资源分组的标题。留空显示 *Developer Resources* / 开发者资源。 |
| `ingenic_hero_title` | *(空)* | 首页区块上方的主标题。留空显示 *Welcome to Ingenic Community* / 欢迎来到 Ingenic 社区。 |
| `ingenic_hero_subtitle` | *(空)* | 主标题下方的说明行，可选。 |
| `ingenic_locales` | `en\|zh_CN` | 页头语言切换器提供的语言，常用的在前。少于两种时切换器隐藏。 |

语言切换器还需要 Discourse 的两个设置：`allow_user_locale`（默认开启）和
`set_locale_from_cookie`（必须开启）。首次访问的访客得到的是站点的 `default_locale`，
不是主题设置。

主题刻意不提供“显示／隐藏侧栏”或“折叠侧栏”的设置：Discourse 本身就有这两个控件，
再做一个会和会员熟悉的那个打架。

---

## 3. 侧边栏

导航是一个 JSON 设置 `ingenic_nav_items`（后台 → Settings → Plugins，或插件的设置
页）。每个条目：

```json
{
  "key": "docs",
  "label": "Online Documentation",
  "icon": "book",
  "href": "/ingenic/docs",
  "section": "resources",
  "position": 5,
  "enabled": true
}
```

- `section` 是三个分组之一，固定按此顺序绘制：
  - `forum` —— 顶部不带标题的列表（发帖、首页、论坛各版块）；
  - `resources` —— 主题标题下的开发者资源（文档、下载、开发板、MCP）；
  - `member` —— Topics 下方的会员行（悬赏、积分，以及固定的 Site Feedback 与
    All Categories）。
- `position` 只在**本组内**排序。
- 用 `"category": "technical-discussions"` 代替 `href`，可直接指向 Discourse 版块。
- `"external": true` 在新标签页打开，并且不会高亮为当前页。
- `"enabled": false` 隐藏条目而不删除。

链接在其指向的整个子树内保持高亮，因此
`/ingenic/docs/t32pro/2.1.0/overview` 仍会把 Documentation 标为当前。

**设置留空不等于“没有导航”**，而是“使用主题内置列表”。内置列表是整体替换，不做
合并：在悬赏功能出现之前配置过导航的站点不会自动多出 Bounties 行，需要手动添加，
或清空设置回退到默认列表。

**Technical Discussions** 与 **Open Source** 的悬停面板由主题为这两行专门绘制，
不能逐项配置；把条目移走，面板也就随之消失。

---

## 4. 首页

后台 → Plugins → Ingenic → **Site content → Home page**。

区块是一个 JSON 数组；该页面可以增删和排序。每个区块：

```json
{ "type": "latest", "limit": 8, "layout": "main", "position": 1 }
```

**类型**（未知类型会被跳过，不会画成空框）：

| 类型 | 内容 |
| --- | --- |
| `categories` | 论坛一级版块卡片；`categories` 指定版块标识及顺序，`limit` 限制数量 |
| `latest` | 最新主题，带分页 |
| `hot` | 近期最活跃的主题 |
| `popular` | 贡献统计窗口内的热门帖子（`ingenic_popular_window_days`） |
| `activity` | 某个版块（`category`）的最新动态 |
| `announcements` | 某个版块（`category`）的主题，按公告样式展示 |
| `discussions` | 某个版块（`category`）的主题 |
| `downloads` | 最新发布的下载资源 |
| `boards` | 最新的开发板 |
| `bounties` | 当前悬赏，金额高的在前；没有悬赏时整块不绘制 |
| `promotions` | Site content → Promotions 里配置的推广内容 |
| `leaderboard` | 每周贡献榜 |

**布局**：`layout` 可为 `full`（通栏）、`main`（左栏）或 `side`（右栏）。不填时按
类型使用其自然位置 —— 栏目卡片通栏，多数列表在左栏，短列表在右栏。

`ingenic_homepage_blocks` 为空表示“使用主题默认首页”：栏目卡片、最新讨论、
Official Announcements 的最新动态、热门帖子、悬赏和每周贡献榜。配置了数组则整体
替换这个默认页。

首页是注册过的首页类型（`ingenic-home`）。只有把 `default_homepage` 设为
*Ingenic home page* 时它才出现在 `/`；它自己的地址是 `/ingenic/home`。

---

## 5. 首页卡片与推广

**首页卡片**（Site content → Home cards）是使用 `categories` 区块时首页顶部的卡片。
每张卡片有标题、简介、图片、目标地址和颜色系列；已发布的卡片随站点数据一起发送给
主题。卡片在这里管理而不是直接改版块，是为了让首页可以自行组合、改名或隐藏某个
栏目，而不改变论坛本身的组织结构。

**推广位**（Site content → Promotions）填充右栏以及任何 `promotions` 区块：图片、
标题、一行文字、一个链接，可选结束时间。只发送仍在有效期内的推广；过期的一条自动
消失而不会被删除，因此活动可以提前排期。

**外链按钮**（Site content → External buttons）是画在页脚 **关注我们** 一栏、与合作
平台并排的按钮：图标或上传的图片、目标地址，以及是否显示名称（不显示时名称仍作为
无障碍标签朗读）。目标地址已经在合作平台中出现过的按钮不会重复绘制。

---

## 6. 页脚内容

**Site content → Partner platforms** 和 **Footer columns** 是页脚的两半：

- **合作平台** —— 有两种形态。*链接*会跳转到别处；*二维码*会在页面上方打开一个
  面板显示上传的图片和说明，因为会跳走的二维码比让人看一眼的二维码更难用。
  `icon_only` 只画图片，名称作为无障碍名称。
- **页脚栏目** —— 页脚右侧的若干栏，每栏有标题和一组链接，按位置排序。链接可以是
  站内路径，也可以是站外地址（新标签页打开）。

两处都以语言为先。每一行属于屏幕上方选中的语言，另一种语言是另外一套行：某种语言
下还没有写的页脚条目在该语言下不会出现，而不会回退到另一种语言。

页脚只有存在内容时才绘制 —— 有链接、有栏目，或两者都有。空页脚不会在页面底部留下
一条空带。

---

## 7. 各页面的数据来源

| 页面 | 路由 | 数据来自 |
| --- | --- | --- |
| 首页 | `/` | `ingenic_homepage_blocks`、首页卡片、推广位、主题列表 |
| 在线文档 | `/ingenic/docs/...` | Ingenic → Documentation |
| 下载中心 | `/ingenic/downloads` | Ingenic → Downloads |
| 开发板与样片 | `/ingenic/boards` | Ingenic → Boards |
| 高分悬赏 | `/ingenic/bounties` | 带有悬赏的主题 |
| 积分 | `/ingenic/points` | 积分流水 |
| 每周贡献榜 | `/ingenic/leaderboard` | 贡献分 |
| 热门帖子 | `/ingenic/popular` | 贡献分与点赞 |
| MCP | `/ingenic/mcp` | `mcp_server_enabled` |

上述数据页在 **后台 → Plugins → Ingenic** 下都有入口；没有哪一项需要改文件才能编辑。

---

## 8. 语言

界面提供英文和中文。页头的切换器记录访客的选择；内容语言由 `ingenic_locales` 与
站点的 `default_locale` 决定。

内容级语言由插件负责：公共产品目录中的每一行只属于一种语言。文档版本与页面继承产品
的语言，开发板继承芯片的语言，下载与站点内容行各自带 `locale`。读者只会看到自己所选
语言的内容——不做跨语言回退，因此尚未翻译的条目不会出现，而不是显示另一种语言。

增加第三种界面语言：把 `locales/en.yml` 复制为 `locales/<locale>.yml`，翻译值、保留
键名，并把语言代码加入 `ingenic_locales`。代码必须是 Discourse 已经提供的语言。详见
[README.zh-CN.md](../README.zh-CN.md)。

---

## 9. 颜色与标签

配色分两处：`about.json`（**Ingenic Light** 方案：主色、文字、页头、高亮和语义色）
与 `common/common.scss` 的 `:root` 块（配色方案没有对应槽位的浅色）。该块之外没有
任何地方写颜色，所以整站色调只在这两处修改。

要换主色，改配色方案里的 `tertiary` —— 链接色和填充按钮上的文字色与它同色相，
分别在两侧一档，会随它一起移动。

标签胶囊按 `common.scss` 里的名称列表着色（芯片天蓝、技术主题科技蓝、`solved` 绿色、
`announcement` 红色，其余天蓝）。管理员可以在 **Ingenic → Tag colours** 中覆盖某个
标签的系列，无需发版；指定值优先于名称列表，且不会改变描边、底色、文字和悬停效果。

---

## 10. 新站配置清单

按这个顺序配置，可以避免出现死链：

1. 创建导航指向的论坛版块（Official Announcements、Technical Discussions、
   Open Source 等）。
2. 把 `default_homepage` 设为 Ingenic 首页。
3. 填写 Site content → Home page、Home cards、Footer columns。
4. 检查 `ingenic_nav_items`；内置列表符合预期就清空它。
5. 添加文档产品、下载资源和开发板。
6. 设置主题的 `ingenic_locales` 与站点的 `default_locale`。

---

## 11. 出现问题时

| 现象 | 检查位置 |
| --- | --- |
| 侧边栏有条目 404 | `ingenic_nav_items` 指向了不存在的版块标识或路径 |
| 配置过的导航少了悬赏／积分 | 非空列表会整体替换默认值 —— 手动补上这两行 |
| 首页某个区块不显示 | 类型不在上表中，或它读取的数据为空 |
| 页脚栏目没有链接 | 栏目存在，但链接未发布或为空 |
| 标签配色覆盖无效 | 标签名的大小写或拼写与指定值不一致 |
| 语言切换器没有反应 | `set_locale_from_cookie` 未开启 |
| 主题更新后样式没变 | 重新编译 SCSS 并重启 —— 见 [DEPLOY.zh-CN.md](../DEPLOY.zh-CN.md#3-升级) |
