"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

// Calls the staff-guarded RPC. The first statement of that function checks
// private.is_staff() and raises for anyone else; the UI check on the page is only a courtesy.
export async function runDetectorNow() {
  const supabase = await createClient();
  const { error } = await supabase.schema("builder").rpc("run_stall_detector_now");

  if (error) {
    redirect(`/detector?error=${encodeURIComponent(error.message)}`);
  }

  revalidatePath("/detector");
  revalidatePath("/projects");
  revalidatePath("/alerts");
  redirect("/detector");
}
