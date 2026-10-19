// Addresses that were written while the site answered on a local host.
//
// A logo or an image field can hold an absolute `http://localhost:3000/...`
// address: the server built it from the address it knew at the time, or an
// administrator pasted it in from a local session. That address is right on the
// machine that wrote it and wrong for every visitor — their own computer either
// has nothing there or refuses the connection, and the image arrives broken.
// Re-root such an address to the origin the page is actually being viewed from;
// a URL on any other host is left exactly as configured.
const LOCAL_HOSTS = ["localhost", "127.0.0.1", "0.0.0.0", "::1", "[::1]"];

export function rebaseLocalUrl(value) {
  if (typeof value !== "string" || value.length === 0) {
    return value;
  }

  try {
    const parsed = new URL(value, window.location.origin);

    if (
      parsed.hostname !== window.location.hostname &&
      LOCAL_HOSTS.includes(parsed.hostname)
    ) {
      return `${window.location.origin}${parsed.pathname}${parsed.search}${parsed.hash}`;
    }
  } catch {
    // Not an address that can be parsed; leave it to the browser.
  }

  return value;
}
