import { embedUrl } from '../lib/slides';

/**
 * Plays a county's Google Slides deck inline.
 *
 * Just the player: no edit button, no link out. Navigation (the arrows, the
 * slide counter, fullscreen) is Google's own, rendered inside the iframe.
 *
 * NOTE ON SANDBOX: this iframe deliberately carries no `sandbox` attribute.
 * An earlier version sandboxed it, which risks breaking Google's own controls
 * — and bought almost nothing, because `allow-scripts` plus `allow-same-origin`
 * is close to no sandbox at all for cross-origin content. The real control is
 * upstream: lib/slides.js allowlists docs.google.com and rebuilds the URL from
 * a validated presentation ID, so this element can only ever point at a Google
 * Slides deck. Widening trust here would mean weakening that parser, not
 * removing this attribute.
 */
export default function SlidesEmbed({ url, countyName }) {
  if (!url) {
    return <p className="muted">No presentation linked for this county yet.</p>;
  }

  const src = embedUrl(url);

  // Parsed to nothing: a typo, or a link that is not a Google Slides deck.
  // Never fall back to framing the raw input.
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
        // Both spellings: `allowFullScreen` is the modern attribute, `allow`
        // is what Chrome checks for the Fullscreen API inside the frame.
        allowFullScreen
        allow="fullscreen"
        loading="lazy"
        referrerPolicy="no-referrer-when-downgrade"
      />
    </div>
  );
}
