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
assert.equal(queries.length, 12);
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
// Resolve by source table, so inserting a projection cannot silently retarget a test.
const byTable = (list) => {
  const pairs = list.map(query => {
    const table = query.match(/\bFROM\s+(?:ledger_private\.)?([a-z_]+)/)?.[1];
    assert.ok(table, "Every projection has an explicit source table");
    return [table, query];
  });
  const mapped = new Map(pairs);
  assert.equal(mapped.size, list.length, "One reviewed projection per source table");
  return mapped;
};
const reportQueries = byTable(queries);
const physicalQueries = byTable(section("physical_account_items"));
const projectQueries = byTable(section("spike_projects"));
const noteQueries = byTable(section("project_note_history"));
const sameProjection = (table, other, message) => {
  assert.ok(reportQueries.has(table) && other.has(table), `Missing overlapping ${table}`);
  assert.deepEqual(projection(reportQueries.get(table)), projection(other.get(table)), message);
};
sameProjection("spike_projects", projectQueries, "Report and bootstrap Project values must match exactly");
sameProjection("spike_projects", noteQueries, "Report and note-history Project values must match exactly");
for (const table of ["spike_items", "spike_item_placements", "spike_spaces", "item_image_sets"]) {
  sameProjection(table, physicalQueries, `Overlapping ${table} values must match exactly`);
}
// Only the marker overlaps this report. Gallery original and derivative
// queries intentionally both output item_image_objects; do not impose a
// one-query-per-table rule on that independent media subscription.
const galleryMarkers = section("item_images").filter(query =>
  query.match(/\bFROM\s+([a-z_]+)/)?.[1] === "item_image_sets");
