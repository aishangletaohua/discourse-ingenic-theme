import { themePrefix } from "virtual:theme";
import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { service } from "@ember/service";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { fn } from "@ember/helper";
import { eq } from "discourse/truth-helpers";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import I18n, { i18n } from "discourse-i18n";
import IngenicImage from "./ingenic-image";
import { loadSiteContent } from "../ingenic/site-content";

/**
 * The site footer: the brand, the partner strip, and the footer's link columns.
 *
 * The shape follows the Chinese forum: the wordmark and its slogan on the left,
 * the editable link columns on the right. The columns are what the team edits,
 * which is the point — a chip family is a category link this month and a
 * download filter the next, and neither should need a theme release to change.
 *
 * A platform is one of two shapes. A link opens somewhere; a QR code opens a
 * panel over the page showing the image, because a code that navigates is a
 * worse experience than a code that is looked at.
 *
 * The footer follows the language the forum was served in. English is the
 * stored default and Chinese sits beside it, so a column or link with no
 * Chinese spelling yet still reads rather than disappearing.
 */
export default class IngenicFooter extends Component {
  @service site;
  @service siteSettings;

  @tracked socialLinks = [];
  @tracked columns = [];
  @tracked openQr = null;

  // Loaded from here rather than from a `did-insert` on the footer, because the
  // footer is what the load decides to draw: a modifier inside the conditional
  // would be waiting for the element that is waiting for the modifier.
  //
  // The component is built again on every route change, and the request itself
  // is shared, so the repeats cost nothing and the footer is there immediately
  // on the pages after the first.
  constructor(owner, args) {
    super(owner, args);
    this.#load();
  }

  // The outlet the footer sits in is the site's footer, so it follows the site's
  // own decision about whether a footer is being shown at all.
  get showFooter() {
    return this.args.outletArgs?.showFooter !== false;
  }

  get isChinese() {
    return (I18n.currentLocale?.() ?? "").toLowerCase().startsWith("zh");
  }

  // The wordmark is the one the header already uses. A site that has not
  // uploaded one still gets a readable footer rather than a broken image.
  //
  // Uploads are stored with the host they were uploaded on. That host is not
  // necessarily the one the forum is being read on — a preview tunnel, or a
  // second domain — and an image pointing at the old host is a broken image.
  // A local upload is therefore resolved against the page it is drawn on.
  get logoUrl() {
    const url = this.siteSettings.site_logo_url;

    if (!url) {
      return null;
    }

    let parsed;

    try {
      parsed = new URL(url, window.location.origin);
    } catch {
      return url;
    }

    if (parsed.pathname.startsWith("/uploads/") && parsed.origin !== window.location.origin) {
      return parsed.pathname;
    }

    return url;
  }

  get hasPlatforms() {
    return this.socialLinks.length > 0;
  }

  get hasContent() {
    return this.hasPlatforms || this.columns.length > 0;
  }

  get visible() {
    return this.showFooter && this.hasContent;
  }

  iconFor(link) {
    return link.icon || (link.show_label ? null : "link");
  }

  // The language is fixed for the life of the document — the switcher reloads
  // the page — so the choice is made once, when the payload lands, rather than
  // on every render. Template calls on `this` with an argument are also not
  // something Glimmer binds here; plain fields keep the template to lookups.
  async #load() {
    const payload = await loadSiteContent();
    const chinese = this.isChinese;

    this.socialLinks = (payload.social_links ?? []).map((link) => ({
      ...link,
      displayLabel: (chinese && link.label_zh?.trim()) || link.label,
      displayCaption: (chinese && link.qr_caption_zh?.trim()) || link.qr_caption,
    }));

