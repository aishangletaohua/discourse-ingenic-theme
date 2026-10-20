import { themePrefix } from "virtual:theme";
import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { trustHTML } from "@ember/template";
import { action } from "@ember/object";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";
import getURL from "discourse/lib/get-url";

const ENDPOINT = "/ingenic/boards";

/**
 * Development board and sample chip catalogue.
 *
 * These are applied for or bought from the Ingenic team, so this page sells
 * nothing and takes no orders: every card ends in a link that leaves the forum.
 *
 * The filters are three levels, drawn like the download centre's: the kind of
 * thing — a board or a sample — then the series, then the chip inside that
 * series. A level with nothing behind it is not drawn, so a catalogue whose
 * boards share one series does not spend a row on a control that cannot
 * narrow anything. Words rather than selects, because the rows are short
 * enough to read at once and a visitor should see what the catalogue holds
 * before choosing anything.
 *
 * Everything is loaded once and filtered here. A catalogue is a handful of
 * rows, and a filter that asks the server again on every click makes the
 * control feel slower than the page it is filtering; the first load is the
 * only network cost.
 *
 * A card is a shop window: picture, name, a short introduction, and the two
 * links. Everything longer — the full description and the specifications —
 * is in the dialog the card opens, so the grid stays the same height whatever
 * was written for each item.
 */
export default class IngenicBoards extends Component {
  @tracked boards = [];
  @tracked filters = { kinds: ["board", "sample"] };
  @tracked kind = "board";
  @tracked series = "";
  @tracked chip = "";
  @tracked selected = null;
  @tracked loading = true;

  // One request, guarded so a second load (the component can be rebuilt by a
  // route) does not replace the list while the first is still in flight.
  requestId = 0;

  get kindTabs() {
    const kinds = this.filters.kinds?.length
      ? this.filters.kinds
      : ["board", "sample"];

    return kinds.map((kind) => ({
      kind,
      label: i18n(themePrefix(`ingenic.boards.kind_${kind}`)),
      active: kind === this.kind,
    }));
  }

  // The default tab's boards, which the two lower rows narrow. The rows are
  // built from these rather than from the whole product tree: an option that
  // has nothing behind it is a control that can only produce an empty page.
  get kindBoards() {
    return this.boards.filter((board) => board.kind === this.kind);
  }

  get seriesButtons() {
    const seen = new Map();

    for (const board of this.kindBoards) {
      if (board.series_slug && !seen.has(board.series_slug)) {
        seen.set(board.series_slug, {
          slug: board.series_slug,
          label: board.series_name || board.series_slug,
        });
      }
    }

    return [
      {
        slug: "",
        label: i18n(themePrefix("ingenic.boards.all_series")),
        active: this.series === "",
      },
      ...Array.from(seen.values()).map((item) => ({
        ...item,
        active: item.slug === this.series,
      })),
    ];
  }

  get chipButtons() {
    const seen = new Map();

    for (const board of this.kindBoards) {
      if (!board.product_slug) {
        continue;
      }

      if (this.series && board.series_slug !== this.series) {
        continue;
      }

      if (!seen.has(board.product_slug)) {
        seen.set(board.product_slug, {
          slug: board.product_slug,
          label: board.chip_name || board.chip || board.product_slug,
        });
      }
    }

    return [
      {
        slug: "",
        label: i18n(themePrefix("ingenic.boards.all_chips")),
        active: this.chip === "",
      },
      ...Array.from(seen.values()).map((item) => ({
        ...item,
        active: item.slug === this.chip,
      })),
    ];
  }

  // A row whose only option is "All series" cannot narrow anything: it is a
  // control with one answer. The catalogue is small enough that this happens
  // whenever its boards sit in one series or name no chip, and on those pages
  // the row only pushed the cards further down.
  get showsSeries() {
    return this.seriesButtons.length > 1;
  }

  get showsChips() {
    return this.chipButtons.length > 1;
  }

