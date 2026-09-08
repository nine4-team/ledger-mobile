import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { execFileSync } from "node:child_process";
import { readFileSync, realpathSync } from "node:fs";

// Actual stream SQL authorization/projection test, not PowerSync engine proof.
assert.ok(!process.env.DOCKER_HOST && !process.env.DOCKER_CONTEXT);
const docker = (args) => execFileSync("docker", args, { encoding: "utf8", timeout: 10_000 });
assert.match(JSON.parse(docker(["context", "inspect", "--format", "{{json .Endpoints.docker.Host}}"])), /^unix:\/\//);
const container = "supabase_db_ledger_target_supabase_local";
const labels = JSON.parse(docker(["inspect", "--format", "{{json .Config.Labels}}", container]));
assert.equal(labels["com.supabase.cli.project"], "ledger_target_supabase_local");
assert.equal(realpathSync(labels["com.supabase.cli.workdir"]), realpathSync(process.cwd()));
const yaml = readFileSync("powersync/sync-streams.yaml", "utf8");
const block = yaml.match(/^  property_management_report:\n([\s\S]*?)(?=^  \S|$(?![\s\S]))/m)?.[1];
assert.ok(block);
const pattern = /^      - \|\n((?:        .*(?:\n|$))+)/gm;
const queries = [...block.matchAll(pattern)].map((match) => match[1].replace(/^        /gm, "").trim());
assert.equal(queries.length, 4);
assert.equal(block.replace(/^    queries:\n/, "").replace(pattern, "").trim(), "");
// Overlapping buckets can contain the same table/id. Keep the complete SELECT
// expressions identical, including casts/aliases—not merely the output keys.
const section = (name) => {
  const match = yaml.match(new RegExp(`^  ${name}:\\n([\\s\\S]*?)(?=^  \\S|$(?![\\s\\S]))`, "m"));
  assert.ok(match, `Missing ${name}`);
  return [...match[1].matchAll(/^      - \|\n((?:        .*(?:\n|$))+)/gm)]
    .map((entry) => entry[1].replace(/^        /gm, "").trim());
};
const projection = (query) => {
  const match = query.match(/^SELECT\s+([\s\S]*?)\s+FROM\s/);
  assert.ok(match);
  return match[1].split(",").map((expression) => expression.trim().replace(/\s+/g, " "));
};
const physicalQueries = section("physical_account_items");
const projectQueries = section("spike_projects");
const noteQueries = section("project_note_history");
assert.deepEqual(projection(queries[0]), projection(projectQueries[0]), "Report and bootstrap Project values must match exactly");
assert.deepEqual(projection(queries[0]), projection(noteQueries[0]), "Report and note-history Project values must match exactly");
assert.deepEqual(projection(queries[3]), projection(physicalQueries[0]), "Report and physical Item values must match exactly");
assert.deepEqual(projection(queries[2]), projection(physicalQueries[1]), "Overlapping placement values must match exactly");
assert.deepEqual(projection(queries[1]), projection(physicalQueries[2]), "Overlapping Space values must match exactly");
for (const query of queries) {
  assert.match(query, /^SELECT /);
  assert.ok(!query.includes(";") && !query.split(/\bFROM\b/)[0].includes("*"));
  assert.ok(query.includes("subscription.parameter('account_id')") && query.includes("subscription.parameter('project_id')"));
  assert.equal(query.match(/auth\.user_id\(\)/g)?.length, 1);
}
const q = (value) => `'${value.replaceAll("'", "''")}'`;
const suffix = randomUUID();
const projects = [`report-a-${suffix}`, `report-b-${suffix}`];
const ids = ["room", "placement", "item"].map((kind) => projects.map((project) => `${kind}-${project}`));
const sql = ["begin; set local standard_conforming_strings=on; set local statement_timeout='5s';"];
for (const [index, project] of projects.entries()) {
  sql.push(`insert into public.spike_projects(id,account_id,client_id,display_name,description,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
    values (${q(project)},'account-primary','client-existing','Synthetic property','Not a property address',now(),now(),1,1,'principal-owner');`);
  sql.push(`insert into public.spike_spaces(id,account_id,scope_kind,project_id,display_name,lifecycle)
    values (${q(ids[0][index])},'account-primary','project',${q(project)},'Archived actual room','archived');`);
  sql.push(`insert into public.spike_items(id,account_id,name,description,sku,market_value_minor_units,market_value_currency,created_by_principal_id)
    values (${q(ids[2][index])},'account-primary',${index === 0 ? "'Actual Item name'" : "null"},'Not the Item name','SKU',${index === 0 ? "0,'USD'" : "null,null"},'principal-owner');`);
  sql.push(`insert into public.spike_item_placements(id,account_id,item_id,scope_kind,project_id,space_id,started_at,started_by_principal_id)
    values (${q(ids[1][index])},'account-primary',${q(ids[2][index])},'project',${q(project)},${q(ids[0][index])},'2026-09-01','principal-owner');`);
}
const user = "10000000-0000-0000-0000-000000000002";
function capture(label, account, project, principal = user) {
  for (const [index, query] of queries.entries()) {
    const bound = query.replaceAll("subscription.parameter('account_id')", q(account))
      .replaceAll("subscription.parameter('project_id')", q(project))
      .replace("auth.user_id()", `${q(principal)}::uuid`);
    sql.push(`select json_build_object('label',${q(label)},'index',${index},'rows',coalesce(json_agg(row_to_json(r)),'[]'::json)) from (${bound}) r;`);
  }
}
capture("project-a", "account-primary", projects[0]);
capture("project-b", "account-primary", projects[1]);
capture("wrong-account", "account-other", projects[0]);
capture("other-user", "account-primary", projects[0], "10000000-0000-0000-0000-000000000003");
sql.push("update public.spike_account_memberships set state='removed' where account_id='account-primary' and principal_id='principal-restricted';");
capture("removed", "account-primary", projects[0]);
sql.push("rollback;");
const output = execFileSync("docker", ["exec", "-i", container, "psql", "-X", "-q", "-A", "-t", "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1"],
  { input: sql.join("\n"), encoding: "utf8", timeout: 30_000 });
const results = output.trim().split("\n").map(JSON.parse);
assert.equal(results.length, 20);
const columns = [
  ["id", "account_id", "client_id", "display_name", "description", "property_address", "lifecycle", "revision", "category_configuration_revision", "created_at_ms", "updated_at_ms", "created_by_principal_id"],
  ["id", "account_id", "scope_kind", "project_id", "display_name", "lifecycle", "revision"],
  ["id", "account_id", "item_id", "scope_kind", "project_id", "space_id", "started_at", "started_by_principal_id", "ended_at", "ended_by_principal_id"],
  ["id", "account_id", "name", "description", "sku", "market_value_minor_units", "market_value_currency", "revision", "created_at", "created_by_principal_id"],
];
for (const { label, index, rows } of results) {
  if (!["project-a", "project-b"].includes(label)) { assert.deepEqual(rows, [], label); continue; }
  const selected = label === "project-a" ? 0 : 1;
  assert.equal(rows.length, 1, `${label}: exact Project projection ${index}`);
  const row = rows[0];
  assert.equal(row.id, index === 0 ? projects[selected] : ids[index - 1][selected]);
  assert.deepEqual(Object.keys(row).sort(), [...columns[index]].sort());
  assert.equal(row.account_id, "account-primary");
  if (index === 0) assert.equal(row.property_address, null);
  if (index === 1) assert.equal(row.lifecycle, "archived", "Retain current Item's archived Space parent");
  if (index === 3) {
    assert.equal(row.name, selected === 0 ? "Actual Item name" : null);
    assert.equal(row.market_value_minor_units, selected === 0 ? "0" : null);
    assert.equal(row.market_value_currency, selected === 0 ? "USD" : null);
  }
}
console.log("property-management stream: 4 actual SQL projections preserve exact Project, archived parent, name/address and unknown/zero values; deny cross-Account/user/removal; all fixtures rolled back (not PowerSync engine validation)");
