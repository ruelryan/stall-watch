-- private schema and the shared updated_at / lock_version trigger.
--
-- WHY. Every mutable business table carries created_at, updated_at and lock_version (schema
-- rule 7), and one shared trigger function should stamp them so no table drifts. The private
-- schema is where the RLS helpers and automation internals live. It is never exposed through
-- the Data API, but policies run as the caller, so authenticated needs usage on it to call
-- the helpers.
--
-- WHAT.
--   1. schema private — helpers and internals; must stay out of the API's exposed schemas.
--   2. private.set_updated_at() — before-update trigger: updated_at = now(), lock_version + 1.
--      SECURITY INVOKER; it touches only the row being written.
--
-- NOT SELF-CONTAINED. private must not be added to [api].schemas in supabase/config.toml nor to
-- "Exposed schemas" in the hosted dashboard. If it were, the helpers would become RPC endpoints
-- (harmless, since they only return the caller's own facts, but not intended).
--
-- ROLLBACK:
--   drop function if exists private.set_updated_at();
--   drop schema if exists private;

create schema if not exists private;

revoke all on schema private from public;
grant usage on schema private to authenticated;

create or replace function private.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  new.lock_version := old.lock_version + 1;
  return new;
end;
$$;

-- Trigger functions run when their trigger fires, not when a role calls them; nobody over the
-- API needs to execute this one directly. (Postgres grants execute to public by default.)
revoke execute on function private.set_updated_at() from public, anon, authenticated;
