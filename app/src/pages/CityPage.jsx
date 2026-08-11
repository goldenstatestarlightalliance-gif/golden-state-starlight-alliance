import { Link, useParams } from 'react-router-dom';

import { useCity } from '../lib/queries';
import { STAGES, stageColor, stageLabel, stageIndex } from '../lib/pipeline';
import SlidesEmbed from '../components/SlidesEmbed';
import DocumentLinks from '../components/DocumentLinks';

export default function CityPage() {
  const { countySlug, citySlug } = useParams();
  const { data: city, error, loading } = useCity(countySlug, citySlug);

  if (loading) return <div className="page"><p className="muted">Loading…</p></div>;
  if (error) return <div className="page"><p className="error">Could not load this city: {error}</p></div>;
  if (!city) return <div className="page"><p className="error">City not found.</p></div>;

  const county = city.counties;
  const hasOrdinance = stageIndex(city.status) >= stageIndex('passed');
  const ordinances = city.ordinances ?? [];
  const docs = city.county_documents ?? [];
  const redline = docs.find((d) => d.kind === 'redlined_ordinance');

  return (
    <div className="page">
      <p className="crumb">
        <Link to="/map">← Statewide map</Link>
        {' · '}
        <Link to={`/county/${county.slug}`}>{county.name} County</Link>
      </p>

      <header className="page-head">
        <h1>{city.name}</h1>
        <p>
          <span className="pill" style={{ background: stageColor(city.status) }}>
            {stageLabel(city.status)}
          </span>
          {city.is_priority && <span className="tier">★ Priority outreach target</span>}
        </p>
      </header>

      <div className="city-grid">
        <section>
          {/* The pipeline, so the current stage is legible without scrolling
              back to a legend on another page. */}
          <ol className="stage-flow city-stage-flow">
            {STAGES.map((s, i) => {
              const reached = i <= stageIndex(city.status);
              return (
                <li key={s.key} className={reached ? 'stage-reached' : 'stage-pending'}>
                  <span
                    className="stage-dot"
                    style={{ background: reached ? s.color : '#f1f5f9' }}
                  />
                  <span className="stage-n">{i + 1}</span>
                  <span className="stage-name">{s.label}</span>
                </li>
              );
            })}
          </ol>

          <h2>Ordinance</h2>
          {ordinances.length ? (
            ordinances.map((o) => (
              <article key={o.id} className="ordinance">
                <h3>{o.title ?? 'Outdoor lighting ordinance'}</h3>
                <p className="muted">
                  {o.date_passed && <>Adopted {o.date_passed}</>}
                  {o.date_effective && <> · effective {o.date_effective}</>}
                </p>
                {o.summary && <p>{o.summary}</p>}
                {o.legal_text_url && (
                  <a href={o.legal_text_url} target="_blank" rel="noreferrer noopener">
                    Read the ordinance text →
                  </a>
                )}
              </article>
            ))
          ) : (
            // A city with no ordinance is a finding, not a blank. Say what was
            // checked, or say plainly that nothing has been checked yet.
            <p className="muted">
              No ordinance on record for {city.name}.
            </p>
          )}

          {city.ordinance_notes && (
            <section className="assessment">
              <h3>{hasOrdinance ? 'What it does and does not cover' : 'What was found'}</h3>
              <p>{city.ordinance_notes}</p>
            </section>
          )}

          {/* The difference between "we looked and found nothing" and "nobody
              has looked" matters enormously on a public accountability map. */}
          <p className="review-status muted">
            {city.code_reviewed_at ? (
              <>
                Municipal code reviewed {city.code_reviewed_at}
                {city.code_review_source && (
                  <>
                    {' · '}
                    <a href={city.code_review_source} target="_blank" rel="noreferrer noopener">
                      source
                    </a>
                  </>
                )}
              </>
            ) : (
              <>
                <strong>Not yet reviewed.</strong> No ordinance found for {city.name},
                but its municipal code has not been read directly — absence of
                evidence, not evidence of absence.
              </>
            )}
          </p>

          <h2>Outreach presentation</h2>
          <SlidesEmbed url={city.slides_url} countyName={city.name} />
        </section>

        <aside>
          <h2>Documents</h2>
          <DocumentLinks documents={docs} />
          {!redline && (
            <p className="muted footnote">
              No redlined ordinance yet. A redline shows the exact amendments
              proposed against the city's current code, in the format a city
              clerk expects.
            </p>
          )}

          <h2>County context</h2>
          <p className="muted">
            {stageIndex(county.status) >= stageIndex('passed') ? (
              <>
                {county.name} County has its own ordinance
                {county.ordinance_title && <> — {county.ordinance_title}</>}, but it
                covers only unincorporated land. It does <strong>not</strong> apply
                inside {city.name}, which needs its own.
              </>
            ) : (
              <>
                {county.name} County has no ordinance of its own, so there is no
                county-level backstop for {city.name}.
              </>
            )}
          </p>
          {county.ordinance_url && (
            <p>
              <a href={county.ordinance_url} target="_blank" rel="noreferrer noopener">
                County ordinance →
              </a>
            </p>
          )}

          <p>
            <Link to={`/county/${county.slug}`}>
              All {county.name} County cities →
            </Link>
          </p>
        </aside>
      </div>
    </div>
  );
}
