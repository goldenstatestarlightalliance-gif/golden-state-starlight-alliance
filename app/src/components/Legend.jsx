import { STAGES } from '../lib/pipeline';

export default function Legend({ counts }) {
  return (
    <ul className="legend">
      {STAGES.map((s) => (
        <li key={s.key}>
          <span className="legend-swatch" style={{ background: s.color }} />
          <span className="legend-label">{s.label}</span>
          {counts && <span className="legend-count">{counts[s.key] ?? 0}</span>}
        </li>
      ))}
    </ul>
  );
}
