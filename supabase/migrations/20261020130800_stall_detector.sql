-- The stall detector: run log, stall episodes, the worker, and the staff "Run now" RPC.
--
-- WHY. A scheduled job has no signed-in user, so RLS would hide every row from it. The worker
-- is therefore SECURITY DEFINER (owner postgres, BYPASSRLS) and lives in private, revoked from
-- anon AND authenticated so it cannot be reached over the API at all. Only pg_cron (next
-- migration) and the guarded RPC below call it. No service-role key anywhere.
--
-- Duplicates are prevented by a row, not a time window: builder.stall_episodes is unique on
-- (project_id, quiet_since). "Quiet since" is the later of the last builder activity and
-- selection_phase_started_at; for one stall it never changes, so a second run hits the unique
-- index and creates nothing, however many times it runs. New builder activity moves quiet_since
-- forward, which is a new episode and a new alert. Overlapping runs are also serialised with an
-- advisory lock so two runs never do the work at once. A consequence worth knowing: staff
-- activity does not move quiet_since, so a stall that is "fixed" by staff only does not restart
-- the clock. That is the rule ("staff activity doesn't count").
--
-- A failed run must stay visible. The run row is inserted BEFORE the work; the work runs inside
-- a nested begin/exception block, which is a subtransaction. On error, everything the block did
-- is rolled back, the run row survives, and the handler records status = failed with the error.
--
-- WHAT.
--   1. builder.detector_runs — one row per run: trigger_kind scheduled|manual, triggered_by,
--      status running|succeeded|failed, started_at, finished_at, projects_flagged (stalled
--      right now), new_episodes (stalls seen for the first time), alerts_created,
--      error_message. A log: no updated_at / lock_version. Staff-only select policy.
--   2. builder.stall_episodes — one row per distinct stall; unique (project_id, quiet_since);
--      resolved_at is set when the project is no longer stalled (observability only).
--      Staff-only select policy.
--   3. private.run_stall_detector(p_trigger_kind, p_triggered_by) — the worker (see above).
--      Returns the run id. Executable by nobody over the API.
--   4. builder.run_stall_detector_now() — SECURITY DEFINER RPC for staff. Its first statement
--      checks private.is_staff() and raises 42501 otherwise. Granted to authenticated only.
--
-- NOT SELF-CONTAINED. The schedule itself is the next migration (pg_cron). Without it the
-- detector only runs when staff press "Run now".
--
-- ROLLBACK:
--   drop function if exists builder.run_stall_detector_now();
--   drop function if exists private.run_stall_detector(text, uuid);
--   drop table if exists builder.stall_episodes;
--   drop table if exists builder.detector_runs;

create table if not exists builder.detector_runs (
  id                uuid primary key default gen_random_uuid(),
  trigger_kind      text not null check (trigger_kind in ('scheduled', 'manual')),
  triggered_by      uuid references public.users (id),
  status            text not null default 'running'
    check (status in ('running', 'succeeded', 'failed')),
  started_at        timestamptz not null default clock_timestamp(),  -- wall clock, not transaction start
  finished_at       timestamptz,
  projects_flagged  integer not null default 0,
  new_episodes      integer not null default 0,
  alerts_created    integer not null default 0,
  error_message     text,
  created_at        timestamptz not null default now()
);

create index if not exists detector_runs_started_at_idx   on builder.detector_runs (started_at desc);
create index if not exists detector_runs_triggered_by_idx on builder.detector_runs (triggered_by);

create table if not exists builder.stall_episodes (
  id               uuid primary key default gen_random_uuid(),
  project_id       uuid not null,
  org_id           uuid not null references public.orgs (id),
  quiet_since      timestamptz not null,
  detector_run_id  uuid not null references builder.detector_runs (id),
  detected_at      timestamptz not null default now(),
  resolved_at      timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  lock_version     integer not null default 0,
  constraint stall_episodes_project_fk
    foreign key (project_id, org_id) references builder.projects (id, org_id),
  constraint stall_episodes_once_per_stall unique (project_id, quiet_since)
);

create index if not exists stall_episodes_org_id_idx          on builder.stall_episodes (org_id);
create index if not exists stall_episodes_detector_run_id_idx on builder.stall_episodes (detector_run_id);

alter table builder.detector_runs  enable row level security;
alter table builder.detector_runs  force  row level security;
alter table builder.stall_episodes enable row level security;
alter table builder.stall_episodes force  row level security;

