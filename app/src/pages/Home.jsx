import { Link } from 'react-router-dom';
import { useCounties } from '../lib/queries';
import { STAGES, stageIndex } from '../lib/pipeline';

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

  // Any county past "not started" counts as underway.
  const started = (counties ?? []).filter((c) => stageIndex(c.status) > 0).length;
  const passed = (counties ?? []).filter(
    (c) => stageIndex(c.status) >= stageIndex('passed')
  ).length;

  return (
    <div className="page">
      <section className="hero">
        <p className="eyebrow">California Dark Sky Coalition</p>
        <h1>
          Bring back the night sky —<br />
          one ordinance at a time.
        </h1>
        <p className="hero-lede">
          We are working to get dark sky lighting policy adopted by at least one
          city or county government in <strong>all 58 California counties</strong>.
          Shielded fixtures, warmer colour temperatures, and sensible lighting
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
      </section>

      <section className="stats">
        <div className="stat">
          <span className="stat-num">58</span>
          <span className="stat-label">counties in scope</span>
        </div>
        <div className="stat">
          {/* Falls back to an em dash rather than a misleading 0 when the
              database has not loaded — an unknown count is not zero. */}
          <span className="stat-num">{counties ? started : '—'}</span>
          <span className="stat-label">counties underway</span>
        </div>
        <div className="stat">
          <span className="stat-num">{counties ? passed : '—'}</span>
          <span className="stat-label">ordinances passed</span>
        </div>
      </section>

      <section>
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
      </section>

      <section>
        <h2>How a county gets there</h2>
        <p className="lede">
          Every county moves through the same six stages. The map colours each
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
      </section>

      <section className="cta">
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
      </section>
    </div>
  );
}
