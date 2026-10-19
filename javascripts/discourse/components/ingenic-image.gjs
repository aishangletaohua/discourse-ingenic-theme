import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { rebaseLocalUrl } from "../ingenic/asset-url";

/**
 * An administrator-supplied image, with the section's own glyph behind it.
 *
 * The address may have been written on a local host (see `asset-url`), so it is
 * re-rooted before it is used. It may also be genuinely gone — an upload deleted
 * from the server, a URL typed with a typo — and a broken-image placeholder in
 * the header or on a section card reads as a broken page. When the image cannot
 * load, the glyph the section would have drawn without an image is drawn
 * instead, so the row keeps its shape and still says what it is.
 */
export default class IngenicImage extends Component {
  @tracked failed = false;

  get src() {
    return rebaseLocalUrl(this.args.src);
  }

  get fallbackIcon() {
    return this.args.fallbackIcon || "image";
  }

  get loading() {
    return this.args.loading || "lazy";
  }

  @action
  fail() {
    this.failed = true;
  }

  <template>
    {{#if this.failed}}
      {{dIcon this.fallbackIcon}}
    {{else}}
      <img
        class={{@className}}
        src={{this.src}}
        alt={{@alt}}
        loading={{this.loading}}
        {{on "error" this.fail}}
      />
    {{/if}}
  </template>
}
