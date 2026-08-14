import { GeoJSON, Pane } from 'react-leaflet';

/**
 * The outline drawn around a searched-for county or city.
 *
 * Two strokes, not one. The fills underneath run from near-white ("no
 * ordinances yet") to dark green ("80-100%"), and no single stroke color is
 * legible against both — a gold line disappears on cream, a dark line
 * disappears on the deep greens. A dark casing under a gold line reads on
 * every fill in the coverage ramp.
 *
 * Both strokes are unfilled, so the coverage color it is marking stays
 * visible, and non-interactive, so the highlight never steals the hover or
 * click from the county underneath it.
 *
 * Lives in its own pane above every optional layer. Leaflet appends each new
 * layer to the top of its pane, which means without an explicit z-index the
 * stacking would depend on which toggles happened to be switched on.
 */
export const HIGHLIGHT_PANE_Z = 500;

export default function SearchHighlight({ feature, id, paneName = 'search-highlight' }) {
  if (!feature) return null;

  return (
    <Pane name={paneName} style={{ zIndex: HIGHLIGHT_PANE_Z }}>
      <GeoJSON
        key={`casing-${id}`}
        data={feature}
        interactive={false}
        style={{ color: '#0f172a', weight: 7, opacity: 0.45, fill: false }}
      />
      <GeoJSON
        key={`stroke-${id}`}
        data={feature}
        interactive={false}
        style={{ color: '#f59e0b', weight: 3.5, opacity: 1, fill: false }}
      />
    </Pane>
  );
}