  get visibleBoards() {
    return this.kindBoards.filter((board) => {
      if (this.series && board.series_slug !== this.series) {
        return false;
      }

      if (this.chip && board.product_slug !== this.chip) {
        return false;
      }

      return true;
    });
  }

  // Worked out here so the template stays a description of the layout. The
  // specification list is free text, one item per line.
  //
  // Both buttons are always drawn. A missing address, or the sold-out switch,
  // grays the button out rather than removing it: the card keeps its shape
  // between a board that is for sale and one that is not, and a sale that has
  // ended reads differently from a board that was never listed.
  get cards() {
    return this.visibleBoards.map((board) => ({
      ...board,
      specs: (board.specs ?? "")
        .split("\n")
        .map((line) => line.trim())
        .filter(Boolean),
      applyDisabled: board.sold_out || !board.application_url,
      buyDisabled: board.sold_out || !board.purchase_url,
    }));
  }

  get selectedApplyDisabled() {
    return Boolean(
      this.selected?.sold_out || !this.selected?.application_url
    );
  }

  get selectedBuyDisabled() {
    return Boolean(this.selected?.sold_out || !this.selected?.purchase_url);
  }

  get filtered() {
    return this.series !== "" || this.chip !== "";
  }

  // Six cards is the grid's first two rows on a wide screen; the placeholders
  // hold their height until the catalogue arrives.
  get placeholders() {
    return Array.from({ length: 6 }, (_, index) => index);
  }

  @action
  async load() {
    const request = ++this.requestId;
    this.loading = true;

    try {
      const response = await fetch(getURL(ENDPOINT), {
        headers: { Accept: "application/json" },
      });

      if (response.ok) {
        const payload = await response.json();

        if (request === this.requestId) {
          this.boards = payload.boards ?? [];
          this.filters = payload.filters ?? this.filters;
        }
      }
    } catch {
      if (request === this.requestId) {
        this.boards = [];
      }
    } finally {
      if (request === this.requestId) {
        this.loading = false;
      }
    }
  }

  @action
  pickKind(kind) {
    if (kind === this.kind) {
      return;
    }

    this.kind = kind;
    // Both rows below are choices about the kind that was just left. Keeping
    // either would hold a value the new list may not contain, and the empty
    // result would have no visible cause.
    this.series = "";
    this.chip = "";
  }

  @action
  pickSeries(value) {
    if ((value ?? "") === this.series) {
      return;
    }

    this.series = value ?? "";
    this.chip = "";
  }

  @action
  pickChip(value) {
    this.chip = value ?? "";
  }

  // The whole card is the way into the detail dialog, so the two links have to
  // stop their own clicks from also opening it — they leave the site, and the
  // browser is already doing what was asked.
  @action
  open(board) {
    this.selected = board;
  }

  @action
  close() {
    this.selected = null;
  }

  @action
  stop(event) {
    event.stopPropagation();
  }

