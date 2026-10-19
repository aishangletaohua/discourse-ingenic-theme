import { apiInitializer } from "discourse/lib/api";
import { ajax } from "discourse/lib/ajax";
import { i18n } from "discourse-i18n";
import { themePrefix } from "virtual:theme";
import IngenicAssistant from "../components/ingenic-assistant";
import IngenicBounty from "../components/ingenic-bounty";
import IngenicComposerBounty from "../components/ingenic-composer-bounty";
import IngenicFooter from "../components/ingenic-footer";
import IngenicHeaderLinks from "../components/ingenic-header-links";
import IngenicLocaleSwitcher from "../components/ingenic-locale-switcher";
import { rebaseLocalUrl } from "../ingenic/asset-url";
import { applyIngenicLayout } from "../ingenic/layout";
import {
  registerIngenicCommunityLinks,
  registerIngenicSidebarSections,
} from "../ingenic/sidebar-section";

/**
 * Wires the Ingenic layout into Discourse.
 *
 * The navigation is registered as sidebar sections rather than drawn into an
 * outlet — three of them, so that the developer resources can carry a heading
 * while the forum above and the member's own entries below it do not. The home
 * page is not drawn here at all: it is a registered homepage, mounted by the
 * plugin at `/`, so it renders on its own route.
 *
 * The footer goes into above-footer, which is where the site's own footer
 * content lands, so it sits where a footer is expected and disappears with the
 * rest of the footer on the pages that hide one.
 *
 * The language switcher goes into the header's icon row. It is registered
 * before the user menu, which is the far right of the header in both states:
 * Discourse's own user menu renders nothing for a signed-out visitor, so the
 * switcher lands after the search and hamburger and beside the login button,
 * and for a signed-in one it sits immediately left of the avatar. It renders
 * nothing at all unless more than one language is configured, so a
 * single-language forum does not carry a control with one option in it.
 *
 * The 高分悬赏 banner goes above the posts, which is the top of the question
 * itself: what an answer here is worth is part of reading the question, and it
 * belongs where somebody decides to answer rather than at the foot of the page.
 * Like the footer, it decides what to draw from the outlet's own payload.
 */
export default apiInitializer((api) => {
  applyIngenicLayout();
  registerIngenicSidebarSections(api);
  registerIngenicCommunityLinks(api);

  api.registerValueTransformer("home-logo-image-url", ({ value }) =>
    rebaseLocalUrl(value),
  );

  api.headerIcons.add("ingenic-locale", IngenicLocaleSwitcher, {
    before: "user-menu",
  });

  // The official site and GitHub sit directly after the wordmark. The outlet
  // is the header's empty middle; the stylesheet gives it the room, and the
  // two buttons keep their names so a reader does not have to guess a glyph.
  api.renderInOutlet("before-header-panel", IngenicHeaderLinks);

  api.renderInOutlet("topic-above-posts", IngenicBounty);

  // The bounty field sits in the composer's own fields, above the title: a
  // member writing a question decides there whether it is worth paying for,
  // and opening the offer afterwards from the topic page stays available for
  // the ones who decide later.
  api.renderInOutlet("composer-fields", IngenicComposerBounty);

  // The bounty is opened here rather than in the field, because the composer
  // and its fields are gone by the time a new topic is announced. The field
  // leaves the amount on the composer model, which is still there at this
  // point; this reads it once and clears it, so a later topic cannot inherit an
  // amount nobody meant to pay.
  api.onAppEvent("composer:created-post", async ({ postId }) => {
    const model = api.container.lookup("service:composer")?.model;
    const points = Number(model?.ingenicBountyPoints) || 0;

    if (model) {
      model.ingenicBountyPoints = 0;
    }

    if (!postId || points < 1) {
      return;
    }

    try {
      const post = await ajax(`/posts/${postId}.json`);
      await ajax("/ingenic/bounties", {
        type: "POST",
        data: { topic_id: post.topic_id, points },
      });
    } catch (failure) {
      // The topic exists; only the offer did not. Say so plainly, with the
      // reason the server gave, and leave the member on the topic page where
      // the same offer can be opened by hand.
      const reason =
        failure?.jqXHR?.responseJSON?.errors?.join(" ") ||
        i18n(themePrefix("ingenic.bounties.failed"));

      api.container.lookup("service:dialog").alert({
        title: i18n(themePrefix("ingenic.bounties.composer_failed_title")),
        message: i18n(themePrefix("ingenic.bounties.composer_failed_body"), {
          reason,
        }),
      });
    }
  });
  api.renderInOutlet("above-footer", IngenicFooter);

  // The assistant floats over whatever is being read, so it goes in an outlet
  // that exists on every page rather than one owned by a particular route.
  // `after-main-outlet` sits outside the content column and is not conditional
  // on the footer, which is what a fixed-position element needs.
  api.renderInOutlet("after-main-outlet", IngenicAssistant);
});
