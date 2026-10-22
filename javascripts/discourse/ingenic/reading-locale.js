import I18n from "discourse-i18n";

/**
 * The language the plugin's public readers answer in.
 *
 * It is sent on the address rather than left to a cookie. The same page is read
 * in more than one language from one address, and a server whose answer depends
 * on a cookie the URL does not mention is a server behind a cache that can hand
 * one reader the other's language. Naming it also lets the reader follow the
 * language change without a hard refresh: a new value is a new address.
 *
 * Discourse uses `zh_CN` in its settings and `zh-CN` in the document language,
 * so the separator is normalised rather than passed through.
 */
export function readingLocale() {
  const value = I18n.currentLocale?.() || document.documentElement.lang || "en";

  return String(value).replace(/-/g, "_");
}

// `url` has already been through `getURL`, so it carries the deployment prefix.
export function withReadingLocale(url) {
  const locale = readingLocale();
  const [path, query] = String(url).split("?");

  if (!locale) {
    return url;
  }

  const params = new URLSearchParams(query || "");
  params.set("locale", locale);

  return `${path}?${params}`;
}
