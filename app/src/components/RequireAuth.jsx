import { Navigate, useLocation } from 'react-router-dom';
import { useAuth } from '../lib/auth';

/**
 * Route guard. Convenience only — it hides pages, it does not protect data.
 * Everything these pages read or write is gated by Row Level Security, so
 * bypassing this guard reveals nothing.
 */
export default function RequireAuth({ children }) {
  const { session, loading } = useAuth();
  const location = useLocation();

  // Redirecting before the session is restored would bounce signed-in users
  // out of their own account page on every refresh.
  if (loading) return <div className="page"><p className="muted">Loading…</p></div>;

  if (!session) {
    return <Navigate to="/signin" replace state={{ from: location.pathname }} />;
  }

  return children;
}
