import { themePrefix } from "virtual:theme";
import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { on } from "@ember/modifier";
import { fn } from "@ember/helper";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import didUpdate from "@ember/render-modifiers/modifiers/did-update";
import { trustHTML } from "@ember/template";
import I18n, { i18n } from "discourse-i18n";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import getURL from "discourse/lib/get-url";
import { readingLocale, withReadingLocale } from "../ingenic/reading-locale";

const ROUTE_PREFIX = "/ingenic/docs";
const SEARCH_ENDPOINT = "/ingenic/docs-search";

// The URL is /<series>/<chip>/<version>/<page>. Only the series is required:
// the plugin fills in the rest, so a navigation entry can point at
// /ingenic/docs and still land somewhere real.
const SEGMENT = { series: 0, chip: 1, version: 2, page: 3 };

// A heading deep in a manual is still a heading; the page rail indents one
// step for an h3 and not at all for an h2.
const HEADING_INDENT = { 2: 0, 3: 1 };

// A page is one request, but the connection carrying it is not always one
// answer. A held request or a 502 from a proxy is a moment, not a verdict, so
// the reader gets two more attempts before being told anything went wrong.
// The waits are short: this is a retry, not a background job.
const FETCH_TIMEOUT = 20_000;
const RETRY_DELAYS = [400, 1_200];

// Which of the two side rails the reader keeps open. It is a reading
// preference, so it outlives the page: a manual read with the contents folded
// should not unfold them on the next page.
const RAILS_KEY = "ingenic-docs-rails";

/**
 * Documentation reader.
 *
 * The toolbar carries the two things that choose what is being read — the
 * series/chip picker and the version — and the one thing that finds a page
 * inside them, the search box. The contents sit under it on the left, the
 * page in the middle, and the page's own headings on the right.
 *
 * The URL is the only navigation state. Choosing a chip or a version
 * transitions the router, `@path` changes, and the single refetch in `load`
 * follows. Deep links, the back button and shared addresses therefore agree
 * without any state to reconcile.
 *
 * The page body is cooked HTML from the plugin. The parts that need behaviour
 * rather than styling — the heading anchors, image zoom, code copy buttons and
 * table wrappers — are added to that DOM after it is inserted, because the
 * body is trusted HTML and Glimmer does not own its children.
 */
export default class IngenicDocs extends Component {
  @service router;
  @service currentUser;

  @tracked series = [];
  @tracked chip = null;
  @tracked chipSlug = null;
  @tracked versions = [];
  @tracked version = null;
  @tracked pages = [];
  @tracked page = null;
  @tracked navigation = { previous: null, next: null };
  @tracked loading = true;
  @tracked notFound = false;
  @tracked loadError = false;

  @tracked pickerOpen = false;
  @tracked openSeriesSlug = null;
  @tracked treeOpen = true;
  @tracked railOpen = true;
  @tracked collapsedGroups = [];

  @tracked searchQuery = "";
  @tracked searchResults = null;
  @tracked searching = false;

  @tracked headings = [];
  @tracked activeHeadingId = null;
  @tracked lightbox = null;

  constructor(owner, args) {
    super(owner, args);

    // A reader who folded a rail once keeps it folded; the state is a reading
    // preference, not something to re-decide on every page. Without a stored
    // answer the contents start folded on a phone — they sit above the page
    // there, and the first thing a reader should see is the page they opened.
    const stored = this.#storedRails();

    if (typeof window !== "undefined") {
      this.treeOpen = stored.toc ?? window.innerWidth >= 768;
      this.railOpen = stored.rail ?? true;
    }
  }

  #searchTimer = null;
  #searchToken = 0;
  #loadToken = 0;
  #searchInput = null;
  #headingElements = [];
  #scrollFrame = null;
  #scroller = null;
  #rail = null;
  #railRevealFrame = null;

  // The language this page is being read in. A signed-in reader carries it on
  // the model, which is tracked, so changing it refetches even when the page
  // itself is not reloaded. Everyone else changes language by reloading.
  get activeLocale() {
    return this.currentUser?.locale || readingLocale();
  }

  get segments() {
    return (this.args.path ?? "").split("/").filter(Boolean).slice(0, 4);
  }

  get seriesSlug() {
    return this.segments[SEGMENT.series];
  }

  get versionSlug() {
    return this.segments[SEGMENT.version] || "latest";
  }

  get urlPageSlug() {
    return this.segments[SEGMENT.page];
  }

  get currentPath() {
    return this.segments.length
      ? `${ROUTE_PREFIX}/${this.segments.join("/")}`
      : ROUTE_PREFIX;
  }

  get seriesName() {
    return (
      this.series.find((entry) => entry.slug === this.seriesSlug)?.name ??
      this.seriesSlug ??
      ""
    );
  }

  get chipMark() {
    return (this.chip?.name ?? "").slice(0, 4).toUpperCase();
  }

  get seriesList() {
    return this.series.map((entry) => ({
      slug: entry.slug,
      name: entry.name,
      isCurrent: entry.slug === this.seriesSlug,
      isOpen: entry.slug === this.openSeriesSlug,
      chips: entry.chips.map((chip) => ({
        slug: chip.slug,
        name: chip.name,
        isCurrent: entry.slug === this.seriesSlug && chip.slug === this.chipSlug,
      })),
    }));
  }

  get openSeries() {
    return (
      this.seriesList.find((entry) => entry.slug === this.openSeriesSlug) ??
      this.seriesList[0] ??
      null
    );
  }

  get hasProducts() {
    return this.series.some((entry) => entry.chips.length > 0);
  }

  // `value` on a <select> is applied before its <option>s exist, so it cannot
  // pick one. Marking the chosen option is the binding that survives the
  // order: each option says whether it is the current version.
  get versionOptions() {
    return this.versions.map((version) => ({
      slug: version.slug,
      label: version.label,
      latest: version.latest,
      isSelected: version.slug === this.versionSlug,
    }));
  }

