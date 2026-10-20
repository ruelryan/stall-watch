import { execSync } from "node:child_process";
import { readFileSync } from "node:fs";
import path from "node:path";
import { Client } from "pg";

// Everything here talks to the LOCAL Supabase stack only. The service key below is the one
// `supabase start` prints for the local demo instance; it is read at run time, never stored.
// This is how the dashboard's "Add user" step is done without a dashboard.

export const E2E_PASSWORD = process.env.E2E_PASSWORD ?? "stall-watch-e2e-local";

export const USERS = {
  staff: "staff@stallwatch.test",
  ana: "ana@builder-a.test",
  bruno: "bruno@builder-b.test",
  mia: "mia@builder-a.test",
} as const;

type LocalStatus = { API_URL: string; SERVICE_ROLE_KEY: string; DB_URL: string };

function localStatus(): LocalStatus {
  const raw = execSync("npx supabase status -o json", { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] });
  const json = JSON.parse(raw.slice(raw.indexOf("{")));
  return { API_URL: json.API_URL, SERVICE_ROLE_KEY: json.SERVICE_ROLE_KEY, DB_URL: json.DB_URL };
}

async function createUser(apiUrl: string, serviceKey: string, email: string) {
  const res = await fetch(`${apiUrl}/auth/v1/admin/users`, {
    method: "POST",
    headers: {
      apikey: serviceKey,
      Authorization: `Bearer ${serviceKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ email, password: E2E_PASSWORD, email_confirm: true }),
  });
  // 422 = already exists (from an earlier run); anything else is a real problem.
  if (!res.ok && res.status !== 422) {
    throw new Error(`Creating ${email} failed: ${res.status} ${await res.text()}`);
  }
}

export default async function globalSetup() {
  const status = localStatus();

  for (const email of Object.values(USERS)) {
    await createUser(status.API_URL, status.SERVICE_ROLE_KEY, email);
  }

  const db = new Client({ connectionString: status.DB_URL });
  await db.connect();
  try {
    // Users that already existed (from an earlier run, or created by hand) keep their old
    // password on a 422; set it to the e2e password so sign-in is deterministic.
    const { rows } = await db.query<{ id: string; email: string }>(
      "select id, email from auth.users where email = any($1)",
      [Object.values(USERS)],
    );
    for (const { id, email } of rows) {
      const res = await fetch(`${status.API_URL}/auth/v1/admin/users/${id}`, {
        method: "PUT",
        headers: {
          apikey: status.SERVICE_ROLE_KEY,
          Authorization: `Bearer ${status.SERVICE_ROLE_KEY}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ password: E2E_PASSWORD }),
      });
      if (!res.ok) throw new Error(`Setting the password for ${email} failed: ${res.status}`);
    }

    // Link users to orgs exactly as the provided file does (safe to run twice).
    await db.query(readFileSync(path.join(__dirname, "..", "supabase", "link-test-users.sql"), "utf8"));

    // Put the seed state back: drop everything a previous test run created. Seeded rows have
    // changed_by / selected_by = null; test-created rows carry the acting user.
    await db.query(`
      begin;
      delete from builder.alerts;
      delete from builder.stall_episodes;
      delete from builder.detector_runs;
      alter table builder.selections disable trigger trg_selections_history;
      delete from builder.selections where selected_by is not null;
      alter table builder.selections enable trigger trg_selections_history;
      alter table builder.selection_history disable trigger trg_selection_history_append_only;
      delete from builder.selection_history where changed_by is not null;
      alter table builder.selection_history enable trigger trg_selection_history_append_only;
      commit;
    `);
  } finally {
    await db.end();
  }
}
