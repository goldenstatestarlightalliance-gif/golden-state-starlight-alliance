-- Golden State Starlight Alliance — core schema
-- Spec refs: §3 (roles), §4 (map/county pages), §5 (chat), §6 (governance), §7 (succession)
--
-- Design notes:
--  * Super Admin and Org President are BOTH stored as transferable data, never
--    hardcoded to an account (spec §3, §7).
--  * The "general public" umbrella org is a normal organizations row, not a
--    special case (spec §3).
--  * events is append-only and does double duty: audit log (§6) and the
--    per-county public timeline/news feed (§4).

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------

-- The fixed six-stage pipeline (spec §4). Order matters: it is used for sorting
-- and for the map colour ramp.
create type progress_stage as enum (
  'not_started',
  'contacted',
  'meeting_scheduled',
  'ordinance_drafted',
  'passed',
  'enforced'
);

-- Platform-level role ladder above the org level (spec §3).
create type platform_role as enum (
  'super_admin',
  'sub_admin',
  'member'
);

-- Role within a single organization (spec §3).
create type org_role as enum (
  'president',
  'officer',
  'member'
);

create type org_kind as enum (
  'sierra_club',
  'darksky',
  'audubon',
  'astronomy',
  'student',
  'general_public',
  'other'
);

create type channel_kind as enum (
  'statewide',
  'county'
);

-- ---------------------------------------------------------------------------
-- Geography + progress
-- ---------------------------------------------------------------------------