  @action
  openFromKeyboard(board, event) {
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      this.open(board);
    }
  }

  @action
  onKeydown(event) {
    if (event.key === "Escape" && this.selected) {
      this.close();
    }
  }

  @action
  focusDialog(element) {
    element.focus();
  }

  <template>
    <section class="ingenic-section" {{didInsert this.load}}>
      <header class="ingenic-section__header">
        <div>
          <h1>{{i18n (themePrefix "ingenic.boards.title")}}</h1>
          <p class="ingenic-section__subtitle">
            {{i18n (themePrefix "ingenic.boards.subtitle")}}
          </p>
        </div>
      </header>

      <div class="ingenic-boards__filters">
        <div
          class="ingenic-downloads__filter"
          role="group"
          aria-label={{i18n (themePrefix "ingenic.boards.kind_filter")}}
        >
          <span class="ingenic-downloads__filter-label">
            {{i18n (themePrefix "ingenic.boards.kind_filter")}}
          </span>
          <div class="ingenic-downloads__options">
            {{#each this.kindTabs as |tab|}}
              <button
                class="ingenic-downloads__option {{if tab.active 'is-current'}}"
                type="button"
                aria-pressed={{tab.active}}
                disabled={{this.loading}}
                {{on "click" (fn this.pickKind tab.kind)}}
              >
                {{tab.label}}
              </button>
            {{/each}}
          </div>
        </div>

        {{#if this.showsSeries}}
          <div
            class="ingenic-downloads__filter"
            role="group"
            aria-label={{i18n (themePrefix "ingenic.boards.series_filter")}}
          >
            <span class="ingenic-downloads__filter-label">
              {{i18n (themePrefix "ingenic.boards.series_filter")}}
            </span>
            <div class="ingenic-downloads__options">
              {{#each this.seriesButtons as |item|}}
                <button
                  class="ingenic-downloads__option {{if item.active 'is-current'}}"
                  type="button"
                  aria-pressed={{item.active}}
                  disabled={{this.loading}}
                  {{on "click" (fn this.pickSeries item.slug)}}
                >
                  {{item.label}}
                </button>
              {{/each}}
            </div>
          </div>
        {{/if}}

        {{#if this.showsChips}}
          <div
            class="ingenic-downloads__filter"
            role="group"
            aria-label={{i18n (themePrefix "ingenic.boards.chip_filter")}}
          >
            <span class="ingenic-downloads__filter-label">
              {{i18n (themePrefix "ingenic.boards.chip_filter")}}
            </span>
            <div class="ingenic-downloads__options">
              {{#each this.chipButtons as |item|}}
                <button
                  class="ingenic-downloads__option {{if item.active 'is-current'}}"
                  type="button"
                  aria-pressed={{item.active}}
                  disabled={{this.loading}}
                  {{on "click" (fn this.pickChip item.slug)}}
                >
                  {{item.label}}
                </button>
              {{/each}}
            </div>
          </div>
        {{/if}}
      </div>

      {{#if this.cards.length}}
        <div class="ingenic-card-grid ingenic-card-grid--products">
          {{#each this.cards as |board|}}
            <article
              class="ingenic-product-card"
              tabindex="0"
              role="button"
              {{on "click" (fn this.open board)}}
              {{on "keydown" (fn this.openFromKeyboard board)}}
            >
              <div class="ingenic-product-card__media">
                {{#if board.sold_out}}
                  <span class="ingenic-stamp">
                    {{i18n (themePrefix "ingenic.boards.sold_out")}}
                  </span>
                {{/if}}

                {{#if board.image_url}}
                  <img
                    class="ingenic-product-card__image"
                    src={{board.image_url}}
                    alt={{board.name}}
                    loading="lazy"
                  />
                {{else}}
                  <span class="ingenic-product-card__placeholder" aria-hidden="true">
                    {{dIcon "microchip"}}
                  </span>
                {{/if}}
              </div>

              <div class="ingenic-product-card__body">
                <h2 class="ingenic-product-card__name">{{board.name}}</h2>

                {{#if board.chip_name}}
                  <div class="ingenic-product-card__meta">
                    {{board.chip_name}}
                    {{#if board.series_name}}· {{board.series_name}}{{/if}}
                  </div>
                {{/if}}

                {{#if board.description}}
                  <p class="ingenic-product-card__description">
                    {{board.description}}
                  </p>
                {{/if}}
              </div>

              <div class="ingenic-product-card__actions">
                {{#if board.applyDisabled}}
                  <button class="btn btn-primary" type="button" disabled>
                    {{i18n (themePrefix "ingenic.boards.apply")}}
                  </button>
                {{else}}
                  <a
                    class="btn btn-primary"
                    href={{board.application_url}}
                    target="_blank"
                    rel="noopener noreferrer"
                    {{on "click" this.stop}}
                  >
                    {{i18n (themePrefix "ingenic.boards.apply")}}
                  </a>
                {{/if}}

                {{#if board.buyDisabled}}
                  <button class="btn btn-primary" type="button" disabled>
                    {{i18n (themePrefix "ingenic.boards.buy")}}
                  </button>
                {{else}}
                  <a
                    class="btn btn-primary"
                    href={{board.purchase_url}}
                    target="_blank"
                    rel="noopener noreferrer"
                    {{on "click" this.stop}}
                  >
                    {{i18n (themePrefix "ingenic.boards.buy")}}
                  </a>
                {{/if}}
              </div>
            </article>
          {{/each}}
        </div>
      {{else if this.loading}}
        <div class="ingenic-card-grid ingenic-card-grid--products" aria-hidden="true">
          {{#each this.placeholders as |placeholder|}}
            <article class="ingenic-product-card ingenic-product-card--skeleton">
              <div class="ingenic-product-card__media ingenic-skeleton"></div>
              <div class="ingenic-product-card__body">
                <span class="ingenic-skeleton ingenic-skeleton--title"></span>
                <span class="ingenic-skeleton ingenic-skeleton--meta"></span>
              </div>
            </article>
          {{/each}}
        </div>
      {{else if this.filtered}}
        <p class="ingenic-card__meta">{{i18n (themePrefix "ingenic.boards.no_match")}}</p>
      {{else}}
        <p class="ingenic-card__meta">{{i18n (themePrefix "ingenic.boards.empty")}}</p>
      {{/if}}

      {{#if this.selected}}
        <div
          class="ingenic-board-dialog"
          role="dialog"
          aria-modal="true"
          tabindex="-1"
          {{didInsert this.focusDialog}}
          {{on "click" this.close}}
          {{on "keydown" this.onKeydown}}
        >
          <div class="ingenic-board-dialog__panel" {{on "click" this.stop}}>
            <button
              class="ingenic-board-dialog__close"
              type="button"
              aria-label={{i18n (themePrefix "ingenic.boards.close")}}
              {{on "click" this.close}}
            >
              ×
            </button>

            <div class="ingenic-board-dialog__scroll">
              {{#if this.selected.sold_out}}
                <span class="ingenic-stamp ingenic-board-dialog__stamp">
                  {{i18n (themePrefix "ingenic.boards.sold_out")}}
                </span>
              {{/if}}
              {{#if this.selected.image_url}}
                <div class="ingenic-board-dialog__media">
                  <img
                    class="ingenic-board-dialog__image"
                    src={{this.selected.image_url}}
                    alt={{this.selected.name}}
                  />
                </div>
              {{/if}}

              <h2 class="ingenic-board-dialog__title">{{this.selected.name}}</h2>

              {{#if this.selected.chip_name}}
                <div class="ingenic-board-dialog__meta">
                  {{this.selected.chip_name}}
                  {{#if this.selected.series_name}}· {{this.selected.series_name}}{{/if}}
                </div>
              {{/if}}

              {{#if this.selected.details_html}}
                <div class="ingenic-board-dialog__details">
                  {{trustHTML this.selected.details_html}}
                </div>
              {{else if this.selected.description}}
                <p class="ingenic-board-dialog__details">
                  {{this.selected.description}}
                </p>
              {{/if}}

              {{#if this.selected.specs.length}}
                <ul class="ingenic-board-dialog__specs">
                  {{#each this.selected.specs as |line|}}
                    <li>{{line}}</li>
                  {{/each}}
                </ul>
              {{/if}}

            </div>

            <div class="ingenic-board-dialog__actions">
              {{#if this.selectedApplyDisabled}}
                <button class="btn btn-primary" type="button" disabled>
                  {{i18n (themePrefix "ingenic.boards.apply")}}
                </button>
              {{else}}
                <a
                  class="btn btn-primary"
                  href={{this.selected.application_url}}
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  {{i18n (themePrefix "ingenic.boards.apply")}}
                </a>
              {{/if}}

              {{#if this.selectedBuyDisabled}}
                <button class="btn btn-primary" type="button" disabled>
                  {{i18n (themePrefix "ingenic.boards.buy")}}
                </button>
              {{else}}
                <a
                  class="btn btn-primary"
                  href={{this.selected.purchase_url}}
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  {{i18n (themePrefix "ingenic.boards.buy")}}
                </a>
              {{/if}}
            </div>
          </div>
        </div>
      {{/if}}
    </section>
  </template>
}
