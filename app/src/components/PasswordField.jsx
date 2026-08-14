import { useId, useState } from 'react';
import { STRENGTH_LEVELS } from '../lib/password';

/**
 * Password input with a show/hide toggle.
 *
 * The toggle is a real <button type="button"> — inside a form, a bare <button>
 * defaults to type="submit", so clicking the eye would have submitted the
 * sign-up form instead of revealing the password.
 *
 * Visibility state is per-field rather than shared: revealing the password box
 * should not also reveal the confirmation box, or checking that the two match
 * by eye becomes impossible.
 */
export default function PasswordField({
  label,
  value,
  onChange,
  autoComplete,
  required = true,
  minLength,
  invalid = false,
  describedBy,
  children,
}) {
  const [shown, setShown] = useState(false);
  const id = useId();

  return (
    <label className="pw-label" htmlFor={id}>
      <span>{label}</span>

      <div className={invalid ? 'pw-row pw-row-invalid' : 'pw-row'}>
        <input
          id={id}
          className="pw-input"
          // Swapping type between password and text is what actually toggles
          // visibility; there is no CSS-only way to unmask a password input.
          type={shown ? 'text' : 'password'}
          value={value}
          onChange={(e) => onChange(e.target.value)}
          autoComplete={autoComplete}
          minLength={minLength}
          required={required}
          aria-invalid={invalid || undefined}
          aria-describedby={describedBy}
        />

        <button
          type="button"
          className="pw-toggle"
          onClick={() => setShown((s) => !s)}
          aria-pressed={shown}
          // The label states the ACTION, not the state — a screen reader user
          // hearing "password shown" cannot tell whether that is a description
          // or a promise about what the button will do.
          aria-label={shown ? 'Hide password' : 'Show password'}
          title={shown ? 'Hide password' : 'Show password'}
        >
          {shown ? <EyeOff /> : <Eye />}
        </button>
      </div>

      {children}
    </label>
  );
}

/**
 * The strength bar.
 *
 * Five segments rather than a percentage: a continuous bar implies a precision
 * the scoring does not have, and invites the user to chase the last few
 * percent by adding a "!" to the end.
 */
export function PasswordStrength({ result, id }) {
  const { score, level, hints, meetsMinimum } = result;

  return (
    <div className="pw-strength" id={id}>
      <div className="pw-bars" aria-hidden="true">
        {STRENGTH_LEVELS.map((_, i) => (
          <span
            key={i}
            className="pw-bar"
            style={{
              // Only fill up to the achieved score, and always in the colour of
              // that score — so the bar's colour and its label never disagree.
              background: i <= score && meetsMinimum ? level.color : '#e2e8f0',
            }}
          />
        ))}
      </div>

      {/* polite, not assertive: this updates on every keystroke, and an
          assertive region would interrupt the user mid-word. */}
      <p className="pw-level" aria-live="polite">
        <strong style={{ color: meetsMinimum ? level.color : undefined }}>
          {meetsMinimum ? level.label : 'Too short'}
        </strong>
      </p>

      {hints.length > 0 && (
        <ul className="pw-hints">
          {hints.map((h) => (
            <li key={h}>{h}</li>
          ))}
        </ul>
      )}
    </div>
  );
}

/* Inline SVG rather than an icon dependency — two icons is not worth a
   package, and these inherit currentColor so they follow the button state. */
function Eye() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor"
      strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z" />
      <circle cx="12" cy="12" r="3" />
    </svg>
  );
}

function EyeOff() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor"
      strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-11-8-11-8a18.45 18.45 0 0 1 5.06-5.94M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19m-6.72-1.07a3 3 0 1 1-4.24-4.24" />
      <line x1="1" y1="1" x2="23" y2="23" />
    </svg>
  );
}
