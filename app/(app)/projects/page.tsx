import Link from "next/link";
import { getCurrentUser } from "@/lib/auth";
import { formatDate, daysSince } from "@/lib/format";
import { createClient } from "@/lib/supabase/server";

const statusWords: Record<string, string> = {
  pending_kickoff: "Pending kickoff",
  selection_phase: "Selecting",
  revision: "In revision",
  complete: "Complete",
};

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
    return (
      <p role="alert" className="rounded-sm bg-kiln-wash px-3 py-2 text-sm text-kiln">
        Projects could not be loaded: {error.message}
      </p>
    );
  }

  const stalled = projects.filter((p) => p.is_stalled).length;

  return (
    <>
      <div className="flex flex-wrap items-baseline justify-between gap-x-6 gap-y-1">
        <h1 className="text-2xl font-medium tracking-tight">Projects</h1>
        <p className="text-sm text-mute">
          {stalled === 0
            ? "Nothing is stalled right now."
            : `${stalled} ${stalled === 1 ? "project has" : "projects have"} gone quiet with slots still empty.`}
        </p>
      </div>

      {projects.length === 0 ? (
        <div className="mt-8 rounded-sm border border-line bg-paper px-5 py-8 text-sm text-mute">
          <p className="text-ink">No projects to show.</p>
          <p className="mt-1">
            Your account is signed in but is not yet a member of a builder. Ask Reverie3D to
            add you.
          </p>
        </div>
      ) : (
        <div className="mt-6 overflow-x-auto rounded-sm border border-line bg-paper px-5 pt-1">
          <table className="table">
            <thead>
              <tr>
                <th>Project</th>
                {user.isStaff ? <th>Builder</th> : null}
                <th>Status</th>
                <th className="num">Slots filled</th>
                <th>Last builder activity</th>
                <th>Selections due</th>
                <th className="w-24"></th>
              </tr>
            </thead>
            <tbody>
              {projects.map((p) => {
                const quietDays = daysSince(p.quiet_since);
                const filled = (p.total_slots ?? 0) - (p.empty_slots ?? 0);
                return (
                  <tr key={p.id}>
                    <td>
                      <Link
                        href={`/projects/${p.id}`}
                        className="font-medium underline decoration-line-strong underline-offset-4 hover:decoration-ink"
                      >
                        {p.name}
                      </Link>
                      {p.archived_at ? <span className="ml-2 text-xs text-mute">archived</span> : null}
                    </td>
                    {user.isStaff ? <td>{p.org_name}</td> : null}
                    <td>{statusWords[p.status ?? ""] ?? p.status}</td>
                    <td className="num">
                      {filled} of {p.total_slots}
                      {(p.empty_slots ?? 0) > 0 && p.status === "selection_phase" ? (
                        <span className="ml-2 text-mute">{p.empty_slots} empty</span>
                      ) : null}
                    </td>
                    <td className="num">
                      {formatDate(p.last_builder_activity_at)}
                      {p.status === "selection_phase" && quietDays !== null ? (
                        <span className="ml-2 text-mute">
                          {quietDays === 0 ? "today" : `${quietDays}d quiet`}
                        </span>
                      ) : null}
                    </td>
                    <td className="num">{formatDate(p.selection_due_date)}</td>
                    <td>{p.is_stalled ? <span className="pill pill-stalled">Stalled</span> : null}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}

      <p className="mt-4 max-w-prose text-xs text-mute">
        A project is stalled when it is selecting finishes, still has an empty slot, and no
        builder has set, changed or cleared a selection for 5 days. The badge is live; alerts
        go out when the nightly detector runs.
      </p>
    </>
  );
}
