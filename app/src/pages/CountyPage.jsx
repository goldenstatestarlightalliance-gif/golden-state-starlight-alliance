import { useEffect, useMemo, useState } from 'react';
import { useParams, Link } from 'react-router-dom';
import { MapContainer, GeoJSON } from 'react-leaflet';
import 'leaflet/dist/leaflet.css';

import { useCounty, useCountyTimeline, activeOrgs } from '../lib/queries';
import { STAGES, stageColor, stageLabel, stageIndex } from '../lib/pipeline';
import OrgList from '../components/OrgList';
import Legend from '../components/Legend';
import AutoFit from '../components/AutoFit';
import SlidesEmbed from '../components/SlidesEmbed';
import DocumentLinks from '../components/DocumentLinks';
import CountyEditor from '../components/CountyEditor';
import { useCanEditCounty } from '../lib/auth';

export default function CountyPage() {
  const { slug } = useParams();
  const { data: county, error, loading, reload } = useCounty(slug);
  const canEdit = useCanEditCounty(county);
  const { data: timeline } = useCountyTimeline(county?.id);
  const [places, setPlaces] = useState(null);
  const [outline, setOutline] = useState(null);

  // Only this county's cities are fetched — the boundary build splits places
  // into one file per county so a page never downloads all 483.
  useEffect(() => {
    if (!county?.fips) return;
    setPlaces(null);
    fetch(`${import.meta.env.BASE_URL}geo/places/${county.fips}.geojson`)
      .then((r) => (r.ok ? r.json() : null))
      .then(setPlaces)
      .catch(() => setPlaces(null));
  }, [county?.fips]);

  // The county's own boundary, drawn underneath the cities.
  //
  // Without it, a rural county reads as broken: Lassen has exactly one
  // incorporated city (Susanville), whose limits are non-contiguous, so the
  // map showed a handful of disconnected fragments floating in white space
  // with nothing to locate them against. 13 counties have one city or none.
  useEffect(() => {
    if (!county?.fips) return;
    setOutline(null);
    fetch(`${import.meta.env.BASE_URL}geo/ca-counties.geojson`)
      .then((r) => (r.ok ? r.json() : null))
      .then((fc) => {
        if (!fc) return;
        const match = fc.features.find((f) => f.properties.COUNTY === county.fips);
        if (match) setOutline({ type: 'FeatureCollection', features: [match] });
      })
      .catch(() => setOutline(null));
  }, [county?.fips]);

  // Match Census place features to our city rows by name. place_fips is the
  // better key but is null until someone backfills it, so name is the fallback.
  const cityByName = useMemo(() => {
    const m = new Map();
    for (const c of county?.cities ?? []) m.set(c.name.toLowerCase(), c);
    return m;
  }, [county]);

  if (loading) return <div className="page"><p className="muted">Loading…</p></div>;
  if (error) return <div className="page"><p className="error">Could not load this county: {error}</p></div>;
  if (!county) return <div className="page"><p className="error">County not found.</p></div>;

  const orgs = activeOrgs(county);
  const ordinances = county.ordinances ?? [];
  const cities = [...(county.cities ?? [])].sort(
    (a, b) => stageIndex(b.status) - stageIndex(a.status) || a.name.localeCompare(b.name)
  );

  const cityStyle = (feature) => {
    const city = cityByName.get(feature.properties.BASENAME?.toLowerCase());
    const status = city?.status ?? 'not_started';
    return {
      fillColor: stageColor(status),
      fillOpacity: 1,
      // Same reasoning as the statewide map: a white border disappears against
      // the near-white "Not Started" fill.
      color: status === 'not_started' ? '#cbd5e1' : '#ffffff',
      weight: 1,
    };
  };

  const onEachCity = (feature, layer) => {
    const name = feature.properties.BASENAME;
    const city = cityByName.get(name?.toLowerCase());
    layer.bindTooltip(`${name} — ${stageLabel(city?.status ?? 'not_started')}`, { sticky: true });
  };

  return (
    <div className="page">
      <p className="crumb"><Link to="/">← Statewide map</Link></p>

      <header className="page-head">
        <h1>{county.name} County</h1>
        <p>
          <span className="pill" style={{ background: stageColor(county.status) }}>
            {stageLabel(county.status)}
          </span>
          {county.priority && <span className="tier">Priority tier {county.priority}</span>}
        </p>
        {county.hook && <p className="lede">{county.hook}</p>}
      </header>

      <div className="county-grid">
        <section>
          <h2>Cities</h2>
          {/* Frame on the county, not the cities. Fitting to the cities zoomed
              a one-city county in until its fragments filled the screen. */}
          {outline ? (
            <div className="map-wrap">
              <MapContainer
                style={{ height: '45vh', width: '100%', background: '#ffffff' }}
                bounds={boundsOf(outline)}
                scrollWheelZoom={false}
                attributionControl={false}
                zoomSnap={0}
                zoomDelta={0.5}
              >
                <AutoFit bounds={boundsOf(outline)} />

                {/* Drawn first so it sits beneath the cities. */}
                <GeoJSON
                  key={`outline-${county.fips}`}
                  data={outline}
                  interactive={false}
                  style={{
                    fillColor: '#f8fafc',
                    fillOpacity: 1,
                    color: '#94a3b8',
                    weight: 1.5,
                  }}
                />

                {places && (
                  <GeoJSON
                    key={`places-${county.fips}-${cities.length}`}
                    data={places}
                    style={cityStyle}
                    onEachFeature={onEachCity}
                  />
                )}
              </MapContainer>

              {!places && (
                // Alpine, Mariposa and Trinity have no incorporated cities at
                // all. Saying so beats an unexplained empty county shape.
                <p className="map-caption muted">
                  {county.name} County has no incorporated cities — lighting
                  policy here goes through the county Board of Supervisors.
                </p>
              )}
            </div>
          ) : (
            <p className="muted">Loading map…</p>
          )}

          <Legend />

          <h3>Progress by city</h3>
          {cities.length ? (
            <table className="pipeline-table">
              <thead>
                <tr><th>City</th><th>Stage</th><th>Progress</th></tr>
              </thead>
              <tbody>
                {cities.map((c) => (
                  <tr key={c.id}>
                    <td>
                      {c.name}
                      {c.is_priority && <span className="star" title="Priority outreach target">★</span>}
                    </td>
                    <td>{stageLabel(c.status)}</td>
                    <td>
                      <div className="bar">
                        {STAGES.map((s, i) => (
                          <span
                            key={s.key}
                            className="bar-seg"
                            style={{
                              background: i <= stageIndex(c.status) ? s.color : '#f4f4f5',
                            }}
                          />
                        ))}
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          ) : (
            <p className="muted">No cities tracked yet for this county.</p>
          )}

          <h2>Outreach presentation</h2>
          <SlidesEmbed url={county.slides_url} countyName={county.name} />

          {canEdit && <CountyEditor county={county} onSaved={reload} />}
        </section>

        <aside>
          {/* The county government's own ordinance. Separated from the city
              list because in California it covers only unincorporated land —
              conflating the two would overstate coverage. */}
          {stageIndex(county.status) >= stageIndex('passed') && (
            <section className="county-ordinance">
              <h2>County ordinance</h2>
              <p>
                <span className="pill" style={{ background: stageColor(county.status) }}>
                  {stageLabel(county.status)}
                </span>
                <span className="muted"> — unincorporated areas only</span>
              </p>
              {county.ordinance_title && <h3>{county.ordinance_title}</h3>}
              {county.ordinance_date_passed && (
                <p className="muted">Passed {county.ordinance_date_passed}</p>
              )}
              {county.ordinance_summary && <p>{county.ordinance_summary}</p>}
              {county.ordinance_url && (
                <a href={county.ordinance_url} target="_blank" rel="noreferrer noopener">
                  Read the county ordinance →
                </a>
              )}
              <p className="muted footnote">
                A California county ordinance applies only outside city limits.
                The cities listed here each need their own.
              </p>
            </section>
          )}

          {county.dark_sky_places?.length > 0 && (
            <>
              <h2>Certified dark sky places</h2>
              <ul className="darksky-list">
                {county.dark_sky_places.map((p) => (
                  <li key={p.id}>
                    <span className="darksky-dot" aria-hidden="true">✦</span>
                    <span>
                      {p.source_url ? (
                        <a href={p.source_url} target="_blank" rel="noreferrer noopener">
                          {p.name}
                        </a>
                      ) : p.name}
                      <br />
                      <span className="muted">
                        {p.designation}
                        {p.designated_year ? ` · ${p.designated_year}` : ''}
                      </span>
                    </span>
                  </li>
                ))}
              </ul>
              <p className="muted footnote">
                These are unincorporated communities and parks, so they are not
                counted in the city figures above.
              </p>
            </>
          )}

          <h2>Documents</h2>
          <DocumentLinks documents={county.county_documents} />

          <h2>Ordinances</h2>
          {ordinances.length ? (
            ordinances.map((o) => (
              <article key={o.id} className="ordinance">
                <h3>{o.title ?? 'Outdoor lighting ordinance'}</h3>
                {o.date_passed && <p className="muted">Passed {o.date_passed}</p>}
                {o.summary && <p>{o.summary}</p>}
                {o.legal_text_url && (
                  <a href={o.legal_text_url} target="_blank" rel="noreferrer noopener">
                    Read the ordinance text →
                  </a>
                )}
              </article>
            ))
          ) : (
            <p className="muted">No ordinance on record yet.</p>
          )}

          <h2>Credited organizations</h2>
          <OrgList orgs={orgs} withLogos />

          <h2>Timeline</h2>
          {timeline?.length ? (
            <ol className="timeline">
              {timeline.map((e) => (
                <li key={e.id}>
                  <time>{new Date(e.created_at).toLocaleDateString()}</time>
                  <span>{e.description ?? e.action}</span>
                </li>
              ))}
            </ol>
          ) : (
            <p className="muted">No recorded updates yet.</p>
          )}

          {county.rationale && (
            <>
              <h2>Why this county</h2>
              <p className="muted">{county.rationale}</p>
            </>
          )}
        </aside>
      </div>
    </div>
  );
}

// Bounding box of a FeatureCollection, as Leaflet [[s,w],[n,e]].
function boundsOf(geojson) {
  let minX = 180, minY = 90, maxX = -180, maxY = -90;
  const walk = (c) => {
    if (typeof c[0] === 'number') {
      minX = Math.min(minX, c[0]); maxX = Math.max(maxX, c[0]);
      minY = Math.min(minY, c[1]); maxY = Math.max(maxY, c[1]);
    } else c.forEach(walk);
  };
  for (const f of geojson.features) if (f.geometry?.coordinates) walk(f.geometry.coordinates);
  return [[minY, minX], [maxY, maxX]];
}
