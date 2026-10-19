import { themePrefix } from "virtual:theme";
import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import getURL from "discourse/lib/get-url";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";

const ENDPOINT = "/ingenic/leaderboard";
const LIMIT = 50;

/**
 * The weekly contribution board, in full.
 *
 * The card on the home page shows the top five and a way here; this is the
 * rest of the list plus the viewer's own line, which the card has no room to
 * explain. Contribution is not points: a bounty payout does not appear here.
 */
export default class IngenicLeaderboardPage extends Component {
  @tracked entries = [];
  @tracked viewer = null;
  @tracked loaded = false;

  get rows() {
    return this.entries.map((entry) => ({
      ...entry,
      avatar: entry.avatar_template?.replace("{size}", "48"),
      path: getURL(`/u/${entry.username}`),
    }));
  }

  get viewerRow() {
    if (!this.viewer || this.viewer.points === undefined) {
      return null;
    }

    return {
      ...this.viewer,
      path: getURL(`/u/${this.viewer.username}`),
    };
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
        this.entries = payload.entries ?? [];
        this.viewer = payload.viewer ?? null;
      }
    } catch {
      this.entries = [];
    } finally {
      this.loaded = true;
    }
  }

  <template>
    <section class="ingenic-section ingenic-leaderboard-page" {{didInsert this.load}}>
      <header class="ingenic-section__header">
        <div>
          <h1>
            <span class="ingenic-section__icon">{{dIcon "trophy"}}</span>
            {{i18n (themePrefix "ingenic.leaderboard.page_title")}}
          </h1>
          <p class="ingenic-section__subtitle">
            {{i18n (themePrefix "ingenic.leaderboard.subtitle")}}
          </p>
        </div>

        {{#if this.viewerRow}}
          <div class="ingenic-leaderboard-page__you">
            <span>{{i18n (themePrefix "ingenic.leaderboard.you")}}</span>
            <strong>{{this.viewerRow.username}}</strong>
            <span class="ingenic-leaderboard-page__you-points">
              {{this.viewerRow.points}}
              {{i18n (themePrefix "ingenic.leaderboard.points")}}
            </span>
          </div>
        {{/if}}
      </header>

      {{#if this.rows.length}}
        <ol class="ingenic-leaderboard-page__list">
          {{#each this.rows as |row|}}
            <li class="ingenic-leaderboard-page__row">
              <span class="ingenic-leaderboard-page__rank">
                {{row.rank}}
              </span>

              {{#if row.avatar}}
                <img
                  class="ingenic-leaderboard-page__avatar"
                  src={{row.avatar}}
                  alt=""
                  loading="lazy"
                />
              {{else}}
                <span class="ingenic-leaderboard-page__avatar"></span>
              {{/if}}

              <a class="ingenic-leaderboard-page__user" href={{row.path}}>
                {{row.name}}
              </a>

              <span class="ingenic-leaderboard-page__points">
                {{row.points}}
                <span class="ingenic-leaderboard-page__unit">
                  {{i18n (themePrefix "ingenic.leaderboard.points")}}
                </span>
              </span>
            </li>
          {{/each}}
        </ol>
      {{else if this.loaded}}
        <p class="ingenic-section__subtitle">
          {{i18n (themePrefix "ingenic.leaderboard.board_empty")}}
        </p>
      {{else}}
        <p class="ingenic-section__subtitle">
          {{i18n (themePrefix "ingenic.leaderboard.loading")}}
        </p>
      {{/if}}
    </section>
  </template>
}
