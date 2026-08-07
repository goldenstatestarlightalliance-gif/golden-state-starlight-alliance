// Google Slides URL handling.
//
// SECURITY: whatever comes out of `embedUrl` goes straight into an <iframe
// src>. Anyone with edit rights on a county can set slides_url, so this must
// never pass through an arbitrary URL — a hostile one could frame a look-alike
// page inside the county page. So we parse strictly: extract the presentation
// ID, verify the host, and REBUILD the URL from the ID rather than forwarding
// whatever was pasted. A URL that does not parse renders nothing.

const ALLOWED_HOSTS = new Set(['docs.google.com', 'www.docs.google.com']);

// Google presentation IDs are long base64url-ish strings. Anchored and
// length-bounded so a crafted path segment cannot smuggle anything through.
const ID_PATTERN = /^[A-Za-z0-9_-]{16,120}$/;

/**
 * Pull the presentation ID out of any of the shapes people actually paste:
 *   .../presentation/d/<id>/edit#slide=id.p
 *   .../presentation/d/<id>/pub?start=true
 *   .../presentation/d/e/<pubId>/pubembed      (published-to-web)
 *   .../presentation/d/<id>/embed?start=false
 * Returns { id, published } or null.
 */
export function parseSlidesUrl(raw) {
  if (!raw || typeof raw !== 'string') return null;

  let url;
  try {
    url = new URL(raw.trim());
  } catch {
    return null;
  }

  if (url.protocol !== 'https:') return null;
  if (!ALLOWED_HOSTS.has(url.hostname)) return null;

  const parts = url.pathname.split('/').filter(Boolean);
  // Expect: presentation / d / [e /] <id> / ...
  if (parts[0] !== 'presentation' || parts[1] !== 'd') return null;

  // The /d/e/ form is a "publish to web" ID, which is a different value from
  // the document ID and must keep the /e/ segment when rebuilt.
  const published = parts[2] === 'e';
  const id = published ? parts[3] : parts[2];

  if (!id || !ID_PATTERN.test(id)) return null;

  return { id, published };
}

export const isValidSlidesUrl = (raw) => parseSlidesUrl(raw) !== null;

/** Player URL for an <iframe>. Rebuilt from the ID, never the input. */
export function embedUrl(raw) {
  const parsed = parseSlidesUrl(raw);
  if (!parsed) return null;

  const base = parsed.published
    ? `https://docs.google.com/presentation/d/e/${parsed.id}/embed`
    : `https://docs.google.com/presentation/d/${parsed.id}/embed`;

  // No autoplay: a deck that starts moving on page load is hostile to someone
  // reading the county page for its ordinance data.
  return `${base}?start=false&loop=false&delayms=60000`;
}

/**
 * The real editor. This CANNOT be iframed — Google sends framing headers that
 * block it — so it is only ever used as a target="_blank" link.
 *
 * Published-to-web IDs are not document IDs, so there is no editor URL to
 * derive from one; returns null in that case and the UI hides the button.
 */
export function editUrl(raw) {
  const parsed = parseSlidesUrl(raw);
  if (!parsed || parsed.published) return null;
  return `https://docs.google.com/presentation/d/${parsed.id}/edit`;
}