assert.equal(galleryMarkers.length, 1, "Exactly one gallery marker projection");
sameProjection("item_image_sets", byTable(galleryMarkers), "Gallery and list marker values must match exactly");
for (const query of queries) {
  assert.match(query, /^SELECT /);
  assert.ok(!query.includes(";") && !query.split(/\bFROM\b/)[0].includes("*"));
  assert.ok(query.includes("subscription.parameter('account_id')") && query.includes("subscription.parameter('project_id')"));
  assert.equal(query.match(/auth\.user_id\(\)/g)?.length, 1);
}
const q = (value) => `'${value.replaceAll("'", "''")}'`;
const suffix = randomUUID();
const projects = [`report-a-${suffix}`, `report-b-${suffix}`];
const clients = projects.map((project) => `client-${project}`);
const ids = ["room", "placement", "item"].map((kind) => projects.map((project) => `${kind}-${project}`));
const sql = ["begin; set local standard_conforming_strings=on; set local statement_timeout='5s';"];
for (const [index, project] of projects.entries()) {
  sql.push(`insert into public.spike_clients(id,account_id,display_name,lifecycle,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
    values (${q(clients[index])},'account-primary','Report Client',${index === 0 ? "'archived'" : "'active'"},now(),now(),1,1,'principal-owner');`);
  sql.push(`insert into public.spike_projects(id,account_id,client_id,display_name,description,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
    values (${q(project)},'account-primary',${q(clients[index])},'Synthetic property','Not a property address',now(),now(),1,1,'principal-owner');`);
  sql.push(`insert into public.spike_spaces(id,account_id,scope_kind,project_id,display_name,lifecycle)
    values (${q(ids[0][index])},'account-primary','project',${q(project)},'Archived actual room','archived');`);
  sql.push(`insert into public.spike_items(id,account_id,name,description,sku,source,current_source,market_value_minor_units,market_value_currency,created_by_principal_id)
    values (${q(ids[2][index])},'account-primary',${index === 0 ? "'Actual Item name'" : "null"},'Not the Item name','SKU','Original vendor',${index === 0 ? "'Inventory'" : "''"},${index === 0 ? "0,'USD'" : "null,null"},'principal-owner');`);
  sql.push(`insert into public.spike_item_placements(id,account_id,item_id,scope_kind,project_id,space_id,started_at,started_by_principal_id)
    values (${q(ids[1][index])},'account-primary',${q(ids[2][index])},'project',${q(project)},${q(ids[0][index])},'2026-09-01','principal-owner');`);
  sql.push(`insert into public.item_image_sets(id,account_id,item_id,revision,expected_count)
    values (${q(ids[2][index])},'account-primary',${q(ids[2][index])},${index+1},${index === 0 ? 1 : 0});`);
  if (index === 0) {
    const imageId = `image-${project}`;
    sql.push(`insert into public.item_image_objects(id,account_id,content_sha256,byte_count,media_type,storage_path)
      values (${q(imageId)},'account-primary',repeat('b',64),17,'image/png',
        ${q(`accounts/account-primary/attachments/${imageId}/`)}||repeat('b',64));
      insert into public.item_image_references(id,account_id,item_id,attachment_id,set_revision,position,is_primary)
      values (${q(`ref-${project}`)},'account-primary',${q(ids[2][index])},${q(imageId)},1,0,true);`);
  }
  sql.push(`insert into public.spike_transactions(id,account_id,project_id,client_id,amount_minor_units,currency)
    values (${q(`payment-${project}`)},'account-primary',${q(project)},${q(clients[index])},500,'USD');
    insert into ledger_private.item_client_payment_connections(id,account_id,project_id,client_id,item_id,placement_id,transaction_id,started_at,started_by_principal_id)
    values (${q(`link-${project}`)},'account-primary',${q(project)},${q(clients[index])},${q(ids[2][index])},${q(ids[1][index])},${q(`payment-${project}`)},'2026-09-02','principal-owner');`);
  sql.push(`insert into public.spike_item_project_categories(id,account_id,project_id,item_id,category_id)
    values (${q(ids[1][index])},'account-primary',${q(project)},${q(ids[2][index])},'category-furnishings');`);
  sql.push(`insert into ledger_private.item_charge_occurrences(id,account_id,project_id,item_id,placement_id,category_id,
    amount_minor_units,currency,created_by_principal_id) values(${q(`charge-${project}`)},'account-primary',${q(project)},
    ${q(ids[2][index])},${q(ids[1][index])},'category-furnishings',500,'USD','principal-owner');
    insert into ledger_private.collected_invoices(id,account_id,project_id,client_id,purchase_id,invoice_revision,currency,total_minor_units)
    values(${q(`invoice-${project}`)},'account-primary',${q(project)},${q(clients[index])},${q(`payment-${project}`)},1,'USD',500);
    insert into ledger_private.collected_invoice_lines(id,account_id,invoice_id,line_position,currency,source_kind,source_id,item_id,
      source_revision,category_id,signed_amount_minor_units,description,source_snapshot)
    values(${q(`line-${project}`)},'account-primary',${q(`invoice-${project}`)},0,'USD','item',${q(`charge-${project}`)},
      ${q(ids[2][index])},1,'category-furnishings',500,'Synthetic','{}');
    update ledger_private.collected_invoices set sealed=true where id=${q(`invoice-${project}`)};`);
}
const user = "10000000-0000-0000-0000-000000000002";
function capture(label, account, project, principal = user, only = []) {
  for (const table of only) assert.ok(reportQueries.has(table), `Unknown capture projection ${table}`);
  for (const [table, query] of reportQueries) {
    if (only.length && !only.includes(table)) continue;
    const bound = query.replaceAll("subscription.parameter('account_id')", q(account))
      .replaceAll("subscription.parameter('project_id')", q(project))
      .replace("auth.user_id()", `${q(principal)}::uuid`);
    sql.push(`select json_build_object('label',${q(label)},'table',${q(table)},'rows',coalesce(json_agg(row_to_json(r)),'[]'::json)) from (${bound}) r;`);
  }
}
capture("project-a", "account-primary", projects[0]);
capture("project-b", "account-primary", projects[1]);
const owner = "10000000-0000-0000-0000-000000000001";
capture("owner-a", "account-primary", projects[0], owner);
capture("owner-b", "account-primary", projects[1], owner);
sql.push(`update ledger_private.item_client_payment_connections set ended_at='2026-09-03',ended_by_principal_id='principal-owner' where id=${q(`link-${projects[0]}`)};`);
capture("closed-link", "account-primary", projects[0], owner, ["item_client_payment_connections"]);
sql.push(`update public.spike_item_placements set ended_at='2026-09-03',ended_by_principal_id='principal-owner' where id=${q(ids[1][1])};`);
capture("departed-placement", "account-primary", projects[1], owner, ["item_client_payment_connections", "spike_item_project_categories", "spike_budget_categories", "item_charge_occurrences", "collected_invoice_lines", "collected_invoices", "item_image_sets"]);
sql.push("update public.spike_budget_categories set visibility_class='company_financial' where id='category-furnishings';");
capture("hidden-category", "account-primary", projects[0], user, ["spike_item_project_categories", "spike_budget_categories"]);
capture("wrong-account", "account-other", projects[0]);
capture("other-user", "account-primary", projects[0], "10000000-0000-0000-0000-000000000003");
sql.push("update public.spike_account_memberships set state='removed' where account_id='account-primary' and principal_id='principal-restricted';");
capture("removed", "account-primary", projects[0]);
sql.push("update public.spike_account_memberships set state='removed' where account_id='account-primary' and principal_id='principal-owner';");
capture("removed-full", "account-primary", projects[0], owner);
sql.push("rollback;");
const output = execFileSync("docker", ["exec", "-i", container, "psql", "-X", "-q", "-A", "-t", "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1"],
  { input: sql.join("\n"), encoding: "utf8", timeout: 30_000 });
