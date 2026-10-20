import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Every page reads the session cookie and renders per user, so there is nothing to
  // prerender into a static shell. Plain dynamic rendering keeps the app simple.
  cacheComponents: false,
  turbopack: {
    rules: {
      "*.css": {
        loaders: ["@tailwindcss/turbopack"],
        as: "*.css",
      },
    },
  },
};

export default nextConfig;
