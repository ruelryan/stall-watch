import Link from "next/link";
import { notFound } from "next/navigation";
import { formatDate, formatDateTime } from "@/lib/format";
import { createClient } from "@/lib/supabase/server";
import { clearSelection, saveSelection } from "./actions";

const statusWords: Record<string, string> = {
  pending_kickoff: "pending kickoff",
  selection_phase: "selecting finishes",
  revision: "in revision",
  complete: "complete",
};

export default async function ProjectPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ error?: string }>;
}) {
  const { id } = await params;
  const { error } = await searchParams;
  const supabase = await createClient();
  const builder = supabase.schema("builder");

  const [{ data: project }, { data: slots }] = await Promise.all([
    builder.from("v_projects_overview").select("*").eq("id", id).maybeSingle(),
    builder
      .from("project_slots")
      .select("id, org_id, room, category")
      .eq("project_id", id)
      .order("room")
      .order("category"),
  ]);

  // RLS returns nothing for a project the caller may not see; treat it as not found.
  if (!project) notFound();

  const slotIds = (slots ?? []).map((s) => s.id);
  const { data: currentSelections } =
    slotIds.length > 0
      ? await builder
          .from("selections")
          .select("id, slot_id, product_name, updated_at")
          .in("slot_id", slotIds)
      : { data: [] };
  const bySlot = new Map((currentSelections ?? []).map((s) => [s.slot_id, s]));

  // Slots group naturally by room; show them that way.
  const rooms = new Map<string, typeof slots>();
  for (const slot of slots ?? []) {
    const list = rooms.get(slot.room) ?? [];
    list.push(slot);
    rooms.set(slot.room, list);
  }

  const filled = (project.total_slots ?? 0) - (project.empty_slots ?? 0);

  return (
    <>
      <p className="text-sm">
        <Link href="/projects" className="text-mute hover:text-ink">
          Projects
        </Link>
        <span className="mx-2 text-line-strong">/</span>
        <span>{project.name}</span>
      </p>

      <div className="mt-4 flex flex-wrap items-center gap-x-4 gap-y-2">
        <h1 className="text-2xl font-medium tracking-tight">{project.name}</h1>
        {project.is_stalled ? <span className="pill pill-stalled">Stalled</span> : null}
      </div>
      <p className="mt-1 text-sm text-mute">
        {project.org_name}, {statusWords[project.status ?? ""] ?? project.status}. Selections
        due {formatDate(project.selection_due_date)}.
      </p>

      <dl className="mt-5 grid max-w-xl grid-cols-2 gap-x-8 gap-y-1 text-sm sm:grid-cols-3">
        <div>
          <dt className="text-mute">Slots filled</dt>
          <dd className="num text-lg">
            {filled} <span className="text-mute">of {project.total_slots}</span>
          </dd>
        </div>
        <div>
          <dt className="text-mute">Last builder activity</dt>
          <dd className="num">{formatDateTime(project.last_builder_activity_at)}</dd>
        </div>
        <div>
          <dt className="text-mute">Selection phase started</dt>
          <dd className="num">{formatDate(project.selection_phase_started_at)}</dd>
        </div>
      </dl>

      {error ? (
        <p role="alert" className="mt-6 rounded-sm bg-kiln-wash px-3 py-2 text-sm text-kiln">
          {error}
        </p>
      ) : null}

      <div className="mt-8 flex flex-col gap-8">
        {[...rooms.entries()].map(([room, roomSlots]) => (
          <section key={room}>
            <h2 className="border-b border-line-strong pb-2 text-sm font-medium">{room}</h2>
            <ul className="divide-y divide-line">
              {(roomSlots ?? []).map((slot) => {
                const current = bySlot.get(slot.id);
                return (
                  <li
                    key={slot.id}
                    className="grid grid-cols-1 gap-3 py-3 sm:grid-cols-[12rem_1fr] sm:items-start"
                  >
                    <div className="text-sm">
                      <p>{slot.category}</p>
                      <p className="num text-xs text-mute">
                        {current ? `picked ${formatDateTime(current.updated_at)}` : "empty"}
                      </p>
                    </div>
                    <div className="flex flex-wrap items-center gap-2">
                      <form action={saveSelection} className="flex min-w-0 flex-1 items-center gap-2">
                        <input type="hidden" name="project_id" value={id} />
                        <input type="hidden" name="slot_id" value={slot.id} />
                        <input type="hidden" name="org_id" value={slot.org_id} />
                        <input
                          name="product_name"
                          defaultValue={current?.product_name ?? ""}
                          placeholder="Product name, e.g. Calacatta Quartz 3cm"
                          aria-label={`${room} ${slot.category} product`}
                          className="field max-w-md"
                        />
                        <button type="submit" className={current ? "btn" : "btn btn-primary"}>
                          {current ? "Change" : "Set"}
                        </button>
                      </form>
                      {current ? (
                        <form action={clearSelection}>
                          <input type="hidden" name="project_id" value={id} />
                          <input type="hidden" name="slot_id" value={slot.id} />
                          <button type="submit" className="btn btn-quiet">
                            Clear
                          </button>
                        </form>
                      ) : null}
                    </div>
                  </li>
                );
              })}
            </ul>
          </section>
        ))}
      </div>
    </>
  );
}
