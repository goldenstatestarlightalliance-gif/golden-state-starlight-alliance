-- Golden State Starlight Alliance — private org channels + bot moderation.
--
-- RUN 0008 FIRST. This file uses channel_kind = 'org', which only exists once
-- 0008 has committed.
--
-- Two things happen here:
--
--   1. Organizations get their own private channel, in addition to the 58
--      county channels and the statewide one (spec §5 left this as an open
--      question; the founder chose to add them).
--
--   2. The automated spam/profanity filter the spec calls for on the statewide
--      channel (spec §5) finally exists, as a BEFORE INSERT trigger.
--
-- IMPORTANT CONSEQUENCE OF (1): until now every authenticated member could read
-- every message in every channel, which was fine when all channels were public.
-- Org channels are private, so the read policy is rewritten below. If you skip
-- that part, org channels are private in name only.

begin;

-- ---------------------------------------------------------------------------
-- 1. Schema: channels can now belong to an org
-- ---------------------------------------------------------------------------

alter table channels add column if not exists org_id bigint
  references organizations(id) on delete cascade;

-- The old constraint only knew about statewide and county. Replace it with one
-- that pins each kind to exactly one owning column and forbids the others.
alter table channels drop constraint if exists channel_scope;
alter table channels add constraint channel_scope check (
  (kind = 'statewide' and county_id is null     and org_id is null) or
  (kind = 'county'    and county_id is not null and org_id is null) or
  (kind = 'org'       and county_id is null     and org_id is not null)
);

create unique index if not exists one_channel_per_org
  on channels(org_id) where org_id is not null;

-- ---------------------------------------------------------------------------
-- 2. Backfill a channel for every existing organization
-- ---------------------------------------------------------------------------

-- Channels are created for ALL orgs, not just approved ones. They cost nothing
-- while empty, they are invisible to non-members, and creating them up front
-- means an org that gets approved later already has its space rather than
-- silently having none.
insert into channels (kind, org_id, name, slug)
select 'org', o.id, o.name, 'org-' || o.slug
from organizations o
on conflict (slug) do nothing;

-- New orgs get one automatically, so this never drifts again.
create or replace function create_org_channel()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into channels (kind, org_id, name, slug)
  values ('org', new.id, new.name, 'org-' || new.slug)
  on conflict (slug) do nothing;
  return new;
end $$;

drop trigger if exists organizations_create_channel on organizations;
create trigger organizations_create_channel
  after insert on organizations
  for each row execute function create_org_channel();

-- ---------------------------------------------------------------------------
-- 3. Who may see a channel at all
-- ---------------------------------------------------------------------------

-- Statewide and county channels are open to every member. An org channel is
-- visible only to that org's members, plus admins for moderation.
create or replace function can_read_channel(target_channel bigint)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from channels c
    where c.id = target_channel
      and (
        c.kind in ('statewide', 'county')
        or is_admin()
        or exists (
          select 1 from org_memberships m
          where m.org_id = c.org_id and m.user_id = auth.uid()
        )
      )
  );
$$;

-- The channel list itself. Public channels stay readable to anonymous visitors
-- (the names are not secret and it keeps the sign-in page honest about what
-- exists); org channels are members-only.
drop policy if exists channels_public_read on channels;
drop policy if exists channels_read on channels;
create policy channels_read on channels
  for select using (
    kind in ('statewide', 'county')
    or is_admin()
    or exists (
      select 1 from org_memberships m
      where m.org_id = channels.org_id and m.user_id = auth.uid()
    )
  );

-- ---------------------------------------------------------------------------
-- 4. Message policies, rewritten for private channels
-- ---------------------------------------------------------------------------

-- Read: you must be able to see the channel. Soft-deleted AND bot-flagged
-- messages are hidden from ordinary members and visible to moderators — that
-- is what makes the filter in section 5 a filter rather than a label.
drop policy if exists messages_member_read on messages;
create policy messages_member_read on messages
  for select using (
    is_authenticated()
    and can_read_channel(channel_id)
    and (
      (deleted_at is null and not flagged)
      or is_moderator()
    )
  );

-- Insert: post as yourself, into a channel you can see, not pre-deleted.
--
-- The old policy also required `not flagged` to stop a client pre-flagging its
-- own message. That check has to go: RLS WITH CHECK runs AFTER BEFORE-triggers,
-- so once moderate_message() flags a spam post the insert would be rejected
-- outright instead of being flagged for review. The guarantee is preserved by
-- the trigger itself, which overwrites flagged/flag_reason unconditionally and
-- therefore discards anything the client sent.
drop policy if exists messages_member_insert on messages;
create policy messages_member_insert on messages
  for insert with check (
    user_id = auth.uid()
    and is_authenticated()
    and deleted_at is null
    and can_read_channel(channel_id)
  );

