import { Link, Outlet } from 'react-router-dom';

export default function App() {
  return (
    <>
      <nav className="topbar">
        <Link to="/" className="brand">
          <span className="brand-mark" aria-hidden="true">✦</span>
          Golden State Starlight Alliance
        </Link>
        <span className="tagline">
          Dark sky policy across all 58 California counties
        </span>
      </nav>

      <main>
        <Outlet />
      </main>

      <footer className="footer">
        <p>
          Golden State Starlight Alliance — a California coalition working to
          reduce light pollution through local outdoor lighting ordinances.
        </p>
      </footer>
    </>
  );
}
