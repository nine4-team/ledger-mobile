#!/usr/bin/env node
/**
 * Validate a Ledger server JSON export for basic referential integrity.
 *
 * Usage:
 *   node docs/data_migrator/validate-ledger-export.mjs <export.json> \
 *     [--storage <storage_export_dir>] \
 *     [--check-storage] \
 *     [--out <report.json>]
 *
 * Notes:
 * - In this dataset, references commonly point to `transactions.transaction_id`
 *   (NOT `transactions.id`). We validate against both, and report what matched.
 * - Empty-string IDs (e.g. from_transaction_id: "") are treated as "no link".
 */

import fs from 'node:fs/promises';
import path from 'node:path';

function parseArgs(argv) {
  const args = argv.slice(2);
  const positional = [];
  const flags = new Map();

  for (let i = 0; i < args.length; i += 1) {
    const a = args[i];
    if (!a.startsWith('--')) {
      positional.push(a);
      continue;
    }
    const key = a.slice(2);
    const next = args[i + 1];
    if (!next || next.startsWith('--')) {
      flags.set(key, true);
    } else {
      flags.set(key, next);
      i += 1;
    }
  }

  return {
    exportPath: positional[0],
    storageDir: flags.get('storage') || null,
    checkStorage: Boolean(flags.get('check-storage')),
    outPath: flags.get('out') || null,
  };
}

function isNonEmptyString(v) {
  return typeof v === 'string' && v.trim().length > 0;
}

function makeIdSet(rows, selector) {
  const s = new Set();
  for (const r of rows) {
    const id = selector(r);
    if (isNonEmptyString(id)) s.add(id);
  }
  return s;
}

function inc(counter, key) {
  counter[key] = (counter[key] ?? 0) + 1;
}

async function fileExists(p) {
  try {
    await fs.access(p);
    return true;
  } catch {
    return false;
  }
}

function extractBucketAndKeyFromUrl(url) {
  if (!isNonEmptyString(url)) return null;
  // Example:
  // https://.../storage/v1/object/public/receipt-images/<KEY>
  const marker = '/storage/v1/object/public/';
  const idx = url.indexOf(marker);
  if (idx === -1) return null;
  const rest = url.slice(idx + marker.length);
  const [bucket, ...keyParts] = rest.split('/');
  if (!bucket || keyParts.length === 0) return null;
  return { bucket, key: keyParts.join('/') };
}

function getTable(exportJson, name) {
  const tables = exportJson?.tables;
  const arr = tables?.[name];
  return Array.isArray(arr) ? arr : [];
}

