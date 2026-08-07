import { useState } from 'react';
import { supabase } from '../lib/supabase';
import { STAGES } from '../lib/pipeline';
import { isValidSlidesUrl } from '../lib/slides';

/**
 * Edit panel shown on a county page to anyone the RLS policy would let write.
 *
 * Every change here goes through the same policies as any other client — this
 * is not an admin bypass. A user who somehow sees this panel without rights
 * gets a policy error from Postgres rather than a silent success.
 */
export default function CountyEditor({ county, onSaved }) {
  const [status, setStatus] = useState(county.status);
  const [slidesUrl, setSlidesUrl] = useState(county.slides_url ?? '');
  const [cityStatuses, setCityStatuses] = useState(
    Object.fromEntries((county.cities ?? []).map((c) => [c.id, c.status]))
  );

  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const [saved, setSaved] = useState(null);

  // Empty clears the deck; anything else must parse, or the county page would
  // render an error box instead of a presentation.
  const slidesValid = slidesUrl.trim() === '' || isValidSlidesUrl(slidesUrl.trim());

  const saveCounty = async () => {
    setBusy(true); setError(null); setSaved(null);

    const { error } = await supabase
      .from('counties')
      .update({
        status,
        slides_url: slidesUrl.trim() === '' ? null : slidesUrl.trim(),
      })
      .eq('id', county.id);

    if (error) setError(error.message);
    else { setSaved('County updated.'); await onSaved?.(); }
    setBusy(false);
  };

  const saveCity = async (cityId) => {
    setBusy(true); setError(null); setSaved(null);

    const { error } = await supabase
      .from('cities')
      .update({ status: cityStatuses[cityId] })
      .eq('id', cityId);

    if (error) setError(error.message);
    else { setSaved('City updated.'); await onSaved?.(); }
    setBusy(false);
  };

  return (
    <section className="editor">
      <h2>Edit this county</h2>
      <p className="muted editor-note">
        Changes are recorded in the county timeline with your name against them.
      </p>

      {error && <p className="error">{error}</p>}
      {saved && <p className="notice">{saved}</p>}

      <div className="editor-row">
        <label>
          <span>County stage</span>
          <select value={status} onChange={(e) => setStatus(e.target.value)}>
            {STAGES.map((s) => (
              <option key={s.key} value={s.key}>{s.label}</option>
            ))}
          </select>
        </label>
      </div>

      <div className="editor-row">
        <label>
          <span>Google Slides presentation</span>
          <input
            type="url"
            placeholder="https://docs.google.com/presentation/d/…"
            value={slidesUrl}
            onChange={(e) => setSlidesUrl(e.target.value)}
          />
          {!slidesValid && (
            <small className="field-error">
              That is not a Google Slides link. Paste the address bar from the
              open presentation, or clear the field to remove it.
            </small>
          )}
          <small className="muted">
            The deck must be shared as “Anyone with the link → Viewer”, or
            visitors will see a “You need access” box instead of the slides.
          </small>
        </label>
      </div>

      <button
        className="btn btn-primary"
        onClick={saveCounty}
        disabled={busy || !slidesValid}
      >
        {busy ? 'Saving…' : 'Save county'}
      </button>

      {(county.cities ?? []).length > 0 && (
        <>
          <h3>City stages</h3>
          <ul className="editor-cities">
            {county.cities.map((c) => (
              <li key={c.id}>
                <span className="editor-city-name">{c.name}</span>
                <select
                  value={cityStatuses[c.id] ?? 'not_started'}
                  onChange={(e) =>
                    setCityStatuses({ ...cityStatuses, [c.id]: e.target.value })
                  }
                >
                  {STAGES.map((s) => (
                    <option key={s.key} value={s.key}>{s.label}</option>
                  ))}
                </select>
                <button
                  className="btn btn-ghost btn-small"
                  onClick={() => saveCity(c.id)}
                  disabled={busy || cityStatuses[c.id] === c.status}
                >
                  Save
                </button>
              </li>
            ))}
          </ul>
        </>
      )}
    </section>
  );
}
