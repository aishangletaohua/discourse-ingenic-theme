import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import didUpdate from "@ember/render-modifiers/modifiers/did-update";
import getURL from "discourse/lib/get-url";
import { i18n } from "discourse-i18n";
import { themePrefix } from "virtual:theme";
import { withReadingLocale } from "../ingenic/reading-locale";

/**
 * A standalone page: the terms, the privacy policy, the rules for points.
 *
 * The body arrives already rendered, because the server is the one that owns
 * the Markdown parser and the sanitiser; the page only gives it a column to
 * read in. The date is the page's last edit, and is left out entirely for a
 * page that is still the copy the plugin ships with — there is no edit to
 * report.
 *
 * The reader's language is sent with the request. Switching language reloads
 * the app, so the component is built again and asks for the new language's
 * page at the same address.
 */
export default class IngenicPage extends Component {
  @tracked page = null;
  @tracked notFound = false;
  @tracked loading = true;
  @tracked failed = false;

  get updatedLabel() {
    if (!this.page?.updated_at) {
      return null;
    }

    return i18n(themePrefix("ingenic.page.updated"), {
      date: new Date(this.page.updated_at).toLocaleDateString(),
    });
  }

  get homePath() {
    return getURL("/");
  }

  @action
  async load() {
    this.loading = true;
    this.notFound = false;
    this.failed = false;

    try {
      const response = await fetch(
        withReadingLocale(getURL(`/ingenic/pages/${this.args.slug}`)),
        {
          headers: { Accept: "application/json" },
          // The text changes when an editor saves it. A cached copy would be
          // the previous version of a page that is printed and quoted.
          cache: "no-store",
        }
      );

      if (response.status === 404) {
        this.page = null;
        this.notFound = true;
        return;
      }

      if (!response.ok) {
        throw new Error(`HTTP ${response.status}`);
      }

      const payload = await response.json();
      this.page = payload.page;
    } catch {
      this.failed = true;
    } finally {
      this.loading = false;
    }
  }

  get title() {
    if (this.loading) {
      return i18n(themePrefix("ingenic.page.loading"));
    }

    if (this.notFound) {
      return i18n(themePrefix("ingenic.page.not_found_title"));
    }

    if (this.failed) {
      return i18n(themePrefix("ingenic.page.failed_title"));
    }

    return this.page?.title ?? "";
  }

  <template>
    <section
      class="ingenic-section ingenic-page"
      {{didInsert this.load}}
      {{didUpdate this.load @slug}}
    >
      <header class="ingenic-section__header">
        <div>
          <h1 class="ingenic-page__title">{{this.title}}</h1>
          {{#if this.updatedLabel}}
            <p class="ingenic-page__updated">{{this.updatedLabel}}</p>
          {{/if}}
        </div>
      </header>

      <article class="ingenic-page__body">
        {{#if this.loading}}
          <p>{{i18n (themePrefix "ingenic.page.loading")}}</p>
        {{else if this.notFound}}
          <p>{{i18n (themePrefix "ingenic.page.not_found_body")}}</p>
          <p>
            <a href={{this.homePath}}>
              {{i18n (themePrefix "ingenic.page.back")}}
            </a>
          </p>
        {{else if this.failed}}
          <p>{{i18n (themePrefix "ingenic.page.failed_body")}}</p>
        {{else}}
          {{{this.page.html}}}
        {{/if}}
      </article>
    </section>
  </template>
}
