-- Attach Google Slides decks to counties.
--
-- Run whichever block you need in the Supabase SQL editor. Until a county has
-- a slides_url, its page shows "No presentation linked for this county yet."
--
-- ---------------------------------------------------------------------------
-- WHICH URL TO USE
-- ---------------------------------------------------------------------------
-- Open the deck in Google Slides and copy the address bar. It looks like:
--
--   https://docs.google.com/presentation/d/1AbC.../edit#slide=id.p
--
-- Paste that whole thing. The app extracts the presentation ID and builds the
-- player URL itself, so the /edit suffix, the #slide fragment, and any ?usp=
-- tracking parameters are all fine and get discarded.
--
-- ---------------------------------------------------------------------------
-- SHARING — the step people miss
-- ---------------------------------------------------------------------------
-- The deck must be visible to people who are not signed in, or visitors get a
-- "You need access" box inside the embed. In Google Slides:
--
--   Share -> General access -> "Anyone with the link" -> Viewer
--
-- This is a public advocacy site, so anonymous visitors must be able to see it.
-- Nothing in the app can work around a private deck — the permission check
-- happens inside Google's iframe, not in our code.

-- ---------------------------------------------------------------------------
-- 1. One shared deck on every county
-- ---------------------------------------------------------------------------
-- Good starting point: a single coalition-wide presentation, replaced with
-- county-specific decks later as they get written.

-- update counties
--    set slides_url = 'PASTE_YOUR_GOOGLE_SLIDES_URL_HERE';

-- ---------------------------------------------------------------------------
-- 2. A deck for one specific county
-- ---------------------------------------------------------------------------

-- update counties
--    set slides_url = 'PASTE_YOUR_GOOGLE_SLIDES_URL_HERE'
--  where slug = 'santa-clara';

-- ---------------------------------------------------------------------------
-- 3. Different decks for several counties at once
-- ---------------------------------------------------------------------------

-- update counties set slides_url = v.url
--   from (values
--     ('santa-clara', 'https://docs.google.com/presentation/d/AAA/edit'),
--     ('san-diego',   'https://docs.google.com/presentation/d/BBB/edit'),
--     ('ventura',     'https://docs.google.com/presentation/d/CCC/edit')
--   ) as v(slug, url)
--  where counties.slug = v.slug;

-- ---------------------------------------------------------------------------
-- Remove a deck
-- ---------------------------------------------------------------------------

-- update counties set slides_url = null where slug = 'santa-clara';

-- ---------------------------------------------------------------------------
-- Check what is attached
-- ---------------------------------------------------------------------------

select
  count(*) filter (where slides_url is not null) as with_deck,
  count(*)                                       as total_counties
from counties;

select slug, name, slides_url
from counties
where slides_url is not null
order by name;
