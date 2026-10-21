# Ingenic 主题部署

组成论坛的是两个仓库：

| 仓库 | 是什么 | 如何安装 |
| --- | --- | --- |
| [`discourse-ingenic-plugin`](https://github.com/aishangletaohua/discourse-ingenic-plugin) | Rails 插件 —— 在线文档、下载、开发板、积分、悬赏、后台管理页 | 克隆到 `plugins/`，然后重建 |
| `discourse-ingenic-theme`（本仓库） | 主题 —— 侧边栏、首页、文档阅读器、下载、开发板、页脚、MCP 页、AI 助手 | 从 Git 地址安装，无需重建 |

请先安装插件。主题绘制的是插件提供的页面；没有插件，这些路由不存在，主题会退回
Discourse 原生布局。

目标版本：Discourse `2026.10.0-latest`，两部分都在该版本上开发和验证。

English: [DEPLOY.md](DEPLOY.md).

---

## 分支说明

| 分支 | 内容 |
| --- | --- |
| `develop` | 当前版本。所有工作提交到这里；论坛安装并跟踪的也是这个分支。 |
| `main` | 留给正式版本。两次发布之间保持为空，因此**不要**从这里安装。 |

仓库的默认分支是 `develop`。不带 `--branch` 的克隆拿到的是当前版本；指向 `main`
则拿不到任何文件，因为 `main` 要等发布时才写入。

---

## 1. 安装

### 通过后台（推荐）

**后台 → Customize → Themes → Install → From a git repository**

- Repository URL：`https://github.com/aishangletaohua/discourse-ingenic-theme.git`
- Branch：`develop`
- *Private* 保持关闭；仓库是公开的。

### 通过 Rails 控制台

```bash
cd /var/discourse
./launcher enter app
rails c
```

```ruby
Theme.create_from_git_url(
  url: "https://github.com/aishangletaohua/discourse-ingenic-theme.git",
  branch: "develop"
)
```

`create_from_git_url` 需要容器能通过 HTTPS 访问 GitHub。无法访问时，改用文件安装：
把仓库根目录下的文件打成一个 zip（不要连外层文件夹一起打包），然后
**后台 → Customize → Themes → Install → From your device**。

### 如果已经有名为 Ingenic Community 的主题

重复安装会新建一份，而不是更新原有的那份。请更新已有主题，见
[升级](#3-升级)。

---

## 2. 启用

主题安装完成后：

1. **设为默认主题。** 后台 → Customize → Themes → 该主题菜单 → *Set as default*。
   也可以同时开放为会员可选主题；默认主题决定未登录访客看到什么。
2. **选择配色。** 主题自带 **Ingenic Light**（定义在 `about.json`）。在主题设置里
   选中它 —— 后台 → Customize → Themes → 该主题 → *Color Palette*。浅天蓝配色是
   版式设计所依据的配色；其他配色可以使用，但 [README.zh-CN.md](README.zh-CN.md)
   里关于对比度的说明不再适用。
3. **设置首页。** 后台 → Settings → Interface → `default_homepage` → *Ingenic home
   page*（存储值为 `ingenic-home`）。该选项只在插件启用时出现。
4. **打开语言切换器**（双语论坛需要）：
   - `allow_user_locale` —— Discourse 默认已开启。
   - `set_locale_from_cookie` —— 必须开启，否则未登录访客的选择只写进 cookie，
     服务端不会读回。
   然后在主题设置 `ingenic_locales` 中列出语言，例如 `en|zh_CN`。
5. **可选页面**：
   - `mcp_server_enabled`（后台 → Settings → MCP）—— 显示 MCP 页及其侧边栏入口。
   - `ai_bot_enabled`（来自 `discourse-ai`）—— 显示右下角悬浮助手。

以上操作都不会改变会员的登录方式。Google、GitHub、邮件登录保持站点原有配置。

---

## 3. 升级

### 后台

后台 → Customize → Themes → 该主题 → **Check for updates** → **Update**。
Discourse 会拉取 `develop` 并安装有变化的部分。

### Rails 控制台

```ruby
theme = Theme.find_by(name: "Ingenic Community")
theme.remote_theme.update_from_remote
```

### 升级之后

- **强制刷新浏览器**（Ctrl/Cmd+Shift+R）。主题的 JavaScript 带指纹，缓存中的页面
  可能还会指向旧包一次。
- **样式改动没有生效时**，重新编译该主题的 SCSS 并重启应用：

  ```ruby
  theme = Theme.find_by(name: "Ingenic Community")
  theme.theme_fields.where(name: "common").each { |f| f.invalidate_baked!; f.ensure_baked! }
  ```

  ```bash
  cd /var/discourse
  ./launcher restart app
  ```

  在开发环境（`bin/pitchfork`）里，同样的现象是改完主题后页面不变；重启服务即可。

主题升级不会改动数据库。内容 —— 文档、下载、开发板、页脚链接 —— 都在插件的表里，
不受影响。

---

## 4. 验收

新装完成后，首页应当：

- 出现 Ingenic 侧边栏，并带有开发者资源分组；
- 首页是 Ingenic 首页（栏目卡片、最新讨论、右侧每周贡献榜），而不是原生主题列表；
- `/ingenic/docs`、`/ingenic/downloads`、`/ingenic/boards` 分别打开文档阅读器、
  下载目录和开发板页面；
- 页脚在页面底部，带可编辑的链接栏目。

侧边栏和页脚都不见了、但论坛本身正常，说明主题没有启用。`/ingenic/...` 返回 404，
说明插件没有加载。

用未登录浏览器做一次简单检查：

```bash
curl -s http://<host>/ | grep -c "ingenic-sidebar"
curl -s -o /dev/null -w "%{http_code}\n" http://<host>/ingenic/docs
```

---

## 5. 回滚

主题是表现层，回滚不会丢内容。

- **退回上一个主题：** 后台 → Customize → Themes → 把另一个主题设为默认。Ingenic
  主题仍保留，随时可以切回。
- **退回上一个主题版本：** Git 历史就是版本记录。检出想要的那次提交，把仓库根目录
  的文件打成 zip，用 **Install → From your device** 装成第二个主题，再把它设为默认。
  Git 安装的那份保留但不再默认即可。
- **完全退回原生外观：** 卸载或取消该主题。插件仍会提供 `/ingenic/*` 页面，只是不带
  主题组件渲染。

---

## 6. 排错

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| 首页是原生主题列表 | 未设置 `default_homepage`，或插件未启用 | 设为 *Ingenic home page* |
| `/ingenic/docs` 404 | 插件未安装或未加载 | 安装插件并重建 |
| 侧边栏／页脚不出现 | 主题未启用 | 设为默认主题 |
| 页脚没有链接栏目 | 插件的 *Site content → Footer columns* 为空或未发布 | 在后台 → Plugins → Ingenic → Site content 填写 |
| 没有语言切换器 | `ingenic_locales` 少于两种语言，或 `set_locale_from_cookie` 未开 | 见“启用” |
| 改了样式看不到 | 编译后的 SCSS 未失效 | 重新编译并重启，见上 |
| `forum.ingenic.com` 的图片不显示 | 图片是在另一个站点上传的，且禁止外链 | 在本站重新上传，或改用可访问的地址 |
| 侧边栏没有 MCP | `mcp_server_enabled` 关闭 | 打开它，或接受该行隐藏 |
| 没有助手按钮 | `ai_bot_enabled` 关闭或未安装 `discourse-ai` | 安装／启用插件 |

日志：

```bash
cd /var/discourse
./launcher logs app | tail -100
```

主题编译错误也会出现在浏览器控制台；主题的 JavaScript 打成一个包，一处语法错误会
让主题绘制的所有组件一起空白。

---

## 7. 本部署不做什么

- 不创建论坛分类、用户组或权限。这些属于插件的部署步骤 —— 见插件的
  [DEPLOY.zh-CN.md](https://github.com/aishangletaohua/discourse-ingenic-plugin/blob/develop/DEPLOY.zh-CN.md)。
- 不初始化内容。文档、下载和开发板卡片都通过插件的后台页面添加。
- 不碰邮件、OAuth、备份或 `app.yml`。
