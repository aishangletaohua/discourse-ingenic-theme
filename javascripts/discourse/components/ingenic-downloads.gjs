import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { fn, get } from "@ember/helper";
import { eq } from "discourse/truth-helpers";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import { themePrefix } from "virtual:theme";
import getURL from "discourse/lib/get-url";
import { ajax } from "discourse/lib/ajax";
import { i18n } from "discourse-i18n";
import { withReadingLocale } from "../ingenic/reading-locale";

const ENDPOINT = "/ingenic/downloads";

/**
 * What each access state offers, and what it is called.
 *
 * The server decides which state a resource is in and this only decides how to
 * draw it, so there is no path on which the button says "Download" and the file
 * endpoint disagrees. A new tier means a line here and strings in the locale
 * file, not a new branch in the template.
 */
// What each state says under the one button. The button itself is always
// "Download" — the access rule decides what pressing it does, not what it is
// called, because a visitor reading the catalogue is looking for a file and
// not for the name of a permission tier.
const HINTS = {
  sign_in: "sign_in_hint",
  profile: "profile_hint",
  request: "apply_hint",
  pending: "pending_hint",
  rejected: "rejected_hint",
  unlock: "unlock_hint",
  points: "points_hint",
  download: null,
};

const ACTION_FOR = {
  anonymous: "sign_in",
  needs_profile: "profile",
  needs_request: "request",
  pending: "pending",
  rejected: "rejected",
  needs_points: "points",
  granted: "download",
};

/**
 * Download centre. Filter values are derived from the resource data returned by
 * the plugin, so a new product or version shows up in the filters as soon as it
 * is added — no theme change required.
 *
 * The developer form and the application form are drawn in place rather than in
 * a modal: both are a step in a sequence the visitor is already reading, and a
 * modal would hide the resource they are asking about.
 */
export default class IngenicDownloads extends Component {
  @tracked downloads = [];
  // Which version the visitor picked under a card, by resource id. The card's
  // description, size and download link all follow this; the access state does
  // not, because approval belongs to the resource rather than to one release.
  @tracked versionChoice = {};
  @tracked filters = { series: [], chips: [], categories: [] };
  @tracked selected = {
    family: "",
    series: "",
    product: "",
    category: "",
  };
  @tracked form = { fields: [], values: {}, completed: false };
  // The answers as they are being edited. The identity in here decides which
  // conditional questions are drawn, so choosing "Individual developer" takes
  // the company questions away before anything is submitted.
  @tracked profileValues = {};
  @tracked signedIn = false;
  @tracked points = 0;
  @tracked pointsEnabled = false;
  @tracked loading = true;
  @tracked panel = null;
  @tracked busy = false;
  @tracked notice = null;
  @tracked error = null;

  get loginPath() {
    return getURL("/login");
  }

  // A chip belongs to exactly one series, so choosing a series narrows the chip
  // list rather than offering every chip on the site and then rejecting most of
  // them. Without a series chosen, every chip is offered — a visitor who knows
  // the part number should not have to find its family first.
  get chipOptions() {
    if (!this.selected.series) {
      return this.filters.chips;
    }

    return this.filters.chips.filter(
      (chip) => chip.series_slug === this.selected.series
    );
  }

  // Every label and decision the card needs, worked out here so the template
  // stays a description of the layout rather than a set of lookups.
  //
  // The button is the same word in every state. What changes is the hint under
  // it and what pressing it does: a link for a file this account may already
  // have, the sign-in page for a visitor, a form for a developer the forum has
  // not met yet, an application for a release made on request.
  get cards() {
    return this.downloads.map((download) => {
      const versions = download.versions ?? [];
      const chosen = this.versionChoice[download.id];
      const version =
        versions.find((entry) => String(entry.id) === String(chosen)) ??
        versions[0] ??
        null;

      let action = ACTION_FOR[download.access_state] ?? "pending";
      const price = download.point_cost ?? 0;

      if (action === "download" && price > 0 && !download.unlocked) {
        action = "unlock";
      }

      const hintKey = HINTS[action];

      return {
        ...download,
        versions,
        version,
        versionId: version?.id ?? "",
        canChooseVersion: versions.length > 1,
        // The description belongs to the selected version: choosing SDK 1.0
        // after 1.1 has to say what 1.0 is, not what the card said before.
        description: version?.description,
        action,
        actionLabel: this.#label("download"),
        initial: (download.name || "?").trim().charAt(0).toUpperCase(),
        actionHint: hintKey ? this.#label(hintKey, { points: price }) : null,
        // A link is drawn for the three states whose next step is a page: the
        // file itself, the sign-in form. The rest open an in-page panel so the
        // visitor does not lose the catalogue they were reading.
        isLink: action === "download" || action === "unlock" || action === "sign_in",
        linkPath:
          action === "sign_in" ? this.loginPath : (version?.file_path ?? "#"),
        leavesSite: action !== "sign_in",
        metaLine: [
          download.category_name,
          version?.platform,
          version?.file_size,
          version?.released_on,
        ]
          .filter(Boolean)
          .join(" · "),
      };
    });
  }

