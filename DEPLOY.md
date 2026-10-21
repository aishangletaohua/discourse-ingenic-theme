# Deploying the Ingenic theme

The theme is one of two repositories that make the forum:

| Repository | What it is | How it installs |
| --- | --- | --- |
| [`discourse-ingenic-plugin`](https://github.com/aishangletaohua/discourse-ingenic-plugin) | Rails plugin — documentation, downloads, boards, points, bounties, admin screens | cloned into `plugins/`, then a rebuild |
| `discourse-ingenic-theme` (this one) | Theme — sidebar, homepage, documentation reader, downloads, boards, footer, MCP page, assistant | installed from its git URL, no rebuild |

Install the plugin first. The theme draws the pages the plugin serves; without
the plugin those routes do not exist and the theme falls back to core's layout.

Target: Discourse `2026.10.0-latest`, the version both pieces were developed
and verified against.

中文版：[DEPLOY.zh-CN.md](DEPLOY.zh-CN.md).

---

## Branches

| Branch | What it holds |
| --- | --- |
| `develop` | The current version. All work lands here; this is what a forum installs and tracks. |
| `main` | Reserved for formal releases. Between releases it carries only a short note, so it is deliberately **not** the branch to install from. |

The repository's default branch is `develop`. A clone with no `--branch` gets
the current version; a pin to `main` gets a note and no theme, because releases
are cut onto it only when one is ready.

---

## 1. Install

### Through the admin UI (recommended)

**Admin → Customize → Themes → Install → From a git repository**

- Repository URL: `https://github.com/aishangletaohua/discourse-ingenic-theme.git`
- Branch: `develop`
- Leave *Private* off; the repository is public.

### From the Rails console

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

`create_from_git_url` needs outbound HTTPS from the container to GitHub. On a
network that cannot reach it, install a downloaded copy instead: zip the
repository's contents (the files at the top level, not the enclosing folder),
then **Admin → Customize → Themes → Install → From your device**.

### If a theme called Ingenic Community already exists

Re-installing creates a second copy rather than updating the first. Update the
existing theme instead — see [Updating](#3-updating).

---

## 2. Turn it on

After the theme is installed:

1. **Make it the default theme.** Admin → Customize → Themes → the theme's menu
   → *Set as default*. A site can also offer it as a user-selectable theme; the
   default is what signed-out visitors see.
2. **Select the colour scheme.** The theme ships **Ingenic Light** (defined in
   `about.json`). Pick it in the theme's settings — Admin → Customize → Themes →
   the theme → *Color Palette*. The light sky palette is the one the layout was
   designed for; other schemes work but the contrast notes in
   [README.md](README.md#colours) no longer apply to them.
3. **Set the front page.** Admin → Settings → Interface → `default_homepage` →
   *Ingenic home page* (stored as `ingenic-home`). The option appears only while
   the plugin is enabled.
4. **Turn on the language switcher** (optional, for a bilingual forum):
   - `allow_user_locale` — on by default in Discourse.
   - `set_locale_from_cookie` — must be on, or a signed-out visitor's choice is
     written to a cookie the server never reads back.
   Then list the languages in the theme setting `ingenic_locales`, e.g.
   `en|zh_CN`.
5. **Optional pages**:
   - `mcp_server_enabled` (Admin → Settings → MCP) — shows the MCP page and its
     sidebar link.
   - `ai_bot_enabled` (from `discourse-ai`) — shows the floating assistant.

Nothing here changes how members sign in. Google, GitHub and email login stay
exactly as the site already has them.

---

## 3. Updating

### Admin UI

Admin → Customize → Themes → the theme → **Check for updates** → **Update**.
Discourse fetches `develop` and installs what changed.

### Rails console

```ruby
theme = Theme.find_by(name: "Ingenic Community")
theme.remote_theme.update_from_remote
```

### After an update

- **Hard-refresh the browser** (Ctrl/Cmd+Shift+R). The theme's JavaScript is
  fingerprinted; a cached document can keep pointing at the old bundle for one
  page load.
- **If a stylesheet change does not appear**, rebake the theme's SCSS and
  restart the app:

  ```ruby
  theme = Theme.find_by(name: "Ingenic Community")
  theme.theme_fields.where(name: "common").each { |f| f.invalidate_baked!; f.ensure_baked! }
  ```

  ```bash
  cd /var/discourse
  ./launcher restart app
  ```

  In development (`bin/pitchfork`) the same staleness shows up as an unchanged
  page after a theme edit; restarting the server clears it.

Theme updates never touch the database. Content — documentation, downloads,
boards, footer links — lives in the plugin's tables and is unaffected.

---

## 4. Verify

A fresh install is working when, on the front page:

- the Ingenic sidebar is present with the developer-resources block;
- the front page is the Ingenic home (section cards, latest discussions, the
  weekly contributors rail) rather than core's topic list;
- `/ingenic/docs`, `/ingenic/downloads` and `/ingenic/boards` open the reader,
  the catalogue and the board pages;
- the footer is at the foot of the page with its link columns.

If the sidebar and footer are missing but the forum itself works, the theme is
not the active theme. If `/ingenic/...` returns 404, the plugin is not loaded.

A short command-line check, run against a signed-out browser:

```bash
curl -s http://<host>/ | grep -c "ingenic-sidebar"
curl -s -o /dev/null -w "%{http_code}\n" http://<host>/ingenic/docs
```

---

## 5. Rollback

The theme is a presentation layer; rolling it back does not lose content.

- **To the previous theme:** Admin → Customize → Themes → set the other theme as
  default. The Ingenic theme stays installed and can be switched back.
- **To the previous theme version:** the theme's git history is the record.
  Check out the commit you want, zip the files at the repository root and
  install them as a second theme with **Install → From your device**, then make
  that the default. Keep the git-installed theme installed but not default.
- **To core's look entirely:** uninstall or unset the theme. The plugin keeps
  serving `/ingenic/*` pages, but they render without the theme's components.

---

## 6. Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| Front page is core's topic list | `default_homepage` not set, or the plugin is off | Set it to *Ingenic home page* |
| `/ingenic/docs` 404 | Plugin not installed or not loaded | Install the plugin, rebuild |
| Sidebar/ footer missing | Theme not active | Set it as default |
| Footer shows no link columns | The plugin's *Site content → Footer columns* is empty or unpublished | Fill it in Admin → Plugins → Ingenic → Site content |
| Language switcher absent | `ingenic_locales` lists fewer than two locales, or `set_locale_from_cookie` is off | See *Turn it on* |
| A changed style is not visible | Baked SCSS is stale | Rebake and restart, above |
| Images from `forum.ingenic.com` do not load | The picture was uploaded on another host and hotlinking is blocked | Upload the picture on this site, or point at a reachable URL |
| MCP row missing | `mcp_server_enabled` is off | Turn it on, or accept the row being hidden |
| Assistant button missing | `ai_bot_enabled` is off or `discourse-ai` is absent | Install/enable the plugin |

Logs:

```bash
cd /var/discourse
./launcher logs app | tail -100
```

Theme compilation errors appear in the browser console as well; the theme's
JavaScript is loaded as a single bundle, so one syntax error blanks every
component the theme draws.

---

## 7. What this deployment does not do

- It does not create forum categories, groups or permissions. Those are the
  plugin's deployment steps — see the plugin's
  [DEPLOY.md](https://github.com/aishangletaohua/discourse-ingenic-plugin/blob/develop/DEPLOY.md).
- It does not seed content. Documentation, downloads and board cards are added
  through the plugin's admin screens.
- It does not touch mail, OAuth, backups or `app.yml`.
