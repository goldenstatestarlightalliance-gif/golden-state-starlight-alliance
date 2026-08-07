// PLACEHOLDER — replace before launch.
//
// Deliberately not set to the founder's personal address: this is a public
// page, and publishing a personal inbox is a decision for the coalition, not a
// default. A role address (e.g. hello@ on the eventual domain) is the usual
// answer, since it survives people moving on — which matters for a group whose
// spec has a whole section on succession planning.
const CONTACT_EMAIL = null;

const ROLES = [
  {
    title: 'County Liaison',
    body: 'Own the relationship with one county — track its lighting agenda, attend the meetings that matter, and be the point of contact for that board or council.',
  },
  {
    title: 'Lead Researcher',
    body: 'Read ordinances. Track what neighbouring jurisdictions have adopted, and turn that into model language a council can actually use.',
  },
  {
    title: 'Outreach Coordinator',
    body: 'Build the relationships — local astronomy clubs, Audubon and Sierra Club chapters, and residents who care about the sky over their own street.',
  },
  {
    title: 'Communications Lead',
    body: 'Explain why this matters, in public comment, in writing, and to local press.',
  },
];

export default function Contact() {
  return (
    <div className="page">
      <header className="page-head">
        <h1>Get involved</h1>
        <p className="lede">
          This is volunteer-run. Dark sky ordinances pass because someone local
          showed up and asked for one — you do not need a policy background to
          be that person.
        </p>
      </header>

      <section>
        <h2>Ways to join</h2>
        <div className="join-grid">
          <article className="join-card">
            <h3>Through a partner organization</h3>
            <p>
              If you are already a member of a Sierra Club or Audubon chapter, a
              DarkSky International group, or a student or astronomy club, you
              can take part under that organization — and the progress your
              chapter drives is credited to it on the map.
            </p>
          </article>

          <article className="join-card">
            <h3>On your own</h3>
            <p>
              Not affiliated with any of those? Join the coalition's general
              membership. You get the same access to county coordination and
              public comment campaigns as members of any named partner.
            </p>
          </article>

          <article className="join-card">
            <h3>As an organization</h3>
            <p>
              Groups can join the coalition as partners, nominate a president,
              and take responsibility for one or more counties. Organizations
              are credited by name wherever they are active.
            </p>
          </article>
        </div>
      </section>

      <section>
        <h2>Roles volunteers take on</h2>
        <div className="role-grid">
          {ROLES.map((r) => (
            <article key={r.title} className="role">
              <h3>{r.title}</h3>
              <p>{r.body}</p>
            </article>
          ))}
        </div>
      </section>

      <section className="cta">
        <h2>Reach us</h2>
        {CONTACT_EMAIL ? (
          <p>
            Email <a href={`mailto:${CONTACT_EMAIL}`}>{CONTACT_EMAIL}</a> and
            tell us which county you are in — that is genuinely all we need to
            get started.
          </p>
        ) : (
          <p className="muted">
            A contact address will be published here once the coalition's domain
            is registered. In the meantime, reach out through any of the partner
            organizations credited on the{' '}
            <a href="/map">progress map</a>.
          </p>
        )}
      </section>
    </div>
  );
}
