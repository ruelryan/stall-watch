import { getCurrentUser } from "@/lib/auth";
import { formatDateTime } from "@/lib/format";
import { createClient } from "@/lib/supabase/server";
import { runDetectorNow } from "./actions";

export default async function DetectorPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string }>;
}) {
  const user = await getCurrentUser();
  const { error } = await searchParams;

  // Courtesy only. If a builder got here, p_detector_runs_select would return nothing and
  // run_stall_detector_now() would raise.
  if (!user.isStaff) {
    return (
      <>
        <h1 className="text-xl font-semibold">Detector</h1>
        <p className="mt-4 text-neutral-600">This page is for Reverie3D staff.</p>
      </>
    );
  }

  const supabase = await createClient();
  const builder = supabase.schema("builder");
  const [{ data: runs, error: runsError }, { count: stalledNow }] = await Promise.all([
    builder.from("detector_runs").select("*").order("started_at", { ascending: false }).limit(50),
    builder
      .from("v_projects_overview")
      .select("id", { count: "exact", head: true })
      .eq("is_stalled", true),
  ]);

  if (runsError) {
    return <p className="text-red-700">Could not load runs: {runsError.message}</p>;
  }

  return (
    <>
      <div className="flex flex-wrap items-center gap-4">
        <h1 className="text-xl font-semibold">Stall detector</h1>
        <form action={runDetectorNow}>
          <button
            type="submit"
            className="rounded bg-neutral-900 px-3 py-1.5 text-sm text-white hover:bg-neutral-700"
          >
            Run now
          </button>
        </form>
        <span className="text-sm text-neutral-600">
          {stalledNow ?? 0} project{stalledNow === 1 ? "" : "s"} stalled right now
        </span>
      </div>
      <p className="mt-2 text-sm text-neutral-600">
        Runs nightly at 09:00 UTC via pg_cron inside the database. Each run flags every stalled
        project, and alerts the builder&apos;s admins only for stalls it has not seen before.
      </p>

      {error ? (
        <p role="alert" className="mt-4 rounded bg-red-50 p-3 text-sm text-red-800">
          {error}
        </p>
      ) : null}

      <h2 className="mt-6 font-semibold">Run history</h2>
      {runs.length === 0 ? (
        <p className="mt-2 text-sm text-neutral-600">No runs yet.</p>
      ) : (
        <table className="mt-2 w-full border-collapse text-sm">
          <thead>
            <tr className="border-b border-neutral-300 text-left">
              <th className="py-2 pr-4">Started</th>
              <th className="py-2 pr-4">Finished</th>
              <th className="py-2 pr-4">Trigger</th>
              <th className="py-2 pr-4">Status</th>
              <th className="py-2 pr-4">Stalled</th>
              <th className="py-2 pr-4">New stalls</th>
              <th className="py-2 pr-4">Alerts created</th>
              <th className="py-2 pr-4">Error</th>
            </tr>
          </thead>
          <tbody>
            {runs.map((r) => (
              <tr key={r.id} className="border-b border-neutral-200 align-top">
                <td className="py-2 pr-4 whitespace-nowrap">{formatDateTime(r.started_at)}</td>
                <td className="py-2 pr-4 whitespace-nowrap">{formatDateTime(r.finished_at)}</td>
                <td className="py-2 pr-4">{r.trigger_kind}</td>
                <td className="py-2 pr-4">
                  <span
                    className={
                      r.status === "failed"
                        ? "rounded bg-red-100 px-2 py-0.5 text-xs font-semibold text-red-800"
                        : r.status === "succeeded"
                          ? "rounded bg-green-100 px-2 py-0.5 text-xs font-semibold text-green-800"
                          : "rounded bg-neutral-100 px-2 py-0.5 text-xs font-semibold"
                    }
                  >
                    {r.status}
                  </span>
                </td>
                <td className="py-2 pr-4">{r.projects_flagged}</td>
                <td className="py-2 pr-4">{r.new_episodes}</td>
                <td className="py-2 pr-4">{r.alerts_created}</td>
                <td className="py-2 pr-4 text-red-800">{r.error_message ?? ""}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </>
  );
}
