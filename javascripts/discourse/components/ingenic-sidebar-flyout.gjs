import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import { service } from "@ember/service";
import getURL from "discourse/lib/get-url";
import dIcon from "discourse/ui-kit/helpers/d-icon";

const PANEL_WIDTH = 268;
// A pointer leaving a row for the panel beside it crosses a few pixels of gap.
// Closing at once would make a diagonal move impossible, so a close is always
// scheduled rather than run; entering the next panel cancels it.
const CLOSE_DELAY = 180;

// The path part of an address without a trailing slash, so a link and a
// category URL that differ only by that slash still match.
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
 * The second level of the sidebar, on hover.
 *
 * Technical Discussions and Open Source both hold sub-categories, and core's
 * sidebar has no way to draw one: a section link is a row, not a tree. This
 * listens to the sidebar rather than replacing it — the rows keep their own
 * click, active state, filter and mobile drawer — and hangs a panel beside the
 * row the pointer is on. Hovering a row in that panel opens the next panel
 * beside it, so a third level is reachable the same way.
 *
 * The panel is rendered from the same category tree the rest of the theme
 * reads, and each row carries the category's own glyph and tint, so the flyout
 * and the category page agree about what a section looks like.
 *
 * Desktop only: on a touch layout there is no hover to follow, and a flyout
 * that needs one would either never open or open on a tap meant for the link.
 * The links themselves still navigate.
 */
export default class IngenicSidebarFlyout extends Component {
  @service site;
  @service capabilities;
  @service router;

  // One entry per open panel, outermost first. Each carries its own fixed
  // position so panels can be placed beside the row that opened them.
  @tracked panels = [];

  // Where the panels are drawn. The sidebar clips its contents at its own
  // edge — the column has a fixed width and a scroll area — so a panel placed
  // in the page at fixed coordinates would be cut off exactly where it is
  // meant to continue. A node beside the sidebar, under <body>, is outside
  // that clip and still inside the page's own stacking order.
  @tracked portalElement = null;

  #portal = null;
  #sidebar = null;
  #closeTimer = null;
  #rootCategoryId = null;
  #routerOff = null;

  get enabled() {
    return !this.capabilities.touch;
  }

