import Link from "next/link";
import { signOut } from "@/app/login/actions";
import { getCurrentUser } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";

export default async function AppLayout({ children }: LayoutProps<"/">) {
  const user = await getCurrentUser();
  const supabase = await createClient();

  // Only the recipient can see their alerts, so this count is already scoped by RLS.
  const { count: unread } = await supabase
    .schema("builder")
    .from("alerts")
    .select("id", { count: "exact", head: true })
    .is("read_at", null);

  return (
    <>
      <header className="border-b border-neutral-200">
        <nav className="mx-auto flex max-w-5xl flex-wrap items-center gap-4 px-6 py-3 text-sm">
          <Link href="/projects" className="font-semibold">
            Stall Watch
          </Link>
          <Link href="/projects" className="hover:underline">
            Projects
          </Link>
          <Link href="/alerts" className="hover:underline">
            Alerts{unread ? ` (${unread})` : ""}
          </Link>
          {user.isStaff ? (
            <Link href="/detector" className="hover:underline">
              Detector
            </Link>
          ) : null}
          <span className="ml-auto text-neutral-600">
            {user.email}
            {user.isStaff ? " · staff" : ""}
          </span>
          <form action={signOut}>
            <button type="submit" className="hover:underline">
              Sign out
            </button>
          </form>
        </nav>
      </header>
      <main className="mx-auto w-full max-w-5xl px-6 py-6">{children}</main>
    </>
  );
}
