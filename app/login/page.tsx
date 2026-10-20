import { signIn } from "./actions";

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string }>;
}) {
  const { error } = await searchParams;

  return (
    <main className="mx-auto max-w-sm p-8">
      <h1 className="text-2xl font-semibold">Stall Watch</h1>
      <p className="mt-1 text-sm text-neutral-600">Sign in with your email and password.</p>

      <form action={signIn} className="mt-6 flex flex-col gap-3">
        <label className="flex flex-col gap-1 text-sm">
          Email
          <input
            name="email"
            type="email"
            required
            autoComplete="email"
            className="rounded border border-neutral-300 px-3 py-2"
          />
        </label>
        <label className="flex flex-col gap-1 text-sm">
          Password
          <input
            name="password"
            type="password"
            required
            autoComplete="current-password"
            className="rounded border border-neutral-300 px-3 py-2"
          />
        </label>
        {error ? (
          <p role="alert" className="text-sm text-red-700">
            {error}
          </p>
        ) : null}
        <button
          type="submit"
          className="mt-2 rounded bg-neutral-900 px-3 py-2 text-white hover:bg-neutral-700"
        >
          Sign in
        </button>
      </form>
    </main>
  );
}
