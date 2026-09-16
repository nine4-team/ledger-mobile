// Exercises the actual copy runner against typed synthetic source data. Every
// database write rolls back; never calls Firebase or overwrites the real copy.
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { writeFileSync, unlinkSync, mkdirSync, mkdtempSync, rmdirSync } from 'node:fs';
import { randomUUID, createHash } from 'node:crypto';
import path from 'node:path';

const root = '/Users/benjaminmackenzie/Dev/ledger_mobile_supabase';
assert.equal(process.cwd(), root);
const account = 'projects/ledger-nine4/databases/(default)/documents/accounts/1dd4fd75-8eea-4f7a-98e7-bf45b987ae94';
const project = '5abd46c9-9886-4b3e-b2b1-19f6cf995a44';
const suffix = randomUUID();
const expense = `expense-${suffix}`, invoice = `invoice-${suffix}`, payment = `payment-${suffix}`, category = `category-${suffix}`;
const s = value => ({ stringValue: value });
const n = value => ({ integerValue: String(value) });
const a = values => ({ arrayValue: { values } });
const m = fields => ({ mapValue: { fields } });
const doc = (id, fields) => ({ name: `${account}/${id}`, fields });
const snapshot = { account, sourceProject: 'ledger-nine4', documents: [
  doc(`projects/${project}`, { name: s('Synthetic Expense project'), clientName: s('Synthetic Client') }),
  doc('presets/default/budgetCategories/da556858-1df8-40be-b10c-b15710d7cc9a',
    { name: s('Synthetic Furnishings'), metadata: m({ categoryType: s('itemized') }) }),
  doc(`presets/default/budgetCategories/${category}`, { name: s('Synthetic category'), metadata: m({ categoryType: s('general') }) }),
  doc(`transactions/${expense}`, { projectId: s(project), type: s('purchase'), purchasedBy: s('design-business'),
    budgetCategoryId: s(category), amountCents: n('9007199254740993'), transactionDate: s('2024-02-29'),
    createdAt: { timestampValue: '1969-12-31T23:59:59.999999999Z' }, source: s('Original vendor'), notes: s('Original notes'), itemIds: a([]) }),
  doc(`transactions/${payment}`, { projectId: s(project), type: s('paymentToBusiness'), amountCents: n('9007199254740993'),
    settlementInvoiceId: s(invoice), settlementInvoiceLineIds: a([s(`line-${suffix}`)]) }),
  doc(`invoices/${invoice}`, { projectId: s(project), status: s('paid'), totalCents: n('9007199254740993'),
    invoiceNumber:s('  INV-SYNTHETIC  '),notes:s('Original Invoice\nnotes'),datePaid:{timestampValue:'1969-12-31T23:59:59.999999999Z'},
    lines: a([m({ id: s(`line-${suffix}`), amountCents: n('9007199254740993'), sign: n(1), sourceType: s('transaction'),
      sourceId: s(expense), snapshotName: s('Historical description'), budgetCategoryId: s(category) })]) })
] };
const directory = path.join(root, 'tmp/real-project-copy');
mkdirSync(directory, { recursive: true, mode: 0o700 });
const file = path.join(directory, `synthetic-expense-${suffix}.json`);
const binDir = execFileSync('swift', ['build', '--package-path', 'LedgeriOS', '--show-bin-path'], { encoding: 'utf8' }).trim();
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
let mediaDirectory, headers;
const uploaded = [], temporaryMediaFiles = [];
try {
  writeFileSync(file, JSON.stringify(snapshot), { mode: 0o600, flag: 'wx' });
  const result = execFileSync(path.join(binDir, 'LedgerLocalPaymentImport'), ['--check-project-copy', file], { encoding: 'utf8', timeout: 30000 });
  assert.match(result, /rollback check passed/);
  assert.match(result, /Expense Invoices 1, Expenses 1, unresolved Transactions 0, unresolved Invoices 0/);
  const count = execFileSync('docker', ['exec', 'supabase_db_ledger_target_supabase_local', 'psql', '-U', 'postgres', '-d', 'postgres', '-Atc',
    `select count(*) from ledger_private.imported_expense_invoice_sources where source_invoice_id='${invoice}';`], { encoding: 'utf8' }).trim();
  assert.equal(count, '0', 'Rollback leaves no imported source');
  const fee = `fee-${suffix}`, feeCategory = `fee-category-${suffix}`;
  const paymentFields = snapshot.documents.find(row => row.name.endsWith(`/transactions/${payment}`)).fields;
  const invoiceFields = snapshot.documents.find(row => row.name.endsWith(`/invoices/${invoice}`)).fields;
  snapshot.documents.push(
    doc(`presets/default/budgetCategories/${feeCategory}`, { name: s('Synthetic Fee category'), metadata: m({ categoryType: s('fee') }) }),
    doc(`projects/${project}/feeInstallments/${fee}`, { label: s('Current Fee'), budgetCategoryId: s(feeCategory), amountCents: n(50) }));
  paymentFields.amountCents = n('9007199254741043');
  paymentFields.settlementInvoiceLineIds.arrayValue.values.push(s(`fee-line-${suffix}`));
  invoiceFields.totalCents = n('9007199254741043');
  invoiceFields.lines.arrayValue.values.push(m({ id: s(`fee-line-${suffix}`), amountCents: n(50), sign: n(1),
    sourceType: s('feeInstallment'), sourceId: s(fee), snapshotName: s('Historical Fee'), budgetCategoryId: s(feeCategory) }));
  writeFileSync(file, JSON.stringify(snapshot), { mode: 0o600 });
  const mixed = execFileSync(path.join(binDir, 'LedgerLocalPaymentImport'), ['--check-project-copy', file], { encoding: 'utf8', timeout: 30000 });
  assert.match(mixed, /Expense Invoices 1, Expenses 1, unresolved Transactions 0, unresolved Invoices 0/);
  assert.equal(execFileSync('docker', ['exec', 'supabase_db_ledger_target_supabase_local', 'psql', '-U', 'postgres', '-d', 'postgres', '-Atc',
    `select count(*) from ledger_private.imported_fee_sources where source_document_id='${fee}';`], { encoding: 'utf8' }).trim(), '0', 'Mixed Fee import rolls back');
  snapshot.documents.splice(-2);
  paymentFields.amountCents = n('9007199254740993');
  paymentFields.settlementInvoiceLineIds.arrayValue.values.pop();
  invoiceFields.totalCents = n('9007199254740993');
  invoiceFields.lines.arrayValue.values.pop();
  snapshot.documents.find(row => row.name.endsWith(`/transactions/${expense}`)).fields.receiptImages =
    a([m({ url: s('https://example.invalid/private-receipt.jpg') })]);
  writeFileSync(file, JSON.stringify(snapshot), { mode: 0o600 });
  const excluded = execFileSync(path.join(binDir, 'LedgerLocalPaymentImport'), ['--check-project-copy', file], { encoding: 'utf8', timeout: 30000 });
  assert.match(excluded, /Expense Invoices 0, Expenses 0, unresolved Transactions 2, unresolved Invoices 1/,
    'Media-bearing source remains excluded until its protected bytes are mapped');
  const originals = [
    { object:`synthetic-${suffix}/receipt.pdf`,contentType:'application/pdf',kind:'pdf',bytes:Buffer.from('%PDF-1.4\n% Synthetic receipt transport fixture\n%%EOF\n') },
    { object:`synthetic-${suffix}/receipt.png`,contentType:'image/png',kind:'image',bytes:Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jB1kAAAAASUVORK5CYII=','base64') }
  ];
  snapshot.documents.find(row=>row.name.endsWith(`/transactions/${expense}`)).fields.receiptImages = a(originals.map(row=>m({
    url:s('https://firebasestorage.googleapis.com/v0/b/ledger-nine4.firebasestorage.app/o/'+encodeURIComponent(row.object)),
    kind:s(row.kind),fileName:s(path.basename(row.object))
  })));
  const snapshotBytes=JSON.stringify(snapshot), sourceSHA256=hash(snapshotBytes);
  writeFileSync(file,snapshotBytes,{mode:0o600});
  mediaDirectory=mkdtempSync(path.join(directory,'media-synthetic-expense-'));
  const saveMedia=(name,bytes)=>{ const target=path.join(mediaDirectory,name);writeFileSync(target,bytes,{mode:0o600,flag:'wx'});temporaryMediaFiles.push(target); };
  saveMedia('source.json',JSON.stringify({input:file,sha256:sourceSHA256,expectedObjects:originals.length}));
  saveMedia('results.jsonl',originals.map(row=>JSON.stringify({status:'copied',object:row.object,file:hash(row.object),sha256:hash(row.bytes),bytes:row.bytes.length,contentType:row.contentType})).join('\n'));
  for(const row of originals) saveMedia(hash(row.object),row.bytes);
  const args=['--check-project-copy',file,'--receipt-media',mediaDirectory];
  const run=()=>execFileSync(path.join(binDir,'LedgerLocalPaymentImport'),args,{encoding:'utf8',timeout:60000,stdio:['ignore','pipe','pipe']});
  assert.throws(run, /Command failed/, 'Missing protected originals must fail before financial import; check never uploads');
  const local=JSON.parse(execFileSync('npx',['--offline','--yes','supabase@2.116.0','status','-o','json'],{encoding:'utf8',stdio:['ignore','pipe','ignore']}));
  assert.equal(local.API_URL,'http://127.0.0.1:54321');
  headers={apikey:local.SERVICE_ROLE_KEY,Authorization:'Bearer '+local.SERVICE_ROLE_KEY};
  const targetAccount='realcopy-b9d236394770-check-'+sourceSHA256.slice(0,12)+'-account';
  const localSQL=sql=>execFileSync('docker',['exec','supabase_db_ledger_target_supabase_local','psql','-X','-q','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-c',sql],{encoding:'utf8'});
  localSQL(`insert into public.spike_accounts(id,display_name) values('${targetAccount}','Synthetic receipt destination conflict');`);
  try {
    assert.throws(run,error=>{
      assert.match(String(error.stderr),/Test copy already exists; reconcile before replay/);
      assert.doesNotMatch(String(error.stderr),/Expense receipt preparation failed/);
      return true;
    },'Destination conflict must stop before protected Storage verification/upload');
  } finally {
    localSQL(`delete from public.spike_accounts where id='${targetAccount}' and display_name='Synthetic receipt destination conflict';`);
  }
  for(const row of originals) {
    const objectID=targetAccount.slice(0,-'-account'.length)+'-tx-media-'+hash(row.object).slice(0,24);
    const storagePath=`accounts/${targetAccount}/attachments/${objectID}/${hash(row.bytes)}`;
    const url='http://127.0.0.1:54321/storage/v1/object/ledger-attachments/'+storagePath;
    const response=await fetch(url,{method:'POST',headers:{...headers,'Content-Type':row.contentType,'x-upsert':'false'},body:row.bytes,signal:AbortSignal.timeout(10000)});
    assert.equal(response.ok,true,'Synthetic receipt upload succeeds without upsert');
    uploaded.push(storagePath);await response.body?.cancel();
  }
  const mapped=run();
  assert.match(mapped,/Expense Invoices 1, Expenses 1, unresolved Transactions 0, unresolved Invoices 0/);
  assert.match(mapped,/Verified Expense receipt objects: 2/);
  const remaining=execFileSync('docker',['exec','supabase_db_ledger_target_supabase_local','psql','-U','postgres','-d','postgres','-Atc',
    `select (select count(*) from public.item_image_objects where account_id='${targetAccount}')+(select count(*) from ledger_private.imported_expense_invoice_sources where source_invoice_id='${invoice}');`],{encoding:'utf8'}).trim();
  assert.equal(remaining,'0','Receipt catalog and financial import both roll back');
  writeFileSync(path.join(mediaDirectory,hash(originals[0].object)),'corrupt');
  assert.throws(run,/Command failed/,'Changed local source bytes cannot be substituted by already-uploaded bytes');
  console.log('PASS: actual Swift Expense-only and mixed Fee/Expense conversion → verified PDF/image Storage bytes → source/receipt/Invoice SQL reconciliation → rollback; >2^53 amount, original timestamp, missing/corrupt media rejection.');
} finally {
  if(uploaded.length) {
    const removed=await fetch('http://127.0.0.1:54321/storage/v1/object/ledger-attachments',{method:'DELETE',headers:{...headers,'Content-Type':'application/json'},body:JSON.stringify({prefixes:uploaded}),signal:AbortSignal.timeout(10000)});
    assert.equal(removed.ok,true,'Remove only this run’s uniquely named synthetic Storage objects');await removed.body?.cancel();
  }
  for(const temporary of temporaryMediaFiles) unlinkSync(temporary);
  if(mediaDirectory) rmdirSync(mediaDirectory);
  unlinkSync(file);
}
