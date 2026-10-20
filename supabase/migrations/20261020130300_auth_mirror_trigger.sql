-- Auth mirror: copy auth.users into public.users.
--
-- WHY. Policies and foreign keys in the exposed schemas need a users table they can reference,
-- and the provided link-test-users.sql expects public.users to already hold every auth user.
-- The trigger fires as supabase_auth_admin, which has no privileges on public.users, so the
-- function is SECURITY DEFINER (owner postgres). It writes one table and reads nothing else;
-- that is the whole scope of the definer rights.
--
-- WHAT.
--   1. private.handle_auth_user_change() — upserts (id, email, display_name) into public.users.
--      display_name comes from raw_user_meta_data.display_name, else the local part of the
--      email. A later display_name edit in public.users is kept on re-sync.
--   2. trg_auth_user_mirror — after insert, or update of email, on auth.users.
--
-- NOT SELF-CONTAINED. Nothing.
--
-- ROLLBACK:
--   drop trigger if exists trg_auth_user_mirror on auth.users;
--   drop function if exists private.handle_auth_user_change();

create or replace function private.handle_auth_user_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.users (id, email, display_name)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data ->> 'display_name', split_part(new.email, '@', 1))
  )
  on conflict (id) do update
    set email        = excluded.email,
        display_name = coalesce(public.users.display_name, excluded.display_name);
  return new;
end;
$$;

revoke execute on function private.handle_auth_user_change() from public, anon, authenticated;
grant  usage   on schema private to supabase_auth_admin;
grant  execute on function private.handle_auth_user_change() to supabase_auth_admin;

drop trigger if exists trg_auth_user_mirror on auth.users;
create trigger trg_auth_user_mirror
  after insert or update of email on auth.users
  for each row execute function private.handle_auth_user_change();
