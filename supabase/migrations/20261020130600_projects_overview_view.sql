-- The stall rule, in one view: builder.v_projects_overview.
--
-- WHY. The stalled badge on /projects must be live, and the detector must flag by the same
-- rule, so the rule lives in exactly one place. A project is stalled when it is in
-- selection_phase and not archived, at least one slot has no selection, and "quiet since"
-- (the later of the last BUILDER history event and selection_phase_started_at) is 5+ days ago.
-- If neither timestamp exists the project is not stalled. Staff activity is excluded by
-- actor_kind, which is why selections.updated_at is never consulted.
--
-- WHAT.
--   1. builder.v_projects_overview — one row per project with org_name, total_slots,
--      empty_slots, last_builder_activity_at, quiet_since and is_stalled.
--   2. security_invoker = true, set after creation (Postgres drops it on create or replace),
--      so a builder sees only their org's rows through the projects and orgs policies.
--
-- NOT SELF-CONTAINED. Nothing.
--
-- ROLLBACK:
--   drop view if exists builder.v_projects_overview;

create or replace view builder.v_projects_overview as
with slot_stats as (
  select s.project_id,
         count(*)                                   as total_slots,
         count(*) filter (where sel.id is null)     as empty_slots
    from builder.project_slots s
    left join builder.selections sel on sel.slot_id = s.id
   group by s.project_id
),
builder_activity as (
  select s.project_id, max(h.changed_at) as last_builder_activity_at
    from builder.selection_history h
    join builder.project_slots s on s.id = h.slot_id
   where h.actor_kind = 'builder'
   group by s.project_id
)
select p.id,
       p.org_id,
       o.name as org_name,
       p.name,
       p.status,
       p.selection_phase_started_at,
       p.selection_due_date,
       p.archived_at,
       p.created_at,
       p.updated_at,
       p.lock_version,
       coalesce(ss.total_slots, 0)::integer as total_slots,
       coalesce(ss.empty_slots, 0)::integer as empty_slots,
       a.last_builder_activity_at,
       greatest(a.last_builder_activity_at, p.selection_phase_started_at) as quiet_since,
       coalesce(
         p.status = 'selection_phase'
         and p.archived_at is null
         and coalesce(ss.empty_slots, 0) > 0
         and greatest(a.last_builder_activity_at, p.selection_phase_started_at)
             <= now() - interval '5 days',
         false) as is_stalled
  from builder.projects p
  join public.orgs o on o.id = p.org_id
  left join slot_stats ss      on ss.project_id = p.id
  left join builder_activity a on a.project_id = p.id;

alter view builder.v_projects_overview set (security_invoker = true);

grant select on builder.v_projects_overview to authenticated;
