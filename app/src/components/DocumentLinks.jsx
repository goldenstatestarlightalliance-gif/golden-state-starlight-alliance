// Default labels and display order for the named document kinds. 'other'
// documents carry their own label and sort after these.
const KINDS = {
  current_ordinance: { label: 'Current ordinance', icon: '📄', order: 0 },
  redlined_ordinance: { label: 'Redlined ordinance', icon: '✏️', order: 1 },
  other: { label: null, icon: '🔗', order: 2 },
};

const meta = (kind) => KINDS[kind] ?? KINDS.other;

export default function DocumentLinks({ documents }) {
  if (!documents?.length) {
    return <p className="muted">No documents linked for this county yet.</p>;
  }

  const sorted = [...documents].sort(
    (a, b) =>
      meta(a.kind).order - meta(b.kind).order ||
      a.sort_order - b.sort_order ||
      a.id - b.id
  );

  return (
    <ul className="doc-links">
      {sorted.map((d) => (
        <li key={d.id}>
          <a href={d.url} target="_blank" rel="noreferrer noopener">
            <span className="doc-icon" aria-hidden="true">{meta(d.kind).icon}</span>
            <span>{d.label ?? meta(d.kind).label}</span>
          </a>
        </li>
      ))}
    </ul>
  );
}
