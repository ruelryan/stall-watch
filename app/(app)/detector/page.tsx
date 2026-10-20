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
        <h1 className="text-2xl font-medium tracking-tight">Detector</h1>
        <p className="mt-2 text-sm text-mute">This page is for Reverie3D staff.</p>
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
    return (
      <p role="alert" className="rounded-sm bg-kiln-wash px-3 py-2 text-sm text-kiln">
        Runs could not be loaded: {runsError.message}
      </p>
    );
  }

  const last = runs[0];

  return (
    <>
      <div className="flex flex-wrap items-center justify-between gap-x-6 gap-y-3">
        <h1 className="text-2xl font-medium tracking-tight">Stall detector</h1>
        <form action={runDetectorNow}>
          <button type="submit" className="btn btn-primary">
            Run now
          </button>
        </form>
      </div>

      <dl className="mt-5 grid max-w-2xl grid-cols-2 gap-x-8 gap-y-1 text-sm sm:grid-cols-3">
        <div>
          <dt className="text-mute">Stalled right now</dt>
          <dd className="num text-lg">{stalledNow ?? 0}</dd>
        </div>
        <div>
          <dt className="text-mute">Last run</dt>
          <dd className="num">{last ? formatDateTime(last.started_at) : "never"}</dd>
        </div>
        <div>
          <dt className="text-mute">Schedule</dt>
          <dd>Daily, 09:00 UTC, inside Postgres (pg_cron)</dd>
        </div>
      </dl>
      <p className="mt-3 max-w-prose text-sm text-mute">
        Each run flags every stalled project and alerts the builder&apos;s admins only for stalls
        it has not seen before. Running it again is harmless.
      </p>

      {error ? (
        <p role="alert" className="mt-6 rounded-sm bg-kiln-wash px-3 py-2 text-sm text-kiln">
          {error}
        </p>
      ) : null}

      <h2 className="mt-8 text-sm font-medium">Run history</h2>
      {runs.length === 0 ? (
        <p className="mt-2 text-sm text-mute">No runs yet. The first one happens tonight, or now if you press Run now.</p>
      ) : (
        <div className="mt-2 overflow-x-auto rounded-sm border border-line bg-paper px-5 pt-1">
          <table className="table">
            <thead>
              <tr>
                <th>Started</th>
                <th>Finished</th>
                <th>Trigger</th>
                <th>Result</th>
                <th className="num">Stalled</th>
                <th className="num">New stalls</th>
                <th className="num">Alerts sent</th>
                <th>Error</th>
              </tr>
            </thead>
            <tbody>
              {runs.map((r) => (
                <tr key={r.id}>
                  <td className="num whitespace-nowrap">{formatDateTime(r.started_at)}</td>
                  <td className="num whitespace-nowrap">{formatDateTime(r.finished_at)}</td>
                  <td>{r.trigger_kind === "manual" ? "Run now" : "Scheduled"}</td>
                  <td>
                    <span
                      className={
                        r.status === "failed"
                          ? "pill pill-bad"
                          : r.status === "succeeded"
                            ? "pill pill-ok"
                            : "pill pill-dim"
                      }
                    >
                      {r.status}
                    </span>
                  </td>
                  <td className="num">{r.projects_flagged}</td>
                  <td className="num">{r.new_episodes}</td>
                  <td className="num">{r.alerts_created}</td>
                  <td className="max-w-xs text-kiln">{r.error_message ?? ""}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </>
  );
}
