import "server-only";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export type CurrentUser = {
  id: string;
  email: string;
  isStaff: boolean;
  orgIds: string[];
};

// Who is signed in and what their memberships say. This is for the UI only (which links to
// show); the database re-derives the same facts from public.memberships on every query.
export async function getCurrentUser(): Promise<CurrentUser> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    redirect("/login");
  }

  const { data: memberships } = await supabase
    .from("memberships")
    .select("org_id, role, orgs!inner(org_type)");

  const rows = memberships ?? [];
  return {
    id: user.id,
    email: user.email ?? "",
    isStaff: rows.some((m) => m.orgs.org_type === "staff"),
    orgIds: rows.map((m) => m.org_id),
  };
}
