import { Link } from 'react-router-dom';
import Glossary from '../components/Glossary';

// The joint model ordinance, as adopted numbers rather than prose.
//
// PROVENANCE MATTERS HERE. This model merges two sources, and one of them is
// somebody else's intellectual property — that is stated on the page rather
// than buried, because the page is public and the orgs involved are the same
// ones GSSA asks to partner.
const ZONES = [
  { z: 'LZ0', desc: 'No ambient light — wilderness, observatory cores', budget: '2,500', cct: '2,700K' },
  { z: 'LZ1', desc: 'Dark — rural, parks, natural areas', budget: '5,000', cct: '2,700K' },
  { z: 'LZ2', desc: 'Low — residential neighborhoods', budget: '12,000', cct: '3,000K' },
  { z: 'LZ3', desc: 'Moderate — commercial districts', budget: '25,000', cct: '3,000K' },
  { z: 'LZ4', desc: 'High — city centers, dense commercial', budget: '50,000', cct: '3,000K' },
];

const PROVISIONS = [
  {
    t: 'Shielding',
    v: 'All fixtures fully shielded',
    d: 'U0 / G2 maximum above 1,000 lumens. Identical in every zone — a zone governs how much light, never how badly it is aimed.',
  },
  {
    t: 'Color temperature',
    v: '3,000K general · 2,700K sensitive',
    d: '2,700K in LZ0/LZ1, observatory areas, streetlights and string lights. 5,700K permitted for sports only.',
  },
  {
    t: 'Residential fixture cap',
    v: '1,000 lumens',
    d: 'Security lighting may reach 1,600 lumens under §6.1(e).',
  },
  {
    t: 'Light trespass',
    v: '0.01 / 0.1 / 0.5 fc',
    d: '0.01 fc wilderness and protected areas · 0.1 fc residential and Waters of the US · 0.5 fc public right of way. Measured at the receiving property line, nearest point to the source — the limit scales by what receives the light, not by the zone emitting it.',
  },
  {
    t: 'Curfew',
    v: '11:00 p.m.',
    d: 'Or a motion sensor with a five-minute shutoff.',
  },
  {
    t: 'Amortization',
    v: '5 years',
    d: 'Non-compliant lighting stays off after the deadline. 90-day immediate measures: re-aim anything adjustable, dim anything above 3,000K. Hardship extension capped at one year.',
  },
  {
    t: 'CUP trigger',
    v: '20,000 / 160,000 lumens',
    d: 'A single fixture above 20,000 lumens, or a site above 160,000, requires a conditional use permit.',
  },
  {
    t: 'Sports lighting',
    v: 'Class IV play ceiling',
    d: 'Per ANSI/IES RP-6, with 85% containment, 10,000 candela at 46 m and an 80 ft mounting maximum.',
  },
  {
    t: 'Sign lighting',
    v: '50 nits · 50 sq ft',
    d: 'The San Diego redline instead uses the County’s 100 cd/m² and 200 sq ft, because matching an adopted local standard is easier to defend than importing a stricter one.',
  },
  {
    t: 'Streetlights',
    v: '2,700K · 10,000 lumen max',
    d: 'Plus a written necessity finding and adaptive controls.',
  },
];

