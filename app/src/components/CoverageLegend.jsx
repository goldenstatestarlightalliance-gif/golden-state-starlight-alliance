import { COVERAGE_BANDS } from '../lib/coverage';

export default function CoverageLegend({ counts }) {
  return (
    <>
      <ul className="legend">
        {COVERAGE_BANDS.map((b) => (
          <li key={b.key}>
            <span className="legend-swatch" style={{ background: b.color }} />
            <span className="legend-label">{b.label}</span>
            {counts && <span className="legend-count">{counts[b.key] ?? 0}</span>}
          </li>
        ))}
      </ul>
      <p className="legend-note muted">
        Share of a county’s incorporated cities that have passed a dark sky
        ordinance.
      </p>
    </>
  );
}
