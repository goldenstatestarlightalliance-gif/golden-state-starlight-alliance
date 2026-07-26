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

-- The recurring schedule for this lives in 0004_cron.sql, which runs OUTSIDE
-- the main transaction: it depends on the pg_cron extension being enabled, and
-- a failure there must not roll back the schema.

-- ---------------------------------------------------------------------------
-- Realtime (spec §5)
-- ---------------------------------------------------------------------------

-- Publish messages so Supabase Realtime streams inserts/updates to subscribed
-- clients. RLS still applies to what each client actually receives.
alter publication supabase_realtime add table messages;
alter publication supabase_realtime add table events;
