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

/**
 * Homepage block: what the Ingenic team has posted lately.
 *
 * This is not the forum's "latest" list and not the promotions slots. It reads
 * the official announcements section, newest first, and shows three of them:
 * the events and notices the team actually wrote, each linking to its topic.
 * "View all" goes to the section itself, which is where the rest live.
 *
 * Kept apart from the announcements block on purpose — that one is an editor's
 * curated list with a heading, while this is a fixed reading of one section
 * that the rail always shows.
 */
export default class IngenicBlockActivity extends Component {
  @service store;

  @tracked topics = [];
  @tracked loaded = false;
  requested = false;

  get category() {
    return this.args.block?.category || "official-announcements";
  }

  get limit() {
    return this.args.block?.limit || 3;
  }

  get title() {
    return (
      this.args.block?.title ||
      i18n(themePrefix("ingenic.activity.title"))
    );
  }

  get allPath() {
    return getURL(`/c/${this.category}`);
  }

  // Newest first by what the reader actually sees change. The category feed
  // puts a pinned "About" topic ahead of everything, so the order on the wire
  // is not the order this card promises.
  get rows() {
    const at = (topic) => new Date(topic.last_posted_at || topic.created_at);
    return [...this.topics]
      .sort((a, b) => at(b) - at(a))
      .slice(0, this.limit)
      .map((topic) => {
        const when = at(topic);
        return {
          id: topic.id,
          title: topic.title,
          url: topic.url,
          at: topic.last_posted_at || topic.created_at,
          // A calendar leaf, the way an events list dates its rows: the day is
          // what a reader scans, and it does not need a locale-dependent
          // "3 days ago" to be read.
          month: new Intl.DateTimeFormat(undefined, { month: "short" })
            .format(when)
            .toUpperCase(),
          day: when.getDate(),
        };
      });
  }

  @action
  async load() {
    if (this.requested) {
      return;
    }

    this.requested = true;

    try {
      const result = await this.store.findFiltered("topicList", {
        filter: `c/${this.category}/l/latest`,
      });

      this.topics = result.topics ?? [];
    } catch {
      this.topics = [];
    } finally {
      this.loaded = true;
    }
  }

  <template>
    <section class="ingenic-section ingenic-activity" {{didInsert this.load}}>
      <header class="ingenic-section__header">
        <h2>
          <span class="ingenic-section__icon">{{dIcon "bullhorn"}}</span>
          {{this.title}}
        </h2>
      </header>

      {{#if this.rows.length}}
        <ul class="ingenic-activity__list">
          {{#each this.rows as |row|}}
            <li class="ingenic-activity__item">
              <span class="ingenic-activity__date" aria-hidden="true">
                <span class="ingenic-activity__month">{{row.month}}</span>
                <span class="ingenic-activity__day">{{row.day}}</span>
              </span>

              <span class="ingenic-activity__body">
                <a class="ingenic-activity__title" href={{row.url}}>{{row.title}}</a>
                <span class="ingenic-activity__when">
                  {{dFormatDate row.at leaveAgo="true"}}
                </span>
              </span>
            </li>
          {{/each}}
        </ul>
      {{else if this.loaded}}
        <p class="ingenic-section__subtitle">
          {{i18n (themePrefix "ingenic.home.empty")}}
        </p>
      {{else}}
        <ul class="ingenic-activity__list" aria-hidden="true">
          <li class="ingenic-activity__item ingenic-activity__item--skeleton">
            <span class="ingenic-skeleton ingenic-skeleton--title"></span>
            <span class="ingenic-skeleton ingenic-skeleton--meta"></span>
          </li>
          <li class="ingenic-activity__item ingenic-activity__item--skeleton">
            <span class="ingenic-skeleton ingenic-skeleton--title"></span>
            <span class="ingenic-skeleton ingenic-skeleton--meta"></span>
          </li>
          <li class="ingenic-activity__item ingenic-activity__item--skeleton">
            <span class="ingenic-skeleton ingenic-skeleton--title"></span>
            <span class="ingenic-skeleton ingenic-skeleton--meta"></span>
          </li>
        </ul>
      {{/if}}

      <a class="ingenic-section__footer" href={{this.allPath}}>
        {{i18n (themePrefix "ingenic.home.show_all")}}
        {{dIcon "arrow-right"}}
      </a>
    </section>
  </template>
}
