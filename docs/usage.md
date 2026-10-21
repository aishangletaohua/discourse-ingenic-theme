# Configuring the Ingenic theme

This guide is for the person who runs the forum: which parts of the look are
theme settings, which are plugin screens, and how to change each without a
release.

For member-facing behaviour — the documentation reader, download access levels,
bounties, points — see the plugin's usage guide:
[English](https://github.com/aishangletaohua/discourse-ingenic-plugin/blob/develop/docs/usage.md)
· [中文](https://github.com/aishangletaohua/discourse-ingenic-plugin/blob/develop/docs/usage.zh-CN.md).

中文版：[usage.zh-CN.md](usage.zh-CN.md).

---

## 1. Who owns what

| What you see | Where it is configured |
| --- | --- |
| Sidebar entries (labels, icons, order, visibility) | Plugin setting `ingenic_nav_items` |
| Heading over the developer-resources block | Theme setting `ingenic_nav_title` |
| Home page blocks and their order | Plugin screen **Ingenic → Site content → Home page** (stored in `ingenic_homepage_blocks`) |
| Home cards | Plugin screen **Site content → Home cards** |
| Promotions in the rail | Plugin screen **Site content → Promotions** |
| Footer link columns, social links, external buttons | Plugin screen **Site content → Footer columns / Partner platforms / External buttons** |
| Sidebar width and side, hero title, languages | Theme settings |
| Colours | The **Ingenic Light** colour scheme and the theme's `common.scss` |
| Tag pill colours | Theme defaults, overridable in **Ingenic → Tag colours** |
| Documentation, downloads, boards themselves | The plugin's own admin screens |

The split is deliberate: anything an editor changes week to week lives in the
plugin's database and is editable without touching either repository; anything
that is a design decision lives in the theme and changes with a theme release.

---

## 2. Theme settings

Admin → Customize → Themes → **Ingenic Community** → *Theme settings*, or
Admin → Settings → Themes if the theme is selected there.

| Setting | Default | What it does |
| --- | --- | --- |
| `ingenic_sidebar_width` | `288` | Width in pixels of the desktop navigation sidebar. Values above 288 are capped so the content column keeps its room. |
| `ingenic_sidebar_position` | `left` | `left` or `right`. On narrow screens the sidebar becomes a drawer and this has no effect. |
| `ingenic_nav_order` | `first` | `first` puts the Ingenic navigation above Discourse's own sidebar sections; `last` puts it below them. |
| `ingenic_nav_title` | *(empty)* | Heading over the developer-resources block. Empty reads *Developer Resources* / 开发者资源. |
| `ingenic_hero_title` | *(empty)* | Headline above the home page blocks. Empty reads *Welcome to Ingenic Community* / 欢迎来到 Ingenic 社区. |
| `ingenic_hero_subtitle` | *(empty)* | Optional line under the headline. |
| `ingenic_locales` | `en\|zh_CN` | Languages offered by the header switcher, most-used first. Hidden while fewer than two are listed. |

The language switcher also needs core settings: `allow_user_locale` (on by
default) and `set_locale_from_cookie` (must be on). English is the language a
first-time visitor gets; that is the site's `default_locale`, not a theme
setting.

There is deliberately no setting to show or hide the sidebar, or to collapse it:
Discourse already has both controls, and a second one would fight the one members
know.

---

## 3. The sidebar

Navigation is one JSON setting, `ingenic_nav_items` (Admin → Settings → Plugins,
or the plugin's settings page). Each entry:

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

- `section` is one of three blocks, drawn in this order:
  - `forum` — the plain list at the top (New Post, Home, the forum's sections);
  - `resources` — under the theme's heading (Documentation, Downloads, Boards,
    MCP);
  - `member` — the rows below Topics (Bounties, Points, and the fixed Site
    Feedback / All Categories).
- `position` orders entries **within** their block.
- Use `"category": "technical-discussions"` instead of `href` to point at a
  Discourse category.
- `"external": true` opens in a new tab and is never highlighted as current.
- `"enabled": false` hides an entry without deleting it.

A link stays highlighted for the whole subtree it points at, so
`/ingenic/docs/t32pro/2.1.0/overview` still marks Documentation as active.

**Leaving the setting empty does not mean "no navigation"** — it means "use the
theme's built-in list". That list is static: it replaces, it does not merge. A
site that configured navigation before Bounties existed will not grow a Bounties
row; add it explicitly or clear the setting to fall back to the defaults.

The hover panels on **Technical Discussions** and **Open Source** are drawn by
the theme for those two category rows only. They are not configurable per item;
moving those entries elsewhere removes the panel.

---

## 4. The home page

Admin → Plugins → Ingenic → **Site content → Home page**.

Blocks are a JSON array; the screen adds, removes and reorders them. Each block:

```json
{ "type": "latest", "limit": 8, "layout": "main", "position": 1 }
```

**Types** (an unknown type is skipped, not drawn as an empty box):

| Type | Draws |
| --- | --- |
| `categories` | The forum's top-level sections as cards; `categories` names slugs and their order, `limit` caps how many |
| `latest` | The newest topics, with paging |
| `hot` | The busiest recent topics |
| `popular` | Popular posts in the contribution window (`ingenic_popular_window_days`) |
| `activity` | Recent replies/activity from one category (`category`) |
| `announcements` | Topics from one category (`category`), presented as announcements |
| `discussions` | Topics from one category (`category`) |
| `downloads` | Latest published downloads |
| `boards` | Latest development boards |
| `bounties` | Standing bounties, richest first; draws nothing when there are none |
| `promotions` | The promotions configured under Site content → Promotions |
| `leaderboard` | The weekly contributor table |

**Layout**: `layout` is `full` (across the page), `main` (the left column) or
`side` (the right rail). Left unset, each type has its natural home — the table
above in the theme's source, section cards full width, most lists in the main
column, the short lists in the rail.

Empty `ingenic_homepage_blocks` means "use the theme's default page": section
cards, latest discussions, activity from Official Announcements, popular posts,
bounties and the weekly leaderboard. A configured array replaces that page
whole.

The home page is a registered homepage (`ingenic-home`). It only appears at `/`
while `default_homepage` is set to *Ingenic home page*; its own address is
`/ingenic/home`.

---

## 5. Home cards and promotions

**Home cards** (Site content → Home cards) are the cards at the top of the
home page when the `categories` block is used. Each card carries a title, a
description, a picture, a destination and a colour family; published cards are
sent to the theme with the site payload. Cards are managed here rather than
through the category itself so the front page can group, rename or hide a
section without changing how the forum is organised.

**Promotions** (Site content → Promotions) fill the rail and any `promotions`
block: a picture, a title, a line of text and a link, with an optional end date.
Only live promotions are sent; an expired one disappears without being deleted,
so a campaign can be scheduled in advance.

**External buttons** (Site content → External buttons) are the buttons drawn in
the footer's **Find us** strip beside the partner platforms: an icon or uploaded
picture, a destination, and whether the label is shown or only read aloud. A
button whose destination already appears among the social links is not drawn
twice.

---

## 6. Footer content

**Site content → Partner platforms** and **Footer columns** are the two halves of the footer:

- **Partner platforms** — each is one of two shapes. A *link* opens somewhere; a *QR code*
  opens a panel over the page showing the uploaded image and a caption, because
  a code that navigates is worse than a code that is looked at. `icon_only`
  draws the picture alone, with the label as its accessible name.
- **Footer columns** — the columns on the right of the footer, each with a
  title and a list of links, ordered by position. Links may be internal (a path) or
  external (opens in a new tab). Column titles, link labels and QR captions each
  have an English and a Chinese field.

Both are bilingual field by field: a row with no Chinese spelling falls back to
the English one rather than disappearing, so a half-translated footer still
reads.

The footer is only drawn when there is something in it — links, columns or both.
An empty footer is not an empty band at the foot of the page.

---

## 7. Where each page gets its content

| Page | Route | Data from |
| --- | --- | --- |
| Home | `/` | `ingenic_homepage_blocks`, section cards, promotions, topic lists |
| Documentation | `/ingenic/docs/...` | Ingenic → Documentation |
| Downloads | `/ingenic/downloads` | Ingenic → Downloads |
| Boards & samples | `/ingenic/boards` | Ingenic → Boards |
| Bounties | `/ingenic/bounties` | Topics carrying a bounty |
| Points | `/ingenic/points` | The points ledger |
| Weekly contributors | `/ingenic/leaderboard` | Contribution scores |
| Popular posts | `/ingenic/popular` | Contribution scores and likes |
| MCP | `/ingenic/mcp` | `mcp_server_enabled` |

Each of those data screens has an admin entry under **Admin → Plugins →
Ingenic**; none of them expects content to be edited in a file.

---

## 8. Language

The interface is English and Chinese. The switcher in the header writes the
visitor's choice; content follows `ingenic_locales` and the site's
`default_locale`.

Content-level language is stored by the plugin: documentation pages, downloads
and boards each carry a `locale`, and a page in the reader's language is
preferred, with `ingenic_default_locale` filling the gaps. Footer and social
rows carry English and Chinese spellings in separate fields.

Adding a third interface language: copy `locales/en.yml` to
`locales/<locale>.yml`, translate the values, keep the keys, and add the code to
`ingenic_locales`. The code must be one Discourse already serves. See
[README.md](../README.md#adding-a-language).

---

## 9. Colours and tags

The palette lives in `about.json` (the **Ingenic Light** scheme: accent, text,
header, highlight and the semantic colours) and in the `:root` block of
`common/common.scss` (the tints a colour scheme has no slot for). Nothing
outside that block names a colour, so the shade of the whole theme is edited in
those two places.

To change the accent, edit `tertiary` in the colour scheme — the link colour and
the ink on filled buttons are the same hue one step either side of it and move
with it.

Tag pills are coloured by a name list in `common.scss` (chips sky, technical
subjects violet, `solved` green, `announcement` red, everything else sky). An
administrator can override a tag's family without a release in **Ingenic → Tag
colours**; the assignment wins over the name list and leaves border, tint, ink
and hover untouched.

---

## 10. A configuration checklist

For a new forum, in the order that avoids dead links:

1. Create the forum sections the navigation points at (Official Announcements,
   Technical Discussions, Open Source, …).
2. Set `default_homepage` to the Ingenic home page.
3. Fill in Site content → Home page, Home cards, Partner platforms and Footer columns.
4. Review `ingenic_nav_items`; clear it if the built-in list matches what you
   want.
5. Add documentation products, downloads and boards.
6. Set the theme's `ingenic_locales` and the site's `default_locale`.

---

## 11. If something looks wrong

| Symptom | Where to look |
| --- | --- |
| Sidebar has an entry that 404s | `ingenic_nav_items` points at a category slug or path that does not exist |
| A configured nav list lost Bounties/Points | A non-empty list replaces the defaults — add the rows |
| Home page block missing | Its `type` is not in the table above, or the data it reads is empty |
| Footer column with no links | The column exists but its links are unpublished or empty |
| Tag colour override has no effect | The tag name differs in case or spelling from the assignment |
| Language switcher does nothing | `set_locale_from_cookie` is off |
| Styles unchanged after a theme update | Rebake the SCSS and restart — see [DEPLOY.md](../DEPLOY.md#3-updating) |
