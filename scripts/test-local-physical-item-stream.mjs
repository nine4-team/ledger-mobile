import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { execFileSync } from "node:child_process";
import { readFileSync, realpathSync } from "node:fs";

// Execute the actual stream SELECTs as privileged Postgres queries so their
// authorization predicates—not RLS—must protect the result. This does not test
// PowerSync's parser, replication engine or hosted revocation behavior.
assert.ok(!process.env.DOCKER_HOST && !process.env.DOCKER_CONTEXT, "No Docker destination override");
const docker = (args) => execFileSync("docker", args, { encoding: "utf8", timeout: 10_000 });
const endpoint = JSON.parse(docker(["context", "inspect", "--format", "{{json .Endpoints.docker.Host}}"]));
assert.match(endpoint, /^unix:\/\//, "Only a local Unix Docker socket is authorized");
const container = "supabase_db_ledger_target_supabase_local";
const labels = JSON.parse(docker(["inspect", "--format", "{{json .Config.Labels}}", container]));
assert.equal(labels["com.supabase.cli.project"], "ledger_target_supabase_local");
assert.equal(realpathSync(labels["com.supabase.cli.workdir"]), realpathSync(process.cwd()));

const yaml = readFileSync("powersync/sync-streams.yaml", "utf8");
const block = yaml.match(/^  physical_account_items:\n([\s\S]*?)(?=^  \S|$(?![\s\S]))/m)?.[1];
assert.ok(block, "physical_account_items stream exists");
assert.match(block, /^    queries:\n/);
const queries = [...block.matchAll(/^      - \|\n((?:        .*(?:\n|$))+)/gm)]
  .map((match) => match[1].replace(/^        /gm, "").trim());
assert.equal(queries.length, 3, "Review changes to the three physical stream projections");
assert.equal(block.replace(/^    queries:\n/, "")
  .replace(/^      - \|\n((?:        .*(?:\n|$))+)/gm, "").trim(), "", "No unparsed stream configuration");
for (const [index, sql] of queries.entries()) {
  assert.match(sql, /^SELECT /);
  assert.ok(!sql.split(/\bFROM\b/)[0].includes("*"), "Projection must name columns explicitly");
  assert.ok(!sql.includes(";"), "Expected one SELECT per stream query");
  assert.equal(sql.match(/auth\.user_id\(\)/g)?.length, 1);
  assert.equal(sql.match(/subscription\.parameter\('account_id'\)/g)?.length, index === 2 ? 2 : 1);
}
const quote = (value) => `'${value.replaceAll("'", "''")}'`;
const suffix = randomUUID();
const fixtureIDs = ["item", "placement", "space"].map((kind) => [`stream-${kind}-a-${suffix}`, `stream-${kind}-b-${suffix}`]);
const unusedArchivedSpace = `stream-unused-archived-${suffix}`;
const endedArchivedSpace = `stream-ended-archived-${suffix}`;
const userA = "10000000-0000-0000-0000-000000000002"; // Employee: no financial access.
const userB = "10000000-0000-0000-0000-000000000003";
const statements = ["begin; set local standard_conforming_strings=on; set local statement_timeout='5s';"];
for (const [index, account, principal] of [[0, "account-primary", "principal-restricted"], [1, "account-other", "principal-other"]]) {
  statements.push(`insert into public.spike_items(id,account_id,description,workflow_status,bookmark,created_by_principal_id) values (${quote(fixtureIDs[0][index])},${quote(account)},'Synthetic physical stream test','legacy sold',${index === 0 ? 'true' : 'null'},${quote(principal)});`);
  statements.push(`insert into public.spike_spaces(id,account_id,scope_kind,display_name) values (${quote(fixtureIDs[2][index])},${quote(account)},'business_inventory','Synthetic stream space');`);
  statements.push(`insert into public.spike_item_placements(id,account_id,item_id,scope_kind,space_id,started_at,started_by_principal_id) values (${quote(fixtureIDs[1][index])},${quote(account)},${quote(fixtureIDs[0][index])},'business_inventory',${quote(fixtureIDs[2][index])},'2026-09-01',${quote(principal)});`);
}
statements.push(`insert into public.spike_spaces(id,account_id,scope_kind,display_name,lifecycle) values
  (${quote(unusedArchivedSpace)},'account-primary','business_inventory','Unused archived','archived'),
  (${quote(endedArchivedSpace)},'account-primary','business_inventory','Ended archived','archived');`);
statements.push(`insert into public.spike_item_placements(id,account_id,item_id,scope_kind,space_id,started_at,started_by_principal_id,ended_at,ended_by_principal_id) values
  (${quote(`stream-ended-placement-${suffix}`)},'account-primary',${quote(fixtureIDs[0][0])},'business_inventory',${quote(endedArchivedSpace)},'2026-08-01','principal-restricted','2026-08-02','principal-restricted');`);
function capture(label, user, account) {
  for (const [index, source] of queries.entries()) {
    // Only the two PowerSync parameter functions are translated; the real
    // projection, joins and predicates remain exactly those in the YAML.
    const sql = source.replace("auth.user_id()", `${quote(user)}::uuid`)
      .replaceAll("subscription.parameter('account_id')", quote(account));
    statements.push(`select json_build_object('label',${quote(label)},'index',${index},'rows',coalesce(json_agg(row_to_json(stream_row)),'[]'::json)) from (${sql}) stream_row;`);
  }
}
capture("member", userA, "account-primary");
capture("foreign-parameter", userA, "account-other");
capture("other-member", userB, "account-other");
capture("other-user-denied", userB, "account-primary");
statements.push(`update public.spike_spaces set lifecycle='archived',revision=revision+1 where id in (${fixtureIDs[2].map(quote).join(",")});`);
capture("archived-parent", userA, "account-primary");
capture("archived-foreign-denied", userA, "account-other");
capture("unknown-user-denied", "00000000-0000-0000-0000-000000000000", "account-primary");
statements.push("update public.spike_account_memberships set state='removed' where account_id='account-primary' and principal_id='principal-restricted';");
capture("removed-same-user", userA, "account-primary");
statements.push("rollback;");
const output = execFileSync("docker", ["exec", "-i", container, "psql", "-X", "-q", "-A", "-t", "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1"],
  { input: statements.join("\n"), encoding: "utf8", timeout: 30_000 });
const results = output.trim().split("\n").map((line) => JSON.parse(line));
assert.equal(results.length, 24);
const columns = [
  ["id", "account_id", "name", "description", "sku", "workflow_status", "bookmark", "market_value_minor_units", "market_value_currency", "revision", "created_at", "created_by_principal_id"],
  ["id", "account_id", "item_id", "scope_kind", "project_id", "space_id", "started_at", "started_by_principal_id", "ended_at", "ended_by_principal_id"],
  ["id", "account_id", "scope_kind", "project_id", "display_name", "lifecycle", "revision"],
];
for (const { label, index, rows } of results) {
  if (!["member", "other-member", "archived-parent"].includes(label)) {
    assert.deepEqual(rows, [], `${label}: projection ${index} must deny all rows`);
    continue;
  }
  const fixtureIndex = label === "other-member" ? 1 : 0;
  const account = fixtureIndex === 0 ? "account-primary" : "account-other";
  assert.ok(rows.some((row) => row.id === fixtureIDs[index][fixtureIndex]), `${label}: expected fixture in projection ${index}`);
  for (const row of rows) {
    assert.equal(row.account_id, account, "No cross-Account physical facts");
    assert.deepEqual(Object.keys(row).sort(), [...columns[index]].sort(), "Only reviewed physical columns may be downloaded");
    if (index === 0 && row.id === fixtureIDs[0][fixtureIndex]) {
      assert.equal(row.workflow_status, 'legacy sold');
      assert.equal(row.bookmark, fixtureIndex === 0 ? true : null);
    }
    if (index === 2) {
      assert.notEqual(row.id, unusedArchivedSpace, "Unreferenced archived Space is not downloaded");
      assert.notEqual(row.id, endedArchivedSpace, "Ended-only Space is not a current physical parent");
      if (row.id === fixtureIDs[2][fixtureIndex]) {
        assert.equal(row.lifecycle, label === "archived-parent" ? "archived" : "active");
      }
    }
  }
}
console.log("local-physical-item-stream: 24 actual SQL captures pass member, current archived parent, unreferenced/ended archived exclusion, cross-Account, other-user, removal and physical-column checks; all fixtures rolled back (not PowerSync engine validation)");