export default function ModelOrdinance() {
  return (
    <div className="page">
      <header className="page-head">
        <h1>The joint model ordinance</h1>
        <p className="lede">
          Eight sections, refined across seven review passes with 29 logged
          drafting fixes. This is the starting text every city redline is built
          from — cities are asked to amend their own code toward it, not to adopt
          it wholesale.
        </p>
      </header>

      {/* Provenance first. The page is public and one source is a partner's IP. */}
      <div className="callout callout-warn">
        <strong>Provenance.</strong> This model merges DarkSky International’s
        2026 U.S. Municipal Code for Outdoor Lighting v1.1 with the SCVBA /
        Sierra Club Loma Prieta Model Lighting Ordinance (May 2025). The Loma
        Prieta model is those organizations’ own work.{' '}
        <strong>Ask before circulating derivatives.</strong>
      </div>

      <section className="guide-section">
        <h2>What each source contributes</h2>
        <div className="guide-split">
          <article className="guide-card">
            <h3>DarkSky International 2026</h3>
            <p className="source-strong">
              <strong>Strong:</strong> BUG ratings, Lighting Zones, per-acre lumen
              budgets, a real enforcement chapter.
            </p>
            <p className="source-weak">
              <strong>Weak:</strong> leaves existing fixtures legal indefinitely.
              Nothing on string lights, interior spill or canopies. Sign standards
              sold separately as a paid module.
            </p>
          </article>

          <article className="guide-card">
            <h3>SCVBA / Sierra Club Loma Prieta</h3>
            <p className="source-strong">
              <strong>Strong:</strong> the best amortization clause anywhere —
              five years plus 90-day immediate measures and a bounded hardship
              extension. Covers security lighting, string lights, canopies, signs
              and interior spill. Written for California.
            </p>
            <p className="source-weak">
              <strong>Weak:</strong> no enforcement provisions at all, no BUG
              ratings, and real drafting defects — a streetlight contradiction
              between §2.1.4 and §6, a double negative at §4.2.1.4, a clause
              reading only “Height?”, and a citation to the superseded RP-6-20.
            </p>
          </article>
        </div>
        <p className="muted">
          The merge takes DarkSky’s enforcement and zone structure and Loma
          Prieta’s amortization and coverage, then fixes the drafting defects.
          Standards editions verified August 2026: RP-43-25, TM-15-20, RP-6-24.
        </p>
      </section>

      <section className="guide-section">
        <h2>Core provisions</h2>
        <table className="provision-table">
          <thead>
            <tr><th>Provision</th><th>Value</th><th>Detail</th></tr>
          </thead>
          <tbody>
            {PROVISIONS.map((p) => (
              <tr key={p.t}>
                <td><strong>{p.t}</strong></td>
                <td className="provision-value">{p.v}</td>
                <td className="muted">{p.d}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </section>

      <section className="guide-section">
        <h2>Lighting zones</h2>
        <p className="lede">
          Zones govern <strong>how much</strong> light, not how well it is aimed.
          Shielding and uplight limits are identical in every zone by design.
        </p>

        <table className="provision-table">
          <thead>
            <tr>
              <th>Zone</th><th>Character</th>
              <th>Lumens per acre</th><th>Max CCT</th>
            </tr>
          </thead>
          <tbody>
            {ZONES.map((z) => (
              <tr key={z.z}>
                <td><strong>{z.z}</strong></td>
                <td className="muted">{z.desc}</td>
                <td className="provision-value">{z.budget}</td>
                <td className="provision-value">{z.cct}</td>
              </tr>
            ))}
          </tbody>
        </table>

        <div className="callout callout-warn">
          <strong>The per-acre lumen budgets are uncalibrated placeholders.</strong>{' '}
          They have not been tested against real site data and should be flagged
          as provisional in any submission. Color temperature has two tiers,
          trespass scales by receiving area, and only the lumen budget varies
          across all five zones.
        </div>
      </section>

      <Glossary />

      <section className="guide-section">
        <h2>Status</h2>
        <ul className="status-list">
          <li className="status-open">
            <strong>Not yet reviewed by an attorney.</strong> Required before any
            formal submission to a city.
          </li>
          <li className="status-open">
            Federal exemptions (FAA, Coast Guard, DOT, OSHA) still to be added —
            they fell out during a rebuild and matter for a harbour city.
          </li>
          <li className="status-open">
            Enforcement authority for San Diego’s §142.0740 is unresolved. The
            section carries no penalty provision, and where enforcement lives in
            the wider Code is the first question for the City Attorney.
          </li>
        </ul>
      </section>

      <section className="cta">
        <h2>How it gets used</h2>
        <p>
          GSSA supplies research and support — ordinance analysis, redline
          language, comparable-jurisdiction precedents, calendar and election
          tracking, coalition coordination. Local organizations lead their own
          campaigns.
        </p>
        <Link className="btn btn-primary" to="/guide">
          How the process works
        </Link>
      </section>
    </div>
  );
}
