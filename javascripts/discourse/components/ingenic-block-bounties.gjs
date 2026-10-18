import { themePrefix } from "virtual:theme";
import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import getURL from "discourse/lib/get-url";
import { i18n } from "discourse-i18n";

const ENDPOINT = "/ingenic/bounties";

/**
 * Homepage block: the richest standing 高分悬赏, with a way through to the board.
 *
 * It draws its own panel even when nothing is on offer: on a forum that takes
 * bounties, the feature is worth one short line saying there is nothing
 * standing, and a card that appears only once somebody has opened a bounty
 * reads as a broken block to everyone who looked before that. The panel is
 * also the way to the board, which is where a member opens one.
 *
 * The first paint needs to know how many rows will be drawn, so the list is
 * asked for in the constructor rather than in `didInsert` — the panel exists
 * either way, and an empty list should become rows in place.
 */
export default class IngenicBlockBounties extends Component {
  @service site;

  @tracked bounties = [];
  // Distinguishes "the list is empty" from "the list has not arrived": the
  // panel shows the same shape either way, with placeholders until then.
  @tracked loaded = false;

  // A plain field rather than a tracked one: `load` is called from the
  // constructor, which runs inside the render computation, and writing tracked
  // state there is refused by Ember — the refusal was thrown before the fetch
  // line, so this panel never asked for its list at all.
  requested = false;

  constructor() {
    super(...arguments);
    this.load();
  }

  get limit() {
    return this.args.block?.limit || 5;
  }

  get title() {
    return this.args.block?.title || i18n(themePrefix("ingenic.bounties.title"));
  }

  get rows() {
    return this.bounties.slice(0, this.limit).map((bounty) => {
      const category = this.site.categories?.find(
        (c) => c.id === bounty.topic.category_id
      );

      return {
        ...bounty,
        url: bounty.topic.url,
        title: bounty.topic.title,
        category,
        categoryUrl: category?.url,
      };
    });
  }

  get boardPath() {
    return getURL("/ingenic/bounties");
  }

  @action
  async load() {
    if (this.requested) {
      return;
    }

    this.requested = true;

    try {
      const response = await fetch(`${getURL(ENDPOINT)}?limit=${this.limit}`, {
        headers: { Accept: "application/json" },
      });

      if (response.ok) {
        const payload = await response.json();
        this.bounties = payload.bounties ?? [];
      }
    } catch {
      this.bounties = [];
    } finally {
      this.loaded = true;
    }
  }

  get placeholders() {
    return Array.from({ length: this.limit }, (_, index) => index);
  }

  <template>
    <section class="ingenic-section ingenic-bounties">
      <header class="ingenic-section__header">
        <h2>
          <span class="ingenic-section__icon">{{dIcon "gift"}}</span>
          <a href={{this.boardPath}}>{{this.title}}</a>
        </h2>
      </header>

      {{#if this.rows.length}}
        <ul class="ingenic-bounty-list">
          {{#each this.rows as |row|}}
            <li class="ingenic-bounty-list__item">
              <span class="ingenic-bounty-list__points">
                {{dIcon "gift"}}
                {{row.points}}
              </span>

              <div class="ingenic-bounty-list__body">
                <a class="ingenic-bounty-list__title" href={{row.url}}>{{row.title}}</a>

                {{#if row.category}}
                  <a
                    class="ingenic-bounty-list__category"
                    href={{row.categoryUrl}}
                    style="border-color: #{{row.category.color}}"
                  >
                    {{row.category.name}}
                  </a>
                {{/if}}
              </div>
            </li>
          {{/each}}
        </ul>
      {{else if this.loaded}}
        <p class="ingenic-section__subtitle">
          {{i18n (themePrefix "ingenic.bounties.empty")}}
        </p>
      {{else}}
        <ul class="ingenic-bounty-list" aria-hidden="true">
          {{#each this.placeholders as |placeholder|}}
            <li class="ingenic-bounty-list__item ingenic-bounty-list__item--skeleton">
              <span class="ingenic-skeleton ingenic-skeleton--badge"></span>
              <div class="ingenic-bounty-list__body">
                <span class="ingenic-skeleton ingenic-skeleton--title"></span>
                <span class="ingenic-skeleton ingenic-skeleton--meta"></span>
              </div>
            </li>
          {{/each}}
        </ul>
      {{/if}}

      <a class="ingenic-section__footer" href={{this.boardPath}}>
        {{i18n (themePrefix "ingenic.home.show_all")}}
        {{dIcon "arrow-right"}}
      </a>
    </section>
  </template>
}
