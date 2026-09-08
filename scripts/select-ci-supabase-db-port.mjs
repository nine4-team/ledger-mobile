import { appendFile } from "node:fs/promises";
import { createServer } from "node:net";
import { pathToFileURL } from "node:url";

// Match Docker's IPv4 wildcard bind. This is a free-port selection, not a
// reservation: a later bind conflict must still fail startup visibly.
export async function selectDatabasePort() {
  const server = createServer();
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen({ host: "0.0.0.0", port: 0, exclusive: true }, resolve);
  });
  const { port } = server.address();
  await new Promise((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
  return port;
}

export async function configureDatabasePort(environment = process.env) {
  if (environment.GITHUB_ACTIONS !== "true" || !environment.GITHUB_ENV) {
    throw new Error("Database port selection requires the GitHub Actions environment file");
  }
  const port = await selectDatabasePort();
  // The pinned CLI maps SUPABASE_DB_PORT to db.port. Persist it for start,
  // lint, tests, status and cleanup without modifying tracked config or identity.
  await appendFile(environment.GITHUB_ENV, `SUPABASE_DB_PORT=${port}\n`);
  return port;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  console.log(`Selected CI Supabase database port ${await configureDatabasePort()}`);
}
