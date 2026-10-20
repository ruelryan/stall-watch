"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

// Set or change the selection for a slot. RLS decides whether the caller may: the org
// predicate on the with check, selected_by = auth.uid(), and the composite foreign key that
// ties the slot to the org. The history row is written by a database trigger, never here.
export async function saveSelection(formData: FormData) {
  const projectId = String(formData.get("project_id") ?? "");
  const slotId = String(formData.get("slot_id") ?? "");
  const orgId = String(formData.get("org_id") ?? "");
  const productName = String(formData.get("product_name") ?? "").trim();

  if (!productName) {
    redirect(`/projects/${projectId}?error=${encodeURIComponent("Enter a product name.")}`);
  }

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  const builder = supabase.schema("builder");
  const { data: existing } = await builder
    .from("selections")
    .select("id")
    .eq("slot_id", slotId)
    .maybeSingle();

  const { error } = existing
    ? await builder
        .from("selections")
        .update({ product_name: productName, selected_by: user.id })
        .eq("id", existing.id)
    : await builder.from("selections").insert({
        org_id: orgId,
        slot_id: slotId,
        product_name: productName,
        selected_by: user.id,
      });

  if (error) {
    redirect(`/projects/${projectId}?error=${encodeURIComponent(error.message)}`);
  }

  revalidatePath(`/projects/${projectId}`);
  revalidatePath("/projects");
  redirect(`/projects/${projectId}`);
}

export async function clearSelection(formData: FormData) {
  const projectId = String(formData.get("project_id") ?? "");
  const slotId = String(formData.get("slot_id") ?? "");

  const supabase = await createClient();
  const { error } = await supabase
    .schema("builder")
    .from("selections")
    .delete()
    .eq("slot_id", slotId);

  if (error) {
    redirect(`/projects/${projectId}?error=${encodeURIComponent(error.message)}`);
  }

  revalidatePath(`/projects/${projectId}`);
  revalidatePath("/projects");
  redirect(`/projects/${projectId}`);
}
