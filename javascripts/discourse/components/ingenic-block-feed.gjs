import { themePrefix } from "virtual:theme";
import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { service } from "@ember/service";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import getURL from "discourse/lib/get-url";
import dFormatDate from "discourse/ui-kit/helpers/d-format-date";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";

/**
 * A column of topics for the front page.
 *
 * The latest block and the hot block are the same list with a different feed:
 * "what was said last" and "what people kept reading" differ in the filter and
 * in nothing a reader sees, so they share one component rather than two that
 * drift. A category block is a different shape — it is pinned to an editor's
 * choice of section — and stays in its own component.
 *
 * The counts and the last-post time are what meta.discourse.org puts beside a
 * title, and they are the reason a list of titles is worth more than a list:
 * a reader can tell a thread with forty replies from one nobody answered.
 */
const FEEDS = {
  latest: "latest",
  // Discourse's own "hot" feed. `top/weekly` is a 301 a fetch does not follow,
  // and a weekly window is empty on a forum whose topics have no views yet —
  // which is every new install on the day it opens.
  hot: "hot",
};

export default class IngenicBlockFeed extends Component {
  @service site;
  @service store;

  @tracked topics = [];
  // True once the request has settled, including a failed one: until then the
  // card draws placeholder rows, so the list does not announce "nothing here"
  // while it is still being fetched.
  @tracked loaded = false;
  // Which rows the reader asked for. The whole list is fetched once and
  // filtered in the browser: Discourse has no "unanswered" feed to ask for, and
  // 已解决 is a tag on the topic rather than a filter the server understands.
  @tracked filter = "all";
  // Which slice of the fetched list the table shows. The whole latest list
  // arrives at once (Discourse sends thirty), so turning a page is a slice
  // rather than a request: the reader does not wait for a reload to see the
  // next rows.
  @tracked page = 1;
  requested = false;

  get type() {
    return this.args.block?.type;
  }

  get isHot() {
    return this.type === "hot";
  }

  // The latest block is the page's table; hot is a compact "what is trending"
  // rail card.
  get isTable() {
    return !this.isHot;
  }

  get limit() {
    return this.args.block?.limit || (this.isHot ? 5 : 8);
  }

  // The two feeds read the same at a glance — the icon is what tells "what was
  // just said" from "what people kept reading" before the title is read.
  // Discourse's icon set has no `fire`, and an unknown name draws an empty
  // <use>, which is why this row looked unmarked; `chart-line` carries the
  // same "what is trending" reading.
  get icon() {
    return this.isHot ? "chart-line" : "clock";
  }

  get title() {
    return (
      this.args.block?.title ||
      i18n(
        themePrefix(
          this.isHot ? "ingenic.home.topics.hot" : "ingenic.home.topics.latest",
        ),
      )
    );
  }

  // The latest list is the table on the page and "View all" goes to the same
  // feed without the card's limit. Hot keeps its own address.
  get allPath() {
    return getURL(this.isHot ? "/hot" : "/latest");
  }

  get filterOptions() {
    return [
      { key: "all", label: i18n(themePrefix("ingenic.home.filters.all")) },
      {
        key: "unanswered",
        label: i18n(themePrefix("ingenic.home.filters.unanswered")),
      },
      { key: "solved", label: i18n(themePrefix("ingenic.home.filters.solved")) },
    ].map((option) => ({ ...option, active: option.key === this.filter }));
  }

  // Topic keeps the payload's own names — `category_id`, `posts_count`,
  // `last_posted_at` — rather than camel-casing them. Reading the camelCase
  // spelling here is what left the reply count undefined and the date blank.
  get categoryFor() {
    return (topic) =>
      this.site.categories?.find(
        (category) => category.id === topic.category_id,
      );
  }