  #childrenOf(categoryId) {
    return (this.site?.categories ?? [])
      .filter((category) => category.parent_category_id === categoryId)
      .sort(
        (a, b) =>
          (a.position ?? 0) - (b.position ?? 0) ||
          a.name.localeCompare(b.name, undefined, { sensitivity: "base" }),
      );
  }

  #categoryForLink(link) {
    const path = normalizePath(link?.getAttribute("href"));

    return (
      (this.site?.categories ?? []).find(
        (category) => normalizePath(category.url) === path,
      ) ?? null
    );
  }

  // A row inside a panel. A series is a row with children rather than a row
  // plus an indented list: the chips wait in a panel of their own, so a series
  // with forty chips is one clean row here and a scrollable list beside it,
  // not forty rows that push everything below them out of sight. `category` is
  // kept so hovering the row can build that next panel.
  #rowFor(child) {
    return {
      id: child.id,
      name: child.name,
      url: getURL(child.url),
      icon: child.icon || "comments",
      tintStyle: `--ingenic-category: #${child.color || "0f7fa8"}`,
      hasChildren: this.#childrenOf(child.id).length > 0,
      category: child,
    };
  }

  #panelFor(category, anchorRect) {
    const items = this.#childrenOf(category.id).map((child) =>
      this.#rowFor(child),
    );

    // The height is only needed to keep the panel inside the window; the
    // stylesheet owns the real layout and caps a long list with a scrollbar.
    const estimated = 46 + items.length * 38;
    const maxTop = Math.max(8, window.innerHeight - Math.min(estimated, window.innerHeight - 16) - 8);
    const top = Math.min(Math.max(anchorRect.top - 8, 8), maxTop);
    const left =
      anchorRect.right + 10 + PANEL_WIDTH > window.innerWidth - 8
        ? Math.max(8, anchorRect.left - PANEL_WIDTH - 10)
        : anchorRect.right + 10;

    return {
      key: `panel-${category.id}`,
      title: category.name,
      icon: category.icon || "comments",
      tintStyle: `--ingenic-category: #${category.color || "0f7fa8"}`,
      style: `left: ${left}px; top: ${top}px; width: ${PANEL_WIDTH}px;`,
      items,
    };
  }

  #open(link, category) {
    if (this.#rootCategoryId === category.id) {
      return;
    }

    this.#cancelClose();
    this.#rootCategoryId = category.id;
    this.panels = [this.#panelFor(category, link.getBoundingClientRect())];
  }

  #scheduleClose() {
    this.#cancelClose();
    this.#closeTimer = setTimeout(() => {
      this.#closeTimer = null;
      this.#rootCategoryId = null;
      this.panels = [];
    }, CLOSE_DELAY);
  }

  #cancelClose() {
    if (this.#closeTimer) {
      clearTimeout(this.#closeTimer);
      this.#closeTimer = null;
    }
  }

  #over = (event) => {
    const target = event.target;

    if (!(target instanceof Element)) {
      return;
    }

    // The flyout lives inside the sidebar, so its own hovers reach this
    // listener; they are the panel's business, not a reason to close.
    if (target.closest(".ingenic-sidebar-flyout")) {
      return;
    }

    // Only this theme's own rows open a panel. The listener is on the whole
    // column, so a Discourse-drawn category row would otherwise grow one too —
    // the navigation's two sections are the only place a panel belongs.
    const link = target.closest(".sidebar-section-link.ingenic-sidebar-link");

    if (!link) {
      this.#scheduleClose();
      return;
    }

    const category = this.#categoryForLink(link);

    if (!category || this.#childrenOf(category.id).length === 0) {
      this.#scheduleClose();
      return;
    }

    this.#open(link, category);
  };

  // Leaving the column is the usual way to dismiss the panel. The sidebar's
  // own pointer listener cannot see that: the pointer is already outside it.
  // Crossing the gap into a panel is the one departure that is not a
  // dismissal, and the panel is where the pointer lands.
  #leave = (event) => {
    const next = event.relatedTarget;

    if (next instanceof Element && next.closest(".ingenic-sidebar-flyout")) {
      return;
    }

    this.#scheduleClose();
  };

  // Scrolling the column moves the row out from under a panel that was placed
  // against it. The panel is fixed, so it would stay where it was placed while
  // the row it describes travelled; closing is the truthful answer.
  #scroll = () => {
    if (this.panels.length) {
      this.close();
    }
  };

  #focus = (event) => {
    const target = event.target;

    if (!(target instanceof Element)) {
      return;
    }

    const link = target.closest(".sidebar-section-link.ingenic-sidebar-link");
    const category = link && this.#categoryForLink(link);

    if (category && this.#childrenOf(category.id).length) {
      this.#open(link, category);
    }
  };

  #key = (event) => {
    if (event.key === "Escape" && this.panels.length) {
      this.close();
    }
  };

  @action
  setup(element) {
    if (!this.enabled) {
      return;
    }

    // The outlet is drawn twice: once in the desktop sidebar and once inside
    // the mobile hamburger's copy of the sections. Only the first is a place a
    // pointer can hover, and attaching to the drawer as well would open two
    // panels for one hover.
    this.#sidebar = element.closest("#d-sidebar");

    if (!this.#sidebar) {
      return;
    }

    this.#sidebar.addEventListener("mouseover", this.#over);
    this.#sidebar.addEventListener("mouseleave", this.#leave);
    this.#sidebar.addEventListener("focusin", this.#focus);
    this.#sidebar.addEventListener("scroll", this.#scroll, { passive: true });
    document.addEventListener("keydown", this.#key);

    // Follow the page rather than the pointer: a row that navigates takes the
    // panel with it otherwise, and the panel would sit over the next page
    // until the pointer happened to cross the sidebar again.
    this.#routerOff = this.router.on("routeDidChange", this.close);

    this.#portal = document.createElement("div");
    this.#portal.className = "ingenic-sidebar-flyout-portal";
    document.body.append(this.#portal);
    this.portalElement = this.#portal;
  }

  // The sidebar outlives this component only on a full teardown, but the
  // listeners are on it and on the document, so they are taken off here.
  willDestroy() {
    super.willDestroy(...arguments);
    this.#cancelClose();
    this.#sidebar?.removeEventListener("mouseover", this.#over);
    this.#sidebar?.removeEventListener("mouseleave", this.#leave);
    this.#sidebar?.removeEventListener("focusin", this.#focus);
    this.#sidebar?.removeEventListener("scroll", this.#scroll);
    document.removeEventListener("keydown", this.#key);

    // `router.on` has returned a plain unsubscribe function for a long time,
    // but not every Ember build does: some hand back a subscription object.
    // Calling it blind throws on teardown, which is the one moment there is
    // nothing left to catch the error.
    if (typeof this.#routerOff === "function") {
      this.#routerOff();
    } else {
      this.#routerOff?.unsubscribe?.();
    }

    this.#portal?.remove();
    this.#sidebar = null;
    this.#portal = null;
    this.portalElement = null;
  }

  @action
  keepOpen() {
    this.#cancelClose();
  }

  @action
  leavePanel(event) {
    const next = event.relatedTarget;

    // Moving between two panels is one movement through the tree, not a
    // departure from it.
    if (next instanceof Element && next.closest(".ingenic-sidebar-flyout")) {
      return;
    }

    this.#scheduleClose();
  }

  // A row with children opens the next panel beside the one it is in, anchored
  // to the row itself. A row without children only tidies any panel left open
  // deeper than the one being read.
  @action
  hoverRow(panelIndex, row, event) {
    this.#cancelClose();

    const kept = this.panels.slice(0, panelIndex + 1);
    const anchor = event?.currentTarget;

    if (!row.hasChildren || !anchor) {
      if (kept.length !== this.panels.length) {
        this.panels = kept;
      }
      return;
    }

    const existing = this.panels[panelIndex + 1];
    const next = this.#panelFor(row.category, anchor.getBoundingClientRect());

    // The pointer moving within the row fires this more than once. Rebuilding
    // the panel on each firing would restart its entry animation and reset a
    // list the reader may already be scrolling, so an already-correct next
    // panel is kept and only anything below it is dropped.
    if (existing?.key === next.key) {
      if (kept.length + 1 !== this.panels.length) {
        this.panels = this.panels.slice(0, panelIndex + 2);
      }
      return;
    }

    this.panels = [...kept, next];
  }

  @action
  close() {
    this.#cancelClose();
    this.#rootCategoryId = null;
    this.panels = [];
  }

  @action
  checkFocusOut(event) {
    const next = event.relatedTarget;

    if (
      next instanceof Element &&
      (next.closest(".ingenic-sidebar-flyout") ||
        next.closest(".sidebar-section-link"))
    ) {
      return;
    }

    this.#scheduleClose();
  }

  <template>
    <div
      class="ingenic-sidebar-flyout-root"
      {{didInsert this.setup}}
      {{on "focusout" this.checkFocusOut}}
    >
      {{#if this.portalElement}}
        {{#in-element this.portalElement}}
          {{#if this.panels.length}}
            <div class="ingenic-sidebar-flyout">
              {{#each this.panels as |panel index|}}
                <div
                  class="ingenic-sidebar-flyout__panel"
                  style={{panel.style}}
                  {{on "mouseenter" this.keepOpen}}
                  {{on "mouseleave" this.leavePanel}}
                  {{on "focusin" this.keepOpen}}
                  {{on "focusout" this.checkFocusOut}}
                >
                  <p class="ingenic-sidebar-flyout__title">
                    <span
                      class="ingenic-sidebar-flyout__title-icon"
                      style={{panel.tintStyle}}
                      aria-hidden="true"
                    >{{dIcon panel.icon}}</span>
                    {{panel.title}}
                  </p>

                  <ul class="ingenic-sidebar-flyout__list">
                    {{#each panel.items as |row|}}
                      <li>
                        <a
                          class="ingenic-sidebar-flyout__row
                            {{if
                              row.hasChildren
                              'ingenic-sidebar-flyout__row--children'
                            }}"
                          href={{row.url}}
                          style={{row.tintStyle}}
                          aria-haspopup={{if row.hasChildren "menu"}}
                          {{on "mouseenter" (fn this.hoverRow index row)}}
                          {{on "focus" (fn this.hoverRow index row)}}
                          {{on "click" this.close}}
                        >
                          <span
                            class="ingenic-sidebar-flyout__row-icon"
                            aria-hidden="true"
                          >{{dIcon row.icon}}</span>
                          <span class="ingenic-sidebar-flyout__row-name">
                            {{row.name}}
                          </span>
                          {{#if row.hasChildren}}
                            <span
                              class="ingenic-sidebar-flyout__chevron"
                              aria-hidden="true"
                            >{{dIcon "chevron-right"}}</span>
                          {{/if}}
                        </a>
                      </li>
                    {{/each}}
                  </ul>
                </div>
              {{/each}}
            </div>
          {{/if}}
        {{/in-element}}
      {{/if}}
    </div>
  </template>
}
