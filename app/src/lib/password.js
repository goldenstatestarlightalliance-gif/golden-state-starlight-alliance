/**
 * Password strength scoring for the sign-up form.
 *
 * WEIGHTED TOWARD LENGTH, ON PURPOSE. Most strength meters reward character
 * variety — one uppercase, one digit, one symbol — which pushes people toward
 * "P@ssw0rd!": short, predictable, and trivially cracked, while telling them
 * it is strong. Entropy grows with length far faster than with alphabet size,
 * so a long ordinary passphrase genuinely beats a short scrambled one and the
 * meter should say so.
 *
 * This is guidance shown to the user, not a security control. The actual
 * minimum is enforced by Supabase Auth on the server; nothing here can be
 * relied on, because anything running in a browser can be skipped.
 */

export const STRENGTH_LEVELS = [
  { key: 'very-weak',   label: 'Very weak',   color: '#dc2626' },
  { key: 'weak',        label: 'Weak',        color: '#f97316' },
  { key: 'fair',        label: 'Fair',        color: '#eab308' },
  { key: 'strong',      label: 'Strong',      color: '#16a34a' },
  { key: 'very-strong', label: 'Very strong', color: '#15803d' },
];

/** Supabase's default minimum, mirrored so the form and the server agree. */
export const MIN_LENGTH = 8;

// Deliberately short. A real breach list belongs on the server; this only
// needs to catch the handful someone might actually type into this form,
// including the ones this project makes tempting.
const COMMON = new Set([
  'password', 'password1', 'password123', '12345678', '123456789', '1234567890',
  'qwertyui', 'qwerty123', 'letmein', 'welcome1', 'iloveyou', 'admin123',
  'darksky', 'darksky1', 'starlight', 'goldenstate', 'nightsky', 'lightpollution',
]);

/** Three or more consecutive code points ascending or descending: abc, 987. */
function hasRun(pw) {
  let up = 1;
  let down = 1;
  for (let i = 1; i < pw.length; i += 1) {
    const d = pw.charCodeAt(i) - pw.charCodeAt(i - 1);
    up = d === 1 ? up + 1 : 1;
    down = d === -1 ? down + 1 : 1;
    if (up >= 3 || down >= 3) return true;
  }
  return false;
}

/**
 * @returns {{score: number, level: object, hints: string[], meetsMinimum: boolean}}
 *   score is 0-4 and indexes STRENGTH_LEVELS.
 */
export function passwordStrength(pw) {
  const value = pw ?? '';
  const meetsMinimum = value.length >= MIN_LENGTH;

  if (!value) {
    return { score: 0, level: STRENGTH_LEVELS[0], hints: [], meetsMinimum: false };
  }

  const classes = [/[a-z]/, /[A-Z]/, /[0-9]/, /[^A-Za-z0-9]/]
    .filter((re) => re.test(value)).length;

  let score = 0;
  if (value.length >= MIN_LENGTH) score += 1;
  if (value.length >= 12) score += 1;
  if (value.length >= 16) score += 1;
  // Length alone can reach the top rating. Without this step a long plain
  // passphrase stalled one rung below a short scrambled string — which is
  // precisely the character-class theater this module exists to avoid.
  if (value.length >= 20) score += 1;
  // Variety is worth exactly one step — real, but never the main event.
  if (classes >= 3) score += 1;

  const hints = [];

  if (value.length < MIN_LENGTH) {
    hints.push(`Use at least ${MIN_LENGTH} characters.`);
  } else if (value.length < 12) {
    hints.push('Longer is stronger — 12+ characters makes a real difference.');
  }
  if (classes < 3 && value.length < 16) {
    hints.push('Mix in another kind of character, or just make it longer.');
  }

  // Fatal patterns. These cap the score no matter how the above scored,
  // because a predictable password is weak however it is decorated.
  const normalized = value.toLowerCase().replace(/[^a-z0-9]/g, '');
  if (COMMON.has(value.toLowerCase()) || COMMON.has(normalized)) {
    score = 0;
    hints.length = 0;
    hints.push('This is a commonly used password. Pick something else.');
  } else if (/^(.)\1+$/.test(value)) {
    score = 0;
    hints.length = 0;
    hints.push('A single repeated character is not a password.');
  } else {
    if (/(.)\1{2,}/.test(value)) {
      score = Math.min(score, 2);
      hints.push('Avoid repeating the same character three times over.');
    }
    if (hasRun(value)) {
      score = Math.min(score, 2);
      hints.push('Avoid runs like “abc” or “123”.');
    }
  }

  // Never show anything above "very weak" for something the server will
  // reject outright — a green bar on a rejected password is a lie.
  if (!meetsMinimum) score = 0;

  score = Math.max(0, Math.min(4, score));

  return { score, level: STRENGTH_LEVELS[score], hints, meetsMinimum };
}
