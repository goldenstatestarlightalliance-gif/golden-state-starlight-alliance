import { useEffect, useMemo, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { MapContainer, GeoJSON } from 'react-leaflet';
import 'leaflet/dist/leaflet.css';

import { useCounties, activeOrgs, NOT_CONFIGURED } from '../lib/queries';
import { stageColor, stageLabel } from '../lib/pipeline';
import Legend from '../components/Legend';
import AutoFit from '../components/AutoFit';

// Roughly the bounding box of California.
const CA_BOUNDS = [[32.3, -124.6], [42.1, -113.9]];

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
    for (const c of counties ?? []) out[c.status] = (out[c.status] ?? 0) + 1;
    return out;
  }, [counties]);

  const styleFor = (feature) => {
    const county = byFips.get(feature.properties.COUNTY);
    return {
      // Counties render neutral until a status says otherwise — colour is
      // applied by progress, never baked into the base map.
      fillColor: stageColor(county?.status ?? 'not_started'),
      fillOpacity: 1,
      color: '#ffffff',
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
        setHovered(fips);
      },
      mouseout: (e) => {
        e.target.setStyle({ weight: 1, color: '#ffffff' });
        setHovered(null);
      },
      click: () => county && navigate(`/county/${county.slug}`),
      keydown: (e) => {
        if (e.originalEvent.key === 'Enter' && county) navigate(`/county/${county.slug}`);
      },
    });

    const name = feature.properties.BASENAME;
    layer.bindTooltip(
      `${name} County — ${stageLabel(county?.status ?? 'not_started')}`,
      { sticky: true }
    );
  };

  // Leaflet caches the style closure per layer, so the GeoJSON layer has to be
  // remounted when county statuses arrive. The key does that.
  const geoKey = counties ? `loaded-${counties.length}` : 'pending';

  const hoveredCounty = hovered ? byFips.get(hovered) : null;

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
                  {activeOrgs(hoveredCounty).slice(0, 5).map((o) => (
                    <li key={o.id}>{o.name}</li>
                  ))}
                  {!activeOrgs(hoveredCounty).length && (
                    <li className="muted">None yet</li>
                  )}
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
