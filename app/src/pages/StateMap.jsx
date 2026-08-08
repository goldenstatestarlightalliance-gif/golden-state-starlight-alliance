import { useEffect, useMemo, useState } from 'react';
import { useNavigate, Link } from 'react-router-dom';
import { MapContainer, GeoJSON } from 'react-leaflet';
import 'leaflet/dist/leaflet.css';

import { useCounties, NOT_CONFIGURED } from '../lib/queries';
import { coverageFor, coverageColor, COVERAGE_BANDS } from '../lib/coverage';
import CoverageLegend from '../components/CoverageLegend';
import AutoFit from '../components/AutoFit';

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
  const navigate = useNavigate();

  useEffect(() => {
    fetch(`${import.meta.env.BASE_URL}geo/ca-counties.geojson`)
      .then((r) => {
        if (!r.ok) throw new Error(`Boundary data failed to load (HTTP ${r.status})`);
        return r.json();
      })
      .then(setGeo)
      .catch((e) => setGeoError(e.message));
  }, []);

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
        // Recompute rather than hardcoding a colour back: the resting border
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
              <GeoJSON
                key={geoKey}
                data={geo}
                style={styleFor}
                onEachFeature={onEachFeature}
              />
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
                      {hoveredCoverage.percent.toFixed(0)}% covered
                    </p>
                  </>
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
        </aside>
      </div>

      <p className="source-note">
        County boundaries: US Census Bureau TIGER/Line (public domain).{' '}
        {counties && `${counties.length} of 58 counties loaded.`}
      </p>
    </div>
  );
}
