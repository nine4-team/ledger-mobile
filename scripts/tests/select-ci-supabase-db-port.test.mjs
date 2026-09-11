import assert from "node:assert/strict";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { createServer } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { configureDatabasePort, selectDatabasePort } from "../select-ci-supabase-db-port.mjs";

test("selection avoids an occupied wildcard port and releases its own socket", async () => {
  const occupied = createServer();
  await new Promise(resolve => occupied.listen(0, "0.0.0.0", resolve));
  try {
    const port = await selectDatabasePort();
    assert.ok(Number.isInteger(port) && port > 0 && port <= 65535);
    assert.notEqual(port, occupied.address().port);
    const probe = createServer();
    await new Promise((resolve, reject) => {
      probe.once("error", reject);
      probe.listen(port, "0.0.0.0", resolve);
    });
    await new Promise(resolve => probe.close(resolve));
    assert.equal(occupied.listening, true);
  } finally {
    await new Promise(resolve => occupied.close(resolve));
  }
});

test("CI export appends only the selected database port", async () => {
  const directory = await mkdtemp(join(tmpdir(), "ledger-ci-port-"));
  try {
    const file = join(directory, "environment");
    await writeFile(file, "EXISTING=value\n");
    const port = await configureDatabasePort({ GITHUB_ACTIONS: "true", GITHUB_ENV: file });
    assert.equal(await readFile(file, "utf8"), `EXISTING=value\nSUPABASE_DB_PORT=${port}\n`);
    await assert.rejects(configureDatabasePort({ GITHUB_ACTIONS: "true", GITHUB_ENV: join(directory, "missing", "file") }));
  } finally {
    await rm(directory, { recursive: true });
  }
});

test("normal local invocations cannot change the database configuration", async () => {
  for (const environment of [{}, { GITHUB_ACTIONS: "true" }, { GITHUB_ENV: "/unused" }]) {
    await assert.rejects(configureDatabasePort(environment), /requires the GitHub Actions/);
  }
});
