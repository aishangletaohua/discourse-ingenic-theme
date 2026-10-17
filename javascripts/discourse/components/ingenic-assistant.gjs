import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { themePrefix } from "virtual:theme";
import getURL from "discourse/lib/get-url";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";

const CONVERSATIONS = "/discourse-ai/ai-bot/conversations";

/**
 * The floating assistant in the bottom-right corner.
 *
 * It is a door, not a chat: the conversation itself is Discourse AI's own page,
 * so it keeps the history, the composer and the permissions that plugin already
 * implements. This widget only explains what the assistant is and gets a
 * visitor there in one click.
 *
 * Hidden while `ai_bot_enabled` is off. The setting belongs to discourse-ai; a
 * site without that plugin has no value here, which reads as off.
 */
export default class IngenicAssistant extends Component {
  @service currentUser;
  @service siteSettings;

  @tracked open = false;

  constructor() {
    super(...arguments);

    this.onKeydown = (event) => {
      if (event.key === "Escape" && this.open) {
        this.open = false;
      }
    };

    document.addEventListener("keydown", this.onKeydown);
  }

  willDestroy() {
    document.removeEventListener("keydown", this.onKeydown);
    super.willDestroy(...arguments);
  }

  get enabled() {
    return Boolean(this.siteSettings.ai_bot_enabled);
  }

  get actionPath() {
    if (this.currentUser) {
      return getURL(CONVERSATIONS);
    }

    return `${getURL("/login")}?redirect=${encodeURIComponent(CONVERSATIONS)}`;
  }

  get actionLabel() {
    return i18n(
      themePrefix(
        this.currentUser
          ? "ingenic.assistant.action"
          : "ingenic.assistant.sign_in",
      ),
    );
  }

  @action
  toggle() {
    this.open = !this.open;
  }

  @action
  close() {
    this.open = false;
  }

  <template>
    {{#if this.enabled}}
      <div class="ingenic-assistant">
        {{#if this.open}}
          <section
            class="ingenic-assistant__panel"
            role="dialog"
            aria-label={{i18n (themePrefix "ingenic.assistant.title")}}
          >
            <header class="ingenic-assistant__header">
              <h2 class="ingenic-assistant__title">
                {{i18n (themePrefix "ingenic.assistant.title")}}
              </h2>
              <button
                type="button"
                class="ingenic-assistant__close"
                aria-label={{i18n (themePrefix "ingenic.assistant.close")}}
                {{on "click" this.close}}
              >
                {{dIcon "times"}}
              </button>
            </header>

            <p class="ingenic-assistant__intro">
              {{i18n (themePrefix "ingenic.assistant.intro")}}
            </p>

            <a class="btn btn-primary ingenic-assistant__action" href={{this.actionPath}}>
              {{this.actionLabel}}
            </a>

            <p class="ingenic-assistant__note">
              {{i18n (themePrefix "ingenic.assistant.note")}}
            </p>
          </section>
        {{/if}}

        <button
          type="button"
          class="ingenic-assistant__launcher"
          aria-label={{i18n (themePrefix "ingenic.assistant.launcher")}}
          aria-expanded={{this.open}}
          {{on "click" this.toggle}}
        >
          <svg
            class="ingenic-assistant__mascot"
            viewBox="0 0 64 64"
            aria-hidden="true"
            focusable="false"
          >
            <circle class="ingenic-assistant__halo" cx="32" cy="32" r="30" />
            <line class="ingenic-assistant__line" x1="32" y1="17" x2="32" y2="12" />
            <circle class="ingenic-assistant__antenna" cx="32" cy="9" r="3" />
            <rect class="ingenic-assistant__ear" x="9" y="28" width="5" height="11" rx="2.5" />
            <rect class="ingenic-assistant__ear" x="50" y="28" width="5" height="11" rx="2.5" />
            <rect class="ingenic-assistant__head" x="15" y="19" width="34" height="28" rx="10" />
            <circle class="ingenic-assistant__eye" cx="25" cy="31" r="3" />
            <circle class="ingenic-assistant__eye" cx="39" cy="31" r="3" />
            <path class="ingenic-assistant__smile" d="M26 40c2.4 2.6 9.6 2.6 12 0" />
          </svg>
        </button>
      </div>
    {{/if}}
  </template>
}
