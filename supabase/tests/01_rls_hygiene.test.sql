-- Schema-rule hygiene, checked against the catalog (not against what the docs say).
begin;
create extension if not exists pgtap with schema extensions;
select plan(12);

-- Rule 1: RLS enabled AND forced on every table in public and builder.
select is(
  (select count(*)::int
     from pg_class c
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname in ('public', 'builder')
      and c.relkind = 'r'
      and not (c.relrowsecurity and c.relforcerowsecurity)),
  0, 'every table in public and builder has RLS enabled and forced');

-- Rule 1: a table with RLS and zero policies is a silent deny-all, which is a bug.
select is(
  (select count(*)::int
     from pg_class c
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname in ('public', 'builder')
      and c.relkind = 'r'
      and not exists (select 1 from pg_policy p where p.polrelid = c.oid)),
  0, 'every table in public and builder has at least one policy');

-- Rule 7: policies are named p_<table>_<command>.
select is(
  (select count(*)::int
     from pg_policies
    where schemaname in ('public', 'builder')
      and policyname !~ ('^p_' || tablename || '_(select|insert|update|delete)$')),
  0, 'policies are named p_<table>_<command>');

-- Rule 3: every insert/update policy has a with check.
select is(
  (select count(*)::int
     from pg_policies
    where schemaname in ('public', 'builder')
      and cmd in ('INSERT', 'UPDATE')
      and with_check is null),
  0, 'every insert/update policy has a with check');

-- Rule 3: every table with a write policy also has a select policy.
select is(
  (select count(distinct tablename)::int
     from pg_policies w
    where w.schemaname in ('public', 'builder')
      and w.cmd in ('INSERT', 'UPDATE', 'DELETE')
      and not exists (select 1 from pg_policies s
                       where s.schemaname = w.schemaname and s.tablename = w.tablename
                         and s.cmd = 'SELECT')),
  0, 'every writable table also has a select policy');

-- Rule 8: every view in an exposed schema is security_invoker.
select is(
  (select count(*)::int
     from pg_class c
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname in ('public', 'builder')
      and c.relkind = 'v'
      and not exists (select 1 from unnest(c.reloptions) o
                       where o in ('security_invoker=true', 'security_invoker=on'))),
  0, 'every view in public and builder is security_invoker');

-- Rule 4: every SECURITY DEFINER function in private/builder pins search_path.
select is(
  (select count(*)::int
     from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('private', 'builder')
      and p.prosecdef
      and not exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%')),
  0, 'every security definer function in private and builder pins search_path');

-- Rule 4: no SECURITY DEFINER function in private is executable by anon, and the only ones
-- authenticated may call are the two RLS helpers (which return only the caller's own facts).
select is(
  (select count(*)::int
     from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private'
      and has_function_privilege('anon', p.oid, 'execute')),
  0, 'anon can execute nothing in private');
select bag_eq(
  $$ select p.proname::text
       from pg_proc p
       join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'private'
        and has_function_privilege('authenticated', p.oid, 'execute') $$,
  $$ values ('current_user_org_ids'), ('is_staff') $$,
  'authenticated can execute only the two RLS helpers in private');
select is(
  (select count(*)::int
     from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'builder'
      and has_function_privilege('anon', p.oid, 'execute')),
  0, 'anon can execute nothing in builder');

-- anon has no table privileges anywhere in public or builder (policies are "to authenticated").
select is(
  (select count(*)::int
     from pg_class c
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname in ('public', 'builder')
      and c.relkind in ('r', 'v')
      and has_table_privilege('anon', c.oid, 'SELECT, INSERT, UPDATE, DELETE')),
  0, 'anon has no privileges on any table or view in public or builder');

-- Rule 7: every mutable table carries created_at, updated_at and lock_version.
select is(
  (select count(*)::int
     from pg_class c
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname in ('public', 'builder')
      and c.relkind = 'r'
      and c.relname not in ('selection_history', 'detector_runs')  -- append-only / log tables
      and (   not exists (select 1 from pg_attribute a where a.attrelid = c.oid and a.attname = 'created_at')
           or not exists (select 1 from pg_attribute a where a.attrelid = c.oid and a.attname = 'updated_at')
           or not exists (select 1 from pg_attribute a where a.attrelid = c.oid and a.attname = 'lock_version'))),
  0, 'every mutable table has created_at, updated_at and lock_version');

select * from finish();
rollback;
