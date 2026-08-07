import { useEffect, useMemo, useRef, useState } from 'react';
import { useNavigate, Link } from 'react-router-dom';
import { MapContainer, GeoJSON, Popup } from 'react-leaflet';
import 'leaflet/dist/leaflet.css';

import { useCounties, activeOrgs, NOT_CONFIGURED } from '../lib/queries';
import { stageColor, stageLabel } from '../lib/pipeline';
import Legend from '../components/Legend';
import AutoFit from '../components/AutoFit';
import OrgList from '../components/OrgList';

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
  const [popupAt, setPopupAt] = useState(null);
  const navigate = useNavigate();

  // The popup has to survive the pointer leaving the county polygon, otherwise
  // its links are unreachable — the moment you move toward them, mouseout
  // fires and the popup closes. A short close delay bridges that gap, and
  // hovering the popup itself cancels the pending close.
  const closeTimer = useRef(null);

  const cancelClose = () => {
    if (closeTimer.current) {
      clearTimeout(closeTimer.current);
      closeTimer.current = null;
    }
  };

  // Carries the Census feature's own name so the popup still works for a county
  // that has no database row yet — before seeding, or if a row is ever missing.
  // The map is the public face of the project; it should degrade to "we know
  // this county exists and nothing has happened here", never to nothing at all.
  const openPopup = (fips, name, latlng) => {
    cancelClose();
    setHovered({ fips, name });
    setPopupAt(latlng);
  };

  const scheduleClose = () => {
    cancelClose();
    closeTimer.current = setTimeout(() => {
      setHovered(null);
      setPopupAt(null);
    }, 300);
  };

  // Don't leave a timer running against an unmounted component.
  useEffect(() => cancelClose, []);

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
    for (const c of counties ?? []) out[c.status] = (out[c.status] ?? 0) + 1;
    return out;
  }, [counties]);

  const styleFor = (feature) => {
    const county = byFips.get(feature.properties.COUNTY);
    const status = county?.status ?? 'not_started';
    return {
      // Counties render neutral until a status says otherwise — colour is
      // applied by progress, never baked into the base map.
      fillColor: stageColor(status),
      fillOpacity: 1,
      // Border colour adapts to the fill. A white border on the near-white
      // "Not Started" fill is invisible, which is the state the whole map
      // starts in — so unstarted counties get a grey outline, and coloured
      // ones keep white, which reads as a cleaner separator against saturated
      // fills.
      color: status === 'not_started' ? '#cbd5e1' : '#ffffff',
      weight: 1,
    };
  };

  // Bind handlers per feature. Keyboard support matters here: this map is the
  // primary navigation for the whole public site, so it cannot be mouse-only.
  const onEachFeature = (feature, layer) => {
    const fips = feature.properties.COUNTY;
    const county = byFips.get(fips);

    layer.on({
      mouseover: (e) => {
        e.target.setStyle({ weight: 2.5, color: '#111827' });
        e.target.bringToFront();
        openPopup(fips, feature.properties.BASENAME, e.target.getBounds().getCenter());
      },
      mouseout: (e) => {
        // Recompute rather than hardcoding a colour back: the resting border
        // depends on the county's status, so a fixed value would leave every
        // hovered county with the wrong outline for the rest of the session.
        e.target.setStyle(styleFor(feature));
        // Delayed, so the pointer can travel from the county into the popup
        // without it vanishing en route.
        scheduleClose();
      },
      click: () => county && navigate(`/county/${county.slug}`),
      keydown: (e) => {
        if (e.originalEvent.key === 'Enter' && county) navigate(`/county/${county.slug}`);
      },
    });

    // No bindTooltip here: a Leaflet tooltip cannot hold a link, and showing
    // one alongside the popup would just duplicate the same text. The popup
    // below carries the name, status, orgs and the through-link.
  };

  // Leaflet caches the style closure per layer, so the GeoJSON layer has to be
  // remounted when county statuses arrive. The key does that.
  const geoKey = counties ? `loaded-${counties.length}` : 'pending';

  // Prefer the database row; fall back to the boundary feature so the popup
  // never blanks out just because a county has not been seeded.
  const row = hovered ? byFips.get(hovered.fips) : null;
  const hoveredCounty = hovered
    ? {
        name: row?.name ?? hovered.name,
        status: row?.status ?? 'not_started',
        slug: row?.slug ?? slugify(hovered.name),
        orgs: row ? activeOrgs(row) : [],
      }
    : null;

  return (
    <div className="page">
      <header className="page-head">
        <h1>California Dark Sky Policy Tracker</h1>
        <p className="lede">
          Tracking outdoor lighting ordinances across all 58 California counties.
          Hover a county for detail, or select it to open its full page.
        </p>
      </header>

      {/* A missing .env is an expected setup state, not a failure — the map is
          still fully usable as geography, so it reads as a notice, not an error. */}
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
              /* Leaflet snaps to whole zoom levels by default, so fitBounds
                 rounds *down* and California ends up filling under half the
                 available height. Fractional zoom lets it fill the frame. */
              zoomSnap={0}
              zoomDelta={0.5}
            >
              <AutoFit bounds={CA_BOUNDS} />
              {/* No basemap tiles on purpose: the tracker is about the
                  choropleth, and a tile layer would fight the status colours
                  and add an external dependency to the flagship page. */}
              <GeoJSON
                key={geoKey}
                data={geo}
                style={styleFor}
                onEachFeature={onEachFeature}
              />

              {hoveredCounty && popupAt && (
                <Popup
                  position={popupAt}
                  closeButton={false}
                  autoPan={false}
                  className="county-popup"
                >
                  {/* Handlers go on the content, not on <Popup eventHandlers>:
                      that binds Leaflet *layer* events (add/remove/open/close),
                      which never fire for a pointer entering the popup box. The
                      popup would close out from under the links. */}
                  <div
                    onMouseEnter={cancelClose}
                    onMouseLeave={scheduleClose}
                  >
                    <h3>{hoveredCounty.name} County</h3>

                    <p className="popup-status">
                      <span
                        className="pill"
                        style={{ background: stageColor(hoveredCounty.status) }}
                      >
                        {stageLabel(hoveredCounty.status)}
                      </span>
                    </p>

                    <h4>Participating organizations</h4>
                    <OrgList orgs={hoveredCounty.orgs} empty="None yet." />

                    <Link className="popup-link" to={`/county/${hoveredCounty.slug}`}>
                      Open {hoveredCounty.name} County →
                    </Link>
                  </div>
                </Popup>
              )}
            </MapContainer>
          )}
        </div>

        <aside className="map-side">
          <h2>Progress</h2>
          {loading ? (
            <p className="muted">Loading…</p>
          ) : (
            <Legend counts={counts} />
          )}

          <div className="hover-card">
            {hoveredCounty ? (
              <>
                <h3>{hoveredCounty.name} County</h3>
                <p>
                  <span
                    className="pill"
                    style={{ background: stageColor(hoveredCounty.status) }}
                  >
                    {stageLabel(hoveredCounty.status)}
                  </span>
                </p>
                <h4>Participating organizations</h4>
                <ul className="org-list">
                  {hoveredCounty.orgs.slice(0, 5).map((o) => (
                    <li key={o.id}>{o.name}</li>
                  ))}
                  {!hoveredCounty.orgs.length && <li className="muted">None yet</li>}
                </ul>
                <button onClick={() => navigate(`/county/${hoveredCounty.slug}`)}>
                  Open {hoveredCounty.name} County →
                </button>
              </>
            ) : (
              <p className="muted">Hover a county to see its status and partners.</p>
            )}
          </div>
        </aside>
      </div>

      <p className="source-note">
        County boundaries: US Census Bureau TIGER/Line (public domain).{' '}
        {counties && `${counties.length} of 58 counties loaded.`}
      </p>
    </div>
  );
}
