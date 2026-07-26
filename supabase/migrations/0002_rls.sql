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
