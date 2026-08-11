-- City pages: each city gets its own slide deck, ordinance record and documents.
--
-- Slide decks move from counties to cities. A deck is an outreach pitch to a
-- specific council, so it belongs with the city being pitched. The county
-- column is dropped at the end of this file.

-- ---------------------------------------------------------------------------
-- Cities
-- ---------------------------------------------------------------------------

alter table cities add column slides_url text;

-- Why this city is where it is. Carries the evidence for a "Passed" as well as
-- the reasoning behind a "Not Started" — a city with no ordinance is not a
-- blank, it is a finding, and the page should say what was checked.
alter table cities add column ordinance_notes text;

-- Set when someone has actually read this city's code, as opposed to simply
-- not having found anything. Distinguishes "confirmed none" from "unknown",
-- which the map cannot otherwise show.
alter table cities add column code_reviewed_at date;
alter table cities add column code_review_source text;

-- ---------------------------------------------------------------------------
-- Documents attach to a city OR a county
-- ---------------------------------------------------------------------------

alter table county_documents add column city_id bigint references cities(id) on delete cascade;
alter table county_documents alter column county_id drop not null;

-- Exactly one owner, mirroring the ordinances table.
alter table county_documents
  add constraint document_scope check (num_nonnulls(county_id, city_id) = 1);

-- The old index assumed a county. Replace with one per scope.
drop index if exists one_doc_per_named_kind;

create unique index one_doc_per_named_kind_county
  on county_documents(county_id, kind)
  where kind <> 'other' and county_id is not null;

create unique index one_doc_per_named_kind_city
  on county_documents(city_id, kind)
  where kind <> 'other' and city_id is not null;

create index county_documents_city_idx on county_documents(city_id, sort_order);

-- ---------------------------------------------------------------------------
-- RLS — a city document is editable by whoever can edit its county
-- ---------------------------------------------------------------------------

drop policy if exists county_documents_write on county_documents;

create policy county_documents_write on county_documents
  for all
  using (
    can_edit_county(coalesce(
      county_id,
      (select c.county_id from cities c where c.id = county_documents.city_id)
    ))
  )
  with check (
    can_edit_county(coalesce(
      county_id,
      (select c.county_id from cities c where c.id = county_documents.city_id)
    ))
  );

-- The timeline trigger reads county_id directly; teach it about city documents.
create or replace function log_document_change()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  county   bigint;
  doc_id   bigint;
  doc_kind document_kind;
  doc_label text;
  verb     text;
  src      record;
begin
  if tg_op = 'DELETE' then src := old; verb := 'removed';
  else src := new; verb := case tg_op when 'INSERT' then 'added' else 'updated' end;
  end if;

  -- A city document still belongs on its county's timeline.
  county := coalesce(
    src.county_id,
    (select c.county_id from cities c where c.id = src.city_id)
  );
  doc_id := src.id; doc_kind := src.kind; doc_label := src.label;

  insert into public.events (
    actor_id, county_id, entity_type, entity_id, action, description, is_public
  ) values (
    auth.uid(), county, 'document', doc_id, 'document_' || verb,
    coalesce(doc_label, initcap(replace(doc_kind::text, '_', ' '))) || ' ' || verb,
    true
  );

  if tg_op = 'DELETE' then return old; else return new; end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Move any existing county deck onto its priority city, then drop the column
-- ---------------------------------------------------------------------------

update cities c
   set slides_url = co.slides_url
  from counties co
 where c.county_id = co.id
   and co.slides_url is not null
   and c.is_priority
   and c.slides_url is null;

alter table counties drop column slides_url;

select
  (select count(*) from cities where slides_url is not null) as cities_with_deck,
  (select count(*) from county_documents where city_id is not null) as city_documents;
-- City-level ordinance detail, and a correction to the San Diego record.
--
-- CORRECTION: San Diego's ordinance was recorded as "O-20186, adopted 2012".
-- That is one amendment, not the origin. SDMC §142.0740 was adopted 9 December
-- 1997 by O-18451, effective 1 January 2000, and has been amended seven times,
-- most recently by O-21771 effective 12 April 2024. Recording the 2012
-- amendment as the adoption date understates it by 15 years and would be
-- embarrassing in front of a City Attorney.

