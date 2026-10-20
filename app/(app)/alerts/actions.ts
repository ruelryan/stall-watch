"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

// "Mark read" may change read_at and nothing else; the database enforces that with a column
// grant, and RLS limits it to the recipient.
export async function markAlertRead(formData: FormData) {
  const alertId = String(formData.get("alert_id") ?? "");
  const supabase = await createClient();
  await supabase
    .schema("builder")
    .from("alerts")
    .update({ read_at: new Date().toISOString() })
    .eq("id", alertId);
  revalidatePath("/alerts");
  revalidatePath("/", "layout");
}
