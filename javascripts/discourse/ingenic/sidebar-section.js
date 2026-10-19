import { themePrefix } from "virtual:theme";
import { service } from "@ember/service";
import getURL from "discourse/lib/get-url";
import { i18n } from "discourse-i18n";
import { hrefFor, resolveNavItems } from "./nav-items";

/**
 * Registers the Ingenic navigation as first-class Discourse sidebar sections.
 *
 * The column reads as three blocks: the forum at the top, the developer
 * resources below it, and the member block at the bottom. Only the first two
 * are sections of their own. The third is core's community section, which
 * already holds Topics and the More drawer; the theme adds the rows that
 * belong around them and orders the whole block in the stylesheet.
 *
 * The blocks are told apart by the cards the stylesheet draws around them, not
 * by headings: a caption over each block broke the column into separate pages.
 * The split still matters, because it keeps 高分悬赏 and Points from filing
 * under the developer resources above them, which is exactly where they do not
 * belong.
 *
 * Rendering a bare <nav> into a plugin outlet looks similar but is not the same
 * thing: it would sit beside Discourse's own sidebar rather than inside it, so
 * it would miss the mobile drawer, the section filter, the collapse state and
 * the active-link handling that core already implements. Going through the
 * public API keeps all of that and leaves no private surface to maintain.
 *
 * Sections draw in the order they were registered, and core draws its own
 * sections around ours (categories, tags, the user's own sections, the filter
 * box). Where this block sits relative to those is therefore the stylesheet's
 * decision, not a matter of registration order — see `ingenic_nav_order`.
 *
 * A section with `hideSectionHeader` is always drawn expanded: core returns
 * true from `displaySectionContent` for it, whatever the collapse state says.
 */

// The groups, in the order they are read. Neither is drawn with a heading;
// `text` is what the sidebar's filter matches.
const GROUPS = [
  {
    name: "ingenic-forum",
    section: "forum",
    titled: false,
    textKey: "ingenic.nav.sections.forum",
  },
  {
    name: "ingenic-resources",
    section: "resources",
    titled: false,
    // An administrator's own words for the group, falling back to the theme's.
    textKey: "ingenic.nav.title",
    textSetting: "ingenic_nav_title",
  },
];

// The third block: Site Feedback, Topics, Bounties, Points, All Categories,
// More. Topics and More are core's, drawn inside its community section, and
// the public API can only append to that section — so registration order here
// is not the order the block reads in. The stylesheet gives each row its place
// with `order`; this list only has to contain the four that are ours.
//
// Site Feedback is a category rather than a page of its own, and it is above
// Topics because it is a place in the forum rather than a view of it. Bounties
// and Points stay configurable through the plugin's navigation setting, which
// is why they are looked up there before falling back to the shipped labels.
// Core's own Categories section, which used to hold two of these behind a
// repeated forum heading, is hidden by the stylesheet.
const communityLinks = [
  {
    key: "site-feedback",
    // The same glyph the section carries on its own page, from the shared
    // marks table; a name should not change its icon between two rows.
    icon: "comment-dots",
    labelKey: "ingenic.nav.site_feedback",
    category: "site-feedback",
    enabled: () => true,
  },
  {
    key: "bounties",
    icon: "gift",
    labelKey: "ingenic.nav.bounties",
    href: "/ingenic/bounties",
    enabled: () => true,
    configured: true,
  },
  {
    key: "points",
    icon: "star",
    labelKey: "ingenic.nav.points",
    href: "/ingenic/points",
    enabled: () => true,
    configured: true,
  },
  {
    key: "all-categories",
    icon: "list",
    labelKey: "ingenic.nav.all_categories",
    href: "/categories",
    enabled: () => true,
  },
];

/**
 * Registers the community links. Separate from the sections above so the
 * initializer reads as what it is: two groups of the developer navigation,
 * plus the four rows that complete the member block.
 */
export function registerIngenicCommunityLinks(api) {
  for (const link of communityLinks) {
    api.addCommunitySectionLink((BaseCommunitySectionLink) => {
      return class extends BaseCommunitySectionLink {
        @service site;

        // A row an administrator has moved, relabelled or re-iconed through
        // the plugin's navigation setting. The setting replaces the shipped
        // list wholesale, so a site that has configured it is read here rather
        // than ignored; a site that has not keeps the labels above.
        get configured() {
          if (!link.configured) {
            return null;
          }

          const items = this.site?.ingenic_nav_items;

          return Array.isArray(items)
            ? items.find((item) => item.key === link.key)
            : null;
        }

        get name() {
          return link.key;
        }

        get text() {
          return this.configured?.label || i18n(themePrefix(link.labelKey));
        }

        get title() {
          return this.text;
        }

        get href() {
          if (this.configured?.href) {
            return getURL(this.configured.href);
          }

          const target = link.category
            ? hrefFor({ category: link.category }, this.site)
            : link.href;

          return getURL(target);
        }

        get prefixValue() {
          return this.configured?.icon || link.icon;
        }

        get shouldDisplay() {
          // A configured list replaces the shipped one, so an entry it does
          // not carry is gone rather than reintroduced from the defaults.
          const items = this.site?.ingenic_nav_items;

          if (
            link.configured &&
            Array.isArray(items) &&
            items.length > 0 &&
            !this.configured
          ) {
            return false;
          }

          return link.enabled(this.siteSettings);
        }

        // These are plain hrefs with no route behind them, so core has no
        // route to compare against. Match the address instead, with the
        // subtree rule the developer links use: /docs/something is still a
        // documentation row.
        get currentWhen() {
          const current = (this.router.currentURL ?? "").split("?")[0];
          const target =
            this.configured?.href ||
            (link.category
              ? hrefFor({ category: link.category }, this.site)
              : link.href);

          return current === target || current.startsWith(`${target}/`);
        }
      };
    });
  }
}

