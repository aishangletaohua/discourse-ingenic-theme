import { themePrefix } from "virtual:theme";
import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import getURL from "discourse/lib/get-url";
import { i18n } from "discourse-i18n";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { loadSiteContent } from "../ingenic/site-content";

// The date chip asks Intl for the month and the day separately, because the
// chip stacks them. The forum's own language decides the spelling, so "Sep"
// stays "9月" without the component carrying a table of month names.
function dateParts(value) {
  const date = new Date(value);
  const locale = document.documentElement.lang || undefined;

  return {
    month: date.toLocaleDateString(locale, { month: "short" }),
    day: date.toLocaleDateString(locale, { day: "numeric" }),
  };
}

/**
 * The promotion slots on the homepage.
 *
 * The slots are a list the Ingenic team edits, each with an optional window, so
 * a campaign can be written once and taken down by its own dates. Nothing here
 * knows what a campaign is: a slot whose window has passed simply does not come
 * back from the endpoint.
 *
 * Drawn as a row of panels rather than a carousel: a carousel hides two thirds
 * of the team's work behind a control most visitors never touch, and three slots
 * that fit on the page say more than three that take turns.
 *
 * The picture is an element behind the text rather than a CSS background, so
 * nothing an editor types is ever parsed as style.
 */
export default class IngenicPromotions extends Component {
  @tracked promotions = [];
  // The card is drawn before its slots exist, then removed if the team has
  // none: a section that only appears after the slowest request on the page
  // makes the rail jump, and the header is cheap to show early.
  @tracked loaded = false;

  // Loaded from here rather than from a `did-insert` on the section, because the
  // section is what the load decides to draw: a modifier inside the conditional
  // would be waiting for the element that is waiting for the modifier.
  //
  // The component can be built more than once per page — a route change rebuilds
  // the homepage — and the request itself is shared, so a second build costs
  // nothing and shows the slots immediately.
  constructor(owner, args) {
    super(owner, args);
    this.#load();
  }

  get title() {
    return this.args.block?.title || i18n(themePrefix("ingenic.promotions.title"));
  }

  get slots() {
    return this.promotions.map((promotion) => {
      // A campaign's date is its window; a slot with no window has been up
      // since it was written, so the day it was created is the honest date.
      const when = promotion.starts_at || promotion.ends_at || promotion.created_at;

      return {
        ...promotion,
        target: promotion.external ? "_blank" : "_self",
        rel: promotion.external ? "noopener noreferrer" : null,
        date: when ? dateParts(when) : null,
        iso: when || null,
      };
    });
  }

  get allPath() {
    return getURL("/latest");
  }

  get isVisible() {
    return !this.loaded || this.promotions.length > 0;
  }

  async #load() {
    try {
      const payload = await loadSiteContent();
      this.promotions = payload.promotions ?? [];
    } finally {
      this.loaded = true;
    }
  }

  <template>
    {{#if this.isVisible}}
      <section class="ingenic-section ingenic-promotions">
        <header class="ingenic-section__header">
          <h2>
            <span class="ingenic-section__icon">{{dIcon "bullhorn"}}</span>
            {{this.title}}
          </h2>
        </header>

        {{#if this.slots.length}}
          <div class="ingenic-promotions__grid">
            {{#each this.slots as |slot|}}
              <article class="ingenic-promotion">
                {{#if slot.image_url}}
                  <img
                    class="ingenic-promotion__image"
                    src={{slot.image_url}}
                    alt=""
                    loading="lazy"
                  />
                {{/if}}

                <div class="ingenic-promotion__content">
                  {{#if slot.corner_label}}
                    <span class="ingenic-promotion__corner">{{slot.corner_label}}</span>
                  {{/if}}

                  <div class="ingenic-promotion__headline">
                    {{#if slot.date}}
                      <time class="ingenic-promotion__date" datetime={{slot.iso}}>
                        <span class="ingenic-promotion__month">{{slot.date.month}}</span>
                        <span class="ingenic-promotion__day">{{slot.date.day}}</span>
                      </time>
                    {{/if}}

                    <h3 class="ingenic-promotion__title">{{slot.title}}</h3>
                  </div>

                  {{#if slot.description}}
                    <p class="ingenic-promotion__body">{{slot.description}}</p>
                  {{/if}}

                  {{#if slot.button_label}}
                    {{#if slot.button_href}}
                      <a
                        class="btn btn-primary"
                        href={{slot.button_href}}
                        target={{slot.target}}
                        rel={{slot.rel}}
                      >
                        {{slot.button_label}}
                      </a>
                    {{else}}
                      <span class="ingenic-promotion__label">{{slot.button_label}}</span>
                    {{/if}}
                  {{/if}}
                </div>
              </article>
            {{/each}}
          </div>

          <a class="ingenic-section__footer" href={{this.allPath}}>
            {{i18n (themePrefix "ingenic.home.show_all")}}
            {{dIcon "arrow-right"}}
          </a>
        {{else}}
          <div class="ingenic-promotions__grid" aria-hidden="true">
            <article class="ingenic-promotion ingenic-promotion--skeleton">
              <div class="ingenic-promotion__content">
                <span class="ingenic-skeleton ingenic-skeleton--title"></span>
                <span class="ingenic-skeleton ingenic-skeleton--meta"></span>
                <span class="ingenic-skeleton ingenic-skeleton--line"></span>
              </div>
            </article>
          </div>
        {{/if}}
      </section>
    {{/if}}
  </template>
}
