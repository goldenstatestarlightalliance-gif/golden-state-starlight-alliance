import { useEffect, useMemo, useState } from 'react';
import { useParams, Link } from 'react-router-dom';
import { MapContainer, GeoJSON, CircleMarker, Tooltip, Pane } from 'react-leaflet';
import 'leaflet/dist/leaflet.css';

import { useCounty, useCountyTimeline, activeOrgs } from '../lib/queries';
import { STAGES, stageColor, stageLabel, stageIndex } from '../lib/pipeline';
import OrgList from '../components/OrgList';
import Legend from '../components/Legend';
import AutoFit from '../components/AutoFit';
import SlidesEmbed from '../components/SlidesEmbed';
import DocumentLinks from '../components/DocumentLinks';
import CountyEditor from '../components/CountyEditor';
import HatchDefs, { COUNTY_HATCH_ID } from '../components/HatchDefs';
import { useCanEditCounty } from '../lib/auth';

export default function CountyPage() {
  const { slug } = useParams();
  const { data: county, error, loading, reload } = useCounty(slug);
  const canEdit = useCanEditCounty(county);
  const { data: timeline } = useCountyTimeline(county?.id);
  const [places, setPlaces] = useState(null);
  const [outline, setOutline] = useState(null);
  const [darkSkyGeo, setDarkSkyGeo] = useState(null);
  const [unincorporated, setUnincorporated] = useState(null);

  // Optional layers. The ordinance hatch is off by default: it covers
  // everything outside the cities, which is legally right but visually loud
  // enough to bury the city outlines that are the point of the map.
  const [showOrdinance, setShowOrdinance] = useState(false);
  const [showDarkSky, setShowDarkSky] = useState(true);

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

  // Named unincorporated regions — everything in the county that is NOT in a
  // city, split into the areas people actually name (Ramona, Fallbrook,
  // Borrego Springs, Mountain Empire…). Built by subtracting the cities from
  // the Census subdivisions, so cities and regions tile the county exactly:
  // 15.3% + 84.7% = 100% for San Diego.
  //
  // Raw subdivisions were tried here first and were wrong — they cover the
  // whole county INCLUDING the cities, so a "San Diego" subdivision sat under
  // the city of San Diego and its outline read as a second, larger, incorrect
  // city boundary.
  useEffect(() => {
    if (!county?.fips) return;
    setUnincorporated(null);
    fetch(`${import.meta.env.BASE_URL}geo/unincorporated/${county.fips}.geojson`)
      .then((r) => (r.ok ? r.json() : null))
      .then((fc) => setUnincorporated(fc?.features?.length ? fc : null))
      .catch(() => setUnincorporated(null));
  }, [county?.fips]);

  // Certified dark sky places for THIS county. The file holds every certified
  // place in California, so it is filtered by the GEOIDs recorded against this
  // county in the database — that join is why place_geoid exists.
  const dsGeoids = (county?.dark_sky_places ?? [])
    .map((p) => p.place_geoid)
    .filter(Boolean)
    .join(',');

  useEffect(() => {
    if (!dsGeoids) { setDarkSkyGeo(null); return; }
    const wanted = new Set(dsGeoids.split(','));

    fetch(`${import.meta.env.BASE_URL}geo/ca-darksky-places.geojson`)
      .then((r) => (r.ok ? r.json() : null))
      .then((fc) => {
        if (!fc) return setDarkSkyGeo(null);
        const features = fc.features.filter((f) => wanted.has(f.properties.GEOID));
        setDarkSkyGeo(features.length ? { type: 'FeatureCollection', features } : null);
      })
      .catch(() => setDarkSkyGeo(null));
  }, [dsGeoids]);

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

  // Cities too small to see at county zoom also get a dot.
  //
  // Framing can only do so much: Bishop is a real town but it occupies about
  // 0.2% of Inyo County, and Susanville is similar in Lassen. Zooming in far
  // enough to see them throws away the county context that makes the map
  // legible. A marker sized in screen pixels stays visible at any zoom, so
  // rural counties stop looking like empty shapes.
  const smallCityMarkers = useMemo(() => {
    if (!places?.features?.length || !outline) return [];

    // Only sparse counties. This is about rescuing maps that read as EMPTY —
    // a county with one small town in a lot of open land. A dense county is
    // already legible: Los Angeles has 88 cities packed together, and an
    // area-share rule marked 82 of them "small" purely because LA's bounding
    // box is enormous (it reaches out to the Channel Islands). Dots there
    // would bury the map they were meant to clarify.
    const SPARSE_COUNTY_MAX = 3;
    if (places.features.length > SPARSE_COUNTY_MAX) return [];

    const area = (bbox) => (bbox[1][0] - bbox[0][0]) * (bbox[1][1] - bbox[0][1]);
    const countyArea = area(boundsOf(outline));
    if (!countyArea) return [];

    return places.features
      .map((f) => {
        const b = boundsOf({ features: [f] });
        return {
          name: f.properties.BASENAME,
          share: area(b) / countyArea,
          center: [(b[0][0] + b[1][0]) / 2, (b[0][1] + b[1][1]) / 2],
        };
      })
      // 0.1%, not 1%. At 1% the marker also landed on cities that are
      // perfectly visible — Mammoth Lakes is 0.79% of Mono County and renders
      // as a clear shape, so the dot sat on top of it looking like a stray
      // graphic. Bishop (0.04%) and Loyalton (0.03%) are the real cases.
      .filter((c) => c.share < 0.001);
  }, [places, outline]);

  // Every county page uses the same wide landscape frame.
  //
  // An earlier version matched the frame to each county's own proportions,
  // which packed each map tightly but meant no two county pages were the same
  // shape — the layout jumped as you moved between counties. A fixed 16:9 is
  // consistent and gives the map the full width of its column.
  //
  // The trade-off is real and unavoidable: a tall county (Los Angeles, Alpine)
  // sits centred with margins either side, because Leaflet fits the whole
  // county inside the frame rather than cropping it.
  const frameAspect = 16 / 9;

  if (loading) return <div className="page"><p className="muted">Loading…</p></div>;
  if (error) return <div className="page"><p className="error">Could not load this county: {error}</p></div>;
  if (!county) return <div className="page"><p className="error">County not found.</p></div>;

  const orgs = activeOrgs(county);
  // Whether the COUNTY government has its own ordinance — which in California
  // covers exactly the unincorporated land the subdivisions represent.
  const countyHasOrdinance = stageIndex(county.status) >= stageIndex('passed');
  const ordinances = county.ordinances ?? [];
  const cities = [...(county.cities ?? [])].sort(
    (a, b) => stageIndex(b.status) - stageIndex(a.status) || a.name.localeCompare(b.name)
  );

  const cityStyle = (feature) => {
    const city = cityByName.get(feature.properties.BASENAME?.toLowerCase());
    const status = city?.status ?? 'not_started';
    const started = status !== 'not_started';
    return {
      // Cities must read as distinct objects whatever their status. The
      // pipeline's "Not Started" grey is near-white, and so is the subdivision
      // background behind it, so an unstarted city vanished entirely — on Del
      // Norte that hid Crescent City, the county's only city. White fill plus a
      // dark outline makes cities read as islands on the county.
      fillColor: started ? stageColor(status) : '#ffffff',
      fillOpacity: 1,
      color: started ? '#ffffff' : '#475569',
      weight: started ? 1 : 1.2,
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
            // The sizing lives on the bordered box, not the map inside it.
            // With it on the map, the box stayed full column width while the
            // map shrank to its aspect ratio — so the "empty space" was the
            // container's own padding, not the map at all.
            <div
              className="map-wrap"
              style={{
                // Bigger than before: the height ceiling is the only cap, and
                // the box takes the full column when the county's shape allows.
                width: `min(100%, calc(82vh * ${frameAspect}))`,
                margin: '0 auto',
              }}
            >
              <MapContainer
                style={{
                  // Fills the box, which is already the right shape and size.
                  // aspectRatio (rather than height:100%) so the map has a
                  // definite height before Leaflet measures it — a percentage
                  // height inside an auto-height parent resolves to zero, which
                  // is the 0x0 container problem AutoFit exists to catch.
                  width: '100%',
                  aspectRatio: frameAspect,
                  background: '#ffffff',
                }}
                bounds={boundsOf(outline)}
                scrollWheelZoom={false}
                attributionControl={false}
                zoomSnap={0}
                zoomDelta={0.5}
              >
                <AutoFit bounds={boundsOf(outline)} />
                <HatchDefs />

                {/* The county backdrop — and it is INTERACTIVE, because it is
                    not empty space. Incorporated cities cover only about 15%
                    of San Diego County; the other 85% is unincorporated land
                    with no city government at all, run directly by the Board
                    of Supervisors. Hovering it says so, which is the honest
                    answer to "why is nothing here". Cities sit in a higher
                    pane and win every overlap. */}
                <GeoJSON
                  key={`outline-${county.fips}`}
                  data={outline}
                  interactive={false}
                  style={{
                    // Same cream as the unincorporated regions on purpose.
                    // Subtracting cities from subdivisions leaves hairline gaps
                    // where the two Census layers disagree, and a contrasting
                    // backdrop showed through them as white slivers along city
                    // edges. Matching the fill makes those gaps invisible
                    // instead of chasing sub-pixel geometry.
                    fillColor: '#fdf3d3',
                    fillOpacity: 1,
                    color: '#475569',
                    weight: 1.8,
                  }}
                />

                {/* Named unincorporated regions. Distinct from cities on
                    purpose — warm fill against the cities' status colours —
                    because they have no city government and can only be
                    reached by county-level policy. */}
                {unincorporated && (
                  <GeoJSON
                    key={`uninc-${county.fips}`}
                    data={unincorporated}
                    style={{
                      fillColor: '#fdf3d3',
                      fillOpacity: 1,
                      color: '#a8a29e',
                      weight: 0.9,
                    }}
                    onEachFeature={(feature, layer) => {
                      // Census subdivisions are often named after the town at
                      // their centre, so the leftover after removing that town
                      // inherits its name — Mono County's "Mammoth Lakes"
                      // region surrounds the incorporated town of Mammoth
                      // Lakes. Saying "Mammoth Lakes — unincorporated" next to
                      // an incorporated town is just wrong, so name it as the
                      // surrounding area when the collision exists.
                      const regionName = feature.properties.NAME;
                      const collides = cityByName.has(regionName?.toLowerCase());
                      const label = collides
                        ? `Around ${regionName}`
                        : regionName;

                      layer.bindTooltip(
                        `<strong>${label}</strong>` +
                          `<br>Unincorporated — no city government` +
                          `<br>${
                            countyHasOrdinance
                              ? 'Covered by the county ordinance'
                              : 'No county ordinance yet'
                          }`,
                        { sticky: true }
                      );
                      layer.on({
                        mouseover: (e) =>
                          e.target.setStyle({ fillColor: '#f7e6a8', weight: 1.6, color: '#78716c' }),
                        mouseout: (e) =>
                          e.target.setStyle({ fillColor: '#fdf3d3', weight: 0.9, color: '#a8a29e' }),
                      });
                    }}
                  />
                )}

                {/* Explicit panes fix the stacking order.
                    Leaflet appends each new layer on top of the pane, so
                    switching the ordinance layer on AFTER the cities had
                    rendered put the hatch over them and buried their
                    boundaries. Panes give each layer a fixed z-index, so the
                    order no longer depends on what was toggled when. */}
                {/* Hatched over the unincorporated regions specifically, not
                    the whole county — that is exactly the land a California
                    county ordinance governs. Cities are excluded by the
                    geometry itself rather than by drawing order. */}
                {countyHasOrdinance && showOrdinance && unincorporated && (
                  <Pane name="ordinance" style={{ zIndex: 410 }}>
                    <GeoJSON
                      key={`ord-${county.fips}`}
                      data={unincorporated}
                      interactive={false}
                      style={{
                        fillColor: `url(#${COUNTY_HATCH_ID})`,
                        fillOpacity: 1,
                        stroke: false,
                      }}
                    />
                  </Pane>
                )}

                {/* Certified dark sky places, when switched on. Unincorporated,
                    so they never overlap a city. */}
                {darkSkyGeo && showDarkSky && (
                  <Pane name="darksky" style={{ zIndex: 420 }}>
                    <GeoJSON
                      key={`ds-${county.fips}`}
                      data={darkSkyGeo}
                      style={{
                        fillColor: '#7c3aed',
                        fillOpacity: 0.55,
                        color: '#4c1d95',
                        weight: 1.5,
                      }}
                      onEachFeature={(feature, layer) => {
                        const p = feature.properties;
                        layer.bindTooltip(
                          `${p.BASENAME} — ${p.designation} (${p.designated_year})`,
                          { sticky: true }
                        );
                      }}
                    />
                  </Pane>
                )}

                {/* Cities in the highest pane, so their status colours and
                    boundaries sit above every optional layer. They are what
                    the map is for. */}
                {places && (
                  <Pane name="cities" style={{ zIndex: 430 }}>
                    <GeoJSON
                      key={`places-${county.fips}-${cities.length}`}
                      data={places}
                      style={cityStyle}
                      onEachFeature={onEachCity}
                    />
                  </Pane>
                )}

                {smallCityMarkers.map((c) => {
                  const city = cityByName.get(c.name?.toLowerCase());
                  const status = city?.status ?? 'not_started';
                  return (
                    <CircleMarker
                      key={`dot-${c.name}`}
                      center={c.center}
                      radius={5}
                      pathOptions={{
                        fillColor: stageColor(status),
                        fillOpacity: 1,
                        color: '#334155',
                        weight: 1.5,
                      }}
                    >
                      <Tooltip sticky>
                        {c.name} — {stageLabel(status)}
                      </Tooltip>
                    </CircleMarker>
                  );
                })}
              </MapContainer>

              {!places ? (
                // Alpine, Mariposa and Trinity have no incorporated cities at
                // all. Saying so beats an unexplained empty county shape.
                <p className="map-caption muted">
                  {county.name} County has no incorporated cities — lighting
                  policy here goes through the county Board of Supervisors.
                </p>
              ) : (
                // Names the shaded background so nobody reads it as missing
                // data. In most California counties the cities are a minority
                // of the land, and that surprises people.
                <p className="map-caption muted">
                  Coloured shapes are <strong>incorporated cities</strong>, each
                  with its own council. Cream regions are{' '}
                  <strong>unincorporated communities</strong> — no city
                  government, governed directly by the Board of Supervisors, and
                  reachable only by a county ordinance.
                </p>
              )}
            </div>
          ) : (
            <p className="muted">Loading map…</p>
          )}

          <Legend />

          {/* Optional layers, each with its own switch. Both sit over the
              cities' territory in different ways, so being able to clear them
              matters when reading city boundaries. */}
          {(countyHasOrdinance || darkSkyGeo) && (
            <div className="legend-extra">
              {countyHasOrdinance && (
                <label className="layer-toggle">
                  <input
                    type="checkbox"
                    checked={showOrdinance}
                    onChange={(e) => setShowOrdinance(e.target.checked)}
                  />
                  <span className="legend-swatch swatch-hatch" />
                  <span>County ordinance coverage</span>
                </label>
              )}
              {darkSkyGeo && (
                <label className="layer-toggle">
                  <input
                    type="checkbox"
                    checked={showDarkSky}
                    onChange={(e) => setShowDarkSky(e.target.checked)}
                  />
                  <span className="legend-swatch swatch-darksky" />
                  <span>Certified dark sky places</span>
                </label>
              )}
            </div>
          )}

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
