import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    // Use forks pool for isolation (firebase-admin is stateful).
    pool: "forks",
    poolOptions: {
      forks: { singleFork: true },
    },
    // Generous timeout — emulator calls take time.
    testTimeout: 30_000,
    hookTimeout: 30_000,
    // Run TypeScript tests via esbuild transform (vitest built-in).
  },
});
