-- Promote the founder's account to Super Admin.
--
-- WHY THIS IS A MANUAL SQL STEP, AND HAS TO BE
--
-- Nothing in the app can grant this. The profiles RLS policy explicitly
-- forbids a user from changing their own role, and set_sub_admin() /
-- transfer_super_admin() both require you to ALREADY be an admin. That is
-- deliberate: if any signed-in user could promote themselves, the publishable
-- key in the browser bundle would be a door to full control of the site.
--
-- So the very first Super Admin is installed here, in the SQL editor, which is
-- authenticated as the database owner rather than as a website visitor. Every
-- admin after this one can be granted in-app by an existing admin.
--
-- ---------------------------------------------------------------------------
-- BEFORE RUNNING: create the account through the website
-- ---------------------------------------------------------------------------
-- 1. Go to /signin on the site and create an account with your real email.
-- 2. If Supabase has email confirmation on (the default), click the link in
--    the confirmation email. Until you do, the account exists but cannot sign
--    in — which looks exactly like a wrong password.
--    To turn it off for now: Dashboard -> Authentication -> Sign In / Up ->
--    Email -> disable "Confirm email".
-- 3. Then run this file.

-- ---------------------------------------------------------------------------
-- Step 1 — check the account exists and see whether it is confirmed
-- ---------------------------------------------------------------------------

select
  u.id,
  u.email,
  u.email_confirmed_at,
  p.display_name,
  p.role as current_role
from auth.users u
left join public.profiles p on p.id = u.id
order by u.created_at desc;

-- If your account is missing from that list, sign up on the site first.
-- If email_confirmed_at is null, confirm the email (or disable confirmation)
-- before signing in — promoting an unconfirmed account works, but you still
-- will not be able to log in.

-- ---------------------------------------------------------------------------
-- Step 2 — promote. Replace the email, then uncomment and run.
-- ---------------------------------------------------------------------------
-- There can only be one Super Admin (enforced by a unique index), so this
-- demotes any existing holder to Sub-Admin first. On a fresh database there is
-- none and that update simply affects zero rows.

-- begin;
--
-- update public.profiles
--    set role = 'sub_admin',
--        sub_admin_title = coalesce(sub_admin_title, 'Founder (emeritus)')
--  where role = 'super_admin';
--
-- update public.profiles
--    set role = 'super_admin',
--        sub_admin_title = null
--  where id = (select id from auth.users where email = 'YOUR_EMAIL_HERE');
--
-- commit;

-- ---------------------------------------------------------------------------
-- Step 3 — confirm it took
-- ---------------------------------------------------------------------------

select u.email, p.display_name, p.role
from public.profiles p
join auth.users u on u.id = p.id
where p.role in ('super_admin', 'sub_admin')
order by p.role;

-- Expect exactly one row with role = super_admin. Reload the site and your
-- account page should show a Super Admin badge, with an edit panel on every
-- county page.
