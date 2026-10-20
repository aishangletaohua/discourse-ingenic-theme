/**
 * Applies the layout theme settings.
 *
 * The sidebar is core's own element, so moving it is a matter of pointing the
 * existing grid at a different area rather than building a second navigation
 * column. The classes set here are the hooks the stylesheet reads; the width
 * needs no JavaScript because theme settings are also compiled into SCSS.
 */
export function applyIngenicLayout() {
  const root = document.documentElement;

  root.classList.toggle(
    "ingenic-sidebar-right",
    settings.ingenic_sidebar_position === "right",
  );
  root.classList.toggle("ingenic-nav-first", settings.ingenic_nav_order === "first");
}

// The header is sticky, so the account controls and the language switcher stay
// on screen wherever the reader is. At the top of the page the header is only
// a wash and the page begins underneath it; once the page has scrolled the
// same controls sit over whatever passed beneath them, which reads as floating
// rather than as a header. This marks the scroll so the stylesheet can give
// them a surface of their own. One rAF per scroll burst, and nothing at all
// while the page is still at the top.
const HEADER_SURFACE_AFTER = 8;

export function watchHeaderSurface() {
  const root = document.documentElement;
  let frame = null;

  const update = () => {
    frame = null;
    root.classList.toggle(
      "ingenic-header-surface",
      window.scrollY > HEADER_SURFACE_AFTER,
    );
  };

  const schedule = () => {
    if (frame === null) {
      frame = window.requestAnimationFrame(update);
    }
  };

  window.addEventListener("scroll", schedule, { passive: true });
  update();
}
