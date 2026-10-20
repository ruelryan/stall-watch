-- Stall Watch — link the test users to their orgs (provided).
--
-- Run this AFTER:
--   1. your migrations and seed.sql have been applied, and
--   2. you've created these users in the Supabase dashboard (Authentication → Add user,
--      tick "Auto Confirm User"), each with a password you choose and do not commit:
--
--        staff@stallwatch.test   — staff
--        ana@builder-a.test      — Builder A admin
--        bruno@builder-b.test    — Builder B admin
--        mia@builder-a.test      — Builder A member (optional; useful to check that only
--                                  admins get stall alerts)
--
-- Your auth-mirror trigger should already have copied each of them into public.users. If it
-- hasn't, this file stops and tells you, which means the trigger needs fixing.
--
-- Run it as the database owner (SQL editor or psql). It writes memberships directly, which
-- the app must never do (SCHEMA-RULES rule 5). Setup data is the exception. Safe to run twice.

do $$
declare
  v_missing text;
begin
  select string_agg(e, ', ') into v_missing
    from unnest(array['staff@stallwatch.test', 'ana@builder-a.test', 'bruno@builder-b.test']) e
   where not exists (select 1 from public.users u where u.email = e);
  if v_missing is not null then
    raise exception 'Not found in public.users: %. Create them in Authentication → Add user first, and check your auth-mirror trigger.', v_missing;
  end if;
end $$;

insert into public.memberships (user_id, org_id, role)
select u.id, m.org_id::uuid, m.role
  from (values
    ('staff@stallwatch.test', '00000000-0000-0000-0000-0000000000f0', 'admin'),
    ('ana@builder-a.test',    '00000000-0000-0000-0000-0000000000a0', 'admin'),
    ('bruno@builder-b.test',  '00000000-0000-0000-0000-0000000000b0', 'admin'),
    ('mia@builder-a.test',    '00000000-0000-0000-0000-0000000000a0', 'member')
  ) as m(email, org_id, role)
  join public.users u on u.email = m.email
on conflict do nothing;