  get allRows() {
    const categoryFor = this.categoryFor;

    return this.topics.map((topic, index) => ({
      id: topic.id,
      rank: index + 1,
      title: topic.title,
      url: topic.url,
      postsCount: topic.posts_count,
      views: topic.views,
      lastPostedAt: topic.last_posted_at,
      // No answer yet. `posts_count` includes the opening post, so one post is
      // an unanswered question and two is a conversation.
      unanswered: (topic.posts_count ?? 0) <= 1,
      solved: (topic.tags ?? []).some(
        (tag) => (typeof tag === "string" ? tag : tag.name) === "已解决",
      ),
      category: categoryFor(topic),
      categoryUrl: categoryFor(topic)?.url,
      tags: (topic.tags ?? []).map((tag) =>
        typeof tag === "string"
          ? {
              name: tag,
              key: tag.toLowerCase(),
              url: getURL(`/tag/${tag.toLowerCase()}`),
            }
          : {
              name: tag.name,
              key: (tag.name ?? "").toLowerCase(),
              url: getURL(`/tag/${tag.slug || tag.id}`),
            },
      ),
    }));
  }

  // Filter the whole fetched list, then slice the current page out of what
  // survived: filtering only the visible page would leave a page shorter than
  // its neighbours and the count of pages wrong.
  get filteredRows() {
    if (this.isHot || this.filter === "all") {
      return this.allRows;
    }

    return this.allRows.filter((row) => row[this.filter]);
  }

  get pageCount() {
    return Math.max(1, Math.ceil(this.filteredRows.length / this.limit));
  }

  get pageLinks() {
    return Array.from({ length: this.pageCount }, (_, index) => ({
      number: index + 1,
      active: index + 1 === this.page,
    }));
  }

  get previousPage() {
    return Math.max(1, this.page - 1);
  }

  get nextPage() {
    return Math.min(this.pageCount, this.page + 1);
  }

  get isFirstPage() {
    return this.page === 1;
  }

  get isLastPage() {
    return this.page === this.pageCount;
  }

  get rows() {
    if (this.isHot) {
      return this.filteredRows.slice(0, this.limit);
    }

    const start = (this.page - 1) * this.limit;
    return this.filteredRows.slice(start, start + this.limit);
  }

  @action
  chooseFilter(key) {
    this.filter = key;
    this.page = 1;
  }

  @action
  choosePage(page) {
    if (page < 1 || page > this.pageCount) {
      return;
    }

    this.page = page;
  }

  // One placeholder per row the real list will hold, so the card keeps its
  // height when the titles arrive.
  get placeholders() {
    return Array.from({ length: this.limit }, (_, index) => index);
  }

  @action
  async load() {
    if (this.requested) {
      return;
    }

    this.requested = true;

    try {
      const result = await this.store.findFiltered("topicList", {
        filter: FEEDS[this.type] || FEEDS.latest,
      });

      this.topics = result.topics ?? [];
    } catch {
      this.topics = [];
    } finally {
      this.loaded = true;
    }
  }

  <template>
    <section
      class="ingenic-section ingenic-feed {{if this.isHot 'ingenic-feed--hot'}} {{if this.isTable 'ingenic-feed--table'}}"
      {{didInsert this.load}}
    >
      <header class="ingenic-section__header">
        <h2>
          <span class="ingenic-section__icon">{{dIcon this.icon}}</span>
          {{this.title}}
        </h2>

