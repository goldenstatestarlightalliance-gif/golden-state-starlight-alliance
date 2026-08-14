import { useEffect, useMemo, useState } from 'react';
import { useNavigate, Link } from 'react-router-dom';
import { MapContainer, GeoJSON } from 'react-leaflet';
import 'leaflet/dist/leaflet.css';

import { useCounties, NOT_CONFIGURED } from '../lib/queries';
import { coverageFor, coverageColor, COVERAGE_BANDS } from '../lib/coverage';
import { stageIndex, stageLabel } from '../lib/pipeline';
import CoverageLegend from '../components/CoverageLegend';
import AutoFit from '../components/AutoFit';
import HatchDefs, { COUNTY_HATCH_ID } from '../components/HatchDefs';
import MapSearch from '../components/MapSearch';
import SearchHighlight from '../components/SearchHighlight';

// A county government has "acted" once its own ordinance is on the books.
const countyHasOrdinance = (c) => stageIndex(c?.status) >= stageIndex('passed');

// Roughly the bounding box of California.
const CA_BOUNDS = [[32.3, -124.6], [42.1, -113.9]];

// Mirrors the slug rule in scripts/generate-seed-sql.mjs, so a link built from
// a boundary feature lands on the same URL as one built from a database row.
const slugify = (s) =>
  s.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');

