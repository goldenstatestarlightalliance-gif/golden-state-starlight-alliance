import { useState } from 'react';

// Initials fallback when an org has no logo, or its logo fails to load.
// Skips "of", "the" etc. so "Golden Gate Audubon Society" reads GGA, not GGAS
// after the filter — first three significant words.
function initials(name) {
  const skip = new Set(['of', 'the', 'and', 'for', 'at', 'in', '&']);
  return name
    .split(/\s+/)
    .filter((w) => w && !skip.has(w.toLowerCase()))
    .slice(0, 3)
    .map((w) => w[0].toUpperCase())
    .join('');
}

function OrgLogo({ org }) {
  // Logos are third-party URLs that can rot. Track failure per org so a dead
  // image degrades to initials instead of a broken-image icon.
  const [failed, setFailed] = useState(false);

  if (!org.logo_url || failed) {
    return (
      <span className="org-logo org-logo-fallback" aria-hidden="true">
        {initials(org.name)}
      </span>
    );
  }

  return (
    <img
      className="org-logo"
      src={org.logo_url}
      alt=""
      loading="lazy"
      onError={() => setFailed(true)}
      referrerPolicy="no-referrer"
    />
  );
}

const linkFor = (o) => {
  if (o.website) return o.website.startsWith('http') ? o.website : `https://${o.website}`;
  if (o.email) return `mailto:${o.email}`;
  return null;
};

/**
 * Org credit list. Every org is hyperlinked where we have a link (spec §4) —
 * the public accountability story depends on progress being attributable to a
 * real, reachable organization.
 *
 * `withLogos` switches between the compact text list used in map popups and
 * the fuller logo treatment used on county pages.
 */
export default function OrgList({
  orgs,
  empty = 'No organizations credited yet.',
  withLogos = false,
}) {
  if (!orgs?.length) return <p className="muted">{empty}</p>;

  if (!withLogos) {
    return (
      <ul className="org-list">
        {orgs.map((o) => {
          const href = linkFor(o);
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

  return (
    <ul className="org-cards">
      {orgs.map((o) => {
        const href = linkFor(o);
        const inner = (
          <>
            <OrgLogo org={o} />
            <span className="org-card-name">{o.name}</span>
          </>
        );

        return (
          <li key={o.id}>
            {href ? (
              <a className="org-card" href={href} target="_blank" rel="noreferrer noopener">
                {inner}
              </a>
            ) : (
              <span className="org-card">{inner}</span>
            )}
          </li>
        );
      })}
    </ul>
  );
}
