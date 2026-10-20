-- Late-change alert (Part 3 bonus): a builder changes a selection after revision has started.
--
-- WHY. Once a project is in revision, staff have started ordering against the selections. A
-- builder changing one at that point is exactly the kind of thing nobody notices until it is
-- expensive. Every staff user should get an in-app alert the moment it happens. A trigger on
-- selection_history is the natural fit: history already knows who acted (actor_kind) and what
-- changed, and firing from history rather than from selections means the alert and the audit
-- row can never disagree.
--
-- Duplicates: source_key is the history row id, and alerts are unique on
-- (user_id, kind, source_key), so one change produces at most one alert per staff user.
-- Staff changes do not alert (actor_kind = 'staff'). The seed loads with triggers off, so the
-- backdated history does not produce alerts.
--
-- WHAT.
--   1. private.notify_late_change() — SECURITY DEFINER trigger function (it inserts into
--      alerts, which authenticated may not). Reads the slot's project; returns early unless
--      actor_kind = 'builder' and status = 'revision'.
--   2. trg_selection_history_late_change — after insert on builder.selection_history.
--
-- NOT SELF-CONTAINED. Nothing.
--
-- ROLLBACK:
--   drop trigger if exists trg_selection_history_late_change on builder.selection_history;
--   drop function if exists private.notify_late_change();

create or replace function private.notify_late_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_project  record;
  v_verb     text;
begin
  if new.actor_kind <> 'builder' then
    return null;
  end if;

  select p.id, p.org_id, p.name, p.status, o.name as org_name, s.room, s.category
    into v_project
    from builder.project_slots s
    join builder.projects p on p.id = s.project_id
    join public.orgs o      on o.id = p.org_id
   where s.id = new.slot_id;

  if v_project.status is distinct from 'revision' then
    return null;
  end if;

  v_verb := case new.action
    when 'set'    then 'set'
    when 'change' then 'changed'
    else               'cleared'
  end;

  insert into builder.alerts (org_id, user_id, project_id, kind, message, source_key)
  select v_project.org_id,
         m.user_id,
         v_project.id,
         'late_change',
         format('%s %s %s – %s on %s after revision.',
                v_project.org_name, v_verb, v_project.room, v_project.category, v_project.name),
         new.id::text
    from public.memberships m
    join public.orgs o on o.id = m.org_id
   where o.org_type = 'staff'
  on conflict (user_id, kind, source_key) do nothing;

  return null;
end;
$$;

revoke execute on function private.notify_late_change() from public, anon, authenticated;

drop trigger if exists trg_selection_history_late_change on builder.selection_history;
create trigger trg_selection_history_late_change
  after insert on builder.selection_history
  for each row execute function private.notify_late_change();
