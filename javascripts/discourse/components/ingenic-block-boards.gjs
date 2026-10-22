import { themePrefix } from "virtual:theme";
import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import { i18n } from "discourse-i18n";
import getURL from "discourse/lib/get-url";
import { withReadingLocale } from "../ingenic/reading-locale";

/**
 * Homepage block showcasing development boards.
 *
 * Board application is an outbound link owned by the Ingenic team, so this block
 * never posts to the forum itself.
 */
export default class IngenicBlockBoards extends Component {
  @tracked boards = [];
  @tracked loaded = false;

  get limit() {
    return this.args.block?.limit || 4;
  }

  get title() {
    return this.args.block?.title || i18n(themePrefix("ingenic.boards.title"));
  }

  // The same two-call-to-action card the catalogue draws, including which of the
  // two leads and which is grayed out. Kept in step with ingenic-boards rather
  // than left to the markup, because the two are the same card at two lengths.
  get cards() {
    return this.boards.map((board) => ({
      ...board,
      applyClass: board.purchase_url ? "btn" : "btn btn-primary",
      applyDisabled: board.sold_out || !board.application_url,
      buyDisabled: board.sold_out || !board.purchase_url,
      // The tree's name for the chip, falling back to the older free-text
      // column, so a board filed before the tree existed still names its chip.
      chipLabel: board.chip_name || board.chip || "",
    }));
  }

  @action
  async load() {
    if (this.loaded) {
      return;
    }

    this.loaded = true;

    try {
      const response = await fetch(withReadingLocale(getURL("/ingenic/boards")), {
        headers: { Accept: "application/json" },
      });

      if (response.ok) {
        const payload = await response.json();
        this.boards = (payload.boards ?? []).slice(0, this.limit);
      }
    } catch {
      this.boards = [];
    }
  }

  <template>
    <section class="ingenic-section" {{didInsert this.load}}>
      <header class="ingenic-section__header">
        <h2><a href="/ingenic/boards">{{this.title}}</a></h2>
      </header>

      {{#if this.boards.length}}
        <div class="ingenic-card-grid">
          {{#each this.cards as |board|}}
            <article class="ingenic-card ingenic-card--board">
              {{#if board.sold_out}}
                <span class="ingenic-stamp">
                  {{i18n (themePrefix "ingenic.boards.sold_out")}}
                </span>
              {{/if}}

              {{#if board.image_url}}
                <img
                  class="ingenic-card__image"
                  src={{board.image_url}}
                  alt={{board.name}}
                  loading="lazy"
                />
              {{/if}}
              <div class="ingenic-card__title">{{board.name}}</div>
              {{#if board.chipLabel}}
                <div class="ingenic-card__meta">{{board.chipLabel}}</div>
              {{/if}}
              <div class="ingenic-card__actions">
                {{#if board.applyDisabled}}
                  <button class={{board.applyClass}} type="button" disabled>
                    {{i18n (themePrefix "ingenic.boards.apply")}}
                  </button>
                {{else}}
                  <a
                    class={{board.applyClass}}
                    href={{board.application_url}}
                    target="_blank"
                    rel="noopener noreferrer"
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
                  >
                    {{i18n (themePrefix "ingenic.boards.buy")}}
                  </a>
                {{/if}}
              </div>
            </article>
          {{/each}}
        </div>
      {{else}}
        <p class="ingenic-card__meta">{{i18n (themePrefix "ingenic.boards.empty")}}</p>
      {{/if}}
    </section>
  </template>
}
