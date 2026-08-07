import { useState } from 'react';
import { useNavigate, useLocation } from 'react-router-dom';
import { useAuth } from '../lib/auth';

export default function SignIn() {
  const { signIn, signUp } = useAuth();
  const navigate = useNavigate();
  const location = useLocation();

  const [mode, setMode] = useState('signin');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [displayName, setDisplayName] = useState('');
  const [error, setError] = useState(null);
  const [notice, setNotice] = useState(null);
  const [busy, setBusy] = useState(false);

  const submit = async (e) => {
    e.preventDefault();
    setError(null);
    setNotice(null);
    setBusy(true);

    try {
      if (mode === 'signin') {
        const { error } = await signIn(email, password);
        if (error) throw error;
        // Return the user where they were headed before being bounced here.
        navigate(location.state?.from ?? '/account', { replace: true });
      } else {
        const { data, error } = await signUp(email, password, displayName);
        if (error) throw error;

        // With email confirmation on, signUp returns a user but no session.
        // Saying so beats a form that looks like it silently did nothing.
        if (!data.session) {
          setNotice(
            'Account created. Check your email for a confirmation link, then sign in.'
          );
          setMode('signin');
        } else {
          navigate('/account', { replace: true });
        }
      }
    } catch (err) {
      setError(err.message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="page page-narrow">
      <header className="page-head">
        <h1>{mode === 'signin' ? 'Sign in' : 'Create an account'}</h1>
        <p className="lede">
          {mode === 'signin'
            ? 'Sign in to update county progress and take part in coordination.'
            : 'Anyone can create an account. New accounts start as general members.'}
        </p>
      </header>

      {error && <p className="error">{error}</p>}
      {notice && <p className="notice">{notice}</p>}

      <form className="form" onSubmit={submit}>
        {mode === 'signup' && (
          <label>
            <span>Name</span>
            <input
              type="text"
              value={displayName}
              onChange={(e) => setDisplayName(e.target.value)}
              autoComplete="name"
              required
            />
          </label>
        )}

        <label>
          <span>Email</span>
          <input
            type="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            autoComplete="email"
            required
          />
        </label>

        <label>
          <span>Password</span>
          <input
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            autoComplete={mode === 'signin' ? 'current-password' : 'new-password'}
            minLength={8}
            required
          />
          {mode === 'signup' && (
            <small className="muted">At least 8 characters.</small>
          )}
        </label>

        <button className="btn btn-primary" type="submit" disabled={busy}>
          {busy ? 'Working…' : mode === 'signin' ? 'Sign in' : 'Create account'}
        </button>
      </form>

      <p className="switch-mode">
        {mode === 'signin' ? (
          <>
            No account yet?{' '}
            <button className="linklike" onClick={() => { setMode('signup'); setError(null); }}>
              Create one
            </button>
          </>
        ) : (
          <>
            Already have an account?{' '}
            <button className="linklike" onClick={() => { setMode('signin'); setError(null); }}>
              Sign in
            </button>
          </>
        )}
      </p>
    </div>
  );
}
