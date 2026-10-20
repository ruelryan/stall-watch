import { signIn } from "./actions";

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string }>;
}) {
  const { error } = await searchParams;

  return (
    <main className="mx-auto w-full max-w-sm px-4 pt-[18vh]">
      <p className="text-sm font-semibold tracking-tight">Stall Watch</p>
      <h1 className="mt-6 text-2xl font-medium tracking-tight">Sign in</h1>
      <p className="mt-1 text-sm text-mute">
        Builders see their own projects. Reverie3D staff see every builder&apos;s.
      </p>

      <form action={signIn} className="mt-8 flex flex-col gap-4">
        <label className="flex flex-col gap-1.5 text-sm">
          <span>Email</span>
          <input name="email" type="email" required autoComplete="email" className="field" />
        </label>
        <label className="flex flex-col gap-1.5 text-sm">
          <span>Password</span>
          <input
            name="password"
            type="password"
            required
            autoComplete="current-password"
            className="field"
          />
        </label>
        {error ? (
          <p role="alert" className="rounded-sm bg-kiln-wash px-3 py-2 text-sm text-kiln">
            {error}
          </p>
        ) : null}
        <button type="submit" className="btn btn-primary mt-2 py-2">
          Sign in
        </button>
      </form>
    </main>
  );
}