  // The option text for a version. A release without a label is still a file,
  // and the date is what distinguishes it from the next one.
  versionLabel(version) {
    return version.version || version.released_on || "—";
  }

  @action
  pickVersion(downloadId, event) {
    this.versionChoice = {
      ...this.versionChoice,
      [downloadId]: event.target.value,
    };
  }

  get needsDeveloperForm() {
    return this.signedIn && !this.form.completed;
  }

  // Questions that belong to one identity carry a condition; the rest are for
  // everyone. The server applies the same rule to validation, so a hidden
  // question cannot be submitted and then refused.
  get visiblePanelFields() {
    return (this.form.fields ?? []).filter((field) => {
      const condition = field.when;
      if (!condition) {
        return true;
      }

      return String(this.profileValues[condition.key] ?? "") === String(condition.value);
    });
  }

  get panelValues() {
    return this.profileValues;
  }

  // Shown to a signed-in visitor on a forum where points are on, and to nobody
  // else: an anonymous visitor has no balance to read, and a forum with points
  // switched off has nothing to say about them.
  get showsPoints() {
    return this.signedIn && this.pointsEnabled;
  }

  get pointsPath() {
    return getURL("/ingenic/points");
  }

  @action
  async load() {
    await this.#fetch();
  }

  // The catalogue's first row: every chip series in the product tree, plus the
  // algorithm line when algorithms have been published. Both come from data —
  // a series is added, renamed and ordered on the documentation screen, and the
  // algorithm line disappears when its last resource does — so this row is not
  // a fixed list in the theme.
  get seriesButtons() {
    const selected = {
      family: this.selected.family,
      series: this.selected.series,
    };
    const all = { id: "all", label: i18n(themePrefix("ingenic.downloads.all_series")) };

    const series = (this.filters.series ?? []).filter(
      (entry) => !this.hasAlgorithm || entry.slug !== "algorithm"
    );

    const buttons = series.map((entry) => ({
      id: entry.slug,
      label: entry.name,
      kind: "series",
    }));

    if (this.hasAlgorithm) {
      // If the site keeps a series row for algorithms, its name is the label:
      // renaming that one row renames this option too. The option still exists
      // without it, because the resources are what make it real.
      const named = (this.filters.series ?? []).find(
        (entry) => entry.slug === "algorithm"
      );

      buttons.push({
        id: "algorithm",
        label: named?.name || i18n(themePrefix("ingenic.downloads.family.algorithm")),
        kind: "algorithm",
      });
    }

    return [
      { ...all, kind: "all", current: !selected.family && !selected.series },
      ...buttons.map((button) => ({
        ...button,
        current:
          button.kind === "algorithm"
            ? selected.family === "algorithm"
            : selected.family !== "algorithm" && selected.series === button.id,
      })),
    ];
  }

  get hasAlgorithm() {
    return (this.filters.families ?? []).includes("algorithm");
  }

  get isAlgorithmFamily() {
    return this.selected.family === "algorithm";
  }

  // Choosing a series drops the chip and type below it: a filter that keeps a
  // value which is no longer in its own list returns an empty page for a
  // reason the visitor cannot see.
  @action
  async pickSeries(item) {
    if (item.kind === "algorithm") {
      this.selected = {
        ...this.selected,
        family: "algorithm",
        series: "",
        product: "",
        category: "",
      };
    } else if (item.kind === "all") {
      this.selected = {
        ...this.selected,
        family: "",
        series: "",
        product: "",
        category: "",
      };
    } else {
      this.selected = {
        ...this.selected,
        family: "",
        series: item.id,
        product: "",
        category: "",
      };
    }

    await this.#fetch();
  }

