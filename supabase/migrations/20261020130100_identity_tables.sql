-- Identity and tenancy tables: orgs, users, memberships.
--
-- WHY. Authentication (a row in auth.users) and authorization (a row in public.memberships)
-- are separate: a signed-in user with no membership sees nothing, which is correct. Orgs are
-- either the single staff org or a builder (a customer). The brief's data-model table lists
-- org_type as staff | admin, but its glossary and the provided seed use 'builder', and the seed
-- must load unchanged, so the check accepts staff | builder (see DESIGN.md).
--
-- WHAT.
--   1. public.orgs — name, org_type (staff | builder). A partial unique index allows exactly
--      one staff org, so "is staff" has one meaning.
--   2. public.users — mirror of auth.users (id, email, display_name), filled by a trigger in a
--      later migration. Never written by the app.
--   3. public.memberships — one row per user per org, role admin | member. This is the only
--      source of authority that RLS reads.
--   4. RLS enabled AND forced on all three; the policies come with the helpers in the next file.
--   5. Privileges: select to authenticated only. No insert/update/delete for anon or
--      authenticated: identity is written only by the auth-mirror trigger, the provided
--      link-test-users.sql (run as the database owner) and, in future, guarded RPCs (rule 5).
--   6. updated_at / lock_version trigger on each table.
--
-- NOT SELF-CONTAINED. Nothing.
--
-- ROLLBACK:
--   drop table if exists public.memberships;
--   drop table if exists public.users;
--   drop table if exists public.orgs;

create table if not exists public.orgs (
  id            uuid primary key default gen_random_uuid(),
  name          text not null,
  org_type      text not null check (org_type in ('staff', 'builder')),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  lock_version  integer not null default 0
);

-- "Staff" means "member of THE staff org". Allow only one.
create unique index if not exists orgs_single_staff_org
  on public.orgs (org_type) where org_type = 'staff';

create table if not exists public.users (
  id            uuid primary key references auth.users (id) on delete cascade,
  email         text not null,
  display_name  text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  lock_version  integer not null default 0
);

create table if not exists public.memberships (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references public.users (id) on delete cascade,
  org_id        uuid not null references public.orgs (id),
  role          text not null check (role in ('admin', 'member')),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  lock_version  integer not null default 0,
  constraint memberships_user_org_unique unique (user_id, org_id)
);

create index if not exists memberships_org_id_idx on public.memberships (org_id);

alter table public.orgs        enable row level security;
alter table public.orgs        force  row level security;
alter table public.users       enable row level security;
alter table public.users       force  row level security;
alter table public.memberships enable row level security;
alter table public.memberships force  row level security;

-- Supabase grants anon/authenticated/service_role everything on new public tables through
-- default privileges. Take it back and grant only what the policies can allow.
revoke all on public.orgs, public.users, public.memberships from public, anon, authenticated;
grant select on public.orgs, public.users, public.memberships to authenticated;

drop trigger if exists trg_orgs_set_updated_at on public.orgs;
create trigger trg_orgs_set_updated_at
  before update on public.orgs
  for each row execute function private.set_updated_at();

drop trigger if exists trg_users_set_updated_at on public.users;
create trigger trg_users_set_updated_at
  before update on public.users
  for each row execute function private.set_updated_at();

drop trigger if exists trg_memberships_set_updated_at on public.memberships;
create trigger trg_memberships_set_updated_at
  before update on public.memberships
  for each row execute function private.set_updated_at();