        {{#unless this.isHot}}
          <div class="ingenic-feed__filters" role="group">
            {{#each this.filterOptions as |option|}}
              <button
                type="button"
                class="ingenic-feed__filter {{if option.active 'is-active'}}"
                aria-pressed={{option.active}}
                {{on "click" (fn this.chooseFilter option.key)}}
              >
                {{option.label}}
              </button>
            {{/each}}
          </div>
        {{/unless}}
      </header>

      {{#if this.isTable}}
        <div class="ingenic-feed__table-head" aria-hidden="true">
          <span class="ingenic-feed__col ingenic-feed__col--topic">
            {{i18n (themePrefix "ingenic.home.topics.topic")}}
          </span>
          <span class="ingenic-feed__col">
            {{i18n (themePrefix "ingenic.home.topics.replies_short")}}
          </span>
          <span class="ingenic-feed__col">
            {{i18n (themePrefix "ingenic.home.topics.views_short")}}
          </span>
          <span class="ingenic-feed__col">
            {{i18n (themePrefix "ingenic.home.topics.activity")}}
          </span>
        </div>
      {{/if}}

      {{#if this.rows.length}}
        <ol class="ingenic-feed__list">
          {{#each this.rows as |row|}}
            {{#if this.isTable}}
              <li class="ingenic-feed__item ingenic-feed__item--row">
                <div class="ingenic-feed__cell ingenic-feed__cell--topic">
                  <a class="ingenic-feed__title" href={{row.url}}>{{row.title}}</a>

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

                  {{#if row.category}}
                    <a
                      class="ingenic-feed__category"
                      href={{row.categoryUrl}}
                      style="--ingenic-category: #{{row.category.color}}"
                    >
                      <span
                        class="ingenic-feed__dot"
                        style="background-color: #{{row.category.color}}"
                        aria-hidden="true"
                      ></span>
                      {{row.category.name}}
                    </a>
                  {{/if}}
                </div>

                <span class="ingenic-feed__cell ingenic-feed__cell--count">{{row.postsCount}}</span>
                <span class="ingenic-feed__cell ingenic-feed__cell--count">{{row.views}}</span>
                <span class="ingenic-feed__cell ingenic-feed__cell--time">
                  {{dFormatDate row.lastPostedAt leaveAgo="true"}}
                </span>
              </li>
            {{else}}
              <li class="ingenic-feed__item">
                <div class="ingenic-feed__headline">
                  <span class="ingenic-feed__rank" aria-hidden="true">{{row.rank}}</span>
                  <a class="ingenic-feed__title" href={{row.url}}>{{row.title}}</a>
                </div>

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

                <div class="ingenic-feed__meta">
                  {{#if row.category}}
                    <a
                      class="ingenic-feed__category"
                      href={{row.categoryUrl}}
                      style="--ingenic-category: #{{row.category.color}}"
                    >
                      <span
                        class="ingenic-feed__dot"
                        style="background-color: #{{row.category.color}}"
                        aria-hidden="true"
                      ></span>
                      {{row.category.name}}
                    </a>
                  {{/if}}
                  <span class="ingenic-feed__count">
                    {{i18n (themePrefix "ingenic.home.topics.replies") count=row.postsCount}}
                  </span>
                  <span class="ingenic-feed__count">
                    {{i18n (themePrefix "ingenic.home.topics.views") count=row.views}}
                  </span>
                  <span class="ingenic-feed__time">
                    {{dFormatDate row.lastPostedAt leaveAgo="true"}}
                  </span>
                </div>
              </li>
            {{/if}}
          {{/each}}
        </ol>
      {{else if this.loaded}}
        <p class="ingenic-section__subtitle">
          {{i18n (themePrefix "ingenic.home.empty")}}
        </p>
      {{else}}
        <ol class="ingenic-feed__list" aria-hidden="true">
          {{#each this.placeholders as |placeholder|}}
            <li class="ingenic-feed__item ingenic-feed__item--skeleton">
              <span class="ingenic-skeleton ingenic-skeleton--title"></span>
              <span class="ingenic-skeleton ingenic-skeleton--meta"></span>
            </li>
          {{/each}}
        </ol>
      {{/if}}

      {{#if this.isTable}}
        <nav
          class="ingenic-feed__pager"
          role="navigation"
          aria-label={{i18n (themePrefix "ingenic.home.pagination")}}
        >
          <button
            type="button"
            class="ingenic-feed__page ingenic-feed__page--step"
            disabled={{this.isFirstPage}}
            aria-label={{i18n (themePrefix "ingenic.home.previous_page")}}
            {{on "click" (fn this.choosePage this.previousPage)}}
          >
            {{dIcon "chevron-left"}}
          </button>

          {{#each this.pageLinks as |page|}}
            <button
              type="button"
              class="ingenic-feed__page {{if page.active 'is-active'}}"
              aria-current={{if page.active "page"}}
              {{on "click" (fn this.choosePage page.number)}}
            >
              {{page.number}}
            </button>
          {{/each}}

          <button
            type="button"
            class="ingenic-feed__page ingenic-feed__page--step"
            disabled={{this.isLastPage}}
            aria-label={{i18n (themePrefix "ingenic.home.next_page")}}
            {{on "click" (fn this.choosePage this.nextPage)}}
          >
            {{dIcon "chevron-right"}}
          </button>
        </nav>
      {{else}}
        <a class="ingenic-section__footer" href={{this.allPath}}>
          {{i18n (themePrefix "ingenic.home.show_all")}}
          {{dIcon "arrow-right"}}
        </a>
      {{/if}}
    </section>
  </template>
}