  // The contents flattened into the rows a tree draws, in the order they
  // appear on screen.
  //
  // The plugin sends a depth-first list with a `depth` on every entry. That is
  // enough to rebuild the tree: a row belongs to the nearest row above it
  // that is shallower. Once the tree exists, a row knows its level and
  // whether each of its ancestors still has siblings below — which is exactly
  // where the guide lines go. Deriving that from a fixed set of indent
  // classes could only ever show the depths the stylesheet anticipated.
  get tocRows() {
    const rows = [];

    const walk = (nodes, ancestors) => {
      for (const node of nodes) {
        const collapsed =
          node.isFolder && this.collapsedGroups.includes(node.slug);

        rows.push({
          ...node,
          level: ancestors.length,
          // One flag per vertical guide column: the line beside this row
          // continues from an ancestor that still has a sibling to come.
          guides: ancestors.map((ancestor) => !ancestor.isLast),
          hasChildren: node.children.length > 0,
          isOpen: !collapsed,
        });

        // A closed folder still carries `children`, so its toggle has
        // something to reopen; only the rows are withheld.
        if (!collapsed) {
          walk(node.children, [...ancestors, node]);
        }
      }
    };

    walk(this.#tocTree(), []);
    return rows;
  }

  // Depth-first entries into a tree of nodes, with each sibling list marked so
  // the last one can draw a corner instead of a continuing line.
  #tocTree() {
    const roots = [];
    const stack = [];

    for (const entry of this.pages) {
      const depth = entry.depth ?? 0;

      while (stack.length && stack[stack.length - 1].depth >= depth) {
        stack.pop();
      }

      // A folder is a heading in the contents, not a destination: the plugin
      // refuses to serve one as a page, so a link to it is a 404.
      const node = {
        slug: entry.slug,
        title: entry.title,
        isFolder: entry.kind === "folder",
        href: entry.kind === "folder" ? null : this.hrefFor(entry.slug),
        isActive: entry.slug === this.urlPageSlug,
        children: [],
      };

      if (stack.length) {
        stack[stack.length - 1].node.children.push(node);
      } else {
        roots.push(node);
      }

      stack.push({ depth, node });
    }

    const markLast = (nodes) => {
      nodes.forEach((node, index) => {
        node.isLast = index === nodes.length - 1;
        markLast(node.children);
      });
    };
    markLast(roots);

    return roots;
  }

  get searchHits() {
    return (this.searchResults ?? []).map((result) => ({
      slug: result.slug,
      title: result.title,
      excerpt: result.excerpt,
      titleParts: this.#highlight(result.title),
      excerptParts: this.#highlight(result.excerpt),
      href: this.hrefFor(result.slug),
    }));
  }

  get railHeadings() {
    return this.headings.map((heading) => ({
      ...heading,
      isActive: heading.id === this.activeHeadingId,
    }));
  }

  get searchOpen() {
    return this.searching || this.searchResults !== null;
  }

  get previousLink() {
    return this.#stepLink(this.navigation.previous);
  }

  get nextLink() {
    return this.#stepLink(this.navigation.next);
  }

  get updatedDate() {
    const value = this.page?.updated_at;
    if (!value) {
      return "";
    }

    const date = new Date(value);
    if (Number.isNaN(date.getTime())) {
      return "";
    }

    // The date follows the forum's language, not the browser's. Left to
    // `undefined` the formatter reads the operating system, so an English
    // page opened on a Chinese desktop said "2026年10月17日" beside an
    // English "Updated". Discourse locales use an underscore; Intl wants a
    // hyphen.
    const locale = I18n.currentLocale?.()?.replace(/_/g, "-");

    return new Intl.DateTimeFormat(locale || undefined, {
      year: "numeric",
      month: "short",
      day: "numeric",
    }).format(date);
  }

  get forumHref() {
    return getURL(this.page?.discussion_url || "/latest");
  }

  #stepLink(resolved) {
    if (!resolved) {
      return null;
    }

