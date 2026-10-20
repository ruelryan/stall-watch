import Link from "next/link";
import { formatDateTime } from "@/lib/format";
import { createClient } from "@/lib/supabase/server";
import { markAlertRead } from "./actions";

export default async function AlertsPage() {
  const supabase = await createClient();

  // p_alerts_select: user_id = auth.uid(). Nobody else's alerts can come back.
  const { data: alerts, error } = await supabase
    .schema("builder")
    .from("alerts")
    .select("id, kind, message, project_id, created_at, read_at")
    .order("created_at", { ascending: false });

  if (error) {
    return <p className="text-red-700">Could not load alerts: {error.message}</p>;
  }

  return (
    <>
      <h1 className="text-xl font-semibold">My alerts</h1>
      {alerts.length === 0 ? (
        <p className="mt-4 text-neutral-600">No alerts.</p>
      ) : (
        <ul className="mt-4 divide-y divide-neutral-200">
          {alerts.map((a) => (
            <li key={a.id} className="flex flex-wrap items-start gap-3 py-3 text-sm">
              <div className="flex-1">
                <p className={a.read_at ? "text-neutral-500" : "font-medium"}>{a.message}</p>
                <p className="mt-1 text-xs text-neutral-500">
                  {a.kind === "stall" ? "Stall" : "Late change"} · {formatDateTime(a.created_at)} ·{" "}
                  <Link href={`/projects/${a.project_id}`} className="underline">
                    open project
                  </Link>
                  {a.read_at ? ` · read ${formatDateTime(a.read_at)}` : ""}
                </p>
              </div>
              {!a.read_at ? (
                <form action={markAlertRead}>
                  <input type="hidden" name="alert_id" value={a.id} />
                  <button
                    type="submit"
                    className="rounded border border-neutral-400 px-2 py-1 hover:bg-neutral-100"
                  >
                    Mark as read
                  </button>
                </form>
              ) : null}
            </li>
          ))}
        </ul>
      )}
    </>
  );
}
