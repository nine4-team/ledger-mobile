// Test-only evaluator, run inside the pinned local PowerSync container. Inputs
// are synthetic fixture rows from categoryManagement.local.ts, never credentials.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const {SqlSyncRules, DEFAULT_HYDRATION_STATE, RequestParameters} = await import('/app/packages/sync-rules/dist/index.js');
const input = JSON.parse(readFileSync(0, 'utf8'));
const block = input.yaml.match(/^  transaction_receipts:\n([\s\S]*?)(?=^  \S|$(?![\s\S]))/m)?.[1];
assert.ok(block);
const queries = [...block.matchAll(/^      - \|\n((?:        .*(?:\n|$))+)/gm)].map(m => m[1]);
const results = [];
const cases = queries.map((query,index)=>({index, query,
    yaml: `config:\n  edition: 3\nstreams:\n  transaction_receipts:\n    auto_subscribe: false\n    queries:\n      - |\n${query}`}));
cases.push({index: 'combined', query: '', yaml: input.yaml});
for (const {index, query, yaml} of cases) {
    const {config} = SqlSyncRules.fromYaml(yaml, {defaultSchema: 'public', throwOnError: true});
    const hydrated = config.hydrate({hydrationState: DEFAULT_HYDRATION_STATE, sqlite: null});
    const lookupIndex = new Map();
    for (const fact of input.facts) {
        // The parameter predicates use scalar columns. Match replication's
        // SQLite representation of booleans and JSON; no monetary calculation.
        const row = Object.fromEntries(Object.entries(fact.row).map(([key,value]) => [key,
            typeof value === 'boolean' ? Number(value) : value !== null && typeof value === 'object' ? JSON.stringify(value) : value]));
        for (const entry of hydrated.evaluateParameterRow(fact.table, row)) {
            const key = entry.lookup.serializedRepresentation;
            // Postgres storage selects the latest row per source key, NOT
            // DISTINCT bucket_parameters. Equal values from different source
            // rows still consume the service's parameter-result budget.
            const existing = lookupIndex.get(key) ?? [];
            existing.push(...entry.bucketParameters);
            lookupIndex.set(key, existing);
        }
    }
    const subscriptions = [{parameters: input.parameters, priorityOverride: null, opaque_id: 0}];
    if (index === 'combined') {
        for (const projectId of (input.projectIds ?? []).slice(1)) subscriptions.push({
            parameters: {...input.parameters, project_id: projectId}, priorityOverride: null, opaque_id: subscriptions.length});
        subscriptions.push({parameters: {...input.parameters,
            scope_kind: 'business_inventory', project_id: null}, priorityOverride: null, opaque_id: subscriptions.length});
    }
    const {querier, errors} = hydrated.getBucketParameterQuerier({
        globalParameters: new RequestParameters({parsedPayload: {sub: input.userId},
            userIdJson: input.userId, parameters: {}}, {}), hasDefaultStreams: index === 'combined',
        streams: {transaction_receipts: subscriptions, ...(index === 'combined'
            ? {spike_projects: [{parameters: null, priorityOverride: null, opaque_id: 2}]} : {})}
    });
    assert.deepEqual(errors, []);
    let lookups = 0, rows = 0;
    const bySource = {};
    let buckets = 0, bucketCandidates = 0, error;
    try {
        const resolved = await querier.queryDynamicBucketDescriptions({getParameterSets: async requests => requests.map(lookup => {
            const values = lookupIndex.get(lookup.serializedRepresentation) ?? [];
            const source = [...lookup.source.getSourceTables()].map(t=>t.name).join(',');
            bySource[source] = (bySource[source] ?? 0) + values.length;
            lookups++; rows += values.length;
            assert.ok(rows <= 5000, 'diagnostic stops excessive expansion');
            return {lookup, rows: values};
        })});
        const all = [...resolved, ...querier.staticBuckets];
        bucketCandidates = all.length;
        buckets = new Set(all.map(bucket=>bucket.bucket)).size;
    } catch (failure) { error = failure.message; }
    results.push({index, table: query.match(/FROM\s+(?:ledger_private\.)?([a-z_]+)/)?.[1], lookups, rows, buckets, bucketCandidates, bySource, error});
}
console.log(JSON.stringify(results));
