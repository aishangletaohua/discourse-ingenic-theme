// The glyph and the hue each section of this forum is known by.
//
// One table, because a section is named in more than one place: the home page
// card, the category badge beside a topic, the breadcrumb on the category's own
// page, and the flyout under the sidebar. When a page drew its own badge the
// same section could arrive as a teal comments glyph on the front page and a
// plain blue square one click later, which reads as two different sections.
//
// These are the colours the sidebar rows draw their glyphs in (see
// `common/common.scss`), so the home-page card, the category badge beside a
// topic, the breadcrumb and the flyout all repeat one hue per section.
//
// A category that is not named here keeps whatever an administrator chose. The
// table is for the sections this theme ships with, not a rule that every future
// category must adopt one of these colours.
export const CATEGORY_MARKS = {
  "technical-discussions": { icon: "comments", tint: "#369687" },
  "official-announcements": { icon: "bullhorn", tint: "#ef8a2b" },
  "site-feedback": { icon: "comment-dots", tint: "#d6539a" },
  "open-source": { icon: "code", tint: "#7b61d6" },
  // The two halves of Open Source. They stay in the purple family of their
  // parent and carry a glyph of their own, so a row in the sidebar flyout says
  // which half it is without a second palette.
  official: { icon: "certificate", tint: "#6d5bd0" },
  "third-party": { icon: "users", tint: "#9077e8" },
  general: { icon: "comments", tint: "#25aae2" },
};

export function markFor(category) {
  return category ? CATEGORY_MARKS[category.slug] : null;
}
