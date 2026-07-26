-- ===========================================================================
-- Golden State Starlight Alliance — full database setup
-- GENERATED: concatenation of supabase/migrations/*.sql + supabase/seed.sql
-- Regenerate with: bash scripts/build-apply-all.sh
--
-- Paste this whole file into the Supabase SQL editor and Run.
-- Order matters: schema -> RLS -> functions -> seed.
-- ===========================================================================


-- ===========================================================================
-- SOURCE: supabase/migrations/0001_schema.sql
-- ===========================================================================

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


-- ===========================================================================
-- SOURCE: supabase/migrations/0002_rls.sql
-- ===========================================================================

-- Golden State Starlight Alliance — Row Level Security
--
-- WHY THIS IS NOT OPTIONAL (handoff §3 step 5):
-- The publishable/anon key ships inside the browser bundle by design. Anyone
-- can read it out of the JS and call PostgREST directly with it. RLS is the
-- ONLY thing between that key and open read/write on every table. A table with
-- RLS disabled is a table the public can rewrite.
--
-- Role ladder (spec §3):
--   Super Admin > Sub-Admin > Org President > Org Officer > Org Member > Public

-- ---------------------------------------------------------------------------
-- Helper functions
--
-- These are SECURITY DEFINER on purpose: they read profiles/org_memberships to
-- decide access, and a plain query would re-enter the very policies that call
-- them (infinite recursion). Definer rights let them read the tables directly.
-- They are all read-only and take no user-controlled table names, so there is
-- no injection surface.
-- ---------------------------------------------------------------------------

create or replace function current_platform_role()
returns platform_role
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select role from profiles where id = auth.uid()),
    'member'::platform_role
  );
$$;

create or replace function is_super_admin()
returns boolean
language sql stable security definer set search_path = public as $$
  select current_platform_role() = 'super_admin';
$$;

-- "Sub-Admin or above" — the tier that can see the full audit log and approve
-- new organizations.
create or replace function is_admin()
returns boolean
language sql stable security definer set search_path = public as $$
  select current_platform_role() in ('super_admin', 'sub_admin');
$$;

-- Raw value of the flag, without the admin override. Used by the self-update
-- policy to assert "you did not change your own moderator bit".
create or replace function current_moderator_flag()
returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select is_moderator from profiles where id = auth.uid()), false);
$$;

create or replace function is_moderator()
returns boolean
language sql stable security definer set search_path = public as $$
  select is_admin() or current_moderator_flag();
$$;

-- This user's role inside one org, or null if not a member.
create or replace function user_org_role(target_org bigint)
returns org_role
language sql stable security definer set search_path = public as $$
  select role from org_memberships
  where user_id = auth.uid() and org_id = target_org;
$$;

-- Can this user edit progress data for this county?
--
-- Spec §6 is trust-based: no approval step for an org editing its own county
-- contributions. We read "has the role" as President or Officer of an approved
-- org that is actively participating in that county. Plain Org Members get read
-- access and chat, but do not move cities through the pipeline.
create or replace function can_edit_county(target_county bigint)
returns boolean
language sql stable security definer set search_path = public as $$
  select is_admin() or exists (
    select 1
    from org_memberships m
    join organizations o on o.id = m.org_id
    join county_org_participation p on p.org_id = m.org_id
    where m.user_id = auth.uid()
      and m.role in ('president', 'officer')
      and o.approved
      and p.county_id = target_county
      and p.active
  );
$$;

create or replace function is_authenticated()
returns boolean
language sql stable as $$
  select auth.uid() is not null;
$$;

-- ---------------------------------------------------------------------------
-- Enable RLS on every table. No exceptions.
-- ---------------------------------------------------------------------------

alter table counties                 enable row level security;
alter table cities                   enable row level security;
alter table ordinances               enable row level security;
alter table county_outreach          enable row level security;
alter table council_contacts         enable row level security;
alter table organizations            enable row level security;
alter table profiles                 enable row level security;
alter table org_memberships          enable row level security;
alter table county_org_participation enable row level security;
alter table email_templates          enable row level security;
alter table channels                 enable row level security;
alter table messages                 enable row level security;
alter table events                   enable row level security;

-- ---------------------------------------------------------------------------
-- Public map data — world-readable (spec §4: "fully public, no login required")
-- ---------------------------------------------------------------------------

create policy counties_public_read on counties
  for select using (true);

create policy counties_edit on counties
  for update using (can_edit_county(id)) with check (can_edit_county(id));

-- Only admins add or remove counties. There are exactly 58 and they do not change.
create policy counties_admin_insert on counties
  for insert with check (is_admin());
create policy counties_admin_delete on counties
  for delete using (is_super_admin());

create policy cities_public_read on cities
  for select using (true);

create policy cities_edit on cities
  for update using (can_edit_county(county_id)) with check (can_edit_county(county_id));
create policy cities_insert on cities
  for insert with check (can_edit_county(county_id));
create policy cities_admin_delete on cities
  for delete using (is_admin());

create policy ordinances_public_read on ordinances
  for select using (true);

create policy ordinances_write on ordinances
  for all
  using (
    can_edit_county(coalesce(
      county_id,
      (select c.county_id from cities c where c.id = ordinances.city_id)
    ))
  )
  with check (
    can_edit_county(coalesce(
      county_id,
      (select c.county_id from cities c where c.id = ordinances.city_id)
    ))
  );

-- Org names/links render in the public map popup and county credit lists, so
-- approved orgs are public. Unapproved ones are visible only to admins and to
-- their own members, so a pending org can still see itself.
create policy organizations_public_read on organizations
  for select using (
    approved
    or is_admin()
    or user_org_role(id) is not null
  );

-- Anyone signed in may register a new org; it stays approved = false until a
-- Sub-Admin runs approve_organization() (spec §3).
create policy organizations_create on organizations
  for insert with check (is_authenticated() and not approved);

create policy organizations_president_update on organizations
  for update
  using (is_admin() or user_org_role(id) = 'president')
  with check (is_admin() or user_org_role(id) = 'president');

create policy organizations_admin_delete on organizations
  for delete using (is_admin());

create policy participation_public_read on county_org_participation
  for select using (true);

create policy participation_write on county_org_participation
  for all
  using (is_admin() or user_org_role(org_id) = 'president')
  with check (is_admin() or user_org_role(org_id) = 'president');

-- ---------------------------------------------------------------------------
-- Internal outreach research — signed-in members only.
-- Council contacts and email drafts are working material, not public content.
-- ---------------------------------------------------------------------------

create policy county_outreach_member_read on county_outreach
  for select using (is_authenticated());
create policy county_outreach_write on county_outreach
  for all using (can_edit_county(county_id)) with check (can_edit_county(county_id));

create policy council_contacts_member_read on council_contacts
  for select using (is_authenticated());
create policy council_contacts_write on council_contacts
  for all using (can_edit_county(county_id)) with check (can_edit_county(county_id));

create policy email_templates_member_read on email_templates
  for select using (is_authenticated());
create policy email_templates_write on email_templates
  for all using (can_edit_county(county_id)) with check (can_edit_county(county_id));

-- ---------------------------------------------------------------------------
-- People
-- ---------------------------------------------------------------------------

-- Display names appear next to chat messages and in org rosters, so any signed-in
-- member can read profiles. Anonymous visitors cannot enumerate the membership.
create policy profiles_member_read on profiles
  for select using (is_authenticated());

-- A user may edit their own profile but MUST NOT change their own role — that
-- would let any member self-promote to super_admin with the anon key. Role
-- changes go through the SECURITY DEFINER functions in 0003 only.
--
-- The comparisons use the definer helpers rather than a subquery on profiles:
-- a subquery here would re-enter this same policy and recurse.
create policy profiles_self_update on profiles
  for update
  using (id = auth.uid())
  with check (
    id = auth.uid()
    and role = current_platform_role()
    and is_moderator = current_moderator_flag()
  );

create policy profiles_admin_update on profiles
  for update using (is_admin()) with check (is_admin());

create policy memberships_member_read on org_memberships
  for select using (is_authenticated());

-- Joining an org: a user may create their OWN membership, and only at the
-- lowest rung. President and officer titles are granted, never self-assigned.
create policy memberships_self_join on org_memberships
  for insert with check (user_id = auth.uid() and role = 'member');

create policy memberships_self_leave on org_memberships
  for delete using (
    user_id = auth.uid() and role <> 'president'   -- a president must transfer, not walk away
    or is_admin()
    or user_org_role(org_id) = 'president'
  );

-- Presidents appoint and retitle officers within their own org; admins anywhere.
-- The president row itself is managed by transfer_presidency() (0003).
create policy memberships_president_manage on org_memberships
  for update
  using (is_admin() or (user_org_role(org_id) = 'president' and role <> 'president'))
  with check (
    (is_admin() or user_org_role(org_id) = 'president')
    and role <> 'president'
  );

create policy memberships_president_insert on org_memberships
  for insert with check (
    (is_admin() or user_org_role(org_id) = 'president') and role <> 'president'
  );

-- ---------------------------------------------------------------------------
-- Chat (spec §5)
-- ---------------------------------------------------------------------------

create policy channels_public_read on channels
  for select using (true);
create policy channels_admin_write on channels
  for all using (is_admin()) with check (is_admin());

-- Members read live messages; soft-deleted ones stay visible to moderators for
-- review.
create policy messages_member_read on messages
  for select using (
    is_authenticated() and (deleted_at is null or is_moderator())
  );

-- Post as yourself, into an existing channel, never pre-flagged or pre-deleted.
create policy messages_member_insert on messages
  for insert with check (
    user_id = auth.uid()
    and is_authenticated()
    and deleted_at is null
    and not flagged
  );

-- Authors may retract their own message (soft delete); moderators may act on any.
create policy messages_author_update on messages
  for update
  using (user_id = auth.uid() or is_moderator())
  with check (user_id = auth.uid() or is_moderator());

-- Hard delete is reserved for the retention job and admins. Day-to-day
-- moderation should soft-delete so the action stays auditable.
create policy messages_admin_delete on messages
  for delete using (is_admin());

-- ---------------------------------------------------------------------------
-- Audit log / timeline (spec §4, §6)
-- ---------------------------------------------------------------------------

-- Public rows power the county news feed; the full log is Sub-Admin+ only.
create policy events_read on events
  for select using (is_public or is_admin());

-- Anyone who can edit a county can generate events for it. In practice the
-- triggers in 0001 write these, but a direct insert is allowed for actions
-- that have no natural trigger (e.g. "met with city planner").
create policy events_insert on events
  for insert with check (
    actor_id = auth.uid() and (county_id is null or can_edit_county(county_id))
  );

-- No UPDATE or DELETE policy exists, so both are denied for every role. The
-- rules in 0001 also make them no-ops. Append-only, two ways.


-- ===========================================================================
-- SOURCE: supabase/migrations/0003_functions.sql
-- ===========================================================================

-- Golden State Starlight Alliance — privileged operations
--
-- Every role change lives here rather than in an RLS policy. The policies in
-- 0002 flatly forbid writing profiles.role and org_memberships.role='president';
-- these SECURITY DEFINER functions are the only doors, and each one re-checks
-- the caller's authority before acting.

-- ---------------------------------------------------------------------------
-- Org President succession (spec §3)
-- ---------------------------------------------------------------------------

-- Hand the presidency to another member of the same org. Self-service for the
-- sitting President — no Sub-Admin re-approval, because the org is already
-- approved. The outgoing President stays on as an officer.
create or replace function transfer_presidency(
  target_org  bigint,
  new_president uuid,
  outgoing_title text default 'Past President'
)
returns void
language plpgsql security definer set search_path = public as $$
declare
  caller uuid := auth.uid();
begin
  if caller is null then
    raise exception 'Not authenticated';
  end if;

  if not (
    is_admin()
    or exists (
      select 1 from org_memberships
      where org_id = target_org and user_id = caller and role = 'president'
    )
  ) then
    raise exception 'Only the sitting President of this organization (or an admin) may transfer the presidency';
  end if;

  if not exists (
    select 1 from org_memberships where org_id = target_org and user_id = new_president
  ) then
    raise exception 'The new President must already be a member of this organization';
  end if;

  -- Step down first: one_president_per_org is a unique index, so promoting
  -- before demoting would collide.
  update org_memberships
     set role = 'officer', officer_title = outgoing_title
   where org_id = target_org and role = 'president';

  update org_memberships
     set role = 'president', officer_title = null
   where org_id = target_org and user_id = new_president;

  insert into events (actor_id, entity_type, entity_id, action, description, before, after, is_public)
  values (
    caller, 'organization', target_org, 'presidency_transferred',
    'Presidency transferred',
    jsonb_build_object('president', caller),
    jsonb_build_object('president', new_president),
    false
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- New organization approval (spec §3)
-- ---------------------------------------------------------------------------

-- A Sub-Admin approves an org and installs its first President in one step.
-- This is the only path that creates a president row from nothing.
create or replace function approve_organization(
  target_org bigint,
  first_president uuid
)
returns void
language plpgsql security definer set search_path = public as $$
declare
  caller uuid := auth.uid();
begin
  if not is_admin() then
    raise exception 'Only a Sub-Admin or Super Admin may approve an organization';
  end if;

  update organizations
     set approved = true, approved_by = caller, approved_at = now()
   where id = target_org;

  if not found then
    raise exception 'Organization % not found', target_org;
  end if;

  insert into org_memberships (org_id, user_id, role)
  values (target_org, first_president, 'president')
  on conflict (org_id, user_id) do update set role = 'president';

  insert into events (actor_id, entity_type, entity_id, action, description, is_public)
  values (caller, 'organization', target_org, 'org_approved',
          'Organization approved and first President installed', false);
end;
$$;

-- ---------------------------------------------------------------------------
-- Super Admin succession (spec §7)
-- ---------------------------------------------------------------------------

-- Deliberately transactional and single-step: there is a unique index allowing
-- exactly one super_admin, so the outgoing holder must be demoted in the same
-- statement batch. Demoting to sub_admin rather than member means a mistaken
-- transfer is still recoverable by the outgoing founder.
create or replace function transfer_super_admin(new_super uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  caller uuid := auth.uid();
begin
  if not is_super_admin() then
    raise exception 'Only the current Super Admin may transfer the Super Admin role';
  end if;

  if not exists (select 1 from profiles where id = new_super) then
    raise exception 'Target user has no profile';
  end if;

  update profiles set role = 'sub_admin',
                      sub_admin_title = coalesce(sub_admin_title, 'Founder (emeritus)')
   where id = caller;

  update profiles set role = 'super_admin', sub_admin_title = null
   where id = new_super;

  insert into events (actor_id, entity_type, action, description, before, after, is_public)
  values (caller, 'platform', 'super_admin_transferred', 'Super Admin role transferred',
          jsonb_build_object('super_admin', caller),
          jsonb_build_object('super_admin', new_super),
          false);
end;
$$;

-- Grant or revoke a Sub-Admin seat. Super Admin only.
create or replace function set_sub_admin(target_user uuid, title text, enabled boolean default true)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_super_admin() then
    raise exception 'Only the Super Admin may assign Sub-Admins';
  end if;

  update profiles
     set role = case when enabled then 'sub_admin'::platform_role else 'member'::platform_role end,
         sub_admin_title = case when enabled then title else null end
   where id = target_user and role <> 'super_admin';

  insert into events (actor_id, entity_type, action, description, is_public)
  values (auth.uid(), 'platform',
          case when enabled then 'sub_admin_granted' else 'sub_admin_revoked' end,
          coalesce(title, 'Sub-Admin') || ' seat updated', false);
end;
$$;

-- Deputise an ordinary member as a chat moderator (spec §5).
create or replace function set_moderator(target_user uuid, enabled boolean default true)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then
    raise exception 'Only a Sub-Admin or Super Admin may assign moderators';
  end if;
  update profiles set is_moderator = enabled where id = target_user;
end;
$$;

-- ---------------------------------------------------------------------------
-- Chat retention (spec §5) — 1 year, then hard delete, as a recurring job.
-- ---------------------------------------------------------------------------

create or replace function purge_expired_messages()
returns integer
language plpgsql security definer set search_path = public as $$
declare
  removed integer;
begin
  delete from messages where created_at < now() - interval '1 year';
  get diagnostics removed = row_count;

  if removed > 0 then
    insert into events (entity_type, action, description, is_public)
    values ('platform', 'messages_purged',
            removed || ' message(s) past the 1-year retention window deleted', false);
  end if;

  return removed;
end;
$$;

-- Schedule it. pg_cron is available on Supabase but must be enabled first;
-- if this extension call fails, enable pg_cron under Database > Extensions in
-- the dashboard and re-run just this block.
create extension if not exists pg_cron with schema extensions;

-- Daily at 03:15 UTC. Unschedule first so re-running this migration is safe.
select cron.unschedule('purge-expired-messages')
  where exists (select 1 from cron.job where jobname = 'purge-expired-messages');

select cron.schedule(
  'purge-expired-messages',
  '15 3 * * *',
  $cron$ select public.purge_expired_messages(); $cron$
);

-- ---------------------------------------------------------------------------
-- Realtime (spec §5)
-- ---------------------------------------------------------------------------

-- Publish messages so Supabase Realtime streams inserts/updates to subscribed
-- clients. RLS still applies to what each client actually receives.
alter publication supabase_realtime add table messages;
alter publication supabase_realtime add table events;


-- ===========================================================================
-- SOURCE: supabase/seed.sql
-- ===========================================================================

-- GENERATED FILE — do not edit by hand.
-- Regenerate with: node scripts/generate-seed-sql.mjs
-- Source: data/GoldenStateStarlight_seed_data.json
--
-- Idempotent: safe to re-run. Counties/cities upsert on their natural keys,
-- and every county starts at not_started (spec §4) — real progress is
-- recorded through the app so it lands in the audit log.

begin;

-- 58 California counties
insert into counties (fips, name, slug, region, priority, priority_reason, rationale, hook, confidence, geo_level) values
  ('085', 'Santa Clara', 'santa-clara', 'southbay', 5, 'Sourced evidence + a named, quotable elected official already on record. Specific to this county: Palo Alto adopted a strict citywide Dark Sky (outdoor lighting) ordinance on Dec 8, 2025 (11pm curfew, 0.1 foot-candle limit). Mountain View began developing its own citywide Dark Sky Ordinance in 2025-26 (Council study session Jan 27, 2026).', 'Palo Alto adopted a strict citywide Dark Sky (outdoor lighting) ordinance on Dec 8, 2025 (11pm curfew, 0.1 foot-candle limit). Mountain View began developing its own citywide Dark Sky Ordinance in 2025-26 (Council study session Jan 27, 2026).', 'Palo Alto just passed one of the strictest dark sky lighting ordinances in the state, and Mountain View is actively drafting its own', 'SOURCED', 'city'),
  ('081', 'San Mateo', 'san-mateo', 'southbay', 4, 'Sourced dark-sky civic activity (ordinance, IDA-certified park, or DarkSky chapter nearby) but no individual official named yet. Specific to this county: Brisbane adopted a dark sky ordinance (10pm outdoor lighting curfew) with a compliance schedule running through 2029/2034.', 'Brisbane adopted a dark sky ordinance (10pm outdoor lighting curfew) with a compliance schedule running through 2029/2034.', 'Brisbane already adopted its own outdoor-lighting curfew ordinance', 'SOURCED', 'city'),
  ('073', 'San Diego', 'san-diego', 'sandiego', 5, 'Sourced evidence + a named, quotable elected official already on record. Specific to this county: NOTE: the named advocates below are County Supervisors for the unincorporated Julian and Borrego Springs communities (which the County Board of Supervisors designated ''Dark Sky Communities'' in 2020), not San Diego city council members. ''San Diego'' (the city) is listed as the selected city only because it is the county''s largest incorporated city and home to the DarkSky San Diego County chapter -- for city-level outreach, contact the San Diego City Council separately; for county-level outreach (recommended given the sourced evidence), contact the Supervisors below.', 'NOTE: the named advocates below are County Supervisors for the unincorporated Julian and Borrego Springs communities (which the County Board of Supervisors designated ''Dark Sky Communities'' in 2020), not San Diego city council members. ''San Diego'' (the city) is listed as the selected city only because it is the county''s largest incorporated city and home to the DarkSky San Diego County chapter -- for city-level outreach, contact the San Diego City Council separately; for county-level outreach (recommended given the sourced evidence), contact the Supervisors below.', 'San Diego County''s Board of Supervisors already designated Julian and Borrego Springs as official Dark Sky Communities back in 2020', 'SOURCED', 'county'),
  ('051', 'Mono', 'mono', 'easternsierra', 4, 'Sourced dark-sky civic activity (ordinance, IDA-certified park, or DarkSky chapter nearby) but no individual official named yet. Specific to this county: Mono County''s General Plan includes Chapter 23, dedicated Dark Sky Regulations governing outdoor lighting countywide.', 'Mono County''s General Plan includes Chapter 23, dedicated Dark Sky Regulations governing outdoor lighting countywide.', 'Mono County has had dedicated Dark Sky Regulations written into its General Plan', 'SOURCED', 'city'),
  ('107', 'Tulare', 'tulare', 'centralvalley_s', 4, 'Sourced dark-sky civic activity (ordinance, IDA-certified park, or DarkSky chapter nearby) but no individual official named yet. Specific to this county: Sequoia & Kings Canyon National Parks (largely in Tulare/Fresno counties) are an IDA-certified International Dark Sky Park and host an annual Dark Sky Festival.', 'Sequoia & Kings Canyon National Parks (largely in Tulare/Fresno counties) are an IDA-certified International Dark Sky Park and host an annual Dark Sky Festival.', 'Sequoia & Kings Canyon National Park, right in your county, is a certified International Dark Sky Park', 'SOURCED', 'city'),
  ('019', 'Fresno', 'fresno', 'centralvalley_s', 4, 'Sourced dark-sky civic activity (ordinance, IDA-certified park, or DarkSky chapter nearby) but no individual official named yet. Specific to this county: Sequoia & Kings Canyon National Parks (spanning Fresno/Tulare counties) are an IDA-certified International Dark Sky Park.', 'Sequoia & Kings Canyon National Parks (spanning Fresno/Tulare counties) are an IDA-certified International Dark Sky Park.', 'Sequoia & Kings Canyon National Park, on your county''s doorstep, is a certified International Dark Sky Park', 'SOURCED', 'city'),
  ('027', 'Inyo', 'inyo', 'easternsierra', 4, 'Sourced dark-sky civic activity (ordinance, IDA-certified park, or DarkSky chapter nearby) but no individual official named yet. Specific to this county: Death Valley National Park (Inyo County) is a Gold-tier International Dark Sky Park, among the darkest skies in the US.', 'Death Valley National Park (Inyo County) is a Gold-tier International Dark Sky Park, among the darkest skies in the US.', 'Death Valley National Park in your county holds Gold-tier International Dark Sky Park status', 'SOURCED', 'city'),
  ('043', 'Mariposa', 'mariposa', 'yosemite_sierra', 4, 'Sourced dark-sky civic activity (ordinance, IDA-certified park, or DarkSky chapter nearby) but no individual official named yet. Specific to this county: Yosemite National Park (Mariposa County) hosts night-sky programs; Under Canvas Yosemite (El Portal) is DarkSky''s first Approved Lodging property in California.', 'Yosemite National Park (Mariposa County) hosts night-sky programs; Under Canvas Yosemite (El Portal) is DarkSky''s first Approved Lodging property in California.', 'Yosemite, right in your county, is home to California''s first DarkSky-Approved Lodging property', 'SOURCED', 'city'),
  ('017', 'El Dorado', 'el-dorado', 'tahoe', 4, 'Sourced dark-sky civic activity (ordinance, IDA-certified park, or DarkSky chapter nearby) but no individual official named yet. Specific to this county: The Lake Tahoe Basin (El Dorado/Placer counties) is a long-running focus of dark-sky and night-sky-protection advocacy tied to wildlife and stargazing tourism.', 'The Lake Tahoe Basin (El Dorado/Placer counties) is a long-running focus of dark-sky and night-sky-protection advocacy tied to wildlife and stargazing tourism.', 'The Tahoe Basin''s dark-sky and night-sky protection efforts have been building for years', 'SOURCED', 'city'),
  ('061', 'Placer', 'placer', 'tahoe', 3, 'No sourced dark-sky record, but a real, specific indirect hook exists (observatory, national park/forest proximity, established sustainability program, etc.). Specific to this county: Placer''s Tahoe-basin portion shares the same dark-sky momentum as El Dorado, though most incorporated cities are in the valley; Roseville selected as county''s largest city for direct outreach capacity.', 'Placer''s Tahoe-basin portion shares the same dark-sky momentum as El Dorado, though most incorporated cities are in the valley; Roseville selected as county''s largest city for direct outreach capacity.', 'Placer County spans both fast-growing valley cities and the dark-sky-rich Tahoe basin', 'LIKELY', 'city'),
  ('057', 'Nevada', 'nevada', 'sierra_gold', 4, 'Sourced dark-sky civic activity (ordinance, IDA-certified park, or DarkSky chapter nearby) but no individual official named yet. Specific to this county: Truckee sits in the dark-sky-attentive Tahoe/Truckee corridor with active land-trust night-sky programming.', 'Truckee sits in the dark-sky-attentive Tahoe/Truckee corridor with active land-trust night-sky programming.', 'Truckee is part of the Tahoe corridor''s growing dark-sky and night-sky-tourism movement', 'SOURCED', 'city'),
  ('071', 'San Bernardino', 'san-bernardino', 'socal', 4, 'Sourced dark-sky civic activity (ordinance, IDA-certified park, or DarkSky chapter nearby) but no individual official named yet. Specific to this county: Twentynine Palms borders Joshua Tree National Park, covered by the DarkSky Joshua Tree chapter; Big Bear Lake hosts the Big Bear Solar Observatory.', 'Twentynine Palms borders Joshua Tree National Park, covered by the DarkSky Joshua Tree chapter; Big Bear Lake hosts the Big Bear Solar Observatory.', 'Twentynine Palms sits right on the edge of Joshua Tree National Park and DarkSky Joshua Tree''s territory', 'SOURCED', 'city'),
  ('065', 'Riverside', 'riverside', 'socal', 3, 'No sourced dark-sky record, but a real, specific indirect hook exists (observatory, national park/forest proximity, established sustainability program, etc.). Specific to this county: Coachella Valley cities border Joshua Tree National Park (DarkSky Joshua Tree chapter territory) and have a strong astro-tourism economy.', 'Coachella Valley cities border Joshua Tree National Park (DarkSky Joshua Tree chapter territory) and have a strong astro-tourism economy.', 'The Coachella Valley''s night-sky tourism economy and proximity to Joshua Tree National Park', 'LIKELY', 'city'),
  ('087', 'Santa Cruz', 'santa-cruz', 'southbay', 4, 'Sourced dark-sky civic activity (ordinance, IDA-certified park, or DarkSky chapter nearby) but no individual official named yet. Specific to this county: Home to DarkSky Santa Cruz, an official chapter of DarkSky International.', 'Home to DarkSky Santa Cruz, an official chapter of DarkSky International.', 'Santa Cruz is already home to its own DarkSky International chapter', 'SOURCED', 'city'),
  ('079', 'San Luis Obispo', 'san-luis-obispo', 'centralcoast', 4, 'Sourced dark-sky civic activity (ordinance, IDA-certified park, or DarkSky chapter nearby) but no individual official named yet. Specific to this county: Covered by the DarkSky Central Coast chapter and the Central Coast Astronomical Society.', 'Covered by the DarkSky Central Coast chapter and the Central Coast Astronomical Society.', 'The Central Coast already has an active DarkSky International chapter working in your area', 'SOURCED', 'city'),
  ('083', 'Santa Barbara', 'santa-barbara', 'centralcoast', 4, 'Sourced dark-sky civic activity (ordinance, IDA-certified park, or DarkSky chapter nearby) but no individual official named yet. Specific to this county: Covered by the DarkSky Central Coast chapter.', 'Covered by the DarkSky Central Coast chapter.', 'The Central Coast already has an active DarkSky International chapter working in your area', 'SOURCED', 'city'),
  ('053', 'Monterey', 'monterey', 'centralcoast', 4, 'Sourced dark-sky civic activity (ordinance, IDA-certified park, or DarkSky chapter nearby) but no individual official named yet. Specific to this county: Covered by the DarkSky Central Coast chapter; Pinnacles National Park (San Benito/Monterey) has notably dark Bortle-class skies.', 'Covered by the DarkSky Central Coast chapter; Pinnacles National Park (San Benito/Monterey) has notably dark Bortle-class skies.', 'Nearby Pinnacles National Park and the Central Coast DarkSky chapter show real regional momentum', 'SOURCED', 'city'),
  ('067', 'Sacramento', 'sacramento', 'centralvalley_n', 4, 'Sourced dark-sky civic activity (ordinance, IDA-certified park, or DarkSky chapter nearby) but no individual official named yet. Specific to this county: Home to the Sacramento Valley Astronomical Society (SVAS), one of the oldest continuously active astronomy clubs in the US (est. 1945).', 'Home to the Sacramento Valley Astronomical Society (SVAS), one of the oldest continuously active astronomy clubs in the US (est. 1945).', 'Sacramento is home to one of the nation''s oldest astronomy clubs, SVAS, founded in 1945', 'SOURCED', 'city'),
  ('001', 'Alameda', 'alameda', 'bay', 3, 'No sourced dark-sky record, but a real, specific indirect hook exists (observatory, national park/forest proximity, established sustainability program, etc.). Specific to this county: No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'your community''s setting and local environmental values', 'LIKELY', 'city'),
  ('003', 'Alpine', 'alpine', 'easternsierra', 1, 'No sourced record; very small population and/or limited local-government capacity. Specific to this county: No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'your community''s setting and local environmental values', 'LIKELY', 'city'),
  ('005', 'Amador', 'amador', 'sierra_gold', 2, 'No sourced record or specific hook; moderate-size city/county with basic local-government capacity. Specific to this county: No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'your community''s setting and local environmental values', 'LIKELY', 'city'),
  ('007', 'Butte', 'butte', 'farnorth', 3, 'No sourced dark-sky record, but a real, specific indirect hook exists (observatory, national park/forest proximity, established sustainability program, etc.). Specific to this county: No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'your community''s setting and local environmental values', 'LIKELY', 'city'),
  ('009', 'Calaveras', 'calaveras', 'sierra_gold', 2, 'No sourced record or specific hook; moderate-size city/county with basic local-government capacity. Specific to this county: No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'your community''s setting and local environmental values', 'LIKELY', 'city'),
  ('011', 'Colusa', 'colusa', 'farnorth', 1, 'No sourced record; very small population and/or limited local-government capacity. Specific to this county: No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'your community''s setting and local environmental values', 'LIKELY', 'city'),
  ('013', 'Contra Costa', 'contra-costa', 'bay', 2, 'No sourced record or specific hook; moderate-size city/county with basic local-government capacity. Specific to this county: No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'your community''s setting and local environmental values', 'LIKELY', 'city'),
  ('015', 'Del Norte', 'del-norte', 'northcoast', 3, 'No sourced dark-sky record, but a real, specific indirect hook exists (observatory, national park/forest proximity, established sustainability program, etc.). Specific to this county: No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'your community''s setting and local environmental values', 'LIKELY', 'city'),
  ('021', 'Glenn', 'glenn', 'farnorth', 1, 'No sourced record; very small population and/or limited local-government capacity. Specific to this county: No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'your community''s setting and local environmental values', 'LIKELY', 'city'),
  ('023', 'Humboldt', 'humboldt', 'northcoast', 3, 'No sourced dark-sky record, but a real, specific indirect hook exists (observatory, national park/forest proximity, established sustainability program, etc.). Specific to this county: No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'your community''s setting and local environmental values', 'LIKELY', 'city'),
  ('025', 'Imperial', 'imperial', 'imperial', 2, 'No sourced record or specific hook; moderate-size city/county with basic local-government capacity. Specific to this county: No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'your community''s setting and local environmental values', 'LIKELY', 'city'),
  ('029', 'Kern', 'kern', 'centralvalley_s', 3, 'No sourced dark-sky record, but a real, specific indirect hook exists (observatory, national park/forest proximity, established sustainability program, etc.). Specific to this county: No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'your community''s setting and local environmental values', 'LIKELY', 'city'),
  ('031', 'Kings', 'kings', 'centralvalley_s', 2, 'No sourced record or specific hook; moderate-size city/county with basic local-government capacity. Specific to this county: No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'your community''s setting and local environmental values', 'LIKELY', 'city'),
  ('033', 'Lake', 'lake', 'northcoast', 2, 'No sourced record or specific hook; moderate-size city/county with basic local-government capacity. Specific to this county: No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'your community''s setting and local environmental values', 'LIKELY', 'city'),
  ('035', 'Lassen', 'lassen', 'farnorth', 3, 'No sourced dark-sky record, but a real, specific indirect hook exists (observatory, national park/forest proximity, established sustainability program, etc.). Specific to this county: No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'your community''s setting and local environmental values', 'LIKELY', 'city'),
  ('037', 'Los Angeles', 'los-angeles', 'socal', 3, 'No sourced dark-sky record, but a real, specific indirect hook exists (observatory, national park/forest proximity, established sustainability program, etc.). Specific to this county: No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'your community''s setting and local environmental values', 'LIKELY', 'city'),
  ('039', 'Madera', 'madera', 'yosemite_sierra', 2, 'No sourced record or specific hook; moderate-size city/county with basic local-government capacity. Specific to this county: No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'your community''s setting and local environmental values', 'LIKELY', 'city'),
  ('041', 'Marin', 'marin', 'bay', 3, 'No sourced dark-sky record, but a real, specific indirect hook exists (observatory, national park/forest proximity, established sustainability program, etc.). Specific to this county: No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'your community''s setting and local environmental values', 'LIKELY', 'city'),
  ('045', 'Mendocino', 'mendocino', 'northcoast', 3, 'No sourced dark-sky record, but a real, specific indirect hook exists (observatory, national park/forest proximity, established sustainability program, etc.). Specific to this county: No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'your community''s setting and local environmental values', 'LIKELY', 'city'),
  ('047', 'Merced', 'merced', 'centralvalley_n', 2, 'No sourced record or specific hook; moderate-size city/county with basic local-government capacity. Specific to this county: No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'your community''s setting and local environmental values', 'LIKELY', 'city'),
  ('049', 'Modoc', 'modoc', 'farnorth', 1, 'No sourced record; very small population and/or limited local-government capacity. Specific to this county: No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'your community''s setting and local environmental values', 'LIKELY', 'city'),
  ('055', 'Napa', 'napa', 'bay', 3, 'No sourced dark-sky record, but a real, specific indirect hook exists (observatory, national park/forest proximity, established sustainability program, etc.). Specific to this county: No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'your community''s setting and local environmental values', 'LIKELY', 'city'),
  ('059', 'Orange', 'orange', 'socal', 3, 'No sourced dark-sky record, but a real, specific indirect hook exists (observatory, national park/forest proximity, established sustainability program, etc.). Specific to this county: No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'your community''s setting and local environmental values', 'LIKELY', 'city'),
  ('063', 'Plumas', 'plumas', 'farnorth', 2, 'No sourced record or specific hook; moderate-size city/county with basic local-government capacity. Specific to this county: No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'your community''s setting and local environmental values', 'LIKELY', 'city'),
  ('069', 'San Benito', 'san-benito', 'centralcoast', 2, 'No sourced record or specific hook; moderate-size city/county with basic local-government capacity. Specific to this county: No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'your community''s setting and local environmental values', 'LIKELY', 'city'),
  ('075', 'San Francisco', 'san-francisco', 'bay', 3, 'No sourced dark-sky record, but a real, specific indirect hook exists (observatory, national park/forest proximity, established sustainability program, etc.). Specific to this county: No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'your community''s setting and local environmental values', 'LIKELY', 'city'),
  ('077', 'San Joaquin', 'san-joaquin', 'centralvalley_n', 2, 'No sourced record or specific hook; moderate-size city/county with basic local-government capacity. Specific to this county: No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'your community''s setting and local environmental values', 'LIKELY', 'city'),
  ('089', 'Shasta', 'shasta', 'farnorth', 2, 'No sourced record or specific hook; moderate-size city/county with basic local-government capacity. Specific to this county: No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'your community''s setting and local environmental values', 'LIKELY', 'city'),
  ('091', 'Sierra', 'sierra', 'sierra_gold', 1, 'No sourced record; very small population and/or limited local-government capacity. Specific to this county: No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'your community''s setting and local environmental values', 'LIKELY', 'city'),
  ('093', 'Siskiyou', 'siskiyou', 'farnorth', 3, 'No sourced dark-sky record, but a real, specific indirect hook exists (observatory, national park/forest proximity, established sustainability program, etc.). Specific to this county: No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'your community''s setting and local environmental values', 'LIKELY', 'city'),
  ('095', 'Solano', 'solano', 'bay', 2, 'No sourced record or specific hook; moderate-size city/county with basic local-government capacity. Specific to this county: No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'your community''s setting and local environmental values', 'LIKELY', 'city'),
  ('097', 'Sonoma', 'sonoma', 'northcoast', 3, 'No sourced dark-sky record, but a real, specific indirect hook exists (observatory, national park/forest proximity, established sustainability program, etc.). Specific to this county: No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'your community''s setting and local environmental values', 'LIKELY', 'city'),
  ('099', 'Stanislaus', 'stanislaus', 'centralvalley_n', 2, 'No sourced record or specific hook; moderate-size city/county with basic local-government capacity. Specific to this county: No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'your community''s setting and local environmental values', 'LIKELY', 'city'),
  ('101', 'Sutter', 'sutter', 'centralvalley_n', 2, 'No sourced record or specific hook; moderate-size city/county with basic local-government capacity. Specific to this county: No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'your community''s setting and local environmental values', 'LIKELY', 'city'),
  ('103', 'Tehama', 'tehama', 'farnorth', 2, 'No sourced record or specific hook; moderate-size city/county with basic local-government capacity. Specific to this county: No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'your community''s setting and local environmental values', 'LIKELY', 'city'),
  ('105', 'Trinity', 'trinity', 'northcoast', 1, 'No sourced record; very small population and/or limited local-government capacity. Specific to this county: No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'your community''s setting and local environmental values', 'LIKELY', 'city'),
  ('109', 'Tuolumne', 'tuolumne', 'yosemite_sierra', 3, 'No sourced dark-sky record, but a real, specific indirect hook exists (observatory, national park/forest proximity, established sustainability program, etc.). Specific to this county: No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'your community''s setting and local environmental values', 'LIKELY', 'city'),
  ('111', 'Ventura', 'ventura', 'centralcoast', 3, 'No sourced dark-sky record, but a real, specific indirect hook exists (observatory, national park/forest proximity, established sustainability program, etc.). Specific to this county: No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'your community''s setting and local environmental values', 'LIKELY', 'city'),
  ('113', 'Yolo', 'yolo', 'centralvalley_n', 3, 'No sourced dark-sky record, but a real, specific indirect hook exists (observatory, national park/forest proximity, established sustainability program, etc.). Specific to this county: No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'your community''s setting and local environmental values', 'LIKELY', 'city'),
  ('115', 'Yuba', 'yuba', 'centralvalley_n', 2, 'No sourced record or specific hook; moderate-size city/county with basic local-government capacity. Specific to this county: No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'No specific sourced dark-sky/light-pollution civic action was found in research for this county. City selected as county seat / largest city for outreach capacity, or (for rural/scenic counties) for its dark, low-light-pollution setting.', 'your community''s setting and local environmental values', 'LIKELY', 'city');

-- Priority outreach cities (from research; ~63 rows, not the full 482)
insert into cities (county_id, name, slug, is_priority) values
  ((select id from counties where fips = '085'), 'Palo Alto', 'palo-alto', true),
  ((select id from counties where fips = '085'), 'Mountain View', 'mountain-view', true),
  ((select id from counties where fips = '081'), 'Brisbane', 'brisbane', true),
  ((select id from counties where fips = '073'), 'San Diego', 'san-diego', true),
  ((select id from counties where fips = '051'), 'Mammoth Lakes', 'mammoth-lakes', true),
  ((select id from counties where fips = '107'), 'Visalia', 'visalia', true),
  ((select id from counties where fips = '019'), 'Fresno', 'fresno', true),
  ((select id from counties where fips = '027'), 'Bishop', 'bishop', true),
  ((select id from counties where fips = '043'), '(no incorporated cities – county seat Mariposa is unincorporated)', 'no-incorporated-cities-county-seat-mariposa-is-unincorporated', true),
  ((select id from counties where fips = '017'), 'South Lake Tahoe', 'south-lake-tahoe', true),
  ((select id from counties where fips = '061'), 'Roseville', 'roseville', true),
  ((select id from counties where fips = '057'), 'Truckee', 'truckee', true),
  ((select id from counties where fips = '057'), 'Nevada City', 'nevada-city', true),
  ((select id from counties where fips = '071'), 'Twentynine Palms', 'twentynine-palms', true),
  ((select id from counties where fips = '071'), 'Big Bear Lake', 'big-bear-lake', true),
  ((select id from counties where fips = '065'), 'Palm Springs', 'palm-springs', true),
  ((select id from counties where fips = '065'), 'Indio', 'indio', true),
  ((select id from counties where fips = '087'), 'Santa Cruz', 'santa-cruz', true),
  ((select id from counties where fips = '079'), 'San Luis Obispo', 'san-luis-obispo', true),
  ((select id from counties where fips = '083'), 'Santa Barbara', 'santa-barbara', true),
  ((select id from counties where fips = '053'), 'Monterey', 'monterey', true),
  ((select id from counties where fips = '067'), 'Sacramento', 'sacramento', true),
  ((select id from counties where fips = '001'), 'Berkeley', 'berkeley', true),
  ((select id from counties where fips = '003'), '(no incorporated cities – county seat Markleeville is unincorporated)', 'no-incorporated-cities-county-seat-markleeville-is-unincorporated', true),
  ((select id from counties where fips = '005'), 'Jackson', 'jackson', true),
  ((select id from counties where fips = '007'), 'Chico', 'chico', true),
  ((select id from counties where fips = '009'), 'Angels Camp', 'angels-camp', true),
  ((select id from counties where fips = '011'), 'Colusa', 'colusa', true),
  ((select id from counties where fips = '013'), 'Walnut Creek', 'walnut-creek', true),
  ((select id from counties where fips = '015'), 'Crescent City', 'crescent-city', true),
  ((select id from counties where fips = '021'), 'Willows', 'willows', true),
  ((select id from counties where fips = '023'), 'Arcata', 'arcata', true),
  ((select id from counties where fips = '025'), 'El Centro', 'el-centro', true),
  ((select id from counties where fips = '029'), 'Bakersfield', 'bakersfield', true),
  ((select id from counties where fips = '031'), 'Hanford', 'hanford', true),
  ((select id from counties where fips = '033'), 'Clearlake', 'clearlake', true),
  ((select id from counties where fips = '035'), 'Susanville', 'susanville', true),
  ((select id from counties where fips = '037'), 'Los Angeles', 'los-angeles', true),
  ((select id from counties where fips = '037'), 'Sierra Madre', 'sierra-madre', true),
  ((select id from counties where fips = '039'), 'Madera', 'madera', true),
  ((select id from counties where fips = '041'), 'San Rafael', 'san-rafael', true),
  ((select id from counties where fips = '045'), 'Ukiah', 'ukiah', true),
  ((select id from counties where fips = '047'), 'Merced', 'merced', true),
  ((select id from counties where fips = '049'), 'Alturas', 'alturas', true),
  ((select id from counties where fips = '055'), 'Napa', 'napa', true),
  ((select id from counties where fips = '059'), 'Irvine', 'irvine', true),
  ((select id from counties where fips = '063'), 'Portola', 'portola', true),
  ((select id from counties where fips = '069'), 'Hollister', 'hollister', true),
  ((select id from counties where fips = '075'), 'San Francisco', 'san-francisco', true),
  ((select id from counties where fips = '077'), 'Stockton', 'stockton', true),
  ((select id from counties where fips = '089'), 'Redding', 'redding', true),
  ((select id from counties where fips = '091'), 'Loyalton', 'loyalton', true),
  ((select id from counties where fips = '093'), 'Mount Shasta', 'mount-shasta', true),
  ((select id from counties where fips = '095'), 'Vacaville', 'vacaville', true),
  ((select id from counties where fips = '097'), 'Santa Rosa', 'santa-rosa', true),
  ((select id from counties where fips = '099'), 'Modesto', 'modesto', true),
  ((select id from counties where fips = '101'), 'Yuba City', 'yuba-city', true),
  ((select id from counties where fips = '103'), 'Red Bluff', 'red-bluff', true),
  ((select id from counties where fips = '105'), '(no incorporated cities – county seat Weaverville is unincorporated)', 'no-incorporated-cities-county-seat-weaverville-is-unincorporated', true),
  ((select id from counties where fips = '109'), 'Sonora', 'sonora', true),
  ((select id from counties where fips = '111'), 'Ventura', 'ventura', true),
  ((select id from counties where fips = '113'), 'Davis', 'davis', true),
  ((select id from counties where fips = '115'), 'Marysville', 'marysville', true)
on conflict (county_id, name) do update set is_priority = true;

-- Researched outreach plan per county (prof + student org, method, deadline).
-- Contact strings preserve the fact-check corrections from the research.
insert into county_outreach (county_id, method, deadline, prof_org, prof_contact, student_org, student_contact) values
  ((select id from counties where fips = '001'), 'Introduce a municipal/county outdoor-lighting ordinance via the city council or board, routed through the planning or sustainability commission first; use the local hook (park/observatory/forest/program) as the opening argument.', 'Send by Nov 30, 2026; natural follow-up anchor: International Dark Sky Week / Earth Day, Apr 2027', 'Sierra Club San Francisco Bay Chapter', 'sierraclub.org/sfbay | contact form on site (no single public email found)', 'UC Berkeley Students for the Exploration and Development of Space (SEDS)', 'CORRECTION: no active UC Berkeley SEDS chapter confirmed. Closest real match: Space Exploration Society at Berkeley (SESB) | sesb.berkeley.edu'),
  ((select id from counties where fips = '003'), 'Introduce a municipal/county outdoor-lighting ordinance (shielded fixtures, curfew, color-temperature limit) via the city council or board of supervisors; start with a public-comment campaign to gauge/build support before a formal proposal.', 'Send by Apr 2027, timed to International Dark Sky Week (lower-urgency batch)', 'Sierra Club Toiyabe Chapter', 'sierraclub.org/Toiyabe | contact form on site (no single public email found)', 'Local high school environmental club (Bishop / Mammoth area)', 'No single verifiable district-wide contact found -- reach out directly to Bishop Union High School or Mammoth Unified School District''s Green Team / Interact Club via the school office.'),
  ((select id from counties where fips = '005'), 'Introduce a municipal/county outdoor-lighting ordinance (shielded fixtures, curfew, color-temperature limit) via the city council or board of supervisors; start with a public-comment campaign to gauge/build support before a formal proposal.', 'Send by Jan 31, 2027; natural follow-up anchor: International Dark Sky Week, Apr 2027', 'Sierra Club Mother Lode Chapter', 'sierraclub.org/mother-lode | contact form on site (no single public email found)', 'Sierra College environmental club', 'ECOS (Environmentally Concerned Organization of Students), Sierra College | SierraCollegeECOS@gmail.com'),
  ((select id from counties where fips = '007'), 'Introduce a municipal/county outdoor-lighting ordinance via the city council or board, routed through the planning or sustainability commission first; use the local hook (park/observatory/forest/program) as the opening argument.', 'Send by Nov 30, 2026; natural follow-up anchor: International Dark Sky Week / Earth Day, Apr 2027', 'Sierra Club Mother Lode Chapter (Shasta-area groups)', 'sierraclub.org/mother-lode | contact form on site (no single public email found)', 'CSU Chico (Chico State) sustainability / astronomy club', 'AS Sustainability, CSU Chico | as_sustainability@csuchico.edu | (530) 898-6677'),
  ((select id from counties where fips = '009'), 'Introduce a municipal/county outdoor-lighting ordinance (shielded fixtures, curfew, color-temperature limit) via the city council or board of supervisors; start with a public-comment campaign to gauge/build support before a formal proposal.', 'Send by Jan 31, 2027; natural follow-up anchor: International Dark Sky Week, Apr 2027', 'Sierra Club Mother Lode Chapter', 'sierraclub.org/mother-lode | contact form on site (no single public email found)', 'Sierra College environmental club', 'ECOS (Environmentally Concerned Organization of Students), Sierra College | SierraCollegeECOS@gmail.com'),
  ((select id from counties where fips = '011'), 'Introduce a municipal/county outdoor-lighting ordinance (shielded fixtures, curfew, color-temperature limit) via the city council or board of supervisors; start with a public-comment campaign to gauge/build support before a formal proposal.', 'Send by Apr 2027, timed to International Dark Sky Week (lower-urgency batch)', 'Sierra Club Mother Lode Chapter (Shasta-area groups)', 'sierraclub.org/mother-lode | contact form on site (no single public email found)', 'CSU Chico (Chico State) sustainability / astronomy club', 'AS Sustainability, CSU Chico | as_sustainability@csuchico.edu | (530) 898-6677'),
  ((select id from counties where fips = '013'), 'Introduce a municipal/county outdoor-lighting ordinance (shielded fixtures, curfew, color-temperature limit) via the city council or board of supervisors; start with a public-comment campaign to gauge/build support before a formal proposal.', 'Send by Jan 31, 2027; natural follow-up anchor: International Dark Sky Week, Apr 2027', 'Sierra Club San Francisco Bay Chapter', 'sierraclub.org/sfbay | contact form on site (no single public email found)', 'UC Berkeley Students for the Exploration and Development of Space (SEDS)', 'CORRECTION: no active UC Berkeley SEDS chapter confirmed. Closest real match: Space Exploration Society at Berkeley (SESB) | sesb.berkeley.edu'),
  ((select id from counties where fips = '015'), 'Introduce a municipal/county outdoor-lighting ordinance via the city council or board, routed through the planning or sustainability commission first; use the local hook (park/observatory/forest/program) as the opening argument.', 'Send by Nov 30, 2026; natural follow-up anchor: International Dark Sky Week / Earth Day, Apr 2027', 'Sierra Club Redwood Chapter', 'sierraclub.org/redwood | contact form on site (no single public email found)', 'Cal Poly Humboldt environmental club', 'Environmental Studies (ENST) Club, Cal Poly Humboldt | enst.club@humboldt.edu'),
  ((select id from counties where fips = '017'), 'Pursue formal DarkSky International Community/Park certification and/or a municipal outdoor-lighting ordinance (shielded fixtures, 3000K or warmer color temperature, late-night curfew), citing the existing nearby designation/momentum as precedent.', 'Send by Sep 30, 2026; natural follow-up anchor: International Dark Sky Week, Apr 2027', 'Sierra Club Mother Lode Chapter', 'sierraclub.org/mother-lode | contact form on site (no single public email found)', 'Sierra Nevada University environmental club (Tahoe area)', 'CORRECTION: Sierra Nevada University closed in July 2022 and is now the Wayne L. Prim Campus of UNR. No independent student environmental club confirmed there since; nearest verified contact is UNR Lake Tahoe, (775) 831-1314, unr.edu/lake-tahoe. Consider Sierra Club Mother Lode Chapter''s Tahoe Area Group instead: sierraclub.org/mother-lode/tahoe'),
  ((select id from counties where fips = '019'), 'Pursue formal DarkSky International Community/Park certification and/or a municipal outdoor-lighting ordinance (shielded fixtures, 3000K or warmer color temperature, late-night curfew), citing the existing nearby designation/momentum as precedent.', 'Send by Sep 30, 2026; natural follow-up anchor: International Dark Sky Week, Apr 2027', 'Sierra Club Tehipite Chapter / Kern-Kaweah Chapter', 'sierraclub.org/Tehipite ; sierraclub.org/Kern-Kaweah | contact forms on each site', 'Fresno State environmental / astronomy club', 'Fresno State Sustainability Club | fresnostatesustainabilityclub@gmail.com  (NOTE: no dedicated student astronomy club found at Fresno State -- Central Valley Astronomers, a public/community club, is the region''s astronomy contact: cvafresno.org, Dave Harris, getastrodave@gmail.com)'),
  ((select id from counties where fips = '021'), 'Introduce a municipal/county outdoor-lighting ordinance (shielded fixtures, curfew, color-temperature limit) via the city council or board of supervisors; start with a public-comment campaign to gauge/build support before a formal proposal.', 'Send by Apr 2027, timed to International Dark Sky Week (lower-urgency batch)', 'Sierra Club Mother Lode Chapter (Shasta-area groups)', 'sierraclub.org/mother-lode | contact form on site (no single public email found)', 'CSU Chico (Chico State) sustainability / astronomy club', 'AS Sustainability, CSU Chico | as_sustainability@csuchico.edu | (530) 898-6677'),
  ((select id from counties where fips = '023'), 'Introduce a municipal/county outdoor-lighting ordinance via the city council or board, routed through the planning or sustainability commission first; use the local hook (park/observatory/forest/program) as the opening argument.', 'Send by Nov 30, 2026; natural follow-up anchor: International Dark Sky Week / Earth Day, Apr 2027', 'Sierra Club Redwood Chapter', 'sierraclub.org/redwood | contact form on site (no single public email found)', 'Cal Poly Humboldt environmental club', 'Environmental Studies (ENST) Club, Cal Poly Humboldt | enst.club@humboldt.edu'),
  ((select id from counties where fips = '025'), 'Introduce a municipal/county outdoor-lighting ordinance (shielded fixtures, curfew, color-temperature limit) via the city council or board of supervisors; start with a public-comment campaign to gauge/build support before a formal proposal.', 'Send by Jan 31, 2027; natural follow-up anchor: International Dark Sky Week, Apr 2027', 'Sierra Club San Diego Chapter', 'sandiegosierraclub.org | contact form on site (no single public email found)', 'Imperial Valley College sustainability club', 'No dedicated student sustainability/environmental club found. General campus contact: Imperial Valley College, (760) 352-8320, imperial.edu/campus-life/campus-clubs.html'),
  ((select id from counties where fips = '027'), 'Pursue formal DarkSky International Community/Park certification and/or a municipal outdoor-lighting ordinance (shielded fixtures, 3000K or warmer color temperature, late-night curfew), citing the existing nearby designation/momentum as precedent.', 'Send by Sep 30, 2026; natural follow-up anchor: International Dark Sky Week, Apr 2027', 'Sierra Club Toiyabe Chapter', 'sierraclub.org/Toiyabe | contact form on site (no single public email found)', 'Local high school environmental club (Bishop / Mammoth area)', 'No single verifiable district-wide contact found -- reach out directly to Bishop Union High School or Mammoth Unified School District''s Green Team / Interact Club via the school office.'),
  ((select id from counties where fips = '029'), 'Introduce a municipal/county outdoor-lighting ordinance via the city council or board, routed through the planning or sustainability commission first; use the local hook (park/observatory/forest/program) as the opening argument.', 'Send by Nov 30, 2026; natural follow-up anchor: International Dark Sky Week / Earth Day, Apr 2027', 'Sierra Club Tehipite Chapter / Kern-Kaweah Chapter', 'sierraclub.org/Tehipite ; sierraclub.org/Kern-Kaweah | contact forms on each site', 'Fresno State environmental / astronomy club', 'Fresno State Sustainability Club | fresnostatesustainabilityclub@gmail.com  (NOTE: no dedicated student astronomy club found at Fresno State -- Central Valley Astronomers, a public/community club, is the region''s astronomy contact: cvafresno.org, Dave Harris, getastrodave@gmail.com)'),
  ((select id from counties where fips = '031'), 'Introduce a municipal/county outdoor-lighting ordinance (shielded fixtures, curfew, color-temperature limit) via the city council or board of supervisors; start with a public-comment campaign to gauge/build support before a formal proposal.', 'Send by Jan 31, 2027; natural follow-up anchor: International Dark Sky Week, Apr 2027', 'Sierra Club Tehipite Chapter / Kern-Kaweah Chapter', 'sierraclub.org/Tehipite ; sierraclub.org/Kern-Kaweah | contact forms on each site', 'Fresno State environmental / astronomy club', 'Fresno State Sustainability Club | fresnostatesustainabilityclub@gmail.com  (NOTE: no dedicated student astronomy club found at Fresno State -- Central Valley Astronomers, a public/community club, is the region''s astronomy contact: cvafresno.org, Dave Harris, getastrodave@gmail.com)'),
  ((select id from counties where fips = '033'), 'Introduce a municipal/county outdoor-lighting ordinance (shielded fixtures, curfew, color-temperature limit) via the city council or board of supervisors; start with a public-comment campaign to gauge/build support before a formal proposal.', 'Send by Jan 31, 2027; natural follow-up anchor: International Dark Sky Week, Apr 2027', 'Sierra Club Redwood Chapter', 'sierraclub.org/redwood | contact form on site (no single public email found)', 'Cal Poly Humboldt environmental club', 'Environmental Studies (ENST) Club, Cal Poly Humboldt | enst.club@humboldt.edu'),
  ((select id from counties where fips = '035'), 'Introduce a municipal/county outdoor-lighting ordinance via the city council or board, routed through the planning or sustainability commission first; use the local hook (park/observatory/forest/program) as the opening argument.', 'Send by Nov 30, 2026; natural follow-up anchor: International Dark Sky Week / Earth Day, Apr 2027', 'Sierra Club Mother Lode Chapter (Shasta-area groups)', 'sierraclub.org/mother-lode | contact form on site (no single public email found)', 'CSU Chico (Chico State) sustainability / astronomy club', 'AS Sustainability, CSU Chico | as_sustainability@csuchico.edu | (530) 898-6677'),
  ((select id from counties where fips = '037'), 'Introduce a municipal/county outdoor-lighting ordinance via the city council or board, routed through the planning or sustainability commission first; use the local hook (park/observatory/forest/program) as the opening argument.', 'Send by Nov 30, 2026; natural follow-up anchor: International Dark Sky Week / Earth Day, Apr 2027', 'DarkSky LA County / DarkSky Joshua Tree (DarkSky International chapters)', 'darkskylacounty.org | lacounty@darksky.org (LA Co.); scdvainfo@gmail.com (Joshua Tree)', 'UCLA Astronomical Society', 'astrosociety.astro.ucla.edu | astrosociety@astro.ucla.edu'),
  ((select id from counties where fips = '039'), 'Introduce a municipal/county outdoor-lighting ordinance (shielded fixtures, curfew, color-temperature limit) via the city council or board of supervisors; start with a public-comment campaign to gauge/build support before a formal proposal.', 'Send by Jan 31, 2027; natural follow-up anchor: International Dark Sky Week, Apr 2027', 'Sierra Club Tehipite Chapter', 'sierraclub.org/Tehipite | contact form on site (no single public email found)', 'UC Merced sustainability / astronomy club', 'ASUCM Sustainability Commission | clubsandorgs@ucmerced.edu (general clubs office; no dedicated astronomy club confirmed)'),
  ((select id from counties where fips = '041'), 'Introduce a municipal/county outdoor-lighting ordinance via the city council or board, routed through the planning or sustainability commission first; use the local hook (park/observatory/forest/program) as the opening argument.', 'Send by Nov 30, 2026; natural follow-up anchor: International Dark Sky Week / Earth Day, Apr 2027', 'Sierra Club San Francisco Bay Chapter', 'sierraclub.org/sfbay | contact form on site (no single public email found)', 'UC Berkeley Students for the Exploration and Development of Space (SEDS)', 'CORRECTION: no active UC Berkeley SEDS chapter confirmed. Closest real match: Space Exploration Society at Berkeley (SESB) | sesb.berkeley.edu'),
  ((select id from counties where fips = '043'), 'Pursue formal DarkSky International Community/Park certification and/or a municipal outdoor-lighting ordinance (shielded fixtures, 3000K or warmer color temperature, late-night curfew), citing the existing nearby designation/momentum as precedent.', 'Send by Sep 30, 2026; natural follow-up anchor: International Dark Sky Week, Apr 2027', 'Sierra Club Tehipite Chapter', 'sierraclub.org/Tehipite | contact form on site (no single public email found)', 'UC Merced sustainability / astronomy club', 'ASUCM Sustainability Commission | clubsandorgs@ucmerced.edu (general clubs office; no dedicated astronomy club confirmed)'),
  ((select id from counties where fips = '045'), 'Introduce a municipal/county outdoor-lighting ordinance via the city council or board, routed through the planning or sustainability commission first; use the local hook (park/observatory/forest/program) as the opening argument.', 'Send by Nov 30, 2026; natural follow-up anchor: International Dark Sky Week / Earth Day, Apr 2027', 'Sierra Club Redwood Chapter', 'sierraclub.org/redwood | contact form on site (no single public email found)', 'Cal Poly Humboldt environmental club', 'Environmental Studies (ENST) Club, Cal Poly Humboldt | enst.club@humboldt.edu'),
  ((select id from counties where fips = '047'), 'Introduce a municipal/county outdoor-lighting ordinance (shielded fixtures, curfew, color-temperature limit) via the city council or board of supervisors; start with a public-comment campaign to gauge/build support before a formal proposal.', 'Send by Jan 31, 2027; natural follow-up anchor: International Dark Sky Week, Apr 2027', 'Sierra Club Mother Lode Chapter', 'sierraclub.org/mother-lode | contact form on site (no single public email found)', 'UC Davis Astronomy Club', 'ucdastronomyclub.com | Facebook: facebook.com/groups/astronomyclubucd (no single public email found; join via site announce list)'),
  ((select id from counties where fips = '049'), 'Introduce a municipal/county outdoor-lighting ordinance (shielded fixtures, curfew, color-temperature limit) via the city council or board of supervisors; start with a public-comment campaign to gauge/build support before a formal proposal.', 'Send by Apr 2027, timed to International Dark Sky Week (lower-urgency batch)', 'Sierra Club Mother Lode Chapter (Shasta-area groups)', 'sierraclub.org/mother-lode | contact form on site (no single public email found)', 'CSU Chico (Chico State) sustainability / astronomy club', 'AS Sustainability, CSU Chico | as_sustainability@csuchico.edu | (530) 898-6677'),
  ((select id from counties where fips = '051'), 'Pursue formal DarkSky International Community/Park certification and/or a municipal outdoor-lighting ordinance (shielded fixtures, 3000K or warmer color temperature, late-night curfew), citing the existing nearby designation/momentum as precedent.', 'Send by Sep 30, 2026; natural follow-up anchor: International Dark Sky Week, Apr 2027', 'Sierra Club Toiyabe Chapter', 'sierraclub.org/Toiyabe | contact form on site (no single public email found)', 'Local high school environmental club (Bishop / Mammoth area)', 'No single verifiable district-wide contact found -- reach out directly to Bishop Union High School or Mammoth Unified School District''s Green Team / Interact Club via the school office.'),
  ((select id from counties where fips = '053'), 'Pursue formal DarkSky International Community/Park certification and/or a municipal outdoor-lighting ordinance (shielded fixtures, 3000K or warmer color temperature, late-night curfew), citing the existing nearby designation/momentum as precedent.', 'Send by Sep 30, 2026; natural follow-up anchor: International Dark Sky Week, Apr 2027', 'DarkSky Central Coast (DarkSky International chapter)', 'we-watch.org/focus/save-our-stars | nancyfemerson52@gmail.com', 'Cal Poly San Luis Obispo Astronomy Club', 'Cal Poly Astronomical Society | club president via rharsey@calpoly.edu (2025-26 contact; verify current officer)'),
  ((select id from counties where fips = '055'), 'Introduce a municipal/county outdoor-lighting ordinance via the city council or board, routed through the planning or sustainability commission first; use the local hook (park/observatory/forest/program) as the opening argument.', 'Send by Nov 30, 2026; natural follow-up anchor: International Dark Sky Week / Earth Day, Apr 2027', 'Sierra Club San Francisco Bay Chapter', 'sierraclub.org/sfbay | contact form on site (no single public email found)', 'UC Berkeley Students for the Exploration and Development of Space (SEDS)', 'CORRECTION: no active UC Berkeley SEDS chapter confirmed. Closest real match: Space Exploration Society at Berkeley (SESB) | sesb.berkeley.edu'),
  ((select id from counties where fips = '057'), 'Pursue formal DarkSky International Community/Park certification and/or a municipal outdoor-lighting ordinance (shielded fixtures, 3000K or warmer color temperature, late-night curfew), citing the existing nearby designation/momentum as precedent.', 'Send by Sep 30, 2026; natural follow-up anchor: International Dark Sky Week, Apr 2027', 'Sierra Club Mother Lode Chapter', 'sierraclub.org/mother-lode | contact form on site (no single public email found)', 'Sierra College environmental club', 'ECOS (Environmentally Concerned Organization of Students), Sierra College | SierraCollegeECOS@gmail.com'),
  ((select id from counties where fips = '059'), 'Introduce a municipal/county outdoor-lighting ordinance via the city council or board, routed through the planning or sustainability commission first; use the local hook (park/observatory/forest/program) as the opening argument.', 'Send by Nov 30, 2026; natural follow-up anchor: International Dark Sky Week / Earth Day, Apr 2027', 'DarkSky LA County / DarkSky Joshua Tree (DarkSky International chapters)', 'darkskylacounty.org | lacounty@darksky.org (LA Co.); scdvainfo@gmail.com (Joshua Tree)', 'UCLA Astronomical Society', 'astrosociety.astro.ucla.edu | astrosociety@astro.ucla.edu'),
  ((select id from counties where fips = '061'), 'Introduce a municipal/county outdoor-lighting ordinance via the city council or board, routed through the planning or sustainability commission first; use the local hook (park/observatory/forest/program) as the opening argument.', 'Send by Nov 30, 2026; natural follow-up anchor: International Dark Sky Week / Earth Day, Apr 2027', 'Sierra Club Mother Lode Chapter', 'sierraclub.org/mother-lode | contact form on site (no single public email found)', 'Sierra Nevada University environmental club (Tahoe area)', 'CORRECTION: Sierra Nevada University closed in July 2022 and is now the Wayne L. Prim Campus of UNR. No independent student environmental club confirmed there since; nearest verified contact is UNR Lake Tahoe, (775) 831-1314, unr.edu/lake-tahoe. Consider Sierra Club Mother Lode Chapter''s Tahoe Area Group instead: sierraclub.org/mother-lode/tahoe'),
  ((select id from counties where fips = '063'), 'Introduce a municipal/county outdoor-lighting ordinance (shielded fixtures, curfew, color-temperature limit) via the city council or board of supervisors; start with a public-comment campaign to gauge/build support before a formal proposal.', 'Send by Jan 31, 2027; natural follow-up anchor: International Dark Sky Week, Apr 2027', 'Sierra Club Mother Lode Chapter (Shasta-area groups)', 'sierraclub.org/mother-lode | contact form on site (no single public email found)', 'CSU Chico (Chico State) sustainability / astronomy club', 'AS Sustainability, CSU Chico | as_sustainability@csuchico.edu | (530) 898-6677'),
  ((select id from counties where fips = '065'), 'Introduce a municipal/county outdoor-lighting ordinance via the city council or board, routed through the planning or sustainability commission first; use the local hook (park/observatory/forest/program) as the opening argument.', 'Send by Nov 30, 2026; natural follow-up anchor: International Dark Sky Week / Earth Day, Apr 2027', 'DarkSky LA County / DarkSky Joshua Tree (DarkSky International chapters)', 'darkskylacounty.org | lacounty@darksky.org (LA Co.); scdvainfo@gmail.com (Joshua Tree)', 'UCLA Astronomical Society', 'astrosociety.astro.ucla.edu | astrosociety@astro.ucla.edu'),
  ((select id from counties where fips = '067'), 'Pursue formal DarkSky International Community/Park certification and/or a municipal outdoor-lighting ordinance (shielded fixtures, 3000K or warmer color temperature, late-night curfew), citing the existing nearby designation/momentum as precedent.', 'Send by Sep 30, 2026; natural follow-up anchor: International Dark Sky Week, Apr 2027', 'Sierra Club Mother Lode Chapter', 'sierraclub.org/mother-lode | contact form on site (no single public email found)', 'UC Davis Astronomy Club', 'ucdastronomyclub.com | Facebook: facebook.com/groups/astronomyclubucd (no single public email found; join via site announce list)'),
  ((select id from counties where fips = '069'), 'Introduce a municipal/county outdoor-lighting ordinance (shielded fixtures, curfew, color-temperature limit) via the city council or board of supervisors; start with a public-comment campaign to gauge/build support before a formal proposal.', 'Send by Jan 31, 2027; natural follow-up anchor: International Dark Sky Week, Apr 2027', 'DarkSky Central Coast (DarkSky International chapter)', 'we-watch.org/focus/save-our-stars | nancyfemerson52@gmail.com', 'Cal Poly San Luis Obispo Astronomy Club', 'Cal Poly Astronomical Society | club president via rharsey@calpoly.edu (2025-26 contact; verify current officer)'),
  ((select id from counties where fips = '071'), 'Pursue formal DarkSky International Community/Park certification and/or a municipal outdoor-lighting ordinance (shielded fixtures, 3000K or warmer color temperature, late-night curfew), citing the existing nearby designation/momentum as precedent.', 'Send by Sep 30, 2026; natural follow-up anchor: International Dark Sky Week, Apr 2027', 'DarkSky LA County / DarkSky Joshua Tree (DarkSky International chapters)', 'darkskylacounty.org | lacounty@darksky.org (LA Co.); scdvainfo@gmail.com (Joshua Tree)', 'UCLA Astronomical Society', 'astrosociety.astro.ucla.edu | astrosociety@astro.ucla.edu'),
  ((select id from counties where fips = '073'), 'Build directly on the existing ordinance: thank the named official publicly, ask them to help extend/strengthen it, and support enforcement via public comment.', 'Send by Aug 15, 2026 (momentum is fresh -- don''t wait)', 'DarkSky San Diego County (DarkSky International chapter)', 'darkskysandiego.org | info@DarkSkySanDiego.org', 'UC San Diego Astronomy Club', 'sites.google.com/view/astronomyclubucsandiego | astronomyucsd@gmail.com'),
  ((select id from counties where fips = '075'), 'Introduce a municipal/county outdoor-lighting ordinance via the city council or board, routed through the planning or sustainability commission first; use the local hook (park/observatory/forest/program) as the opening argument.', 'Send by Nov 30, 2026; natural follow-up anchor: International Dark Sky Week / Earth Day, Apr 2027', 'Sierra Club San Francisco Bay Chapter', 'sierraclub.org/sfbay | contact form on site (no single public email found)', 'UC Berkeley Students for the Exploration and Development of Space (SEDS)', 'CORRECTION: no active UC Berkeley SEDS chapter confirmed. Closest real match: Space Exploration Society at Berkeley (SESB) | sesb.berkeley.edu'),
  ((select id from counties where fips = '077'), 'Introduce a municipal/county outdoor-lighting ordinance (shielded fixtures, curfew, color-temperature limit) via the city council or board of supervisors; start with a public-comment campaign to gauge/build support before a formal proposal.', 'Send by Jan 31, 2027; natural follow-up anchor: International Dark Sky Week, Apr 2027', 'Sierra Club Mother Lode Chapter', 'sierraclub.org/mother-lode | contact form on site (no single public email found)', 'UC Davis Astronomy Club', 'ucdastronomyclub.com | Facebook: facebook.com/groups/astronomyclubucd (no single public email found; join via site announce list)'),
  ((select id from counties where fips = '079'), 'Pursue formal DarkSky International Community/Park certification and/or a municipal outdoor-lighting ordinance (shielded fixtures, 3000K or warmer color temperature, late-night curfew), citing the existing nearby designation/momentum as precedent.', 'Send by Sep 30, 2026; natural follow-up anchor: International Dark Sky Week, Apr 2027', 'DarkSky Central Coast (DarkSky International chapter)', 'we-watch.org/focus/save-our-stars | nancyfemerson52@gmail.com', 'Cal Poly San Luis Obispo Astronomy Club', 'Cal Poly Astronomical Society | club president via rharsey@calpoly.edu (2025-26 contact; verify current officer)'),
  ((select id from counties where fips = '081'), 'Pursue formal DarkSky International Community/Park certification and/or a municipal outdoor-lighting ordinance (shielded fixtures, 3000K or warmer color temperature, late-night curfew), citing the existing nearby designation/momentum as precedent.', 'Send by Sep 30, 2026; natural follow-up anchor: International Dark Sky Week, Apr 2027', 'DarkSky Santa Cruz (DarkSky International chapter)', 'santacruzdarksky.org | idasantacruzca@gmail.com', 'Stanford Students for the Exploration and Development of Space (SEDS)', 'CORRECTION: no active Stanford SEDS chapter confirmed. Closest real match: Stanford Student Space Initiative (SSI) | ssi.stanford.edu'),
  ((select id from counties where fips = '083'), 'Pursue formal DarkSky International Community/Park certification and/or a municipal outdoor-lighting ordinance (shielded fixtures, 3000K or warmer color temperature, late-night curfew), citing the existing nearby designation/momentum as precedent.', 'Send by Sep 30, 2026; natural follow-up anchor: International Dark Sky Week, Apr 2027', 'DarkSky Central Coast (DarkSky International chapter)', 'we-watch.org/focus/save-our-stars | nancyfemerson52@gmail.com', 'Cal Poly San Luis Obispo Astronomy Club', 'Cal Poly Astronomical Society | club president via rharsey@calpoly.edu (2025-26 contact; verify current officer)'),
  ((select id from counties where fips = '085'), 'Build directly on the existing ordinance: thank the named official publicly, ask them to help extend/strengthen it, and support enforcement via public comment.', 'Send by Aug 15, 2026 (momentum is fresh -- don''t wait)', 'DarkSky Santa Cruz (DarkSky International chapter)', 'santacruzdarksky.org | idasantacruzca@gmail.com', 'Stanford Students for the Exploration and Development of Space (SEDS)', 'CORRECTION: no active Stanford SEDS chapter confirmed. Closest real match: Stanford Student Space Initiative (SSI) | ssi.stanford.edu'),
  ((select id from counties where fips = '087'), 'Pursue formal DarkSky International Community/Park certification and/or a municipal outdoor-lighting ordinance (shielded fixtures, 3000K or warmer color temperature, late-night curfew), citing the existing nearby designation/momentum as precedent.', 'Send by Sep 30, 2026; natural follow-up anchor: International Dark Sky Week, Apr 2027', 'DarkSky Santa Cruz (DarkSky International chapter)', 'santacruzdarksky.org | idasantacruzca@gmail.com', 'Stanford Students for the Exploration and Development of Space (SEDS)', 'CORRECTION: no active Stanford SEDS chapter confirmed. Closest real match: Stanford Student Space Initiative (SSI) | ssi.stanford.edu'),
  ((select id from counties where fips = '089'), 'Introduce a municipal/county outdoor-lighting ordinance (shielded fixtures, curfew, color-temperature limit) via the city council or board of supervisors; start with a public-comment campaign to gauge/build support before a formal proposal.', 'Send by Jan 31, 2027; natural follow-up anchor: International Dark Sky Week, Apr 2027', 'Sierra Club Mother Lode Chapter (Shasta-area groups)', 'sierraclub.org/mother-lode | contact form on site (no single public email found)', 'CSU Chico (Chico State) sustainability / astronomy club', 'AS Sustainability, CSU Chico | as_sustainability@csuchico.edu | (530) 898-6677'),
  ((select id from counties where fips = '091'), 'Introduce a municipal/county outdoor-lighting ordinance (shielded fixtures, curfew, color-temperature limit) via the city council or board of supervisors; start with a public-comment campaign to gauge/build support before a formal proposal.', 'Send by Apr 2027, timed to International Dark Sky Week (lower-urgency batch)', 'Sierra Club Mother Lode Chapter', 'sierraclub.org/mother-lode | contact form on site (no single public email found)', 'Sierra College environmental club', 'ECOS (Environmentally Concerned Organization of Students), Sierra College | SierraCollegeECOS@gmail.com'),
  ((select id from counties where fips = '093'), 'Introduce a municipal/county outdoor-lighting ordinance via the city council or board, routed through the planning or sustainability commission first; use the local hook (park/observatory/forest/program) as the opening argument.', 'Send by Nov 30, 2026; natural follow-up anchor: International Dark Sky Week / Earth Day, Apr 2027', 'Sierra Club Mother Lode Chapter (Shasta-area groups)', 'sierraclub.org/mother-lode | contact form on site (no single public email found)', 'CSU Chico (Chico State) sustainability / astronomy club', 'AS Sustainability, CSU Chico | as_sustainability@csuchico.edu | (530) 898-6677'),
  ((select id from counties where fips = '095'), 'Introduce a municipal/county outdoor-lighting ordinance (shielded fixtures, curfew, color-temperature limit) via the city council or board of supervisors; start with a public-comment campaign to gauge/build support before a formal proposal.', 'Send by Jan 31, 2027; natural follow-up anchor: International Dark Sky Week, Apr 2027', 'Sierra Club San Francisco Bay Chapter', 'sierraclub.org/sfbay | contact form on site (no single public email found)', 'UC Berkeley Students for the Exploration and Development of Space (SEDS)', 'CORRECTION: no active UC Berkeley SEDS chapter confirmed. Closest real match: Space Exploration Society at Berkeley (SESB) | sesb.berkeley.edu'),
  ((select id from counties where fips = '097'), 'Introduce a municipal/county outdoor-lighting ordinance via the city council or board, routed through the planning or sustainability commission first; use the local hook (park/observatory/forest/program) as the opening argument.', 'Send by Nov 30, 2026; natural follow-up anchor: International Dark Sky Week / Earth Day, Apr 2027', 'Sierra Club Redwood Chapter', 'sierraclub.org/redwood | contact form on site (no single public email found)', 'Cal Poly Humboldt environmental club', 'Environmental Studies (ENST) Club, Cal Poly Humboldt | enst.club@humboldt.edu'),
  ((select id from counties where fips = '099'), 'Introduce a municipal/county outdoor-lighting ordinance (shielded fixtures, curfew, color-temperature limit) via the city council or board of supervisors; start with a public-comment campaign to gauge/build support before a formal proposal.', 'Send by Jan 31, 2027; natural follow-up anchor: International Dark Sky Week, Apr 2027', 'Sierra Club Mother Lode Chapter', 'sierraclub.org/mother-lode | contact form on site (no single public email found)', 'UC Davis Astronomy Club', 'ucdastronomyclub.com | Facebook: facebook.com/groups/astronomyclubucd (no single public email found; join via site announce list)'),
  ((select id from counties where fips = '101'), 'Introduce a municipal/county outdoor-lighting ordinance (shielded fixtures, curfew, color-temperature limit) via the city council or board of supervisors; start with a public-comment campaign to gauge/build support before a formal proposal.', 'Send by Jan 31, 2027; natural follow-up anchor: International Dark Sky Week, Apr 2027', 'Sierra Club Mother Lode Chapter', 'sierraclub.org/mother-lode | contact form on site (no single public email found)', 'UC Davis Astronomy Club', 'ucdastronomyclub.com | Facebook: facebook.com/groups/astronomyclubucd (no single public email found; join via site announce list)'),
  ((select id from counties where fips = '103'), 'Introduce a municipal/county outdoor-lighting ordinance (shielded fixtures, curfew, color-temperature limit) via the city council or board of supervisors; start with a public-comment campaign to gauge/build support before a formal proposal.', 'Send by Jan 31, 2027; natural follow-up anchor: International Dark Sky Week, Apr 2027', 'Sierra Club Mother Lode Chapter (Shasta-area groups)', 'sierraclub.org/mother-lode | contact form on site (no single public email found)', 'CSU Chico (Chico State) sustainability / astronomy club', 'AS Sustainability, CSU Chico | as_sustainability@csuchico.edu | (530) 898-6677'),
  ((select id from counties where fips = '105'), 'Introduce a municipal/county outdoor-lighting ordinance (shielded fixtures, curfew, color-temperature limit) via the city council or board of supervisors; start with a public-comment campaign to gauge/build support before a formal proposal.', 'Send by Apr 2027, timed to International Dark Sky Week (lower-urgency batch)', 'Sierra Club Redwood Chapter', 'sierraclub.org/redwood | contact form on site (no single public email found)', 'Cal Poly Humboldt environmental club', 'Environmental Studies (ENST) Club, Cal Poly Humboldt | enst.club@humboldt.edu'),
  ((select id from counties where fips = '107'), 'Pursue formal DarkSky International Community/Park certification and/or a municipal outdoor-lighting ordinance (shielded fixtures, 3000K or warmer color temperature, late-night curfew), citing the existing nearby designation/momentum as precedent.', 'Send by Sep 30, 2026; natural follow-up anchor: International Dark Sky Week, Apr 2027', 'Sierra Club Tehipite Chapter / Kern-Kaweah Chapter', 'sierraclub.org/Tehipite ; sierraclub.org/Kern-Kaweah | contact forms on each site', 'Fresno State environmental / astronomy club', 'Fresno State Sustainability Club | fresnostatesustainabilityclub@gmail.com  (NOTE: no dedicated student astronomy club found at Fresno State -- Central Valley Astronomers, a public/community club, is the region''s astronomy contact: cvafresno.org, Dave Harris, getastrodave@gmail.com)'),
  ((select id from counties where fips = '109'), 'Introduce a municipal/county outdoor-lighting ordinance via the city council or board, routed through the planning or sustainability commission first; use the local hook (park/observatory/forest/program) as the opening argument.', 'Send by Nov 30, 2026; natural follow-up anchor: International Dark Sky Week / Earth Day, Apr 2027', 'Sierra Club Tehipite Chapter', 'sierraclub.org/Tehipite | contact form on site (no single public email found)', 'UC Merced sustainability / astronomy club', 'ASUCM Sustainability Commission | clubsandorgs@ucmerced.edu (general clubs office; no dedicated astronomy club confirmed)'),
  ((select id from counties where fips = '111'), 'Introduce a municipal/county outdoor-lighting ordinance via the city council or board, routed through the planning or sustainability commission first; use the local hook (park/observatory/forest/program) as the opening argument.', 'Send by Nov 30, 2026; natural follow-up anchor: International Dark Sky Week / Earth Day, Apr 2027', 'DarkSky Central Coast (DarkSky International chapter)', 'we-watch.org/focus/save-our-stars | nancyfemerson52@gmail.com', 'Cal Poly San Luis Obispo Astronomy Club', 'Cal Poly Astronomical Society | club president via rharsey@calpoly.edu (2025-26 contact; verify current officer)'),
  ((select id from counties where fips = '113'), 'Introduce a municipal/county outdoor-lighting ordinance via the city council or board, routed through the planning or sustainability commission first; use the local hook (park/observatory/forest/program) as the opening argument.', 'Send by Nov 30, 2026; natural follow-up anchor: International Dark Sky Week / Earth Day, Apr 2027', 'Sierra Club Mother Lode Chapter', 'sierraclub.org/mother-lode | contact form on site (no single public email found)', 'UC Davis Astronomy Club', 'ucdastronomyclub.com | Facebook: facebook.com/groups/astronomyclubucd (no single public email found; join via site announce list)'),
  ((select id from counties where fips = '115'), 'Introduce a municipal/county outdoor-lighting ordinance (shielded fixtures, curfew, color-temperature limit) via the city council or board of supervisors; start with a public-comment campaign to gauge/build support before a formal proposal.', 'Send by Jan 31, 2027; natural follow-up anchor: International Dark Sky Week, Apr 2027', 'Sierra Club Mother Lode Chapter', 'sierraclub.org/mother-lode | contact form on site (no single public email found)', 'UC Davis Astronomy Club', 'ucdastronomyclub.com | Facebook: facebook.com/groups/astronomyclubucd (no single public email found; join via site announce list)')
on conflict (county_id) do update set
  method = excluded.method, deadline = excluded.deadline,
  prof_org = excluded.prof_org, prof_contact = excluded.prof_contact,
  student_org = excluded.student_org, student_contact = excluded.student_contact,
  updated_at = now();

-- Researched council members / local champions
insert into council_contacts (county_id, name, title, evidence, source_url) values
  ((select id from counties where fips = '085'), 'Greer Stone', 'Palo Alto City Council Member', 'Publicly framed the ordinance as balancing public safety and environmental stewardship during the Dec 2025 vote.', 'https://www.paloaltoonline.com/environment/2025/12/09/palo-alto-approves-dark-sky-ordinance-sets-earlier-curfew/'),
  ((select id from counties where fips = '073'), 'Jim Desmond', 'San Diego County Supervisor, District 5 (Borrego Springs)', 'Publicly said he would ''gladly support'' the dark sky ordinance, citing dark skies as a major draw for Borrego Springs.', 'https://www.eastcountymagazine.org/supervisors-approve-dark-skies-protections-julian-area-and-borrego-springs'),
  ((select id from counties where fips = '073'), 'Joel Anderson', 'San Diego County Supervisor, District 2 (includes Julian)', 'Current supervisor for the district covering Julian, one of the county''s two designated Dark Sky Communities (predecessor Supervisor Dianne Jacob championed the original 2020 designation).', 'https://www.supervisorjoelanderson.com/content/d2/us/en/about/district2.html');

-- Partner organizations, plus the "general public" umbrella org.
-- The umbrella org is a normal row with no special casing (spec §3).
insert into organizations (name, slug, kind, region, is_umbrella, approved) values
  ('California Starlight Volunteers', 'california-starlight-volunteers', 'general_public', null, true, true),
  ('Sierra Club San Francisco Bay Chapter', 'sierra-club-san-francisco-bay-chapter', 'sierra_club'::org_kind, 'bay', false, true),
  ('Golden Gate Audubon Society', 'golden-gate-audubon-society', 'audubon'::org_kind, 'bay', false, true),
  ('Chabot Space & Science Center astronomy program (Oakland)', 'chabot-space-science-center-astronomy-program-oakland', 'astronomy'::org_kind, 'bay', false, true),
  ('UC Berkeley Students for the Exploration and Development of Space (SEDS)', 'uc-berkeley-students-for-the-exploration-and-development-of-space-seds', 'student'::org_kind, 'bay', false, true),
  ('Sunrise Movement Bay Area hub', 'sunrise-movement-bay-area-hub', 'student'::org_kind, 'bay', false, true),
  ('Sierra Club Loma Prieta Chapter', 'sierra-club-loma-prieta-chapter', 'sierra_club'::org_kind, 'southbay', false, true),
  ('DarkSky Santa Cruz (chapter of DarkSky International)', 'darksky-santa-cruz-chapter-of-darksky-international', 'darksky'::org_kind, 'southbay', false, true),
  ('Santa Clara Valley Audubon Society', 'santa-clara-valley-audubon-society', 'audubon'::org_kind, 'southbay', false, true),
  ('San Jose Astronomical Association / Peninsula Astronomical Society', 'san-jose-astronomical-association-peninsula-astronomical-society', 'astronomy'::org_kind, 'southbay', false, true),
  ('Stanford Students for the Exploration and Development of Space (SEDS)', 'stanford-students-for-the-exploration-and-development-of-space-seds', 'student'::org_kind, 'southbay', false, true),
  ('San Jose State University Astronomy Club', 'san-jose-state-university-astronomy-club', 'student'::org_kind, 'southbay', false, true),
  ('Sierra Club Santa Lucia Chapter (San Luis Obispo) / Santa Barbara-Ventura Chapter / Ventana Chapter (Monterey)', 'sierra-club-santa-lucia-chapter-san-luis-obispo-santa-barbara-ventura-chapter-ventana-chapter-monterey', 'sierra_club'::org_kind, 'centralcoast', false, true),
  ('DarkSky Central Coast (chapter of DarkSky International)', 'darksky-central-coast-chapter-of-darksky-international', 'darksky'::org_kind, 'centralcoast', false, true),
  ('Morro Coast Audubon Society / Santa Barbara Audubon Society', 'morro-coast-audubon-society-santa-barbara-audubon-society', 'audubon'::org_kind, 'centralcoast', false, true),
  ('Central Coast Astronomical Society', 'central-coast-astronomical-society', 'astronomy'::org_kind, 'centralcoast', false, true),
  ('Cal Poly San Luis Obispo Astronomy Club', 'cal-poly-san-luis-obispo-astronomy-club', 'student'::org_kind, 'centralcoast', false, true),
  ('UC Santa Barbara Astronomy Club', 'uc-santa-barbara-astronomy-club', 'student'::org_kind, 'centralcoast', false, true),
  ('Sierra Club Angeles Chapter (LA/Orange) / San Gorgonio Chapter (Riverside/San Bernardino)', 'sierra-club-angeles-chapter-la-orange-san-gorgonio-chapter-riverside-san-bernardino', 'sierra_club'::org_kind, 'socal', false, true),
  ('DarkSky LA County / DarkSky Joshua Tree (chapters of DarkSky International)', 'darksky-la-county-darksky-joshua-tree-chapters-of-darksky-international', 'darksky'::org_kind, 'socal', false, true),
  ('Los Angeles Audubon Society / Sea and Sage Audubon Society (Orange Co.)', 'los-angeles-audubon-society-sea-and-sage-audubon-society-orange-co', 'audubon'::org_kind, 'socal', false, true),
  ('Los Angeles Astronomical Society / Orange County Astronomers', 'los-angeles-astronomical-society-orange-county-astronomers', 'astronomy'::org_kind, 'socal', false, true),
  ('UCLA Astronomical Society', 'ucla-astronomical-society', 'student'::org_kind, 'socal', false, true),
  ('Caltech Astronomy Club', 'caltech-astronomy-club', 'student'::org_kind, 'socal', false, true),
  ('Sierra Club San Diego Chapter', 'sierra-club-san-diego-chapter', 'sierra_club'::org_kind, 'sandiego', false, true),
  ('DarkSky San Diego County (chapter of DarkSky International)', 'darksky-san-diego-county-chapter-of-darksky-international', 'darksky'::org_kind, 'sandiego', false, true),
  ('San Diego Audubon Society', 'san-diego-audubon-society', 'audubon'::org_kind, 'sandiego', false, true),
  ('San Diego Astronomy Association', 'san-diego-astronomy-association', 'astronomy'::org_kind, 'sandiego', false, true),
  ('UC San Diego Astronomy Club', 'uc-san-diego-astronomy-club', 'student'::org_kind, 'sandiego', false, true),
  ('San Diego Youth Climate Strike / Sunrise Movement San Diego', 'san-diego-youth-climate-strike-sunrise-movement-san-diego', 'student'::org_kind, 'sandiego', false, true),
  ('Sierra Club Mother Lode Chapter', 'sierra-club-mother-lode-chapter', 'sierra_club'::org_kind, null, false, true),
  ('Sacramento Audubon Society / Yolo Audubon Society', 'sacramento-audubon-society-yolo-audubon-society', 'audubon'::org_kind, 'centralvalley_n', false, true),
  ('Sacramento Valley Astronomical Society (SVAS)', 'sacramento-valley-astronomical-society-svas', 'astronomy'::org_kind, 'centralvalley_n', false, true),
  ('UC Davis Astronomy Club', 'uc-davis-astronomy-club', 'student'::org_kind, 'centralvalley_n', false, true),
  ('Sunrise Movement Sacramento hub', 'sunrise-movement-sacramento-hub', 'student'::org_kind, 'centralvalley_n', false, true),
  ('Sierra Club Tehipite Chapter (Fresno/Madera) / Kern-Kaweah Chapter (Kern/Tulare)', 'sierra-club-tehipite-chapter-fresno-madera-kern-kaweah-chapter-kern-tulare', 'sierra_club'::org_kind, 'centralvalley_s', false, true),
  ('Fresno Audubon Society / Kern Audubon Society', 'fresno-audubon-society-kern-audubon-society', 'audubon'::org_kind, 'centralvalley_s', false, true),
  ('Central Valley Astronomers (Fresno)', 'central-valley-astronomers-fresno', 'astronomy'::org_kind, 'centralvalley_s', false, true),
  ('Fresno State environmental / astronomy club', 'fresno-state-environmental-astronomy-club', 'student'::org_kind, 'centralvalley_s', false, true),
  ('CSU Bakersfield sustainability club', 'csu-bakersfield-sustainability-club', 'student'::org_kind, 'centralvalley_s', false, true),
  ('Sierra Foothills Audubon Society / Central Sierra Audubon Society', 'sierra-foothills-audubon-society-central-sierra-audubon-society', 'audubon'::org_kind, 'sierra_gold', false, true),
  ('Nevada County / Placer astronomy groups (Northern California Astronomy resource network)', 'nevada-county-placer-astronomy-groups-northern-california-astronomy-resource-network', 'astronomy'::org_kind, 'sierra_gold', false, true),
  ('Sierra College environmental club', 'sierra-college-environmental-club', 'student'::org_kind, 'sierra_gold', false, true),
  ('Local Sunrise Movement / high school Green Team', 'local-sunrise-movement-high-school-green-team', 'student'::org_kind, 'sierra_gold', false, true),
  ('Sierra Club Toiyabe Chapter (covers the CA Eastern Sierra and Nevada)', 'sierra-club-toiyabe-chapter-covers-the-ca-eastern-sierra-and-nevada', 'sierra_club'::org_kind, 'easternsierra', false, true),
  ('Eastern Sierra Audubon Society', 'eastern-sierra-audubon-society', 'audubon'::org_kind, 'easternsierra', false, true),
  ('Eastern Sierra / Death Valley astronomy & stargazing groups', 'eastern-sierra-death-valley-astronomy-stargazing-groups', 'astronomy'::org_kind, 'easternsierra', false, true),
  ('Local high school environmental club (Bishop / Mammoth area)', 'local-high-school-environmental-club-bishop-mammoth-area', 'student'::org_kind, 'easternsierra', false, true),
  ('Sierra Club Tehipite Chapter (Mariposa/Tuolumne/Madera)', 'sierra-club-tehipite-chapter-mariposa-tuolumne-madera', 'sierra_club'::org_kind, 'yosemite_sierra', false, true),
  ('Yosemite Area Audubon Society', 'yosemite-area-audubon-society', 'audubon'::org_kind, 'yosemite_sierra', false, true),
  ('Under Canvas Yosemite / Yosemite Conservancy night-sky programs', 'under-canvas-yosemite-yosemite-conservancy-night-sky-programs', 'astronomy'::org_kind, 'yosemite_sierra', false, true),
  ('UC Merced sustainability / astronomy club', 'uc-merced-sustainability-astronomy-club', 'student'::org_kind, 'yosemite_sierra', false, true),
  ('Sierra Club Redwood Chapter', 'sierra-club-redwood-chapter', 'sierra_club'::org_kind, 'northcoast', false, true),
  ('Redwood Region Audubon Society (Humboldt) / Mendocino Coast Audubon Society', 'redwood-region-audubon-society-humboldt-mendocino-coast-audubon-society', 'audubon'::org_kind, 'northcoast', false, true),
  ('Humboldt-area amateur astronomy group', 'humboldt-area-amateur-astronomy-group', 'astronomy'::org_kind, 'northcoast', false, true),
  ('Cal Poly Humboldt environmental club', 'cal-poly-humboldt-environmental-club', 'student'::org_kind, 'northcoast', false, true),
  ('Local Sunrise Movement hub', 'local-sunrise-movement-hub', 'student'::org_kind, 'northcoast', false, true),
  ('Sierra Club Mother Lode Chapter (Shasta-area groups)', 'sierra-club-mother-lode-chapter-shasta-area-groups', 'sierra_club'::org_kind, 'farnorth', false, true),
  ('Wintu Audubon Society (Shasta) / Altacal Audubon Society (Butte/Glenn/Tehama)', 'wintu-audubon-society-shasta-altacal-audubon-society-butte-glenn-tehama', 'audubon'::org_kind, 'farnorth', false, true),
  ('Shasta area amateur astronomy club', 'shasta-area-amateur-astronomy-club', 'astronomy'::org_kind, 'farnorth', false, true),
  ('CSU Chico (Chico State) sustainability / astronomy club', 'csu-chico-chico-state-sustainability-astronomy-club', 'student'::org_kind, 'farnorth', false, true),
  ('Sierra Foothills Audubon Society', 'sierra-foothills-audubon-society', 'audubon'::org_kind, 'tahoe', false, true),
  ('Tahoe area amateur astronomy / Truckee Donner Land Trust night-sky programs', 'tahoe-area-amateur-astronomy-truckee-donner-land-trust-night-sky-programs', 'astronomy'::org_kind, 'tahoe', false, true),
  ('Sierra Nevada University environmental club (Tahoe area)', 'sierra-nevada-university-environmental-club-tahoe-area', 'student'::org_kind, 'tahoe', false, true),
  ('Sierra Club San Diego Chapter (Imperial Co. is in its territory)', 'sierra-club-san-diego-chapter-imperial-co-is-in-its-territory', 'sierra_club'::org_kind, 'imperial', false, true),
  ('Kern/Salton Sea area Audubon contacts (Sea & Sage Audubon Salton Sea program)', 'kern-salton-sea-area-audubon-contacts-sea-sage-audubon-salton-sea-program', 'audubon'::org_kind, 'imperial', false, true),
  ('San Diego Astronomy Association (nearest active society)', 'san-diego-astronomy-association-nearest-active-society', 'astronomy'::org_kind, 'imperial', false, true),
  ('Imperial Valley College sustainability club', 'imperial-valley-college-sustainability-club', 'student'::org_kind, 'imperial', false, true)
on conflict (name) do nothing;

-- Which orgs cover which counties (drives map popups + county credit lists)
insert into county_org_participation (county_id, org_id) values
  ((select id from counties where fips = '001'), (select id from organizations where name = 'Sierra Club San Francisco Bay Chapter')),
  ((select id from counties where fips = '013'), (select id from organizations where name = 'Sierra Club San Francisco Bay Chapter')),
  ((select id from counties where fips = '041'), (select id from organizations where name = 'Sierra Club San Francisco Bay Chapter')),
  ((select id from counties where fips = '055'), (select id from organizations where name = 'Sierra Club San Francisco Bay Chapter')),
  ((select id from counties where fips = '075'), (select id from organizations where name = 'Sierra Club San Francisco Bay Chapter')),
  ((select id from counties where fips = '095'), (select id from organizations where name = 'Sierra Club San Francisco Bay Chapter')),
  ((select id from counties where fips = '001'), (select id from organizations where name = 'Golden Gate Audubon Society')),
  ((select id from counties where fips = '013'), (select id from organizations where name = 'Golden Gate Audubon Society')),
  ((select id from counties where fips = '041'), (select id from organizations where name = 'Golden Gate Audubon Society')),
  ((select id from counties where fips = '055'), (select id from organizations where name = 'Golden Gate Audubon Society')),
  ((select id from counties where fips = '075'), (select id from organizations where name = 'Golden Gate Audubon Society')),
  ((select id from counties where fips = '095'), (select id from organizations where name = 'Golden Gate Audubon Society')),
  ((select id from counties where fips = '001'), (select id from organizations where name = 'Chabot Space & Science Center astronomy program (Oakland)')),
  ((select id from counties where fips = '013'), (select id from organizations where name = 'Chabot Space & Science Center astronomy program (Oakland)')),
  ((select id from counties where fips = '041'), (select id from organizations where name = 'Chabot Space & Science Center astronomy program (Oakland)')),
  ((select id from counties where fips = '055'), (select id from organizations where name = 'Chabot Space & Science Center astronomy program (Oakland)')),
  ((select id from counties where fips = '075'), (select id from organizations where name = 'Chabot Space & Science Center astronomy program (Oakland)')),
  ((select id from counties where fips = '095'), (select id from organizations where name = 'Chabot Space & Science Center astronomy program (Oakland)')),
  ((select id from counties where fips = '001'), (select id from organizations where name = 'UC Berkeley Students for the Exploration and Development of Space (SEDS)')),
  ((select id from counties where fips = '013'), (select id from organizations where name = 'UC Berkeley Students for the Exploration and Development of Space (SEDS)')),
  ((select id from counties where fips = '041'), (select id from organizations where name = 'UC Berkeley Students for the Exploration and Development of Space (SEDS)')),
  ((select id from counties where fips = '055'), (select id from organizations where name = 'UC Berkeley Students for the Exploration and Development of Space (SEDS)')),
  ((select id from counties where fips = '075'), (select id from organizations where name = 'UC Berkeley Students for the Exploration and Development of Space (SEDS)')),
  ((select id from counties where fips = '095'), (select id from organizations where name = 'UC Berkeley Students for the Exploration and Development of Space (SEDS)')),
  ((select id from counties where fips = '001'), (select id from organizations where name = 'Sunrise Movement Bay Area hub')),
  ((select id from counties where fips = '013'), (select id from organizations where name = 'Sunrise Movement Bay Area hub')),
  ((select id from counties where fips = '041'), (select id from organizations where name = 'Sunrise Movement Bay Area hub')),
  ((select id from counties where fips = '055'), (select id from organizations where name = 'Sunrise Movement Bay Area hub')),
  ((select id from counties where fips = '075'), (select id from organizations where name = 'Sunrise Movement Bay Area hub')),
  ((select id from counties where fips = '095'), (select id from organizations where name = 'Sunrise Movement Bay Area hub')),
  ((select id from counties where fips = '085'), (select id from organizations where name = 'Sierra Club Loma Prieta Chapter')),
  ((select id from counties where fips = '081'), (select id from organizations where name = 'Sierra Club Loma Prieta Chapter')),
  ((select id from counties where fips = '087'), (select id from organizations where name = 'Sierra Club Loma Prieta Chapter')),
  ((select id from counties where fips = '085'), (select id from organizations where name = 'DarkSky Santa Cruz (chapter of DarkSky International)')),
  ((select id from counties where fips = '081'), (select id from organizations where name = 'DarkSky Santa Cruz (chapter of DarkSky International)')),
  ((select id from counties where fips = '087'), (select id from organizations where name = 'DarkSky Santa Cruz (chapter of DarkSky International)')),
  ((select id from counties where fips = '085'), (select id from organizations where name = 'Santa Clara Valley Audubon Society')),
  ((select id from counties where fips = '081'), (select id from organizations where name = 'Santa Clara Valley Audubon Society')),
  ((select id from counties where fips = '087'), (select id from organizations where name = 'Santa Clara Valley Audubon Society')),
  ((select id from counties where fips = '085'), (select id from organizations where name = 'San Jose Astronomical Association / Peninsula Astronomical Society')),
  ((select id from counties where fips = '081'), (select id from organizations where name = 'San Jose Astronomical Association / Peninsula Astronomical Society')),
  ((select id from counties where fips = '087'), (select id from organizations where name = 'San Jose Astronomical Association / Peninsula Astronomical Society')),
  ((select id from counties where fips = '085'), (select id from organizations where name = 'Stanford Students for the Exploration and Development of Space (SEDS)')),
  ((select id from counties where fips = '081'), (select id from organizations where name = 'Stanford Students for the Exploration and Development of Space (SEDS)')),
  ((select id from counties where fips = '087'), (select id from organizations where name = 'Stanford Students for the Exploration and Development of Space (SEDS)')),
  ((select id from counties where fips = '085'), (select id from organizations where name = 'San Jose State University Astronomy Club')),
  ((select id from counties where fips = '081'), (select id from organizations where name = 'San Jose State University Astronomy Club')),
  ((select id from counties where fips = '087'), (select id from organizations where name = 'San Jose State University Astronomy Club')),
  ((select id from counties where fips = '079'), (select id from organizations where name = 'Sierra Club Santa Lucia Chapter (San Luis Obispo) / Santa Barbara-Ventura Chapter / Ventana Chapter (Monterey)')),
  ((select id from counties where fips = '083'), (select id from organizations where name = 'Sierra Club Santa Lucia Chapter (San Luis Obispo) / Santa Barbara-Ventura Chapter / Ventana Chapter (Monterey)')),
  ((select id from counties where fips = '053'), (select id from organizations where name = 'Sierra Club Santa Lucia Chapter (San Luis Obispo) / Santa Barbara-Ventura Chapter / Ventana Chapter (Monterey)')),
  ((select id from counties where fips = '069'), (select id from organizations where name = 'Sierra Club Santa Lucia Chapter (San Luis Obispo) / Santa Barbara-Ventura Chapter / Ventana Chapter (Monterey)')),
  ((select id from counties where fips = '111'), (select id from organizations where name = 'Sierra Club Santa Lucia Chapter (San Luis Obispo) / Santa Barbara-Ventura Chapter / Ventana Chapter (Monterey)')),
  ((select id from counties where fips = '079'), (select id from organizations where name = 'DarkSky Central Coast (chapter of DarkSky International)')),
  ((select id from counties where fips = '083'), (select id from organizations where name = 'DarkSky Central Coast (chapter of DarkSky International)')),
  ((select id from counties where fips = '053'), (select id from organizations where name = 'DarkSky Central Coast (chapter of DarkSky International)')),
  ((select id from counties where fips = '069'), (select id from organizations where name = 'DarkSky Central Coast (chapter of DarkSky International)')),
  ((select id from counties where fips = '111'), (select id from organizations where name = 'DarkSky Central Coast (chapter of DarkSky International)')),
  ((select id from counties where fips = '079'), (select id from organizations where name = 'Morro Coast Audubon Society / Santa Barbara Audubon Society')),
  ((select id from counties where fips = '083'), (select id from organizations where name = 'Morro Coast Audubon Society / Santa Barbara Audubon Society')),
  ((select id from counties where fips = '053'), (select id from organizations where name = 'Morro Coast Audubon Society / Santa Barbara Audubon Society')),
  ((select id from counties where fips = '069'), (select id from organizations where name = 'Morro Coast Audubon Society / Santa Barbara Audubon Society')),
  ((select id from counties where fips = '111'), (select id from organizations where name = 'Morro Coast Audubon Society / Santa Barbara Audubon Society')),
  ((select id from counties where fips = '079'), (select id from organizations where name = 'Central Coast Astronomical Society')),
  ((select id from counties where fips = '083'), (select id from organizations where name = 'Central Coast Astronomical Society')),
  ((select id from counties where fips = '053'), (select id from organizations where name = 'Central Coast Astronomical Society')),
  ((select id from counties where fips = '069'), (select id from organizations where name = 'Central Coast Astronomical Society')),
  ((select id from counties where fips = '111'), (select id from organizations where name = 'Central Coast Astronomical Society')),
  ((select id from counties where fips = '079'), (select id from organizations where name = 'Cal Poly San Luis Obispo Astronomy Club')),
  ((select id from counties where fips = '083'), (select id from organizations where name = 'Cal Poly San Luis Obispo Astronomy Club')),
  ((select id from counties where fips = '053'), (select id from organizations where name = 'Cal Poly San Luis Obispo Astronomy Club')),
  ((select id from counties where fips = '069'), (select id from organizations where name = 'Cal Poly San Luis Obispo Astronomy Club')),
  ((select id from counties where fips = '111'), (select id from organizations where name = 'Cal Poly San Luis Obispo Astronomy Club')),
  ((select id from counties where fips = '079'), (select id from organizations where name = 'UC Santa Barbara Astronomy Club')),
  ((select id from counties where fips = '083'), (select id from organizations where name = 'UC Santa Barbara Astronomy Club')),
  ((select id from counties where fips = '053'), (select id from organizations where name = 'UC Santa Barbara Astronomy Club')),
  ((select id from counties where fips = '069'), (select id from organizations where name = 'UC Santa Barbara Astronomy Club')),
  ((select id from counties where fips = '111'), (select id from organizations where name = 'UC Santa Barbara Astronomy Club')),
  ((select id from counties where fips = '071'), (select id from organizations where name = 'Sierra Club Angeles Chapter (LA/Orange) / San Gorgonio Chapter (Riverside/San Bernardino)')),
  ((select id from counties where fips = '065'), (select id from organizations where name = 'Sierra Club Angeles Chapter (LA/Orange) / San Gorgonio Chapter (Riverside/San Bernardino)')),
  ((select id from counties where fips = '037'), (select id from organizations where name = 'Sierra Club Angeles Chapter (LA/Orange) / San Gorgonio Chapter (Riverside/San Bernardino)')),
  ((select id from counties where fips = '059'), (select id from organizations where name = 'Sierra Club Angeles Chapter (LA/Orange) / San Gorgonio Chapter (Riverside/San Bernardino)')),
  ((select id from counties where fips = '071'), (select id from organizations where name = 'DarkSky LA County / DarkSky Joshua Tree (chapters of DarkSky International)')),
  ((select id from counties where fips = '065'), (select id from organizations where name = 'DarkSky LA County / DarkSky Joshua Tree (chapters of DarkSky International)')),
  ((select id from counties where fips = '037'), (select id from organizations where name = 'DarkSky LA County / DarkSky Joshua Tree (chapters of DarkSky International)')),
  ((select id from counties where fips = '059'), (select id from organizations where name = 'DarkSky LA County / DarkSky Joshua Tree (chapters of DarkSky International)')),
  ((select id from counties where fips = '071'), (select id from organizations where name = 'Los Angeles Audubon Society / Sea and Sage Audubon Society (Orange Co.)')),
  ((select id from counties where fips = '065'), (select id from organizations where name = 'Los Angeles Audubon Society / Sea and Sage Audubon Society (Orange Co.)')),
  ((select id from counties where fips = '037'), (select id from organizations where name = 'Los Angeles Audubon Society / Sea and Sage Audubon Society (Orange Co.)')),
  ((select id from counties where fips = '059'), (select id from organizations where name = 'Los Angeles Audubon Society / Sea and Sage Audubon Society (Orange Co.)')),
  ((select id from counties where fips = '071'), (select id from organizations where name = 'Los Angeles Astronomical Society / Orange County Astronomers')),
  ((select id from counties where fips = '065'), (select id from organizations where name = 'Los Angeles Astronomical Society / Orange County Astronomers')),
  ((select id from counties where fips = '037'), (select id from organizations where name = 'Los Angeles Astronomical Society / Orange County Astronomers')),
  ((select id from counties where fips = '059'), (select id from organizations where name = 'Los Angeles Astronomical Society / Orange County Astronomers')),
  ((select id from counties where fips = '071'), (select id from organizations where name = 'UCLA Astronomical Society')),
  ((select id from counties where fips = '065'), (select id from organizations where name = 'UCLA Astronomical Society')),
  ((select id from counties where fips = '037'), (select id from organizations where name = 'UCLA Astronomical Society')),
  ((select id from counties where fips = '059'), (select id from organizations where name = 'UCLA Astronomical Society')),
  ((select id from counties where fips = '071'), (select id from organizations where name = 'Caltech Astronomy Club')),
  ((select id from counties where fips = '065'), (select id from organizations where name = 'Caltech Astronomy Club')),
  ((select id from counties where fips = '037'), (select id from organizations where name = 'Caltech Astronomy Club')),
  ((select id from counties where fips = '059'), (select id from organizations where name = 'Caltech Astronomy Club')),
  ((select id from counties where fips = '073'), (select id from organizations where name = 'Sierra Club San Diego Chapter')),
  ((select id from counties where fips = '073'), (select id from organizations where name = 'DarkSky San Diego County (chapter of DarkSky International)')),
  ((select id from counties where fips = '073'), (select id from organizations where name = 'San Diego Audubon Society')),
  ((select id from counties where fips = '073'), (select id from organizations where name = 'San Diego Astronomy Association')),
  ((select id from counties where fips = '073'), (select id from organizations where name = 'UC San Diego Astronomy Club')),
  ((select id from counties where fips = '073'), (select id from organizations where name = 'San Diego Youth Climate Strike / Sunrise Movement San Diego')),
  ((select id from counties where fips = '067'), (select id from organizations where name = 'Sierra Club Mother Lode Chapter')),
  ((select id from counties where fips = '047'), (select id from organizations where name = 'Sierra Club Mother Lode Chapter')),
  ((select id from counties where fips = '077'), (select id from organizations where name = 'Sierra Club Mother Lode Chapter')),
  ((select id from counties where fips = '099'), (select id from organizations where name = 'Sierra Club Mother Lode Chapter')),
  ((select id from counties where fips = '101'), (select id from organizations where name = 'Sierra Club Mother Lode Chapter')),
  ((select id from counties where fips = '113'), (select id from organizations where name = 'Sierra Club Mother Lode Chapter')),
  ((select id from counties where fips = '115'), (select id from organizations where name = 'Sierra Club Mother Lode Chapter')),
  ((select id from counties where fips = '057'), (select id from organizations where name = 'Sierra Club Mother Lode Chapter')),
  ((select id from counties where fips = '005'), (select id from organizations where name = 'Sierra Club Mother Lode Chapter')),
  ((select id from counties where fips = '009'), (select id from organizations where name = 'Sierra Club Mother Lode Chapter')),
  ((select id from counties where fips = '091'), (select id from organizations where name = 'Sierra Club Mother Lode Chapter')),
  ((select id from counties where fips = '017'), (select id from organizations where name = 'Sierra Club Mother Lode Chapter')),
  ((select id from counties where fips = '061'), (select id from organizations where name = 'Sierra Club Mother Lode Chapter')),
  ((select id from counties where fips = '067'), (select id from organizations where name = 'Sacramento Audubon Society / Yolo Audubon Society')),
  ((select id from counties where fips = '047'), (select id from organizations where name = 'Sacramento Audubon Society / Yolo Audubon Society')),
  ((select id from counties where fips = '077'), (select id from organizations where name = 'Sacramento Audubon Society / Yolo Audubon Society')),
  ((select id from counties where fips = '099'), (select id from organizations where name = 'Sacramento Audubon Society / Yolo Audubon Society')),
  ((select id from counties where fips = '101'), (select id from organizations where name = 'Sacramento Audubon Society / Yolo Audubon Society')),
  ((select id from counties where fips = '113'), (select id from organizations where name = 'Sacramento Audubon Society / Yolo Audubon Society')),
  ((select id from counties where fips = '115'), (select id from organizations where name = 'Sacramento Audubon Society / Yolo Audubon Society')),
  ((select id from counties where fips = '067'), (select id from organizations where name = 'Sacramento Valley Astronomical Society (SVAS)')),
  ((select id from counties where fips = '047'), (select id from organizations where name = 'Sacramento Valley Astronomical Society (SVAS)')),
  ((select id from counties where fips = '077'), (select id from organizations where name = 'Sacramento Valley Astronomical Society (SVAS)')),
  ((select id from counties where fips = '099'), (select id from organizations where name = 'Sacramento Valley Astronomical Society (SVAS)')),
  ((select id from counties where fips = '101'), (select id from organizations where name = 'Sacramento Valley Astronomical Society (SVAS)')),
  ((select id from counties where fips = '113'), (select id from organizations where name = 'Sacramento Valley Astronomical Society (SVAS)')),
  ((select id from counties where fips = '115'), (select id from organizations where name = 'Sacramento Valley Astronomical Society (SVAS)')),
  ((select id from counties where fips = '067'), (select id from organizations where name = 'UC Davis Astronomy Club')),
  ((select id from counties where fips = '047'), (select id from organizations where name = 'UC Davis Astronomy Club')),
  ((select id from counties where fips = '077'), (select id from organizations where name = 'UC Davis Astronomy Club')),
  ((select id from counties where fips = '099'), (select id from organizations where name = 'UC Davis Astronomy Club')),
  ((select id from counties where fips = '101'), (select id from organizations where name = 'UC Davis Astronomy Club')),
  ((select id from counties where fips = '113'), (select id from organizations where name = 'UC Davis Astronomy Club')),
  ((select id from counties where fips = '115'), (select id from organizations where name = 'UC Davis Astronomy Club')),
  ((select id from counties where fips = '067'), (select id from organizations where name = 'Sunrise Movement Sacramento hub')),
  ((select id from counties where fips = '047'), (select id from organizations where name = 'Sunrise Movement Sacramento hub')),
  ((select id from counties where fips = '077'), (select id from organizations where name = 'Sunrise Movement Sacramento hub')),
  ((select id from counties where fips = '099'), (select id from organizations where name = 'Sunrise Movement Sacramento hub')),
  ((select id from counties where fips = '101'), (select id from organizations where name = 'Sunrise Movement Sacramento hub')),
  ((select id from counties where fips = '113'), (select id from organizations where name = 'Sunrise Movement Sacramento hub')),
  ((select id from counties where fips = '115'), (select id from organizations where name = 'Sunrise Movement Sacramento hub')),
  ((select id from counties where fips = '107'), (select id from organizations where name = 'Sierra Club Tehipite Chapter (Fresno/Madera) / Kern-Kaweah Chapter (Kern/Tulare)')),
  ((select id from counties where fips = '019'), (select id from organizations where name = 'Sierra Club Tehipite Chapter (Fresno/Madera) / Kern-Kaweah Chapter (Kern/Tulare)')),
  ((select id from counties where fips = '029'), (select id from organizations where name = 'Sierra Club Tehipite Chapter (Fresno/Madera) / Kern-Kaweah Chapter (Kern/Tulare)')),
  ((select id from counties where fips = '031'), (select id from organizations where name = 'Sierra Club Tehipite Chapter (Fresno/Madera) / Kern-Kaweah Chapter (Kern/Tulare)')),
  ((select id from counties where fips = '107'), (select id from organizations where name = 'Fresno Audubon Society / Kern Audubon Society')),
  ((select id from counties where fips = '019'), (select id from organizations where name = 'Fresno Audubon Society / Kern Audubon Society')),
  ((select id from counties where fips = '029'), (select id from organizations where name = 'Fresno Audubon Society / Kern Audubon Society')),
  ((select id from counties where fips = '031'), (select id from organizations where name = 'Fresno Audubon Society / Kern Audubon Society')),
  ((select id from counties where fips = '107'), (select id from organizations where name = 'Central Valley Astronomers (Fresno)')),
  ((select id from counties where fips = '019'), (select id from organizations where name = 'Central Valley Astronomers (Fresno)')),
  ((select id from counties where fips = '029'), (select id from organizations where name = 'Central Valley Astronomers (Fresno)')),
  ((select id from counties where fips = '031'), (select id from organizations where name = 'Central Valley Astronomers (Fresno)')),
  ((select id from counties where fips = '107'), (select id from organizations where name = 'Fresno State environmental / astronomy club')),
  ((select id from counties where fips = '019'), (select id from organizations where name = 'Fresno State environmental / astronomy club')),
  ((select id from counties where fips = '029'), (select id from organizations where name = 'Fresno State environmental / astronomy club')),
  ((select id from counties where fips = '031'), (select id from organizations where name = 'Fresno State environmental / astronomy club')),
  ((select id from counties where fips = '107'), (select id from organizations where name = 'CSU Bakersfield sustainability club')),
  ((select id from counties where fips = '019'), (select id from organizations where name = 'CSU Bakersfield sustainability club')),
  ((select id from counties where fips = '029'), (select id from organizations where name = 'CSU Bakersfield sustainability club')),
  ((select id from counties where fips = '031'), (select id from organizations where name = 'CSU Bakersfield sustainability club')),
  ((select id from counties where fips = '057'), (select id from organizations where name = 'Sierra Foothills Audubon Society / Central Sierra Audubon Society')),
  ((select id from counties where fips = '005'), (select id from organizations where name = 'Sierra Foothills Audubon Society / Central Sierra Audubon Society')),
  ((select id from counties where fips = '009'), (select id from organizations where name = 'Sierra Foothills Audubon Society / Central Sierra Audubon Society')),
  ((select id from counties where fips = '091'), (select id from organizations where name = 'Sierra Foothills Audubon Society / Central Sierra Audubon Society')),
  ((select id from counties where fips = '057'), (select id from organizations where name = 'Nevada County / Placer astronomy groups (Northern California Astronomy resource network)')),
  ((select id from counties where fips = '005'), (select id from organizations where name = 'Nevada County / Placer astronomy groups (Northern California Astronomy resource network)')),
  ((select id from counties where fips = '009'), (select id from organizations where name = 'Nevada County / Placer astronomy groups (Northern California Astronomy resource network)')),
  ((select id from counties where fips = '091'), (select id from organizations where name = 'Nevada County / Placer astronomy groups (Northern California Astronomy resource network)')),
  ((select id from counties where fips = '057'), (select id from organizations where name = 'Sierra College environmental club')),
  ((select id from counties where fips = '005'), (select id from organizations where name = 'Sierra College environmental club')),
  ((select id from counties where fips = '009'), (select id from organizations where name = 'Sierra College environmental club')),
  ((select id from counties where fips = '091'), (select id from organizations where name = 'Sierra College environmental club')),
  ((select id from counties where fips = '057'), (select id from organizations where name = 'Local Sunrise Movement / high school Green Team')),
  ((select id from counties where fips = '005'), (select id from organizations where name = 'Local Sunrise Movement / high school Green Team')),
  ((select id from counties where fips = '009'), (select id from organizations where name = 'Local Sunrise Movement / high school Green Team')),
  ((select id from counties where fips = '091'), (select id from organizations where name = 'Local Sunrise Movement / high school Green Team')),
  ((select id from counties where fips = '051'), (select id from organizations where name = 'Sierra Club Toiyabe Chapter (covers the CA Eastern Sierra and Nevada)')),
  ((select id from counties where fips = '027'), (select id from organizations where name = 'Sierra Club Toiyabe Chapter (covers the CA Eastern Sierra and Nevada)')),
  ((select id from counties where fips = '003'), (select id from organizations where name = 'Sierra Club Toiyabe Chapter (covers the CA Eastern Sierra and Nevada)')),
  ((select id from counties where fips = '051'), (select id from organizations where name = 'Eastern Sierra Audubon Society')),
  ((select id from counties where fips = '027'), (select id from organizations where name = 'Eastern Sierra Audubon Society')),
  ((select id from counties where fips = '003'), (select id from organizations where name = 'Eastern Sierra Audubon Society')),
  ((select id from counties where fips = '051'), (select id from organizations where name = 'Eastern Sierra / Death Valley astronomy & stargazing groups')),
  ((select id from counties where fips = '027'), (select id from organizations where name = 'Eastern Sierra / Death Valley astronomy & stargazing groups')),
  ((select id from counties where fips = '003'), (select id from organizations where name = 'Eastern Sierra / Death Valley astronomy & stargazing groups')),
  ((select id from counties where fips = '051'), (select id from organizations where name = 'Local high school environmental club (Bishop / Mammoth area)')),
  ((select id from counties where fips = '027'), (select id from organizations where name = 'Local high school environmental club (Bishop / Mammoth area)')),
  ((select id from counties where fips = '003'), (select id from organizations where name = 'Local high school environmental club (Bishop / Mammoth area)')),
  ((select id from counties where fips = '043'), (select id from organizations where name = 'Sierra Club Tehipite Chapter (Mariposa/Tuolumne/Madera)')),
  ((select id from counties where fips = '039'), (select id from organizations where name = 'Sierra Club Tehipite Chapter (Mariposa/Tuolumne/Madera)')),
  ((select id from counties where fips = '109'), (select id from organizations where name = 'Sierra Club Tehipite Chapter (Mariposa/Tuolumne/Madera)')),
  ((select id from counties where fips = '043'), (select id from organizations where name = 'Yosemite Area Audubon Society')),
  ((select id from counties where fips = '039'), (select id from organizations where name = 'Yosemite Area Audubon Society')),
  ((select id from counties where fips = '109'), (select id from organizations where name = 'Yosemite Area Audubon Society')),
  ((select id from counties where fips = '043'), (select id from organizations where name = 'Under Canvas Yosemite / Yosemite Conservancy night-sky programs')),
  ((select id from counties where fips = '039'), (select id from organizations where name = 'Under Canvas Yosemite / Yosemite Conservancy night-sky programs')),
  ((select id from counties where fips = '109'), (select id from organizations where name = 'Under Canvas Yosemite / Yosemite Conservancy night-sky programs')),
  ((select id from counties where fips = '043'), (select id from organizations where name = 'UC Merced sustainability / astronomy club')),
  ((select id from counties where fips = '039'), (select id from organizations where name = 'UC Merced sustainability / astronomy club')),
  ((select id from counties where fips = '109'), (select id from organizations where name = 'UC Merced sustainability / astronomy club')),
  ((select id from counties where fips = '015'), (select id from organizations where name = 'Sierra Club Redwood Chapter')),
  ((select id from counties where fips = '023'), (select id from organizations where name = 'Sierra Club Redwood Chapter')),
  ((select id from counties where fips = '033'), (select id from organizations where name = 'Sierra Club Redwood Chapter')),
  ((select id from counties where fips = '045'), (select id from organizations where name = 'Sierra Club Redwood Chapter')),
  ((select id from counties where fips = '097'), (select id from organizations where name = 'Sierra Club Redwood Chapter')),
  ((select id from counties where fips = '105'), (select id from organizations where name = 'Sierra Club Redwood Chapter')),
  ((select id from counties where fips = '015'), (select id from organizations where name = 'Redwood Region Audubon Society (Humboldt) / Mendocino Coast Audubon Society')),
  ((select id from counties where fips = '023'), (select id from organizations where name = 'Redwood Region Audubon Society (Humboldt) / Mendocino Coast Audubon Society')),
  ((select id from counties where fips = '033'), (select id from organizations where name = 'Redwood Region Audubon Society (Humboldt) / Mendocino Coast Audubon Society')),
  ((select id from counties where fips = '045'), (select id from organizations where name = 'Redwood Region Audubon Society (Humboldt) / Mendocino Coast Audubon Society')),
  ((select id from counties where fips = '097'), (select id from organizations where name = 'Redwood Region Audubon Society (Humboldt) / Mendocino Coast Audubon Society')),
  ((select id from counties where fips = '105'), (select id from organizations where name = 'Redwood Region Audubon Society (Humboldt) / Mendocino Coast Audubon Society')),
  ((select id from counties where fips = '015'), (select id from organizations where name = 'Humboldt-area amateur astronomy group')),
  ((select id from counties where fips = '023'), (select id from organizations where name = 'Humboldt-area amateur astronomy group')),
  ((select id from counties where fips = '033'), (select id from organizations where name = 'Humboldt-area amateur astronomy group')),
  ((select id from counties where fips = '045'), (select id from organizations where name = 'Humboldt-area amateur astronomy group')),
  ((select id from counties where fips = '097'), (select id from organizations where name = 'Humboldt-area amateur astronomy group')),
  ((select id from counties where fips = '105'), (select id from organizations where name = 'Humboldt-area amateur astronomy group')),
  ((select id from counties where fips = '015'), (select id from organizations where name = 'Cal Poly Humboldt environmental club')),
  ((select id from counties where fips = '023'), (select id from organizations where name = 'Cal Poly Humboldt environmental club')),
  ((select id from counties where fips = '033'), (select id from organizations where name = 'Cal Poly Humboldt environmental club')),
  ((select id from counties where fips = '045'), (select id from organizations where name = 'Cal Poly Humboldt environmental club')),
  ((select id from counties where fips = '097'), (select id from organizations where name = 'Cal Poly Humboldt environmental club')),
  ((select id from counties where fips = '105'), (select id from organizations where name = 'Cal Poly Humboldt environmental club')),
  ((select id from counties where fips = '015'), (select id from organizations where name = 'Local Sunrise Movement hub')),
  ((select id from counties where fips = '023'), (select id from organizations where name = 'Local Sunrise Movement hub')),
  ((select id from counties where fips = '033'), (select id from organizations where name = 'Local Sunrise Movement hub')),
  ((select id from counties where fips = '045'), (select id from organizations where name = 'Local Sunrise Movement hub')),
  ((select id from counties where fips = '097'), (select id from organizations where name = 'Local Sunrise Movement hub')),
  ((select id from counties where fips = '105'), (select id from organizations where name = 'Local Sunrise Movement hub')),
  ((select id from counties where fips = '007'), (select id from organizations where name = 'Sierra Club Mother Lode Chapter (Shasta-area groups)')),
  ((select id from counties where fips = '011'), (select id from organizations where name = 'Sierra Club Mother Lode Chapter (Shasta-area groups)')),
  ((select id from counties where fips = '021'), (select id from organizations where name = 'Sierra Club Mother Lode Chapter (Shasta-area groups)')),
  ((select id from counties where fips = '035'), (select id from organizations where name = 'Sierra Club Mother Lode Chapter (Shasta-area groups)')),
  ((select id from counties where fips = '049'), (select id from organizations where name = 'Sierra Club Mother Lode Chapter (Shasta-area groups)')),
  ((select id from counties where fips = '063'), (select id from organizations where name = 'Sierra Club Mother Lode Chapter (Shasta-area groups)')),
  ((select id from counties where fips = '089'), (select id from organizations where name = 'Sierra Club Mother Lode Chapter (Shasta-area groups)')),
  ((select id from counties where fips = '093'), (select id from organizations where name = 'Sierra Club Mother Lode Chapter (Shasta-area groups)')),
  ((select id from counties where fips = '103'), (select id from organizations where name = 'Sierra Club Mother Lode Chapter (Shasta-area groups)')),
  ((select id from counties where fips = '007'), (select id from organizations where name = 'Wintu Audubon Society (Shasta) / Altacal Audubon Society (Butte/Glenn/Tehama)')),
  ((select id from counties where fips = '011'), (select id from organizations where name = 'Wintu Audubon Society (Shasta) / Altacal Audubon Society (Butte/Glenn/Tehama)')),
  ((select id from counties where fips = '021'), (select id from organizations where name = 'Wintu Audubon Society (Shasta) / Altacal Audubon Society (Butte/Glenn/Tehama)')),
  ((select id from counties where fips = '035'), (select id from organizations where name = 'Wintu Audubon Society (Shasta) / Altacal Audubon Society (Butte/Glenn/Tehama)')),
  ((select id from counties where fips = '049'), (select id from organizations where name = 'Wintu Audubon Society (Shasta) / Altacal Audubon Society (Butte/Glenn/Tehama)')),
  ((select id from counties where fips = '063'), (select id from organizations where name = 'Wintu Audubon Society (Shasta) / Altacal Audubon Society (Butte/Glenn/Tehama)')),
  ((select id from counties where fips = '089'), (select id from organizations where name = 'Wintu Audubon Society (Shasta) / Altacal Audubon Society (Butte/Glenn/Tehama)')),
  ((select id from counties where fips = '093'), (select id from organizations where name = 'Wintu Audubon Society (Shasta) / Altacal Audubon Society (Butte/Glenn/Tehama)')),
  ((select id from counties where fips = '103'), (select id from organizations where name = 'Wintu Audubon Society (Shasta) / Altacal Audubon Society (Butte/Glenn/Tehama)')),
  ((select id from counties where fips = '007'), (select id from organizations where name = 'Shasta area amateur astronomy club')),
  ((select id from counties where fips = '011'), (select id from organizations where name = 'Shasta area amateur astronomy club')),
  ((select id from counties where fips = '021'), (select id from organizations where name = 'Shasta area amateur astronomy club')),
  ((select id from counties where fips = '035'), (select id from organizations where name = 'Shasta area amateur astronomy club')),
  ((select id from counties where fips = '049'), (select id from organizations where name = 'Shasta area amateur astronomy club')),
  ((select id from counties where fips = '063'), (select id from organizations where name = 'Shasta area amateur astronomy club')),
  ((select id from counties where fips = '089'), (select id from organizations where name = 'Shasta area amateur astronomy club')),
  ((select id from counties where fips = '093'), (select id from organizations where name = 'Shasta area amateur astronomy club')),
  ((select id from counties where fips = '103'), (select id from organizations where name = 'Shasta area amateur astronomy club')),
  ((select id from counties where fips = '007'), (select id from organizations where name = 'CSU Chico (Chico State) sustainability / astronomy club')),
  ((select id from counties where fips = '011'), (select id from organizations where name = 'CSU Chico (Chico State) sustainability / astronomy club')),
  ((select id from counties where fips = '021'), (select id from organizations where name = 'CSU Chico (Chico State) sustainability / astronomy club')),
  ((select id from counties where fips = '035'), (select id from organizations where name = 'CSU Chico (Chico State) sustainability / astronomy club')),
  ((select id from counties where fips = '049'), (select id from organizations where name = 'CSU Chico (Chico State) sustainability / astronomy club')),
  ((select id from counties where fips = '063'), (select id from organizations where name = 'CSU Chico (Chico State) sustainability / astronomy club')),
  ((select id from counties where fips = '089'), (select id from organizations where name = 'CSU Chico (Chico State) sustainability / astronomy club')),
  ((select id from counties where fips = '093'), (select id from organizations where name = 'CSU Chico (Chico State) sustainability / astronomy club')),
  ((select id from counties where fips = '103'), (select id from organizations where name = 'CSU Chico (Chico State) sustainability / astronomy club')),
  ((select id from counties where fips = '017'), (select id from organizations where name = 'Sierra Foothills Audubon Society')),
  ((select id from counties where fips = '061'), (select id from organizations where name = 'Sierra Foothills Audubon Society')),
  ((select id from counties where fips = '017'), (select id from organizations where name = 'Tahoe area amateur astronomy / Truckee Donner Land Trust night-sky programs')),
  ((select id from counties where fips = '061'), (select id from organizations where name = 'Tahoe area amateur astronomy / Truckee Donner Land Trust night-sky programs')),
  ((select id from counties where fips = '017'), (select id from organizations where name = 'Sierra Nevada University environmental club (Tahoe area)')),
  ((select id from counties where fips = '061'), (select id from organizations where name = 'Sierra Nevada University environmental club (Tahoe area)')),
  ((select id from counties where fips = '025'), (select id from organizations where name = 'Sierra Club San Diego Chapter (Imperial Co. is in its territory)')),
  ((select id from counties where fips = '025'), (select id from organizations where name = 'Kern/Salton Sea area Audubon contacts (Sea & Sage Audubon Salton Sea program)')),
  ((select id from counties where fips = '025'), (select id from organizations where name = 'San Diego Astronomy Association (nearest active society)')),
  ((select id from counties where fips = '025'), (select id from organizations where name = 'Imperial Valley College sustainability club'))
on conflict (county_id, org_id) do nothing;

-- Per-county outreach email drafts (members-only under RLS)
insert into email_templates (county_id, body) values
  ((select id from counties where fips = '085'), 'Dear Greer Stone (Palo Alto City Council Member),

Hello, my name is Timothy Lee, and I''m writing from SCVBA and FUHSD CC. I''ve been advocating for dark sky policies across California — local ordinances that reduce unnecessary outdoor light at night through simple measures like shielded fixtures, warmer color temperatures, and lighting curfews.

Thank you for the work your community has already done on this front — Palo Alto just passed one of the strictest dark sky lighting ordinances in the state, and Mountain View is actively drafting its own, and that kind of leadership doesn''t go unnoticed. Given that track record, I believe you''d be a genuinely strong voice for dark sky policy going forward.

Dark sky policies matter for more than stargazing. They cut wasted energy and utility costs, restore nocturnal habitat for birds, insects, and other wildlife whose migration and breeding cycles depend on natural darkness, and improve sleep and public health for residents. They also tend to pay for themselves quickly since well-shielded fixtures use less energy for the same or better visibility and safety.

I''m reaching out because Santa Clara County — and Palo Alto in particular — seems like a place where this policy would find real support, and where a local champion on the council or board could help move it forward.

One thing I''ve learned in this work: advocacy through public comment at council and board meetings is often a numbers-and-passion game. A handful of consistent, well-informed voices at the right meetings can shift a policy conversation faster than people expect. I''d love to help make sure Palo Alto has that support if you''re interested in pursuing this.

Any help you can offer — whether that''s raising it as an agenda item, connecting me with the right staff contact, or just pointing me toward others in Palo Alto who care about this — would be greatly appreciated.

If you''re interested in learning more, please reply to this email and I''ll follow up with further information, background material, and next steps.

Thank you again for your time and your work on behalf of Palo Alto and Santa Clara County.

Best,
Timothy Lee
SCVBA and FUHSD CC
'),
  ((select id from counties where fips = '081'), 'Dear Mayor and City Council of Brisbane,

Hello, my name is Timothy Lee, and I''m writing from SCVBA and FUHSD CC. I''ve been advocating for dark sky policies across California — local ordinances that reduce unnecessary outdoor light at night through simple measures like shielded fixtures, warmer color temperatures, and lighting curfews.

Thank you for the work your community has already done on this front — Brisbane already adopted its own outdoor-lighting curfew ordinance, and that kind of leadership doesn''t go unnoticed. Given that track record, I believe you''d be a genuinely strong voice for dark sky policy going forward.

Dark sky policies matter for more than stargazing. They cut wasted energy and utility costs, restore nocturnal habitat for birds, insects, and other wildlife whose migration and breeding cycles depend on natural darkness, and improve sleep and public health for residents. They also tend to pay for themselves quickly since well-shielded fixtures use less energy for the same or better visibility and safety.

I''m reaching out because San Mateo County — and Brisbane in particular — seems like a place where this policy would find real support, and where a local champion on the council or board could help move it forward.

One thing I''ve learned in this work: advocacy through public comment at council and board meetings is often a numbers-and-passion game. A handful of consistent, well-informed voices at the right meetings can shift a policy conversation faster than people expect. I''d love to help make sure Brisbane has that support if you''re interested in pursuing this.

Any help you can offer — whether that''s raising it as an agenda item, connecting me with the right staff contact, or just pointing me toward others in Brisbane who care about this — would be greatly appreciated.

If you''re interested in learning more, please reply to this email and I''ll follow up with further information, background material, and next steps.

Thank you again for your time and your work on behalf of Brisbane and San Mateo County.

Best,
Timothy Lee
SCVBA and FUHSD CC
'),
  ((select id from counties where fips = '073'), 'Dear Jim Desmond (San Diego County Supervisor, District 5 (Borrego Springs)) and Joel Anderson (San Diego County Supervisor, District 2 (includes Julian)),

Hello, my name is Timothy Lee, and I''m writing from SCVBA and FUHSD CC. I''ve been advocating for dark sky policies across California — local ordinances that reduce unnecessary outdoor light at night through simple measures like shielded fixtures, warmer color temperatures, and lighting curfews.

Thank you for the work your community has already done on this front — San Diego County''s Board of Supervisors already designated Julian and Borrego Springs as official Dark Sky Communities back in 2020, and that kind of leadership doesn''t go unnoticed. Given that track record, I believe you''d be a genuinely strong voice for dark sky policy going forward.

Dark sky policies matter for more than stargazing. They cut wasted energy and utility costs, restore nocturnal habitat for birds, insects, and other wildlife whose migration and breeding cycles depend on natural darkness, and improve sleep and public health for residents. They also tend to pay for themselves quickly since well-shielded fixtures use less energy for the same or better visibility and safety.

I''m reaching out because San Diego County has real, demonstrated momentum on this — the kind of place where this policy would find genuine support.

One thing I''ve learned in this work: advocacy through public comment at council and board meetings is often a numbers-and-passion game. A handful of consistent, well-informed voices at the right meetings can shift a policy conversation faster than people expect. I''d love to help make sure San Diego County has that support if you''re interested in building on it.

Any help you can offer — whether that''s raising it as an agenda item, connecting me with the right staff contact, or just pointing me toward others in San Diego County who care about this — would be greatly appreciated.

If you''re interested in learning more, please reply to this email and I''ll follow up with further information, background material, and next steps.

Thank you again for your time and your work on behalf of San Diego County.

Best,
Timothy Lee
SCVBA and FUHSD CC
'),
  ((select id from counties where fips = '051'), 'Dear Mayor and City Council of Mammoth Lakes,

Hello, my name is Timothy Lee, and I''m writing from SCVBA and FUHSD CC. I''ve been advocating for dark sky policies across California — local ordinances that reduce unnecessary outdoor light at night through simple measures like shielded fixtures, warmer color temperatures, and lighting curfews.

Thank you for the work your community has already done on this front — Mono County has had dedicated Dark Sky Regulations written into its General Plan, and that kind of leadership doesn''t go unnoticed. Given that track record, I believe you''d be a genuinely strong voice for dark sky policy going forward.

Dark sky policies matter for more than stargazing. They cut wasted energy and utility costs, restore nocturnal habitat for birds, insects, and other wildlife whose migration and breeding cycles depend on natural darkness, and improve sleep and public health for residents. They also tend to pay for themselves quickly since well-shielded fixtures use less energy for the same or better visibility and safety.

I''m reaching out because Mono County — and Mammoth Lakes in particular — seems like a place where this policy would find real support, and where a local champion on the council or board could help move it forward.

One thing I''ve learned in this work: advocacy through public comment at council and board meetings is often a numbers-and-passion game. A handful of consistent, well-informed voices at the right meetings can shift a policy conversation faster than people expect. I''d love to help make sure Mammoth Lakes has that support if you''re interested in pursuing this.

Any help you can offer — whether that''s raising it as an agenda item, connecting me with the right staff contact, or just pointing me toward others in Mammoth Lakes who care about this — would be greatly appreciated.

If you''re interested in learning more, please reply to this email and I''ll follow up with further information, background material, and next steps.

Thank you again for your time and your work on behalf of Mammoth Lakes and Mono County.

Best,
Timothy Lee
SCVBA and FUHSD CC
'),
  ((select id from counties where fips = '107'), 'Dear Mayor and City Council of Visalia,

Hello, my name is Timothy Lee, and I''m writing from SCVBA and FUHSD CC. I''ve been advocating for dark sky policies across California — local ordinances that reduce unnecessary outdoor light at night through simple measures like shielded fixtures, warmer color temperatures, and lighting curfews.

Thank you for the work your community has already done on this front — Sequoia & Kings Canyon National Park, right in your county, is a certified International Dark Sky Park, and that kind of leadership doesn''t go unnoticed. Given that track record, I believe you''d be a genuinely strong voice for dark sky policy going forward.

Dark sky policies matter for more than stargazing. They cut wasted energy and utility costs, restore nocturnal habitat for birds, insects, and other wildlife whose migration and breeding cycles depend on natural darkness, and improve sleep and public health for residents. They also tend to pay for themselves quickly since well-shielded fixtures use less energy for the same or better visibility and safety.

I''m reaching out because Tulare County — and Visalia in particular — seems like a place where this policy would find real support, and where a local champion on the council or board could help move it forward.

One thing I''ve learned in this work: advocacy through public comment at council and board meetings is often a numbers-and-passion game. A handful of consistent, well-informed voices at the right meetings can shift a policy conversation faster than people expect. I''d love to help make sure Visalia has that support if you''re interested in pursuing this.

Any help you can offer — whether that''s raising it as an agenda item, connecting me with the right staff contact, or just pointing me toward others in Visalia who care about this — would be greatly appreciated.

If you''re interested in learning more, please reply to this email and I''ll follow up with further information, background material, and next steps.

Thank you again for your time and your work on behalf of Visalia and Tulare County.

Best,
Timothy Lee
SCVBA and FUHSD CC
'),
  ((select id from counties where fips = '019'), 'Dear Mayor and City Council of Fresno,

Hello, my name is Timothy Lee, and I''m writing from SCVBA and FUHSD CC. I''ve been advocating for dark sky policies across California — local ordinances that reduce unnecessary outdoor light at night through simple measures like shielded fixtures, warmer color temperatures, and lighting curfews.

Thank you for the work your community has already done on this front — Sequoia & Kings Canyon National Park, on your county''s doorstep, is a certified International Dark Sky Park, and that kind of leadership doesn''t go unnoticed. Given that track record, I believe you''d be a genuinely strong voice for dark sky policy going forward.

Dark sky policies matter for more than stargazing. They cut wasted energy and utility costs, restore nocturnal habitat for birds, insects, and other wildlife whose migration and breeding cycles depend on natural darkness, and improve sleep and public health for residents. They also tend to pay for themselves quickly since well-shielded fixtures use less energy for the same or better visibility and safety.

I''m reaching out because Fresno County — and Fresno in particular — seems like a place where this policy would find real support, and where a local champion on the council or board could help move it forward.

One thing I''ve learned in this work: advocacy through public comment at council and board meetings is often a numbers-and-passion game. A handful of consistent, well-informed voices at the right meetings can shift a policy conversation faster than people expect. I''d love to help make sure Fresno has that support if you''re interested in pursuing this.

Any help you can offer — whether that''s raising it as an agenda item, connecting me with the right staff contact, or just pointing me toward others in Fresno who care about this — would be greatly appreciated.

If you''re interested in learning more, please reply to this email and I''ll follow up with further information, background material, and next steps.

Thank you again for your time and your work on behalf of Fresno and Fresno County.

Best,
Timothy Lee
SCVBA and FUHSD CC
'),
  ((select id from counties where fips = '027'), 'Dear Mayor and City Council of Bishop,

Hello, my name is Timothy Lee, and I''m writing from SCVBA and FUHSD CC. I''ve been advocating for dark sky policies across California — local ordinances that reduce unnecessary outdoor light at night through simple measures like shielded fixtures, warmer color temperatures, and lighting curfews.

Thank you for the work your community has already done on this front — Death Valley National Park in your county holds Gold-tier International Dark Sky Park status, and that kind of leadership doesn''t go unnoticed. Given that track record, I believe you''d be a genuinely strong voice for dark sky policy going forward.

Dark sky policies matter for more than stargazing. They cut wasted energy and utility costs, restore nocturnal habitat for birds, insects, and other wildlife whose migration and breeding cycles depend on natural darkness, and improve sleep and public health for residents. They also tend to pay for themselves quickly since well-shielded fixtures use less energy for the same or better visibility and safety.

I''m reaching out because Inyo County — and Bishop in particular — seems like a place where this policy would find real support, and where a local champion on the council or board could help move it forward.

One thing I''ve learned in this work: advocacy through public comment at council and board meetings is often a numbers-and-passion game. A handful of consistent, well-informed voices at the right meetings can shift a policy conversation faster than people expect. I''d love to help make sure Bishop has that support if you''re interested in pursuing this.

Any help you can offer — whether that''s raising it as an agenda item, connecting me with the right staff contact, or just pointing me toward others in Bishop who care about this — would be greatly appreciated.

If you''re interested in learning more, please reply to this email and I''ll follow up with further information, background material, and next steps.

Thank you again for your time and your work on behalf of Bishop and Inyo County.

Best,
Timothy Lee
SCVBA and FUHSD CC
'),
  ((select id from counties where fips = '043'), 'Dear Mariposa County Board of Supervisors,

Hello, my name is Timothy Lee, and I''m writing from SCVBA and FUHSD CC. I''ve been advocating for dark sky policies across California — local ordinances that reduce unnecessary outdoor light at night through simple measures like shielded fixtures, warmer color temperatures, and lighting curfews.

Thank you for the work your community has already done on this front — Yosemite, right in your county, is home to California''s first DarkSky-Approved Lodging property, and that kind of leadership doesn''t go unnoticed. Given that track record, I believe you''d be a genuinely strong voice for dark sky policy going forward.

Dark sky policies matter for more than stargazing. They cut wasted energy and utility costs, restore nocturnal habitat for birds, insects, and other wildlife whose migration and breeding cycles depend on natural darkness, and improve sleep and public health for residents. They also tend to pay for themselves quickly since well-shielded fixtures use less energy for the same or better visibility and safety.

I''m reaching out because Mariposa County — and Mariposa in particular — seems like a place where this policy would find real support, and where a local champion on the council or board could help move it forward.

One thing I''ve learned in this work: advocacy through public comment at council and board meetings is often a numbers-and-passion game. A handful of consistent, well-informed voices at the right meetings can shift a policy conversation faster than people expect. I''d love to help make sure Mariposa has that support if you''re interested in pursuing this.

Any help you can offer — whether that''s raising it as an agenda item, connecting me with the right staff contact, or just pointing me toward others in Mariposa who care about this — would be greatly appreciated.

If you''re interested in learning more, please reply to this email and I''ll follow up with further information, background material, and next steps.

Thank you again for your time and your work on behalf of Mariposa and Mariposa County.

Best,
Timothy Lee
SCVBA and FUHSD CC
'),
  ((select id from counties where fips = '017'), 'Dear Mayor and City Council of South Lake Tahoe,

Hello, my name is Timothy Lee, and I''m writing from SCVBA and FUHSD CC. I''ve been advocating for dark sky policies across California — local ordinances that reduce unnecessary outdoor light at night through simple measures like shielded fixtures, warmer color temperatures, and lighting curfews.

Thank you for the work your community has already done on this front — The Tahoe Basin''s dark-sky and night-sky protection efforts have been building for years, and that kind of leadership doesn''t go unnoticed. Given that track record, I believe you''d be a genuinely strong voice for dark sky policy going forward.

Dark sky policies matter for more than stargazing. They cut wasted energy and utility costs, restore nocturnal habitat for birds, insects, and other wildlife whose migration and breeding cycles depend on natural darkness, and improve sleep and public health for residents. They also tend to pay for themselves quickly since well-shielded fixtures use less energy for the same or better visibility and safety.

I''m reaching out because El Dorado County — and South Lake Tahoe in particular — seems like a place where this policy would find real support, and where a local champion on the council or board could help move it forward.

One thing I''ve learned in this work: advocacy through public comment at council and board meetings is often a numbers-and-passion game. A handful of consistent, well-informed voices at the right meetings can shift a policy conversation faster than people expect. I''d love to help make sure South Lake Tahoe has that support if you''re interested in pursuing this.

Any help you can offer — whether that''s raising it as an agenda item, connecting me with the right staff contact, or just pointing me toward others in South Lake Tahoe who care about this — would be greatly appreciated.

If you''re interested in learning more, please reply to this email and I''ll follow up with further information, background material, and next steps.

Thank you again for your time and your work on behalf of South Lake Tahoe and El Dorado County.

Best,
Timothy Lee
SCVBA and FUHSD CC
'),
  ((select id from counties where fips = '061'), 'Dear Mayor and City Council of Roseville,

Hello, my name is Timothy Lee, and I''m writing from SCVBA and FUHSD CC. I''ve been advocating for dark sky policies across California — local ordinances that reduce unnecessary outdoor light at night through simple measures like shielded fixtures, warmer color temperatures, and lighting curfews.

Thank you for the work you and your community continue to put into environmental stewardship in Placer County, from land and water conservation to public health — it''s the kind of leadership that doesn''t go unnoticed. Given that, I believe you and your community would be well-positioned to champion dark sky policy too.

Dark sky policies matter for more than stargazing. They cut wasted energy and utility costs, restore nocturnal habitat for birds, insects, and other wildlife whose migration and breeding cycles depend on natural darkness, and improve sleep and public health for residents. They also tend to pay for themselves quickly since well-shielded fixtures use less energy for the same or better visibility and safety.

I''m reaching out because Placer County — and Roseville in particular — seems like a place where this policy would find real support, and where a local champion on the council or board could help move it forward.

One thing I''ve learned in this work: advocacy through public comment at council and board meetings is often a numbers-and-passion game. A handful of consistent, well-informed voices at the right meetings can shift a policy conversation faster than people expect. I''d love to help make sure Roseville has that support if you''re interested in pursuing this.

Any help you can offer — whether that''s raising it as an agenda item, connecting me with the right staff contact, or just pointing me toward others in Roseville who care about this — would be greatly appreciated.

If you''re interested in learning more, please reply to this email and I''ll follow up with further information, background material, and next steps.

Thank you again for your time and your work on behalf of Roseville and Placer County.

Best,
Timothy Lee
SCVBA and FUHSD CC
'),
  ((select id from counties where fips = '057'), 'Dear Mayor and City Council of Truckee,

Hello, my name is Timothy Lee, and I''m writing from SCVBA and FUHSD CC. I''ve been advocating for dark sky policies across California — local ordinances that reduce unnecessary outdoor light at night through simple measures like shielded fixtures, warmer color temperatures, and lighting curfews.

Thank you for the work your community has already done on this front — Truckee is part of the Tahoe corridor''s growing dark-sky and night-sky-tourism movement, and that kind of leadership doesn''t go unnoticed. Given that track record, I believe you''d be a genuinely strong voice for dark sky policy going forward.

Dark sky policies matter for more than stargazing. They cut wasted energy and utility costs, restore nocturnal habitat for birds, insects, and other wildlife whose migration and breeding cycles depend on natural darkness, and improve sleep and public health for residents. They also tend to pay for themselves quickly since well-shielded fixtures use less energy for the same or better visibility and safety.

I''m reaching out because Nevada County — and Truckee in particular — seems like a place where this policy would find real support, and where a local champion on the council or board could help move it forward.

One thing I''ve learned in this work: advocacy through public comment at council and board meetings is often a numbers-and-passion game. A handful of consistent, well-informed voices at the right meetings can shift a policy conversation faster than people expect. I''d love to help make sure Truckee has that support if you''re interested in pursuing this.

Any help you can offer — whether that''s raising it as an agenda item, connecting me with the right staff contact, or just pointing me toward others in Truckee who care about this — would be greatly appreciated.

If you''re interested in learning more, please reply to this email and I''ll follow up with further information, background material, and next steps.

Thank you again for your time and your work on behalf of Truckee and Nevada County.

Best,
Timothy Lee
SCVBA and FUHSD CC
'),
  ((select id from counties where fips = '071'), 'Dear Mayor and City Council of Twentynine Palms,

Hello, my name is Timothy Lee, and I''m writing from SCVBA and FUHSD CC. I''ve been advocating for dark sky policies across California — local ordinances that reduce unnecessary outdoor light at night through simple measures like shielded fixtures, warmer color temperatures, and lighting curfews.

Thank you for the work your community has already done on this front — Twentynine Palms sits right on the edge of Joshua Tree National Park and DarkSky Joshua Tree''s territory, and that kind of leadership doesn''t go unnoticed. Given that track record, I believe you''d be a genuinely strong voice for dark sky policy going forward.

Dark sky policies matter for more than stargazing. They cut wasted energy and utility costs, restore nocturnal habitat for birds, insects, and other wildlife whose migration and breeding cycles depend on natural darkness, and improve sleep and public health for residents. They also tend to pay for themselves quickly since well-shielded fixtures use less energy for the same or better visibility and safety.

I''m reaching out because San Bernardino County — and Twentynine Palms in particular — seems like a place where this policy would find real support, and where a local champion on the council or board could help move it forward.

One thing I''ve learned in this work: advocacy through public comment at council and board meetings is often a numbers-and-passion game. A handful of consistent, well-informed voices at the right meetings can shift a policy conversation faster than people expect. I''d love to help make sure Twentynine Palms has that support if you''re interested in pursuing this.

Any help you can offer — whether that''s raising it as an agenda item, connecting me with the right staff contact, or just pointing me toward others in Twentynine Palms who care about this — would be greatly appreciated.

If you''re interested in learning more, please reply to this email and I''ll follow up with further information, background material, and next steps.

Thank you again for your time and your work on behalf of Twentynine Palms and San Bernardino County.

Best,
Timothy Lee
SCVBA and FUHSD CC
'),
  ((select id from counties where fips = '065'), 'Dear Mayor and City Council of Palm Springs,

Hello, my name is Timothy Lee, and I''m writing from SCVBA and FUHSD CC. I''ve been advocating for dark sky policies across California — local ordinances that reduce unnecessary outdoor light at night through simple measures like shielded fixtures, warmer color temperatures, and lighting curfews.

Thank you for the work you and your community continue to put into environmental stewardship in Riverside County, from land and water conservation to public health — it''s the kind of leadership that doesn''t go unnoticed. Given that, I believe you and your community would be well-positioned to champion dark sky policy too.

Dark sky policies matter for more than stargazing. They cut wasted energy and utility costs, restore nocturnal habitat for birds, insects, and other wildlife whose migration and breeding cycles depend on natural darkness, and improve sleep and public health for residents. They also tend to pay for themselves quickly since well-shielded fixtures use less energy for the same or better visibility and safety.

I''m reaching out because Riverside County — and Palm Springs in particular — seems like a place where this policy would find real support, and where a local champion on the council or board could help move it forward.

One thing I''ve learned in this work: advocacy through public comment at council and board meetings is often a numbers-and-passion game. A handful of consistent, well-informed voices at the right meetings can shift a policy conversation faster than people expect. I''d love to help make sure Palm Springs has that support if you''re interested in pursuing this.

Any help you can offer — whether that''s raising it as an agenda item, connecting me with the right staff contact, or just pointing me toward others in Palm Springs who care about this — would be greatly appreciated.

If you''re interested in learning more, please reply to this email and I''ll follow up with further information, background material, and next steps.

Thank you again for your time and your work on behalf of Palm Springs and Riverside County.

Best,
Timothy Lee
SCVBA and FUHSD CC
'),
  ((select id from counties where fips = '087'), 'Dear Mayor and City Council of Santa Cruz,

Hello, my name is Timothy Lee, and I''m writing from SCVBA and FUHSD CC. I''ve been advocating for dark sky policies across California — local ordinances that reduce unnecessary outdoor light at night through simple measures like shielded fixtures, warmer color temperatures, and lighting curfews.

Thank you for the work your community has already done on this front — Santa Cruz is already home to its own DarkSky International chapter, and that kind of leadership doesn''t go unnoticed. Given that track record, I believe you''d be a genuinely strong voice for dark sky policy going forward.

Dark sky policies matter for more than stargazing. They cut wasted energy and utility costs, restore nocturnal habitat for birds, insects, and other wildlife whose migration and breeding cycles depend on natural darkness, and improve sleep and public health for residents. They also tend to pay for themselves quickly since well-shielded fixtures use less energy for the same or better visibility and safety.

I''m reaching out because Santa Cruz County — and Santa Cruz in particular — seems like a place where this policy would find real support, and where a local champion on the council or board could help move it forward.

One thing I''ve learned in this work: advocacy through public comment at council and board meetings is often a numbers-and-passion game. A handful of consistent, well-informed voices at the right meetings can shift a policy conversation faster than people expect. I''d love to help make sure Santa Cruz has that support if you''re interested in pursuing this.

Any help you can offer — whether that''s raising it as an agenda item, connecting me with the right staff contact, or just pointing me toward others in Santa Cruz who care about this — would be greatly appreciated.

If you''re interested in learning more, please reply to this email and I''ll follow up with further information, background material, and next steps.

Thank you again for your time and your work on behalf of Santa Cruz and Santa Cruz County.

Best,
Timothy Lee
SCVBA and FUHSD CC
'),
  ((select id from counties where fips = '079'), 'Dear Mayor and City Council of San Luis Obispo,

Hello, my name is Timothy Lee, and I''m writing from SCVBA and FUHSD CC. I''ve been advocating for dark sky policies across California — local ordinances that reduce unnecessary outdoor light at night through simple measures like shielded fixtures, warmer color temperatures, and lighting curfews.

Thank you for the work your community has already done on this front — The Central Coast already has an active DarkSky International chapter working in your area, and that kind of leadership doesn''t go unnoticed. Given that track record, I believe you''d be a genuinely strong voice for dark sky policy going forward.

Dark sky policies matter for more than stargazing. They cut wasted energy and utility costs, restore nocturnal habitat for birds, insects, and other wildlife whose migration and breeding cycles depend on natural darkness, and improve sleep and public health for residents. They also tend to pay for themselves quickly since well-shielded fixtures use less energy for the same or better visibility and safety.

I''m reaching out because San Luis Obispo County — and San Luis Obispo in particular — seems like a place where this policy would find real support, and where a local champion on the council or board could help move it forward.

One thing I''ve learned in this work: advocacy through public comment at council and board meetings is often a numbers-and-passion game. A handful of consistent, well-informed voices at the right meetings can shift a policy conversation faster than people expect. I''d love to help make sure San Luis Obispo has that support if you''re interested in pursuing this.

Any help you can offer — whether that''s raising it as an agenda item, connecting me with the right staff contact, or just pointing me toward others in San Luis Obispo who care about this — would be greatly appreciated.

If you''re interested in learning more, please reply to this email and I''ll follow up with further information, background material, and next steps.

Thank you again for your time and your work on behalf of San Luis Obispo and San Luis Obispo County.

Best,
Timothy Lee
SCVBA and FUHSD CC
'),
  ((select id from counties where fips = '083'), 'Dear Mayor and City Council of Santa Barbara,

Hello, my name is Timothy Lee, and I''m writing from SCVBA and FUHSD CC. I''ve been advocating for dark sky policies across California — local ordinances that reduce unnecessary outdoor light at night through simple measures like shielded fixtures, warmer color temperatures, and lighting curfews.

Thank you for the work your community has already done on this front — The Central Coast already has an active DarkSky International chapter working in your area, and that kind of leadership doesn''t go unnoticed. Given that track record, I believe you''d be a genuinely strong voice for dark sky policy going forward.

Dark sky policies matter for more than stargazing. They cut wasted energy and utility costs, restore nocturnal habitat for birds, insects, and other wildlife whose migration and breeding cycles depend on natural darkness, and improve sleep and public health for residents. They also tend to pay for themselves quickly since well-shielded fixtures use less energy for the same or better visibility and safety.

I''m reaching out because Santa Barbara County — and Santa Barbara in particular — seems like a place where this policy would find real support, and where a local champion on the council or board could help move it forward.

One thing I''ve learned in this work: advocacy through public comment at council and board meetings is often a numbers-and-passion game. A handful of consistent, well-informed voices at the right meetings can shift a policy conversation faster than people expect. I''d love to help make sure Santa Barbara has that support if you''re interested in pursuing this.

Any help you can offer — whether that''s raising it as an agenda item, connecting me with the right staff contact, or just pointing me toward others in Santa Barbara who care about this — would be greatly appreciated.

If you''re interested in learning more, please reply to this email and I''ll follow up with further information, background material, and next steps.

Thank you again for your time and your work on behalf of Santa Barbara and Santa Barbara County.

Best,
Timothy Lee
SCVBA and FUHSD CC
'),
  ((select id from counties where fips = '053'), 'Dear Mayor and City Council of Monterey,

Hello, my name is Timothy Lee, and I''m writing from SCVBA and FUHSD CC. I''ve been advocating for dark sky policies across California — local ordinances that reduce unnecessary outdoor light at night through simple measures like shielded fixtures, warmer color temperatures, and lighting curfews.

Thank you for the work your community has already done on this front — Nearby Pinnacles National Park and the Central Coast DarkSky chapter show real regional momentum, and that kind of leadership doesn''t go unnoticed. Given that track record, I believe you''d be a genuinely strong voice for dark sky policy going forward.

Dark sky policies matter for more than stargazing. They cut wasted energy and utility costs, restore nocturnal habitat for birds, insects, and other wildlife whose migration and breeding cycles depend on natural darkness, and improve sleep and public health for residents. They also tend to pay for themselves quickly since well-shielded fixtures use less energy for the same or better visibility and safety.

I''m reaching out because Monterey County — and Monterey in particular — seems like a place where this policy would find real support, and where a local champion on the council or board could help move it forward.

One thing I''ve learned in this work: advocacy through public comment at council and board meetings is often a numbers-and-passion game. A handful of consistent, well-informed voices at the right meetings can shift a policy conversation faster than people expect. I''d love to help make sure Monterey has that support if you''re interested in pursuing this.

Any help you can offer — whether that''s raising it as an agenda item, connecting me with the right staff contact, or just pointing me toward others in Monterey who care about this — would be greatly appreciated.

If you''re interested in learning more, please reply to this email and I''ll follow up with further information, background material, and next steps.

Thank you again for your time and your work on behalf of Monterey and Monterey County.

Best,
Timothy Lee
SCVBA and FUHSD CC
'),
  ((select id from counties where fips = '067'), 'Dear Mayor and City Council of Sacramento,

Hello, my name is Timothy Lee, and I''m writing from SCVBA and FUHSD CC. I''ve been advocating for dark sky policies across California — local ordinances that reduce unnecessary outdoor light at night through simple measures like shielded fixtures, warmer color temperatures, and lighting curfews.

Thank you for the work your community has already done on this front — Sacramento is home to one of the nation''s oldest astronomy clubs, SVAS, founded in 1945, and that kind of leadership doesn''t go unnoticed. Given that track record, I believe you''d be a genuinely strong voice for dark sky policy going forward.

Dark sky policies matter for more than stargazing. They cut wasted energy and utility costs, restore nocturnal habitat for birds, insects, and other wildlife whose migration and breeding cycles depend on natural darkness, and improve sleep and public health for residents. They also tend to pay for themselves quickly since well-shielded fixtures use less energy for the same or better visibility and safety.

I''m reaching out because Sacramento County — and Sacramento in particular — seems like a place where this policy would find real support, and where a local champion on the council or board could help move it forward.

One thing I''ve learned in this work: advocacy through public comment at council and board meetings is often a numbers-and-passion game. A handful of consistent, well-informed voices at the right meetings can shift a policy conversation faster than people expect. I''d love to help make sure Sacramento has that support if you''re interested in pursuing this.

Any help you can offer — whether that''s raising it as an agenda item, connecting me with the right staff contact, or just pointing me toward others in Sacramento who care about this — would be greatly appreciated.

If you''re interested in learning more, please reply to this email and I''ll follow up with further information, background material, and next steps.

Thank you again for your time and your work on behalf of Sacramento and Sacramento County.

Best,
Timothy Lee
SCVBA and FUHSD CC
'),
  ((select id from counties where fips = '001'), 'Dear Mayor and City Council of Berkeley,

Hello, my name is Timothy Lee, and I''m writing from SCVBA and FUHSD CC. I''ve been advocating for dark sky policies across California — local ordinances that reduce unnecessary outdoor light at night through simple measures like shielded fixtures, warmer color temperatures, and lighting curfews.

Thank you for the work you and your community continue to put into environmental stewardship in Alameda County, from land and water conservation to public health — it''s the kind of leadership that doesn''t go unnoticed. Given that, I believe you and your community would be well-positioned to champion dark sky policy too.

Dark sky policies matter for more than stargazing. They cut wasted energy and utility costs, restore nocturnal habitat for birds, insects, and other wildlife whose migration and breeding cycles depend on natural darkness, and improve sleep and public health for residents. They also tend to pay for themselves quickly since well-shielded fixtures use less energy for the same or better visibility and safety.

I''m reaching out because Alameda County — and Berkeley in particular — seems like a place where this policy would find real support, and where a local champion on the council or board could help move it forward.

One thing I''ve learned in this work: advocacy through public comment at council and board meetings is often a numbers-and-passion game. A handful of consistent, well-informed voices at the right meetings can shift a policy conversation faster than people expect. I''d love to help make sure Berkeley has that support if you''re interested in pursuing this.

Any help you can offer — whether that''s raising it as an agenda item, connecting me with the right staff contact, or just pointing me toward others in Berkeley who care about this — would be greatly appreciated.

If you''re interested in learning more, please reply to this email and I''ll follow up with further information, background material, and next steps.

Thank you again for your time and your work on behalf of Berkeley and Alameda County.

Best,
Timothy Lee
SCVBA and FUHSD CC
'),
  ((select id from counties where fips = '003'), 'Dear Alpine County Board of Supervisors,

Hello, my name is Timothy Lee, and I''m writing from SCVBA and FUHSD CC. I''ve been advocating for dark sky policies across California — local ordinances that reduce unnecessary outdoor light at night through simple measures like shielded fixtures, warmer color temperatures, and lighting curfews.

Thank you for the work you and your community continue to put into environmental stewardship in Alpine County, from land and water conservation to public health — it''s the kind of leadership that doesn''t go unnoticed. Given that, I believe you and your community would be well-positioned to champion dark sky policy too.

Dark sky policies matter for more than stargazing. They cut wasted energy and utility costs, restore nocturnal habitat for birds, insects, and other wildlife whose migration and breeding cycles depend on natural darkness, and improve sleep and public health for residents. They also tend to pay for themselves quickly since well-shielded fixtures use less energy for the same or better visibility and safety.

I''m reaching out because Alpine County — and Markleeville in particular — seems like a place where this policy would find real support, and where a local champion on the council or board could help move it forward.

One thing I''ve learned in this work: advocacy through public comment at council and board meetings is often a numbers-and-passion game. A handful of consistent, well-informed voices at the right meetings can shift a policy conversation faster than people expect. I''d love to help make sure Markleeville has that support if you''re interested in pursuing this.

Any help you can offer — whether that''s raising it as an agenda item, connecting me with the right staff contact, or just pointing me toward others in Markleeville who care about this — would be greatly appreciated.

If you''re interested in learning more, please reply to this email and I''ll follow up with further information, background material, and next steps.

Thank you again for your time and your work on behalf of Markleeville and Alpine County.

Best,
Timothy Lee
SCVBA and FUHSD CC
'),
  ((select id from counties where fips = '005'), 'Dear Mayor and City Council of Jackson,

Hello, my name is Timothy Lee, and I''m writing from SCVBA and FUHSD CC. I''ve been advocating for dark sky policies across California — local ordinances that reduce unnecessary outdoor light at night through simple measures like shielded fixtures, warmer color temperatures, and lighting curfews.

Thank you for the work you and your community continue to put into environmental stewardship in Amador County, from land and water conservation to public health — it''s the kind of leadership that doesn''t go unnoticed. Given that, I believe you and your community would be well-positioned to champion dark sky policy too.

Dark sky policies matter for more than stargazing. They cut wasted energy and utility costs, restore nocturnal habitat for birds, insects, and other wildlife whose migration and breeding cycles depend on natural darkness, and improve sleep and public health for residents. They also tend to pay for themselves quickly since well-shielded fixtures use less energy for the same or better visibility and safety.

I''m reaching out because Amador County — and Jackson in particular — seems like a place where this policy would find real support, and where a local champion on the council or board could help move it forward.

One thing I''ve learned in this work: advocacy through public comment at council and board meetings is often a numbers-and-passion game. A handful of consistent, well-informed voices at the right meetings can shift a policy conversation faster than people expect. I''d love to help make sure Jackson has that support if you''re interested in pursuing this.

Any help you can offer — whether that''s raising it as an agenda item, connecting me with the right staff contact, or just pointing me toward others in Jackson who care about this — would be greatly appreciated.

If you''re interested in learning more, please reply to this email and I''ll follow up with further information, background material, and next steps.

Thank you again for your time and your work on behalf of Jackson and Amador County.

Best,
Timothy Lee
SCVBA and FUHSD CC
'),
  ((select id from counties where fips = '007'), 'Dear Mayor and City Council of Chico,

Hello, my name is Timothy Lee, and I''m writing from SCVBA and FUHSD CC. I''ve been advocating for dark sky policies across California — local ordinances that reduce unnecessary outdoor light at night through simple measures like shielded fixtures, warmer color temperatures, and lighting curfews.

Thank you for the work you and your community continue to put into environmental stewardship in Butte County, from land and water conservation to public health — it''s the kind of leadership that doesn''t go unnoticed. Given that, I believe you and your community would be well-positioned to champion dark sky policy too.

Dark sky policies matter for more than stargazing. They cut wasted energy and utility costs, restore nocturnal habitat for birds, insects, and other wildlife whose migration and breeding cycles depend on natural darkness, and improve sleep and public health for residents. They also tend to pay for themselves quickly since well-shielded fixtures use less energy for the same or better visibility and safety.

I''m reaching out because Butte County — and Chico in particular — seems like a place where this policy would find real support, and where a local champion on the council or board could help move it forward.

One thing I''ve learned in this work: advocacy through public comment at council and board meetings is often a numbers-and-passion game. A handful of consistent, well-informed voices at the right meetings can shift a policy conversation faster than people expect. I''d love to help make sure Chico has that support if you''re interested in pursuing this.

Any help you can offer — whether that''s raising it as an agenda item, connecting me with the right staff contact, or just pointing me toward others in Chico who care about this — would be greatly appreciated.

If you''re interested in learning more, please reply to this email and I''ll follow up with further information, background material, and next steps.

Thank you again for your time and your work on behalf of Chico and Butte County.

Best,
Timothy Lee
SCVBA and FUHSD CC
'),
  ((select id from counties where fips = '009'), 'Dear Mayor and City Council of Angels Camp,

Hello, my name is Timothy Lee, and I''m writing from SCVBA and FUHSD CC. I''ve been advocating for dark sky policies across California — local ordinances that reduce unnecessary outdoor light at night through simple measures like shielded fixtures, warmer color temperatures, and lighting curfews.

Thank you for the work you and your community continue to put into environmental stewardship in Calaveras County, from land and water conservation to public health — it''s the kind of leadership that doesn''t go unnoticed. Given that, I believe you and your community would be well-positioned to champion dark sky policy too.

Dark sky policies matter for more than stargazing. They cut wasted energy and utility costs, restore nocturnal habitat for birds, insects, and other wildlife whose migration and breeding cycles depend on natural darkness, and improve sleep and public health for residents. They also tend to pay for themselves quickly since well-shielded fixtures use less energy for the same or better visibility and safety.

I''m reaching out because Calaveras County — and Angels Camp in particular — seems like a place where this policy would find real support, and where a local champion on the council or board could help move it forward.

One thing I''ve learned in this work: advocacy through public comment at council and board meetings is often a numbers-and-passion game. A handful of consistent, well-informed voices at the right meetings can shift a policy conversation faster than people expect. I''d love to help make sure Angels Camp has that support if you''re interested in pursuing this.

Any help you can offer — whether that''s raising it as an agenda item, connecting me with the right staff contact, or just pointing me toward others in Angels Camp who care about this — would be greatly appreciated.

If you''re interested in learning more, please reply to this email and I''ll follow up with further information, background material, and next steps.

Thank you again for your time and your work on behalf of Angels Camp and Calaveras County.

Best,
Timothy Lee
SCVBA and FUHSD CC
'),
  ((select id from counties where fips = '011'), 'Dear Mayor and City Council of Colusa,

Hello, my name is Timothy Lee, and I''m writing from SCVBA and FUHSD CC. I''ve been advocating for dark sky policies across California — local ordinances that reduce unnecessary outdoor light at night through simple measures like shielded fixtures, warmer color temperatures, and lighting curfews.

Thank you for the work you and your community continue to put into environmental stewardship in Colusa County, from land and water conservation to public health — it''s the kind of leadership that doesn''t go unnoticed. Given that, I believe you and your community would be well-positioned to champion dark sky policy too.

Dark sky policies matter for more than stargazing. They cut wasted energy and utility costs, restore nocturnal habitat for birds, insects, and other wildlife whose migration and breeding cycles depend on natural darkness, and improve sleep and public health for residents. They also tend to pay for themselves quickly since well-shielded fixtures use less energy for the same or better visibility and safety.

I''m reaching out because Colusa County — and Colusa in particular — seems like a place where this policy would find real support, and where a local champion on the council or board could help move it forward.

One thing I''ve learned in this work: advocacy through public comment at council and board meetings is often a numbers-and-passion game. A handful of consistent, well-informed voices at the right meetings can shift a policy conversation faster than people expect. I''d love to help make sure Colusa has that support if you''re interested in pursuing this.

Any help you can offer — whether that''s raising it as an agenda item, connecting me with the right staff contact, or just pointing me toward others in Colusa who care about this — would be greatly appreciated.

If you''re interested in learning more, please reply to this email and I''ll follow up with further information, background material, and next steps.

Thank you again for your time and your work on behalf of Colusa and Colusa County.

Best,
Timothy Lee
SCVBA and FUHSD CC
'),
  ((select id from counties where fips = '013'), 'Dear Mayor and City Council of Walnut Creek,

Hello, my name is Timothy Lee, and I''m writing from SCVBA and FUHSD CC. I''ve been advocating for dark sky policies across California — local ordinances that reduce unnecessary outdoor light at night through simple measures like shielded fixtures, warmer color temperatures, and lighting curfews.

Thank you for the work you and your community continue to put into environmental stewardship in Contra Costa County, from land and water conservation to public health — it''s the kind of leadership that doesn''t go unnoticed. Given that, I believe you and your community would be well-positioned to champion dark sky policy too.

Dark sky policies matter for more than stargazing. They cut wasted energy and utility costs, restore nocturnal habitat for birds, insects, and other wildlife whose migration and breeding cycles depend on natural darkness, and improve sleep and public health for residents. They also tend to pay for themselves quickly since well-shielded fixtures use less energy for the same or better visibility and safety.

I''m reaching out because Contra Costa County — and Walnut Creek in particular — seems like a place where this policy would find real support, and where a local champion on the council or board could help move it forward.

One thing I''ve learned in this work: advocacy through public comment at council and board meetings is often a numbers-and-passion game. A handful of consistent, well-informed voices at the right meetings can shift a policy conversation faster than people expect. I''d love to help make sure Walnut Creek has that support if you''re interested in pursuing this.

Any help you can offer — whether that''s raising it as an agenda item, connecting me with the right staff contact, or just pointing me toward others in Walnut Creek who care about this — would be greatly appreciated.

If you''re interested in learning more, please reply to this email and I''ll follow up with further information, background material, and next steps.

Thank you again for your time and your work on behalf of Walnut Creek and Contra Costa County.

Best,
Timothy Lee
SCVBA and FUHSD CC
'),
  ((select id from counties where fips = '015'), 'Dear Mayor and City Council of Crescent City,

Hello, my name is Timothy Lee, and I''m writing from SCVBA and FUHSD CC. I''ve been advocating for dark sky policies across California — local ordinances that reduce unnecessary outdoor light at night through simple measures like shielded fixtures, warmer color temperatures, and lighting curfews.

Thank you for the work you and your community continue to put into environmental stewardship in Del Norte County, from land and water conservation to public health — it''s the kind of leadership that doesn''t go unnoticed. Given that, I believe you and your community would be well-positioned to champion dark sky policy too.

Dark sky policies matter for more than stargazing. They cut wasted energy and utility costs, restore nocturnal habitat for birds, insects, and other wildlife whose migration and breeding cycles depend on natural darkness, and improve sleep and public health for residents. They also tend to pay for themselves quickly since well-shielded fixtures use less energy for the same or better visibility and safety.

I''m reaching out because Del Norte County — and Crescent City in particular — seems like a place where this policy would find real support, and where a local champion on the council or board could help move it forward.

One thing I''ve learned in this work: advocacy through public comment at council and board meetings is often a numbers-and-passion game. A handful of consistent, well-informed voices at the right meetings can shift a policy conversation faster than people expect. I''d love to help make sure Crescent City has that support if you''re interested in pursuing this.

Any help you can offer — whether that''s raising it as an agenda item, connecting me with the right staff contact, or just pointing me toward others in Crescent City who care about this — would be greatly appreciated.

If you''re interested in learning more, please reply to this email and I''ll follow up with further information, background material, and next steps.

Thank you again for your time and your work on behalf of Crescent City and Del Norte County.

Best,
Timothy Lee
SCVBA and FUHSD CC
'),
  ((select id from counties where fips = '021'), 'Dear Mayor and City Council of Willows,

Hello, my name is Timothy Lee, and I''m writing from SCVBA and FUHSD CC. I''ve been advocating for dark sky policies across California — local ordinances that reduce unnecessary outdoor light at night through simple measures like shielded fixtures, warmer color temperatures, and lighting curfews.

Thank you for the work you and your community continue to put into environmental stewardship in Glenn County, from land and water conservation to public health — it''s the kind of leadership that doesn''t go unnoticed. Given that, I believe you and your community would be well-positioned to champion dark sky policy too.

Dark sky policies matter for more than stargazing. They cut wasted energy and utility costs, restore nocturnal habitat for birds, insects, and other wildlife whose migration and breeding cycles depend on natural darkness, and improve sleep and public health for residents. They also tend to pay for themselves quickly since well-shielded fixtures use less energy for the same or better visibility and safety.

I''m reaching out because Glenn County — and Willows in particular — seems like a place where this policy would find real support, and where a local champion on the council or board could help move it forward.

One thing I''ve learned in this work: advocacy through public comment at council and board meetings is often a numbers-and-passion game. A handful of consistent, well-informed voices at the right meetings can shift a policy conversation faster than people expect. I''d love to help make sure Willows has that support if you''re interested in pursuing this.

Any help you can offer — whether that''s raising it as an agenda item, connecting me with the right staff contact, or just pointing me toward others in Willows who care about this — would be greatly appreciated.

If you''re interested in learning more, please reply to this email and I''ll follow up with further information, background material, and next steps.

Thank you again for your time and your work on behalf of Willows and Glenn County.

Best,
Timothy Lee
SCVBA and FUHSD CC
'),
  ((select id from counties where fips = '023'), 'Dear Mayor and City Council of Arcata,

Hello, my name is Timothy Lee, and I''m writing from SCVBA and FUHSD CC. I''ve been advocating for dark sky policies across California — local ordinances that reduce unnecessary outdoor light at night through simple measures like shielded fixtures, warmer color temperatures, and lighting curfews.

Thank you for the work you and your community continue to put into environmental stewardship in Humboldt County, from land and water conservation to public health — it''s the kind of leadership that doesn''t go unnoticed. Given that, I believe you and your community would be well-positioned to champion dark sky policy too.

Dark sky policies matter for more than stargazing. They cut wasted energy and utility costs, restore nocturnal habitat for birds, insects, and other wildlife whose migration and breeding cycles depend on natural darkness, and improve sleep and public health for residents. They also tend to pay for themselves quickly since well-shielded fixtures use less energy for the same or better visibility and safety.

I''m reaching out because Humboldt County — and Arcata in particular — seems like a place where this policy would find real support, and where a local champion on the council or board could help move it forward.

One thing I''ve learned in this work: advocacy through public comment at council and board meetings is often a numbers-and-passion game. A handful of consistent, well-informed voices at the right meetings can shift a policy conversation faster than people expect. I''d love to help make sure Arcata has that support if you''re interested in pursuing this.

Any help you can offer — whether that''s raising it as an agenda item, connecting me with the right staff contact, or just pointing me toward others in Arcata who care about this — would be greatly appreciated.

If you''re interested in learning more, please reply to this email and I''ll follow up with further information, background material, and next steps.

Thank you again for your time and your work on behalf of Arcata and Humboldt County.

Best,
Timothy Lee
SCVBA and FUHSD CC
'),
  ((select id from counties where fips = '025'), 'Dear Mayor and City Council of El Centro,

Hello, my name is Timothy Lee, and I''m writing from SCVBA and FUHSD CC. I''ve been advocating for dark sky policies across California — local ordinances that reduce unnecessary outdoor light at night through simple measures like shielded fixtures, warmer color temperatures, and lighting curfews.

Thank you for the work you and your community continue to put into environmental stewardship in Imperial County, from land and water conservation to public health — it''s the kind of leadership that doesn''t go unnoticed. Given that, I believe you and your community would be well-positioned to champion dark sky policy too.

Dark sky policies matter for more than stargazing. They cut wasted energy and utility costs, restore nocturnal habitat for birds, insects, and other wildlife whose migration and breeding cycles depend on natural darkness, and improve sleep and public health for residents. They also tend to pay for themselves quickly since well-shielded fixtures use less energy for the same or better visibility and safety.

I''m reaching out because Imperial County — and El Centro in particular — seems like a place where this policy would find real support, and where a local champion on the council or board could help move it forward.

One thing I''ve learned in this work: advocacy through public comment at council and board meetings is often a numbers-and-passion game. A handful of consistent, well-informed voices at the right meetings can shift a policy conversation faster than people expect. I''d love to help make sure El Centro has that support if you''re interested in pursuing this.

Any help you can offer — whether that''s raising it as an agenda item, connecting me with the right staff contact, or just pointing me toward others in El Centro who care about this — would be greatly appreciated.

If you''re interested in learning more, please reply to this email and I''ll follow up with further information, background material, and next steps.

Thank you again for your time and your work on behalf of El Centro and Imperial County.

Best,
Timothy Lee
SCVBA and FUHSD CC
'),
  ((select id from counties where fips = '029'), 'Dear Mayor and City Council of Bakersfield,

Hello, my name is Timothy Lee, and I''m writing from SCVBA and FUHSD CC. I''ve been advocating for dark sky policies across California — local ordinances that reduce unnecessary outdoor light at night through simple measures like shielded fixtures, warmer color temperatures, and lighting curfews.

Thank you for the work you and your community continue to put into environmental stewardship in Kern County, from land and water conservation to public health — it''s the kind of leadership that doesn''t go unnoticed. Given that, I believe you and your community would be well-positioned to champion dark sky policy too.

Dark sky policies matter for more than stargazing. They cut wasted energy and utility costs, restore nocturnal habitat for birds, insects, and other wildlife whose migration and breeding cycles depend on natural darkness, and improve sleep and public health for residents. They also tend to pay for themselves quickly since well-shielded fixtures use less energy for the same or better visibility and safety.

I''m reaching out because Kern County — and Bakersfield in particular — seems like a place where this policy would find real support, and where a local champion on the council or board could help move it forward.

One thing I''ve learned in this work: advocacy through public comment at council and board meetings is often a numbers-and-passion game. A handful of consistent, well-informed voices at the right meetings can shift a policy conversation faster than people expect. I''d love to help make sure Bakersfield has that support if you''re interested in pursuing this.

Any help you can offer — whether that''s raising it as an agenda item, connecting me with the right staff contact, or just pointing me toward others in Bakersfield who care about this — would be greatly appreciated.

If you''re interested in learning more, please reply to this email and I''ll follow up with further information, background material, and next steps.

Thank you again for your time and your work on behalf of Bakersfield and Kern County.

Best,
Timothy Lee
SCVBA and FUHSD CC
'),
  ((select id from counties where fips = '031'), 'Dear Mayor and City Council of Hanford,

Hello, my name is Timothy Lee, and I''m writing from SCVBA and FUHSD CC. I''ve been advocating for dark sky policies across California — local ordinances that reduce unnecessary outdoor light at night through simple measures like shielded fixtures, warmer color temperatures, and lighting curfews.

Thank you for the work you and your community continue to put into environmental stewardship in Kings County, from land and water conservation to public health — it''s the kind of leadership that doesn''t go unnoticed. Given that, I believe you and your community would be well-positioned to champion dark sky policy too.

Dark sky policies matter for more than stargazing. They cut wasted energy and utility costs, restore nocturnal habitat for birds, insects, and other wildlife whose migration and breeding cycles depend on natural darkness, and improve sleep and public health for residents. They also tend to pay for themselves quickly since well-shielded fixtures use less energy for the same or better visibility and safety.

I''m reaching out because Kings County — and Hanford in particular — seems like a place where this policy would find real support, and where a local champion on the council or board could help move it forward.

One thing I''ve learned in this work: advocacy through public comment at council and board meetings is often a numbers-and-passion game. A handful of consistent, well-informed voices at the right meetings can shift a policy conversation faster than people expect. I''d love to help make sure Hanford has that support if you''re interested in pursuing this.

Any help you can offer — whether that''s raising it as an agenda item, connecting me with the right staff contact, or just pointing me toward others in Hanford who care about this — would be greatly appreciated.

If you''re interested in learning more, please reply to this email and I''ll follow up with further information, background material, and next steps.

Thank you again for your time and your work on behalf of Hanford and Kings County.

Best,
Timothy Lee
SCVBA and FUHSD CC
'),
  ((select id from counties where fips = '033'), 'Dear Mayor and City Council of Clearlake,

Hello, my name is Timothy Lee, and I''m writing from SCVBA and FUHSD CC. I''ve been advocating for dark sky policies across California — local ordinances that reduce unnecessary outdoor light at night through simple measures like shielded fixtures, warmer color temperatures, and lighting curfews.

Thank you for the work you and your community continue to put into environmental stewardship in Lake County, from land and water conservation to public health — it''s the kind of leadership that doesn''t go unnoticed. Given that, I believe you and your community would be well-positioned to champion dark sky policy too.

Dark sky policies matter for more than stargazing. They cut wasted energy and utility costs, restore nocturnal habitat for birds, insects, and other wildlife whose migration and breeding cycles depend on natural darkness, and improve sleep and public health for residents. They also tend to pay for themselves quickly since well-shielded fixtures use less energy for the same or better visibility and safety.

I''m reaching out because Lake County — and Clearlake in particular — seems like a place where this policy would find real support, and where a local champion on the council or board could help move it forward.

One thing I''ve learned in this work: advocacy through public comment at council and board meetings is often a numbers-and-passion game. A handful of consistent, well-informed voices at the right meetings can shift a policy conversation faster than people expect. I''d love to help make sure Clearlake has that support if you''re interested in pursuing this.

Any help you can offer — whether that''s raising it as an agenda item, connecting me with the right staff contact, or just pointing me toward others in Clearlake who care about this — would be greatly appreciated.

If you''re interested in learning more, please reply to this email and I''ll follow up with further information, background material, and next steps.

Thank you again for your time and your work on behalf of Clearlake and Lake County.

Best,
Timothy Lee
SCVBA and FUHSD CC
'),
  ((select id from counties where fips = '035'), 'Dear Mayor and City Council of Susanville,

Hello, my name is Timothy Lee, and I''m writing from SCVBA and FUHSD CC. I''ve been advocating for dark sky policies across California — local ordinances that reduce unnecessary outdoor light at night through simple measures like shielded fixtures, warmer color temperatures, and lighting curfews.

Thank you for the work you and your community continue to put into environmental stewardship in Lassen County, from land and water conservation to public health — it''s the kind of leadership that doesn''t go unnoticed. Given that, I believe you and your community would be well-positioned to champion dark sky policy too.

Dark sky policies matter for more than stargazing. They cut wasted energy and utility costs, restore nocturnal habitat for birds, insects, and other wildlife whose migration and breeding cycles depend on natural darkness, and improve sleep and public health for residents. They also tend to pay for themselves quickly since well-shielded fixtures use less energy for the same or better visibility and safety.

I''m reaching out because Lassen County — and Susanville in particular — seems like a place where this policy would find real support, and where a local champion on the council or board could help move it forward.

One thing I''ve learned in this work: advocacy through public comment at council and board meetings is often a numbers-and-passion game. A handful of consistent, well-informed voices at the right meetings can shift a policy conversation faster than people expect. I''d love to help make sure Susanville has that support if you''re interested in pursuing this.

Any help you can offer — whether that''s raising it as an agenda item, connecting me with the right staff contact, or just pointing me toward others in Susanville who care about this — would be greatly appreciated.

If you''re interested in learning more, please reply to this email and I''ll follow up with further information, background material, and next steps.

Thank you again for your time and your work on behalf of Susanville and Lassen County.

Best,
Timothy Lee
SCVBA and FUHSD CC
'),
  ((select id from counties where fips = '037'), 'Dear Mayor and City Council of Los Angeles,

Hello, my name is Timothy Lee, and I''m writing from SCVBA and FUHSD CC. I''ve been advocating for dark sky policies across California — local ordinances that reduce unnecessary outdoor light at night through simple measures like shielded fixtures, warmer color temperatures, and lighting curfews.

Thank you for the work you and your community continue to put into environmental stewardship in Los Angeles County, from land and water conservation to public health — it''s the kind of leadership that doesn''t go unnoticed. Given that, I believe you and your community would be well-positioned to champion dark sky policy too.

Dark sky policies matter for more than stargazing. They cut wasted energy and utility costs, restore nocturnal habitat for birds, insects, and other wildlife whose migration and breeding cycles depend on natural darkness, and improve sleep and public health for residents. They also tend to pay for themselves quickly since well-shielded fixtures use less energy for the same or better visibility and safety.

I''m reaching out because Los Angeles County — and Los Angeles in particular — seems like a place where this policy would find real support, and where a local champion on the council or board could help move it forward.

One thing I''ve learned in this work: advocacy through public comment at council and board meetings is often a numbers-and-passion game. A handful of consistent, well-informed voices at the right meetings can shift a policy conversation faster than people expect. I''d love to help make sure Los Angeles has that support if you''re interested in pursuing this.

Any help you can offer — whether that''s raising it as an agenda item, connecting me with the right staff contact, or just pointing me toward others in Los Angeles who care about this — would be greatly appreciated.

If you''re interested in learning more, please reply to this email and I''ll follow up with further information, background material, and next steps.

Thank you again for your time and your work on behalf of Los Angeles and Los Angeles County.

Best,
Timothy Lee
SCVBA and FUHSD CC
'),
  ((select id from counties where fips = '039'), 'Dear Mayor and City Council of Madera,

Hello, my name is Timothy Lee, and I''m writing from SCVBA and FUHSD CC. I''ve been advocating for dark sky policies across California — local ordinances that reduce unnecessary outdoor light at night through simple measures like shielded fixtures, warmer color temperatures, and lighting curfews.

Thank you for the work you and your community continue to put into environmental stewardship in Madera County, from land and water conservation to public health — it''s the kind of leadership that doesn''t go unnoticed. Given that, I believe you and your community would be well-positioned to champion dark sky policy too.

Dark sky policies matter for more than stargazing. They cut wasted energy and utility costs, restore nocturnal habitat for birds, insects, and other wildlife whose migration and breeding cycles depend on natural darkness, and improve sleep and public health for residents. They also tend to pay for themselves quickly since well-shielded fixtures use less energy for the same or better visibility and safety.

I''m reaching out because Madera County — and Madera in particular — seems like a place where this policy would find real support, and where a local champion on the council or board could help move it forward.

One thing I''ve learned in this work: advocacy through public comment at council and board meetings is often a numbers-and-passion game. A handful of consistent, well-informed voices at the right meetings can shift a policy conversation faster than people expect. I''d love to help make sure Madera has that support if you''re interested in pursuing this.

Any help you can offer — whether that''s raising it as an agenda item, connecting me with the right staff contact, or just pointing me toward others in Madera who care about this — would be greatly appreciated.

If you''re interested in learning more, please reply to this email and I''ll follow up with further information, background material, and next steps.

Thank you again for your time and your work on behalf of Madera and Madera County.

Best,
Timothy Lee
SCVBA and FUHSD CC
'),
  ((select id from counties where fips = '041'), 'Dear Mayor and City Council of San Rafael,

Hello, my name is Timothy Lee, and I''m writing from SCVBA and FUHSD CC. I''ve been advocating for dark sky policies across California — local ordinances that reduce unnecessary outdoor light at night through simple measures like shielded fixtures, warmer color temperatures, and lighting curfews.

Thank you for the work you and your community continue to put into environmental stewardship in Marin County, from land and water conservation to public health — it''s the kind of leadership that doesn''t go unnoticed. Given that, I believe you and your community would be well-positioned to champion dark sky policy too.

Dark sky policies matter for more than stargazing. They cut wasted energy and utility costs, restore nocturnal habitat for birds, insects, and other wildlife whose migration and breeding cycles depend on natural darkness, and improve sleep and public health for residents. They also tend to pay for themselves quickly since well-shielded fixtures use less energy for the same or better visibility and safety.

I''m reaching out because Marin County — and San Rafael in particular — seems like a place where this policy would find real support, and where a local champion on the council or board could help move it forward.

One thing I''ve learned in this work: advocacy through public comment at council and board meetings is often a numbers-and-passion game. A handful of consistent, well-informed voices at the right meetings can shift a policy conversation faster than people expect. I''d love to help make sure San Rafael has that support if you''re interested in pursuing this.

Any help you can offer — whether that''s raising it as an agenda item, connecting me with the right staff contact, or just pointing me toward others in San Rafael who care about this — would be greatly appreciated.

If you''re interested in learning more, please reply to this email and I''ll follow up with further information, background material, and next steps.

Thank you again for your time and your work on behalf of San Rafael and Marin County.

Best,
Timothy Lee
SCVBA and FUHSD CC
'),
  ((select id from counties where fips = '045'), 'Dear Mayor and City Council of Ukiah,

Hello, my name is Timothy Lee, and I''m writing from SCVBA and FUHSD CC. I''ve been advocating for dark sky policies across California — local ordinances that reduce unnecessary outdoor light at night through simple measures like shielded fixtures, warmer color temperatures, and lighting curfews.

Thank you for the work you and your community continue to put into environmental stewardship in Mendocino County, from land and water conservation to public health — it''s the kind of leadership that doesn''t go unnoticed. Given that, I believe you and your community would be well-positioned to champion dark sky policy too.

Dark sky policies matter for more than stargazing. They cut wasted energy and utility costs, restore nocturnal habitat for birds, insects, and other wildlife whose migration and breeding cycles depend on natural darkness, and improve sleep and public health for residents. They also tend to pay for themselves quickly since well-shielded fixtures use less energy for the same or better visibility and safety.

I''m reaching out because Mendocino County — and Ukiah in particular — seems like a place where this policy would find real support, and where a local champion on the council or board could help move it forward.

One thing I''ve learned in this work: advocacy through public comment at council and board meetings is often a numbers-and-passion game. A handful of consistent, well-informed voices at the right meetings can shift a policy conversation faster than people expect. I''d love to help make sure Ukiah has that support if you''re interested in pursuing this.

Any help you can offer — whether that''s raising it as an agenda item, connecting me with the right staff contact, or just pointing me toward others in Ukiah who care about this — would be greatly appreciated.

If you''re interested in learning more, please reply to this email and I''ll follow up with further information, background material, and next steps.

Thank you again for your time and your work on behalf of Ukiah and Mendocino County.

Best,
Timothy Lee
SCVBA and FUHSD CC
'),
  ((select id from counties where fips = '047'), 'Dear Mayor and City Council of Merced,

Hello, my name is Timothy Lee, and I''m writing from SCVBA and FUHSD CC. I''ve been advocating for dark sky policies across California — local ordinances that reduce unnecessary outdoor light at night through simple measures like shielded fixtures, warmer color temperatures, and lighting curfews.

Thank you for the work you and your community continue to put into environmental stewardship in Merced County, from land and water conservation to public health — it''s the kind of leadership that doesn''t go unnoticed. Given that, I believe you and your community would be well-positioned to champion dark sky policy too.

Dark sky policies matter for more than stargazing. They cut wasted energy and utility costs, restore nocturnal habitat for birds, insects, and other wildlife whose migration and breeding cycles depend on natural darkness, and improve sleep and public health for residents. They also tend to pay for themselves quickly since well-shielded fixtures use less energy for the same or better visibility and safety.

I''m reaching out because Merced County — and Merced in particular — seems like a place where this policy would find real support, and where a local champion on the council or board could help move it forward.

One thing I''ve learned in this work: advocacy through public comment at council and board meetings is often a numbers-and-passion game. A handful of consistent, well-informed voices at the right meetings can shift a policy conversation faster than people expect. I''d love to help make sure Merced has that support if you''re interested in pursuing this.

Any help you can offer — whether that''s raising it as an agenda item, connecting me with the right staff contact, or just pointing me toward others in Merced who care about this — would be greatly appreciated.

If you''re interested in learning more, please reply to this email and I''ll follow up with further information, background material, and next steps.

Thank you again for your time and your work on behalf of Merced and Merced County.

Best,
Timothy Lee
SCVBA and FUHSD CC
'),
  ((select id from counties where fips = '049'), 'Dear Mayor and City Council of Alturas,

Hello, my name is Timothy Lee, and I''m writing from SCVBA and FUHSD CC. I''ve been advocating for dark sky policies across California — local ordinances that reduce unnecessary outdoor light at night through simple measures like shielded fixtures, warmer color temperatures, and lighting curfews.

Thank you for the work you and your community continue to put into environmental stewardship in Modoc County, from land and water conservation to public health — it''s the kind of leadership that doesn''t go unnoticed. Given that, I believe you and your community would be well-positioned to champion dark sky policy too.

Dark sky policies matter for more than stargazing. They cut wasted energy and utility costs, restore nocturnal habitat for birds, insects, and other wildlife whose migration and breeding cycles depend on natural darkness, and improve sleep and public health for residents. They also tend to pay for themselves quickly since well-shielded fixtures use less energy for the same or better visibility and safety.

I''m reaching out because Modoc County — and Alturas in particular — seems like a place where this policy would find real support, and where a local champion on the council or board could help move it forward.

One thing I''ve learned in this work: advocacy through public comment at council and board meetings is often a numbers-and-passion game. A handful of consistent, well-informed voices at the right meetings can shift a policy conversation faster than people expect. I''d love to help make sure Alturas has that support if you''re interested in pursuing this.

Any help you can offer — whether that''s raising it as an agenda item, connecting me with the right staff contact, or just pointing me toward others in Alturas who care about this — would be greatly appreciated.

If you''re interested in learning more, please reply to this email and I''ll follow up with further information, background material, and next steps.

Thank you again for your time and your work on behalf of Alturas and Modoc County.

Best,
Timothy Lee
SCVBA and FUHSD CC
'),
  ((select id from counties where fips = '055'), 'Dear Mayor and City Council of Napa,

Hello, my name is Timothy Lee, and I''m writing from SCVBA and FUHSD CC. I''ve been advocating for dark sky policies across California — local ordinances that reduce unnecessary outdoor light at night through simple measures like shielded fixtures, warmer color temperatures, and lighting curfews.

Thank you for the work you and your community continue to put into environmental stewardship in Napa County, from land and water conservation to public health — it''s the kind of leadership that doesn''t go unnoticed. Given that, I believe you and your community would be well-positioned to champion dark sky policy too.

Dark sky policies matter for more than stargazing. They cut wasted energy and utility costs, restore nocturnal habitat for birds, insects, and other wildlife whose migration and breeding cycles depend on natural darkness, and improve sleep and public health for residents. They also tend to pay for themselves quickly since well-shielded fixtures use less energy for the same or better visibility and safety.

I''m reaching out because Napa County — and Napa in particular — seems like a place where this policy would find real support, and where a local champion on the council or board could help move it forward.

One thing I''ve learned in this work: advocacy through public comment at council and board meetings is often a numbers-and-passion game. A handful of consistent, well-informed voices at the right meetings can shift a policy conversation faster than people expect. I''d love to help make sure Napa has that support if you''re interested in pursuing this.

Any help you can offer — whether that''s raising it as an agenda item, connecting me with the right staff contact, or just pointing me toward others in Napa who care about this — would be greatly appreciated.

If you''re interested in learning more, please reply to this email and I''ll follow up with further information, background material, and next steps.

Thank you again for your time and your work on behalf of Napa and Napa County.

Best,
Timothy Lee
SCVBA and FUHSD CC
'),
  ((select id from counties where fips = '059'), 'Dear Mayor and City Council of Irvine,

Hello, my name is Timothy Lee, and I''m writing from SCVBA and FUHSD CC. I''ve been advocating for dark sky policies across California — local ordinances that reduce unnecessary outdoor light at night through simple measures like shielded fixtures, warmer color temperatures, and lighting curfews.

Thank you for the work you and your community continue to put into environmental stewardship in Orange County, from land and water conservation to public health — it''s the kind of leadership that doesn''t go unnoticed. Given that, I believe you and your community would be well-positioned to champion dark sky policy too.

Dark sky policies matter for more than stargazing. They cut wasted energy and utility costs, restore nocturnal habitat for birds, insects, and other wildlife whose migration and breeding cycles depend on natural darkness, and improve sleep and public health for residents. They also tend to pay for themselves quickly since well-shielded fixtures use less energy for the same or better visibility and safety.

I''m reaching out because Orange County — and Irvine in particular — seems like a place where this policy would find real support, and where a local champion on the council or board could help move it forward.

One thing I''ve learned in this work: advocacy through public comment at council and board meetings is often a numbers-and-passion game. A handful of consistent, well-informed voices at the right meetings can shift a policy conversation faster than people expect. I''d love to help make sure Irvine has that support if you''re interested in pursuing this.

Any help you can offer — whether that''s raising it as an agenda item, connecting me with the right staff contact, or just pointing me toward others in Irvine who care about this — would be greatly appreciated.

If you''re interested in learning more, please reply to this email and I''ll follow up with further information, background material, and next steps.

Thank you again for your time and your work on behalf of Irvine and Orange County.

Best,
Timothy Lee
SCVBA and FUHSD CC
'),
  ((select id from counties where fips = '063'), 'Dear Mayor and City Council of Portola,

Hello, my name is Timothy Lee, and I''m writing from SCVBA and FUHSD CC. I''ve been advocating for dark sky policies across California — local ordinances that reduce unnecessary outdoor light at night through simple measures like shielded fixtures, warmer color temperatures, and lighting curfews.

Thank you for the work you and your community continue to put into environmental stewardship in Plumas County, from land and water conservation to public health — it''s the kind of leadership that doesn''t go unnoticed. Given that, I believe you and your community would be well-positioned to champion dark sky policy too.

Dark sky policies matter for more than stargazing. They cut wasted energy and utility costs, restore nocturnal habitat for birds, insects, and other wildlife whose migration and breeding cycles depend on natural darkness, and improve sleep and public health for residents. They also tend to pay for themselves quickly since well-shielded fixtures use less energy for the same or better visibility and safety.

I''m reaching out because Plumas County — and Portola in particular — seems like a place where this policy would find real support, and where a local champion on the council or board could help move it forward.

One thing I''ve learned in this work: advocacy through public comment at council and board meetings is often a numbers-and-passion game. A handful of consistent, well-informed voices at the right meetings can shift a policy conversation faster than people expect. I''d love to help make sure Portola has that support if you''re interested in pursuing this.

Any help you can offer — whether that''s raising it as an agenda item, connecting me with the right staff contact, or just pointing me toward others in Portola who care about this — would be greatly appreciated.

If you''re interested in learning more, please reply to this email and I''ll follow up with further information, background material, and next steps.

Thank you again for your time and your work on behalf of Portola and Plumas County.

Best,
Timothy Lee
SCVBA and FUHSD CC
'),
  ((select id from counties where fips = '069'), 'Dear Mayor and City Council of Hollister,

Hello, my name is Timothy Lee, and I''m writing from SCVBA and FUHSD CC. I''ve been advocating for dark sky policies across California — local ordinances that reduce unnecessary outdoor light at night through simple measures like shielded fixtures, warmer color temperatures, and lighting curfews.

Thank you for the work you and your community continue to put into environmental stewardship in San Benito County, from land and water conservation to public health — it''s the kind of leadership that doesn''t go unnoticed. Given that, I believe you and your community would be well-positioned to champion dark sky policy too.

Dark sky policies matter for more than stargazing. They cut wasted energy and utility costs, restore nocturnal habitat for birds, insects, and other wildlife whose migration and breeding cycles depend on natural darkness, and improve sleep and public health for residents. They also tend to pay for themselves quickly since well-shielded fixtures use less energy for the same or better visibility and safety.

I''m reaching out because San Benito County — and Hollister in particular — seems like a place where this policy would find real support, and where a local champion on the council or board could help move it forward.

One thing I''ve learned in this work: advocacy through public comment at council and board meetings is often a numbers-and-passion game. A handful of consistent, well-informed voices at the right meetings can shift a policy conversation faster than people expect. I''d love to help make sure Hollister has that support if you''re interested in pursuing this.

Any help you can offer — whether that''s raising it as an agenda item, connecting me with the right staff contact, or just pointing me toward others in Hollister who care about this — would be greatly appreciated.

If you''re interested in learning more, please reply to this email and I''ll follow up with further information, background material, and next steps.

Thank you again for your time and your work on behalf of Hollister and San Benito County.

Best,
Timothy Lee
SCVBA and FUHSD CC
'),
  ((select id from counties where fips = '075'), 'Dear Mayor and City Council of San Francisco,

Hello, my name is Timothy Lee, and I''m writing from SCVBA and FUHSD CC. I''ve been advocating for dark sky policies across California — local ordinances that reduce unnecessary outdoor light at night through simple measures like shielded fixtures, warmer color temperatures, and lighting curfews.

Thank you for the work you and your community continue to put into environmental stewardship in San Francisco County, from land and water conservation to public health — it''s the kind of leadership that doesn''t go unnoticed. Given that, I believe you and your community would be well-positioned to champion dark sky policy too.

Dark sky policies matter for more than stargazing. They cut wasted energy and utility costs, restore nocturnal habitat for birds, insects, and other wildlife whose migration and breeding cycles depend on natural darkness, and improve sleep and public health for residents. They also tend to pay for themselves quickly since well-shielded fixtures use less energy for the same or better visibility and safety.

I''m reaching out because San Francisco County — and San Francisco in particular — seems like a place where this policy would find real support, and where a local champion on the council or board could help move it forward.

One thing I''ve learned in this work: advocacy through public comment at council and board meetings is often a numbers-and-passion game. A handful of consistent, well-informed voices at the right meetings can shift a policy conversation faster than people expect. I''d love to help make sure San Francisco has that support if you''re interested in pursuing this.

Any help you can offer — whether that''s raising it as an agenda item, connecting me with the right staff contact, or just pointing me toward others in San Francisco who care about this — would be greatly appreciated.

If you''re interested in learning more, please reply to this email and I''ll follow up with further information, background material, and next steps.

Thank you again for your time and your work on behalf of San Francisco and San Francisco County.

Best,
Timothy Lee
SCVBA and FUHSD CC
'),
  ((select id from counties where fips = '077'), 'Dear Mayor and City Council of Stockton,

Hello, my name is Timothy Lee, and I''m writing from SCVBA and FUHSD CC. I''ve been advocating for dark sky policies across California — local ordinances that reduce unnecessary outdoor light at night through simple measures like shielded fixtures, warmer color temperatures, and lighting curfews.

Thank you for the work you and your community continue to put into environmental stewardship in San Joaquin County, from land and water conservation to public health — it''s the kind of leadership that doesn''t go unnoticed. Given that, I believe you and your community would be well-positioned to champion dark sky policy too.

Dark sky policies matter for more than stargazing. They cut wasted energy and utility costs, restore nocturnal habitat for birds, insects, and other wildlife whose migration and breeding cycles depend on natural darkness, and improve sleep and public health for residents. They also tend to pay for themselves quickly since well-shielded fixtures use less energy for the same or better visibility and safety.

I''m reaching out because San Joaquin County — and Stockton in particular — seems like a place where this policy would find real support, and where a local champion on the council or board could help move it forward.

One thing I''ve learned in this work: advocacy through public comment at council and board meetings is often a numbers-and-passion game. A handful of consistent, well-informed voices at the right meetings can shift a policy conversation faster than people expect. I''d love to help make sure Stockton has that support if you''re interested in pursuing this.

Any help you can offer — whether that''s raising it as an agenda item, connecting me with the right staff contact, or just pointing me toward others in Stockton who care about this — would be greatly appreciated.

If you''re interested in learning more, please reply to this email and I''ll follow up with further information, background material, and next steps.

Thank you again for your time and your work on behalf of Stockton and San Joaquin County.

Best,
Timothy Lee
SCVBA and FUHSD CC
'),
  ((select id from counties where fips = '089'), 'Dear Mayor and City Council of Redding,

Hello, my name is Timothy Lee, and I''m writing from SCVBA and FUHSD CC. I''ve been advocating for dark sky policies across California — local ordinances that reduce unnecessary outdoor light at night through simple measures like shielded fixtures, warmer color temperatures, and lighting curfews.

Thank you for the work you and your community continue to put into environmental stewardship in Shasta County, from land and water conservation to public health — it''s the kind of leadership that doesn''t go unnoticed. Given that, I believe you and your community would be well-positioned to champion dark sky policy too.

Dark sky policies matter for more than stargazing. They cut wasted energy and utility costs, restore nocturnal habitat for birds, insects, and other wildlife whose migration and breeding cycles depend on natural darkness, and improve sleep and public health for residents. They also tend to pay for themselves quickly since well-shielded fixtures use less energy for the same or better visibility and safety.

I''m reaching out because Shasta County — and Redding in particular — seems like a place where this policy would find real support, and where a local champion on the council or board could help move it forward.

One thing I''ve learned in this work: advocacy through public comment at council and board meetings is often a numbers-and-passion game. A handful of consistent, well-informed voices at the right meetings can shift a policy conversation faster than people expect. I''d love to help make sure Redding has that support if you''re interested in pursuing this.

Any help you can offer — whether that''s raising it as an agenda item, connecting me with the right staff contact, or just pointing me toward others in Redding who care about this — would be greatly appreciated.

If you''re interested in learning more, please reply to this email and I''ll follow up with further information, background material, and next steps.

Thank you again for your time and your work on behalf of Redding and Shasta County.

Best,
Timothy Lee
SCVBA and FUHSD CC
'),
  ((select id from counties where fips = '091'), 'Dear Mayor and City Council of Loyalton,

Hello, my name is Timothy Lee, and I''m writing from SCVBA and FUHSD CC. I''ve been advocating for dark sky policies across California — local ordinances that reduce unnecessary outdoor light at night through simple measures like shielded fixtures, warmer color temperatures, and lighting curfews.

Thank you for the work you and your community continue to put into environmental stewardship in Sierra County, from land and water conservation to public health — it''s the kind of leadership that doesn''t go unnoticed. Given that, I believe you and your community would be well-positioned to champion dark sky policy too.

Dark sky policies matter for more than stargazing. They cut wasted energy and utility costs, restore nocturnal habitat for birds, insects, and other wildlife whose migration and breeding cycles depend on natural darkness, and improve sleep and public health for residents. They also tend to pay for themselves quickly since well-shielded fixtures use less energy for the same or better visibility and safety.

I''m reaching out because Sierra County — and Loyalton in particular — seems like a place where this policy would find real support, and where a local champion on the council or board could help move it forward.

One thing I''ve learned in this work: advocacy through public comment at council and board meetings is often a numbers-and-passion game. A handful of consistent, well-informed voices at the right meetings can shift a policy conversation faster than people expect. I''d love to help make sure Loyalton has that support if you''re interested in pursuing this.

Any help you can offer — whether that''s raising it as an agenda item, connecting me with the right staff contact, or just pointing me toward others in Loyalton who care about this — would be greatly appreciated.

If you''re interested in learning more, please reply to this email and I''ll follow up with further information, background material, and next steps.

Thank you again for your time and your work on behalf of Loyalton and Sierra County.

Best,
Timothy Lee
SCVBA and FUHSD CC
'),
  ((select id from counties where fips = '093'), 'Dear Mayor and City Council of Mount Shasta,

Hello, my name is Timothy Lee, and I''m writing from SCVBA and FUHSD CC. I''ve been advocating for dark sky policies across California — local ordinances that reduce unnecessary outdoor light at night through simple measures like shielded fixtures, warmer color temperatures, and lighting curfews.

Thank you for the work you and your community continue to put into environmental stewardship in Siskiyou County, from land and water conservation to public health — it''s the kind of leadership that doesn''t go unnoticed. Given that, I believe you and your community would be well-positioned to champion dark sky policy too.

Dark sky policies matter for more than stargazing. They cut wasted energy and utility costs, restore nocturnal habitat for birds, insects, and other wildlife whose migration and breeding cycles depend on natural darkness, and improve sleep and public health for residents. They also tend to pay for themselves quickly since well-shielded fixtures use less energy for the same or better visibility and safety.

I''m reaching out because Siskiyou County — and Mount Shasta in particular — seems like a place where this policy would find real support, and where a local champion on the council or board could help move it forward.

One thing I''ve learned in this work: advocacy through public comment at council and board meetings is often a numbers-and-passion game. A handful of consistent, well-informed voices at the right meetings can shift a policy conversation faster than people expect. I''d love to help make sure Mount Shasta has that support if you''re interested in pursuing this.

Any help you can offer — whether that''s raising it as an agenda item, connecting me with the right staff contact, or just pointing me toward others in Mount Shasta who care about this — would be greatly appreciated.

If you''re interested in learning more, please reply to this email and I''ll follow up with further information, background material, and next steps.

Thank you again for your time and your work on behalf of Mount Shasta and Siskiyou County.

Best,
Timothy Lee
SCVBA and FUHSD CC
'),
  ((select id from counties where fips = '095'), 'Dear Mayor and City Council of Vacaville,

Hello, my name is Timothy Lee, and I''m writing from SCVBA and FUHSD CC. I''ve been advocating for dark sky policies across California — local ordinances that reduce unnecessary outdoor light at night through simple measures like shielded fixtures, warmer color temperatures, and lighting curfews.

Thank you for the work you and your community continue to put into environmental stewardship in Solano County, from land and water conservation to public health — it''s the kind of leadership that doesn''t go unnoticed. Given that, I believe you and your community would be well-positioned to champion dark sky policy too.

Dark sky policies matter for more than stargazing. They cut wasted energy and utility costs, restore nocturnal habitat for birds, insects, and other wildlife whose migration and breeding cycles depend on natural darkness, and improve sleep and public health for residents. They also tend to pay for themselves quickly since well-shielded fixtures use less energy for the same or better visibility and safety.

I''m reaching out because Solano County — and Vacaville in particular — seems like a place where this policy would find real support, and where a local champion on the council or board could help move it forward.

One thing I''ve learned in this work: advocacy through public comment at council and board meetings is often a numbers-and-passion game. A handful of consistent, well-informed voices at the right meetings can shift a policy conversation faster than people expect. I''d love to help make sure Vacaville has that support if you''re interested in pursuing this.

Any help you can offer — whether that''s raising it as an agenda item, connecting me with the right staff contact, or just pointing me toward others in Vacaville who care about this — would be greatly appreciated.

If you''re interested in learning more, please reply to this email and I''ll follow up with further information, background material, and next steps.

Thank you again for your time and your work on behalf of Vacaville and Solano County.

Best,
Timothy Lee
SCVBA and FUHSD CC
'),
  ((select id from counties where fips = '097'), 'Dear Mayor and City Council of Santa Rosa,

Hello, my name is Timothy Lee, and I''m writing from SCVBA and FUHSD CC. I''ve been advocating for dark sky policies across California — local ordinances that reduce unnecessary outdoor light at night through simple measures like shielded fixtures, warmer color temperatures, and lighting curfews.

Thank you for the work you and your community continue to put into environmental stewardship in Sonoma County, from land and water conservation to public health — it''s the kind of leadership that doesn''t go unnoticed. Given that, I believe you and your community would be well-positioned to champion dark sky policy too.

Dark sky policies matter for more than stargazing. They cut wasted energy and utility costs, restore nocturnal habitat for birds, insects, and other wildlife whose migration and breeding cycles depend on natural darkness, and improve sleep and public health for residents. They also tend to pay for themselves quickly since well-shielded fixtures use less energy for the same or better visibility and safety.

I''m reaching out because Sonoma County — and Santa Rosa in particular — seems like a place where this policy would find real support, and where a local champion on the council or board could help move it forward.

One thing I''ve learned in this work: advocacy through public comment at council and board meetings is often a numbers-and-passion game. A handful of consistent, well-informed voices at the right meetings can shift a policy conversation faster than people expect. I''d love to help make sure Santa Rosa has that support if you''re interested in pursuing this.

Any help you can offer — whether that''s raising it as an agenda item, connecting me with the right staff contact, or just pointing me toward others in Santa Rosa who care about this — would be greatly appreciated.

If you''re interested in learning more, please reply to this email and I''ll follow up with further information, background material, and next steps.

Thank you again for your time and your work on behalf of Santa Rosa and Sonoma County.

Best,
Timothy Lee
SCVBA and FUHSD CC
'),
  ((select id from counties where fips = '099'), 'Dear Mayor and City Council of Modesto,

Hello, my name is Timothy Lee, and I''m writing from SCVBA and FUHSD CC. I''ve been advocating for dark sky policies across California — local ordinances that reduce unnecessary outdoor light at night through simple measures like shielded fixtures, warmer color temperatures, and lighting curfews.

Thank you for the work you and your community continue to put into environmental stewardship in Stanislaus County, from land and water conservation to public health — it''s the kind of leadership that doesn''t go unnoticed. Given that, I believe you and your community would be well-positioned to champion dark sky policy too.

Dark sky policies matter for more than stargazing. They cut wasted energy and utility costs, restore nocturnal habitat for birds, insects, and other wildlife whose migration and breeding cycles depend on natural darkness, and improve sleep and public health for residents. They also tend to pay for themselves quickly since well-shielded fixtures use less energy for the same or better visibility and safety.

I''m reaching out because Stanislaus County — and Modesto in particular — seems like a place where this policy would find real support, and where a local champion on the council or board could help move it forward.

One thing I''ve learned in this work: advocacy through public comment at council and board meetings is often a numbers-and-passion game. A handful of consistent, well-informed voices at the right meetings can shift a policy conversation faster than people expect. I''d love to help make sure Modesto has that support if you''re interested in pursuing this.

Any help you can offer — whether that''s raising it as an agenda item, connecting me with the right staff contact, or just pointing me toward others in Modesto who care about this — would be greatly appreciated.

If you''re interested in learning more, please reply to this email and I''ll follow up with further information, background material, and next steps.

Thank you again for your time and your work on behalf of Modesto and Stanislaus County.

Best,
Timothy Lee
SCVBA and FUHSD CC
'),
  ((select id from counties where fips = '101'), 'Dear Mayor and City Council of Yuba City,

Hello, my name is Timothy Lee, and I''m writing from SCVBA and FUHSD CC. I''ve been advocating for dark sky policies across California — local ordinances that reduce unnecessary outdoor light at night through simple measures like shielded fixtures, warmer color temperatures, and lighting curfews.

Thank you for the work you and your community continue to put into environmental stewardship in Sutter County, from land and water conservation to public health — it''s the kind of leadership that doesn''t go unnoticed. Given that, I believe you and your community would be well-positioned to champion dark sky policy too.

Dark sky policies matter for more than stargazing. They cut wasted energy and utility costs, restore nocturnal habitat for birds, insects, and other wildlife whose migration and breeding cycles depend on natural darkness, and improve sleep and public health for residents. They also tend to pay for themselves quickly since well-shielded fixtures use less energy for the same or better visibility and safety.

I''m reaching out because Sutter County — and Yuba City in particular — seems like a place where this policy would find real support, and where a local champion on the council or board could help move it forward.

One thing I''ve learned in this work: advocacy through public comment at council and board meetings is often a numbers-and-passion game. A handful of consistent, well-informed voices at the right meetings can shift a policy conversation faster than people expect. I''d love to help make sure Yuba City has that support if you''re interested in pursuing this.

Any help you can offer — whether that''s raising it as an agenda item, connecting me with the right staff contact, or just pointing me toward others in Yuba City who care about this — would be greatly appreciated.

If you''re interested in learning more, please reply to this email and I''ll follow up with further information, background material, and next steps.

Thank you again for your time and your work on behalf of Yuba City and Sutter County.

Best,
Timothy Lee
SCVBA and FUHSD CC
'),
  ((select id from counties where fips = '103'), 'Dear Mayor and City Council of Red Bluff,

Hello, my name is Timothy Lee, and I''m writing from SCVBA and FUHSD CC. I''ve been advocating for dark sky policies across California — local ordinances that reduce unnecessary outdoor light at night through simple measures like shielded fixtures, warmer color temperatures, and lighting curfews.

Thank you for the work you and your community continue to put into environmental stewardship in Tehama County, from land and water conservation to public health — it''s the kind of leadership that doesn''t go unnoticed. Given that, I believe you and your community would be well-positioned to champion dark sky policy too.

Dark sky policies matter for more than stargazing. They cut wasted energy and utility costs, restore nocturnal habitat for birds, insects, and other wildlife whose migration and breeding cycles depend on natural darkness, and improve sleep and public health for residents. They also tend to pay for themselves quickly since well-shielded fixtures use less energy for the same or better visibility and safety.

I''m reaching out because Tehama County — and Red Bluff in particular — seems like a place where this policy would find real support, and where a local champion on the council or board could help move it forward.

One thing I''ve learned in this work: advocacy through public comment at council and board meetings is often a numbers-and-passion game. A handful of consistent, well-informed voices at the right meetings can shift a policy conversation faster than people expect. I''d love to help make sure Red Bluff has that support if you''re interested in pursuing this.

Any help you can offer — whether that''s raising it as an agenda item, connecting me with the right staff contact, or just pointing me toward others in Red Bluff who care about this — would be greatly appreciated.

If you''re interested in learning more, please reply to this email and I''ll follow up with further information, background material, and next steps.

Thank you again for your time and your work on behalf of Red Bluff and Tehama County.

Best,
Timothy Lee
SCVBA and FUHSD CC
'),
  ((select id from counties where fips = '105'), 'Dear Trinity County Board of Supervisors,

Hello, my name is Timothy Lee, and I''m writing from SCVBA and FUHSD CC. I''ve been advocating for dark sky policies across California — local ordinances that reduce unnecessary outdoor light at night through simple measures like shielded fixtures, warmer color temperatures, and lighting curfews.

Thank you for the work you and your community continue to put into environmental stewardship in Trinity County, from land and water conservation to public health — it''s the kind of leadership that doesn''t go unnoticed. Given that, I believe you and your community would be well-positioned to champion dark sky policy too.

Dark sky policies matter for more than stargazing. They cut wasted energy and utility costs, restore nocturnal habitat for birds, insects, and other wildlife whose migration and breeding cycles depend on natural darkness, and improve sleep and public health for residents. They also tend to pay for themselves quickly since well-shielded fixtures use less energy for the same or better visibility and safety.

I''m reaching out because Trinity County — and Weaverville in particular — seems like a place where this policy would find real support, and where a local champion on the council or board could help move it forward.

One thing I''ve learned in this work: advocacy through public comment at council and board meetings is often a numbers-and-passion game. A handful of consistent, well-informed voices at the right meetings can shift a policy conversation faster than people expect. I''d love to help make sure Weaverville has that support if you''re interested in pursuing this.

Any help you can offer — whether that''s raising it as an agenda item, connecting me with the right staff contact, or just pointing me toward others in Weaverville who care about this — would be greatly appreciated.

If you''re interested in learning more, please reply to this email and I''ll follow up with further information, background material, and next steps.

Thank you again for your time and your work on behalf of Weaverville and Trinity County.

Best,
Timothy Lee
SCVBA and FUHSD CC
'),
  ((select id from counties where fips = '109'), 'Dear Mayor and City Council of Sonora,

Hello, my name is Timothy Lee, and I''m writing from SCVBA and FUHSD CC. I''ve been advocating for dark sky policies across California — local ordinances that reduce unnecessary outdoor light at night through simple measures like shielded fixtures, warmer color temperatures, and lighting curfews.

Thank you for the work you and your community continue to put into environmental stewardship in Tuolumne County, from land and water conservation to public health — it''s the kind of leadership that doesn''t go unnoticed. Given that, I believe you and your community would be well-positioned to champion dark sky policy too.

Dark sky policies matter for more than stargazing. They cut wasted energy and utility costs, restore nocturnal habitat for birds, insects, and other wildlife whose migration and breeding cycles depend on natural darkness, and improve sleep and public health for residents. They also tend to pay for themselves quickly since well-shielded fixtures use less energy for the same or better visibility and safety.

I''m reaching out because Tuolumne County — and Sonora in particular — seems like a place where this policy would find real support, and where a local champion on the council or board could help move it forward.

One thing I''ve learned in this work: advocacy through public comment at council and board meetings is often a numbers-and-passion game. A handful of consistent, well-informed voices at the right meetings can shift a policy conversation faster than people expect. I''d love to help make sure Sonora has that support if you''re interested in pursuing this.

Any help you can offer — whether that''s raising it as an agenda item, connecting me with the right staff contact, or just pointing me toward others in Sonora who care about this — would be greatly appreciated.

If you''re interested in learning more, please reply to this email and I''ll follow up with further information, background material, and next steps.

Thank you again for your time and your work on behalf of Sonora and Tuolumne County.

Best,
Timothy Lee
SCVBA and FUHSD CC
'),
  ((select id from counties where fips = '111'), 'Dear Mayor and City Council of Ventura,

Hello, my name is Timothy Lee, and I''m writing from SCVBA and FUHSD CC. I''ve been advocating for dark sky policies across California — local ordinances that reduce unnecessary outdoor light at night through simple measures like shielded fixtures, warmer color temperatures, and lighting curfews.

Thank you for the work you and your community continue to put into environmental stewardship in Ventura County, from land and water conservation to public health — it''s the kind of leadership that doesn''t go unnoticed. Given that, I believe you and your community would be well-positioned to champion dark sky policy too.

Dark sky policies matter for more than stargazing. They cut wasted energy and utility costs, restore nocturnal habitat for birds, insects, and other wildlife whose migration and breeding cycles depend on natural darkness, and improve sleep and public health for residents. They also tend to pay for themselves quickly since well-shielded fixtures use less energy for the same or better visibility and safety.

I''m reaching out because Ventura County — and Ventura in particular — seems like a place where this policy would find real support, and where a local champion on the council or board could help move it forward.

One thing I''ve learned in this work: advocacy through public comment at council and board meetings is often a numbers-and-passion game. A handful of consistent, well-informed voices at the right meetings can shift a policy conversation faster than people expect. I''d love to help make sure Ventura has that support if you''re interested in pursuing this.

Any help you can offer — whether that''s raising it as an agenda item, connecting me with the right staff contact, or just pointing me toward others in Ventura who care about this — would be greatly appreciated.

If you''re interested in learning more, please reply to this email and I''ll follow up with further information, background material, and next steps.

Thank you again for your time and your work on behalf of Ventura and Ventura County.

Best,
Timothy Lee
SCVBA and FUHSD CC
'),
  ((select id from counties where fips = '113'), 'Dear Mayor and City Council of Davis,

Hello, my name is Timothy Lee, and I''m writing from SCVBA and FUHSD CC. I''ve been advocating for dark sky policies across California — local ordinances that reduce unnecessary outdoor light at night through simple measures like shielded fixtures, warmer color temperatures, and lighting curfews.

Thank you for the work you and your community continue to put into environmental stewardship in Yolo County, from land and water conservation to public health — it''s the kind of leadership that doesn''t go unnoticed. Given that, I believe you and your community would be well-positioned to champion dark sky policy too.

Dark sky policies matter for more than stargazing. They cut wasted energy and utility costs, restore nocturnal habitat for birds, insects, and other wildlife whose migration and breeding cycles depend on natural darkness, and improve sleep and public health for residents. They also tend to pay for themselves quickly since well-shielded fixtures use less energy for the same or better visibility and safety.

I''m reaching out because Yolo County — and Davis in particular — seems like a place where this policy would find real support, and where a local champion on the council or board could help move it forward.

One thing I''ve learned in this work: advocacy through public comment at council and board meetings is often a numbers-and-passion game. A handful of consistent, well-informed voices at the right meetings can shift a policy conversation faster than people expect. I''d love to help make sure Davis has that support if you''re interested in pursuing this.

Any help you can offer — whether that''s raising it as an agenda item, connecting me with the right staff contact, or just pointing me toward others in Davis who care about this — would be greatly appreciated.

If you''re interested in learning more, please reply to this email and I''ll follow up with further information, background material, and next steps.

Thank you again for your time and your work on behalf of Davis and Yolo County.

Best,
Timothy Lee
SCVBA and FUHSD CC
'),
  ((select id from counties where fips = '115'), 'Dear Mayor and City Council of Marysville,

Hello, my name is Timothy Lee, and I''m writing from SCVBA and FUHSD CC. I''ve been advocating for dark sky policies across California — local ordinances that reduce unnecessary outdoor light at night through simple measures like shielded fixtures, warmer color temperatures, and lighting curfews.

Thank you for the work you and your community continue to put into environmental stewardship in Yuba County, from land and water conservation to public health — it''s the kind of leadership that doesn''t go unnoticed. Given that, I believe you and your community would be well-positioned to champion dark sky policy too.

Dark sky policies matter for more than stargazing. They cut wasted energy and utility costs, restore nocturnal habitat for birds, insects, and other wildlife whose migration and breeding cycles depend on natural darkness, and improve sleep and public health for residents. They also tend to pay for themselves quickly since well-shielded fixtures use less energy for the same or better visibility and safety.

I''m reaching out because Yuba County — and Marysville in particular — seems like a place where this policy would find real support, and where a local champion on the council or board could help move it forward.

One thing I''ve learned in this work: advocacy through public comment at council and board meetings is often a numbers-and-passion game. A handful of consistent, well-informed voices at the right meetings can shift a policy conversation faster than people expect. I''d love to help make sure Marysville has that support if you''re interested in pursuing this.

Any help you can offer — whether that''s raising it as an agenda item, connecting me with the right staff contact, or just pointing me toward others in Marysville who care about this — would be greatly appreciated.

If you''re interested in learning more, please reply to this email and I''ll follow up with further information, background material, and next steps.

Thank you again for your time and your work on behalf of Marysville and Yuba County.

Best,
Timothy Lee
SCVBA and FUHSD CC
')
on conflict (county_id) do update set body = excluded.body, updated_at = now();

-- 1 statewide channel + 1 per county = 59 total (spec §5)
insert into channels (kind, county_id, name, slug)
values ('statewide', null, 'California Statewide', 'statewide')
on conflict (slug) do nothing;

insert into channels (kind, county_id, name, slug)
select 'county', id, name || ' County', slug from counties
on conflict (slug) do nothing;

commit;

