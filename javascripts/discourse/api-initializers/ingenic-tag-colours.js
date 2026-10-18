import { apiInitializer } from "discourse/lib/api";

const FAMILIES = ["sky", "tech", "resolved", "announcement", "hot"];
const STYLE_ID = "ingenic-tag-colours";

// Text inside a CSS attribute selector's quoted string. A tag name can hold
// either of these characters; the theme does not decide what tags exist.
function cssString(value) {
  return String(value).replace(/\\/g, "\\\\").replace(/"/g, '\\"');
}

/**
 * Applies the administrator's tag colour assignments.
 *
 * The families themselves live in the stylesheet as four sets of custom
 * properties. This adds one rule per assigned tag that points those properties
 * at the family the Tag colours screen chose, so the pill's own rule — border,
 * background, ink, hover — is untouched and cannot drift from the defaults.
 *
 * The assignments come with the site payload as a name → family map. The map
 * holds explicit choices only; a tag that is not in it keeps the stylesheet's
 * default, which is the family its name suggests, and then sky.
 *
 * The attribute selector is matched case-insensitively: Discourse lowercases
 * tag slugs but not every tag name, and an administrator who typed "Linux" on
 * one screen should not get a different colour than one who typed "linux".
 *
 * The style element is created here rather than in the stylesheet because the
 * assignments are data, not design: they change without a theme release.
 * Building it once at boot is enough — a changed assignment reaches the forum
 * on the next page load, which is also when the admin sees their own change.
 */
export default apiInitializer((api) => {
  const site = api.container.lookup("service:site");
  const assignments = site?.ingenic_tag_colours;

  if (!assignments || typeof assignments !== "object") {
    return;
  }

  const rules = Object.entries(assignments)
    .filter(([, family]) => FAMILIES.includes(family))
    .map(([name, family]) => {
      // `html` only raises the specificity: these rules tie with the
      // stylesheet's own name-matched defaults, and the compiled theme styles
      // are not guaranteed to sit before this element in the document.
      const selector = `html .discourse-tags .discourse-tag[data-tag-name="${cssString(
        name.toLowerCase()
      )}" i]`;
      return `${selector} {
  --ingenic-tag-tint: var(--ingenic-tag-${family}-tint);
  --ingenic-tag-border: var(--ingenic-tag-${family}-border);
  --ingenic-tag-ink: var(--ingenic-tag-${family}-ink);
}`;
    });

  if (!rules.length) {
    return;
  }

  let style = document.getElementById(STYLE_ID);
  if (!style) {
    style = document.createElement("style");
    style.id = STYLE_ID;
    document.head.appendChild(style);
  }
  style.textContent = rules.join("\n");
});
