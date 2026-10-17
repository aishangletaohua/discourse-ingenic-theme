import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { themePrefix } from "virtual:theme";
import getURL from "discourse/lib/get-url";
import { i18n } from "discourse-i18n";

/**
 * What MCP is, where this forum's endpoint is, and how a client connects.
 *
 * The server is Discourse's own: the protocol, the OAuth flow and the tools
 * belong to core, and this page only explains them. It draws the endpoint from
 * the current origin rather than a setting, so a copy of the forum served under
 * another address describes that address.
 */
export default class IngenicMcp extends Component {
  @service siteSettings;

  @tracked copied = false;

  get enabled() {
    return Boolean(this.siteSettings.mcp_server_enabled);
  }

  get endpointUrl() {
    return new URL(getURL("/mcp"), window.location.origin).toString();
  }

  get claudeCodeCommand() {
    return `claude mcp add --transport http ingenic-forum ${this.endpointUrl}`;
  }

  get vscodeConfig() {
    return JSON.stringify(
      {
        servers: {
          "ingenic-forum": {
            type: "http",
            url: this.endpointUrl,
          },
        },
      },
      null,
      2,
    );
  }

  @action
  async copy() {
    try {
      await navigator.clipboard.writeText(this.endpointUrl);
      this.copied = true;
      setTimeout(() => (this.copied = false), 1600);
    } catch {
      // The address is selectable on the page; a failed copy needs no alarm.
    }
  }

  <template>
    <section class="ingenic-section ingenic-mcp">
      <header class="ingenic-section__header">
        <div>
          <h1>{{i18n (themePrefix "ingenic.mcp.title")}}</h1>
          <p class="ingenic-section__subtitle">
            {{i18n (themePrefix "ingenic.mcp.subtitle")}}
          </p>
        </div>
      </header>

      {{#unless this.enabled}}
        <p class="ingenic-notice">
          {{i18n (themePrefix "ingenic.mcp.disabled")}}
        </p>
      {{/unless}}

      <p class="ingenic-mcp__intro">
        {{i18n (themePrefix "ingenic.mcp.intro")}}
      </p>

      <div class="ingenic-mcp__endpoint">
        <span class="ingenic-mcp__endpoint-label">
          {{i18n (themePrefix "ingenic.mcp.endpoint_label")}}
        </span>
        <code class="ingenic-mcp__endpoint-url">{{this.endpointUrl}}</code>
        <button
          type="button"
          class="btn ingenic-mcp__copy"
          {{on "click" this.copy}}
        >
          {{#if this.copied}}
            {{i18n (themePrefix "ingenic.mcp.copied")}}
          {{else}}
            {{i18n (themePrefix "ingenic.mcp.copy")}}
          {{/if}}
        </button>
      </div>

      <h2>{{i18n (themePrefix "ingenic.mcp.connect_title")}}</h2>
      <ol class="ingenic-mcp__steps">
        <li>
          <strong>{{i18n (themePrefix "ingenic.mcp.step_add_title")}}</strong>
          <p>{{i18n (themePrefix "ingenic.mcp.step_add_text")}}</p>
        </li>
        <li>
          <strong>{{i18n (themePrefix "ingenic.mcp.step_signin_title")}}</strong>
          <p>{{i18n (themePrefix "ingenic.mcp.step_signin_text")}}</p>
        </li>
        <li>
          <strong>{{i18n (themePrefix "ingenic.mcp.step_use_title")}}</strong>
          <p>{{i18n (themePrefix "ingenic.mcp.step_use_text")}}</p>
        </li>
      </ol>

      <h2>{{i18n (themePrefix "ingenic.mcp.clients_title")}}</h2>
      <div class="ingenic-mcp__clients">
        <article class="ingenic-mcp__client">
          <h3>{{i18n (themePrefix "ingenic.mcp.claude_code")}}</h3>
          <pre><code>{{this.claudeCodeCommand}}</code></pre>
        </article>
        <article class="ingenic-mcp__client">
          <h3>{{i18n (themePrefix "ingenic.mcp.vscode")}}</h3>
          <pre><code>{{this.vscodeConfig}}</code></pre>
        </article>
        <article class="ingenic-mcp__client">
          <h3>{{i18n (themePrefix "ingenic.mcp.other_title")}}</h3>
          <p>{{i18n (themePrefix "ingenic.mcp.other_text")}}</p>
        </article>
      </div>

      <h2>{{i18n (themePrefix "ingenic.mcp.permissions_title")}}</h2>
      <p>{{i18n (themePrefix "ingenic.mcp.permissions_text")}}</p>

      <p class="ingenic-mcp__note">
        {{i18n (themePrefix "ingenic.mcp.admin_note")}}
      </p>
    </section>
  </template>
}
