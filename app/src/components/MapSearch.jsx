import { useEffect, useMemo, useRef, useState } from 'react';

/**
 * Type-ahead search over a map's features.
 *
 * Used for counties on the statewide map and cities on a county page, so it
 * takes a plain {key, label} list and reports the chosen item back — it knows
 * nothing about Leaflet or about what a county is.
 *
 * Built as a custom combobox rather than an <input list=""> + <datalist>.
 * Native datalist cannot be styled, renders differently in every browser, and
 * gives no control over match ordering — and ordering is the whole point here,
 * because "San" should offer San Diego before Mission San Jose.
 */
export default function MapSearch({
  items,
  placeholder = 'Search…',
  label,
  onSelect,
  selectedKey = null,
}) {
  const [q, setQ] = useState('');
  const [open, setOpen] = useState(false);
  const [active, setActive] = useState(0);
  const wrapRef = useRef(null);
  const inputRef = useRef(null);

  const matches = useMemo(() => {
    const s = q.trim().toLowerCase();
    if (!s) return [];

    // Prefix matches first, then substring. Someone typing "san" wants the
    // cities that start with San, not every name containing those letters.
    const starts = [];
    const contains = [];
    for (const it of items) {
      const l = it.label.toLowerCase();
      if (l.startsWith(s)) starts.push(it);
      else if (l.includes(s)) contains.push(it);
    }
    return [...starts, ...contains].slice(0, 8);
  }, [q, items]);

  // Reset the highlight whenever the result set changes, so Enter never fires
  // the option that happened to sit at the old index.
  useEffect(() => setActive(0), [q]);

  // Close on an outside click. Without this the list stays open over the map
  // and swallows the first click aimed at a county.
  useEffect(() => {
    const onDown = (e) => {
      if (wrapRef.current && !wrapRef.current.contains(e.target)) setOpen(false);
    };
    document.addEventListener('mousedown', onDown);
    return () => document.removeEventListener('mousedown', onDown);
  }, []);

  const choose = (item) => {
    if (!item) return;
    setQ(item.label);
    setOpen(false);
    onSelect(item);
  };

  const clear = () => {
    setQ('');
    setOpen(false);
    onSelect(null);
    inputRef.current?.focus();
  };

  const onKeyDown = (e) => {
    if (e.key === 'Escape') {
      clear();
      return;
    }
    if (!matches.length) return;

    if (e.key === 'ArrowDown') {
      e.preventDefault();
      setOpen(true);
      setActive((i) => (i + 1) % matches.length);
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      setOpen(true);
      setActive((i) => (i - 1 + matches.length) % matches.length);
    } else if (e.key === 'Enter') {
      e.preventDefault();
      choose(matches[active]);
    }
  };

  const listId = `mapsearch-list-${label?.replace(/\W+/g, '') ?? 'x'}`;

  return (
    <div className="map-search" ref={wrapRef}>
      <div className="map-search-row">
        <input
          ref={inputRef}
          type="text"
          className="map-search-input"
          placeholder={placeholder}
          aria-label={label}
          value={q}
          onChange={(e) => {
            setQ(e.target.value);
            setOpen(true);
            // Typing after a selection drops the old highlight, so the outline
            // never disagrees with what the box says.
            if (selectedKey) onSelect(null);
          }}
          onFocus={() => setOpen(true)}
          onKeyDown={onKeyDown}
          role="combobox"
          aria-expanded={open && matches.length > 0}
          aria-controls={listId}
          aria-autocomplete="list"
        />

        {(q || selectedKey) && (
          <button type="button" className="map-search-clear" onClick={clear} aria-label="Clear search">
            ×
          </button>
        )}
      </div>

      {open && matches.length > 0 && (
        <ul className="map-search-list" id={listId} role="listbox">
          {matches.map((m, i) => (
            <li key={m.key} role="option" aria-selected={i === active}>
              <button
                type="button"
                className={i === active ? 'map-search-opt map-search-opt-on' : 'map-search-opt'}
                // mousedown, not click: the input's blur would close the list
                // before a click ever landed.
                onMouseDown={(e) => {
                  e.preventDefault();
                  choose(m);
                }}
                onMouseEnter={() => setActive(i)}
              >
                <Highlighted text={m.label} query={q} />
                {m.note && <span className="map-search-note">{m.note}</span>}
              </button>
            </li>
          ))}
        </ul>
      )}

      {open && q.trim() && matches.length === 0 && (
        <p className="map-search-empty">No match for “{q.trim()}”</p>
      )}
    </div>
  );
}

/** Bolds the typed portion so it is obvious why a result matched. */
function Highlighted({ text, query }) {
  const s = query.trim().toLowerCase();
  const i = s ? text.toLowerCase().indexOf(s) : -1;
  if (i < 0) return <span>{text}</span>;

  return (
    <span>
      {text.slice(0, i)}
      <strong>{text.slice(i, i + s.length)}</strong>
      {text.slice(i + s.length)}
    </span>
  );
}
