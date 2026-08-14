import { Link } from 'react-router-dom';
import { useCounties } from '../lib/queries';
import { STAGES, stageIndex } from '../lib/pipeline';
import { hasOrdinance } from '../lib/coverage';

// Why this work matters. Kept here rather than in the database because it is
// editorial copy, not tracked data.
const REASONS = [
  {
    icon: '🕊️',
    title: 'Wildlife',
    body: 'Artificial light at night disrupts bird migration, insect populations, and the nocturnal species that depend on them.',
  },
  {
    icon: '💡',
    title: 'Wasted energy',
    body: 'Light that spills upward illuminates nothing. Shielded fixtures cut utility bills while lighting the ground better.',
  },
  {
    icon: '😴',
    title: 'Human health',
    body: 'Night-time light exposure interferes with circadian rhythms and sleep quality in nearby residents.',
  },
  {
    icon: '✦',
    title: 'The night sky',
    body: 'Most Californians can no longer see the Milky Way from where they live. That is recoverable — light pollution stops the moment the light does.',
  },
];

export default function Home() {
  const { data: counties } = useCounties();

  // Three distinct facts, deliberately not overlapping.
  //
  // An earlier version showed "counties underway" and "ordinances passed" as
  // separate figures while computing both from county status alone — so they
  // were the same set counted twice, and city ordinances went uncounted.
  const all = counties ?? [];

  // The coalition's actual goal (spec §1): an ordinance from at least one city
  // OR county government in every county. A county qualifies either way.
  const countiesWithAnyOrdinance = all.filter(
    (c) =>
      stageIndex(c.status) >= stageIndex('passed') ||
      (c.cities ?? []).some(hasOrdinance)
  ).length;

  // City ordinances statewide — the measure of how many people actually live
  // under one, since a county ordinance covers only unincorporated land.
  const citiesWithOrdinance = all.reduce(
    (n, c) => n + (c.cities ?? []).filter(hasOrdinance).length,
    0
  );

  return (
    // No .page wrapper: the bands run edge to edge and hold their own inner
    // max-width, which is what makes the alternating stripes read as a
    // designed page rather than a column with different background colors.
    <>
      <section className="hero-band">
        <div className="hero-inner">
          <p className="eyebrow">California Dark Sky Coalition</p>
          <h1>
            Bring back the night sky —<br />
            one ordinance at a time.
          </h1>
          <p className="hero-lede">
            We are working to get dark sky lighting policy adopted by at least one
            city or county government in <strong>all 58 California counties</strong>.
            Shielded fixtures, warmer color temperatures, and sensible lighting
            curfews: small changes, applied locally, that add up to a darker sky
            and a lighter energy bill.
          </p>

          <div className="hero-actions">
            <Link className="btn btn-primary" to="/map">
              See the progress map
            </Link>
            <Link className="btn btn-ghost" to="/contact">
              Get involved
            </Link>
          </div>
        </div>
      </section>

      {/* Stat row directly under the hero, the way DarkSky leads with
          "60+ chapters / 4,000+ Advocates". Numbers first, argument after. */}
      <section className="band stat-band">
        <div className="band-inner stats">
          <div className="stat">
            <span className="stat-num">58</span>
            <span className="stat-label">counties in scope</span>
          </div>
          <div className="stat">
            {/* Falls back to an em dash rather than a misleading 0 when the
                database has not loaded — an unknown count is not zero. */}
            <span className="stat-num">{counties ? countiesWithAnyOrdinance : '—'}</span>
            <span className="stat-label">counties with an ordinance</span>
          </div>
          <div className="stat">
            <span className="stat-num">{counties ? citiesWithOrdinance : '—'}</span>
            <span className="stat-label">cities with an ordinance</span>
          </div>
        </div>
      </section>

      <section className="band band-tint">
        <div className="band-inner">
          <h2>Why dark sky policy</h2>
          <div className="reason-grid">
            {REASONS.map((r) => (
              <article key={r.title} className="reason">
                <span className="reason-icon" aria-hidden="true">{r.icon}</span>
                <h3>{r.title}</h3>
                <p>{r.body}</p>
              </article>
            ))}
          </div>
        </div>
      </section>

      <section className="band">
        <div className="band-inner">
          <h2>How a county gets there</h2>
          <p className="lede">
            Every county moves through the same six stages. The map colors each
            county by whichever stage it has reached, so progress is visible and
            credited to the organizations doing the work.
          </p>

          <ol className="stage-flow">
            {STAGES.map((s, i) => (
              <li key={s.key}>
                <span className="stage-dot" style={{ background: s.color }} />
                <span className="stage-n">{i + 1}</span>
                <span className="stage-name">{s.label}</span>
              </li>
            ))}
          </ol>
        </div>
      </section>

      {/* Closing call to action on the brand's own ground, so the page ends
          dark and runs straight into the footer. */}
      <section className="band band-ink">
        <div className="band-inner">
          <h2>This runs on volunteers</h2>
          <p>
            The coalition works through partner organizations — Sierra Club and
            Audubon chapters, DarkSky International groups, student and astronomy
            clubs — plus an umbrella group for anyone not affiliated with a named
            partner. You do not need a background in policy to help.
          </p>
          <Link className="btn btn-primary" to="/contact">
            Find out how to help
          </Link>
        </div>
      </section>
    </>
  );
}
