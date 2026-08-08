-- Attach the outreach deck to San Diego County only.
--
-- BEFORE THIS WORKS: the deck is currently private. Fetching its embed URL
-- anonymously returns Google's sign-in page (HTTP 401), so visitors would see
-- a "Sign in" box where the slides should be.
--
-- Fix in Google Slides:
--   Share -> General access -> "Anyone with the link" -> Viewer
--
-- No code change can work around this; the permission check happens inside
-- Google's iframe.

update counties
   set slides_url = 'https://docs.google.com/presentation/d/14Yu1nGC_QTyid2Yjg_nkbODVDiUbbdtgzSxum2eeJUw/edit'
 where slug = 'san-diego';

-- Confirm exactly one county has a deck.
select slug, name, slides_url
from counties
where slides_url is not null;
