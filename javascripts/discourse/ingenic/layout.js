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

// A page offset that ignores transforms, so it stays the same while the search
// is being held at the top. `offsetTop` is the layout position; a translate
// does not move it.
function documentTop(element) {
  let top = 0;
  let node = element;

  while (node) {
    top += node.offsetTop;
    node = node.offsetParent;
  }

  return top;
}

// The header is sticky, so the account controls and the language switcher stay
// on screen wherever the reader is. On the home page the search is what people
// arrive for, so it is the search that sets the moment the header turns into a
// surface: the field and the three links under it are held near the top once
// the field arrives there, and the white behind them reaches exactly as far
// down as the block does.
//
// Where it is held depends on the room left beside it. A wide header has empty
// space between the logo and the icons, and the search sits at the very top,
// over the white. A narrower one does not: holding it there would put it over
// the logo or the account controls, so it is held immediately below the header
// instead, at the moment its top reaches the header's foot. Either way nothing
// underneath it moves, because it is translated rather than taken out of the
// layout.
//
// On every other page there is no search to wait for, so the surface still
// follows the scroll itself.
const HEADER_SURFACE_AFTER = 8;
const HEADER_CLEARANCE = 12;

export function watchHeaderSurface(api) {
  const root = document.documentElement;
  let frame = null;
  let mode = "top";

  const measureMode = () => {
    const panel = document.querySelector(".ingenic-homepage__search-panel");
    const logo = document.querySelector(".d-header .home-logo-wrapper-outlet");
    const icons = document.querySelector(".d-header-icons");

    if (!panel || !logo || !icons) {
      return "top";
    }

    const block = panel.getBoundingClientRect();
    const brand = logo.getBoundingClientRect();
    const controls = icons.getBoundingClientRect();

    return block.left > brand.right + HEADER_CLEARANCE &&
      block.right < controls.left - HEADER_CLEARANCE
      ? "top"
      : "below";
  };

  const update = () => {
    frame = null;

    const panel = document.querySelector(".ingenic-homepage__search-panel");
    const header = document.querySelector(".d-header-wrap");

    if (!panel || !header) {
      root.classList.remove("ingenic-search-docked");
      root.classList.toggle(
        "ingenic-header-surface",
        window.scrollY > HEADER_SURFACE_AFTER,
      );
      return;
    }

    const headerHeight = header.getBoundingClientRect().height;
    const start = documentTop(panel);

    // Measured while the block is still in the flow; its horizontal edges do
    // not change when it is translated vertically.
    if (!root.classList.contains("ingenic-search-docked")) {
      mode = measureMode();
    }

    // "top" waits for the block's top edge to reach the top of the screen.
    // "below" waits for it to reach the foot of the header, which is where it
    // will be held.
    const dockAt = mode === "below" ? start - headerHeight : start;
    const docked = window.scrollY >= dockAt;

    root.classList.toggle("ingenic-search-docked", docked);
    root.classList.toggle("ingenic-header-surface", docked);

    if (!docked) {
      return;
    }

    root.style.setProperty(
      "--ingenic-dock-shift",
      `${window.scrollY - start + (mode === "below" ? headerHeight : 0)}px`,
    );
    root.style.setProperty(
      "--ingenic-search-overhang",
      `${Math.max(
        panel.offsetHeight - (mode === "below" ? 0 : headerHeight),
        0,
      )}px`,
    );
  };

  const schedule = () => {
    if (frame === null) {
      frame = window.requestAnimationFrame(update);
    }
  };

  window.addEventListener("scroll", schedule, { passive: true });
  window.addEventListener("resize", () => {
    mode = measureMode();
    schedule();
  });

  // The sidebar shares the header row with the block: opening it moves the
  // content column, which can leave room for the top position the narrower
  // layout did not have, or take it away.
  new MutationObserver(() => {
    mode = measureMode();
    schedule();
  }).observe(document.body, { attributes: true, attributeFilter: ["class"] });

  if (api?.onPageChange) {
    api.onPageChange(schedule);
  }

  update();
}