    return {
      slug: resolved.slug,
      title: resolved.title,
      href: this.hrefFor(resolved.slug),
    };
  }

  // A router path, deliberately without the deployment prefix: the router
  // applies rootURL itself, so a prefixed path would break on a subfolder
  // install. `getURL` adds it back wherever the path becomes an href or a
  // fetch target.
  urlFor({ series, chip, version, page }) {
    const parts = [ROUTE_PREFIX, series, chip];

    if (version) {
      parts.push(version);
    }

    if (version && page) {
      parts.push(page);
    }

    return parts.filter(Boolean).join("/");
  }

  hrefFor(pageSlug) {
    return getURL(
      this.urlFor({
        series: this.seriesSlug,
        chip: this.chipSlug,
        version: this.version?.slug ?? this.versionSlug,
        page: pageSlug,
      }),
    );
  }

  @action
  async load() {
    // Only the newest load may write state. Navigating twice before the first
    // answer arrives would otherwise let a slower earlier response land on top
    // of the page the reader is looking at.
    const token = ++this.#loadToken;

    this.loading = true;
    this.notFound = false;
    this.loadError = false;
    this.pickerOpen = false;
    this.openSeriesSlug = null;
    this.headings = [];
    this.activeHeadingId = null;

    try {
      const response = await this.#fetchJson(this.currentPath);

      if (token !== this.#loadToken) {
        return;
      }

      if (!response.ok) {
        // A page that does not exist is an answer, not a fault, and retrying
        // cannot change it. A bad address must not take the way out of it with
        // it either: the controls render from the catalogue, so a deep link
        // that resolves to nothing still leaves the picker usable.
        await this.#loadCatalogue(token);
        if (token === this.#loadToken) {
          this.notFound = true;
        }
        return;
      }

      const payload = await response.json();

      if (token !== this.#loadToken) {
        return;
      }

      this.series = payload.series ?? [];
      this.chip = payload.product ?? null;
      this.chipSlug = payload.chip_slug ?? null;
      this.versions = payload.versions ?? [];
      this.version = payload.version ?? null;
      this.pages = payload.pages ?? [];
      this.page = payload.page ?? null;
      this.navigation = payload.navigation ?? { previous: null, next: null };

      this.#canonicalize(payload);
    } catch {
      // The retries are spent and this is still not an answer: the connection
      // failed, timed out, or something between here and the server returned
      // an error. That is not the same as the page being gone, and it is the
      // difference a reader needs in order to decide whether to try again.
      if (token === this.#loadToken) {
        this.loadError = true;
      }
    } finally {
      if (token === this.#loadToken) {
        this.loading = false;
      }
    }
  }

  @action
  retry() {
    this.load();
  }

  // Fetches JSON with the retries a transient failure deserves. A 4xx is
  // returned as it is — the address is wrong and repeating it is pointless —
  // while timeouts, network errors, 5xx and 429 are tried again.
  async #fetchJson(path) {
    let failure = null;

    for (let attempt = 0; attempt <= RETRY_DELAYS.length; attempt++) {
      if (attempt > 0) {
        await new Promise((resolve) =>
          window.setTimeout(resolve, RETRY_DELAYS[attempt - 1]),
        );
      }

      const controller = new AbortController();
      const timeout = window.setTimeout(
        () => controller.abort(),
        FETCH_TIMEOUT,
      );

      try {
        const response = await fetch(withReadingLocale(getURL(path)), {
          headers: { Accept: "application/json" },
          // The answer is per language and changes when an editor saves a
          // page; a cached copy is a page the reader has already been shown.
          cache: "no-store",
          signal: controller.signal,
        });

        if (response.ok || (response.status < 500 && response.status !== 429)) {
          return response;
        }

        failure = new Error(`HTTP ${response.status}`);
      } catch (error) {
        failure = error;
      } finally {
        window.clearTimeout(timeout);
      }
    }

    throw failure ?? new Error("request failed");
  }

  // Enough state for the controls to work after a 404. The requested address
  // is still wrong and stays in the URL, but the picker, the version dropdown
  // and the contents are drawn from the catalogue's first product, so the
  // reader can leave the broken page without going back.
  async #loadCatalogue(token) {
    if (this.hasProducts) {
      return;
    }

    try {
      const response = await this.#fetchJson(ROUTE_PREFIX);

      if (!response.ok || token !== this.#loadToken) {
        return;
      }

      const payload = await response.json();

      if (token !== this.#loadToken) {
        return;
      }

      this.series = payload.series ?? [];
      this.chip = payload.product ?? null;
      this.chipSlug = payload.chip_slug ?? null;
      this.versions = payload.versions ?? [];
      this.version = payload.version ?? null;
      this.pages = payload.pages ?? [];
    } catch {
      // Nothing to pick from; the notice remains the page, which is all that
      // can be said when even the catalogue cannot be read.
    }
  }

  // The plugin resolves a partial path to a concrete chip and version.
  // Rewriting the address to what was actually resolved keeps the version
  // dropdown, the contents and the URL in agreement, and makes the address a
  // visitor copies the one that reproduces the page.
  //
  // A chip with pages but no page in the address opens the first page: landing
  // on the documentation and being told to choose something that is already
  // there is a dead end, not a choice.
  #canonicalize(payload) {
    if (!payload.series_slug || !payload.chip_slug || !payload.version) {
      return;
    }

    const pageSlug =
      payload.page?.slug ?? this.#firstReadablePage(payload.pages)?.slug;
    const canonical = this.urlFor({
      series: payload.series_slug,
      chip: payload.chip_slug,
      version: payload.version.slug,
      page: pageSlug,
    });

    if (canonical !== this.currentPath) {
      this.router.replaceWith(canonical);
    }
  }

  // The first row a reader can open. A folder heads its section but has no
  // body, so opening the documentation on one would land on a page the plugin
  // does not serve.
  #firstReadablePage(pages) {
    return (pages ?? []).find((entry) => entry.kind !== "folder");
  }

  @action
  togglePicker() {
    this.pickerOpen = !this.pickerOpen;

    if (this.pickerOpen) {
      this.openSeriesSlug = this.seriesSlug ?? this.series[0]?.slug ?? null;
    }
  }

  @action
  closePicker() {
    this.pickerOpen = false;
  }

  @action
  chooseSeries(series, event) {
    event?.preventDefault();
    this.openSeriesSlug = series.slug;
  }

  @action
  selectChip(series, chip, event) {
    event?.preventDefault();

    if (!chip) {
      return;
    }

    this.pickerOpen = false;
    this.openSeriesSlug = null;
    this.#resetSearch();

    // No version and no page: the plugin supplies this chip's default version
    // and the first page, then `#canonicalize` rewrites the address.
    this.router.transitionTo(
      this.urlFor({ series: series.slug, chip: chip.slug }),
    );
  }

  // A version change keeps the reader on the same page when that version has
  // it, and opens the version's first page when it does not. Sending the old
  // slug blind would show a 404 for a page that exists only in the newer
  // version, which is exactly the page a reader is most likely to be on.
  @action
  async selectVersion(event) {
    this.#resetSearch();

    const version = event.target.value;
    const base = this.urlFor({
      series: this.seriesSlug,
      chip: this.chipSlug || this.segments[SEGMENT.chip],
      version,
    });

    try {
      const response = await fetch(withReadingLocale(getURL(base)), {
        headers: { Accept: "application/json" },
        cache: "no-store",
      });

      if (response.ok) {
        const payload = await response.json();
        const pages = payload.pages ?? [];
        const page = pages.some((entry) => entry.slug === this.urlPageSlug)
          ? this.urlPageSlug
          : this.#firstReadablePage(pages)?.slug;

        this.router.transitionTo(this.urlFor({
          series: this.seriesSlug,
          chip: this.chipSlug || this.segments[SEGMENT.chip],
          version,
          page,
        }));
        return;
      }
    } catch {
      // Fall through to the plain version path; the reader still moves.
    }

    this.router.transitionTo(base);
  }

  // The article has its own scrollbar, so it also has its own idea of where
  // the reader is. Opening another page must start at that page's first line;
  // without this the new text would inherit the old article's offset.
  #scrollSlug = null;

  @action
  syncScroll(element) {
    // The article scrolls in this element, not in the window, so this is where
    // the reader's position has to be watched from. Re-registering on every
    // update would stack listeners, so only the first sighting of a pane does.
    if (element !== this.#scroller) {
      this.#scroller?.removeEventListener("scroll", this.#onScroll);
      this.#scroller = element;
      element.addEventListener("scroll", this.#onScroll, { passive: true });
    }

    if (this.page?.slug !== this.#scrollSlug) {
      this.#scrollSlug = this.page?.slug ?? null;
      element.scrollTop = 0;
    }
  }

  @action
  openPage(page, event) {
    if (!page) {
      return;
    }

    event?.preventDefault();
    this.#resetSearch();

    this.router.transitionTo(
      this.urlFor({
        series: this.seriesSlug,
        chip: this.chipSlug,
        version: this.version?.slug ?? this.versionSlug,
        page: page.slug,
      }),
    );
  }

  @action
  toggleTree() {
    this.treeOpen = !this.treeOpen;
    this.#rememberRails();
  }

  @action
  toggleRail() {
    this.railOpen = !this.railOpen;
    this.#rememberRails();

    if (this.railOpen) {
      this.#scheduleRailReveal();
    }
  }

  @action
  toggleGroup(slug) {
    this.collapsedGroups = this.collapsedGroups.includes(slug)
      ? this.collapsedGroups.filter((entry) => entry !== slug)
      : [...this.collapsedGroups, slug];
  }

  @action
  updateQuery(event) {
    const value = event.target.value;
    this.searchQuery = value;

    window.clearTimeout(this.#searchTimer);

    const query = value.trim();
    if (query.length < 2) {
      this.searchResults = null;
      this.searching = false;
      return;
    }

    this.searching = true;
    this.#searchTimer = window.setTimeout(() => this.#runSearch(), 250);
  }

  @action
  submitSearch(event) {
    event.preventDefault();

    if (this.searchHits.length > 0) {
      this.openPage(this.searchHits[0], event);
      return;
    }

    window.clearTimeout(this.#searchTimer);
    this.#runSearch();
  }

  @action
  clearSearch() {
    this.searchQuery = "";
    this.searchResults = null;
    this.searching = false;
    this.#searchInput?.focus();
  }

  async #runSearch() {
    const query = this.searchQuery.trim();
    if (query.length < 2) {
      return;
    }

    const token = ++this.#searchToken;
    this.searching = true;

    const params = new URLSearchParams({
      q: query,
      series: this.seriesSlug ?? "",
      chip: this.chipSlug ?? "",
      version: this.version?.slug ?? "",
    });

    try {
      const response = await fetch(
        withReadingLocale(getURL(`${SEARCH_ENDPOINT}?${params}`)),
        {
          headers: { Accept: "application/json" },
          cache: "no-store",
        },
      );

      if (token !== this.#searchToken) {
        return;
      }

      this.searchResults = response.ok ? (await response.json()).results : [];
    } catch {
      if (token === this.#searchToken) {
        this.searchResults = [];
      }
    } finally {
      if (token === this.#searchToken) {
        this.searching = false;
      }
    }
  }

  #resetSearch() {
    window.clearTimeout(this.#searchTimer);
    this.searchQuery = "";
    this.searchResults = null;
    this.searching = false;
  }

  // Split a result into the matched and unmatched runs so the template can
  // wrap one in <mark>. Glimmer escapes every string, so this is presentation
  // only and cannot inject markup.
  #highlight(text) {
    const value = text ?? "";
    const query = this.searchQuery.trim();

    if (!query) {
      return [{ text: value }];
    }

    const haystack = value.toLowerCase();
    const needle = query.toLowerCase();
    const parts = [];
    let index = 0;

    while (index < value.length) {
      const match = haystack.indexOf(needle, index);

      if (match < 0) {
        parts.push({ text: value.slice(index) });
        break;
      }

      if (match > index) {
        parts.push({ text: value.slice(index, match) });
      }

      parts.push({ text: value.slice(match, match + needle.length), match: true });
      index = match + needle.length;
    }

    return parts.filter((part) => part.text.length > 0);
  }

  @action
  setup() {
    window.addEventListener("keydown", this.#onKeydown);
    window.addEventListener("scroll", this.#onScroll, { passive: true });
  }

  @action
  captureSearch(element) {
    this.#searchInput = element;
  }

  @action
  decorateContent(element) {
    this.#decorateImages(element);
    this.#decorateCode(element);
    this.#decorateTables(element);
    this.#decorateLinks(element);
    this.#collectHeadings(element);
  }

  #decorateImages(element) {
    element.querySelectorAll("img").forEach((image) => {
      image.loading = "lazy";
      image.classList.add("ingenic-doc__image");
      image.tabIndex = 0;

      image.addEventListener("click", () => this.#openLightbox(image));
      image.addEventListener("keydown", (event) => {
        if (event.key === "Enter" || event.key === " ") {
          event.preventDefault();
          this.#openLightbox(image);
        }
      });

      const parent = image.parentElement;
      const standalone =
        parent?.tagName === "P" &&
        parent.children.length === 1 &&
        parent.textContent.trim() === "";

      if (!standalone) {
        return;
      }

      const figure = document.createElement("figure");
      figure.className = "ingenic-doc__figure";
      parent.replaceWith(figure);
      figure.appendChild(image);

      if (image.alt) {
        const caption = document.createElement("figcaption");
        caption.textContent = image.alt;
        figure.appendChild(caption);
      }

      const zoom = document.createElement("span");
      zoom.className = "ingenic-doc__zoom";
      zoom.textContent = "⤢";
      zoom.setAttribute(
        "aria-label",
        i18n(themePrefix("ingenic.docs.zoom_image")),
      );
      figure.appendChild(zoom);
    });
  }

  #openLightbox(image) {
    this.lightbox = {
      src: image.currentSrc || image.src,
      alt: image.alt || "",
    };
  }

  @action
  closeLightbox() {
    this.lightbox = null;
  }

  @action
  onLightboxKeydown(event) {
    if (event.key === "Escape") {
      this.closeLightbox();
    }
  }

  #decorateCode(element) {
    const copyLabel = i18n(themePrefix("ingenic.docs.copy"));
    const copiedLabel = i18n(themePrefix("ingenic.docs.copied"));

    element.querySelectorAll("pre > code").forEach((code) => {
      const pre = code.parentElement;
      if (pre.dataset.ingenicCode === "true") {
        return;
      }

      pre.dataset.ingenicCode = "true";

      const shell = document.createElement("div");
      shell.className = "ingenic-doc__codeshell";
      pre.replaceWith(shell);
      shell.appendChild(pre);

      const head = document.createElement("div");
      head.className = "ingenic-doc__codehead";

      const language = [...code.classList]
        .find((name) => name.startsWith("lang-"))
        ?.slice(5);

      const label = document.createElement("span");
      label.className = "ingenic-doc__codelang";
      label.textContent = language || "code";
      head.appendChild(label);

      const copy = document.createElement("button");
      copy.type = "button";
      copy.className = "ingenic-doc__copy";
      copy.textContent = copyLabel;
      copy.addEventListener("click", async () => {
        try {
          await navigator.clipboard.writeText(code.innerText);
          copy.textContent = copiedLabel;
          window.setTimeout(() => {
            copy.textContent = copyLabel;
          }, 1500);
        } catch {
          // A browser that refuses clipboard access leaves the label as it is;
          // selecting the code by hand still works.
        }
      });
      head.appendChild(copy);

      shell.prepend(head);
    });
  }

  #decorateTables(element) {
    element.querySelectorAll("table").forEach((table) => {
      if (table.parentElement?.classList.contains("ingenic-doc__tablewrap")) {
        return;
      }

      const wrap = document.createElement("div");
      wrap.className = "ingenic-doc__tablewrap";
      table.replaceWith(wrap);
      wrap.appendChild(table);
    });
  }

  #decorateLinks(element) {
    element.querySelectorAll("a[href]").forEach((link) => {
      if (!/^https?:/i.test(link.getAttribute("href") || "")) {
        return;
      }

      if (link.hostname === window.location.hostname) {
        return;
      }

      link.target = "_blank";
      link.rel = "noopener noreferrer";
    });
  }

  #collectHeadings(element) {
    const nodes = [...element.querySelectorAll("h2, h3")];

    nodes.forEach((node, index) => {
      if (!node.id) {
        node.id = `doc-section-${index}-${this.#slugify(node.textContent)}`;
      }

      if (node.dataset.ingenicAnchor !== "true") {
        node.dataset.ingenicAnchor = "true";

        const anchor = document.createElement("a");
        anchor.className = "ingenic-doc__anchor";
        anchor.href = `#${node.id}`;
        anchor.textContent = "#";
        anchor.setAttribute(
          "aria-label",
          i18n(themePrefix("ingenic.docs.link_section")),
        );
        node.appendChild(anchor);
      }
    });

    this.#headingElements = nodes;
    this.headings = nodes.map((node) => ({
      id: node.id,
      text: node.textContent.replace(/#$/, "").trim(),
      indent: HEADING_INDENT[node.tagName] ?? 0,
    }));

    if (!this.headings.some((heading) => heading.id === this.activeHeadingId)) {
      this.activeHeadingId = this.headings[0]?.id ?? null;
    }

    this.#onScroll();
    this.#scheduleRailReveal();
  }

  // The two rails are a reading preference: a manual read with the contents
  // folded should stay folded on the next page, and on the next visit.
  #rememberRails() {
    try {
      window.localStorage.setItem(
        RAILS_KEY,
        JSON.stringify({ toc: this.treeOpen, rail: this.railOpen }),
      );
    } catch {
      // Storage can be refused; the toggles still work for this visit.
    }
  }

  #storedRails() {
    try {
      return JSON.parse(window.localStorage.getItem(RAILS_KEY) || "{}") ?? {};
    } catch {
      return {};
    }
  }

  #slugify(text) {
    return (
      (text ?? "")
        .toLowerCase()
        .replace(/[^a-z0-9]+/g, "-")
        .replace(/^-+|-+$/g, "")
        .slice(0, 48) || "section"
    );
  }

  #onScroll = () => {
    if (this.#scrollFrame) {
      return;
    }

    this.#scrollFrame = window.requestAnimationFrame(() => {
      this.#scrollFrame = null;

      if (this.#headingElements.length === 0) {
        return;
      }

      // A heading counts as read once it has crossed the top of the article
      // pane. Measuring against the window instead would be measuring against
      // nothing: the page never scrolls, the pane does.
      const line = (this.#scroller?.getBoundingClientRect().top ?? 0) + 24;
      let active = this.#headingElements[0].id;

      for (const heading of this.#headingElements) {
        if (heading.getBoundingClientRect().top <= line) {
          active = heading.id;
        } else {
          break;
        }
      }

      // A last section shorter than the pane would otherwise never reach the
      // line, leaving the rail on the section before it while the reader is
      // looking at the end of the page. An article that fits in the pane is at
      // both its top and its bottom at once, so it is excluded: there, the
      // first section is the one being read.
      const scroller = this.#scroller;
      const overflows = scroller
        ? scroller.scrollHeight > scroller.clientHeight + 8
        : false;

      if (
        overflows &&
        scroller.scrollTop + scroller.clientHeight >=
          scroller.scrollHeight - 8
      ) {
        active = this.#headingElements[this.#headingElements.length - 1].id;
      }

      if (active !== this.activeHeadingId) {
        this.activeHeadingId = active;
        this.#scheduleRailReveal();
      }
    });
  };

  // Keep a stable reference to the rail itself. The active row is rendered by
  // Glimmer after `activeHeadingId` changes, so the reveal is scheduled for the
  // next frame rather than being tied to each link's modifier lifecycle.
  @action
  captureRail(element) {
    this.#rail = element;
    this.#scheduleRailReveal();
  }

  #scheduleRailReveal() {
    if (this.#railRevealFrame || typeof window === "undefined") {
      return;
    }

    this.#railRevealFrame = window.requestAnimationFrame(() => {
      this.#railRevealFrame = null;
      this.#revealActiveRailRow();
    });
  }

  // On a long page the rail is taller than the pane it sits in. Moving the
  // reader's place in the article has to bring that row into view as well,
  // without the rail jumping around when the row is already visible. Only the
  // rail's own scrollTop is changed; the article pane never moves here.
  #revealActiveRailRow() {
    const rail = this.#rail;

    if (
      !rail ||
      rail.clientHeight === 0 ||
      rail.scrollHeight <= rail.clientHeight
    ) {
      return;
    }

    const active = rail.querySelector(".ingenic-docs__rail-link.is-active");

    if (!active) {
      return;
    }

    const row = active.getBoundingClientRect();
    const pane = rail.getBoundingClientRect();
    const margin = 12;

    if (row.top < pane.top + margin) {
      rail.scrollTop -= pane.top + margin - row.top;
    } else if (row.bottom > pane.bottom - margin) {
      rail.scrollTop += row.bottom - (pane.bottom - margin);
    }
  }

  #onKeydown = (event) => {
    if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") {
      event.preventDefault();
      this.#searchInput?.focus();
      return;
    }

    if (event.key === "Escape") {
      this.pickerOpen = false;
      this.searchResults = null;
      this.searching = false;
      this.lightbox = null;
    }
  };

  willDestroy() {
    window.clearTimeout(this.#searchTimer);

    if (this.#scrollFrame) {
      window.cancelAnimationFrame(this.#scrollFrame);
    }

    if (this.#railRevealFrame) {
      window.cancelAnimationFrame(this.#railRevealFrame);
    }

    this.#scroller?.removeEventListener("scroll", this.#onScroll);
    this.#scroller = null;
    this.#rail = null;
    window.removeEventListener("keydown", this.#onKeydown);
    window.removeEventListener("scroll", this.#onScroll);
  }

  <template>
    <div
      class="ingenic-docs"
      {{didInsert this.setup}}
      {{didInsert this.load}}
      {{didUpdate this.load @path this.activeLocale}}
    >
      {{#if this.loading}}
        <p class="ingenic-docs__notice">
          {{i18n (themePrefix "ingenic.docs.loading")}}
        </p>
      {{else if this.hasProducts}}
        <div class="ingenic-docs__toolbar">
          <nav class="ingenic-docs__crumbs" aria-label="Breadcrumb">
            <a href={{getURL "/ingenic/docs"}}>{{i18n (themePrefix "ingenic.docs.documentation")}}</a>
            {{#if this.seriesName}}
              <span class="ingenic-docs__crumb-sep" aria-hidden="true">/</span>
              <span class="ingenic-docs__crumb-current">{{this.seriesName}}</span>
            {{/if}}
          </nav>

          <div class="ingenic-docpicker {{if this.pickerOpen 'is-open'}}">
            {{#if this.pickerOpen}}
              <div
                class="ingenic-docpicker__scrim"
                role="presentation"
                {{on "click" this.closePicker}}
              ></div>
            {{/if}}

            <button
              type="button"
              class="ingenic-docpicker__trigger"
              aria-expanded={{if this.pickerOpen "true" "false"}}
              {{on "click" this.togglePicker}}
            >
              <span class="ingenic-docpicker__glyph">{{dIcon "microchip"}}</span>
              <span class="ingenic-docpicker__value">
                {{this.chip.name}}
              </span>
              <span class="ingenic-docpicker__caret" aria-hidden="true">▾</span>
            </button>

            {{#if this.pickerOpen}}
              <div class="ingenic-docpicker__panel">
                <div class="ingenic-docpicker__column">
                  <p class="ingenic-docpicker__heading">
                    {{i18n (themePrefix "ingenic.docs.series")}}
                  </p>
                  <ul class="ingenic-docpicker__series">
                    {{#each this.seriesList as |series|}}
                      <li>
                        <button
                          type="button"
                          class="ingenic-docpicker__series-button {{if series.isOpen 'is-open'}} {{if series.isCurrent 'is-current'}}"
                          {{on "mouseenter" (fn this.chooseSeries series)}}
                          {{on "click" (fn this.chooseSeries series)}}
                        >
                          <span>{{series.name}}</span>
                          <span class="ingenic-docpicker__arrow" aria-hidden="true">›</span>
                        </button>
                      </li>
                    {{/each}}
                  </ul>
                </div>

                <div class="ingenic-docpicker__column ingenic-docpicker__column--chips">
                  <p class="ingenic-docpicker__heading">
                    {{i18n (themePrefix "ingenic.docs.chips")}}
                    {{#if this.openSeries}}
                      <span>· {{this.openSeries.name}}</span>
                    {{/if}}
                  </p>
                  <ul class="ingenic-docpicker__chips">
                    {{#each this.openSeries.chips as |chip|}}
                      <li>
                        <button
                          type="button"
                          class="ingenic-docpicker__chip {{if chip.isCurrent 'is-current'}}"
                          {{on "click" (fn this.selectChip this.openSeries chip)}}
                        >
                          {{chip.name}}
                          {{#if chip.isCurrent}}
                            <span class="ingenic-docpicker__check" aria-hidden="true">✓</span>
                          {{/if}}
                        </button>
                      </li>
                    {{else}}
                      <li class="ingenic-docpicker__empty">
                        {{i18n (themePrefix "ingenic.docs.no_chips")}}
                      </li>
                    {{/each}}
                  </ul>
                </div>
              </div>
            {{/if}}
          </div>

          {{#if this.versions.length}}
            <label class="ingenic-docs__version">
              <select
                aria-label={{i18n (themePrefix "ingenic.docs.version")}}
                {{on "change" this.selectVersion}}
              >
                {{#each this.versionOptions as |version|}}
                  <option value={{version.slug}} selected={{version.isSelected}}>
                    {{version.label}}{{#if version.latest}} · {{i18n (themePrefix "ingenic.docs.latest")}}{{/if}}
                  </option>
                {{/each}}
              </select>
              <span class="ingenic-docs__version-caret" aria-hidden="true">▾</span>
            </label>
          {{/if}}

          <button
            type="button"
            class="ingenic-docs__toc-toggle"
            aria-expanded={{if this.treeOpen "true" "false"}}
            {{on "click" this.toggleTree}}
          >
            {{dIcon "list"}}
            {{i18n (themePrefix "ingenic.docs.contents")}}
          </button>

          <div class="ingenic-docsearch">
            <form class="ingenic-docsearch__form" {{on "submit" this.submitSearch}}>
              <span class="ingenic-docsearch__icon">{{dIcon "magnifying-glass"}}</span>
              <input
                type="search"
                name="query"
                class="ingenic-docsearch__input"
                value={{this.searchQuery}}
                placeholder={{i18n (themePrefix "ingenic.docs.search_placeholder")}}
                autocomplete="off"
                {{didInsert this.captureSearch}}
                {{on "input" this.updateQuery}}
              />
              {{#if this.searchQuery}}
                <button
                  type="button"
                  class="ingenic-docsearch__clear"
                  aria-label={{i18n (themePrefix "ingenic.docs.clear_search")}}
                  {{on "click" this.clearSearch}}
                >
                  {{dIcon "times"}}
                </button>
              {{else}}
                <kbd class="ingenic-docsearch__kbd">⌘K</kbd>
              {{/if}}
            </form>

            {{#if this.searchOpen}}
              <div class="ingenic-docsearch__panel">
                {{#if this.searching}}
                  <p class="ingenic-docsearch__state">
                    {{i18n (themePrefix "ingenic.docs.loading")}}
                  </p>
                {{else}}
                  <p class="ingenic-docsearch__summary">
                    {{i18n (themePrefix "ingenic.docs.result_count")}}
                    {{this.searchHits.length}}
                  </p>

                  <ul class="ingenic-docsearch__results">
                    {{#each this.searchHits as |hit|}}
                      <li>
                        <a
                          class="ingenic-docsearch__result"
                          href={{hit.href}}
                          {{on "click" (fn this.openPage hit)}}
                        >
                          <span class="ingenic-docsearch__title">
                            {{#each hit.titleParts as |part|}}
                              {{#if part.match}}<mark>{{part.text}}</mark>{{else}}{{part.text}}{{/if}}
                            {{/each}}
                          </span>
                          <span class="ingenic-docsearch__excerpt">
                            {{#each hit.excerptParts as |part|}}
                              {{#if part.match}}<mark>{{part.text}}</mark>{{else}}{{part.text}}{{/if}}
                            {{/each}}
                          </span>
                        </a>
                      </li>
                    {{else}}
                      <li class="ingenic-docsearch__empty">
                        {{i18n (themePrefix "ingenic.docs.no_results")}}
                      </li>
                    {{/each}}
                  </ul>
                {{/if}}
              </div>
            {{/if}}
          </div>
        </div>

        <div
          class="ingenic-docs__panes
            {{if this.page 'ingenic-docs__panes--rail'}}
            {{unless this.treeOpen 'is-toc-hidden'}}
            {{unless this.railOpen 'is-rail-hidden'}}"
        >
          {{! The two triangles sit on the borders the rails share with the
              page, so the reader pushes a rail away from the text rather than
              hunting for a control in a toolbar. They stay put when a rail is
              folded — a folded rail that could not be brought back would be a
              one-way door. }}
          <button
            aria-controls="ingenic-doctoc"
            aria-expanded={{if this.treeOpen "true" "false"}}
            aria-label={{if
              this.treeOpen
              (i18n (themePrefix "ingenic.docs.hide_contents"))
              (i18n (themePrefix "ingenic.docs.show_contents"))
            }}
            class="ingenic-docs__rail-toggle ingenic-docs__rail-toggle--toc"
            type="button"
            {{on "click" this.toggleTree}}
          >
            {{dIcon (if this.treeOpen "chevron-left" "chevron-right")}}
          </button>

          {{#if this.page}}
            <button
              aria-controls="ingenic-docs-rail"
              aria-expanded={{if this.railOpen "true" "false"}}
              aria-label={{if
                this.railOpen
                (i18n (themePrefix "ingenic.docs.hide_rail"))
                (i18n (themePrefix "ingenic.docs.show_rail"))
              }}
              class="ingenic-docs__rail-toggle ingenic-docs__rail-toggle--rail"
              type="button"
              {{on "click" this.toggleRail}}
            >
              {{dIcon (if this.railOpen "chevron-right" "chevron-left")}}
            </button>
          {{/if}}

          <aside class="ingenic-doctoc {{unless this.treeOpen 'is-collapsed'}}" id="ingenic-doctoc">
            <p class="ingenic-doctoc__title">
              {{i18n (themePrefix "ingenic.docs.contents")}}
            </p>

            {{#if this.tocRows.length}}
              <ul class="ingenic-doctoc__tree">
                {{#each this.tocRows as |row|}}
                  <li
                    class="ingenic-doctoc__node"
                    style="--ingenic-toc-level: {{row.level}}"
                  >
                    {{! The tree is drawn, not decorated: one column per
                        ancestor level, then the elbow into this row. }}
                    <span class="ingenic-doctoc__guides" aria-hidden="true">
                      {{#each row.guides as |continues|}}
                        <span
                          class="ingenic-doctoc__guide {{if continues 'is-on'}}"
                        ></span>
                      {{/each}}
                      <span
                        class="ingenic-doctoc__elbow {{if row.isLast 'is-last'}}"
                      ></span>
                    </span>

                    {{#if row.isFolder}}
                      {{#if row.hasChildren}}
                        <button
                          type="button"
                          class="ingenic-doctoc__row ingenic-doctoc__row--folder ingenic-doctoc__row--toggle"
                          aria-expanded={{if row.isOpen "true" "false"}}
                          {{on "click" (fn this.toggleGroup row.slug)}}
                        >
                          <span class="ingenic-doctoc__label">{{row.title}}</span>
                          <span
                            class="ingenic-doctoc__chev {{if row.isOpen 'is-open'}}"
                            aria-hidden="true"
                          >▾</span>
                        </button>
                      {{else}}
                        <span class="ingenic-doctoc__row ingenic-doctoc__row--folder">
                          <span class="ingenic-doctoc__label">{{row.title}}</span>
                        </span>
                      {{/if}}
                    {{else}}
                      <a
                        class="ingenic-doctoc__row {{if row.isActive 'is-current'}}"
                        href={{row.href}}
                        {{on "click" (fn this.openPage row)}}
                      >
                        <span class="ingenic-doctoc__label">{{row.title}}</span>
                      </a>
                    {{/if}}
                  </li>
                {{/each}}
              </ul>
            {{else}}
              <p class="ingenic-doctoc__empty">
                {{i18n (themePrefix "ingenic.docs.empty")}}
              </p>
            {{/if}}
          </aside>

          <main class="ingenic-docs__main">
            {{#if this.loadError}}
              <div class="ingenic-docs__emptycard">
                <span class="ingenic-docs__emptyicon">{{dIcon "triangle-exclamation"}}</span>
                <h2>{{i18n (themePrefix "ingenic.docs.load_failed")}}</h2>
                <p>{{i18n (themePrefix "ingenic.docs.load_failed_hint")}}</p>
                <button
                  type="button"
                  class="btn btn-primary ingenic-docs__retry"
                  {{on "click" this.retry}}
                >
                  {{i18n (themePrefix "ingenic.docs.retry")}}
                </button>
              </div>
            {{else if this.notFound}}
              <div class="ingenic-docs__emptycard">
                <span class="ingenic-docs__emptyicon">{{dIcon "triangle-exclamation"}}</span>
                <h2>{{i18n (themePrefix "ingenic.docs.not_found")}}</h2>
                <p>{{i18n (themePrefix "ingenic.docs.pick_page")}}</p>
              </div>
            {{else if this.page}}
              <article class="ingenic-doc">
                <div
                  class="ingenic-doc__scroll"
                  {{didInsert this.syncScroll}}
                  {{didUpdate this.syncScroll this.page.slug}}
                >
                <section class="ingenic-doc__hero">
                  <div class="ingenic-doc__hero-top">
                    <div class="ingenic-doc__chipmark">
                      <b>{{this.chipMark}}</b>
                      <span>{{i18n (themePrefix "ingenic.docs.soc")}}</span>
                    </div>

                    <div class="ingenic-doc__hero-text">
                      <h1>{{this.page.title}}</h1>
                      <p class="ingenic-doc__subtitle">
                        {{this.seriesName}} · {{i18n (themePrefix "ingenic.docs.documentation")}}
                      </p>

                      <div class="ingenic-doc__pills">
                        {{#if this.version}}
                          <span class="ingenic-doc__pill ingenic-doc__pill--green">
                            <span class="ingenic-doc__dot" aria-hidden="true"></span>
                            {{this.version.label}}
                            {{#if this.version.latest}}
                              · {{i18n (themePrefix "ingenic.docs.latest_label")}}
                            {{/if}}
                          </span>
                        {{/if}}
                        <span class="ingenic-doc__pill ingenic-doc__pill--blue">
                          {{this.chip.name}}
                        </span>
                        {{#if this.updatedDate}}
                          <span class="ingenic-doc__pill">
                            {{i18n (themePrefix "ingenic.docs.updated") date=this.updatedDate}}
                          </span>
                        {{/if}}
                      </div>
                    </div>
                  </div>

                  <div class="ingenic-doc__hero-actions">
                    <a class="ingenic-doc__btn ingenic-doc__btn--primary" href={{getURL "/ingenic/downloads"}}>
                      {{dIcon "download"}}
                      {{i18n (themePrefix "ingenic.docs.download_sdk")}}
                    </a>
                    <a class="ingenic-doc__btn" href={{getURL "/ingenic/boards"}}>
                      {{dIcon "microchip"}}
                      {{i18n (themePrefix "ingenic.docs.boards_action")}}
                    </a>
                  </div>
                </section>

                <div
                  class="ingenic-doc__content"
                  {{didInsert this.decorateContent}}
                  {{didUpdate this.decorateContent this.page.body}}
                >{{trustHTML this.page.body}}</div>

                {{#if this.page.discussion_url}}
                  <p class="ingenic-doc__discuss">
                    <a href={{getURL this.page.discussion_url}}>
                      {{dIcon "comments"}}
                      {{i18n (themePrefix "ingenic.docs.discuss")}}
                    </a>
                  </p>
                {{/if}}
                </div>

                <footer class="ingenic-doc__pager">
                  {{#if this.previousLink}}
                    <a
                      class="ingenic-doc__pagecard"
                      href={{this.previousLink.href}}
                      {{on "click" (fn this.openPage this.previousLink)}}
                    >
                      <small>{{i18n (themePrefix "ingenic.docs.previous")}}</small>
                      <b>{{this.previousLink.title}}</b>
                    </a>
                  {{/if}}

                  {{#if this.nextLink}}
                    <a
                      class="ingenic-doc__pagecard ingenic-doc__pagecard--next"
                      href={{this.nextLink.href}}
                      {{on "click" (fn this.openPage this.nextLink)}}
                    >
                      <small>{{i18n (themePrefix "ingenic.docs.next")}}</small>
                      <b>{{this.nextLink.title}}</b>
                    </a>
                  {{/if}}
                </footer>
              </article>
            {{else}}
              <div class="ingenic-docs__emptycard">
                <span class="ingenic-docs__emptyicon">{{dIcon "file-lines"}}</span>
                <h2>
                  {{#if this.chip}}
                    {{#if this.versions.length}}
                      {{i18n (themePrefix "ingenic.docs.pick_page")}}
                    {{else}}
                      {{i18n (themePrefix "ingenic.docs.no_versions")}}
                    {{/if}}
                  {{else}}
                    {{i18n (themePrefix "ingenic.docs.pick_page")}}
                  {{/if}}
                </h2>
              </div>
            {{/if}}
          </main>

          {{#if this.page}}
            <aside
              class="ingenic-docs__rail"
              id="ingenic-docs-rail"
              {{didInsert this.captureRail}}
            >
              <p class="ingenic-docs__rail-title">
                {{i18n (themePrefix "ingenic.docs.on_this_page")}}
              </p>

              {{#each this.railHeadings as |heading|}}
                <a
                  class="ingenic-docs__rail-link ingenic-docs__rail-link--{{heading.indent}} {{if heading.isActive 'is-active'}}"
                  href="#{{heading.id}}"
                >
                  {{heading.text}}
                </a>
              {{/each}}

              <div class="ingenic-docs__help">
                <span class="ingenic-docs__help-icon">{{dIcon "comments"}}</span>
                <b>{{i18n (themePrefix "ingenic.docs.need_help")}}</b>
                <span>{{i18n (themePrefix "ingenic.docs.need_help_text")}}</span>
                <a href={{this.forumHref}}>
                  {{i18n (themePrefix "ingenic.docs.go_to_forum")}} →
                </a>
              </div>
            </aside>
          {{/if}}
        </div>
      {{else if this.loadError}}
        <div class="ingenic-docs__emptycard">
          <span class="ingenic-docs__emptyicon">{{dIcon "triangle-exclamation"}}</span>
          <h2>{{i18n (themePrefix "ingenic.docs.load_failed")}}</h2>
          <p>{{i18n (themePrefix "ingenic.docs.load_failed_hint")}}</p>
          <button
            type="button"
            class="btn btn-primary ingenic-docs__retry"
            {{on "click" this.retry}}
          >
            {{i18n (themePrefix "ingenic.docs.retry")}}
          </button>
        </div>
      {{else if this.notFound}}
        <p class="ingenic-docs__notice">
          {{i18n (themePrefix "ingenic.docs.not_found")}}
        </p>
      {{else}}
        <p class="ingenic-docs__notice">
          {{i18n (themePrefix "ingenic.docs.no_products")}}
        </p>
      {{/if}}

      {{#if this.lightbox}}
        <div
          class="ingenic-docs__lightbox"
          role="dialog"
          aria-modal="true"
          tabindex="-1"
          {{on "click" this.closeLightbox}}
          {{on "keydown" this.onLightboxKeydown}}
        >
          <img src={{this.lightbox.src}} alt={{this.lightbox.alt}} />
          <button
            type="button"
            class="ingenic-docs__lightbox-close"
            aria-label={{i18n (themePrefix "ingenic.docs.close")}}
            {{on "click" this.closeLightbox}}
          >
            {{dIcon "times"}}
          </button>
        </div>
      {{/if}}
    </div>
  </template>
}
