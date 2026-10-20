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
      <header className="border-b border-line bg-paper">
        <nav className="mx-auto flex w-full max-w-5xl flex-wrap items-center gap-x-6 gap-y-2 px-6 py-3 text-sm">
          <Link href="/projects" className="font-semibold tracking-tight">
            Stall Watch
          </Link>
          <Link href="/projects" className="text-mute hover:text-ink">
            Projects
          </Link>
          <Link href="/alerts" className="flex items-center gap-1.5 text-mute hover:text-ink">
            Alerts
            {unread ? (
              <span className="pill pill-stalled num px-1.5 py-0 text-[11px]">{unread}</span>
            ) : null}
          </Link>
          {user.isStaff ? (
            <Link href="/detector" className="text-mute hover:text-ink">
              Detector
            </Link>
          ) : null}
          <span className="ml-auto text-mute">
            {user.email}
            {user.isStaff ? <span className="ml-2 pill pill-dim">staff</span> : null}
          </span>
          <form action={signOut}>
            <button type="submit" className="btn btn-quiet px-0">
              Sign out
            </button>
          </form>
        </nav>
      </header>
      <main className="mx-auto w-full max-w-5xl px-6 pb-16 pt-8">{children}</main>
    </>
  );
}
