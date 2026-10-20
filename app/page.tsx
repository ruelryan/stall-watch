import { redirect } from "next/navigation";

// The proxy already sends signed-in users to /projects and everyone else to /login; this is
// the fallback for the root path.
export default function Home() {
  redirect("/projects");
}