const results = output.trim().split("\n").map(JSON.parse);
assert.equal(results.length, 106);
const columns = {
  item_image_sets: ["id", "account_id", "item_id", "revision", "expected_count"],
  spike_projects: ["id", "account_id", "client_id", "display_name", "description", "legacy_notes", "property_address", "lifecycle", "revision", "category_configuration_revision", "created_at_ms", "updated_at_ms", "created_by_principal_id"],
  spike_spaces: ["id", "account_id", "scope_kind", "project_id", "display_name", "lifecycle", "revision"],
  spike_item_placements: ["id", "account_id", "item_id", "scope_kind", "project_id", "space_id", "started_at", "started_by_principal_id", "ended_at", "ended_by_principal_id"],
  spike_items: ["id", "account_id", "name", "description", "sku", "workflow_status", "bookmark", "source", "current_source", "notes", "market_value_minor_units", "market_value_currency", "revision", "created_at", "created_by_principal_id"],
  spike_clients: ["id", "account_id", "display_name", "lifecycle", "revision", "created_at_ms", "updated_at_ms", "created_by_principal_id"],
  item_client_payment_connections: ["id", "account_id", "project_id", "client_id", "item_id", "placement_id", "transaction_id", "transaction_type", "transaction_role", "ended_at"],
  spike_item_project_categories: ["id", "account_id", "project_id", "item_id", "category_id", "revision"],
  spike_budget_categories: ["id", "account_id", "display_name", "kind", "lifecycle", "is_system", "excludes_from_overall_budget", "visibility_class", "presentation_order", "revision", "created_at_ms", "updated_at_ms"],
  item_charge_occurrences: ["id","account_id","project_id","item_id","placement_id","category_id","amount_minor_units","currency","revision","withdrawn_at"],
  collected_invoice_lines: ["id","account_id","invoice_id","source_kind","source_id","item_id","source_revision","category_id","signed_amount_minor_units","currency"],
  collected_invoices: ["id","account_id","project_id","client_id","sealed"],
};
assert.deepEqual([...reportQueries.keys()].sort(), Object.keys(columns).sort(), "Review every report projection");
const financialTables = new Set(["item_client_payment_connections", "item_charge_occurrences", "collected_invoice_lines", "collected_invoices"]);
for (const { label, table, rows } of results) {
  if (!["project-a", "project-b", "owner-a", "owner-b"].includes(label)) { assert.deepEqual(rows, [], label); continue; }
  if (financialTables.has(table) && !label.startsWith("owner-")) { assert.deepEqual(rows, [], 'Restricted members receive no financial provenance'); continue; }
  const selected = label.endsWith("-a") ? 0 : 1;
  assert.equal(rows.length, 1, `${label}: exact Project projection ${table}`);
  const row = rows[0];
  const expectedIDs = {
    item_image_sets: ids[2][selected],
    spike_projects: projects[selected],
    spike_spaces: ids[0][selected],
    spike_item_placements: ids[1][selected],
    spike_items: ids[2][selected],
    spike_clients: clients[selected],
    item_client_payment_connections: `link-${projects[selected]}`,
    spike_item_project_categories: ids[1][selected],
    spike_budget_categories: 'category-furnishings',
    item_charge_occurrences: `charge-${projects[selected]}`,
    collected_invoice_lines: `line-${projects[selected]}`,
    collected_invoices: `invoice-${projects[selected]}`,
  };
  assert.equal(row.id, expectedIDs[table]);
  assert.deepEqual(Object.keys(row).sort(), [...columns[table]].sort());
  assert.equal(row.account_id, "account-primary");
  if (table === "item_image_sets") {
    assert.equal(row.item_id, ids[2][selected]);
    assert.equal(row.revision, String(selected+1));
    assert.equal(row.expected_count, selected === 0 ? 1 : 0, "Positive and explicit-empty markers are exact, including limited members");
  }
  if (table === "spike_projects") {
    assert.equal(row.property_address, null);
    assert.equal(row.legacy_notes, null);
  }
  if (table === "spike_spaces") assert.equal(row.lifecycle, "archived", "Retain current Item's archived Space parent");
  if (table === "spike_clients") assert.equal(row.lifecycle, selected === 0 ? "archived" : "active", "Retain exact historical Client without including another Project's Client");
  if (table === "spike_items") {
    assert.equal(row.name, selected === 0 ? "Actual Item name" : null);
    assert.equal(row.source, "Original vendor");
    assert.equal(row.current_source, selected === 0 ? "Inventory" : "");
    assert.equal(row.market_value_minor_units, selected === 0 ? "0" : null);
    assert.equal(row.market_value_currency, selected === 0 ? "USD" : null);
  }
}
console.log("shared report stream: 12 named actual SQL projections / 106 captures preserve exact scope and image markers, deny hidden categories, restricted payment/charge/frozen provenance, closed links, departed placement, cross-Account/user/removal; fixtures rolled back (not live replication validation)");
