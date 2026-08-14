import { useState } from 'react';

// Two glossaries, deliberately separated.
//
// LIGHTING terms are the ones you must actually understand to read the
// ordinance — they are the numbers being argued over. LEGAL/PROCESS terms are
// the ones that stop a newcomer reading a staff report or a council agenda.
// Mixing them buries the small set you genuinely need in a much longer list.
//
// Definitions use concrete anchors (a phone screen, a full moon, a candle)
// because "1 nit = 1 candela per square metre" explains nothing to someone who
// does not already know what a candela is.

const LIGHTING = [
  {
    t: 'Lumen',
    d: 'How much light a bulb puts out in total, in every direction. A normal household LED bulb is about 800 lumens. A car headlight is roughly 1,500.',
    why: 'Almost every limit in the ordinance is written in lumens, because it is the one number printed on every box.',
  },
  {
    t: 'Foot-candle (fc)',
    d: 'How much light is landing on a surface. A full moon gives about 0.01 fc. An office is 30–50 fc.',
    why: 'Light trespass limits use this. 0.1 fc at a neighbor’s fence is about ten times moonlight — enough to notice, not enough to read by.',
  },
  {
    t: 'Correlated Color Temperature (CCT), in Kelvin',
    d: 'The color of white light, not its brightness. Lower is warmer and more orange: a candle is 1,800K, a warm bulb 2,700K, daylight 5,500K+. Higher numbers are bluer.',
    why: 'Blue light scatters much further in the atmosphere and disrupts wildlife and sleep more. Dropping a city from 4000K to 3000K changes nothing about how much light there is — only its color.',
  },
  {
    t: 'Fully shielded / full cutoff',
    d: 'A fixture built so no light escapes above horizontal. The bulb is not visible from the side; light only goes down.',
    why: 'The single most effective provision. Light aimed at the sky lights nothing and is pure waste.',
  },
  {
    t: 'Uplight',
    d: 'Light that goes upward instead of down onto the ground.',
    why: 'Uplight is what creates the orange dome over a city. It is the entire problem in one word.',
  },
  {
    t: 'BUG rating (B, U, G)',
    d: 'A standard fixture rating with three parts: Backlight (spill behind), Uplight (into the sky), Glare (sideways). Each scores 0–5, and lower is better.',
    why: '“U0” means zero uplight. “G2” caps glare at 2. San Diego already collects these at permit intake and compares them to nothing — one of the cheapest fixes available.',
  },
  {
    t: 'Light trespass',
    d: 'Light crossing onto somebody else’s property — the floodlight shining into a bedroom window.',
    why: 'Measured at the receiving property line, not at the fixture. That matters: the limit depends on who is being lit, not on who owns the light.',
  },
  {
    t: 'Sky glow',
    d: 'The permanent orange haze over a city, caused by light scattering off dust and moisture in the air.',
    why: 'It is why roughly 80% of North Americans cannot see the Milky Way from home.',
  },
  {
    t: 'Glare',
    d: 'Light bright enough that it hurts to look at and makes it harder to see, not easier.',
    why: 'The main reason “brighter equals safer” is not automatically true — glare can create dark shadows the eye cannot adjust to.',
  },
  {
    t: 'Candela',
    d: 'Brightness in one particular direction. Roughly one candle’s worth, viewed head on.',
    why: 'Used for sports lighting, where the concern is a single beam pointed somewhere specific.',
  },
  {
    t: 'Nit (or cd/m²)',
    d: 'How bright a glowing surface looks. A phone screen at full brightness is about 500 nits. Identical units — 1 nit is 1 candela per square meter.',
    why: 'Used for signs, because a sign is a lit surface rather than a lamp.',
  },
  {
    t: 'Lumen budget per acre',
    d: 'A cap on the total light a site may install, scaled to its size. A big lot gets more total light than a small one.',
    why: 'Stops a rule being satisfied by installing fifty compliant fixtures where two would do.',
  },
  {
    t: 'Lighting Zone (LZ0–LZ4)',
    d: 'How dark an area is meant to be. LZ0 is wilderness or an observatory; LZ4 is a dense downtown.',
    why: 'Zones govern how MUCH light is allowed, never how well it is aimed. Shielding is identical in every zone by design.',
  },
  {
    t: 'Adaptive controls',
    d: 'Anything that changes lighting automatically — timers, dimmers, motion sensors.',
    why: 'How a curfew is met without going fully dark: lights dim until someone is actually there.',
  },
  {
    t: 'Photocell',
    d: 'A small sensor that switches a light off when it detects daylight.',
    why: 'Cheap, and it stops the common failure of lights running at noon.',
  },
];