async function main() {
  const { exportPath, storageDir, checkStorage, outPath } = parseArgs(process.argv);

  if (!exportPath) {
    console.error('Missing export path.\n');
    console.error('Usage: node docs/data_migrator/validate-ledger-export.mjs <export.json> [--out report.json]');
    process.exitCode = 2;
    return;
  }

  const raw = await fs.readFile(exportPath, 'utf8');
  const exportJson = JSON.parse(raw);

  const accounts = getTable(exportJson, 'public.accounts');
  const users = getTable(exportJson, 'public.users');
  const projects = getTable(exportJson, 'public.projects');
  const spaces = getTable(exportJson, 'public.spaces');
  const items = getTable(exportJson, 'public.items');
  const transactions = getTable(exportJson, 'public.transactions');
  const edges = getTable(exportJson, 'public.item_lineage_edges');

  const counters = {};
  const problems = {
    errors: [],
    warnings: [],
  };

  const userIdSet = makeIdSet(users, (u) => u.id);
  const projectIdSet = makeIdSet(projects, (p) => p.id);
  const spaceIdSet = makeIdSet(spaces, (s) => s.id);

  const itemUuidSet = makeIdSet(items, (i) => i.id);
  const itemIdSet = makeIdSet(items, (i) => i.item_id);

  // transactions has BOTH `id` (row id) and `transaction_id` (domain id).
  const txRowIdSet = makeIdSet(transactions, (t) => t.id);
  const txDomainIdSet = makeIdSet(transactions, (t) => t.transaction_id);
  const txAnyIdSet = new Set([...txRowIdSet, ...txDomainIdSet]);

  // Basic scope checks
  for (const u of users) {
    if (isNonEmptyString(u.account_id) && accounts.length > 0 && u.account_id !== accounts[0].id) {
      problems.warnings.push({
        code: 'cross_account_user',
        message: 'User belongs to different account_id than exported account.',
        details: { userId: u.id, userAccountId: u.account_id, exportedAccountId: accounts[0].id },
      });
    }
  }

  // Item references
  for (const item of items) {
    if (isNonEmptyString(item.project_id) && !projectIdSet.has(item.project_id)) {
      inc(counters, 'items.project_id_missing');
      problems.errors.push({
        code: 'missing_fk',
        message: 'Item references missing project_id.',
        details: { itemUuid: item.id, item_id: item.item_id, project_id: item.project_id },
      });
    }

    if (isNonEmptyString(item.space_id) && !spaceIdSet.has(item.space_id)) {
      inc(counters, 'items.space_id_missing');
      problems.errors.push({
        code: 'missing_fk',
        message: 'Item references missing space_id.',
        details: { itemUuid: item.id, item_id: item.item_id, space_id: item.space_id },
      });
    }

    // These appear to be domain transaction IDs in this dataset.
    for (const field of ['transaction_id', 'latest_transaction_id', 'previous_project_transaction_id', 'origin_transaction_id']) {
      const v = item[field];
      if (!isNonEmptyString(v)) continue;
      if (!txAnyIdSet.has(v)) {
        inc(counters, `items.${field}_missing`);
        problems.warnings.push({
          code: 'missing_fk',
          message: `Item references missing ${field}.`,
          details: { itemUuid: item.id, item_id: item.item_id, [field]: v },
        });
      }
    }
  }

  // Transaction references
  for (const tx of transactions) {
    if (isNonEmptyString(tx.project_id) && !projectIdSet.has(tx.project_id)) {
      inc(counters, 'transactions.project_id_missing');
      problems.errors.push({
        code: 'missing_fk',
        message: 'Transaction references missing project_id.',
        details: { txRowId: tx.id, transaction_id: tx.transaction_id, project_id: tx.project_id },
      });
    }

    if (Array.isArray(tx.item_ids)) {
      for (const itemId of tx.item_ids) {
        if (!isNonEmptyString(itemId)) continue;
        if (!itemIdSet.has(itemId)) {
          inc(counters, 'transactions.item_ids_missing');
          problems.warnings.push({
            code: 'missing_fk',
            message: 'Transaction references missing item_id (in item_ids array).',
            details: { txRowId: tx.id, transaction_id: tx.transaction_id, item_id: itemId },
          });
        }
      }
    }

    if (isNonEmptyString(tx.created_by) && !userIdSet.has(tx.created_by)) {
      inc(counters, 'transactions.created_by_missing');
      problems.warnings.push({
        code: 'missing_fk',
        message: 'Transaction references missing created_by user.',
        details: { txRowId: tx.id, transaction_id: tx.transaction_id, created_by: tx.created_by },
      });
    }
  }

  // Lineage edges references
  let edgeFromMatchedRowId = 0;
  let edgeFromMatchedDomainId = 0;
  let edgeFromMissing = 0;
  let edgeFromEmpty = 0;
  let edgeItemMissing = 0;

  for (const edge of edges) {
    if (isNonEmptyString(edge.item_id) && !itemIdSet.has(edge.item_id)) {
      edgeItemMissing += 1;
      problems.errors.push({
        code: 'missing_fk',
        message: 'Lineage edge references missing item_id.',
        details: { edgeId: edge.id, item_id: edge.item_id },
      });
    }

    const from = edge.from_transaction_id;
    if (!isNonEmptyString(from)) {
      edgeFromEmpty += 1;
    } else if (txDomainIdSet.has(from)) {
      edgeFromMatchedDomainId += 1;
    } else if (txRowIdSet.has(from)) {
      edgeFromMatchedRowId += 1;
    } else {
      edgeFromMissing += 1;
      problems.warnings.push({
        code: 'missing_fk',
        message: 'Lineage edge references missing from_transaction_id.',
        details: { edgeId: edge.id, from_transaction_id: from },
      });
    }
  }

  counters['item_lineage_edges.from_transaction_id.matched_domain_id'] = edgeFromMatchedDomainId;
  counters['item_lineage_edges.from_transaction_id.matched_row_id'] = edgeFromMatchedRowId;
  counters['item_lineage_edges.from_transaction_id.empty'] = edgeFromEmpty;
  counters['item_lineage_edges.from_transaction_id.missing'] = edgeFromMissing;
  counters['item_lineage_edges.item_id_missing'] = edgeItemMissing;

  // Optional: storage checks (sampled)
  const storageChecks = {
    enabled: Boolean(checkStorage),
    storageDir: storageDir,
    checked: 0,
    missing: 0,
    missingExamples: [],
  };

  if (checkStorage) {
    if (!storageDir) {
      problems.warnings.push({
        code: 'storage_check_skipped',
        message: 'Storage check requested but no --storage dir provided.',
        details: {},
      });
    } else {
      const maxChecks = 500; // avoid walking tens of thousands of files

      /**
       * @param {unknown} media
       */
      const maybeCheckMedia = async (media) => {
        if (!media || typeof media !== 'object') return;
        const url = media.url;
        if (!isNonEmptyString(url)) return;
        const parsed = extractBucketAndKeyFromUrl(url);
        if (!parsed) return;

        if (storageChecks.checked >= maxChecks) return;
        storageChecks.checked += 1;

        const localPath = path.join(storageDir, parsed.bucket, parsed.key);
        const ok = await fileExists(localPath);
        if (!ok) {
          storageChecks.missing += 1;
          if (storageChecks.missingExamples.length < 25) {
            storageChecks.missingExamples.push({ bucket: parsed.bucket, key: parsed.key });
          }
        }
      };

      for (const item of items) {
        if (storageChecks.checked >= maxChecks) break;
        if (Array.isArray(item.images)) {
          for (const img of item.images) {
            if (storageChecks.checked >= maxChecks) break;
            // eslint-disable-next-line no-await-in-loop
            await maybeCheckMedia(img);
          }
        }
      }

      for (const tx of transactions) {
        if (storageChecks.checked >= maxChecks) break;
        for (const field of ['receipt_images', 'transaction_images', 'other_images']) {
          const arr = tx[field];
          if (!Array.isArray(arr)) continue;
          for (const media of arr) {
            if (storageChecks.checked >= maxChecks) break;
            // eslint-disable-next-line no-await-in-loop
            await maybeCheckMedia(media);
          }
        }
      }
    }
  }

  const report = {
    exportPath,
    exportedAt: exportJson.exportedAt ?? null,
    scope: exportJson.scope ?? null,
    counts: exportJson.counts ?? null,
    derivedCounts: {
      accounts: accounts.length,
      users: users.length,
      projects: projects.length,
      spaces: spaces.length,
      items: items.length,
      transactions: transactions.length,
      item_lineage_edges: edges.length,
    },
    idSets: {
      items: { item_id: itemIdSet.size, id: itemUuidSet.size },
      transactions: { transaction_id: txDomainIdSet.size, id: txRowIdSet.size },
    },
    counters,
    totals: {
      errors: problems.errors.length,
      warnings: problems.warnings.length,
    },
    storageChecks,
    errors: problems.errors.slice(0, 200),
    warnings: problems.warnings.slice(0, 200),
    truncated: {
      errors: problems.errors.length > 200,
      warnings: problems.warnings.length > 200,
    },
  };

  const out = JSON.stringify(report, null, 2);
  if (outPath) {
    await fs.writeFile(outPath, out, 'utf8');
    console.log(`Wrote report to ${outPath}`);
  } else {
    console.log(out);
  }
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});

