/**
 * The GSSA mark — four-point star over a curved horizon.
 *
 * Drawn as SVG rather than shipped as a raster so it stays sharp at every
 * size, inherits colour from props, and costs no extra request.
 *
 * FOLLOWS THE BRAND SHEET, INCLUDING THE PARTS THAT CONSTRAIN US:
 *
 *   Two versions only. On navy: cream stars, gold horizon. On white: gold
 *   stars, black horizon. There is no third recolouring, so `variant` takes
 *   exactly those two values.
 *
 *   Cream is reserved for stars on navy and nothing else — that is why it
 *   appears here and nowhere in the page background tokens.
 *
 *   Never a shadow, gradient, second ring, or rotation. None are applied, and
 *   none should be added later.
 *
 *   Minimum size 24px; below that the sheet calls for the simplified badge —
 *   star and horizon only. `simplified` drops the small accent stars for that
 *   case, and is applied automatically under 24px.
 */

const INK = '#0B1226';
const GOLD = '#E9B44C';
const CREAM = '#F5EFE3';

export default function Logo({
  variant = 'navy',
  size = 40,
  simplified = false,
  title = 'Golden State Starlight Alliance',
}) {
  const onNavy = variant === 'navy';
  const starColor = onNavy ? CREAM : GOLD;
  const horizonColor = onNavy ? GOLD : INK;

  // The sheet's own rule, enforced rather than left to the caller.
  const plain = simplified || size < 24;

  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 100 100"
      role="img"
      aria-label={title}
      focusable="false"
    >
      {/* Main four-point star. Concave sides — a straight-edged diamond reads
          as a rhombus, not a star. */}
      <path
        d="M50 8 C53 32 60 40 84 43 C60 46 53 54 50 78 C47 54 40 46 16 43 C40 40 47 32 50 8 Z"
        fill={starColor}
      />

      {!plain && (
        <>
          {/* Accent stars. Deliberately asymmetric: a symmetrical scatter
              reads as a pattern rather than as sky. */}
          <path
            d="M78 18 C79 25 81 27 88 28 C81 29 79 31 78 38 C77 31 75 29 68 28 C75 27 77 25 78 18 Z"
            fill={starColor}
            opacity="0.9"
          />
          <path
            d="M25 22 C25.6 26 27 27.4 31 28 C27 28.6 25.6 30 25 34 C24.4 30 23 28.6 19 28 C23 27.4 24.4 26 25 22 Z"
            fill={starColor}
            opacity="0.7"
          />
        </>
      )}

      {/* The horizon. A stroke rather than a filled shape so its weight scales
          with the mark instead of thickening at small sizes. */}
      <path
        d="M14 84 Q50 97 86 84"
        fill="none"
        stroke={horizonColor}
        strokeWidth="7"
        strokeLinecap="round"
      />
    </svg>
  );
}

/**
 * Mark plus wordmark, as used in the site header.
 *
 * Poppins Bold for "GSSA" at 0.13em, Poppins Medium for the tagline at
 * 0.20em — both taken straight from the brand sheet rather than eyeballed.
 */
export function Wordmark({ variant = 'navy', size = 40, showTagline = true }) {
  const onNavy = variant === 'navy';

  return (
    <span className="wordmark">
      <Logo variant={variant} size={size} />
      <span className="wordmark-text">
        <span
          className="wordmark-name"
          style={{ color: onNavy ? '#fff' : INK }}
        >
          GSSA
        </span>
        {showTagline && (
          <span
            className="wordmark-tagline"
            style={{ color: onNavy ? GOLD : '#5b6478' }}
          >
            Golden State Starlight Alliance
          </span>
        )}
      </span>
    </span>
  );
}
