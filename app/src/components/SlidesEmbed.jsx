import { embedUrl } from '../lib/slides';

/**
 * Plays a county's Google Slides deck inline.
 *
 * Just the player: no edit button, no "open in Google Slides" link. The deck
 * runs in the page with its own built-in controls (next/previous, fullscreen,
 * present), so a visitor never leaves the county page to view it.
 */
export default function SlidesEmbed({ url, countyName }) {
  if (!url) {
    return <p className="muted">No presentation linked for this county yet.</p>;
  }

  const src = embedUrl(url);

  // Parsed to nothing: a typo, or a link that is not a Google Slides deck.
  // Never fall back to framing the raw input — see lib/slides.js.
  if (!src) {
    return (
      <p className="error">
        The presentation linked for {countyName} County is not a valid Google
        Slides URL, so it has not been embedded.
      </p>
    );
  }

  return (
    <div className="slides-frame">
      <iframe
        src={src}
        title={`${countyName} County outreach presentation`}
        allowFullScreen
        loading="lazy"
        sandbox="allow-scripts allow-same-origin allow-popups allow-presentation"
        referrerPolicy="no-referrer-when-downgrade"
      />
    </div>
  );
}
