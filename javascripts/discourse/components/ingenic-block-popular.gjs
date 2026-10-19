import { themePrefix } from "virtual:theme";
import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import getURL from "discourse/lib/get-url";
import dFormatDate from "discourse/ui-kit/helpers/d-format-date";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";

const ENDPOINT = "/ingenic/popular";

/**
 * Homepage block: the topics the forum liked most in the recent window.
 *
 * Likes first, views second. The ordering is the server's — it is the one
 * decision the card cannot make from a list it was handed — so this only draws
 * the ranks and the two counts that explain them.
 */
export default class IngenicBlockPopular extends Component {
  @service store;

  @tracked rows = [];
  @tracked loaded = false;
  requested = false;

  get limit() {
    return this.args.block?.limit || 5;
  }

  get title() {
    return (
      this.args.block?.title ||
      i18n(themePrefix("ingenic.popular.title"))
    );
  }

  get allPath() {
    return getURL("/ingenic/popular");
  }

  get placeholders() {
    return Array.from({ length: this.limit }, (_, index) => index);
  }

  get visibleRows() {
    return this.rows.slice(0, this.limit);
  }

  @action
  async load() {
    if (this.requested) {
      return;
    }

    this.requested = true;

    try {
      const response = await fetch(
        `${getURL(ENDPOINT)}?limit=${this.limit}`,
        { headers: { Accept: "application/json" } },
      );

      if (response.ok) {
        const payload = await response.json();
        this.rows = (payload.topics ?? []).map((topic, index) => ({
          ...topic,
          rank: index + 1,
          isTop: index < 3,
          path: getURL(topic.url),
          categoryPath: topic.category_url
            ? getURL(topic.category_url)
            : null,
          tags: (topic.tags ?? []).map((tag) => ({
            name: tag.name,
            key: tag.slug || tag.name.toLowerCase(),
            // A tag written in Chinese has no romanised slug; its name is the
            // address Discourse routes it by.
            url: getURL(
              tag.slug
                ? `/tag/${tag.slug}`
                : `/tag/${encodeURIComponent(tag.name)}`,
            ),
          })),
        }));
      }
    } catch {
      this.rows = [];
    } finally {
      this.loaded = true;
    }
  }

  <template>
    <section class="ingenic-section ingenic-popular" {{didInsert this.load}}>
      <header class="ingenic-section__header">
        <h2>
          <span class="ingenic-section__icon">{{dIcon "heart"}}</span>
          {{this.title}}
        </h2>
      </header>

      {{#if this.visibleRows.length}}
        <ol class="ingenic-popular__list">
          {{#each this.visibleRows as |row|}}
            <li class="ingenic-popular__item">
              <span class="ingenic-popular__rank {{if row.isTop 'is-top'}}" aria-hidden="true">
                {{row.rank}}
              </span>
              <div class="ingenic-popular__body">
                <a class="ingenic-popular__title" href={{row.path}}>{{row.title}}</a>

                {{#if row.tags.length}}
                  <div class="ingenic-feed__tags discourse-tags">
                    {{#each row.tags as |tag|}}
                      <a
                        class="discourse-tag simple"
                        href={{tag.url}}
                        data-tag-name={{tag.key}}
                      >{{tag.name}}</a>
                    {{/each}}
                  </div>
                {{/if}}

                <span class="ingenic-popular__meta">
                  {{#if row.category}}
                    <a
                      class="ingenic-popular__category"
                      href={{row.categoryPath}}
                      style="--ingenic-category: #{{row.category_color}}"
                    >
                      <span
                        class="ingenic-popular__dot"
                        style="background-color: #{{row.category_color}}"
                        aria-hidden="true"
                      ></span>
                      {{row.category}}
                    </a>
                  {{/if}}
                  <span class="ingenic-popular__count">
                    {{i18n (themePrefix "ingenic.popular.likes") count=row.likes}}
                  </span>
                  <span class="ingenic-popular__count">
                    {{i18n (themePrefix "ingenic.popular.views") count=row.views}}
                  </span>
                  <span class="ingenic-popular__when">
                    {{dFormatDate row.last_posted_at leaveAgo="true"}}
                  </span>
                </span>
              </div>
            </li>
          {{/each}}
        </ol>
      {{else if this.loaded}}
        <p class="ingenic-section__subtitle">
          {{i18n (themePrefix "ingenic.home.empty")}}
        </p>
      {{else}}
        <ol class="ingenic-popular__list" aria-hidden="true">
          {{#each this.placeholders as |placeholder|}}
            <li class="ingenic-popular__item ingenic-popular__item--skeleton">
              <span class="ingenic-skeleton ingenic-skeleton--title"></span>
              <span class="ingenic-skeleton ingenic-skeleton--meta"></span>
            </li>
          {{/each}}
        </ol>
      {{/if}}

      <a class="ingenic-section__footer" href={{this.allPath}}>
        {{i18n (themePrefix "ingenic.home.show_all")}}
        {{dIcon "arrow-right"}}
      </a>
    </section>
  </template>
}