export default function StateMap() {
  const { data: counties, error, loading } = useCounties();
  const [geo, setGeo] = useState(null);
  const [geoError, setGeoError] = useState(null);
  const [hovered, setHovered] = useState(null);
  const [darkSkyGeo, setDarkSkyGeo] = useState(null);
  const [showDarkSky, setShowDarkSky] = useState(true);
  // Matches the county pages: the hatch is heavy enough to compete with the
  // coverage colors underneath, so it is opt-in rather than always on.
  const [showOrdinance, setShowOrdinance] = useState(false);
  // FIPS of the county picked in the search box, or null. Kept separate from
  // `hovered` so moving the mouse across the map cannot wipe out a deliberate
  // search — the two mark different intents and both stay on screen.
  const [searchFips, setSearchFips] = useState(null);
  const navigate = useNavigate();

  useEffect(() => {
    fetch(`${import.meta.env.BASE_URL}geo/ca-counties.geojson`)
      .then((r) => {
        if (!r.ok) throw new Error(`Boundary data failed to load (HTTP ${r.status})`);
        return r.json();
      })
      .then(setGeo)
      .catch((e) => setGeoError(e.message));

    // Certified dark sky communities. Small file (41 KB) and always loaded, so
    // toggling the layer is instant rather than triggering a fetch each time.
    fetch(`${import.meta.env.BASE_URL}geo/ca-darksky-places.geojson`)
      .then((r) => (r.ok ? r.json() : null))
      .then(setDarkSkyGeo)
      .catch(() => setDarkSkyGeo(null));
  }, []);

  // Counties whose own government has passed an ordinance — drawn as a hatch
  // layer on top of the coverage colors.
  const ordinanceGeo = useMemo(() => {
    if (!geo || !counties) return null;
    const acted = new Set(
      counties.filter(countyHasOrdinance).map((c) => c.fips)
    );
    if (!acted.size) return null;
    return {
      type: 'FeatureCollection',
      features: geo.features.filter((f) => acted.has(f.properties.COUNTY)),
    };
  }, [geo, counties]);

  // FIPS is the join key between the Census boundary features and our rows.
  const byFips = useMemo(() => {
    const m = new Map();
    for (const c of counties ?? []) m.set(c.fips, c);
    return m;
  }, [counties]);

  const counts = useMemo(() => {
    const out = {};
    for (const c of counties ?? []) {
      const { band } = coverageFor(c);
      out[band.key] = (out[band.key] ?? 0) + 1;
    }
    return out;
  }, [counties]);

  // Search list is built from the boundary features rather than the database
  // rows, so every shape on the map is reachable even if its row failed to
  // load. Falls back to the Census name when there is no matching row.
  const searchItems = useMemo(() => {
    if (!geo) return [];
    return geo.features
      .map((f) => ({
        key: f.properties.COUNTY,
        label: byFips.get(f.properties.COUNTY)?.name ?? f.properties.BASENAME,
      }))
      .sort((a, b) => a.label.localeCompare(b.label));
  }, [geo, byFips]);

  const searchFeature = useMemo(
    () => geo?.features.find((f) => f.properties.COUNTY === searchFips) ?? null,
    [geo, searchFips]
  );

  const styleFor = (feature) => {
    const county = byFips.get(feature.properties.COUNTY);
    const { percent } = coverageFor(county);
    const color = coverageColor(percent);
    return {
      fillColor: color,
      fillOpacity: 1,
      // A white border vanishes against the near-white "none yet" fill, which
      // is the state most of the map starts in.
      color: color === COVERAGE_BANDS[0].color ? '#cbd5e1' : '#ffffff',
      weight: 1,
    };
  };

  const onEachFeature = (feature, layer) => {
    const fips = feature.properties.COUNTY;
    const county = byFips.get(fips);
    const target = () => county?.slug ?? slugify(feature.properties.BASENAME);

    layer.on({
      mouseover: (e) => {
        e.target.setStyle({ weight: 2.5, color: '#111827' });
        e.target.bringToFront();
        setHovered({
          fips,
          name: county?.name ?? feature.properties.BASENAME,
          slug: target(),
        });
      },
      mouseout: (e) => {
        // Recompute rather than hardcoding a color back: the resting border
        // depends on coverage.
        e.target.setStyle(styleFor(feature));
        // Deliberately does NOT clear `hovered`. The panel keeps showing the
        // last county you looked at, so its link stays reachable — clearing it
        // would blank the panel the moment you moved toward the link.
      },
      click: () => navigate(`/county/${target()}`),
      keydown: (e) => {
        if (e.originalEvent.key === 'Enter') navigate(`/county/${target()}`);
      },
    });
  };

  // Leaflet caches the style closure per layer, so the GeoJSON layer has to be
  // remounted when county data arrives.
  const geoKey = counties ? `loaded-${counties.length}` : 'pending';

  const hoveredCounty = hovered ? byFips.get(hovered.fips) : null;
  const hoveredCoverage = coverageFor(hoveredCounty);

  return (
    <div className="page">
      <header className="page-head">
        <h1>California Dark Sky Policy Tracker</h1>
        <p className="lede">
          Counties are shaded by how many of their cities have passed a dark sky
          ordinance. Hover a county for detail, or select it to open its page.
        </p>
      </header>

      {error === NOT_CONFIGURED && <p className="notice">{error}</p>}
      {error && error !== NOT_CONFIGURED && (
        <p className="error">Could not load county data: {error}</p>
      )}
      {geoError && <p className="error">{geoError}</p>}

      <div className="map-layout">
        <div className="map-wrap">
          {geo && (
            <MapSearch
              items={searchItems}
              label="Search counties"
              placeholder="Search a county — try “Mono” or “San”"
              selectedKey={searchFips}
              onSelect={(item) => {
                setSearchFips(item?.key ?? null);
                // Drive the side panel too. Finding a county on the map is
                // only half of what someone searching for it wants; the other
                // half is its coverage figures and the link into its page.
                if (item) {
                  const county = byFips.get(item.key);
                  setHovered({
                    fips: item.key,
                    name: county?.name ?? item.label,
                    slug: county?.slug ?? slugify(item.label),
                  });
                }
              }}
            />
          )}

          {!geo && !geoError && <p className="muted">Loading map…</p>}
          {geo && (
            <MapContainer
              bounds={CA_BOUNDS}
              style={{ height: '70vh', width: '100%', background: '#ffffff' }}
              scrollWheelZoom={false}
              attributionControl={false}
              zoomSnap={0}
              zoomDelta={0.5}
            >
              <AutoFit bounds={CA_BOUNDS} />
              <HatchDefs />

              <GeoJSON
                key={geoKey}
                data={geo}
                style={styleFor}
                onEachFeature={onEachFeature}
              />

              {/* County-ordinance hatch. Drawn over the coverage colors but
                  non-interactive, so it annotates without stealing hover from
                  the counties underneath — city coverage stays the primary
                  reading of the map. */}
              {showOrdinance && ordinanceGeo && (
                <GeoJSON
                  key={`ord-${ordinanceGeo.features.length}`}
                  data={ordinanceGeo}
                  interactive={false}
                  style={{
                    fillColor: `url(#${COUNTY_HATCH_ID})`,
                    fillOpacity: 1,
                    color: '#1e293b',
                    weight: 1.5,
                    opacity: 0.55,
                  }}
                />
              )}

              {/* Certified dark sky communities — unincorporated, so they can
                  never appear in the city layer. */}
              {showDarkSky && darkSkyGeo && (
                <GeoJSON
                  key="darksky"
                  data={darkSkyGeo}
                  style={{
                    // Desaturated violet: dark sky places are a designation
                    // rather than a pipeline stage, so they keep a hue of their
                    // own — but toned down, so a certified place no longer
                    // outshouts a county that is 90% covered.
                    fillColor: '#6b5b95',
                    fillOpacity: 0.5,
                    color: '#4a3f6b',
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
              )}

              {/* Last, and in the highest pane, so a searched county reads
                  over the coverage fill, the ordinance hatch and the dark sky
                  layer alike. */}
              <SearchHighlight feature={searchFeature} id={searchFips} />
            </MapContainer>
          )}

        </div>

        <aside className="map-side">
          {/* Detail panel lives beside the map, never over it. An overlay card
              sat between the cursor and whatever county was behind it, so
              moving north out of Santa Clara hit the card instead of the next
              county. Off to the side, the map is never obstructed — and there
              is nothing left to clip at the edges either. */}
          <div className="detail-card">
            {hovered ? (
              <>
                <h3>{hovered.name} County</h3>

                {hoveredCoverage.totalCities === 0 ? (
                  <p className="hover-stat muted">No incorporated cities</p>
                ) : (
                  <>
                    <p className="hover-stat">
                      <strong>
                        {hoveredCoverage.withOrdinance}/{hoveredCoverage.totalCities}
                      </strong>{' '}
                      cities with an ordinance
                    </p>
                    <div className="hover-bar">
                      <span
                        style={{
                          width: `${hoveredCoverage.percent}%`,
                          background: hoveredCoverage.band.color,
                        }}
                      />
                    </div>
                    <p className="hover-pct muted">
                      {hoveredCoverage.percent.toFixed(0)}% of cities covered
                    </p>
                  </>
                )}

                {/* The county's own ordinance, kept visually distinct from the
                    city figure above so the two are never read as one number. */}
                {hoveredCounty && countyHasOrdinance(hoveredCounty) && (
                  <p className="county-ord-flag">
                    <span className="swatch-hatch inline-hatch" />
                    County ordinance: <strong>{stageLabel(hoveredCounty.status)}</strong>
                    <span className="muted"> — unincorporated areas</span>
                  </p>
                )}

                {hoveredCounty?.dark_sky_places?.length > 0 && (
                  <p className="darksky-flag">
                    ✦ {hoveredCounty.dark_sky_places.length} certified dark sky place
                    {hoveredCounty.dark_sky_places.length > 1 ? 's' : ''}
                  </p>
                )}

                <Link className="popup-link" to={`/county/${hovered.slug}`}>
                  Open {hovered.name} County →
                </Link>
              </>
            ) : (
              <p className="muted detail-empty">
                Hover a county to see its ordinance coverage. Select one to open
                its page.
              </p>
            )}
          </div>

          <h2>Ordinance coverage</h2>
          {loading ? <p className="muted">Loading…</p> : <CoverageLegend counts={counts} />}

          <h2>Other layers</h2>

          <label className="layer-toggle">
            <input
              type="checkbox"
              checked={showOrdinance}
              onChange={(e) => setShowOrdinance(e.target.checked)}
              disabled={!ordinanceGeo}
            />
            <span className="legend-swatch swatch-hatch" />
            <span>
              County ordinance passed
              {counties && (
                <span className="legend-count">
                  {' '}({counties.filter(countyHasOrdinance).length})
                </span>
              )}
            </span>
          </label>
          <p className="legend-note muted">
            A California county ordinance covers only the <strong>unincorporated</strong>{' '}
            area — it does not apply inside that county’s cities, so it is shown
            as hatching over the city-coverage color rather than replacing it.
          </p>

          <label className="layer-toggle">
            <input
              type="checkbox"
              checked={showDarkSky}
              onChange={(e) => setShowDarkSky(e.target.checked)}
              disabled={!darkSkyGeo}
            />
            <span className="legend-swatch swatch-darksky" />
            <span>Certified dark sky communities</span>
          </label>
          <p className="legend-note muted">
            Borrego Springs and Julian — DarkSky International certified. Both
            are unincorporated, so neither appears in the city figures.
          </p>
        </aside>
      </div>

      <p className="source-note">
        County boundaries: US Census Bureau TIGER/Line (public domain).{' '}
        {counties && `${counties.length} of 58 counties loaded.`}
      </p>
    </div>
  );
}
