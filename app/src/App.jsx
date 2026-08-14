import { Link, NavLink, Outlet } from 'react-router-dom';
import { useAuth } from './lib/auth';
import Logo, { Wordmark } from './components/Logo';

const TABS = [
  { to: '/', label: 'Home', end: true },
  { to: '/map', label: 'Progress Map' },
  { to: '/guide', label: 'How It Works' },
  { to: '/model-ordinance', label: 'Model Ordinance' },
  { to: '/contact', label: 'Contact Us' },
];

export default function App() {
  const { session, profile, loading } = useAuth();

  return (
    <>
      <header className="topbar">
        {/* Navy variant: cream stars, gold horizon — the only combination the
            brand sheet allows on a dark ground. */}
        <Link to="/" className="brand" aria-label="Golden State Starlight Alliance — home">
          <Wordmark variant="navy" size={42} />
        </Link>

        <nav className="tabs" aria-label="Main">
          {TABS.map((t) => (
            <NavLink
              key={t.to}
              to={t.to}
              // Without `end`, "/" would match every route and Home would
              // always look selected.
              end={t.end}
              className={({ isActive }) => (isActive ? 'tab tab-active' : 'tab')}
            >
              {t.label}
            </NavLink>
          ))}

          {/* Chat is built and working, but deliberately NOT advertised.
              The founder's judgement after actually running outreach: the
              people worth reaching — city planners, council staff, chapter
              leads — will not create an account on a coalition site to read a
              message, and email already reaches them. A discoverable room
              nobody answers in is worse than no room at all.

              The route still resolves at /chat, so it can be shown to a
              partner or switched back on by restoring this NavLink. Nothing
              was deleted: schema, RLS, moderation and the 127 channels are all
              intact and cost nothing while idle. */}

          {/* Held back until the session is known, so the nav does not flash
              "Sign in" at someone who is already signed in. */}
          {!loading && (
            <NavLink
              to={session ? '/account' : '/signin'}
              className={({ isActive }) => (isActive ? 'tab tab-active' : 'tab')}
            >
              {session ? (profile?.display_name || 'Account') : 'Sign in'}
            </NavLink>
          )}
        </nav>
      </header>

      <main>
        <Outlet />
      </main>

      {/* Dark footer, mirroring DarkSky's — it closes the page on the brand's
          own ground rather than trailing off into white. */}
      <footer className="footer">
        <div className="footer-inner">
          <div className="footer-brand">
            <Logo variant="navy" size={52} />
            <p className="footer-mission">
              A California coalition working to reduce light pollution through
              local outdoor lighting ordinances — one city, one county at a time.
            </p>
          </div>

          <nav className="footer-nav" aria-label="Footer">
            <h4>The work</h4>
            <Link to="/map">Progress map</Link>
            <Link to="/guide">How it works</Link>
            <Link to="/model-ordinance">Model ordinance</Link>
            <Link to="/contact">Contact us</Link>
          </nav>
        </div>

        <p className="footer-fine">
          County and city boundaries from the US Census Bureau TIGER/Line
          service (public domain). Ordinance records are compiled from primary
          municipal code sources and cited on each city page.
        </p>
      </footer>
    </>
  );
}
