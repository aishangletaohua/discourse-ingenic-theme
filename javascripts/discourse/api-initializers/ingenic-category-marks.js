import { apiInitializer } from "discourse/lib/api";
import { markFor } from "../ingenic/category-marks";

/**
 * Draws every named section with the glyph and hue the theme uses for it.
 *
 * Discourse draws a category as a coloured square unless the category was
 * saved with an icon style. The home page already knew each section's glyph,
 * but a category page or a topic row asked the server and got the square back,
 * so the same section looked like two different things one click apart.
 *
 * The correction is made on the client, on the category models the whole app
 * reads. Every badge — breadcrumb, subcategory cards, topic rows, the composer
 * picker — is rendered from these objects, so one pass reaches all of them
 * without a stylesheet rule per screen. Nothing is written back to the server:
 * an administrator's own choice is overridden for display only, and a category
 * this table does not name keeps exactly what they saved.
 *
 * Applied at boot and again on each page change, because the site payload can
 * be replaced while the app is running (an admin saves a category, a user
 * refreshes the site model); the second pass is cheap and idempotent.
 */
export default apiInitializer((api) => {
  const site = api.container.lookup("service:site");

  function apply() {
    for (const category of site?.categories ?? []) {
      const mark = markFor(category);

      if (!mark) {
        continue;
      }

      const tint = mark.tint.replace(/^#/, "");

      // `style_type` is what the badge helper reads; `styleType` is the
      // tracked copy the category model keeps for templates. Both are set so
      // a badge rendered before and after this pass agrees.
      category.style_type = "icon";
      category.styleType = "icon";
      category.icon = mark.icon;

      if (category.color !== tint) {
        category.color = tint;
      }
    }
  }

  apply();
  api.onPageChange(apply);
});
