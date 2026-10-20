-- RLS helpers and the identity-table policies.
--
-- WHY. Every policy needs two facts about the caller: which orgs they belong to, and whether
-- they are staff. Both come from public.memberships, which has forced RLS, so the helpers are
-- SECURITY DEFINER and owned by postgres, which has BYPASSRLS on Supabase. That is why they
-- work. They are safe to grant to authenticated because they return only the caller's own
-- facts, keyed on auth.uid(): for a stranger they return an empty array and false. STABLE so
-- the planner may evaluate them once per statement rather than per row.
--
-- WHAT.
--   1. private.current_user_org_ids() — uuid[] of the orgs the caller is a member of.
--   2. private.is_staff() — true iff the caller is a member of the org whose type is staff.
--      Never from user_metadata, auth.role() or anything the client can influence.
--   3. p_orgs_select, p_users_select, p_memberships_select — select policies for authenticated.
--      No write policies: identity is never written through the API (rule 5).
--
-- NOT SELF-CONTAINED. Nothing.
--
-- ROLLBACK:
--   drop policy if exists p_memberships_select on public.memberships;
--   drop policy if exists p_users_select on public.users;
--   drop policy if exists p_orgs_select on public.orgs;
--   drop function if exists private.is_staff();
--   drop function if exists private.current_user_org_ids();

create or replace function private.current_user_org_ids()
returns uuid[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(array_agg(m.org_id), '{}'::uuid[])
    from public.memberships m
   where m.user_id = auth.uid();
$$;

create or replace function private.is_staff()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.memberships m
      join public.orgs o on o.id = m.org_id
     where m.user_id = auth.uid()
       and o.org_type = 'staff'
  );
$$;

revoke execute on function private.current_user_org_ids() from public, anon;
revoke execute on function private.is_staff()             from public, anon;
grant  execute on function private.current_user_org_ids() to authenticated;
grant  execute on function private.is_staff()             to authenticated;

drop policy if exists p_orgs_select on public.orgs;
create policy p_orgs_select on public.orgs
  for select to authenticated
  using (id = any (private.current_user_org_ids()) or private.is_staff());

-- Narrower than org scope: a user sees their own row; staff see everyone.
drop policy if exists p_users_select on public.users;
create policy p_users_select on public.users
  for select to authenticated
  using (id = auth.uid() or private.is_staff());

drop policy if exists p_memberships_select on public.memberships;
create policy p_memberships_select on public.memberships
  for select to authenticated
  using (org_id = any (private.current_user_org_ids()) or private.is_staff());
