import Link from "next/link";
import { notFound } from "next/navigation";
import { formatDate, formatDateTime } from "@/lib/format";
import { createClient } from "@/lib/supabase/server";
import { clearSelection, saveSelection } from "./actions";

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

  return (
    <>
      <p className="text-sm">
        <Link href="/projects" className="underline">
          ← Projects
        </Link>
      </p>
      <h1 className="mt-2 text-xl font-semibold">
        {project.name}
        {project.is_stalled ? (
          <span className="ml-3 rounded bg-red-100 px-2 py-0.5 align-middle text-xs font-semibold text-red-800">
            stalled
          </span>
        ) : null}
      </h1>
      <p className="mt-1 text-sm text-neutral-600">
        {project.org_name} · {project.status} · due {formatDate(project.selection_due_date)} ·{" "}
        {(project.total_slots ?? 0) - (project.empty_slots ?? 0)} of {project.total_slots} slots
        filled · last builder activity {formatDateTime(project.last_builder_activity_at)}
      </p>

      {error ? (
        <p role="alert" className="mt-4 rounded bg-red-50 p-3 text-sm text-red-800">
          {error}
        </p>
      ) : null}

      <table className="mt-6 w-full border-collapse text-sm">
        <thead>
          <tr className="border-b border-neutral-300 text-left">
            <th className="py-2 pr-4">Slot</th>
            <th className="py-2 pr-4">Selection</th>
            <th className="py-2 pr-4"></th>
          </tr>
        </thead>
        <tbody>
          {(slots ?? []).map((slot) => {
            const current = bySlot.get(slot.id);
            return (
              <tr key={slot.id} className="border-b border-neutral-200 align-top">
                <td className="py-2 pr-4 whitespace-nowrap">
                  {slot.room} – {slot.category}
                </td>
                <td className="py-2 pr-4">
                  <form action={saveSelection} className="flex flex-wrap items-center gap-2">
                    <input type="hidden" name="project_id" value={id} />
                    <input type="hidden" name="slot_id" value={slot.id} />
                    <input type="hidden" name="org_id" value={slot.org_id} />
                    <input
                      name="product_name"
                      defaultValue={current?.product_name ?? ""}
                      placeholder="e.g. Calacatta Quartz 3cm"
                      className="w-72 rounded border border-neutral-300 px-2 py-1"
                    />
                    <button
                      type="submit"
                      className="rounded border border-neutral-400 px-2 py-1 hover:bg-neutral-100"
                    >
                      {current ? "Change" : "Set"}
                    </button>
                  </form>
                  {current ? (
                    <p className="mt-1 text-xs text-neutral-500">
                      picked {formatDateTime(current.updated_at)}
                    </p>
                  ) : (
                    <p className="mt-1 text-xs text-neutral-500">empty</p>
                  )}
                </td>
                <td className="py-2 pr-4">
                  {current ? (
                    <form action={clearSelection}>
                      <input type="hidden" name="project_id" value={id} />
                      <input type="hidden" name="slot_id" value={slot.id} />
                      <button
                        type="submit"
                        className="rounded border border-neutral-400 px-2 py-1 hover:bg-neutral-100"
                      >
                        Clear
                      </button>
                    </form>
                  ) : null}
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </>
  );
}