begin;

update ordinances set
  title = 'Municipal Code §142.0740 — Outdoor Lighting Regulations',
  summary =
    'Adopted 9 December 1997 by Ordinance O-18451, effective 1 January 2000, '
    || 'and amended seven times since — most recently by O-21771, effective '
    || '12 April 2024. Covers shielding, light trespass, lighting colour, hours '
    || 'of operation and sensitive biological resource areas, and requires BUG '
    || 'ratings at permit intake. Separate from San Diego County''s Light '
    || 'Pollution Code, which reaches only unincorporated land.',
  date_passed = '1997-12-09',
  date_effective = '2000-01-01'
where city_id = (select id from cities where place_fips = '66000');

-- ---------------------------------------------------------------------------
-- Notes explaining each city's status, including the cities with no ordinance
-- ---------------------------------------------------------------------------

update cities set
  ordinance_notes =
    'In force since 2000 and amended seven times, but with real gaps. The '
    || 'shielding threshold sits at 6,200 / 4,050 lumens rather than 1,000; '
    || 'colour temperature is capped at 4000K rather than 3000K; sports and '
    || 'sign lighting are exempt from shielding entirely; the City exempts its '
    || 'own streetlights; and the observatory provision at (c)(5)(A)(ii) reads '
    || '"4,050 lumens OR 2500K" — a choice, not a mandate. There is no '
    || 'amortization schedule, so existing non-compliant fixtures stay legal '
    || 'indefinitely, and §142.0740 carries no penalty provision at all.',
  code_reviewed_at = '2026-08-08',
  code_review_source = 'https://docs.sandiego.gov/municode/MuniCodeChapter14/Ch14Art02Division07.pdf'
where place_fips = '66000';

update cities set
  ordinance_notes =
    'Article 35 requires shielded low-pressure sodium, shielded narrow-spectrum '
    || 'amber LEDs, or other shielded efficient fixtures at 3,000 Kelvin or '
    || 'less, and requires fixture types, locations and controls to minimise '
    || 'glare, light trespass and artificial sky glow. Both a shielding mandate '
    || 'and a colour temperature cap, which is more than most California city '
    || 'codes carry.',
  code_reviewed_at = '2026-08-08',
  code_review_source = 'https://ecode360.com/43266390'
where place_fips = '22804';

update cities set
  ordinance_notes =
    'Chapter 30.40 requires outdoor fixtures to be fully shielded so all '
    || 'emitted light falls below an imaginary horizontal plane through the '
    || 'lowest point of the luminaire, directed away from streets and '
    || 'neighbouring properties. Full cutoff is the defining dark sky '
    || 'requirement. No colour temperature cap or curfew, so there is room to '
    || 'amend rather than start from nothing.',
  code_reviewed_at = '2026-08-08',
  code_review_source = 'https://ecode360.com/44483877'
where place_fips = '22678';

-- Poway: checked, deliberately not marked passed. The page should say why.
update cities set
  ordinance_notes =
    'Poway Municipal Code 17.08.220(L) and 17.10.150(H) state that "in order to '
    || 'preserve the night sky" outdoor fixtures shall minimise glare, upward '
    || 'light, artificial sky glow, light pollution and light trespass, and '
    || 'require visors or louvres and photocells. Genuine dark sky intent, but '
    || 'the operative wording is "to the maximum extent feasible" — '
    || 'discretionary rather than a shielding mandate, with no colour '
    || 'temperature cap or curfew. Not counted as passed under the coalition''s '
    || 'criterion; a strong candidate for amendment rather than a new ordinance.',
  code_reviewed_at = '2026-08-08',
  code_review_source = 'https://www.codepublishing.com/CA/Poway/'
where place_fips = '58520';

commit;

select
  (select count(*) from cities where ordinance_notes is not null) as cities_with_notes,
  (select count(*) from cities where code_reviewed_at is not null) as cities_code_reviewed,
  (select count(*) from cities where slides_url is not null) as cities_with_deck;
