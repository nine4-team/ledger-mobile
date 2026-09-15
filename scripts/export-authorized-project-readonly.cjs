// One authorized source project only. This tool has no Firebase write operation.
// Raw output is private, ignored test evidence, not a target import or cutover.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { execFileSync } = require('node:child_process');

async function main() {
  const workspace = '/Users/benjaminmackenzie/Dev/ledger_mobile_supabase';
  if (process.cwd() !== workspace) throw Error('Wrong worktree');
  const args = process.argv.slice(2);
  if (args[0] !== '--execute-read-only' || ![1, 3].includes(args.length) || (args.length === 3 && !['--extend', '--history', '--reverse'].includes(args[1]))) throw Error('Requires --execute-read-only [--extend|--history|--reverse snapshot]');
  for (const name of ['FIRESTORE_EMULATOR_HOST', 'FIREBASE_AUTH_EMULATOR_HOST']) {
    if (process.env[name]) throw Error('Unexpected emulator');
  }
  const projectId = '5abd46c9-9886-4b3e-b2b1-19f6cf995a44';
  const account = 'projects/ledger-nine4/databases/(default)/documents/accounts/1dd4fd75-8eea-4f7a-98e7-bf45b987ae94';
  const outputRoot = path.join(workspace, 'tmp/real-project-copy');
  execFileSync('git', ['check-ignore', 'tmp/real-project-copy/snapshot.json'], { stdio: 'pipe' });
  fs.mkdirSync(outputRoot, { recursive: true, mode: 0o700 });
  if (fs.lstatSync(outputRoot).isSymbolicLink()) throw Error('Symlink output refused');
  fs.chmodSync(outputRoot, 0o700);
  const cli = '/usr/local/lib/node_modules/firebase-tools/lib/';
  const identity = require(cli + 'auth.js').getGlobalDefaultAccount();
  if (identity?.user?.email !== 'team@nine4.co') throw Error('Unexpected identity');
  await require(cli + 'requireAuth.js').requireAuth({ project: 'ledger-nine4', ...identity, nonInteractive: true });
  const api = new (require(cli + 'apiv2.js').Client)({ urlPrefix: 'https://firestore.googleapis.com', apiVersion: 'v1' });
  const priorPath = args[2] && path.resolve(args[2]);
  if (priorPath && (path.dirname(priorPath) !== outputRoot || fs.lstatSync(priorPath).isSymbolicLink())) throw Error('Unexpected input path');
  const prior = priorPath && JSON.parse(fs.readFileSync(priorPath, 'utf8'));
  if (prior && (prior.account !== account || prior.projectId !== projectId || prior.sourceProject !== 'ledger-nine4')) throw Error('Unexpected source');
  const documents = new Map((prior?.documents || []).map(doc => [doc.name, doc]));
  const reads = [];
  const startedAt = new Date().toISOString();
  if (!prior) {
    const source = await api.get('/' + account + '/projects/' + projectId);
    if (source.body.fields?.isArchived?.booleanValue !== false) throw Error('Source no longer explicitly active');
    documents.set(source.body.name, source.body);
  }
  async function query(collection, field, value) {
    const response = await api.post('/' + account + ':runQuery', { structuredQuery: {
      from: [{ collectionId: collection }],
      where: { fieldFilter: { field: { fieldPath: field }, op: 'EQUAL', value: { stringValue: value } } }
    } });
    if (!Array.isArray(response.body)) throw Error('Unexpected query response');
    for (const row of response.body) if (row.document) documents.set(row.document.name, row.document);
    reads.push({ collection, field, readTime: response.body.at(-1)?.readTime });
  }
  if (!prior) {
    for (const collection of ['items', 'transactions', 'spaces', 'invoices']) await query(collection, 'projectId', projectId);
    for (const field of ['fromProjectId', 'toProjectId']) await query('lineageEdges', field, projectId);
  }
  // Project-owned child collections are scoped by their parent path.
  for (const child of prior ? [] : ['budgetCategories', 'feeInstallments', 'notes', 'requests']) {
    let pageToken;
    do {
      const params = new URLSearchParams({ pageSize: '500' });
      if (pageToken) params.set('pageToken', pageToken);
      const response = await api.get('/' + account + '/projects/' + projectId + '/' + child + '?' + params);
      for (const doc of response.body.documents || []) documents.set(doc.name, doc);
      pageToken = response.body.nextPageToken;
    } while (pageToken);
  }
  const missing = [...(prior?.missing || [])];
  if (prior && args[1] === '--reverse') {
    const transactionIDs = prior.documents.filter(doc => doc.name.startsWith(account + '/transactions/')).map(doc => doc.name.split('/').at(-1));
    for (const [collection, field] of [['items', 'transactionId'], ['lineageEdges', 'fromTransactionId'], ['lineageEdges', 'toTransactionId']]) {
      for (let offset = 0; offset < transactionIDs.length; offset += 10) {
        const response = await api.post('/' + account + ':runQuery', { structuredQuery: {
          from: [{ collectionId: collection }], where: { fieldFilter: {
            field: { fieldPath: field }, op: 'IN',
            value: { arrayValue: { values: transactionIDs.slice(offset, offset + 10).map(stringValue => ({ stringValue })) } }
          } }
        } });
        if (!Array.isArray(response.body)) throw Error('Unexpected reverse-link response');
        for (const row of response.body) if (row.document) documents.set(row.document.name, row.document);
        reads.push({ collection, field, readTime: response.body.at(-1)?.readTime });
      }
    }
  }
  if (prior && args[1] === '--history') {
    const itemIDs = prior.documents.filter(doc => doc.name.startsWith(account + '/items/')).map(doc => doc.name.split('/').at(-1));
    for (let offset = 0; offset < itemIDs.length; offset += 10) {
      const response = await api.post('/' + account + ':runQuery', { structuredQuery: {
        from: [{ collectionId: 'lineageEdges' }], where: { fieldFilter: {
          field: { fieldPath: 'itemId' }, op: 'IN',
          value: { arrayValue: { values: itemIDs.slice(offset, offset + 10).map(stringValue => ({ stringValue })) } }
        } }
      } });
      if (!Array.isArray(response.body)) throw Error('Unexpected history response');
      for (const row of response.body) if (row.document) documents.set(row.document.name, row.document);
      reads.push({ collection: 'lineageEdges', field: 'itemId', readTime: response.body.at(-1)?.readTime });
    }
    for (const space of prior.documents.filter(doc => doc.name.startsWith(account + '/spaces/'))) {
      let pageToken;
      do {
        const params = new URLSearchParams({ pageSize: '500' });
        if (pageToken) params.set('pageToken', pageToken);
        const response = await api.get('/' + space.name + '/reviewNotes?' + params);
        for (const doc of response.body.documents || []) documents.set(doc.name, doc);
        pageToken = response.body.nextPageToken;
      } while (pageToken);
    }
  }
  if (prior && args[1] === '--extend') {
    const references = new Set();
    function collect(document) {
      for (const reference of collectDocumentReferences(account, document)) references.add(reference);
    }
    for (const doc of prior.documents) collect(doc);
    // Follow explicit references to closure, never sweep another project.
    // Set iteration includes references discovered by each successful GET.
    for (const name of references) {
      if (documents.has(name) || missing.includes(name)) continue;
      try {
        const response = await api.get('/' + name);
        documents.set(response.body.name, response.body);
        if (documents.size > 5000) throw Error('Dependency scope exceeds reviewed test-copy bound');
        collect(response.body);
      } catch (error) {
        if (error.status === 404 || error.context?.response?.statusCode === 404) missing.push(name);
        else throw error;
      }
    }
  }
  const sorted = [...documents.values()].sort((a, b) => a.name.localeCompare(b.name));
  const payload = JSON.stringify({ sourceProject: 'ledger-nine4', account, projectId, startedAt,
    finishedAt: new Date().toISOString(), consistency: 'Sequential reads, not an atomic snapshot',
    completeness: 'Project-scoped first pass; cross-project references, item-only lineage and media bytes require closure before import',
    parentSnapshot: priorPath || null, missing, reads, documents: sorted });
  const filename = path.join(outputRoot, 'source-' + Date.now() + '.json');
  fs.writeFileSync(filename, payload, { mode: 0o600, flag: 'wx' });
  const counts = {};
  for (const doc of sorted) { const kind = doc.name.split('/').at(-2); counts[kind] = (counts[kind] || 0) + 1; }
  console.log(JSON.stringify({ filename, counts, bytes: Buffer.byteLength(payload), sha256: crypto.createHash('sha256').update(payload).digest('hex'), imported: false }));
}
// Pure reference discovery; importing this module never starts a source export.
function collectDocumentReferences(account, document) {
  if (!document.name?.startsWith(account + '/')) throw Error('Reference document outside Account');
  const targets = { itemId: 'items', itemIds: 'items', transactionId: 'transactions', transactionIds: 'transactions',
    fromTransactionId: 'transactions', toTransactionId: 'transactions', inventoryEntryTransactionId: 'transactions',
    settlementTransactionId: 'transactions', settlementTransactionIds: 'transactions',
    settlementInvoiceId: 'invoices', spaceId: 'spaces', budgetCategoryId: 'presets/default/budgetCategories',
    vendorId: 'presets/default/vendors', clientId: 'clients', invoiceId: 'invoices', projectId: 'projects',
    fromProjectId: 'projects', toProjectId: 'projects', existingSaleMovementEdgeIds: 'lineageEdges' };
  const references = new Set();
  const validID = id => typeof id === 'string' && id.length > 0 && !id.includes('/') && !['.', '..'].includes(id);
  const project = document.fields?.projectId?.stringValue;
  function add(collection, id) {
    if (validID(id)) references.add(account + '/' + collection + '/' + id);
  }
  function collect(fields) {
    for (const [key, value] of Object.entries(fields || {})) {
      if (targets[key]) for (const candidate of value.arrayValue?.values || [value]) add(targets[key], candidate.stringValue);
      if (value.mapValue) collect(value.mapValue.fields);
      for (const entry of value.arrayValue?.values || []) if (entry.mapValue) collect(entry.mapValue.fields);
    }
  }
  collect(document.fields);
  // sourceId is polymorphic. Never treat fee IDs as Account-root collections,
  // line IDs as documents, or a manual line as an external source.
  for (const value of document.fields?.lines?.arrayValue?.values || []) {
    const line = value.mapValue?.fields;
    const type = line?.sourceType?.stringValue?.toLowerCase(), id = line?.sourceId?.stringValue;
    if (type === 'item') add('items', id);
    if (type === 'transaction') add('transactions', id);
    if (type === 'feeinstallment' && validID(id)) {
      if (!validID(project)) throw Error('Invoice fee source requires Project scope');
      add('projects/' + project + '/feeInstallments', id);
    }
  }
  return [...references];
}
module.exports = { collectDocumentReferences };
if (require.main === module) main().catch(error => { console.error('Read-only export failed:', error.code || error.status || error.name); process.exitCode = 1; });
