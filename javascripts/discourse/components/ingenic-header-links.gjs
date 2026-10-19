import Component from "@glimmer/component";
import { service } from "@ember/service";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import IngenicImage from "./ingenic-image";

/**
 * The two buttons beside the wordmark: the official site and GitHub.
 *
 * The list is content — it arrives in the site payload, so the first paint has
 * it and the header does not grow a row of buttons a moment after the page
 * appears. Each entry is either a name, an icon (built in or an image), or
 * both; an icon-only button keeps its name as its accessible label, so the
 * button is still announced.
 *
 * It draws nothing at all when the list is empty, which is what a forum that
 * has chosen its own header looks like.
 */
export default class IngenicHeaderLinks extends Component {
  @service site;

  get links() {
    return this.site.ingenic_header_links ?? [];
  }

  iconFor(link) {
    return link.icon || (link.show_label ? null : "link");
  }

  <template>
    {{#if this.links.length}}
      <nav class="ingenic-header-links">
        {{#each this.links as |link|}}
          <a
            class="ingenic-header-links__link"
            href={{link.href}}
            target={{if link.external "_blank"}}
            rel={{if link.external "noopener noreferrer"}}
            aria-label={{if link.show_label null link.label}}
            title={{if link.show_label null link.label}}
          >
            {{#if link.image_url}}
              <IngenicImage
                @src={{link.image_url}}
                @className="ingenic-header-links__image"
                @fallbackIcon={{this.iconFor link}}
              />
            {{else if (this.iconFor link)}}
              {{dIcon (this.iconFor link)}}
            {{/if}}

            {{#if link.show_label}}
              <span>{{link.label}}</span>
            {{/if}}
          </a>
        {{/each}}
      </nav>
    {{/if}}
  </template>
}
