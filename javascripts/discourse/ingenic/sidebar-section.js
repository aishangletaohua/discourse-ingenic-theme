import { themePrefix } from "virtual:theme";
import { service } from "@ember/service";
import getURL from "discourse/lib/get-url";
import { i18n } from "discourse-i18n";
import { hrefFor, resolveNavItems } from "./nav-items";

/**
 * Registers the Ingenic navigation as first-class Discourse sidebar sections.
 *
 * Three of them, because the navigation is three things: the forum itself at
 * the top, the developer resources below it, and what a member has earned or
 * set aside at the bottom. The groups are told apart by the cards the
 * stylesheet draws around them, not by headings: a caption over each group
 * broke the column into separate blocks. The split still matters, because it
 * keeps 高分悬赏 and Points from filing under the resources above them, which
 * is exactly where they do not belong.
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
 * The links that browse the community itself are not a section: they are added
 * to core's community section through `addCommunitySectionLink`, which puts
 * them under Topics and above the More drawer, in registration order.
 *
 * A section with `hideSectionHeader` is always drawn expanded: core returns
 * true from `displaySectionContent` for it, whatever the collapse state says.
 */

// The groups, in the order they are read. None is drawn with a heading; `text`
// is what the sidebar's filter matches.
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
  {
    name: "ingenic-member",
    section: "member",
    titled: false,
    textKey: "ingenic.nav.sections.member",
  },
];

// The links that browse the community itself — MCP, Site Feedback and All
// categories — belong in the community section rather than in a section of
// their own, because that is where core draws Topics and the More drawer. The
// public API appends them to the section's primary links, so they render
// directly under Topics and above More in the order registered here. Core's
// own Categories section, which used to hold two of them behind a repeated
// forum heading, is hidden by the stylesheet.
const communityLinks = [
  {
    key: "mcp",
    icon: "robot",
    labelKey: "ingenic.nav.mcp",
    href: "/ingenic/mcp",
    // The MCP server is core's and is off by default. A link to a page about
    // an endpoint that is not listening would explain something that cannot
    // be used, so the row follows the setting.
    enabled: (siteSettings) => siteSettings.mcp_server_enabled,
  },
  {
    key: "site-feedback",
    icon: "comments",
    labelKey: "ingenic.nav.site_feedback",
    category: "site-feedback",
    enabled: () => true,
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
 * initializer reads as what it is: three groups of the developer navigation,
 * plus the three links that browse the forum.
 */
export function registerIngenicCommunityLinks(api) {
  for (const link of communityLinks) {
    api.addCommunitySectionLink((BaseCommunitySectionLink) => {
      return class extends BaseCommunitySectionLink {
        @service site;

        get name() {
          return link.key;
        }

        get text() {
          return i18n(themePrefix(link.labelKey));
        }

        get title() {
          return this.text;
        }

        get href() {
          const target = link.category
            ? hrefFor({ category: link.category }, this.site)
            : link.href;

          return getURL(target);
        }

        get prefixValue() {
          return link.icon;
        }

        get shouldDisplay() {
          return link.enabled(this.siteSettings);
        }

        // These are plain hrefs with no route behind them, so core has no
        // route to compare against. Match the address instead, with the
        // subtree rule the developer links use: /mcp/something is still MCP.
        get currentWhen() {
          const current = (this.router.currentURL ?? "").split("?")[0];
          const target = link.category
            ? hrefFor({ category: link.category }, this.site)
            : link.href;

          return current === target || current.startsWith(`${target}/`);
        }
      };
    });
  }
}

/**
 * One row of the navigation. Core hands the base class to each registration
 * callback, so the link class is built from it rather than imported.
 */
function makeLinkClass(BaseCustomSidebarSectionLink) {
  return class IngenicSectionLink extends BaseCustomSidebarSectionLink {
    constructor({ item, router }) {
      super(...arguments);

      this.item = item;
      this.router = router;
    }

    get name() {
      return this.item.key;
    }

    // The key goes on the row so the stylesheet can give each module an icon
    // colour of its own; the class does not depend on the label, which an
    // administrator may change.
    get classNames() {
      // A configured key is usually a slug, but nothing stops an administrator
      // from typing spaces or punctuation into one.
      const key = String(this.item.key ?? "").replace(/[^a-z0-9_-]/gi, "-");

      return `ingenic-sidebar-link ingenic-sidebar-link--${key}`;
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
            return resolveNavItems(this.site, group.section).map(
              (item) => new IngenicSectionLink({ item, router: this.router }),
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
