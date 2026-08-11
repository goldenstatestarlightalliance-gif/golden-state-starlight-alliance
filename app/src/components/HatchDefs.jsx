import { useEffect } from 'react';
import { useMap } from 'react-leaflet';

export const COUNTY_HATCH_ID = 'county-ordinance-hatch';

/**
 * Injects an SVG <pattern> into Leaflet's overlay SVG so county polygons can be
 * filled with diagonal hatching.
 *
 * The hatch marks "this county government has passed its own ordinance". It has
 * to coexist with the coverage color rather than replace it: the fill answers
 * "how many of this county's cities are covered", the hatch answers "has the
 * county itself acted". Both matter, and in California they are genuinely
 * independent — a county ordinance covers only unincorporated land, so a
 * hatched county can still be 0% on cities.
 *
 * Hence a pattern with a transparent background: the coverage color shows
 * through the gaps, and the hatch reads as an annotation on top of it rather
 * than as a competing color.
 */
export default function HatchDefs() {
  const map = useMap();

  useEffect(() => {
    if (!map) return;

    const svg = map.getPanes().overlayPane.querySelector('svg');
    if (!svg || svg.querySelector(`#${COUNTY_HATCH_ID}`)) return;

    const svgNS = 'http://www.w3.org/2000/svg';
    const defs = document.createElementNS(svgNS, 'defs');
    const pattern = document.createElementNS(svgNS, 'pattern');

    pattern.setAttribute('id', COUNTY_HATCH_ID);
    pattern.setAttribute('patternUnits', 'userSpaceOnUse');
    pattern.setAttribute('width', '8');
    pattern.setAttribute('height', '8');
    pattern.setAttribute('patternTransform', 'rotate(45)');

    // Single stripe per tile: sparse enough to read the fill color underneath.
    const line = document.createElementNS(svgNS, 'line');
    line.setAttribute('x1', '0');
    line.setAttribute('y1', '0');
    line.setAttribute('x2', '0');
    line.setAttribute('y2', '8');
    line.setAttribute('stroke', '#1e293b');
    line.setAttribute('stroke-width', '2');
    line.setAttribute('stroke-opacity', '0.45');

    pattern.appendChild(line);
    defs.appendChild(pattern);
    svg.insertBefore(defs, svg.firstChild);
  }, [map]);

  return null;
}