  // The model row. A chip belongs to one series, so choosing a series narrows
  // this list; with no series chosen every chip in the catalogue is offered,
  // because a visitor who knows the part number should not have to find its
  // family first.
  get productButtons() {
    const selected = this.selected.product ?? "";

    return [
      {
        id: "",
        label: i18n(themePrefix("ingenic.downloads.all_products")),
        current: selected === "",
      },
      ...this.chipOptions.map((chip) => ({
        id: chip.slug,
        label: chip.name,
        current: selected === chip.slug,
      })),
    ];
  }

  // An algorithm runs across chips, so there is no model to choose and the row
  // would be a control with one answer. It is left out rather than shown
  // disabled: a row that cannot do anything is furniture.
  get showsModels() {
    return !this.isAlgorithmFamily && this.chipOptions.length > 0;
  }

  @action
  async pickProduct(value) {
    this.selected = { ...this.selected, product: value ?? "", category: "" };
    await this.#fetch();
  }

  // The type filter is drawn as a row of buttons rather than a select: there
  // are only a handful of types, they are the first thing a visitor narrows by,
  // and a select hid all of them behind one click. The id arrives as a number
  // from the row and as a string from the URL, so both are normalised here.
  @action
  async pickCategory(id) {
    await this.#applyFilter("category", id == null ? "" : String(id));
  }

  // Only the types this chip actually has. The server sends where each type is
  // used, so a visitor who picked a chip sees its own list rather than every
  // type on the site — most of which would return nothing and read as a bug.
  #categoriesForSelection() {
    const all = this.filters.categories ?? [];
    const { family, product, series } = this.selected;

    if (product) {
      return all.filter((category) =>
        (category.product_slugs ?? []).includes(product)
      );
    }

    if (series) {
      const slugs = this.filters.chips
        .filter((chip) => chip.series_slug === series)
        .map((chip) => chip.slug);

      return all.filter((category) =>
        (category.product_slugs ?? []).some((slug) => slugs.includes(slug))
      );
    }

    if (family) {
      return all.filter((category) =>
        (category.families ?? []).includes(family)
      );
    }

