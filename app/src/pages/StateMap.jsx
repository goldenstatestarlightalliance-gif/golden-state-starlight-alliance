import { useEffect, useMemo, useRef, useState } from 'react';
import { useNavigate, Link } from 'react-router-dom';
import { MapContainer, GeoJSON, useMap } from 'react-leaflet';
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

// Publishes the Leaflet map instance upward so the hover card can convert a
// county's lat/lng into pixel coordinates inside the map container.
function MapRef({ onReady }) {
  const map = useMap();
  useEffect(() => { onReady(map); }, [map, onReady]);
  return null;
}

export default function StateMap() {
  const { data: counties, error, loading } = useCounties();
  const [geo, setGeo] = useState(null);
  const [geoError, setGeoError] = useState(null);
  const [hovered, setHovered] = useState(null);
  const [map, setMap] = useState(null);
  const navigate = useNavigate();

  const wrapRef = useRef(null);
  const cardRef = useRef(null);
  const closeTimer = useRef(null);

  useEffect(() => {
    fetch(`${import.meta.env.BASE_URL}geo/ca-counties.geojson`)
      .then((r) => {
        if (!r.ok) throw new Error(`Boundary data failed to load (HTTP ${r.status})`);
        return r.json();
      })
      .then(setGeo)
      .catch((e) => setGeoError(e.message));
  }, []);

  const cancelClose = () => {
    if (closeTimer.current) { clearTimeout(closeTimer.current); closeTimer.current = null; }
  };
  const scheduleClose = () => {
    cancelClose();
    closeTimer.current = setTimeout(() => setHovered(null), 300);
  };
  useEffect(() => cancelClose, []);

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
        cancelClose();
        setHovered({
          fips,
          name: county?.name ?? feature.properties.BASENAME,
          slug: target(),
          center: e.target.getBounds().getCenter(),
        });
      },
      mouseout: (e) => {
        // Recompute rather than hardcoding a colour back: the resting border
        // depends on coverage.
        e.target.setStyle(styleFor(feature));
        scheduleClose();
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

  // Position the hover card in the map wrapper's pixel space, clamped so it
  // can never spill outside.
  //
  // This replaces a Leaflet <Popup>. Leaflet renders popups INSIDE
  // .leaflet-container, which sets overflow:hidden — so a popup near the top
  // edge was cut off, and no amount of styling fixed it. Rendering the card as
  // a sibling of the map, positioned by hand, removes the clipping surface
  // entirely instead of fighting it.
  const cardPos = useMemo(() => {
    if (!hovered || !map || !wrapRef.current) return null;

    const wrap = wrapRef.current.getBoundingClientRect();
    const pt = map.latLngToContainerPoint(hovered.center);

    const CARD_W = 240;
    const CARD_H = cardRef.current?.offsetHeight ?? 150;
    const GAP = 14;
    const PAD = 8;

    // Prefer above the county; flip below when there is not room.
    let top = pt.y - CARD_H - GAP;
    let arrow = 'bottom';
    if (top < PAD) { top = pt.y + GAP; arrow = 'top'; }

    let left = pt.x - CARD_W / 2;
    left = Math.max(PAD, Math.min(left, wrap.width - CARD_W - PAD));
    top = Math.max(PAD, Math.min(top, wrap.height - CARD_H - PAD));

    return { left, top, width: CARD_W, arrow };
  }, [hovered, map]);

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
        <div className="map-wrap" ref={wrapRef}>
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
              <MapRef onReady={setMap} />
              <AutoFit bounds={CA_BOUNDS} />
              <GeoJSON
                key={geoKey}
                data={geo}
                style={styleFor}
                onEachFeature={onEachFeature}
              />
            </MapContainer>
          )}

          {hovered && cardPos && (
            <div
              ref={cardRef}
              className={`hover-pop hover-pop-${cardPos.arrow}`}
              style={{ left: cardPos.left, top: cardPos.top, width: cardPos.width }}
              onMouseEnter={cancelClose}
              onMouseLeave={scheduleClose}
            >
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
            </div>
          )}
        </div>

        <aside className="map-side">
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
