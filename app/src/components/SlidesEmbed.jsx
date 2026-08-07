import { embedUrl, editUrl } from '../lib/slides';

/**
 * Plays a county's Google Slides deck inline.
 *
 * Editing deliberately happens in a new tab. Google blocks its editor from
 * being framed, so an in-page edit surface is not buildable — the honest
 * version is a clear hand-off to the real editor, where inserting slides,
 * reordering, and everything else works normally.
 */
export default function SlidesEmbed({ url, countyName }) {
  if (!url) {
    return (
      <p className="muted">
        No presentation linked for this county yet.
      </p>
    );
  }

  const src = embedUrl(url);
  const edit = editUrl(url);

  // Parsed to nothing: either a typo or a non-Google link. Say so rather than
  // rendering an empty box, and never fall back to framing the raw input.
  if (!src) {
    return (
      <p className="error">
        The linked presentation is not a valid Google Slides URL, so it has not
        been embedded.{' '}
        <a href={url} target="_blank" rel="noreferrer noopener">Open the link directly</a>{' '}
        to check it.
      </p>
    );
  }

  return (
    <div className="slides">
      <div className="slides-frame">
        <iframe
          src={src}
          title={`${countyName} County outreach presentation`}
          allowFullScreen
          loading="lazy"
          // The deck is third-party content in our page; deny it everything it
          // does not need.
          sandbox="allow-scripts allow-same-origin allow-popups allow-presentation"
          referrerPolicy="no-referrer-when-downgrade"
        />
      </div>

      <div className="slides-actions">
        {edit ? (
          <>
            <a
              className="btn btn-primary"
              href={edit}
              target="_blank"
              rel="noreferrer noopener"
            >
              Edit in Google Slides ↗
            </a>
            <span className="muted slides-note">
              Opens the real editor in a new tab — add, reorder, or delete
              slides there and the change shows up here on reload. Google does
              not allow its editor to run inside another site.
            </span>
          </>
        ) : (
          <span className="muted slides-note">
            This deck is linked by its published-to-web address, which is
            view-only. Link the editable{' '}
            <code>/presentation/d/…/edit</code> URL instead to enable editing.
          </span>
        )}
      </div>
    </div>
  );
}