// The path part of an address, without a trailing slash, so `/c/open-source/7`
// and `/c/open-source/7/` are the same destination.
function normalizePath(url) {
  if (!url) {
    return "";
  }

  try {
    return new URL(url, window.location.origin).pathname.replace(/\/+$/, "");
  } catch {
    return String(url).replace(/\/+$/, "");
  }
}

/**
 * One row of the navigation. Core hands the base class to each registration
 * callback, so the link class is built from it rather than imported.
 */
function makeLinkClass(BaseCustomSidebarSectionLink) {
  return class IngenicSectionLink extends BaseCustomSidebarSectionLink {
    // The site is handed in rather than injected: core instantiates these
    // links itself, but the section above builds them with `new`, and `new` on
    // a plain class has no owner for `@service` to look the service up on.
    constructor({ item, router, site }) {
      super(...arguments);

      this.item = item;
      this.router = router;
      this.site = site;
    }

    get name() {
      return this.item.key;
    }

    // The category a row points at, when it points at one. A row is a plain
    // href, so the address is the only thing tying it to the category tree.
    get category() {
      const path = normalizePath(this.item.href);

      return (
        (this.site?.categories ?? []).find(
          (candidate) => normalizePath(candidate.url) === path,
        ) ?? null
      );
    }

    // Whether the row has another level under it. The flyout component reads
    // the same tree; this is only what marks the row as a parent.
    get hasChildren() {
      const category = this.category;

      return (
        !!category &&
        (this.site?.categories ?? []).some(
          (candidate) => candidate.parent_category_id === category.id,
        )
      );
    }

    // The key goes on the row so the stylesheet can give each module an icon
    // colour of its own; the class does not depend on the label, which an
    // administrator may change.
    get classNames() {
      // A configured key is usually a slug, but nothing stops an administrator
      // from typing spaces or punctuation into one.
      const key = String(this.item.key ?? "").replace(/[^a-z0-9_-]/gi, "-");

      return [
        "ingenic-sidebar-link",
        `ingenic-sidebar-link--${key}`,
        this.hasChildren && "ingenic-sidebar-link--children",
      ]
        .filter(Boolean)
        .join(" ");
    }

    get text() {
      return this.item.label;
    }

    get title() {
      return this.item.label;
    }

    get href() {
      return this.item.url;
    }

    get prefixType() {
      return "icon";
    }

    get prefixValue() {
      return this.item.icon;
    }

    get keywords() {
      return { navigation: [this.item.label] };
    }

    // A link counts as active for the whole subtree it points at, so someone
    // reading /ingenic/docs/t-series/t33/1.0/overview still sees Documentation
    // highlighted. Core's own comparison is exact, and these links are plain
    // URLs with no route behind them, so the decision is made here instead —
    // `isActiveLink` honours a boolean `currentWhen` first. Reading
    // router.currentURL is what keeps this tracked, so it updates as you move.
    get currentWhen() {
      if (this.item.external) {
        return false;
      }

      const current = (this.router.currentURL ?? "").split("?")[0];
      const target = this.item.href;

      if (target === "/") {
        return current === "/";
      }

      return current === target || current.startsWith(`${target}/`);
    }
  };
}

export function registerIngenicSidebarSections(api) {
  for (const group of GROUPS) {
    api.addSidebarSection(
      (BaseCustomSidebarSection, BaseCustomSidebarSectionLink) => {
        const IngenicSectionLink = makeLinkClass(BaseCustomSidebarSectionLink);

        return class extends BaseCustomSidebarSection {
          @service router;
          @service site;
          @service siteSettings;

          get name() {
            return group.name;
          }

          get title() {
            return this.text;
          }

          get text() {
            const configured = group.textSetting
              ? settings[group.textSetting]
              : null;

            return configured || i18n(themePrefix(group.textKey));
          }

          get hideSectionHeader() {
            return !group.titled;
          }

          get links() {
            return resolveNavItems(
              this.site,
              group.section,
              this.siteSettings,
            ).map(
              (item) =>
                new IngenicSectionLink({
                  item,
                  router: this.router,
                  site: this.site,
                }),
            );
          }

          get displaySection() {
            return this.links.length > 0;
          }
        };
      },
    );
  }
}
