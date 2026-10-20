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
    return (
      <p role="alert" className="rounded-sm bg-kiln-wash px-3 py-2 text-sm text-kiln">
        Alerts could not be loaded: {error.message}
      </p>
    );
  }

  const unread = alerts.filter((a) => !a.read_at).length;

  return (
    <>
      <div className="flex flex-wrap items-baseline justify-between gap-x-6 gap-y-1">
        <h1 className="text-2xl font-medium tracking-tight">Alerts</h1>
        <p className="text-sm text-mute">
          {alerts.length === 0
            ? "Nothing yet."
            : unread === 0
              ? "All read."
              : `${unread} unread.`}
        </p>
      </div>

      {alerts.length === 0 ? (
        <div className="mt-8 rounded-sm border border-line bg-paper px-5 py-8 text-sm text-mute">
          <p className="text-ink">No alerts.</p>
          <p className="mt-1">
            You will be told here when one of your projects has gone quiet with selections
            still to make.
          </p>
        </div>
      ) : (
        <ul className="mt-6 divide-y divide-line rounded-sm border border-line bg-paper px-5">
          {alerts.map((a) => (
            <li key={a.id} className="flex flex-wrap items-start gap-x-6 gap-y-2 py-4 text-sm">
              <span
                aria-hidden="true"
                className={`mt-2 h-2 w-2 shrink-0 rounded-full ${a.read_at ? "bg-line" : "bg-kiln"}`}
              />
              <div className="min-w-0 flex-1">
                <p className={a.read_at ? "text-mute" : "font-medium"}>{a.message}</p>
                <p className="num mt-1 text-xs text-mute">
                  {a.kind === "stall" ? "Stall" : "Late change"}, {formatDateTime(a.created_at)}.{" "}
                  <Link href={`/projects/${a.project_id}`} className="underline underline-offset-4 hover:text-ink">
                    Open project
                  </Link>
                  {a.read_at ? ` Read ${formatDateTime(a.read_at)}.` : ""}
                </p>
              </div>
              {!a.read_at ? (
                <form action={markAlertRead}>
                  <input type="hidden" name="alert_id" value={a.id} />
                  <button type="submit" className="btn">
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