grant select on builder.detector_runs, builder.stall_episodes to authenticated;

drop policy if exists p_detector_runs_select on builder.detector_runs;
create policy p_detector_runs_select on builder.detector_runs
  for select to authenticated
  using (private.is_staff());

drop policy if exists p_stall_episodes_select on builder.stall_episodes;
create policy p_stall_episodes_select on builder.stall_episodes
  for select to authenticated
  using (private.is_staff());

drop trigger if exists trg_stall_episodes_set_updated_at on builder.stall_episodes;
create trigger trg_stall_episodes_set_updated_at
  before update on builder.stall_episodes
  for each row execute function private.set_updated_at();

-- The worker. Reachable only by pg_cron (as postgres) and by the staff RPC below.
create or replace function private.run_stall_detector(p_trigger_kind text, p_triggered_by uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_run_id      uuid;
  v_flagged     integer := 0;
  v_new         integer := 0;
  v_alerts      integer := 0;
  v_inserted    integer;
  v_episode_id  uuid;
  r             record;
begin
  -- One run at a time. The unique index below would stop duplicates anyway; this stops two
  -- overlapping runs from both doing the work.
  perform pg_advisory_xact_lock(hashtext('builder.stall_detector'));

  insert into builder.detector_runs (trigger_kind, triggered_by)
  values (p_trigger_kind, p_triggered_by)
  returning id into v_run_id;

  begin
    for r in
      select v.id, v.org_id, v.name, v.quiet_since, v.empty_slots
        from builder.v_projects_overview v
       where v.is_stalled
       order by v.name
    loop
      v_flagged := v_flagged + 1;
      v_episode_id := null;

      insert into builder.stall_episodes (project_id, org_id, quiet_since, detector_run_id)
      values (r.id, r.org_id, r.quiet_since, v_run_id)
      on conflict (project_id, quiet_since) do nothing
      returning id into v_episode_id;

      if v_episode_id is null then
        continue;  -- the same stall as a previous run: already alerted
      end if;
      v_new := v_new + 1;

      -- One alert per admin of the builder org. org_id is the project's builder org.
      insert into builder.alerts (org_id, user_id, project_id, kind, message, source_key)
      select r.org_id,
             m.user_id,
             r.id,
             'stall',
             format('%s has had no builder activity for %s days. %s %s still empty.',
                    r.name,
                    floor(extract(epoch from (now() - r.quiet_since)) / 86400)::integer,
                    r.empty_slots,
                    case when r.empty_slots = 1 then 'slot is' else 'slots are' end),
             v_episode_id::text
        from public.memberships m
       where m.org_id = r.org_id
         and m.role = 'admin'
      on conflict (user_id, kind, source_key) do nothing;

      get diagnostics v_inserted = row_count;
      v_alerts := v_alerts + v_inserted;
    end loop;

    -- Close episodes whose stall is over. Observability only; dedupe is the unique key.
    update builder.stall_episodes e
       set resolved_at = now()
     where e.resolved_at is null
       and not exists (
         select 1
           from builder.v_projects_overview v
          where v.id = e.project_id
            and v.is_stalled
            and v.quiet_since = e.quiet_since);

    update builder.detector_runs
       set status = 'succeeded',
           finished_at = clock_timestamp(),
           projects_flagged = v_flagged,
           new_episodes = v_new,
           alerts_created = v_alerts
     where id = v_run_id;
  exception when others then
    -- The block above was a subtransaction: all of its work is already rolled back. The run
    -- row was written before it, so it survives to record the failure.
    update builder.detector_runs
       set status = 'failed',
           finished_at = clock_timestamp(),
           error_message = sqlerrm
     where id = v_run_id;
  end;

  return v_run_id;
end;
$$;

revoke execute on function private.run_stall_detector(text, uuid) from public, anon, authenticated;

-- Staff "Run now". The grant alone protects nothing; the first statement is the check.
create or replace function builder.run_stall_detector_now()
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.is_staff() then
    raise exception 'Only staff can run the stall detector' using errcode = '42501';
  end if;
  return private.run_stall_detector('manual', auth.uid());
end;
$$;

revoke execute on function builder.run_stall_detector_now() from public, anon;
grant  execute on function builder.run_stall_detector_now() to authenticated;
