import Link from "next/link";
import { getCurrentUser } from "@/lib/auth";
import { formatDate, daysSince } from "@/lib/format";
import { createClient } from "@/lib/supabase/server";

export default async function ProjectsPage() {
  const user = await getCurrentUser();
  const supabase = await createClient();

  // The view is security_invoker: builders get their org's rows, staff get everything.
  // is_stalled is computed live by the same rule the detector uses.
  const { data: projects, error } = await supabase
    .schema("builder")
    .from("v_projects_overview")
    .select("*")
    .order("org_name")
    .order("name");

  if (error) {
    return <p className="text-red-700">Could not load projects: {error.message}</p>;
  }

  return (
    <>
      <h1 className="text-xl font-semibold">Projects</h1>
      {projects.length === 0 ? (
        <p className="mt-4 text-neutral-600">
          No projects to show. If you expected some, your account may not be a member of an org yet.
        </p>
      ) : (
        <table className="mt-4 w-full border-collapse text-sm">
          <thead>
            <tr className="border-b border-neutral-300 text-left">
              <th className="py-2 pr-4">Project</th>
              {user.isStaff ? <th className="py-2 pr-4">Builder</th> : null}
              <th className="py-2 pr-4">Status</th>
              <th className="py-2 pr-4">Slots filled</th>
              <th className="py-2 pr-4">Last builder activity</th>
              <th className="py-2 pr-4">Due</th>
              <th className="py-2 pr-4"></th>
            </tr>
          </thead>
          <tbody>
            {projects.map((p) => {
              const quietDays = daysSince(p.quiet_since);
              return (
                <tr key={p.id} className="border-b border-neutral-200">
                  <td className="py-2 pr-4">
                    <Link href={`/projects/${p.id}`} className="underline">
                      {p.name}
                    </Link>
                    {p.archived_at ? (
                      <span className="ml-2 text-xs text-neutral-500">archived</span>
                    ) : null}
                  </td>
                  {user.isStaff ? <td className="py-2 pr-4">{p.org_name}</td> : null}
                  <td className="py-2 pr-4">{p.status}</td>
                  <td className="py-2 pr-4">
                    {(p.total_slots ?? 0) - (p.empty_slots ?? 0)} / {p.total_slots}
                  </td>
                  <td className="py-2 pr-4">
                    {formatDate(p.last_builder_activity_at)}
                    {p.status === "selection_phase" && quietDays !== null ? (
                      <span className="ml-1 text-neutral-500">({quietDays}d quiet)</span>
                    ) : null}
                  </td>
                  <td className="py-2 pr-4">{formatDate(p.selection_due_date)}</td>
                  <td className="py-2 pr-4">
                    {p.is_stalled ? (
                      <span className="rounded bg-red-100 px-2 py-0.5 text-xs font-semibold text-red-800">
                        stalled
                      </span>
                    ) : null}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      )}
      <p className="mt-4 text-xs text-neutral-500">
        A project is stalled when it is in selection phase, has at least one empty slot, and has had
        no builder activity for 5 or more days. The badge is live; alerts are sent by the nightly
        detector.
      </p>
    </>
  );
}
