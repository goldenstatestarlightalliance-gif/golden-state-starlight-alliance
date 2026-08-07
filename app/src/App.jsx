import { Link, NavLink, Outlet } from 'react-router-dom';

const TABS = [
  { to: '/', label: 'Home', end: true },
  { to: '/map', label: 'Progress Map' },
  { to: '/contact', label: 'Contact Us' },
];

export default function App() {
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
