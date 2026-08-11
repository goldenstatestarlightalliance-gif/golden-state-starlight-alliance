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
