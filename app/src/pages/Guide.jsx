import { Link } from 'react-router-dom';
import { STAGES } from '../lib/pipeline';
import { COVERAGE_BANDS } from '../lib/coverage';

// The 30-step advocacy process, grouped into its seven phases.
//
// The phases with NO public meeting attached — 0, 2, 3 and 7 — are where
// campaigns are actually won, and they are exactly what volunteer efforts skip
// because nothing forces a date. That is called out visually rather than left
// as a footnote.
const PHASES = [
  {
    n: 0,
    title: 'Preparation',
    meeting: false,
    steps: [
      'Decide one exact ask — not "better lighting", a specific code section',
      'Source every number you will cite',
      'Recruit 3–5 partner organizations before going public',
      'Write the objections sheet before opponents write it for you',
      'Identify a sponsor on the council',
    ],
  },
  {
    n: 1,
    title: 'Authorization',
    meeting: true,
    steps: [
      'Get a council referral',
      'Or attach to a vehicle already moving through the process',
      'Confirm who can open a code amendment docket',
    ],
  },
  {
    n: 2,
    title: 'Drafting',
    meeting: false,
    steps: [
      'Reach staff first, with a finished redline in hand',
      'Hand over the leverage arguments so staff can use them internally',
      'Public Review Draft comment window',
      'Expect legal review to reshape vague language',
    ],
  },
  {
    n: 3,
    title: 'Pre-hearing',
    meeting: false,
    steps: [
      'Individual meetings with each commissioner',
      'The same with councilmembers',
      'Coalition sign-on letter',
      'Press',
      'A public event',
    ],
  },
  {
    n: 4,
    title: 'Planning Commission',
    meeting: true,
    steps: [
      'Read the staff report the moment it posts',
      'Coordinate speakers so testimony does not repeat',
      'Know the full range of possible outcomes in advance',
      'A continuance is not a defeat',
    ],
  },
  {
    n: 5,
    title: 'Council',
    meeting: true,
    steps: [
      'Repeat the relationship work — commissioners are not councilmembers',
      'Two readings',
      'CEQA determination',
      'Know the outcome range',
    ],
  },
  {
    n: 6,
    title: 'Effective date',
    meeting: false,
    steps: ['Roughly 30 days after adoption', 'Check for a state review layer'],
  },
  {
    n: 7,
    title: 'After adoption',
    meeting: false,
    steps: [
      'Request enforcement data',
      'Watch for erosion through variances and amendments',
      'Keep the coalition alive for the next fight',
    ],
  },
];

const REDLINE_STEPS = [
  {
    t: 'Get the current code from the city itself',
    d: 'Go to the city’s own municipal code library page. Municode has gaps, CodePublishing is hard to navigate, and AmLegal will not filter by city. Getting this wrong means redlining text that is not in force.',
  },
  {
    t: 'Read it for what is missing, not what is wrong',
    d: 'Most California cities have some lighting language. The gaps are usually the same ones: a shielding threshold set too high, no color temperature cap, sports and signs exempted, the city exempting its own streetlights, and no amortization — so existing fixtures stay legal forever.',
  },
  {
    t: 'Amend rather than replace',
    d: 'A council will approve an amendment to a code it already owns far more readily than a new ordinance. Amending also keeps the existing enforcement and permit machinery, which a fresh ordinance would have to rebuild.',
  },
  {
    t: 'Write it in the city’s own house format',
    d: 'San Diego publishes strikeout ordinances with a specific header block, all-caps caption, Times New Roman, and “[No change in text.]” placeholders instead of reproducing unchanged provisions. Matching the format removes an objection before it is raised.',
  },
  {
    t: 'Sort the amendments by difficulty',
    d: 'Separate the one-word fixes from the contested ones. A package that opens with five cheap corrections builds credibility for the amortization clause later.',
  },
  {
    t: 'Source every change',
    d: 'Each amendment should carry a comparable jurisdiction that already adopted it. A City Attorney can verify an adopted California ordinance; they cannot verify a preference.',
  },
];

