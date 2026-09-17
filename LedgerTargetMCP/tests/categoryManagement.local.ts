// Explicit local integration entry point, not part of network-free *.test.ts.
// Uses only the isolated Supabase stack and removes its exact synthetic Accounts.
import assert from "node:assert/strict";
import { createHmac, randomUUID } from "node:crypto";
import { execFileSync, execFile } from "node:child_process";
import { createServer } from "node:http";
import { promisify } from "node:util";
import { fileURLToPath } from "node:url";
import { realpathSync, readFileSync } from "node:fs";
import { manageCategoriesTool, SupabaseCategoryManagementApplier, type CategoryManagementInput } from "../src/categoryManagement.js";
import { SupabaseTransactionReceiptReader } from "../src/transactionReceiptRead.js";
import { SupabaseTransactionDetailReader } from "../src/transactionDetailRead.js";
import { transactionDetailsEditTool } from "../src/transactionDetailsEdit.js";
import { transactionReceiptLinesEditTool } from "../src/transactionReceiptLinesEdit.js";

const root = fileURLToPath(new URL("../../", import.meta.url));
assert.ok(!process.env.DOCKER_HOST && !process.env.DOCKER_CONTEXT, "Local tests refuse Docker endpoint overrides");
assert.match(JSON.parse(execFileSync("docker", ["context", "inspect", "--format", "{{json .Endpoints.docker.Host}}"],
  { encoding: "utf8" })), /^unix:\/\//);
const labels = JSON.parse(execFileSync("docker", ["inspect", "--format", "{{json .Config.Labels}}",
  "supabase_db_ledger_target_supabase_local"], { encoding: "utf8" }));
assert.equal(labels["com.supabase.cli.project"], "ledger_target_supabase_local");
assert.equal(realpathSync(labels["com.supabase.cli.workdir"]), realpathSync(root));
const status = JSON.parse(execFileSync("npx", ["--yes", "supabase@2.116.0", "status", "-o", "json"],
  { cwd: root, encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }));
const rest = new URL(status.REST_URL);
assert.equal(rest.protocol, "http:", "Local category test refuses hosted endpoints");
assert.ok(["127.0.0.1", "localhost"].includes(rest.hostname), "Local category test refuses remote endpoints");
assert.equal(typeof status.JWT_SECRET, "string");
assert.equal(typeof status.PUBLISHABLE_KEY, "string");
const accountId = `category-http-${randomUUID()}`;
const foreignAccountId = `${accountId}-foreign`;
const literal = (value: string) => `'${value.replaceAll("'", "''")}'`;
const sql = (query: string, unaligned = false) => execFileSync("docker", ["exec", "-i", "supabase_db_ledger_target_supabase_local",
  "psql", "-X", "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-1", ...(unaligned ? ["-A", "-t"] : [])],
  { input: query, encoding: "utf8", maxBuffer: 16 * 1024 * 1024, stdio: ["pipe", "pipe", "pipe"] });
// Current export completeness is a data-contract claim, not completed future
// writers. Expanding server origins must update native/MCP/stream coverage too.
const originContract = sql(`select pg_get_constraintdef(oid) from pg_constraint
  where conrelid='public.spike_transactions'::regclass and conname='spike_transactions_origin_check'
    and convalidated;`);
assert.deepEqual([...originContract.matchAll(/'([^']+)'/g)].map(match => match[1]).sort(),
  ['firebase_client_payment', 'vendor_payment'], 'Export readers/streams must cover every allowed server origin');
const token = (sub: string) => {
  const base = (value: unknown) => Buffer.from(JSON.stringify(value)).toString("base64url");
  const issuedAt = Math.floor(Date.now() / 1000);
  const unsigned = `${base({ alg: "HS256", typ: "JWT" })}.${base({ sub, role: "authenticated", aud: "authenticated", iat: issuedAt, exp: issuedAt + 600 })}`;
  return `${unsigned}.${createHmac("sha256", status.JWT_SECRET).update(unsigned).digest("base64url")}`;
};
const owner = { accountId, principalId: "principal-owner", accessToken: token("10000000-0000-0000-0000-000000000001") };
const member = { accountId, principalId: "principal-restricted", accessToken: token("10000000-0000-0000-0000-000000000002") };
const applier = new SupabaseCategoryManagementApplier(new URL(rest.origin), status.PUBLISHABLE_KEY);
const receipts = new SupabaseTransactionReceiptReader(new URL(rest.origin), status.PUBLISHABLE_KEY);
const details = new SupabaseTransactionDetailReader(new URL(rest.origin), status.PUBLISHABLE_KEY);
const receiptId = `${accountId}-receipt`, receiptItemId = `${accountId}-item`;
const receiptProject = `${accountId}-receipt-project`, receiptClient = `${accountId}-receipt-client`;
const streamBlock = readFileSync(new URL("../../powersync/sync-streams.yaml", import.meta.url), "utf8")
  .match(/^  transaction_receipts:\n([\s\S]*?)(?=^  \S|$(?![\s\S]))/m)?.[1];
assert.ok(streamBlock);
const streamQueries = [...streamBlock.matchAll(/^      - \|\n((?:        .*(?:\n|$))+)/gm)]
  .map(match => match[1].replace(/^        /gm, "").trim());
assert.equal(streamQueries.length, 17);
// Execute the checked-in stream predicates as the replication role would, not
// under RLS that could accidentally conceal a missing stream authorization filter.
function receiptStream(userId: string, scope = "business_inventory", project: string | null = null, account = accountId, idsOnly = false) {
  const args: Record<string, string | null> = { account_id: account, scope_kind: scope, project_id: project };
  return streamRows(streamQueries, userId, args, idsOnly);
}
function streamRows(queries: string[], userId: string, args: Record<string, string | null>, idsOnly = false) {
  const tables = new Map<string, string[]>();
  for (const query of queries) {
    const table = query.match(/\bFROM\s+(?:ledger_private\.)?([a-z_]+)/)?.[1];
    assert.ok(table);
    if (idsOnly && !['spike_items', 'item_image_sets', 'spike_item_placements', 'spike_item_project_categories', 'transaction_receipt_items'].includes(table)) continue;
    // PowerSync's two-argument SQLite IFNULL has PostgreSQL COALESCE semantics.
    const bound = query.replaceAll('ifnull(', 'coalesce(').replaceAll("auth.user_id()", `${literal(userId)}::uuid`)
      .replace(/subscription\.parameter\('([a-z_]+)'\)/g, (_, key) => {
        assert.ok(key in args); return args[key] === null ? "NULL" : literal(args[key]!);
      });
    const queries = tables.get(table) ?? [];
    queries.push(`select ${idsOnly ? "jsonb_build_object('id',row.id)" : "to_jsonb(row)"} as payload from (${bound}) row`);
    tables.set(table, queries);
  }
  // Multiple origin queries target the same table. Combine their results;
  // duplicate JSON keys would silently discard the earlier origin.
  const fields = [...tables].map(([table, queries]) =>
    `${literal(table)},(select coalesce(jsonb_agg(payload),'[]'::jsonb) from (${queries.join(" union all ")}) rows)`);
  const output = sql(`select 'STREAM_RESULT:' || jsonb_build_object(${fields.join(",")})::text;`, true);
  const row = output.split("\n").map(line => line.trim()).find(line => line.startsWith("STREAM_RESULT:"));
  assert.ok(row);
  return JSON.parse(row.slice("STREAM_RESULT:".length)) as Record<string, Array<Record<string, unknown>>>;
}
function assertDirectoryStreamParity(userId: string) {
  const block = readFileSync(new URL('../../powersync/sync-streams.yaml', import.meta.url), 'utf8')
    .match(/^  spike_projects:\n([\s\S]*?)(?=^  \S)/m)?.[1];
  assert.ok(block);
  const queries = [...block.matchAll(/^      - \|\n((?:        .*(?:\n|$))+)/gm)].map(match=>match[1]);
  assert.equal(queries.length, 3);
  const actual = streamRows(queries.slice(1), userId, {});
  const output = sql(`select set_config('request.jwt.claims',json_build_object('sub',${literal(userId)})::text,true);
    set local role authenticated;
    select 'RLS_DIRECTORY:'||json_build_object(
      'spike_budget_categories',(select coalesce(json_agg(id order by id),'[]') from public.spike_budget_categories),
      'spike_project_category_allocations',(select coalesce(json_agg(id order by id),'[]') from public.spike_project_category_allocations))::text;`);
  const line = output.split('\n').map(value=>value.trim()).find(value=>value.startsWith('RLS_DIRECTORY:'));
  assert.ok(line);
  const expected = JSON.parse(line.slice('RLS_DIRECTORY:'.length));
  for (const table of Object.keys(expected)) assert.deepEqual(actual[table].map(row=>row.id).sort(), expected[table],
    `${table}: default stream permission must equal database RLS, including other local Accounts`);
}
const input = (payload: CategoryManagementInput["payload"]): CategoryManagementInput => ({
  operationUUID: randomUUID(), clientCreatedAtMilliseconds: Date.now(), payload });
const create = (id: string, name: string, kind: "fee" | "general" = "general") => input({
  action: "create", categoryId: id, name, kind, excludesFromOverallBudget: false });
const a = `${accountId}-a`, b = `${accountId}-b`;
let seeded = false;
let authUserId: string | undefined;
const authPrincipal = `${accountId}-principal`;
try {
  sql(`insert into public.spike_accounts(id,display_name) values(${literal(accountId)},'Category HTTP fixture'),
    (${literal(foreignAccountId)},'Isolated foreign fixture');
    insert into public.spike_account_memberships(account_id,principal_id,role,state,financial_access)
      values(${literal(accountId)},'principal-owner','owner','active','full'),
      (${literal(accountId)},'principal-restricted','employee','active','none'),
      (${literal(foreignAccountId)},'principal-owner','owner','active','full');
    notify pgrst, 'reload schema';`);
  seeded = true;
  assert.equal((await manageCategoriesTool(create(a, "Fee", "fee"), owner, applier)).phase, "applied");
  assert.equal((await manageCategoriesTool(create(`${a}-foreign`, "Foreign category"),
    { ...owner, accountId: foreignAccountId }, applier)).phase, "applied");
  sql(`insert into public.spike_items(id,account_id,description,created_by_principal_id,source,current_source)
    values(${literal(receiptItemId)},${literal(accountId)},'Receipt Item','principal-owner','Original vendor','Display vendor');
    insert into public.spike_transactions(id,account_id,scope_kind,origin,type,amount_minor_units,currency,category_id,non_item_receipt_lines)
    values(${literal(receiptId)},${literal(accountId)},'business_inventory','vendor_payment','purchase',100,'USD',${literal(a)},
      '[{"id":"tax","description":"Tax","amountMinorUnits":"1","effect":"increase"}]');
    insert into public.transaction_receipt_items(id,account_id,transaction_id,item_id,currency,amount_minor_units,membership_kind)
    values(${literal(`${accountId}-receipt-link`)},${literal(accountId)},${literal(receiptId)},${literal(receiptItemId)},'USD',99,'sold');`);
  sql(`insert into public.spike_items(id,account_id,description,created_by_principal_id)
    values(${literal(`${receiptItemId}-foreign`)},${literal(foreignAccountId)},'Private foreign Item','principal-owner');
    insert into public.spike_transactions(id,account_id,scope_kind,origin,type,amount_minor_units,currency,category_id)
    values(${literal(`${receiptId}-foreign`)},${literal(foreignAccountId)},'business_inventory','vendor_payment','purchase',99,'USD',${literal(`${a}-foreign`)});
    insert into public.transaction_receipt_items(id,account_id,transaction_id,item_id,currency,amount_minor_units,membership_kind)
    values(${literal(`${accountId}-foreign-link`)},${literal(foreignAccountId)},${literal(`${receiptId}-foreign`)},
      ${literal(`${receiptItemId}-foreign`)},'USD',99,'linked');`);
  await assert.rejects(receipts.read({ transactionId: receiptId }, member), { code: "transaction_not_available" });
  await assert.rejects(details.read({ transactionId: receiptId }, member), { code: "transaction_not_available" });
  sql(`update public.spike_transactions set source='Café vendor',transaction_date='2024-02-29',
    created_at_ms=1709251200123,notes='Preserved notes',payment_method='Company card',has_email_receipt=false,
    legacy_subtotal_minor_units=9007199254740993,legacy_tax_rate_pct=8.12345678901234567890
    where id=${literal(receiptId)} and account_id=${literal(accountId)};`);
  assert.equal((await receipts.read({ transactionId: receiptId }, owner)).audit.status, "notApplicable");
  sql(`insert into public.spike_clients(id,account_id,display_name,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
    values(${literal(receiptClient)},${literal(accountId)},'Receipt client',now(),now(),1,1,'principal-owner');
    insert into public.spike_projects(id,account_id,client_id,display_name,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
    values(${literal(receiptProject)},${literal(accountId)},${literal(receiptClient)},'Receipt project',now(),now(),1,1,'principal-owner');
    insert into public.spike_transactions(id,account_id,project_id,client_id,scope_kind,origin,type,amount_minor_units,currency,category_id)
    values(${literal(`${receiptId}-project`)},${literal(accountId)},${literal(receiptProject)},${literal(receiptClient)},
      'project','vendor_payment','return',99,'USD',${literal(a)});
    insert into public.transaction_receipt_items(id,account_id,transaction_id,item_id,currency,amount_minor_units,membership_kind)
    values(${literal(`${accountId}-project-link`)},${literal(accountId)},${literal(`${receiptId}-project`)},${literal(receiptItemId)},'USD',99,'returned');`);
  sql(`select ledger_private.import_client_payment(${literal(`${receiptId}-payment`)},${literal(accountId)},
    ${literal(receiptProject)},${literal(receiptClient)},9007199254740993,'USD',${literal(accountId)},'standalone-payment',decode('01','hex'));`);
  sql(`insert into public.spike_spaces(id,account_id,scope_kind,project_id,display_name,lifecycle)
    values(${literal(`${receiptItemId}-space`)},${literal(accountId)},'project',${literal(receiptProject)},'Current room','active');
    insert into public.spike_item_placements(id,account_id,item_id,scope_kind,project_id,space_id,
    started_at,ended_at,started_by_principal_id,ended_by_principal_id) values
    (${literal(`${receiptItemId}-inventory`)},${literal(accountId)},${literal(receiptItemId)},'business_inventory',null,null,
      '2024-01-01T00:00:00Z','2024-02-01T00:00:00Z','principal-owner','principal-owner'),
    (${literal(`${receiptItemId}-project`)},${literal(accountId)},${literal(receiptItemId)},'project',${literal(receiptProject)},${literal(`${receiptItemId}-space`)},
      '2024-02-01T00:00:00Z',null,'principal-owner',null);`);
  // Metadata-only media fixture; this does not claim Storage byte availability.
  sql(`insert into public.item_image_objects(id,account_id,content_sha256,byte_count,media_type,storage_path)
    values(${literal(`${receiptItemId}-image`)},${literal(accountId)},repeat('a',64),123,'image/png',
      ${literal(`accounts/${accountId}/attachments/${receiptItemId}-image/`)}||repeat('a',64));
    insert into public.item_image_sets(id,account_id,item_id,revision,expected_count)
    values(${literal(receiptItemId)},${literal(accountId)},${literal(receiptItemId)},1,1);
    insert into public.item_image_references(id,account_id,item_id,attachment_id,set_revision,position,is_primary)
    values(${literal(`${receiptItemId}-image-ref`)},${literal(accountId)},${literal(receiptItemId)},${literal(`${receiptItemId}-image`)},1,0,true);`);
  sql(`select ledger_private.import_client_payment(${literal(`${receiptId}-linked-payment`)},${literal(accountId)},
    ${literal(receiptProject)},${literal(receiptClient)},123,'USD',${literal(accountId)},'linked-payment',decode('02','hex'));
    insert into public.spike_item_project_categories(id,account_id,project_id,item_id,category_id)
    values(${literal(`${receiptItemId}-project`)},${literal(accountId)},${literal(receiptProject)},${literal(receiptItemId)},${literal(a)});
    insert into ledger_private.item_client_payment_connections(id,account_id,project_id,client_id,item_id,placement_id,transaction_id,started_at,started_by_principal_id)
    values(${literal(`${receiptItemId}-payment-connection`)},${literal(accountId)},${literal(receiptProject)},${literal(receiptClient)},
      ${literal(receiptItemId)},${literal(`${receiptItemId}-project`)},${literal(`${receiptId}-linked-payment`)},'2024-02-02','principal-owner');`);
  const projectInput = { scopeKind: "project", projectId: receiptProject } as const;
  sql(`insert into ledger_private.item_project_prices(account_id,item_id,amount_minor_units,currency,updated_at,updated_by_principal_id)
    values(${literal(accountId)},${literal(receiptItemId)},9223372036854775807,'USD',now(),'principal-owner');`);
  const paymentOnlyItem = `${receiptItemId}-payment-only`;
  sql(`insert into public.spike_items(id,account_id,name,description,created_by_principal_id,source)
    values(${literal(paymentOnlyItem)},${literal(accountId)},'Renamed paid chair','Historical chair','principal-owner','Chair vendor');
    insert into public.spike_spaces(id,account_id,scope_kind,display_name,lifecycle)
    values(${literal(`${paymentOnlyItem}-space`)},${literal(accountId)},'business_inventory','Inventory room','active');
    insert into public.spike_item_placements(id,account_id,item_id,scope_kind,space_id,started_at,started_by_principal_id)
    values(${literal(`${paymentOnlyItem}-placement`)},${literal(accountId)},${literal(paymentOnlyItem)},'business_inventory',
      ${literal(`${paymentOnlyItem}-space`)},'2024-03-01','principal-owner');
    insert into public.item_image_sets(id,account_id,item_id,revision,expected_count)
    values(${literal(paymentOnlyItem)},${literal(accountId)},${literal(paymentOnlyItem)},1,0);`);
  // Retained history is independent of today's placement/category. A closed
  // interval and all three frozen source kinds must survive the same download.
  sql(`insert into ledger_private.item_client_payment_connections(id,account_id,project_id,client_id,item_id,placement_id,
      transaction_id,started_at,started_by_principal_id,ended_at,ended_by_principal_id)
    values(${literal(`${receiptItemId}-closed-connection`)},${literal(accountId)},${literal(receiptProject)},${literal(receiptClient)},
      ${literal(receiptItemId)},${literal(`${receiptItemId}-project`)},${literal(`${receiptId}-linked-payment`)},
      '2024-02-01','principal-owner','2024-02-02','principal-owner');
    insert into ledger_private.collected_invoices(id,account_id,project_id,client_id,purchase_id,invoice_revision,currency,total_minor_units)
    values(${literal(`${receiptId}-invoice`)},${literal(accountId)},${literal(receiptProject)},${literal(receiptClient)},
      ${literal(`${receiptId}-linked-payment`)},3,'USD',123);
    insert into ledger_private.collected_invoice_lines(id,account_id,invoice_id,line_position,currency,source_kind,source_id,
      item_id,source_revision,category_id,signed_amount_minor_units,description,source_snapshot) values
    (${literal(`${receiptId}-line-item`)},${literal(accountId)},${literal(`${receiptId}-invoice`)},0,'USD','item','frozen-occurrence',
      ${literal(paymentOnlyItem)},2,${literal(a)},100,'Frozen Item',${literal(JSON.stringify({ item: { itemId: paymentOnlyItem,
        occurrenceId: "frozen-occurrence", price: { basis: { projectPrice: {} }, amount: { minorUnits: 100, currency: "USD" } } } }))}::jsonb),
    (${literal(`${receiptId}-line-expense`)},${literal(accountId)},${literal(`${receiptId}-invoice`)},1,'USD','expense','frozen-expense',
      null,1,${literal(a)},20,'Frozen Expense','{"expense":{"expenseId":"frozen-expense"}}'),
    (${literal(`${receiptId}-line-fee`)},${literal(accountId)},${literal(`${receiptId}-invoice`)},2,'USD','fee_installment','frozen-fee',
      null,1,${literal(a)},3,'Frozen Fee','{"feeInstallment":{"installmentId":"frozen-fee"}}');
    update ledger_private.collected_invoices set sealed=true where account_id=${literal(accountId)} and id=${literal(`${receiptId}-invoice`)};`);
  const ownerList = await details.list(projectInput, owner);
  assert.equal(ownerList.coverage, "partial");
  assert.deepEqual(ownerList.transactions.map(row => row.transactionId), [`${receiptId}-linked-payment`, `${receiptId}-payment`, `${receiptId}-project`]);
  const payment = await details.read({ transactionId: `${receiptId}-payment` }, owner);
  assert.equal(payment.amountMinorUnits, "9007199254740993");
  assert.equal(payment.category, null);
  assert.deepEqual(ownerList.transactions[1], payment);
  assert.deepEqual(payment.currentItemCategories, [], "Standalone payment is not inferred to own Items");
  assert.deepEqual(payment.paymentContents?.connections, []);
  assert.equal(payment.paymentContents?.invoice, null);
  const paidContents = ownerList.transactions[0].paymentContents;
  assert.equal(paidContents?.connections.length, 2);
  assert.ok(paidContents?.connections.some(link => link.endedAt !== null));
  assert.deepEqual(paidContents?.invoice?.lines.map(line => line.source_kind), ["item", "expense", "fee_installment"]);
  assert.equal(paidContents?.invoice?.total_minor_units, "123");
  assert.equal(paidContents?.items?.length, 2);
  assert.deepEqual(paidContents?.items?.find(item => item.itemId === paymentOnlyItem), {
    itemId: paymentOnlyItem, name: "Renamed paid chair", sku: null, source: "Chair vendor", currentSource: null,
    currentSpaceName: "Inventory room", imageCount: "0",
  });
  assert.deepEqual(ownerList.transactions[0].currentItemCategories,
    [{ itemId: receiptItemId, placementId: `${receiptItemId}-project`, categoryId: a }]);
  assert.deepEqual(ownerList.transactions[2].currentItemCategories, [], "Returned receipt evidence is not current attachment");
  // Same immutable PDF referenced by vendor receipts and a client payment;
  // section metadata does not require another object/byte store.
  sql(`insert into public.item_image_objects(id,account_id,content_sha256,byte_count,media_type,storage_path)
    values(${literal(`${receiptId}-pdf`)},${literal(accountId)},repeat('b',64),9007199254740993,'application/pdf',
      ${literal(`accounts/${accountId}/attachments/${receiptId}-pdf/`)}||repeat('b',64));`);
  for (const transaction of [receiptId, `${receiptId}-project`, `${receiptId}-payment`]) {
    sql(`insert into public.transaction_attachment_sets(id,account_id,transaction_id,section,revision,expected_count)
      values(${literal(`${transaction}-receipts`)},${literal(accountId)},${literal(transaction)},'receipts',2,1),
        (${literal(`${transaction}-other`)},${literal(accountId)},${literal(transaction)},'other',1,0);
      insert into public.transaction_attachment_references(id,account_id,transaction_id,section,attachment_id,set_revision,position,is_primary,file_name)
      values(${literal(`${transaction}-pdf-ref`)},${literal(accountId)},${literal(transaction)},'receipts',${literal(`${receiptId}-pdf`)},2,0,true,'Vendor receipt.pdf'),
        (${literal(`${transaction}-old-ref`)},${literal(accountId)},${literal(transaction)},'receipts',${literal(`${receiptId}-pdf`)},1,0,true,'Old name.pdf');`);
  }
  const fullStream = receiptStream("10000000-0000-0000-0000-000000000001", "project", receiptProject);
  for (const transactionId of [receiptId, `${receiptId}-project`, `${receiptId}-payment`]) {
    const page = await details.attachments({transactionId,section:"receipts"},owner);
    assert.equal(page.isComplete,true);
    assert.equal(page.revision,"2");
    assert.deepEqual(page.attachments,[{id:`${transactionId}-pdf-ref`,position:0,isPrimary:true,kind:"pdf",fileName:"Vendor receipt.pdf"}]);
    assert.equal((await details.attachments({transactionId,section:"other"},owner)).expectedCount,0);
    await assert.rejects(details.attachments({transactionId,section:"receipts",revision:"1"},owner),
      {code:"transaction_attachment_revision_changed"});
  }
  console.log('PASS: real HTTP attachment pages preserve public metadata/exact revision, empty sections and 409 conflicts');
  for (const transactionId of [receiptId, `${receiptId}-project`, `${receiptId}-payment`]) {
    await assert.rejects(details.attachments({ transactionId, section: "receipts" }, member),
      { code: "transaction_not_available" });
    await assert.rejects(details.attachments({ transactionId, section: "receipts" },
      { ...owner, accountId: foreignAccountId }), { code: "transaction_not_available" });
  }
  assert.equal(fullStream.transaction_attachment_sets.length, 4);
  assert.equal(fullStream.transaction_attachment_references.length, 2);
  assert.ok(fullStream.transaction_attachment_references.every(row => row.set_revision === '2' && row.file_name === 'Vendor receipt.pdf'));
  assert.ok(fullStream.transaction_attachment_references.every(row => row.attachment_id === `${receiptId}-pdf` && row.byte_count === '9007199254740993'));
  assert.deepEqual(fullStream.spike_transactions.map(row => row.id).sort(), ownerList.transactions.map(row => row.transactionId));
  assert.equal(fullStream.spike_transactions.find(row => row.id === payment.transactionId)?.amount_minor_units, payment.amountMinorUnits);
  assert.equal(fullStream.item_client_payment_connections[0].transaction_id, `${receiptId}-linked-payment`);
  assert.equal(fullStream.spike_item_project_categories[0].category_id, a);
  assert.equal(fullStream.item_client_payment_connections.length, 2);
  assert.equal(fullStream.collected_invoices[0].purchase_id, `${receiptId}-linked-payment`);
  assert.equal(fullStream.collected_invoice_lines.length, 3);
  assert.equal(fullStream.spike_items.find(item => item.id === paymentOnlyItem)?.name, "Renamed paid chair");
  assert.equal(fullStream.spike_item_placements.find(row => row.item_id === paymentOnlyItem)?.scope_kind, "business_inventory");
  assert.equal(fullStream.spike_spaces.find(row => row.id === `${paymentOnlyItem}-space`)?.display_name, "Inventory room");
  assert.equal(fullStream.item_image_sets.find(row => row.item_id === paymentOnlyItem)?.expected_count, 0);
  for (const line of paidContents!.invoice!.lines) {
    const streamed = fullStream.collected_invoice_lines.find(row => row.id === line.id)!;
    for (const key of ["source_revision", "signed_amount_minor_units", "description", "source_snapshot_json"] as const) {
      assert.equal(streamed[key], line[key], `Frozen ${key} matches HTTP without rounding/reconstruction`);
    }
  }
  const limitedProjectStream = receiptStream("10000000-0000-0000-0000-000000000002", "project", receiptProject);
  assert.deepEqual(limitedProjectStream.transaction_attachment_sets, []);
  assert.deepEqual(limitedProjectStream.transaction_attachment_references, []);
  assert.equal(limitedProjectStream.item_image_objects, undefined, 'Object descriptors are scoped reference fields, not separate object buckets');
  assert.deepEqual(limitedProjectStream.item_client_payment_connections, []);
  assert.deepEqual(limitedProjectStream.collected_invoices, []);
  assert.deepEqual(limitedProjectStream.collected_invoice_lines, []);
  // Physical metadata has the existing Account-member permission, independent
  // of the payment relationship. The financial assertions above stay denied.
  assert.ok(limitedProjectStream.spike_items.some(row => row.id === paymentOnlyItem));
  assert.ok(limitedProjectStream.spike_spaces.some(row => row.id === `${paymentOnlyItem}-space`));
  assert.ok(limitedProjectStream.item_image_sets.some(row => row.item_id === paymentOnlyItem));
  assert.deepEqual(limitedProjectStream.spike_item_project_categories, []);
  for (const userId of ['10000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000003']) assertDirectoryStreamParity(userId);
  assert.equal(limitedProjectStream.spike_item_placements.length, 2, "Physical placement itself is ordinary visible metadata");
  assert.deepEqual((await details.list(projectInput, member)).transactions, [], "Neither hidden Fee nor unclassified payment leaks");
  await assert.rejects(details.read({ transactionId: payment.transactionId }, member), { code: "transaction_not_available" });
  const ownerStream = receiptStream("10000000-0000-0000-0000-000000000001");
  assert.equal(ownerStream.transaction_attachment_sets.length, 2);
  assert.equal(ownerStream.transaction_attachment_references.length, 1);
  assert.equal(ownerStream.transaction_attachment_references[0].byte_count, '9007199254740993');
  assert.deepEqual(ownerStream.spike_transactions.map(row => row.id), [receiptId]);
  assert.equal(ownerStream.transaction_receipt_items[0].membership_kind, "sold");
  const receiptPhysicalItem = ownerStream.spike_items.find(row => row.id === receiptItemId);
  assert.equal(receiptPhysicalItem?.description, "Receipt Item");
  assert.equal(receiptPhysicalItem?.sku, null);
  assert.equal(receiptPhysicalItem?.source, "Original vendor");
  assert.equal(receiptPhysicalItem?.current_source, "Display vendor");
  assert.equal(ownerStream.item_image_sets.find(row => row.item_id === receiptItemId)?.expected_count, 1);
  assert.equal(ownerStream.spike_spaces.find(row => row.id === `${receiptItemId}-space`)?.display_name, "Current room");
  assert.equal(ownerStream.spike_item_placements.find(row => row.item_id === receiptItemId)?.space_id, `${receiptItemId}-space`);
  assert.equal((await receipts.read({ transactionId: receiptId }, owner)).items[0].currentSpaceName, "Current room");
  assert.equal((await receipts.read({ transactionId: receiptId }, owner)).items[0].imageCount, "1");
  assert.equal((await receipts.read({ transactionId: receiptId }, owner)).items[0].source, "Original vendor");
  assert.equal((await receipts.read({ transactionId: receiptId }, owner)).items[0].currentSource, "Display vendor");
  assert.equal((await receipts.read({ transactionId: receiptId }, owner)).items[0].name, "Receipt Item");
  const hiddenStream = receiptStream("10000000-0000-0000-0000-000000000002");
  for (const table of ["spike_transactions", "transaction_receipt_items", "spike_budget_categories", "transaction_attachment_sets", "transaction_attachment_references"]) assert.deepEqual(hiddenStream[table], []);
  assert.ok(hiddenStream.spike_items.some(row => row.id === receiptItemId), "Hidden financial relationships must not hide independently authorized physical Items");
  for (const result of [receiptStream("10000000-0000-0000-0000-000000000003"),
    receiptStream("10000000-0000-0000-0000-000000000002", "business_inventory", null, foreignAccountId)]) {
    assert.ok(Object.values(result).every(rows => rows.length === 0));
  }
  assert.equal((await manageCategoriesTool(create(b, "Lighting"), member, applier)).phase, "applied");
  assert.deepEqual((await applier.read(member)).categories.map(row => row.id), [b]);
  assert.equal((await applier.read(owner)).categories.length, 2);
  assert.equal((await manageCategoriesTool(input({ action: "edit", categoryId: b, expectedRevision: "1",
    name: "Lighting", kind: "itemized", excludesFromOverallBudget: false }), member, applier)).phase, "applied");
  for (const [action, expectedRevision] of [["archive", "2"], ["restore", "3"]] as const) {
    assert.equal((await manageCategoriesTool(input({ action, categoryId: b, expectedRevision }), member, applier)).phase, "applied");
    assert.equal((await applier.read(member)).categories[0].lifecycle, action === "archive" ? "archived" : "active");
  }
  assert.equal((await manageCategoriesTool(input({ action: "edit", categoryId: a, expectedRevision: "1",
    name: "Fee", kind: "general", excludesFromOverallBudget: false }), owner, applier)).phase, "applied");
  const visible = await applier.read(member);
  assert.deepEqual(visible.categories.map(row => row.id), [a, b], "Current General type is automatically visible");
  const visibleReceipt = await receipts.read({ transactionId: receiptId }, member);
  const visibleDetail = await details.read({ transactionId: receiptId }, member);
  assert.deepEqual((await details.attachments({ transactionId: receiptId, section: "receipts" }, member)).attachments,
    (await details.attachments({ transactionId: receiptId, section: "receipts" }, owner)).attachments,
    "General attachments become visible under normal current-category access");
  const { audit: receiptAudit, ...receiptEvidence } = visibleReceipt;
  assert.deepEqual(visibleDetail.receipt, receiptEvidence, "Browser/detail and audit share exact receipt evidence");
  assert.equal(receiptAudit.reconstructedTotalMinorUnits, "100");
  assert.equal(visibleDetail.source, "Café vendor");
  assert.equal(visibleDetail.transactionDate, "2024-02-29");
  assert.equal(visibleDetail.createdAtMilliseconds, "1709251200123");
  assert.equal(visibleDetail.notes, "Preserved notes");
  assert.equal(visibleDetail.paymentMethod, "Company card");
  assert.equal(visibleDetail.hasEmailReceipt, false);
  assert.equal(visibleDetail.detailsRevision, "2");
  assert.equal(visibleDetail.legacySubtotalMinorUnits, "9007199254740993");
  assert.equal(visibleDetail.legacyTaxRatePct, "8.12345678901234567890");
  assert.equal(visibleReceipt.category.kind, "general");
  assert.equal(visibleReceipt.audit.reconstructedTotalMinorUnits, "100");
  assert.equal(visibleReceipt.items[0].membershipKind, "sold");
  const memberStream = receiptStream("10000000-0000-0000-0000-000000000002");
  assert.equal(memberStream.transaction_attachment_sets.length, 2);
  assert.equal(memberStream.transaction_attachment_references[0].set_revision, '2');
  assert.equal(memberStream.transaction_attachment_references[0].byte_count, '9007199254740993');
  assert.deepEqual(memberStream.spike_transactions.map(row => row.id), [receiptId]);
  const streamedDetail = memberStream.spike_transactions[0];
  assert.equal(streamedDetail.source, visibleDetail.source);
  assert.equal(streamedDetail.transaction_date, visibleDetail.transactionDate);
  assert.equal(streamedDetail.created_at_ms, visibleDetail.createdAtMilliseconds);
  assert.equal(streamedDetail.notes, visibleDetail.notes);
  assert.equal(streamedDetail.payment_method, visibleDetail.paymentMethod);
  assert.equal(streamedDetail.has_email_receipt, visibleDetail.hasEmailReceipt);
  assert.equal(streamedDetail.details_revision, visibleDetail.detailsRevision);
  assert.equal(streamedDetail.legacy_subtotal_minor_units, visibleDetail.legacySubtotalMinorUnits);
  assert.equal(streamedDetail.legacy_tax_rate_pct, visibleDetail.legacyTaxRatePct);
  assert.equal(memberStream.spike_budget_categories.find(row => row.id === a)?.kind, "general");
  assert.equal(memberStream.transaction_receipt_items[0].amount_minor_units, "99");
  const projectStream = receiptStream("10000000-0000-0000-0000-000000000002", "project", receiptProject);
  assert.deepEqual(projectStream.spike_transactions.map(row => row.id), [`${receiptId}-project`]);
  assert.equal(projectStream.transaction_receipt_items[0].membership_kind, "returned");
  assert.deepEqual((await details.list(projectInput, member)).transactions.map(row => row.transactionId), [`${receiptId}-project`]);
  assert.deepEqual((await details.list({ scopeKind: "business_inventory" }, member)).transactions, [visibleDetail]);
  const wrongProject = receiptStream("10000000-0000-0000-0000-000000000002", "project", `${receiptProject}-other`);
  assert.deepEqual(wrongProject.spike_transactions, []);
  assert.deepEqual(wrongProject.transaction_receipt_items, []);
  const reorder = input({ action: "reorder", order: [...visible.categories].reverse().map(row => ({ categoryId: row.id, expectedRevision: row.revision })) });
  const first = await manageCategoriesTool(reorder, member, applier);
  assert.equal(first.phase, "applied");
  const after = await applier.read(member);
  assert.deepEqual(after.categories.map(row => row.id), [b, a]);
  assert.deepEqual(await manageCategoriesTool(reorder, member, applier), first);
  assert.deepEqual(await applier.read(member), after, "Exact retry must not bump revisions");
  await assert.rejects(manageCategoriesTool({ ...reorder, payload: { action: "archive", categoryId: b,
    expectedRevision: after.categories[0].revision } }, member, applier), { code: "category_request_rejected" });

  const races = await Promise.all([create(`${accountId}-c`, "Race"), create(`${accountId}-d`, "RACE")]
    .map(request => manageCategoriesTool(request, member, applier)));
  assert.equal(races.filter(result => result.phase === "applied").length, 1);
  assert.equal(races.filter(result => result.errorCode === "category_name_unavailable").length, 1);
  const current = (await applier.read(member)).categories.find(row => row.id === b)!;
  const edits = await Promise.all(["Left", "Right"].map(name => manageCategoriesTool(input({
    action: "edit", categoryId: b, expectedRevision: current.revision, name, kind: "general",
    excludesFromOverallBudget: false }), member, applier)));
  assert.equal(edits.filter(result => result.phase === "applied").length, 1);
  assert.equal(edits.filter(result => result.errorCode === "category_revision_conflict").length, 1);
  await assert.rejects(applier.read({ ...member, accountId: `foreign-${randomUUID()}` }), { code: "category_read_rejected" });
  sql(`update public.spike_account_memberships set state='removed'
    where account_id=${literal(accountId)} and principal_id='principal-restricted';`);
  await assert.rejects(applier.read(member), { code: "category_read_rejected" });
  await assert.rejects(details.list(projectInput, member), { code: "transaction_scope_not_available" });
  await assert.rejects(receipts.read({ transactionId: receiptId }, member), { code: "transaction_not_available" });
  assert.ok(Object.values(receiptStream("10000000-0000-0000-0000-000000000002")).every(rows => rows.length === 0));
  await assert.rejects(details.attachments({ transactionId: receiptId, section: "receipts" }, member),
    { code: "transaction_not_available" });
  console.log("PASS: real HTTP attachment access denies hidden/foreign Transactions, restores General visibility and rejects the same token after removal");
  assertDirectoryStreamParity('10000000-0000-0000-0000-000000000002');
  console.log('PASS: default category/allocation stream equals RLS for full, restricted, foreign and removed users');
  console.log("PASS: checked-in receipt stream SQL scopes Project/Inventory, historical Items, current category, cross-Account denial and removal");
  console.log("PASS: real HTTP Transaction receipt/history read follows category visibility and membership removal");
  await assert.rejects(manageCategoriesTool(reorder, member, applier), { code: "category_request_rejected" });
  console.log("PASS: local HTTP category lookup, all five actions, current-type visibility, exact replay, collision, concurrent name/revision writes and revocation");
  if (process.argv.includes('--routing-concurrency')) {
    const transactionId = `${receiptId}-project`;
    const run = (name: string, statement: string) => promisify(execFile)('docker', ['exec',
      'supabase_db_ledger_target_supabase_local','psql','-X','-q','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1',
      '-c',`begin; set local application_name=${literal(name)}; set local statement_timeout='5s'; ${statement} commit;`],
      {timeout: 8_000}).then(()=>null, error=>error as Error);
    const waitFor = async (name: string, event: string) => {
      for (let attempt=0; attempt<20; attempt++) {
        const waiting = sql(`select count(*) from pg_stat_activity where application_name=${literal(name)}
          and (wait_event=${literal(event)} or wait_event_type=${literal(event)});`, true).trim();
        if (waiting === '1') return;
        await new Promise(resolve=>setTimeout(resolve,25));
      }
      assert.fail(`Expected local concurrency fixture to reach ${event}`);
    };
    for (const parentFirst of [true,false]) {
      const id = `${accountId}-routing-${Number(parentFirst)}`;
      sql(`insert into public.spike_items(id,account_id,created_by_principal_id) values(${literal(id)},${literal(accountId)},'principal-owner');`);
      const parent = `update public.spike_transactions set category_id=${literal(b)} where id=${literal(transactionId)};`;
      const child = `insert into public.transaction_receipt_items(id,account_id,transaction_id,item_id,currency,amount_minor_units,membership_kind)
        values(${literal(id)},${literal(accountId)},${literal(transactionId)},${literal(id)},'USD',17,'linked');`;
      const firstName = `routing-first-${randomUUID()}`, secondName = `routing-second-${randomUUID()}`;
      const jobs = [run(firstName, `${parentFirst ? parent : child} select pg_sleep(2);`)];
      try {
        await waitFor(firstName,'PgSleep');
        jobs.push(run(secondName,parentFirst ? child : parent));
        await waitFor(secondName,'Lock'); // Prove overlap, not merely two serial successful writes.
      } finally {
        for (const result of await Promise.all(jobs)) assert.equal(result,null);
      }
      assert.equal(sql(`select count(*) from public.transaction_receipt_items where id=${literal(id)}
        and sync_category_id=${literal(b)} and sync_project_id=${literal(receiptProject)}
        and sync_scope_kind='project' and amount_minor_units=17;`,true).trim(),'1');
      sql(`delete from public.transaction_receipt_items where id=${literal(id)};
        delete from public.spike_items where id=${literal(id)};
        update public.spike_transactions set category_id=${literal(a)} where id=${literal(transactionId)};`);
    }
    console.log('PASS: observed parent-first and child-first lock contention preserves exact Transaction routing and amounts');
  }
  if (process.argv.includes('--counter-concurrency')) {
    const space = `${receiptItemId}-space`;
    const count = () => Number(sql(`select 'SPACE_COUNT:'||sync_current_item_count from public.spike_spaces where id=${literal(space)};`)
      .match(/SPACE_COUNT:(\d+)/)![1]);
    const before = count();
    const ids = [0,1].map(index=>`${accountId}-counter-${index}`);
    sql(`insert into public.spike_items(id,account_id,created_by_principal_id) values
      ${ids.map(id=>`(${literal(id)},${literal(accountId)},'principal-owner')`).join(',')};`);
    const concurrently = async (statement: (id: string)=>string) => Promise.all(ids.map(id=>
      promisify(execFile)('docker', ['exec', 'supabase_db_ledger_target_supabase_local', 'psql', '-X', '-q',
        '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-c',
        `begin; set local statement_timeout='5s'; ${statement(id)} select pg_sleep(0.1); commit;`], {timeout: 8_000})));
    await concurrently(id=>`insert into public.spike_item_placements(id,account_id,item_id,scope_kind,project_id,space_id,started_at,started_by_principal_id)
      values(${literal(id)},${literal(accountId)},${literal(id)},'project',${literal(receiptProject)},${literal(space)},'2024-04-01','principal-owner');`);
    assert.equal(count(), before+2, 'Concurrent placements must not lose a Space count increment');
    await concurrently(id=>`update public.spike_item_placements set ended_at='2024-05-01',ended_by_principal_id='principal-owner' where id=${literal(id)};`);
    assert.equal(count(), before, 'Concurrent closures must each remove their contribution');
    console.log('PASS: concurrent local connections preserve Space sync counts on insertion and closure');
  }
  if (process.argv.includes("--diagnose-parameters") || process.argv.includes("--native-replication")) {
    const serviceLabels = JSON.parse(execFileSync('docker', ['inspect', '--format', '{{json .Config.Labels}}', 'ledger_powersync_local'], {encoding: 'utf8'}));
    assert.equal(realpathSync(serviceLabels['ledger.local-powersync']), realpathSync(root));
    const bundledParser = execFileSync('docker', ['exec', 'ledger_powersync_local', 'node', '-p',
      'require("/app/packages/sync-rules/package.json").version'], {encoding: 'utf8'}).trim();
    const localParser = JSON.parse(readFileSync(new URL('../../node_modules/@powersync/service-sync-rules/package.json', import.meta.url), 'utf8')).version;
    assert.equal(localParser, bundledParser, 'Parser checks must match the pinned running service');
  }
  if (process.argv.includes("--diagnose-parameters")) {
    const scale = Number(process.argv.find(arg=>arg.startsWith('--parameter-scale='))?.split('=')[1] ?? '0');
    assert.ok(Number.isInteger(scale) && scale >= 0 && scale <= 700, 'Bound the synthetic load fixture');
    const projectCount = Number(process.argv.find(arg=>arg.startsWith('--parameter-projects='))?.split('=')[1] ?? '1');
    assert.ok(Number.isInteger(projectCount) && projectCount >= 1 && projectCount <= 10);
    const transactionsPerProject = Number(process.argv.find(arg=>arg.startsWith('--parameter-transactions='))?.split('=')[1] ?? '1');
    assert.ok(Number.isInteger(transactionsPerProject) && transactionsPerProject >= 1 && transactionsPerProject <= 100);
    const attachmentsPerTransaction = Number(process.argv.find(arg=>arg.startsWith('--parameter-attachments='))?.split('=')[1] ?? '0');
    assert.ok(Number.isInteger(attachmentsPerTransaction) && attachmentsPerTransaction >= 0 && attachmentsPerTransaction <= 20);
    const invoicesPerProject = Number(process.argv.find(arg=>arg.startsWith('--parameter-invoices='))?.split('=')[1] ?? '0');
    assert.ok(Number.isInteger(invoicesPerProject) && invoicesPerProject >= 0 && invoicesPerProject <= 100);
    let scaledAttachmentCount = 0;
    const projectIds = Array.from({length: projectCount}, (_,index)=>index === 0 ? receiptProject : `${receiptProject}-${index}`);
    for (const [index, projectId] of projectIds.entries()) {
      const itemPrefix = `${accountId}-scale-${index}-`;
      const placementPrefix = `${accountId}-scale-placement-${index}-`;
      const transactionId = index === 0 ? `${receiptId}-project` : `${receiptId}-project-${index}`;
      const spaceId = index === 0 ? `${receiptItemId}-space` : `${receiptItemId}-space-${index}`;
      if (index > 0) sql(`insert into public.spike_projects(id,account_id,client_id,display_name,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
        values(${literal(projectId)},${literal(accountId)},${literal(receiptClient)},'Scale Project',now(),now(),1,1,'principal-owner');
        insert into public.spike_spaces(id,account_id,scope_kind,project_id,display_name,lifecycle)
        values(${literal(spaceId)},${literal(accountId)},'project',${literal(projectId)},'Scale room','active');
        insert into public.spike_transactions(id,account_id,project_id,client_id,scope_kind,origin,type,amount_minor_units,currency,category_id)
        values(${literal(transactionId)},${literal(accountId)},${literal(projectId)},${literal(receiptClient)},
          'project','vendor_payment','purchase',99,'USD',${literal(a)});`);
      if (transactionsPerProject > 1) sql(`insert into public.spike_transactions(id,account_id,project_id,client_id,scope_kind,origin,type,amount_minor_units,currency,category_id)
        select ${literal(`${transactionId}-distinct-`)}||n,${literal(accountId)},${literal(projectId)},${literal(receiptClient)},
          'project','vendor_payment','purchase',99,'USD',${literal(a)} from generate_series(1,${transactionsPerProject-1}) n;`);
      if (invoicesPerProject > 0) {
        const prefix = `${accountId}-scale-invoice-${index}-`;
        sql(`select ledger_private.import_client_payment(${literal(prefix)}||n||'-payment',${literal(accountId)},
            ${literal(projectId)},${literal(receiptClient)},7,'USD',${literal(accountId)},${literal(prefix)}||n,decode('04','hex'))
          from generate_series(1,${invoicesPerProject}) n;
          insert into ledger_private.collected_invoices(id,account_id,project_id,client_id,purchase_id,invoice_revision,currency,total_minor_units)
          select ${literal(prefix)}||n,${literal(accountId)},${literal(projectId)},${literal(receiptClient)},
            ${literal(prefix)}||n||'-payment',1,'USD',7 from generate_series(1,${invoicesPerProject}) n;
          insert into ledger_private.collected_invoice_lines(id,account_id,invoice_id,line_position,currency,source_kind,source_id,
            item_id,source_revision,category_id,signed_amount_minor_units,description,source_snapshot)
          select ${literal(prefix)}||n||'-line',${literal(accountId)},${literal(prefix)}||n,0,'USD','expense',${literal(prefix)}||n,
            null,1,${literal(a)},7,'Frozen synthetic Expense',jsonb_build_object('expense',jsonb_build_object('expenseId',${literal(prefix)}||n))
          from generate_series(1,${invoicesPerProject}) n;
          update ledger_private.collected_invoices set sealed=true where account_id=${literal(accountId)} and id like ${literal(`${prefix}%`)};`);
      }
      if (attachmentsPerTransaction > 0) {
        const mediaPrefix = `${accountId}-scale-media-${index}-`;
        // Preserve the original fixture's published section. New synthetic
        // Transactions get complete marker/reference/object metadata, not bytes.
        sql(`insert into public.transaction_attachment_sets(id,account_id,transaction_id,section,revision,expected_count)
          select ${literal(mediaPrefix)}||n,${literal(accountId)},
            case when n=0 then ${literal(transactionId)} else ${literal(`${transactionId}-distinct-`)}||n end,
            'receipts',1,${attachmentsPerTransaction} from generate_series(0,${transactionsPerProject-1}) n
          on conflict(account_id,transaction_id,section) do nothing;
          insert into public.item_image_objects(id,account_id,content_sha256,byte_count,media_type,storage_path)
          select s.id||'-'||n,s.account_id,repeat('e',64),99,'image/png',
            'accounts/'||s.account_id||'/attachments/'||s.id||'-'||n||'/'||repeat('e',64)
          from public.transaction_attachment_sets s cross join generate_series(1,${attachmentsPerTransaction}) n
          where s.account_id=${literal(accountId)} and s.id like ${literal(`${mediaPrefix}%`)};
          insert into public.transaction_attachment_references(id,account_id,transaction_id,section,attachment_id,set_revision,position,is_primary,file_name)
          select s.id||'-'||n,s.account_id,s.transaction_id,s.section,s.id||'-'||n,1,n-1,n=1,'Synthetic.png'
          from public.transaction_attachment_sets s cross join generate_series(1,${attachmentsPerTransaction}) n
          where s.account_id=${literal(accountId)} and s.id like ${literal(`${mediaPrefix}%`)};`);
        scaledAttachmentCount += (transactionsPerProject - (index === 0 ? 1 : 0)) * attachmentsPerTransaction;
      }
      if (scale === 0) continue;
      sql(`insert into public.spike_items(id,account_id,description,created_by_principal_id)
        select ${literal(itemPrefix)}||n,${literal(accountId)},'Load-test Item','principal-owner' from generate_series(1,${scale}) n;
        insert into public.spike_item_placements(id,account_id,item_id,scope_kind,project_id,space_id,started_at,started_by_principal_id)
        select ${literal(placementPrefix)}||n,${literal(accountId)},${literal(itemPrefix)}||n,
          'project',${literal(projectId)},${literal(spaceId)},'2024-03-01','principal-owner' from generate_series(1,${scale}) n;
        insert into public.transaction_receipt_items(id,account_id,transaction_id,item_id,currency,amount_minor_units,membership_kind)
        select ${literal(`${accountId}-scale-link-${index}-`)}||n,${literal(accountId)},
          case when (n-1)%${transactionsPerProject}=0 then ${literal(transactionId)}
            else ${literal(`${transactionId}-distinct-`)}||((n-1)%${transactionsPerProject}) end,
          ${literal(itemPrefix)}||n,'USD',null,'linked' from generate_series(1,${scale}) n;
        insert into public.item_image_sets(id,account_id,item_id,revision,expected_count)
        select ${literal(itemPrefix)}||n,${literal(accountId)},${literal(itemPrefix)}||n,1,0 from generate_series(1,${scale}) n;
        insert into public.spike_item_project_categories(id,account_id,project_id,item_id,category_id)
        select ${literal(placementPrefix)}||n,${literal(accountId)},${literal(projectId)},
          ${literal(itemPrefix)}||n,${literal(a)} from generate_series(1,${scale}) n;`);
    }
    if (invoicesPerProject > 0) {
      const invoiceQueries = streamQueries.filter(query=>/FROM ledger_private\.collected_invoice(?:s|_lines)\b/.test(query));
      for (const projectId of projectIds) {
        const selected = streamRows(invoiceQueries, '10000000-0000-0000-0000-000000000001',
          {account_id: accountId,scope_kind: 'project',project_id: projectId});
        for (const table of ['collected_invoices','collected_invoice_lines']) {
          const rows = selected[table].filter(row=>String(row.id).startsWith(`${accountId}-scale-invoice-`));
          assert.equal(rows.length,invoicesPerProject,'Every scoped frozen Invoice and line must survive');
          assert.ok(rows.every(row=>table === 'collected_invoices' ? row.total_minor_units === '7' : row.signed_amount_minor_units === '7'));
        }
      }
      console.log(`PASS: ${invoicesPerProject * projectCount} sealed synthetic Invoices retain exact scoped headers/lines/amounts`);
    }
    if (scaledAttachmentCount > 0) {
      const attachmentQueries = streamQueries.filter(query=>query.includes('FROM transaction_attachment_references'));
      const selected = projectIds.flatMap(projectId=>streamRows(attachmentQueries, '10000000-0000-0000-0000-000000000001',
        {account_id: accountId,scope_kind: 'project',project_id: projectId})
        .transaction_attachment_references.filter(row=>String(row.id).startsWith(`${accountId}-scale-media-`)));
      assert.equal(selected.length, scaledAttachmentCount, 'Every scoped attachment descriptor must survive routing optimization');
      assert.ok(selected.every(row=>row.content_sha256 === 'e'.repeat(64) && row.byte_count === '99' && row.media_type === 'image/png'));
      console.log(`PASS: ${scaledAttachmentCount} synthetic current attachment descriptors retain exact scope and immutable object metadata`);
    }
    if (scale > 0) for (const projectId of projectIds) {
      const scaledRows = receiptStream('10000000-0000-0000-0000-000000000001', 'project', projectId, accountId, true);
      for (const table of ['spike_items', 'item_image_sets', 'spike_item_placements', 'spike_item_project_categories', 'transaction_receipt_items']) {
        const expected = ['spike_item_project_categories', 'transaction_receipt_items'].includes(table) ? scale : scale * projectCount;
        assert.equal(scaledRows[table].filter(row=>String(row.id).startsWith(`${accountId}-scale-`)).length, expected,
          `${table}: reducing parameter counts must preserve every synthetic Item's evidence`);
      }
    }
    const {SqlSyncRules} = await import('@powersync/service-sync-rules');
    const yaml = readFileSync(new URL('../../powersync/sync-streams.yaml', import.meta.url), 'utf8');
    const config = SqlSyncRules.fromYaml(yaml, {defaultSchema: 'public', throwOnError: true}).config;
    const facts: unknown[] = [];
    for (const table of config.getSourceTables()) {
      assert.ok(['public', 'ledger_private'].includes(table.schema) && /^[a-z_]+$/.test(table.name));
      // This owned, isolated local stack contains synthetic data only. Include
      // all of it: default-stream parameter indexes can see other fixture
      // Accounts before authorization. Restricting this to four names understated
      // the real service budget. Never use this harness against a hosted stack.
      const output = sql(`select 'PARAMETER_FACT:' || row_to_json(row)::text from ${table.schema}.${table.name} row;`, true);
      for (const line of output.split('\n').map(row=>row.trim()).filter(row=>row.startsWith('PARAMETER_FACT:'))) {
        facts.push({table: {connectionTag: table.connectionTag, schema: table.schema, name: table.name}, row: JSON.parse(line.slice(15))});
      }
    }
    const evaluator = readFileSync(new URL('../../scripts/evaluate-sync-parameter-budget.mjs', import.meta.url), 'utf8');
    const evaluated = execFileSync('docker', ['exec', '-i', 'ledger_powersync_local', 'node', '--input-type=module', '-e', evaluator], {
      input: JSON.stringify({yaml, facts, projectIds, userId: '10000000-0000-0000-0000-000000000001',
        parameters: {account_id: accountId, scope_kind: 'project', project_id: receiptProject}}), encoding: 'utf8', timeout: 15_000
    });
    console.log('PARAMETER_BUDGET:' + evaluated.trim());
    if (process.argv.includes('--check-parameter-budget')) {
      const measurements = JSON.parse(evaluated) as {index: number | string; rows: number; buckets: number; error?: string}[];
      for (const measurement of measurements) assert.equal(measurement.error, undefined);
      const combined = measurements.find(row=>row.index === 'combined');
      assert.ok(combined && combined.rows <= 1000 && combined.buckets <= 1000,
        'Combined default + Project + Inventory subscriptions must fit both pinned service limits');
      console.log(`PASS: ${scale * projectCount} additional Items across ${projectCount} Projects (${transactionsPerProject} vendor Transactions each) retain metadata/category/receipt coverage within the service parameter and bucket limits`);
    }
    if (process.argv.includes('--service-parameter-probe')) {
      assert.ok(scale > 0, 'The live load probe requires a nonempty fixture');
      const installedYaml = execFileSync('docker', ['exec', 'ledger_powersync_local', 'cat', '/config/sync-streams.yaml'], {encoding: 'utf8'});
      assert.equal(installedYaml, yaml, 'Reload the owned service with these exact queries before the live probe');
      const controller = new AbortController();
      // The first local checkpoint after the schema/config reload took 60s.
      // Bound this large initial download separately from fast native unit tests.
      const deadline = setTimeout(()=>controller.abort(), 90_000);
      const received = new Map(['spike_items','item_image_sets','spike_item_placements',
        'spike_item_project_categories','transaction_receipt_items'].map(table=>[table,new Set<string>()]));
      if (scaledAttachmentCount > 0) received.set('transaction_attachment_references', new Set());
      if (invoicesPerProject > 0) for (const table of ['collected_invoices','collected_invoice_lines']) received.set(table,new Set());
      const expectedCount = (table: string) => table === 'transaction_attachment_references' ? scaledAttachmentCount
        : table.startsWith('collected_invoice') ? invoicesPerProject * projectCount : scale * projectCount;
      let complete = false;
      const messageKinds = new Map<string, number>();
      const started = Date.now();
      try {
        // The pinned service's StreamingSyncRequest contract. This observes an
        // actual completed download; it is not an alternative production SDK.
        const response = await fetch('http://127.0.0.1:5590/sync/stream', {
          method: 'POST', signal: controller.signal,
          headers: {Authorization: `Bearer ${owner.accessToken}`, 'Content-Type': 'application/json', Accept: 'application/x-ndjson'},
          body: JSON.stringify({buckets: [], raw_data: true, client_id: `ledger-scale-${randomUUID()}`,
            streams: {include_defaults: true, subscriptions: [
              ...projectIds.map(project_id=>({stream: 'transaction_receipts', override_priority: null,
                parameters: {account_id: accountId, scope_kind: 'project', project_id}})),
              {stream: 'transaction_receipts', override_priority: null,
                parameters: {account_id: accountId, scope_kind: 'business_inventory', project_id: null}},
              {stream: 'spike_projects', override_priority: null, parameters: null}]}})
        });
        assert.equal(response.status, 200, `Live parameter probe HTTP ${response.status}`);
        assert.ok(response.body);
        const reader = response.body.pipeThrough(new TextDecoderStream()).getReader();
        let pending = '';
        try {
          while (!complete) {
            const chunk = await reader.read();
            if (chunk.done) break;
            pending += chunk.value;
            const lines = pending.split('\n'); pending = lines.pop()!;
            for (const line of lines) {
              if (!line.trim()) continue;
              const message = JSON.parse(line);
              for (const kind of Object.keys(message)) messageKinds.set(kind, (messageKinds.get(kind) ?? 0) + 1);
              assert.ok(!message.error, 'Actual service rejected the load subscription');
              for (const stream of message.checkpoint?.streams ?? []) assert.deepEqual(stream.errors, []);
              for (const row of message.data?.data ?? []) {
                if (row.op === 'PUT' && String(row.object_id).startsWith(`${accountId}-scale-`)) {
                  received.get(row.object_type)?.add(row.object_id);
                }
              }
              if (message.checkpoint_complete && [...received].every(([table,ids])=>ids.size === expectedCount(table))) complete = true;
            }
          }
        } finally { await reader.cancel().catch(()=>{}); }
        assert.ok(complete, 'Service must complete all scoped Item/category/receipt rows, not just accept the connection');
        console.log(`PASS: actual service completed ${scale * projectCount} Items and all five evidence tables plus ${scaledAttachmentCount} attachment descriptors and ${invoicesPerProject * projectCount} frozen Invoices/lines across ${projectCount} Projects in ${Date.now()-started}ms`);
      } catch (error) {
        console.log('LIVE_SCALE_DIAGNOSTIC:' + JSON.stringify({elapsedMs: Date.now()-started,
          messages: Object.fromEntries(messageKinds), rows: Object.fromEntries([...received].map(([table,ids])=>[table,ids.size]))}));
        throw error;
      } finally { clearTimeout(deadline); controller.abort(); }
    }
  }
  const liveReplication = process.argv.includes("--native-replication");
  if (process.argv.includes("--native-sdk") || process.argv.includes("--native-auth-sdk") || liveReplication) {
    const authEnvironment: Record<string, string> = {};
    if (liveReplication) {
      const health = await fetch("http://127.0.0.1:5590/probes/readiness", { signal: AbortSignal.timeout(2_000) });
      assert.equal(health.status, 200, "Start Ledger's isolated local PowerSync service first");
      authEnvironment.LEDGER_CATEGORY_SYNC_URL = "http://127.0.0.1:5590";
    }
    if (process.argv.includes("--native-auth-sdk") || liveReplication) {
      assert.equal(typeof status.SERVICE_ROLE_KEY, "string");
      const email = `${accountId}@example.invalid`;
      const password = randomUUID() + randomUUID();
      // Only this already-validated local stack receives privileged credentials.
      // Never pass them to the native app/test process.
      const response = await fetch(new URL("/auth/v1/admin/users", rest.origin), {
        method: "POST", headers: { apikey: status.SERVICE_ROLE_KEY,
          Authorization: `Bearer ${status.SERVICE_ROLE_KEY}`, "Content-Type": "application/json" },
        body: JSON.stringify({ email, password, email_confirm: true }),
      });
      assert.ok(response.ok, `Local auth fixture creation failed (${response.status})`);
      const user = await response.json();
      assert.match(user.id, /^[0-9a-f-]{36}$/i);
      authUserId = user.id;
      sql(`insert into public.spike_principals(id,auth_user_id) values(${literal(authPrincipal)},${literal(user.id)});
        insert into public.spike_account_memberships(account_id,principal_id,role,state,financial_access,
          can_manage_clients,can_manage_projects,can_manage_project_budgets)
        values(${literal(accountId)},${literal(authPrincipal)},'employee','active','full',true,true,true);`);
      Object.assign(authEnvironment, { LEDGER_CATEGORY_AUTH_EMAIL: email, LEDGER_CATEGORY_AUTH_PASSWORD: password,
        LEDGER_CATEGORY_AUTH_USER: user.id, LEDGER_CATEGORY_AUTH_PRINCIPAL: authPrincipal });
    }
    // A private loopback callback lets the native scenario request removal of
    // ONLY its synthetic membership; no SQL or privileged key reaches Swift.
    const revokePath = `/revoke-${randomUUID()}`;
    const control = createServer((request, response) => {
      if (liveReplication && request.method === 'POST'
        && [revokePath+'?review=ordinary',revokePath+'?review=restricted'].includes(request.url ?? '')) {
        try {
          const kind = request.url!.endsWith('ordinary') ? 'general' : 'fee';
          sql(`update public.spike_account_memberships set financial_access='none'
            where account_id=${literal(accountId)} and principal_id=${literal(authPrincipal)};
            update public.spike_budget_categories set kind=${literal(kind)},revision=revision+1,updated_at_ms=updated_at_ms+1
            where account_id=${literal(accountId)} and id=${literal(a)};`);
          response.writeHead(204).end();
        } catch { response.writeHead(500).end(); }
        return;
      }
      if (!liveReplication || request.method !== "POST" || request.url !== revokePath) {
        response.writeHead(404).end(); return;
      }
      try {
        sql(`update public.spike_account_memberships set state='removed'
          where account_id=${literal(accountId)} and principal_id=${literal(authPrincipal)};`);
        response.writeHead(204).end();
      } catch { response.writeHead(500).end(); }
    });
    if (liveReplication) {
      await new Promise<void>(resolve => control.listen(0, "127.0.0.1", resolve));
      const address = control.address();
      assert.ok(address && typeof address !== "string");
      authEnvironment.LEDGER_CATEGORY_REVOKE_URL = `http://127.0.0.1:${address.port}${revokePath}`;
      authEnvironment.LEDGER_CATEGORY_FOREIGN_ACCOUNT = foreignAccountId;
    }
    // Tokens stay in the child environment, never command arguments or output.
    let native: { status: number; stdout: string; stderr: string };
    try {
      const result = await promisify(execFile)("swift", ["test", "--package-path", "LedgeriOS", "--no-parallel",
        "--filter", liveReplication
          ? "AccountWorkspacePendingWorkRuntimeTests/sdkCategoryLiveReplication"
          : "AccountWorkspacePendingWorkRuntimeTests/sdkCategoryLocalServer"], {
        cwd: root, encoding: "utf8", timeout: 120_000, maxBuffer: 16 * 1024 * 1024,
        env: { ...process.env, LEDGER_CATEGORY_LOCAL_ACCOUNT: accountId,
          LEDGER_CATEGORY_LOCAL_URL: rest.origin, LEDGER_CATEGORY_LOCAL_KEY: status.PUBLISHABLE_KEY,
          LEDGER_CATEGORY_LOCAL_TOKEN: owner.accessToken, LEDGER_CATEGORY_LOCAL_RECEIPT: receiptId, ...authEnvironment },
      });
      native = { status: 0, ...result };
    } catch (failure) {
      const result = failure as Error & { stdout?: string; stderr?: string; code?: string | number; signal?: string; killed?: boolean };
      native = { status: 1, stdout: result.stdout ?? "",
        stderr: `${result.stderr ?? result.message}\nNative process termination: code=${result.code ?? "unknown"} signal=${result.signal ?? "none"} killed=${result.killed ?? false}` };
    } finally {
      if (liveReplication) await new Promise<void>((resolve, reject) => control.close(error => error ? reject(error) : resolve()));
    }
    const output = native.stdout + native.stderr;
    if (native.status !== 0) console.error(sql(`select command_type,phase,error_code
      from public.spike_operation_results where account_id=${literal(accountId)} and phase='rejected';`));
    assert.equal(native.status, 0, `Native test output:\n${native.stdout.slice(-6000)}\nBuild diagnostics:\n${native.stderr.slice(-2000)}`);
    assert.match(output, /Test run with 1 test.*passed/,
      "Selected native integration tests must execute");
    if (liveReplication) console.log("PASS: native Transaction edit saves offline, survives encrypted restart, uploads, replicates exact readback and preserves other fields");
    if (liveReplication) console.log("PASS: actual local PowerSync download, offline category edit, encrypted reopen, upload and replicated receipt readback");
    if (liveReplication) console.log("PASS: real downloaded Transaction browser metadata, explicit partial scope, offline reopen, optimistic/reconciled category changes and post-removal denial");
    if (liveReplication) console.log("PASS: Project export uses complete authorized current-origin rows and processed order online/offline; removal denies export");
    if (liveReplication) console.log("PASS: populated foreign Account excluded by actual service subscription; membership removal withdraws downloaded category/receipt access");
    if (!liveReplication) {
      const rows = (await applier.read(owner)).categories.filter(row => row.id.startsWith(`${accountId}-sdk-`));
      assert.deepEqual(rows.map(row => row.id).sort(), [`${accountId}-sdk-normal`, `${accountId}-sdk-retry`]);
      assert.ok(rows.every(row => row.revision === "1" && row.kind === "general"));
      console.log("PASS: real SDK uploads after encrypted restart, lost-response replay, retained terminal result, and authoritative MCP category readback");
      if (authUserId) {
        const linked = sql(`select count(*) from public.spike_projects p
          join public.spike_clients c on c.account_id=p.account_id and c.id=p.client_id
          join public.spike_project_category_allocations a on a.account_id=p.account_id and a.project_id=p.id
          where p.account_id=${literal(accountId)} and p.id=${literal(`${accountId}-project`)}
            and c.id=${literal(`client-runtime-${accountId}`)} and a.category_id=${literal(`${accountId}-sdk-normal`)}
            and a.allocation_minor_units is null;`);
        assert.match(linked, /\n\s*1\s*\n/, "Server must retain the Project/Client/new category relationship");
        console.log("PASS: native Supabase Auth receipt/history read and app connection upload Client, inline category and linked Project after encrypted restart");
      }
    }
  }
  if (process.argv.includes('--transaction-edit')) {
    const before = await details.read({ transactionId: receiptId }, owner);
    assert.ok(before.detailsRevision);
    const edit = { operationUUID: randomUUID(), clientCreatedAtMilliseconds: 123000, payload: {
      transactionId: receiptId, scopeKind: before.scopeKind, projectId: before.projectId, clientId: before.clientId,
      expectedRevision: before.detailsRevision, changes: { notes: 'Edited via MCP 🪑', paymentMethod: null }
    } };
    const result = await transactionDetailsEditTool(edit, owner, details);
    assert.equal(result.phase, 'applied');
    assert.deepEqual(await transactionDetailsEditTool(edit, owner, details), result);
    const after = await details.read({ transactionId: receiptId }, owner);
    assert.deepEqual(after, { ...before, notes: 'Edited via MCP 🪑', paymentMethod: null,
      detailsRevision: String(BigInt(before.detailsRevision) + 1n) });
    const stale = await transactionDetailsEditTool({ ...edit, operationUUID: randomUUID() }, owner, details);
    assert.equal(stale.errorCode, 'transaction_edit_stale');
    await assert.rejects(transactionDetailsEditTool({ ...edit, payload: { ...edit.payload,
      changes: { notes: 'Changed retry' } } }, owner, details), { code: 'transaction_edit_request_failed' });
    await assert.rejects(transactionDetailsEditTool({ ...edit, operationUUID: randomUUID() }, member, details),
      { code: 'transaction_edit_unavailable' });
    await assert.rejects(transactionDetailsEditTool({ ...edit, operationUUID: randomUUID() },
      { ...owner, accountId: foreignAccountId }, details), { code: 'transaction_edit_unavailable' });
    const paid = await details.read({ transactionId: `${receiptId}-payment` }, owner);
    await assert.rejects(transactionDetailsEditTool({ ...edit, operationUUID: randomUUID(), payload: {
      ...edit.payload, transactionId: paid.transactionId, scopeKind: paid.scopeKind,
      projectId: paid.projectId, clientId: paid.clientId, expectedRevision: paid.detailsRevision!
    } }, owner, details), { code: 'transaction_edit_unavailable' });
    assert.deepEqual(await details.read({ transactionId: paid.transactionId }, owner), paid);
    assert.deepEqual(await details.read({ transactionId: receiptId }, owner), after);
    console.log('PASS: real HTTP Transaction descriptive edit/readback, exact retry, stale/conflicting edit and removed/foreign/imported-payment denial; cash/history unchanged');
  }
  if (process.argv.includes('--transaction-receipt-edit')) {
    const before = await details.read({ transactionId: receiptId }, owner);
    assert.ok(before.receipt);
    const expectedLines = before.receipt.nonItemReceiptLines.map(line => ({ id: line.id, description: line.description,
      magnitudeMinorUnits: line.amountMinorUnits, currency: before.currency, effect: line.effect, quantity: line.quantity ?? null }));
    const lines = [...expectedLines, { id: 'receipt-http-tax', description: 'Printed tax',
      magnitudeMinorUnits: '101', currency: before.currency, effect: 'increase' as const, quantity: null }];
    const edit = { operationUUID: randomUUID(), clientCreatedAtMilliseconds: 123000, payload: {
      transactionId: receiptId, scopeKind: before.scopeKind, projectId: before.projectId, clientId: before.clientId,
      currency: before.currency, expectedLines, lines } };
    const result = await transactionReceiptLinesEditTool(edit, owner, details);
    assert.equal(result.phase, 'applied');
    assert.deepEqual(await transactionReceiptLinesEditTool(edit, owner, details), result);
    const after = await details.read({ transactionId: receiptId }, owner);
    assert.deepEqual(after, { ...before, receipt: { ...before.receipt, nonItemReceiptLines: lines.map(line => ({
      id: line.id, description: line.description, amountMinorUnits: line.magnitudeMinorUnits,
      effect: line.effect, quantity: line.quantity })) } });
    assert.equal((await transactionReceiptLinesEditTool({ ...edit, operationUUID: randomUUID() }, owner, details)).errorCode,
      'transaction_receipt_edit_stale');
    await assert.rejects(transactionReceiptLinesEditTool({ ...edit, payload: { ...edit.payload, lines: [] } }, owner, details),
      { code: 'transaction_edit_request_failed' });
    await assert.rejects(transactionReceiptLinesEditTool({ ...edit, operationUUID: randomUUID() }, member, details),
      { code: 'transaction_edit_unavailable' });
    await assert.rejects(transactionReceiptLinesEditTool({ ...edit, operationUUID: randomUUID() },
      { ...owner, accountId: foreignAccountId }, details), { code: 'transaction_edit_unavailable' });
    const paid = await details.read({ transactionId: `${receiptId}-payment` }, owner);
    await assert.rejects(transactionReceiptLinesEditTool({ ...edit, operationUUID: randomUUID(), payload: {
      ...edit.payload, transactionId: paid.transactionId, scopeKind: paid.scopeKind, projectId: paid.projectId,
      clientId: paid.clientId, expectedLines: [] } }, owner, details), { code: 'transaction_edit_unavailable' });
    assert.deepEqual(await details.read({ transactionId: paid.transactionId }, owner), paid);
    console.log('PASS: real HTTP receipt-line edit/readback, replay/stale/conflict and removed/foreign/imported-payment denial; other Transaction facts unchanged');
  }
} finally {
  // The local test owns these exact synthetic Accounts. Bypass immutable-history
  // triggers only in this cleanup transaction/session, never alter the trigger.
  for (const fixtureAccount of seeded ? [accountId, foreignAccountId] : []) {
    const accountId = fixtureAccount;
    sql(`set local session_replication_role = replica;
    delete from ledger_private.collected_invoice_lines where account_id=${literal(accountId)};
    delete from ledger_private.collected_invoices where account_id=${literal(accountId)};
    delete from ledger_private.item_client_payment_connections where account_id=${literal(accountId)};
    delete from public.item_image_references where account_id=${literal(accountId)};
    delete from public.transaction_attachment_references where account_id=${literal(accountId)};
    delete from public.transaction_attachment_sets where account_id=${literal(accountId)};
    delete from public.item_image_sets where account_id=${literal(accountId)};
    delete from public.item_image_objects where account_id=${literal(accountId)};
    delete from public.transaction_receipt_items where account_id=${literal(accountId)};
    delete from ledger_private.imported_transaction_sources where account_id=${literal(accountId)};
    delete from public.spike_item_project_categories where account_id=${literal(accountId)};
    delete from public.spike_item_placements where account_id=${literal(accountId)};
    delete from public.spike_spaces where account_id=${literal(accountId)};
    delete from public.spike_transactions where account_id=${literal(accountId)};
    delete from public.spike_items where account_id=${literal(accountId)};
    delete from public.spike_operation_results where account_id=${literal(accountId)};
    delete from public.spike_project_category_allocations where account_id=${literal(accountId)};
    delete from public.spike_projects where account_id=${literal(accountId)};
    delete from public.spike_clients where account_id=${literal(accountId)};
    delete from public.spike_budget_categories where account_id=${literal(accountId)};
    delete from public.spike_account_memberships where account_id=${literal(accountId)};
    delete from public.spike_accounts where id=${literal(accountId)};`);
    assert.match(sql(`select 'REMAINING_ATTRIBUTIONS:'||count(*)
      from public.spike_item_project_categories where account_id=${literal(accountId)};`), /REMAINING_ATTRIBUTIONS:0\b/,
      'Fixture cleanup must not leave category evidence after deleting its Account');
  }
  if (authUserId) {
    sql(`delete from public.spike_principals where id=${literal(authPrincipal)} and auth_user_id=${literal(authUserId)};`);
    const response = await fetch(new URL(`/auth/v1/admin/users/${authUserId}`, rest.origin), {
      method: "DELETE", headers: { apikey: status.SERVICE_ROLE_KEY, Authorization: `Bearer ${status.SERVICE_ROLE_KEY}` },
    });
    assert.ok(response.ok, `Local auth fixture cleanup failed (${response.status})`);
  }
}
