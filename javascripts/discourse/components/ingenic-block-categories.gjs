import { themePrefix } from "virtual:theme";
import Component from "@glimmer/component";
import { service } from "@ember/service";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";
import { markFor } from "../ingenic/category-marks";

// A category only carries an icon when an administrator sets one, and most
// forums do not bother. The sections this forum ships with are the ones a
// visitor sees on the front page, so they get a glyph of their own. The table
// is shared with the category page and the sidebar, so a section is drawn the
// same way wherever its name appears.

/**
 * The forum's sections, as the home page's way into the forum.
 *
 * Three sources, in this order: the cards an administrator wrote on Site
 * content → Home cards; the category slugs an editor put on this block; and,
 * with neither, three cards that fit this forum out of the box — technical
 * discussions, the documentation reader, and announcements. The documentation
 * card is why a card can carry its own destination: the reader is not a
 * category, and inventing one for it would make the forum claim a section it
 * does not have.
 *
 * A card naming a category borrows that category's name, colour and icon from
 * `site.categories`, so what the front page says about a section is what its
 * page says.
 */
export default class IngenicBlockCategories extends Component {
  @service site;

  get configured() {
    return this.args.block?.categories ?? [];
  }

  get limit() {
    return this.args.block?.limit || 3;
  }

  get topLevel() {
    return this.site.categories.filter(
      (category) => !category.parent_category_id
    );
  }

  get cards() {
    const written = this.site.ingenic_section_cards ?? [];

    if (written.length) {
      return written.map((card) => this.cardFromConfig(card)).filter(Boolean);
    }

    if (this.configured.length) {
      return this.configured
        .map((slug) => this.cardFromCategory(this.topLevel.find((c) => c.slug === slug)))
        .filter(Boolean);
    }

    return this.defaultCards;
  }

  get defaultCards() {
    const wanted = ["technical-discussions", "official-announcements"];
    const found = wanted
      .map((slug) => this.topLevel.find((category) => category.slug === slug))
      .filter(Boolean);

    const docs = {
      key: "docs",
      href: "/ingenic/docs",
      label: i18n(themePrefix("ingenic.nav.docs")),
      icon: "book",
      style: "--ingenic-category: #2f9e63",
    };

    // Documentation sits between the two forum sections, which is where a
    // developer arriving with a chip question looks before asking it.
    return [
      found[0] && this.cardFromCategory(found[0]),
      docs,
      found[1] && this.cardFromCategory(found[1]),
    ].filter(Boolean);
  }

  get showAll() {
    return this.args.block?.show_all !== false;
  }

  cardFromConfig(card) {
    if (card.category) {
      return this.cardFromCategory(
        this.site.categories.find((category) => category.slug === card.category),
        card
      );
    }

    return {
      key: `card-${card.id}`,
      href: card.href,
      label: card.label,
      icon: card.icon,
      image_url: card.image_url,
      style: card.color ? `--ingenic-category: #${card.color.replace(/^#/, "")}` : null,
    };
  }

  cardFromCategory(category, overlay = {}) {
    if (!category) {
      return null;
    }

    const mark = markFor(category);
    const color = overlay.color || mark?.tint || category.color;

    return {
      key: `category-${category.id}`,
      href: category.url,
      label: overlay.label || category.name,
      icon: overlay.icon || category.icon || mark?.icon || "comments",
      image_url: overlay.image_url,
      style: color ? `--ingenic-category: #${color.replace(/^#/, "")}` : null,
    };
  }

  <template>
    <section class="ingenic-sections-block">
      <header class="ingenic-sections-block__header">
        <h2>
          <span class="ingenic-section__icon">{{dIcon "layer-group"}}</span>
          {{i18n (themePrefix "ingenic.home.sections.title")}}
        </h2>

        {{#if this.showAll}}
          <a class="ingenic-sections-block__all" href="/categories">
            {{i18n (themePrefix "ingenic.home.sections.all")}}
            {{dIcon "arrow-right"}}
          </a>
        {{/if}}
      </header>

      {{#if this.cards.length}}
        <div class="ingenic-sections">
          {{#each this.cards as |card|}}
            <a
              class="ingenic-sections__card"
              href={{card.href}}
              style={{card.style}}
            >
              <span class="ingenic-sections__icon" aria-hidden="true">
                {{#if card.image_url}}
                  <img
                    class="ingenic-sections__image"
                    src={{card.image_url}}
                    alt=""
                    loading="lazy"
                  />
                {{else if card.icon}}
                  {{dIcon card.icon}}
                {{/if}}
              </span>

              <span class="ingenic-sections__text">
                <span class="ingenic-sections__name">{{card.label}}</span>
              </span>
            </a>
          {{/each}}
        </div>
      {{else}}
        <p class="ingenic-section__subtitle">
          {{i18n (themePrefix "ingenic.home.sections.empty")}}
        </p>
      {{/if}}
    </section>
  </template>
}
