-- Smoke test: pgTAP runs and the Supabase roles the policies rely on exist.
begin;
create extension if not exists pgtap with schema extensions;
select plan(4);

select has_role('anon', 'anon role exists');
select has_role('authenticated', 'authenticated role exists');
select has_schema('auth', 'auth schema exists');
select has_function('auth', 'uid', 'auth.uid() exists');

select * from finish();
rollback;