    this.columns = (payload.footer_columns ?? []).map((column) => ({
      ...column,
      displayTitle: (chinese && column.title_zh?.trim()) || column.title,
      links: (column.links ?? []).map((link) => ({
        ...link,
        displayLabel: (chinese && link.label_zh?.trim()) || link.label,
      })),
    }));
  }

  @action
  toggleQr(link, event) {
    event.preventDefault();
    this.openQr = this.openQr === link.id ? null : link.id;
  }

  @action
  closeQr() {
    this.openQr = null;
  }

  <template>
    {{#if this.visible}}
      <footer class="ingenic-footer">
        <div class="ingenic-footer__inner">
          <div class="ingenic-footer__brand">
            <div class="ingenic-footer__lockup">
              {{#if this.logoUrl}}
                <img
                  class="ingenic-footer__logo"
                  src={{this.logoUrl}}
                  alt={{this.siteSettings.title}}
                />
              {{else}}
                <span class="ingenic-footer__logo-text">{{this.siteSettings.title}}</span>
              {{/if}}
              <span class="ingenic-footer__badge">
                {{i18n (themePrefix "ingenic.footer.badge")}}
              </span>
            </div>

            <p class="ingenic-footer__slogan">
              {{i18n (themePrefix "ingenic.footer.slogan")}}
            </p>

            {{#if this.hasPlatforms}}
              <ul
                class="ingenic-footer__strip"
                aria-label={{i18n (themePrefix "ingenic.footer.platforms")}}
              >
                {{#each this.socialLinks as |link|}}
                  <li class="ingenic-footer__platform">
                    {{#if (eq link.kind "qr")}}
                      <button
                        class="ingenic-footer__link
                          {{if link.icon_only 'ingenic-footer__link--icon' 'ingenic-footer__link--text'}}"
                        type="button"
                        aria-expanded={{if (eq this.openQr link.id) "true" "false"}}
                        aria-label={{link.displayLabel}}
                        title={{link.displayLabel}}
                        {{on "click" (fn this.toggleQr link)}}
                      >
                        {{#if link.image_url}}
                          <img
                            class="ingenic-footer__icon"
                            src={{link.image_url}}
                            alt=""
                            loading="lazy"
                          />
                        {{else}}
                          {{dIcon "qrcode"}}
                        {{/if}}
                        {{#unless link.icon_only}}
                          <span>{{link.displayLabel}}</span>
                        {{/unless}}
                      </button>

                      {{#if (eq this.openQr link.id)}}
                        <div class="ingenic-footer__qr">
                          {{#if link.qr_image_url}}
                            <img src={{link.qr_image_url}} alt={{link.displayLabel}} />
                          {{/if}}
                          {{#if (or link.qr_caption link.qr_caption_zh)}}
                            <p>{{link.displayCaption}}</p>
                          {{/if}}
                          <button
                            class="btn btn-small"
                            type="button"
                            {{on "click" this.closeQr}}
                          >
                            {{i18n (themePrefix "ingenic.footer.close")}}
                          </button>
                        </div>
                      {{/if}}
                    {{else}}
                      <a
                        class="ingenic-footer__link
                          {{if link.icon_only 'ingenic-footer__link--icon' 'ingenic-footer__link--text'}}"
                        href={{link.href}}
                        target="_blank"
                        rel="noopener noreferrer"
                        aria-label={{link.displayLabel}}
                        title={{link.displayLabel}}
                      >
                        {{#if link.image_url}}
                          <img
                            class="ingenic-footer__icon"
                            src={{link.image_url}}
                            alt=""
                            loading="lazy"
                          />
                        {{else}}
                          {{dIcon (this.iconFor link)}}
                        {{/if}}
                        {{#unless link.icon_only}}
                          <span>{{link.displayLabel}}</span>
                        {{/unless}}
                      </a>
                    {{/if}}
                  </li>
                {{/each}}
              </ul>
            {{/if}}
          </div>

          {{#if this.columns.length}}
            <nav class="ingenic-footer__columns">
              {{#each this.columns as |column|}}
                <section class="ingenic-footer__column">
                  <h2 class="ingenic-footer__heading">{{column.displayTitle}}</h2>
                  <ul>
                    {{#each column.links as |link|}}
                      <li>
                        {{#if link.external}}
                          <a
                            href={{link.href}}
                            target="_blank"
                            rel="noopener noreferrer"
                          >{{link.displayLabel}}</a>
                        {{else}}
                          <a href={{link.href}}>{{link.displayLabel}}</a>
                        {{/if}}
                      </li>
                    {{/each}}
                  </ul>
                </section>
              {{/each}}
            </nav>
          {{/if}}
        </div>
      </footer>
    {{/if}}
  </template>
}