export default function Guide() {
  return (
    <div className="page">
      <header className="page-head">
        <h1>How this works</h1>
        <p className="lede">
          What the colors mean, why a county ordinance is not a city ordinance,
          how a redline is put together, and the thirty steps between an idea and
          an adopted rule.
        </p>
      </header>

      {/* ---------------------------------------------------------------- */}
      <section className="guide-section">
        <h2>The six stages</h2>
        <p className="lede">
          Every city moves through the same pipeline. The stage is the furthest
          point reached, not the current activity.
        </p>

        <ol className="guide-stages">
          {STAGES.map((s, i) => (
            <li key={s.key}>
              <span className="guide-stage-dot" style={{ background: s.color }} />
              <div>
                <strong>{i + 1}. {s.label}</strong>
                <p className="muted">{STAGE_MEANING[s.key]}</p>
              </div>
            </li>
          ))}
        </ol>

        <div className="callout">
          <strong>Only “Passed” and “Enforced” count as coverage.</strong> A
          drafted ordinance is not policy. Counting drafts would make the map
          measure effort rather than results, and every number on it would
          overstate what has actually changed.
        </div>
      </section>

      {/* ---------------------------------------------------------------- */}
      <section className="guide-section">
        <h2>How counties are colored</h2>
        <p className="lede">
          The statewide map shades each county by the share of its incorporated
          cities that have passed an ordinance.
        </p>

        <ul className="guide-bands">
          {COVERAGE_BANDS.map((b) => (
            <li key={b.key}>
              <span className="guide-band-swatch" style={{ background: b.color }} />
              <span className="guide-band-label">{b.label}</span>
            </li>
          ))}
        </ul>

        <div className="callout">
          <strong>Why 0% has its own band.</strong> With a single 0–20% bottom
          band, Los Angeles would need eighteen city ordinances before it stopped
          looking identical to a county that had done nothing. The first real win
          in a county would be invisible for years. Zero is its own color so
          that the first ordinance shows immediately.
        </div>
      </section>

      {/* ---------------------------------------------------------------- */}
      <section className="guide-section">
        <h2>County ordinances are not city ordinances</h2>
        <p className="lede">
          This is the single most misunderstood thing on the map, and it changes
          what a win is worth.
        </p>

        <div className="guide-split">
          <article className="guide-card">
            <h3>An incorporated city</h3>
            <p>
              Has its own council and its own police power over land use. Only
              that council can regulate lighting inside its limits.
            </p>
            <p className="muted">
              San Diego’s 18 cities cover <strong>15%</strong> of the county.
            </p>
          </article>

          <article className="guide-card guide-card-alt">
            <h3>Unincorporated land</h3>
            <p>
              No city government. Governed directly by the county Board of
              Supervisors, and reachable only by a county ordinance.
            </p>
            <p className="muted">
              The other <strong>85%</strong> of San Diego County — Ramona,
              Fallbrook, Julian, Borrego Springs.
            </p>
          </article>
        </div>

        <div className="callout callout-warn">
          <strong>A county ordinance stops at the city limit.</strong> San Diego
          County’s Light Pollution Code protects Borrego Springs and Julian, and
          does nothing inside the city of San Diego. That is why county
          ordinances are shown as hatching over the city colors rather than
          replacing them: they are real protection over different ground.
        </div>

        <p className="muted">
          It cuts the other way too. Borrego Springs and Julian are DarkSky
          International certified communities and neither is a city — they appear
          in no city list anywhere, and their protection comes entirely from the
          county.
        </p>
      </section>

      {/* ---------------------------------------------------------------- */}
      <section className="guide-section">
        <h2>What a dark sky ordinance actually contains</h2>
        <p className="lede">
          Five levers. Most existing California codes pull one or two of them.
        </p>

        <div className="lever-grid">
          {LEVERS.map((l) => (
            <article key={l.t} className="lever">
              <span className="lever-icon" aria-hidden="true">{l.icon}</span>
              <h3>{l.t}</h3>
              <p>{l.d}</p>
              <p className="lever-model muted">{l.model}</p>
            </article>
          ))}
        </div>

        <div className="callout">
          <strong>Amortization is the one that decides whether anything
          changes.</strong> Without it, every existing non-compliant fixture stays
          legal forever and the ordinance only governs new construction — which
          in a built-out city is almost nothing. It is also the most contested
          clause, because it is the only one that asks anybody to spend money.
        </div>
      </section>

      {/* ---------------------------------------------------------------- */}
      <section className="guide-section">
        <h2>How a redline is built</h2>
        <p className="lede">
          A redline is the amendment written against the city’s current code, in
          the format their clerk expects. It is the difference between a request
          and a document staff can act on.
        </p>

        <ol className="redline-steps">
          {REDLINE_STEPS.map((s, i) => (
            <li key={s.t}>
              <span className="redline-n">{i + 1}</span>
              <div>
                <strong>{s.t}</strong>
                <p className="muted">{s.d}</p>
              </div>
            </li>
          ))}
        </ol>
      </section>

      {/* ---------------------------------------------------------------- */}
      <section className="guide-section">
        <h2>Thirty steps, seven phases</h2>
        <p className="lede">
          From first conversation to adopted rule. Phases shaded below have{' '}
          <strong>no public meeting attached</strong> — nothing forces a date, so
          they are the ones volunteer campaigns skip, and they are where
          campaigns are won or lost.
        </p>

        <div className="phase-grid">
          {PHASES.map((p) => (
            <article
              key={p.n}
              className={`phase ${p.meeting ? 'phase-meeting' : 'phase-quiet'}`}
            >
              <header>
                <span className="phase-n">Phase {p.n}</span>
                <h3>{p.title}</h3>
                <span className="phase-tag">
                  {p.meeting ? 'Public meeting' : 'No meeting — easy to skip'}
                </span>
              </header>
              <ol>
                {p.steps.map((s) => <li key={s}>{s}</li>)}
              </ol>
            </article>
          ))}
        </div>
      </section>

      {/* ---------------------------------------------------------------- */}
      <section className="guide-section">
        <h2>Things worth knowing before you start</h2>
        <dl className="guide-facts">
          <dt>Amortization is lawful in California</dt>
          <dd>
            <em>City of Los Angeles v. Gage</em> (1954) upheld it as a valid
            exercise of police power, with the burden on the challenger.
            California permits termination of nonconforming uses after a
            reasonable recoupment period — and the hardship valve is part of what
            makes the period reasonable, so it is legally load-bearing rather
            than a courtesy.
          </dd>

          <dt>CEQA is usually not an obstacle</dt>
          <dd>
            A net-protective lighting ordinance likely qualifies for a
            categorical exemption under Guidelines §15307/§15308. Confirm with the
            City Attorney rather than assuming — Monterey was sued in 2012 over
            changing streetlight brightness without review.
          </dd>

          <dt>The Brown Act permits one-on-one meetings</dt>
          <dd>
            Meeting individual commissioners or councilmembers is generally fine.
            What is restricted is group deliberation outside a noticed meeting.
          </dd>

          <dt>Public records requests are the underused tool</dt>
          <dd>
            The CPRA (Gov. Code §7920 et seq.) requires a response within ten
            days. Use it for enforcement logs, complaint records and staff
            correspondence — the evidence that shows whether an existing
            ordinance is doing anything.
          </dd>

          <dt>Do not overstate the crime argument</dt>
          <dd>
            The evidence is genuinely contested. A New York public housing trial
            found roughly a 36% reduction and a DOJ review found reductions, but
            a 2015 study across 62 England and Wales authorities found no effect,
            and four of eight US evaluations found none. The studies showing
            benefit are about <em>street</em> lighting, not private floodlights.
            Overstating it is how a coalition loses credibility in one hearing.
          </dd>
        </dl>
      </section>

      <section className="cta">
        <h2>The model ordinance</h2>
        <p>
          The joint model is the starting text these redlines are built from —
          shielding, color temperature, lumen budgets, trespass limits, curfew
          and amortization, with the reasoning behind each number.
        </p>
        <Link className="btn btn-primary" to="/model-ordinance">
          Read the model ordinance
        </Link>
      </section>
    </div>
  );
}

