-- Stall Watch — sample data (provided; you don't need to write a seed).
--
-- WHAT. Three orgs, nine projects, their slots, current selections and backdated selection
-- history. Dates are relative to now(), so the scenarios below hold whenever you load it.
--
-- REQUIRES the table and column names from the data model in BRIEF.md. You may add columns,
-- as long as they have defaults or are nullable. Columns this file sets that you might not
-- expect: created_at / updated_at on selections (backdated), and actor_kind on history.
--
-- TRIGGERS ARE OFF while this runs (session_replication_role = replica), so your history and
-- updated_at triggers don't overwrite the backdated timestamps. That also means foreign keys
-- are NOT checked during the load (Postgres enforces them with triggers). The data here is
-- consistent, so that's fine, but don't copy this pattern into application code.
-- Check constraints, NOT NULL and defaults still apply.
--
-- SCENARIOS (what your stall detector should conclude on its first run):
--
--   Builder A
--     Lot 12  selection_phase  5 of 8 slots filled, last builder activity 7 days ago   → STALLED
--     Lot 14  selection_phase  3 of 6 filled, last builder activity yesterday (a clear),
--             due in 2 days                                                       → not stalled (recent
--                                                                                   activity); the
--                                                                                   "due soon" case for Part 3
--     Lot 15  revision         all 6 filled                                       → not stalled (wrong status);
--                                                                                   the "late change" case for Part 3
--     Lot 9   complete         all filled                                         → not stalled
--     Lot 3   complete, archived                                                  → not stalled
--   Builder B
--     Unit 4B selection_phase  no selections ever, entered phase 8 days ago       → STALLED
--     Unit 5A selection_phase  no selections ever, entered phase 2 days ago       → not stalled (too new)
--     Unit 7C selection_phase  last BUILDER activity 9 days ago, but a STAFF user
--             changed a selection yesterday                                       → STALLED (staff activity doesn't count)
--     Unit 2A pending_kickoff                                                     → not stalled
--
-- No users are created here. Create the test users in the Supabase dashboard, then run
-- link-test-users.sql. Seeded history has changed_by = null; actor_kind says who acted.
-- Clears have product_name = null, so that history column must be nullable.
--
-- TRAP: selections.updated_at is NOT a measure of builder activity. Unit 7C's staff change
-- makes it one day old. Compute the stall from selection_history.actor_kind.

set session_replication_role = replica;

-- ── Orgs ─────────────────────────────────────────────────────────────────────────────────
insert into public.orgs (id, name, org_type) values
  ('00000000-0000-0000-0000-0000000000f0', 'Reverie3D Studio', 'staff'),
  ('00000000-0000-0000-0000-0000000000a0', 'Builder A',        'builder'),
  ('00000000-0000-0000-0000-0000000000b0', 'Builder B',        'builder');

-- ── Projects ────────────────────────────────────────────────────────────────────────────────
insert into builder.projects
  (id, org_id, name, status, selection_phase_started_at, selection_due_date, archived_at)
values
  ('00000000-0000-0000-0000-00000000a012', '00000000-0000-0000-0000-0000000000a0', 'Lot 12',  'selection_phase', now() - interval '20 days', (now() + interval '10 days')::date, null),
  ('00000000-0000-0000-0000-00000000a014', '00000000-0000-0000-0000-0000000000a0', 'Lot 14',  'selection_phase', now() - interval '10 days', (now() + interval '2 days')::date,  null),
  ('00000000-0000-0000-0000-00000000a015', '00000000-0000-0000-0000-0000000000a0', 'Lot 15',  'revision',        now() - interval '40 days', (now() - interval '5 days')::date,  null),
  ('00000000-0000-0000-0000-00000000a009', '00000000-0000-0000-0000-0000000000a0', 'Lot 9',   'complete',        now() - interval '90 days', (now() - interval '60 days')::date, null),
  ('00000000-0000-0000-0000-00000000a003', '00000000-0000-0000-0000-0000000000a0', 'Lot 3',   'complete',        now() - interval '200 days',(now() - interval '170 days')::date, now() - interval '100 days'),
  ('00000000-0000-0000-0000-00000000b04b', '00000000-0000-0000-0000-0000000000b0', 'Unit 4B', 'selection_phase', now() - interval '8 days',  (now() + interval '20 days')::date, null),
  ('00000000-0000-0000-0000-00000000b05a', '00000000-0000-0000-0000-0000000000b0', 'Unit 5A', 'selection_phase', now() - interval '2 days',  (now() + interval '25 days')::date, null),
  ('00000000-0000-0000-0000-00000000b07c', '00000000-0000-0000-0000-0000000000b0', 'Unit 7C', 'selection_phase', now() - interval '15 days', (now() + interval '6 days')::date,  null),
  ('00000000-0000-0000-0000-00000000b02a', '00000000-0000-0000-0000-0000000000b0', 'Unit 2A', 'pending_kickoff', null,                      (now() + interval '45 days')::date, null);

-- ── Slots ───────────────────────────────────────────────────────────────────────────────────
-- Slot ids are generated; the selections below find their slot by (project, room, category).
insert into builder.project_slots (org_id, project_id, room, category)
select p.org_id, p.id, s.room, s.category
  from (values
    ('Lot 12', 'Kitchen', 'Countertop'), ('Lot 12', 'Kitchen', 'Backsplash'), ('Lot 12', 'Kitchen', 'Faucet'),
    ('Lot 12', 'Primary Bath', 'Floor Tile'), ('Lot 12', 'Primary Bath', 'Wall Tile'), ('Lot 12', 'Primary Bath', 'Vanity Top'),
    ('Lot 12', 'Laundry', 'Floor Tile'), ('Lot 12', 'Great Room', 'Flooring'),

    ('Lot 14', 'Kitchen', 'Countertop'), ('Lot 14', 'Kitchen', 'Backsplash'), ('Lot 14', 'Kitchen', 'Faucet'),
    ('Lot 14', 'Primary Bath', 'Floor Tile'), ('Lot 14', 'Primary Bath', 'Wall Tile'), ('Lot 14', 'Great Room', 'Flooring'),

    ('Lot 15', 'Kitchen', 'Countertop'), ('Lot 15', 'Kitchen', 'Backsplash'), ('Lot 15', 'Kitchen', 'Faucet'),
    ('Lot 15', 'Primary Bath', 'Floor Tile'), ('Lot 15', 'Primary Bath', 'Wall Tile'), ('Lot 15', 'Great Room', 'Flooring'),

    ('Lot 9', 'Kitchen', 'Countertop'), ('Lot 9', 'Kitchen', 'Backsplash'), ('Lot 9', 'Great Room', 'Flooring'),

    ('Lot 3', 'Kitchen', 'Countertop'), ('Lot 3', 'Great Room', 'Flooring'),

    ('Unit 4B', 'Kitchen', 'Countertop'), ('Unit 4B', 'Kitchen', 'Backsplash'), ('Unit 4B', 'Bath', 'Floor Tile'),
    ('Unit 4B', 'Bath', 'Wall Tile'), ('Unit 4B', 'Living', 'Flooring'),

    ('Unit 5A', 'Kitchen', 'Countertop'), ('Unit 5A', 'Kitchen', 'Backsplash'), ('Unit 5A', 'Bath', 'Floor Tile'),
    ('Unit 5A', 'Living', 'Flooring'),

    ('Unit 7C', 'Kitchen', 'Countertop'), ('Unit 7C', 'Kitchen', 'Backsplash'), ('Unit 7C', 'Kitchen', 'Faucet'),
    ('Unit 7C', 'Bath', 'Floor Tile'), ('Unit 7C', 'Bath', 'Wall Tile'), ('Unit 7C', 'Living', 'Flooring'),

    ('Unit 2A', 'Kitchen', 'Countertop'), ('Unit 2A', 'Bath', 'Floor Tile'), ('Unit 2A', 'Living', 'Flooring')
  ) as s(project_name, room, category)
  join builder.projects p on p.name = s.project_name;

-- ── Selection events ────────────────────────────────────────────────────────────────────────
-- Every set / change / clear, in order. History is loaded from these as-is, and the current
-- selection for each slot is the latest event (unless that event is a clear).
create temp table seed_events (
  project_name text, room text, category text,
  action text, product_name text, actor_kind text, days_ago numeric
);

insert into seed_events values
  -- Lot 12: 5 of 8 filled; last builder activity 7 days ago → STALLED
  ('Lot 12', 'Kitchen',      'Countertop', 'set',    'Calacatta Quartz 3cm',        'builder', 15),
  ('Lot 12', 'Kitchen',      'Backsplash', 'set',    'White Gloss Subway 3x12',     'builder', 15),
  ('Lot 12', 'Kitchen',      'Faucet',     'set',    'Brushed Nickel Pull-Down',    'builder', 12),
  ('Lot 12', 'Kitchen',      'Faucet',     'change', 'Matte Black Pull-Down',       'builder', 10),
  ('Lot 12', 'Primary Bath', 'Floor Tile', 'set',    'Grey Slate Look 12x24',       'builder', 9),
  ('Lot 12', 'Great Room',   'Flooring',   'set',    'Natural Oak LVP 7in',         'builder', 7),

  -- Lot 14: 3 of 6 filled; active yesterday; due in 2 days → not stalled, but due soon
  ('Lot 14', 'Kitchen',      'Countertop', 'set',    'Carrara Marble Look Quartz',  'builder', 6),
  ('Lot 14', 'Kitchen',      'Backsplash', 'set',    'Sage Zellige 4x4',            'builder', 4),
  ('Lot 14', 'Great Room',   'Flooring',   'set',    'Hickory Engineered 6in',      'builder', 3),
  ('Lot 14', 'Primary Bath', 'Floor Tile', 'set',    'Hex Marble Mosaic',           'builder', 2),
  ('Lot 14', 'Primary Bath', 'Floor Tile', 'clear',  null,                          'builder', 1),

  -- Lot 15: complete set, now in revision (useful for the late-change option)
  ('Lot 15', 'Kitchen',      'Countertop', 'set',    'Absolute Black Granite',      'builder', 35),
  ('Lot 15', 'Kitchen',      'Backsplash', 'set',    'Charcoal Slate 3x6',          'builder', 35),
  ('Lot 15', 'Kitchen',      'Faucet',     'set',    'Chrome Single-Handle',        'builder', 33),
  ('Lot 15', 'Primary Bath', 'Floor Tile', 'set',    'Warm Travertine 12x12',       'builder', 30),
  ('Lot 15', 'Primary Bath', 'Wall Tile',  'set',    'Ivory Ceramic 4x12',          'builder', 30),
  ('Lot 15', 'Great Room',   'Flooring',   'set',    'Walnut LVP 9in',              'builder', 28),

  -- Lot 9: complete
  ('Lot 9',  'Kitchen',      'Countertop', 'set',    'Calacatta Quartz 3cm',        'builder', 80),
  ('Lot 9',  'Kitchen',      'Backsplash', 'set',    'White Gloss Subway 3x12',     'builder', 80),
  ('Lot 9',  'Great Room',   'Flooring',   'set',    'Natural Oak LVP 7in',         'builder', 78),

  -- Lot 3: complete, archived
  ('Lot 3',  'Kitchen',      'Countertop', 'set',    'Butcher Block Maple',         'builder', 190),
  ('Lot 3',  'Great Room',   'Flooring',   'set',    'Red Oak Solid 3in',           'builder', 190),

  -- Unit 4B and Unit 5A: no events at all (stall clock starts at selection_phase_started_at)

  -- Unit 7C: builder went quiet 9 days ago; staff touched it yesterday → still STALLED
  ('Unit 7C', 'Kitchen',     'Countertop', 'set',    'Concrete Look Quartz',        'builder', 13),
  ('Unit 7C', 'Kitchen',     'Backsplash', 'set',    'Terracotta 2x8',              'builder', 11),
  ('Unit 7C', 'Living',      'Flooring',   'set',    'Ash Grey LVP 7in',            'builder', 9),
  ('Unit 7C', 'Kitchen',     'Backsplash', 'change', 'Clay 2x8', 'staff', 1);

-- History, exactly as above.
insert into builder.selection_history
  (org_id, slot_id, action, product_name, changed_by, actor_kind, changed_at)
select sl.org_id, sl.id, e.action, e.product_name, null, e.actor_kind,
       now() - make_interval(secs => e.days_ago * 86400)
  from seed_events e
  join builder.projects p       on p.name = e.project_name
  join builder.project_slots sl on sl.project_id = p.id and sl.room = e.room and sl.category = e.category;

-- Current selections: the latest event per slot, unless it was a clear.
insert into builder.selections
  (org_id, slot_id, product_name, selected_by, created_at, updated_at)
select org_id, slot_id, product_name, null, at, at
  from (
    select distinct on (sl.id)
           sl.org_id, sl.id as slot_id, e.action, e.product_name,
           now() - make_interval(secs => e.days_ago * 86400) as at
      from seed_events e
      join builder.projects p       on p.name = e.project_name
      join builder.project_slots sl on sl.project_id = p.id and sl.room = e.room and sl.category = e.category
     order by sl.id, e.days_ago asc
  ) latest
 where action <> 'clear';

drop table seed_events;

set session_replication_role = origin;
