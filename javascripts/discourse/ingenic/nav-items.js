import { themePrefix } from "virtual:theme";
import { i18n } from "discourse-i18n";
import getURL from "discourse/lib/get-url";

// Shipped so the navigation is not empty before the Ingenic team fills in the
// plugin's setting. Anything configured on the plugin side replaces this list
// wholesale rather than merging with it, so order and labels have one owner.
//
// `section` is which of the two Ingenic groups an entry belongs to:
//
//   forum      the plain list at the top — the forum itself, no heading
//   resources  the titled group below it
//
// Bounties and Points are not here: they are community-section links, so they
// can sit in the member block below Topics rather than in a card of their own.
// The third block is core's community section, and the theme orders its rows
// together in the stylesheet.
//
// `href` is used as written; `category` resolves to `/c/<slug>`, which is how an
// entry points at a forum section without the theme having to know category ids.
// The two lists share no heading, so an entry's section is what keeps it out of
// the group above it.
const DEFAULT_ITEMS = [
  // The forum.
  {
    key: "new-post",
    icon: "plus",
    labelKey: "ingenic.nav.new_post",
    // Discourse's own route for "start writing": it opens the composer in
    // place, and asks a signed-out visitor to sign in first. A plain link is
    // enough because that is a real route, not a modal with no address.
    href: "/new-topic",
    section: "forum",
  },
  { key: "home", icon: "house", labelKey: "ingenic.nav.home", href: "/", section: "forum" },
  {
    key: "announcements",
    icon: "bullhorn",
    labelKey: "ingenic.nav.announcements",
    category: "official-announcements",
    section: "forum",
  },
  {
    key: "discussions",
    icon: "comments",
    labelKey: "ingenic.nav.discussions",
    category: "technical-discussions",
    section: "forum",
  },
  // Directly below Technical Discussions, because it is the next section of the
  // forum rather than one of the developer resources. Its own row, with its
  // own hover panel; it is not filed inside Technical Discussions.
  {
    key: "open-source",
    icon: "code",
    labelKey: "ingenic.nav.open_source",
    category: "open-source",
    section: "forum",
  },

  // The developer resources.
  { key: "docs", icon: "book", labelKey: "ingenic.nav.docs", href: "/ingenic/docs", section: "resources" },
  {
    key: "downloads",
    icon: "download",
    labelKey: "ingenic.nav.downloads",
    href: "/ingenic/downloads",
    section: "resources",
  },
  {
    key: "boards",
    icon: "microchip",
    labelKey: "ingenic.nav.boards",
    href: "/ingenic/boards",
    section: "resources",
  },
  // Below Development Boards, because it is another way into the developer
  // material rather than a place in the forum. The MCP server is core's and is
  // off by default, so the row follows the setting; a link to a page about an
  // endpoint that is not listening would explain something that cannot be used.
  {
    key: "mcp",
    icon: "robot",
    labelKey: "ingenic.nav.mcp",
    href: "/ingenic/mcp",
    section: "resources",
    setting: "mcp_server_enabled",
  },
];

// What an entry with no `section` belongs to. Unstated is the plain list at the
// top, which is where a list that says nothing about groups reads as being.
// The server normalises this on its side too, so a configured entry arrives
// carrying the name of its group; this is what the shipped defaults fall back to.
const DEFAULT_SECTION = "forum";

function isExternal(href) {
  return /^https?:\/\//i.test(href) || href.startsWith("//");
}

// A category is addressed the way Discourse addresses one: by its slug *and* its
// id. `/c/open-source` on its own is not a route and answers 404, so an entry
// naming a category is a working link only once the id is in it — which is what
// the site's category list is for.
//
// The list carries no `url` to take, only ids, so the address is built the way
// `Category#url` builds it: every ancestor's slug, then the id. A section two
// levels down is `/c/technical-discussions/t-series/t33/12`, and the whole
// chain is in the same list.
//
// The server resolves a configured entry the same way; this is the shipped
// list's turn, and it is the only place a category entry is written by hand.
//
// Exported because the shipped list names no sub-category, so the branch that
// composes an ancestor path is the one part of this a page load would never
// reach: it is here for an entry an administrator adds as a default, and it is
// checked on its own rather than left to be found by whoever writes that entry.
export function hrefFor(item, site) {
  if (item.href) {
    return item.href;
  }

  if (!item.category) {
    return "";
  }

  const categories = site?.categories || [];
  const category = categories.find(
    (candidate) => candidate.slug === item.category,
  );

  if (!category?.id) {
    // A category this site does not have. Kept as a link rather than dropped,
    // and `rake ingenic:doctor` names it.
    return `/c/${item.category}`;
  }

  const ancestors = [];
  let parent = categories.find(
    (candidate) => candidate.id === category.parent_category_id,
  );

  while (parent) {
    ancestors.unshift(parent.slug);
    const next = parent;
    parent = categories.find(
      (candidate) => candidate.id === next.parent_category_id,
    );
  }

  const path = [...ancestors, category.slug].join("/");

  return `/c/${path}/${category.id}`;
}

/**
 * Turns the configured navigation into the shape the sidebar link needs.
 *
 * Entries come from the plugin's `ingenic_nav_items` site setting, which the
 * site serializer exposes so the Ingenic team can relabel, reorder or hide an
 * entry from the admin UI. The server has already resolved `category` entries
 * into hrefs and dropped entries that could not render a link; this only fills
 * in the same two things for the shipped defaults, which never went through it.
 *
 * @param {object} site the site model, carrying `ingenic_nav_items`
 * @param {string} section which group to return
 * @param {object} siteSettings the site's settings, for rows that follow one
 */
export function resolveNavItems(site, section, siteSettings = null) {
  const configured = site?.ingenic_nav_items;
  const items =
    Array.isArray(configured) && configured.length > 0
      ? configured
      : DEFAULT_ITEMS.map((item) => ({
          key: item.key,
          icon: item.icon,
          label: i18n(themePrefix(item.labelKey)),
          href: hrefFor(item, site),
          section: item.section,
          setting: item.setting,
        }));

  return items
    .filter((item) => item && (item.section ?? DEFAULT_SECTION) === section)
    .map((item) => ({
      key: item.key,
      label: item.label,
      icon: item.icon || "circle",
      // Kept unprefixed: it is matched against router.currentURL to decide
      // whether the link is active, and `url` is what goes in the href.
      href: item.href,
      url: getURL(item.href),
      external: item.external === true || isExternal(item.href),
      // A configured list loses the shipped row's `setting` on the way through
      // the server, so MCP is recognised by its key as well. Other rows have no
      // setting to follow.
      setting: item.setting || (item.key === "mcp" ? "mcp_server_enabled" : null),
    }))
    .filter((item) => item.key && item.label && item.href)
    .filter((item) => !item.setting || siteSettings?.[item.setting] !== false);
}
