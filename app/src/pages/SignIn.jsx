import { useMemo, useState } from 'react';
import { useNavigate, useLocation } from 'react-router-dom';
import { useAuth } from '../lib/auth';
import PasswordField, { PasswordStrength } from '../components/PasswordField';
import { passwordStrength, MIN_LENGTH } from '../lib/password';

export default function SignIn() {
  const { signIn, signUp } = useAuth();
  const navigate = useNavigate();
  const location = useLocation();

  const [mode, setMode] = useState('signin');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [confirm, setConfirm] = useState('');
  const [displayName, setDisplayName] = useState('');
  const [error, setError] = useState(null);
  const [notice, setNotice] = useState(null);
  const [busy, setBusy] = useState(false);

  const strength = useMemo(() => passwordStrength(password), [password]);

  // Only complain once there is something to compare against — flagging a
  // mismatch while the user is still typing the second box is just noise.
  const mismatch = mode === 'signup' && confirm.length > 0 && confirm !== password;
  const canSubmit =
    mode === 'signin' ||
    (strength.meetsMinimum && confirm === password && confirm.length > 0);

  const submit = async (e) => {
    e.preventDefault();

    // Belt and braces: the button is disabled in this state, but a form can
    // still be submitted with Enter from inside a field.
    if (mode === 'signup' && !canSubmit) {
      setError(
        confirm !== password
          ? 'The two passwords do not match.'
          : `Password must be at least ${MIN_LENGTH} characters.`
      );
      return;
    }

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

        <PasswordField
          label="Password"
          value={password}
          onChange={setPassword}
          autoComplete={mode === 'signin' ? 'current-password' : 'new-password'}
          minLength={mode === 'signup' ? MIN_LENGTH : undefined}
          describedBy={mode === 'signup' ? 'pw-strength' : undefined}
        >
          {/* Meter only while choosing a password. Rating the one someone
              already has is pointless, and on a sign-in form it reads as an
              accusation. */}
          {mode === 'signup' && password.length > 0 && (
            <PasswordStrength result={strength} id="pw-strength" />
          )}
        </PasswordField>

        {mode === 'signup' && (
          <PasswordField
            label="Confirm password"
            value={confirm}
            onChange={setConfirm}
            autoComplete="new-password"
            invalid={mismatch}
            describedBy={mismatch ? 'pw-mismatch' : undefined}
          >
            {mismatch && (
              <small className="pw-error" id="pw-mismatch">
                The two passwords do not match.
              </small>
            )}
            {!mismatch && confirm.length > 0 && confirm === password && (
              <small className="pw-match">Passwords match.</small>
            )}
          </PasswordField>
        )}

        <button
          className="btn btn-primary"
          type="submit"
          disabled={busy || !canSubmit}
        >
          {busy ? 'Working…' : mode === 'signin' ? 'Sign in' : 'Create account'}
        </button>
      </form>

      <p className="switch-mode">
        {mode === 'signin' ? (
          <>
            No account yet?{' '}
            <button className="linklike" onClick={() => { setMode('signup'); setError(null); setConfirm(''); }}>
              Create one
            </button>
          </>
        ) : (
          <>
            Already have an account?{' '}
            <button className="linklike" onClick={() => { setMode('signin'); setError(null); setConfirm(''); }}>
              Sign in
            </button>
          </>
        )}
      </p>
    </div>
  );
}
