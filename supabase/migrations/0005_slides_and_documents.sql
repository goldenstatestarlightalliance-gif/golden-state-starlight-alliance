-- Golden State Starlight Alliance — county slide decks, documents, and org logos
--
-- Adds three things to the county page:
--   1. An embedded Google Slides deck per county (the outreach presentation).
--   2. Named document links — current ordinance, redlined ordinance, and any
--      others a county needs.
--   3. Logos for participating organizations.

-- ---------------------------------------------------------------------------
-- 1. Slide deck per county
-- ---------------------------------------------------------------------------

-- Stored as the full Google Slides URL as pasted by a human. The app derives
-- the /embed and /edit forms from it, and refuses to render anything that is
-- not a docs.google.com presentation — see app/src/lib/slides.js. Keeping the
-- raw URL (rather than just the extracted ID) means a mistyped paste is still
-- visible and fixable rather than silently mangled.
alter table counties add column slides_url text;

-- ---------------------------------------------------------------------------
-- 2. County documents
-- ---------------------------------------------------------------------------

-- The two named kinds the coalition always wants, plus an escape hatch. Using
-- an enum for the known ones keeps the UI able to label and order them
-- consistently; 'other' carries its own label.
create type document_kind as enum (
  'current_ordinance',
  'redlined_ordinance',
  'other'
);

create table county_documents (
  id         bigint generated always as identity primary key,
  county_id  bigint not null references counties(id) on delete cascade,
  kind       document_kind not null default 'other',
  -- Required for 'other', optional for the named kinds (the UI supplies a
  -- default label for those).
  label      text,
  url        text not null,
  -- Manual ordering within a county; ties break by kind then id.
  sort_order smallint not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  -- An 'other' document with no label would render as an unlabelled link.
  constraint other_needs_label check (kind <> 'other' or label is not null)
);

create index county_documents_county_idx on county_documents(county_id, sort_order);

-- At most one current and one redlined ordinance per county. A second one is
-- almost always a mistake rather than an intent.
create unique index one_doc_per_named_kind
  on county_documents(county_id, kind)
  where kind <> 'other';

create trigger county_documents_touch before update on county_documents
  for each row execute function touch_updated_at();

-- ---------------------------------------------------------------------------
-- 3. Organization logos
-- ---------------------------------------------------------------------------

alter table organizations add column logo_url text;

-- ---------------------------------------------------------------------------
-- RLS — same rules as the rest of the county data (spec §6)
-- ---------------------------------------------------------------------------

alter table county_documents enable row level security;

-- Ordinance links are public: they are the evidence behind a "Passed" status.
create policy county_documents_public_read on county_documents
  for select using (true);

create policy county_documents_write on county_documents
  for all
  using (can_edit_county(county_id))
  with check (can_edit_county(county_id));

-- Log document changes to the county timeline, like status changes are.
--
-- NOTE: deliberately branches on TG_OP instead of `coalesce(new, old)`.
-- NEW and OLD are not ordinary values — coalesce() over them does not reliably
-- resolve a row type in PL/pgSQL, and on DELETE, NEW is unset rather than a
-- typed null. Explicit branching is the portable form.
create or replace function log_document_change()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  county   bigint;
  doc_id   bigint;
  doc_kind document_kind;
  doc_label text;
  verb     text;
begin
  if tg_op = 'DELETE' then
    county := old.county_id; doc_id := old.id;
    doc_kind := old.kind;    doc_label := old.label;
    verb := 'removed';
  else
    county := new.county_id; doc_id := new.id;
    doc_kind := new.kind;    doc_label := new.label;
    verb := case tg_op when 'INSERT' then 'added' else 'updated' end;
  end if;

  insert into public.events (
    actor_id, county_id, entity_type, entity_id, action, description, is_public
  ) values (
    auth.uid(), county, 'document', doc_id, 'document_' || verb,
    coalesce(doc_label, initcap(replace(doc_kind::text, '_', ' '))) || ' ' || verb,
    true
  );

  -- AFTER triggers ignore the return value, but it must still be a row.
  if tg_op = 'DELETE' then return old; else return new; end if;
end;
$$;

create trigger county_documents_log
  after insert or update or delete on county_documents
  for each row execute function log_document_change();