const STAGE_MEANING = {
  not_started: 'No contact yet, or no record of any.',
  contacted: 'A council office, commissioner or staff member has been approached.',
  meeting_scheduled: 'A meeting or hearing is on a calendar.',
  ordinance_drafted: 'Draft language exists — not yet policy.',
  passed: 'Adopted by the council. This is what counts as coverage.',
  enforced: 'In force and actually being enforced, with compliance underway.',
};

const LEVERS = [
  {
    icon: '🔦',
    t: 'Shielding',
    d: 'Fixtures fully shielded so no light is emitted above the horizontal. The single most effective provision, and the one most codes already have in some form.',
    model: 'Model: fully shielded, U0/G2 above 1,000 lumens',
  },
  {
    icon: '🌡️',
    t: 'Color temperature',
    d: 'Warmer light scatters less and disrupts wildlife and sleep less. Blue-rich white LED is the main thing that got worse over the last fifteen years.',
    model: 'Model: 3,000K general · 2,700K in dark zones and streetlights',
  },
  {
    icon: '📏',
    t: 'Light trespass',
    d: 'A numeric limit on light crossing onto a neighboring property, measured at the receiving property line. Without a number it is unenforceable.',
    model: 'Model: 0.01 fc wilderness · 0.1 fc residential · 0.5 fc public right of way',
  },
  {
    icon: '🕚',
    t: 'Curfew',
    d: 'Lights off, dimmed or motion-triggered after a set hour. Cheap, popular, and the provision that most directly restores the night sky.',
    model: 'Model: 11:00 p.m., or motion sensor with 5-minute shutoff',
  },
  {
    icon: '⏳',
    t: 'Amortization',
    d: 'A deadline by which existing non-compliant fixtures must be brought into line. Without it an ordinance reaches only new construction.',
    model: 'Model: 5 years, plus 90-day immediate measures and a bounded hardship extension',
  },
];