    return all;
  }

  // Built here rather than compared in the template: a template call with an
  // argument is what broke the first version of this row, and a list of plain
  // values cannot fail to resolve while the page is drawing.
  get categoryButtons() {
    const selected = String(this.selected.category ?? "");

    return [
      {
        id: null,
        label: i18n(themePrefix("ingenic.downloads.all_resources")),
        current: selected === "",
      },
      ...this.#categoriesForSelection().map((category) => ({
        id: category.id,
        label: category.name,
        current: selected === String(category.id),
      })),
    ];
  }

  // The form opens on the resource that asked for it, so the visitor can see
  // which file they are answering about while they answer.
  @action
  openPanel(kind, download, event) {
    event?.preventDefault();
    this.notice = null;
    this.error = null;
    if (kind === "profile") {
      this.profileValues = { ...(this.form.values ?? {}) };
    }
    this.panel = { kind, download };
  }

  // Only the select uses this today, but writing it as a generic handler keeps
  // a conditional question working if one is ever keyed off a text answer.
  @action
  updateProfileValue(key, event) {
    this.profileValues = { ...this.profileValues, [key]: event.target.value };
  }

  @action
  closePanel() {
    this.panel = null;
    this.error = null;
  }

  @action
  async saveProfile(event) {
    event.preventDefault();
    this.busy = true;
    this.error = null;

    const answers = Object.fromEntries(new FormData(event.target));

    try {
      const response = await ajax(`${ENDPOINT}/profile`, {
        type: "POST",
        data: { profile: answers },
      });
      this.form = response.form ?? this.form;
      this.notice = this.#label("profile_saved");

      const target = this.panel?.download;
      this.panel = null;
      await this.#fetch();

      // The form was opened by pressing Download, so the download is where the
      // visitor expects to be taken. If the answers cleared the resource, the
      // file starts now; if it still needs an application, that panel opens
      // rather than making them find the card again and press Download twice.
      if (target) {
        await this.#continueAfterProfile(target.id);
      }
    } catch (failure) {
      this.error = this.#failureMessage(failure);
    } finally {
      this.busy = false;
    }
  }

  @action
  async sendRequest(event) {
    event.preventDefault();
    this.busy = true;
    this.error = null;

    const { message } = Object.fromEntries(new FormData(event.target));

    try {
      const response = await ajax(
        `${ENDPOINT}/${this.panel.download.id}/request`,
        { type: "POST", data: { message } }
      );
      this.notice = response.notice || this.#label("request_sent");
      this.panel = null;
      await this.#fetch();
    } catch (failure) {
      this.error = this.#failureMessage(failure);
    } finally {
      this.busy = false;
    }
  }

  @action
  dismissNotice() {
    this.notice = null;
  }

  // What pressing Download leads to once the developer form is saved.
  async #continueAfterProfile(downloadId) {
    const download = this.downloads.find((entry) => entry.id === downloadId);

    if (!download) {
      return;
    }

    if (download.access_state === "needs_request") {
      this.panel = { kind: "request", download };
      return;
    }

    if (download.access_state === "granted") {
      const card = this.cards.find((entry) => entry.id === downloadId);
      if (card?.linkPath) {
        window.location.assign(card.linkPath);
      }
    }
  }

  #label(key, params) {
    return i18n(themePrefix(`ingenic.downloads.${key}`), params);
  }

  #failureMessage(failure) {
    const errors = failure?.jqXHR?.responseJSON?.errors;
    return errors?.join(" ") || this.#label("failed");
  }

  async #applyFilter(key, value) {
    this.selected = { ...this.selected, [key]: value };
    await this.#fetch();
  }

  // Only the newest request may write. A click on a second chip does not wait
  // for the first response, and without this token the slower request could
  // land last and paint the list for the filter the visitor already left.
  #requestSeq = 0;

  async #fetch() {
    const seq = ++this.#requestSeq;
    this.loading = true;

    const params = new URLSearchParams();
    Object.entries(this.selected).forEach(([key, value]) => {
      if (value) {
        params.set(key, value);
      }
    });

    const query = params.toString();
    const url = getURL(ENDPOINT);

    const target = query ? `${url}?${query}` : url;

    try {
      const response = await fetch(withReadingLocale(target), {
        headers: { Accept: "application/json" },
      });

      if (seq !== this.#requestSeq) {
        return;
      }

      if (response.ok) {
        const payload = await response.json();
        this.downloads = payload.downloads ?? [];
        this.form = payload.form ?? this.form;
        this.signedIn = payload.signed_in ?? false;
        this.points = payload.points ?? 0;
        this.pointsEnabled = payload.points_enabled ?? false;

        // Filter options always come from the unfiltered response so the user
        // can widen the selection again after narrowing it.
        if (!query) {
          this.filters = payload.filters ?? this.filters;
        }
      }
    } catch {
      if (seq === this.#requestSeq) {
        this.downloads = [];
      }
    } finally {
      if (seq === this.#requestSeq) {
        this.loading = false;
      }
    }
  }

  <template>
    <section class="ingenic-section" {{didInsert this.load}}>
      <header class="ingenic-section__header">
        <div>
          <h1>{{i18n (themePrefix "ingenic.downloads.title")}}</h1>
          <p class="ingenic-section__subtitle">
            {{i18n (themePrefix "ingenic.downloads.subtitle")}}
          </p>
        </div>

        {{#if this.showsPoints}}
          <a class="ingenic-points__balance" href={{this.pointsPath}}>
            <span class="ingenic-points__balance-value">{{this.points}}</span>
            <span class="ingenic-points__balance-label">
              {{i18n (themePrefix "ingenic.downloads.points_balance")}}
            </span>
          </a>
        {{/if}}
      </header>

      {{#if this.notice}}
        <p class="ingenic-notice ingenic-notice--ok">
          {{this.notice}}
          <button
            class="ingenic-notice__close"
            type="button"
            {{on "click" this.dismissNotice}}
          >×</button>
        </p>
      {{/if}}

      {{#if this.error}}
        <p class="ingenic-notice ingenic-notice--error">{{this.error}}</p>
      {{/if}}

      <div
        class="ingenic-downloads__filter"
        role="group"
        aria-label={{i18n (themePrefix "ingenic.downloads.series_label")}}
      >
        <span class="ingenic-downloads__filter-label">
          {{i18n (themePrefix "ingenic.downloads.series_label")}}
        </span>
        <div class="ingenic-downloads__options">
          {{#each this.seriesButtons as |item|}}
            <button
              type="button"
              class="ingenic-downloads__option {{if item.current 'is-current'}}"
              aria-pressed={{item.current}}
              disabled={{this.loading}}
              {{on "click" (fn this.pickSeries item)}}
            >
              {{item.label}}
            </button>
          {{/each}}
        </div>
      </div>

      {{#if this.showsModels}}
        <div
          class="ingenic-downloads__filter"
          role="group"
          aria-label={{i18n (themePrefix "ingenic.downloads.product_label")}}
        >
          <span class="ingenic-downloads__filter-label">
            {{i18n (themePrefix "ingenic.downloads.product_label")}}
          </span>
          <div class="ingenic-downloads__options">
            {{#each this.productButtons as |item|}}
              <button
                type="button"
                class="ingenic-downloads__option {{if item.current 'is-current'}}"
                aria-pressed={{item.current}}
                disabled={{this.loading}}
                {{on "click" (fn this.pickProduct item.id)}}
              >
                {{item.label}}
              </button>
            {{/each}}
          </div>
        </div>
      {{/if}}

      <div
        class="ingenic-downloads__filter"
        role="group"
        aria-label={{i18n (themePrefix "ingenic.downloads.category_label")}}
      >
        <span class="ingenic-downloads__filter-label">
          {{i18n (themePrefix "ingenic.downloads.category_label")}}
        </span>
        <div class="ingenic-downloads__options ingenic-downloads__options--wrap">
          {{#each this.categoryButtons as |item|}}
            <button
              type="button"
              class="ingenic-downloads__option {{if item.current 'is-current'}}"
              aria-pressed={{item.current}}
              disabled={{this.loading}}
              {{on "click" (fn this.pickCategory item.id)}}
            >
              {{item.label}}
            </button>
          {{/each}}
        </div>
      </div>

      {{#if this.needsDeveloperForm}}
        <div class="ingenic-downloads__prompt">
          <div>
            <strong>{{i18n (themePrefix "ingenic.downloads.developer_form")}}</strong>
            <p>{{i18n (themePrefix "ingenic.downloads.developer_form_intro")}}</p>
          </div>
          <button class="btn" type="button" {{on "click" (fn this.openPanel "profile" null)}}>
            {{i18n (themePrefix "ingenic.downloads.profile_action")}}
          </button>
        </div>
      {{/if}}

      {{#if this.panel}}
        {{#if (eq this.panel.kind "profile")}}
          <form class="ingenic-downloads__panel" {{on "submit" this.saveProfile}}>
            <h2>{{i18n (themePrefix "ingenic.downloads.developer_form")}}</h2>

            <div class="ingenic-downloads__fields">
              {{#each this.visiblePanelFields as |field|}}
                <label class="ingenic-docs__field">
                  <span>
                    {{field.label}}
                    {{#if field.required}}<em>*</em>{{/if}}
                  </span>
                  {{#if (eq field.type "select")}}
                    <select
                      name={{field.key}}
                      value={{get this.panelValues field.key}}
                      {{on "change" (fn this.updateProfileValue field.key)}}
                    >
                      <option value="">{{i18n (themePrefix "ingenic.downloads.choose")}}</option>
                      {{#each field.options as |option|}}
                        <option value={{option.value}}>{{option.label}}</option>
                      {{/each}}
                    </select>
                  {{else if (eq field.type "textarea")}}
                    <textarea name={{field.key}} rows="3">{{get this.panelValues field.key}}</textarea>
                  {{else}}
                    <input name={{field.key}} value={{get this.panelValues field.key}} />
                  {{/if}}
                </label>
              {{/each}}
            </div>

            <div class="ingenic-downloads__panel-actions">
              <button class="btn btn-primary" type="submit" disabled={{this.busy}}>
                {{i18n (themePrefix "ingenic.downloads.submit_profile")}}
              </button>
              <button class="btn" type="button" {{on "click" this.closePanel}}>
                {{i18n (themePrefix "ingenic.downloads.cancel")}}
              </button>
            </div>
          </form>
        {{else}}
          <form class="ingenic-downloads__panel" {{on "submit" this.sendRequest}}>
            <h2>
              {{i18n (themePrefix "ingenic.downloads.apply")}}
              {{#if this.panel.download}}· {{this.panel.download.name}}{{/if}}
            </h2>

            <label class="ingenic-docs__field">
              <span>{{i18n (themePrefix "ingenic.downloads.message")}}</span>
              <textarea name="message" rows="4"></textarea>
            </label>

            <div class="ingenic-downloads__panel-actions">
              <button class="btn btn-primary" type="submit" disabled={{this.busy}}>
                {{i18n (themePrefix "ingenic.downloads.submit_request")}}
              </button>
              <button class="btn" type="button" {{on "click" this.closePanel}}>
                {{i18n (themePrefix "ingenic.downloads.cancel")}}
              </button>
            </div>
          </form>
        {{/if}}
      {{/if}}

      {{#if this.cards.length}}
        <div class="ingenic-download-cards">
          {{#each this.cards as |card|}}
            <article class="ingenic-download-card">
              <div class="ingenic-download-card__media">
                {{#if card.image_url}}
                  <img src={{card.image_url}} alt="" loading="lazy" />
                {{else}}
                  <span class="ingenic-download-card__placeholder">{{card.initial}}</span>
                {{/if}}
              </div>

              <div class="ingenic-download-card__body">
                <h3 class="ingenic-download-card__title">{{card.name}}</h3>

                {{#if card.metaLine}}
                  <div class="ingenic-download-card__meta">{{card.metaLine}}</div>
                {{/if}}

                {{#if card.canChooseVersion}}
                  <label class="ingenic-download-card__version">
                    <span>{{i18n (themePrefix "ingenic.downloads.version_label")}}</span>
                    {{! `value` on a <select> is only an attribute, so it never moved the
                        chosen option. Marking the option is what keeps the box showing
                        the version the card is actually pointing at. }}
                    <select
                      name="version"
                      {{on "change" (fn this.pickVersion card.id)}}
                    >
                      {{#each card.versions as |version|}}
                        <option
                          selected={{eq version.id card.versionId}}
                          value={{version.id}}
                        >{{this.versionLabel version}}</option>
                      {{/each}}
                    </select>
                  </label>
                {{else if card.version.version}}
                  <div class="ingenic-download-card__version-static">
                    {{i18n (themePrefix "ingenic.downloads.version_label")}}
                    {{card.version.version}}
                  </div>
                {{/if}}

                {{#if card.description}}
                  <p class="ingenic-download-card__description">{{card.description}}</p>
                {{/if}}
              </div>

              <div class="ingenic-download-card__action">
                {{#if card.isLink}}
                  {{#if card.leavesSite}}
                    <a
                      class="btn btn-primary"
                      href={{card.linkPath}}
                      target="_blank"
                      rel="noopener noreferrer"
                    >
                      {{card.actionLabel}}
                    </a>
                  {{else}}
                    <a class="btn btn-primary" href={{card.linkPath}}>
                      {{card.actionLabel}}
                    </a>
                  {{/if}}
                {{else if (eq card.action "profile")}}
                  <button
                    class="btn btn-primary"
                    type="button"
                    {{on "click" (fn this.openPanel "profile" card)}}
                  >
                    {{card.actionLabel}}
                  </button>
                {{else if (eq card.action "request")}}
                  <button
                    class="btn btn-primary"
                    type="button"
                    {{on "click" (fn this.openPanel "request" card)}}
                  >
                    {{card.actionLabel}}
                  </button>
                {{else}}
                  <button class="btn btn-primary" type="button" disabled>
                    {{card.actionLabel}}
                  </button>
                {{/if}}

                {{#if card.actionHint}}
                  <p class="ingenic-download-card__hint">{{card.actionHint}}</p>
                {{/if}}
              </div>
            </article>
          {{/each}}
        </div>
      {{else if this.loading}}
        <p class="ingenic-card__meta">…</p>
      {{else}}
        <p class="ingenic-card__meta">
          {{i18n (themePrefix "ingenic.downloads.empty")}}
        </p>
      {{/if}}
    </section>
  </template>
}