-- ---------------------------------------------------------------------------
-- 5. Automated moderation (spec §5)
-- ---------------------------------------------------------------------------

-- Terms live in a table rather than in the function body so a Sub-Admin can
-- adjust the list without a migration.
create table if not exists moderation_terms (
  id         bigint generated always as identity primary key,
  term       text not null unique,
  -- Plain words only. The matcher wraps each term in word boundaries, so
  -- regex metacharacters here would misbehave rather than match literally.
  note       text,
  created_at timestamptz not null default now()
);

alter table moderation_terms enable row level security;

-- Not public: publishing the blocklist is a roadmap for evading it.
drop policy if exists moderation_terms_read on moderation_terms;
create policy moderation_terms_read on moderation_terms
  for select using (is_moderator());

drop policy if exists moderation_terms_write on moderation_terms;
create policy moderation_terms_write on moderation_terms
  for all using (is_admin()) with check (is_admin());

-- A deliberately small starter list. It is meant to be edited by a human who
-- knows the community, not to be comprehensive out of the box — an
-- over-broad list flags ordinary conversation and trains moderators to ignore
-- the queue, which is worse than a short one.
insert into moderation_terms (term, note) values
  ('viagra',       'classic pharmaceutical spam'),
  ('casino',       'gambling spam'),
  ('crypto',       'review manually — legitimate in some contexts'),
  ('bitcoin',      'review manually — legitimate in some contexts'),
  ('forex',        'investment spam'),
  ('nudes',        'explicit solicitation'),
  ('onlyfans',     'explicit solicitation'),
  ('telegram',     'common vector for off-platform scam funnels'),
  ('whatsapp',     'common vector for off-platform scam funnels'),
  ('seo services', 'agency spam')
on conflict (term) do nothing;

-- Flags rather than blocks. A blocked message tells a spammer exactly what to
-- change; a flagged one disappears from view and lands in a moderator queue.
create or replace function moderate_message()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  matched      text;
  is_statewide boolean;
  link_count   int;
  caps_ratio   numeric;
  recent_count int;
begin
  -- Always overwrite whatever the client sent. This is what lets the insert
  -- policy drop its `not flagged` check safely.
  new.flagged     := false;
  new.flag_reason := null;

  select c.kind = 'statewide' into is_statewide
  from channels c where c.id = new.channel_id;

  -- Spec §5 scopes bot moderation to the statewide channel. County and org
  -- channels are small enough that human moderation is proportionate, and
  -- false positives there are more costly than the spam they would catch.
  if not coalesce(is_statewide, false) then
    return new;
  end if;

  -- Blocklist, matched on word boundaries so 'crypto' does not fire inside
  -- 'cryptography'.
  select t.term into matched
  from moderation_terms t
  where new.body ~* ('\m' || t.term || '\M')
  limit 1;

  if matched is not null then
    new.flagged     := true;
    new.flag_reason := 'blocked term: ' || matched;
    return new;
  end if;

  -- Link flooding.
  select count(*) into link_count
  from regexp_matches(new.body, 'https?://', 'g');

  if link_count >= 3 then
    new.flagged     := true;
    new.flag_reason := link_count || ' links in one message';
    return new;
  end if;

  -- Shouting, but only on messages long enough for the ratio to mean
  -- something — 'OK' and 'FYI' are not spam.
  if length(new.body) >= 40 then
    caps_ratio := length(regexp_replace(new.body, '[^A-Z]', '', 'g'))::numeric
                  / length(new.body);
    if caps_ratio > 0.7 then
      new.flagged     := true;
      new.flag_reason := 'mostly capital letters';
      return new;
    end if;
  end if;

  -- Flooding: more than five messages from this author in ten seconds.
  select count(*) into recent_count
  from messages
  where user_id = new.user_id
    and created_at > now() - interval '10 seconds';

  if recent_count > 5 then
    new.flagged     := true;
    new.flag_reason := 'posting faster than 5 messages / 10s';
  end if;

  return new;
end $$;

drop trigger if exists messages_moderate on messages;
create trigger messages_moderate
  before insert on messages
  for each row execute function moderate_message();

commit;

-- Confirm.
select
  (select count(*) from channels where kind = 'statewide')     as statewide,
  (select count(*) from channels where kind = 'county')        as county,
  (select count(*) from channels where kind = 'org')           as org,
  (select count(*) from moderation_terms)                      as terms;