const LEGAL = [
  {
    t: 'Ordinance',
    d: 'A local law passed by a city council or a county board of supervisors. Not a state or federal law.',
    why: 'This is the thing being changed. Everything else is procedure around it.',
  },
  {
    t: 'Municipal code',
    d: 'The complete book of a city’s ordinances. §142.0740 means chapter 14, article 2, division 7, section 40.',
    why: 'You amend a section of the code, which is why the section number matters more than the ordinance title.',
  },
  {
    t: 'Amortization',
    d: 'A deadline by which existing equipment that breaks a new rule must be replaced — usually years out, so owners get reasonable use out of what they already bought.',
    why: 'The most important and most contested clause. Without it, an ordinance only touches new construction, and in a built-out city that is almost nothing.',
  },
  {
    t: 'Nonconforming use (“grandfathered”)',
    d: 'Something that was legal when it was built but would not be allowed under today’s rules.',
    why: 'Every existing floodlight becomes this the moment an ordinance passes. Amortization is how that gets resolved.',
  },
  {
    t: 'Police power',
    d: 'The constitutional authority of a government to regulate for public health, safety and welfare. Nothing to do with the police.',
    why: 'The legal basis for regulating lighting at all — and, per <em>City of Los Angeles v. Gage</em> (1954), for amortization.',
  },
  {
    t: 'Conditional Use Permit (CUP)',
    d: 'Extra permission required for a project above a certain size, with extra review before approval.',
    why: 'The model uses a lumen threshold as the trigger, so a stadium gets scrutiny and a driveway light does not.',
  },
  {
    t: 'Variance',
    d: 'Permission to break a specific rule in one specific case, usually for an unusual property.',
    why: 'Watch these after adoption — a stream of variances is how an ordinance quietly stops meaning anything.',
  },
  {
    t: 'Overlay zone',
    d: 'Extra rules layered on top of normal zoning within a mapped area.',
    why: 'How Ventura County did it: the Ojai Valley Dark Sky Overlay applies stricter lighting rules to one mapped area.',
  },
  {
    t: 'CEQA',
    d: 'The California Environmental Quality Act. Requires environmental review before many government decisions.',
    why: 'Usually not an obstacle — a net-protective lighting rule likely qualifies for an exemption — but it must be addressed on the record, not ignored.',
  },
  {
    t: 'Categorical exemption',
    d: 'A class of action that CEQA has already decided does not need full environmental review.',
    why: 'What you are asking the City Attorney to confirm applies, rather than starting a full study.',
  },
  {
    t: 'Brown Act',
    d: 'California’s open-meetings law. Public bodies must deliberate in public.',
    why: 'Meeting councilmembers one at a time is fine. Getting a majority together privately is not.',
  },
  {
    t: 'CPRA (Public Records Act)',
    d: 'A law letting anyone request government records, with a ten-day response requirement.',
    why: 'The most underused tool available. Enforcement logs and complaint records show whether an existing ordinance does anything.',
  },
  {
    t: 'Redline / strikeout',
    d: 'A document showing exactly which words are removed and which are added — deletions struck through, additions underlined.',
    why: 'What staff can actually act on. A request is an opinion; a redline is a document.',
  },
  {
    t: 'First and second reading',
    d: 'An ordinance must be voted on twice, at separate council meetings, before it takes effect.',
    why: 'A win at first reading is not final. The gap between readings is when opposition organizes.',
  },
  {
    t: 'Planning Commission',
    d: 'An appointed body — not elected — that reviews land use matters and recommends to the council.',
    why: 'Usually the first hearing. A recommendation here shapes what the council sees.',
  },
  {
    t: 'Staff report',
    d: 'City staff’s written analysis and recommendation, published before a hearing.',
    why: 'Read it the moment it posts. It tells you what the decision-makers will be reading.',
  },
  {
    t: 'Docket',
    d: 'The official list of items a department is working on.',
    why: 'Getting onto the code amendment docket is what turns interest into scheduled work.',
  },
  {
    t: 'Continuance',
    d: 'A decision to postpone an item to a later meeting rather than vote on it.',
    why: 'Not a defeat. Often it means the body wants changes rather than rejection.',
  },
  {
    t: 'ANSI / IES / RP-6 / TM-15',
    d: 'Standards organizations and their documents. IES is the Illuminating Engineering Society; RP-6 covers sports lighting, TM-15 defines BUG ratings.',
    why: 'Citing the current edition matters — the Loma Prieta model cites RP-6-20, which has been superseded by RP-6-24.',
  },
  {
    t: 'Right of way (ROW)',
    d: 'Public land used for streets and sidewalks.',
    why: 'Gets the loosest trespass limit (0.5 fc), because nobody lives in it.',
  },
  {
    t: 'Waters of the US',
    d: 'Federally protected waters — rivers, wetlands, and similar.',
    why: 'Gets the same strict 0.1 fc trespass limit as a residence, because wildlife lives there.',
  },
];

function TermList({ terms }) {
  return (
    <dl className="glossary">
      {terms.map((x) => (
        <div key={x.t} className="glossary-term">
          <dt>{x.t}</dt>
          <dd>
            <p>{x.d}</p>
            <p className="glossary-why">
              <strong>Why it matters:</strong>{' '}
              <span dangerouslySetInnerHTML={{ __html: x.why }} />
            </p>
          </dd>
        </div>
      ))}
    </dl>
  );
}

export default function Glossary() {
  const [tab, setTab] = useState('lighting');

  return (
    <section className="guide-section">
      <h2>Glossary</h2>
      <p className="lede">
        Two lists. The first is the vocabulary you need to read the ordinance
        itself — these are the numbers being argued over. The second is the
        vocabulary you need to survive a council meeting.
      </p>

      <div className="glossary-tabs">
        <button
          className={tab === 'lighting' ? 'gtab gtab-on' : 'gtab'}
          onClick={() => setTab('lighting')}
        >
          Lighting terms ({LIGHTING.length})
        </button>
        <button
          className={tab === 'legal' ? 'gtab gtab-on' : 'gtab'}
          onClick={() => setTab('legal')}
        >
          Legal &amp; process terms ({LEGAL.length})
        </button>
      </div>

      {tab === 'lighting' ? (
        <>
          <p className="muted glossary-intro">
            Physics and engineering. Learn these and the ordinance stops being
            opaque — most of it is just limits on these quantities.
          </p>
          <TermList terms={LIGHTING} />
        </>
      ) : (
        <>
          <p className="muted glossary-intro">
            Law and procedure. None of these are about lighting; they are how
            local government works, and they are what makes a staff report hard
            to read the first time.
          </p>
          <TermList terms={LEGAL} />
        </>
      )}
    </section>
  );
}
