import { Link, NavLink, Outlet } from 'react-router-dom';
import { useAuth } from './lib/auth';

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
        <Link to="/" className="brand">
          <span className="brand-mark" aria-hidden="true">✦</span>
          <span>
            Golden State Starlight Alliance
            <small>Dark sky policy across all 58 California counties</small>
          </span>
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

      <footer className="footer">
        <p>
          <strong>Golden State Starlight Alliance</strong> — a California
          coalition working to reduce light pollution through local outdoor
          lighting ordinances.
        </p>
        <p className="muted">
          County and city boundaries from the US Census Bureau TIGER/Line
          service (public domain).
        </p>
      </footer>
    </>
  );
}
