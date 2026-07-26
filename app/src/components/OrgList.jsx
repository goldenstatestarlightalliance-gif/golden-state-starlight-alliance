// Org credit list. Every org is hyperlinked where we have a link (spec §4) —
// the public accountability story depends on progress being attributable to a
// real, reachable organization.
export default function OrgList({ orgs, empty = 'No organizations credited yet.' }) {
  if (!orgs?.length) return <p className="muted">{empty}</p>;

  return (
    <ul className="org-list">
      {orgs.map((o) => {
        const href = o.website
          ? (o.website.startsWith('http') ? o.website : `https://${o.website}`)
          : o.email
            ? `mailto:${o.email}`
            : null;

        return (
          <li key={o.id}>
            {href ? (
              <a href={href} target="_blank" rel="noreferrer noopener">{o.name}</a>
            ) : (
              <span>{o.name}</span>
            )}
          </li>
        );
      })}
    </ul>
  );
}
