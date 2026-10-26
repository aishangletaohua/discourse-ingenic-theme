import Component from "@glimmer/component";
import { service } from "@ember/service";
import routeAction from "discourse/helpers/route-action";
import DButton from "discourse/ui-kit/d-button";

/**
 * The Sign Up button the topic page loses on scroll.
 *
 * Core draws Sign Up only while the topic's own heading is on screen. Once the
 * heading scrolls away and the title moves into the header, `AuthButtons`
 * hides the button on purpose, leaving a signed-out reader with Log In alone.
 * The theme keeps the right side of the header unchanged, so this component
 * draws the same button in that one state and leaves every other state to
 * core: it is silent when somebody is signed in, when the title is not in the
 * header, and when registration is closed.
 */
export default class IngenicSignupButton extends Component {
  @service currentUser;
  @service header;
  @service site;
  @service siteSettings;

  // The same conditions `controller:application` uses. Kept here rather than
  // looked up from the controller so the button does not depend on a route
  // being mounted when the header renders.
  get canSignUp() {
    return (
      !this.site.isReadOnly &&
      !this.siteSettings.invite_only &&
      this.siteSettings.allow_new_registrations &&
      !this.siteSettings.enable_discourse_connect
    );
  }

  get visible() {
    return (
      !this.currentUser &&
      this.header.topicInfoVisible &&
      this.canSignUp &&
      // Other parts of the page ask the header to hide its buttons — the
      // composer and the user menu do — and core's own Sign Up honours that.
      !this.header.headerButtonsHidden.includes("signup")
    );
  }

  <template>
    {{#if this.visible}}
      <DButton
        class="btn-primary btn-small sign-up-button ingenic-signup-button"
        @action={{routeAction "showCreateAccount"}}
        @label="sign_up"
      />
    {{/if}}
  </template>
}