create table counties (
  id            bigint generated always as identity primary key,
  -- 3-digit CA county FIPS, e.g. '085' for Santa Clara. Joins to the Census
  -- TIGER/Line boundary features rendered on the map (spec §4).
  fips          text not null unique,
  name          text not null unique,
  slug          text not null unique,
  region        text,                       -- seed data grouping, e.g. 'southbay'
  status        progress_stage not null default 'not_started',
  -- Outreach research carried over from the seed file.
  priority      smallint check (priority between 1 and 5),
  priority_reason text,
  rationale     text,
  hook          text,
  confidence    text,                       -- 'SOURCED' | 'INFERRED' etc.
  geo_level     text,                       -- 'city' | 'county'
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create table cities (
  id            bigint generated always as identity primary key,
  county_id     bigint not null references counties(id) on delete cascade,
  name          text not null,
  slug          text not null,
  -- Census "place" FIPS. Null until matched against the Census Places file;
  -- the seed data carries names only.
  place_fips    text,
  status        progress_stage not null default 'not_started',
  -- True for the 1-2 cities per county chosen as outreach targets in the seed
  -- data. The remaining ~420 CA cities are loaded from Census Places and are
  -- not priority targets.
  is_priority   boolean not null default false,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (county_id, name)
);

create index cities_county_id_idx on cities(county_id);
create index cities_status_idx on cities(status);

-- Ordinance detail for a city or a county (spec §4: summary AND legal text link).
create table ordinances (
  id             bigint generated always as identity primary key,
  county_id      bigint references counties(id) on delete cascade,
  city_id        bigint references cities(id) on delete cascade,
  title          text,
  summary        text,                      -- plain-language description
  date_passed    date,
  date_effective date,
  legal_text_url text,                      -- link to actual ordinance text/PDF
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  -- Attach to exactly one of city or county, never both, never neither.
  constraint ordinance_scope check (num_nonnulls(county_id, city_id) = 1)
);

create index ordinances_county_id_idx on ordinances(county_id);
create index ordinances_city_id_idx on ordinances(city_id);

-- The researched outreach plan for each county: which professional org and
-- which student org to approach, how to route the ordinance, and by when.
--
-- Kept as free text rather than FKs to organizations on purpose — the research
-- carries per-county corrections that the regional org list does not (e.g.
-- "no active UC Berkeley SEDS chapter confirmed; closest real match is SESB").
-- Losing that nuance to a tidy join would mean re-doing the fact-checking.
create table county_outreach (
  county_id       bigint primary key references counties(id) on delete cascade,
  method          text,
  deadline        text,
  prof_org        text,
  prof_contact    text,
  student_org     text,
  student_contact text,
  updated_at      timestamptz not null default now()
);

-- Council members / local champions researched per county (seed: council[]).
create table council_contacts (
  id         bigint generated always as identity primary key,
  county_id  bigint not null references counties(id) on delete cascade,
  name       text not null,
  title      text,
  evidence   text,
  source_url text,
  created_at timestamptz not null default now()
);

create index council_contacts_county_id_idx on council_contacts(county_id);

-- ---------------------------------------------------------------------------
-- Organizations and people
-- ---------------------------------------------------------------------------

create table organizations (
  id          bigint generated always as identity primary key,
  name        text not null unique,
  slug        text not null unique,
  kind        org_kind not null default 'other',
  website     text,
  email       text,
  region      text,
  -- The coalition's own "general public" org. Flag is descriptive only — it
  -- gets no special treatment in the data model (spec §3).
  is_umbrella boolean not null default false,
  -- A new org is inert until a Sub-Admin approves its first President (spec §3).
  approved    boolean not null default false,
  approved_by uuid,
  approved_at timestamptz,
  created_at  timestamptz not null default now()
);

-- One row per user, mirroring auth.users. Holds the platform-level role.
create table profiles (
  id             uuid primary key references auth.users(id) on delete cascade,
  display_name   text,
  email          text,
  role           platform_role not null default 'member',
  -- e.g. 'Technology & Platform' — only meaningful when role = 'sub_admin'.
  sub_admin_title text,
  -- Moderator is an assignable flag rather than a ladder rung, so a Sub-Admin
  -- can deputise an ordinary member for chat moderation (spec §5).
  is_moderator   boolean not null default false,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

-- Exactly one Super Admin at a time. Transferring the role is an UPDATE of two
-- rows, not a schema change — this is what makes succession possible (spec §7).
create unique index one_super_admin on profiles((role)) where role = 'super_admin';

create table org_memberships (
  id           bigint generated always as identity primary key,
  org_id       bigint not null references organizations(id) on delete cascade,
  user_id      uuid not null references profiles(id) on delete cascade,
  role         org_role not null default 'member',
  officer_title text,                       -- e.g. 'County Liaison'
  -- A County Liaison is scoped to one county; null for other officer titles.
  county_id    bigint references counties(id) on delete set null,
  created_at   timestamptz not null default now(),
  unique (org_id, user_id)
);

-- One sitting President per org. Transfer = update old row to officer/member
-- and new row to president, inside transfer_presidency() below (spec §3).
create unique index one_president_per_org
  on org_memberships(org_id) where role = 'president';

create index org_memberships_user_id_idx on org_memberships(user_id);
create index org_memberships_org_id_idx on org_memberships(org_id);

-- Which orgs are actively working which county. Drives the map hover popup and
-- the county-page credit list (spec §4).
create table county_org_participation (
  county_id  bigint not null references counties(id) on delete cascade,
  org_id     bigint not null references organizations(id) on delete cascade,
  active     boolean not null default true,
  joined_at  timestamptz not null default now(),
  primary key (county_id, org_id)
);

create index county_org_participation_org_idx on county_org_participation(org_id);

-- Per-county outreach email drafts from the seed data.
create table email_templates (
  id         bigint generated always as identity primary key,
  county_id  bigint not null references counties(id) on delete cascade unique,
  body       text not null,
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Chat (spec §5) — Supabase Realtime rides on these tables.
-- ---------------------------------------------------------------------------

create table channels (
  id         bigint generated always as identity primary key,
  kind       channel_kind not null,
  -- Null for the single statewide channel, set for each of the 58 county ones.
  county_id  bigint references counties(id) on delete cascade,
  name       text not null,
  slug       text not null unique,
  created_at timestamptz not null default now(),
  constraint channel_scope check (
    (kind = 'statewide' and county_id is null) or
    (kind = 'county'    and county_id is not null)
  )
);

-- Enforces exactly one statewide channel.
create unique index one_statewide_channel on channels((kind)) where kind = 'statewide';
create unique index one_channel_per_county on channels(county_id) where county_id is not null;

create table messages (
  id          bigint generated always as identity primary key,
  channel_id  bigint not null references channels(id) on delete cascade,
  user_id     uuid references profiles(id) on delete set null,
  body        text not null check (length(body) between 1 and 4000),
  -- Soft delete so moderation is reversible and auditable; the retention job
  -- (0003) is what hard-deletes.
  deleted_at  timestamptz,
  deleted_by  uuid references profiles(id) on delete set null,
  -- Set by the automated spam/profanity filter on the statewide channel.
  flagged     boolean not null default false,
  flag_reason text,
  created_at  timestamptz not null default now()
);

-- Covers the main read pattern: newest messages in one channel.
create index messages_channel_created_idx on messages(channel_id, created_at desc);
-- Supports the 1-year retention sweep.
create index messages_created_at_idx on messages(created_at);

-- ---------------------------------------------------------------------------
-- Audit log / timeline (spec §4 news feed + §6 full audit log)
-- ---------------------------------------------------------------------------

create table events (
  id           bigint generated always as identity primary key,
  actor_id     uuid references profiles(id) on delete set null,
  -- Denormalised so the county timeline is a single indexed lookup rather than
  -- a union across every entity type.
  county_id    bigint references counties(id) on delete cascade,
  entity_type  text not null,               -- 'city' | 'county' | 'ordinance' | ...
  entity_id    bigint,
  action       text not null,               -- 'status_changed' | 'ordinance_added' | ...
  description  text,                        -- human-readable line for the feed
  before       jsonb,
  after        jsonb,
  -- Audit rows are visible to Sub-Admins+; the subset marked public is what
  -- renders in the county news feed.
  is_public    boolean not null default true,
  created_at   timestamptz not null default now()
);

create index events_county_created_idx on events(county_id, created_at desc);
create index events_actor_idx on events(actor_id);
create index events_entity_idx on events(entity_type, entity_id);

-- Append-only: no updates, no deletes, for anyone. This is what makes the
-- trust-based editing model in spec §6 safe.
create rule events_no_update as on update to events do instead nothing;
create rule events_no_delete as on delete to events do instead nothing;

-- ---------------------------------------------------------------------------
-- Triggers
-- ---------------------------------------------------------------------------

create or replace function touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger counties_touch  before update on counties
  for each row execute function touch_updated_at();
create trigger cities_touch    before update on cities
  for each row execute function touch_updated_at();
create trigger ordinances_touch before update on ordinances
  for each row execute function touch_updated_at();
create trigger profiles_touch  before update on profiles
  for each row execute function touch_updated_at();

-- New auth user -> profile row. Everyone starts as a plain member.
create or replace function handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, display_name)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'display_name', split_part(new.email, '@', 1))
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

-- Status changes write themselves into the audit log / timeline. Doing this in
-- a trigger rather than app code means a direct SQL edit is logged too.
create or replace function log_city_status_change()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status is distinct from old.status then
    insert into public.events (
      actor_id, county_id, entity_type, entity_id, action, description, before, after
    ) values (
      auth.uid(), new.county_id, 'city', new.id, 'status_changed',
      new.name || ' moved from ' || replace(old.status::text, '_', ' ')
                || ' to ' || replace(new.status::text, '_', ' '),
      jsonb_build_object('status', old.status),
      jsonb_build_object('status', new.status)
    );
  end if;
  return new;
end;
$$;

create trigger cities_log_status
  after update on cities
  for each row execute function log_city_status_change();

create or replace function log_county_status_change()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status is distinct from old.status then
    insert into public.events (
      actor_id, county_id, entity_type, entity_id, action, description, before, after
    ) values (
      auth.uid(), new.id, 'county', new.id, 'status_changed',
      new.name || ' County moved from ' || replace(old.status::text, '_', ' ')
                || ' to ' || replace(new.status::text, '_', ' '),
      jsonb_build_object('status', old.status),
      jsonb_build_object('status', new.status)
    );
  end if;
  return new;
end;
$$;

create trigger counties_log_status
  after update on counties
  for each row execute function log_county_status_change();
