import { themePrefix } from "virtual:theme";
import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import getURL from "discourse/lib/get-url";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";

const ENDPOINT = "/ingenic/popular";
const LIMIT = 50;

/**
 * The popular page behind the rail card.
 *
 * The card shows five; this shows as many as the server will send, in the same
 * order. Likes first, views breaking ties — the server decides that, and this
 * page does not re-sort it, because a list that quietly reorders itself between
 * the card and its own page is worse than either order alone.
 */
export default class IngenicPopular extends Component {
  @tracked topics = [];
  @tracked windowDays = 30;
  @tracked loading = true;

  get rows() {
    return this.topics.map((topic, index) => ({
      ...topic,
      rank: index + 1,
      isTop: index < 3,
      path: getURL(topic.url),
    }));
  }

  get subtitle() {
    return i18n(
      themePrefix("ingenic.popular.subtitle"),
      { days: this.windowDays },
    );
  }

  @action
  async load() {
    try {
      const response = await fetch(
        `${getURL(ENDPOINT)}?limit=${LIMIT}`,
        { headers: { Accept: "application/json" } },
      );

      if (response.ok) {
        const payload = await response.json();
        this.topics = payload.topics ?? [];
        this.windowDays = payload.window_days ?? 30;
      }
    } catch {
      this.topics = [];
    } finally {
      this.loading = false;
    }
  }

  <template>
    <section class="ingenic-section ingenic-popular-page" {{didInsert this.load}}>
      <header class="ingenic-section__header">
        <div>
          <h1>
            <span class="ingenic-section__icon">{{dIcon "heart"}}</span>
            {{i18n (themePrefix "ingenic.popular.title")}}
          </h1>
          <p class="ingenic-section__subtitle">{{this.subtitle}}</p>
        </div>
      </header>

      {{#if this.rows.length}}
        <ol class="ingenic-popular-page__list">
          {{#each this.rows as |row|}}
            <li class="ingenic-popular-page__row">
              <span class="ingenic-popular-page__rank {{if row.isTop 'is-top'}}">
                {{row.rank}}
              </span>

              <div class="ingenic-popular-page__body">
                <a class="ingenic-popular-page__title" href={{row.path}}>
                  {{row.title}}
                </a>
                {{#if row.category}}
                  <span class="ingenic-popular-page__category">{{row.category}}</span>
                {{/if}}
              </div>

              <span class="ingenic-popular-page__stat">
                {{dIcon "heart"}}
                {{row.likes}}
              </span>
              <span class="ingenic-popular-page__stat">
                {{dIcon "eye"}}
                {{row.views}}
              </span>
            </li>
          {{/each}}
        </ol>
      {{else}}
        <p class="ingenic-section__subtitle">
          {{#if this.loading}}
            {{i18n (themePrefix "ingenic.popular.loading")}}
          {{else}}
            {{i18n (themePrefix "ingenic.popular.empty")}}
          {{/if}}
        </p>
      {{/if}}
    </section>
  </template>
}
