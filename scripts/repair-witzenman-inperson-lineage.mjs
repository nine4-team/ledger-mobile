#!/usr/bin/env node

/**
 * Append evidence-backed historical lineage for Witzenman's 2nd Home.
 *
 * Dry-run (default):
 *   node scripts/repair-witzenman-inperson-lineage.mjs \
 *     --evidence /absolute/path/to/receipt-evidence.json
 *
 * Apply the exact dry-run plan:
 *   node scripts/repair-witzenman-inperson-lineage.mjs \
 *     --evidence /absolute/path/to/receipt-evidence.json \
 *     --apply --plan-hash <sha256-from-dry-run>
 *
 * This script writes only accounts/{accountId}/lineageEdges. Historical
 * source predecessors use correction edges because creating a sold edge with
 * fromTransactionId set would invoke onLineageEdgeCreated and mutate the
 * source transaction audit. Existing sold edges remain untouched.
 */

import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import admin from 'firebase-admin';

const FIREBASE_PROJECT_ID = 'ledger-nine4';
const ACCOUNT_ID = '1dd4fd75-8eea-4f7a-98e7-bf45b987ae94';
const LEDGER_PROJECT_ID = '5abd46c9-9886-4b3e-b2b1-19f6cf995a44';
const FURNISHINGS_CATEGORY_ID = 'da556858-1df8-40be-b10c-b15710d7cc9a';
const SPECIAL_ITEM_ID = '4XUEzzfBYHtbDgm3N4ZD';
const SPECIAL_SALE_TRANSACTION_ID = 'os433BpkCtwT7NbdvSRS';
const REPAIR_VERSION = 'witzenman-inperson-lineage-v1';
const REPAIR_SOURCE = `ledger-admin/${REPAIR_VERSION}`;
const DEFAULT_OUTPUT_DIR =
  '/Users/benjaminmackenzie/1584_design/06-design-projects/witzenman-2nd-home/ledger_cleanup/ledger-data';

const IN_PERSON_SOURCES = new Set([
  'Homegoods',
  'HomeGoods',
  'TJ Maxx & HomeGoods',
  'Ross',
  'Hobby Lobby',
  'At Home',
  'Marshalls',
]);

function fail(message) {
  throw new Error(message);
}

function assert(condition, message) {
  if (!condition) fail(message);
}

function parseArgs(argv) {
  const result = { apply: false, evidencePath: null, outputDir: DEFAULT_OUTPUT_DIR, planHash: null };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === '--apply') result.apply = true;
    else if (arg === '--evidence') result.evidencePath = argv[++index];
    else if (arg === '--output-dir') result.outputDir = argv[++index];
    else if (arg === '--plan-hash') result.planHash = argv[++index];
    else fail(`Unknown argument: ${arg}`);
  }
  assert(result.evidencePath, '--evidence is required');
  if (result.apply) assert(result.planHash, '--apply requires --plan-hash from the reviewed dry-run');
  return result;
}

function canonicalize(value) {
  if (value === undefined) return { __type: 'undefined' };
  if (value === null || typeof value === 'string' || typeof value === 'boolean') return value;
  if (typeof value === 'number') {
    if (Number.isNaN(value)) return { __type: 'number', value: 'NaN' };
    if (value === Infinity) return { __type: 'number', value: 'Infinity' };
    if (value === -Infinity) return { __type: 'number', value: '-Infinity' };
    if (Object.is(value, -0)) return { __type: 'number', value: '-0' };
    return value;
  }
  if (value instanceof admin.firestore.Timestamp) {
    return { __type: 'timestamp', seconds: value.seconds, nanoseconds: value.nanoseconds };
  }
  if (value instanceof admin.firestore.GeoPoint) {
    return { __type: 'geopoint', latitude: value.latitude, longitude: value.longitude };
  }
  if (value instanceof admin.firestore.DocumentReference) {
    return { __type: 'reference', path: value.path };
  }
  if (Buffer.isBuffer(value) || value instanceof Uint8Array) {
    return { __type: 'bytes', base64: Buffer.from(value).toString('base64') };
  }
  if (Array.isArray(value)) return value.map(canonicalize);
  const result = {};
  for (const key of Object.keys(value).sort()) result[key] = canonicalize(value[key]);
  return result;
}

function stableStringify(value) {
  return JSON.stringify(canonicalize(value));
}

function sha256(value) {
  return crypto.createHash('sha256').update(value).digest('hex');
}

function documentRecord(doc) {
  const data = doc.data();
  return {
    id: doc.id,
    path: doc.ref.path,
    createTime: doc.createTime?.toDate().toISOString() ?? null,
    updateTime: doc.updateTime?.toDate().toISOString() ?? null,
    dataHash: sha256(stableStringify(data)),
    data: canonicalize(data),
  };
}

function collectionDigest(records) {
  return sha256(records.map((record) => `${record.path}|${record.updateTime}|${record.dataHash}`).join('\n'));
}

function snapshotPayload(label, capturedAt, itemDocs, transactionDocs, lineageDocs) {
  const items = itemDocs.map(documentRecord).sort((a, b) => a.id.localeCompare(b.id));
  const transactions = transactionDocs.map(documentRecord).sort((a, b) => a.id.localeCompare(b.id));
  const lineageEdges = lineageDocs.map(documentRecord).sort((a, b) => a.id.localeCompare(b.id));
  return {
    schemaVersion: 1,
    label,
    capturedAt,
    firebaseProjectId: FIREBASE_PROJECT_ID,
    accountId: ACCOUNT_ID,
    ledgerProjectId: LEDGER_PROJECT_ID,
    counts: { items: items.length, transactions: transactions.length, lineageEdges: lineageEdges.length },
    digests: {
      items: collectionDigest(items),
      transactions: collectionDigest(transactions),
      lineageEdges: collectionDigest(lineageEdges),
    },
    items,
    transactions,
    lineageEdges,
  };
}

function normalizeSku(value) {
  if (value == null) return null;
  const normalized = String(value).trim().replace(/[^0-9A-Za-z]/g, '').toUpperCase();
  return normalized || null;
}

function normalizeSource(value) {
  return String(value ?? '').trim().toLowerCase().replace(/[^a-z0-9]/g, '');
}

function sourceFamily(value) {
  const normalized = normalizeSource(value);
  if (['homegoods', 'homegood', 'tjmaxxhomegoods', 'tjmaxxandhomegoods', 'tjmaxx'].includes(normalized)) {
    return 'tjx-homegoods';
  }
  if (normalized === 'marshalls') return 'marshalls';
  if (normalized === 'ross' || normalized === 'rossdressforless') return 'ross';
  if (normalized === 'hobbylobby') return 'hobby-lobby';
  if (normalized === 'athome' || normalized === 'athomestore') return 'at-home';
  return normalized;
}

function transactionType(transaction) {
  return String(transaction.type ?? transaction.transactionType ?? '').trim().toLowerCase();
}

function isActive(data) {
  return data.deletedAt == null && String(data.status ?? '').trim().toLowerCase() !== 'returned';
}

function validInventorySale(transaction, itemId) {
  return transaction != null
    && transaction.deletedAt == null
    && transactionType(transaction) === 'purchase'
    && transaction.projectId === LEDGER_PROJECT_ID
    && String(transaction.source ?? '').trim().endsWith('Inventory')
    && Array.isArray(transaction.itemIds)
    && transaction.itemIds.includes(itemId);
}

function eligibleSourcePurchase(transaction) {
  return transaction != null
    && transaction.deletedAt == null
    && transactionType(transaction) === 'purchase'
    && (transaction.projectId == null || transaction.projectId === '')
    && !String(transaction.source ?? '').trim().endsWith('Inventory');
}

function dayString(value) {
  if (typeof value === 'string') return value.slice(0, 10);
  if (value instanceof admin.firestore.Timestamp) return value.toDate().toISOString().slice(0, 10);
  if (value instanceof Date) return value.toISOString().slice(0, 10);
  return null;
}

function priceCents(item) {
  return Number.isFinite(item.purchasePriceCents) ? Math.round(item.purchasePriceCents) : null;
}

function edgeSemantic(edge) {
  return {
    itemId: edge.itemId ?? null,
    movementKind: edge.movementKind ?? null,
    fromTransactionId: edge.fromTransactionId ?? null,
    toTransactionId: edge.toTransactionId ?? null,
    fromProjectId: edge.fromProjectId ?? null,
    toProjectId: edge.toProjectId ?? null,
    source: edge.source ?? null,
    repairKind: edge.repairKind ?? null,
    idempotencyKey: edge.idempotencyKey ?? null,
  };
}

function deterministicEdgeId(kind, itemId, fromTransactionId, toTransactionId) {
  const digest = sha256(`${REPAIR_VERSION}|${kind}|${itemId}|${fromTransactionId ?? ''}|${toTransactionId}`);
  return `hist_${kind}_${digest.slice(0, 40)}`;
}

function csvEscape(value) {
  if (value == null) return '';
  const text = typeof value === 'string' ? value : JSON.stringify(value);
  return /[",\n\r]/.test(text) ? `"${text.replaceAll('"', '""')}"` : text;
}

function writeCsv(filePath, rows) {
  const headers = [
    'status', 'itemId', 'itemName', 'itemSource', 'sku', 'purchasePriceCents',
    'existingSaleTransactionId', 'existingSaleMovementEdgeId', 'proposedEdgeId',
    'proposedMovementKind', 'sourcePurchaseTransactionId', 'receiptMessageId',
    'receiptDate', 'receiptTotalCents', 'receiptStoreNumber', 'receiptTransactionNumber',
    'receiptCardLast4', 'receiptSku', 'receiptUnitPriceCents', 'receiptQuantity',
    'consumedQuantityBefore', 'unconsumedQuantityBefore', 'reason',
  ];
  const lines = [headers.join(',')];
  for (const row of rows) lines.push(headers.map((header) => csvEscape(row[header])).join(','));
  fs.writeFileSync(filePath, `${lines.join('\n')}\n`);
}

function parseEvidence(filePath) {
  const raw = fs.readFileSync(filePath, 'utf8');
  const data = JSON.parse(raw);
  assert(Array.isArray(data.receipts), 'Evidence file must contain a receipts array');
  const receipts = data.receipts.map((receipt, index) => {
    assert(receipt.messageId, `Receipt ${index} is missing messageId`);
    assert(/^\d{4}-\d{2}-\d{2}$/.test(receipt.date), `Receipt ${receipt.messageId} has invalid date`);
    assert(Number.isInteger(receipt.totalCents) && receipt.totalCents > 0,
      `Receipt ${receipt.messageId} has invalid totalCents`);
    assert(Array.isArray(receipt.lines) && receipt.lines.length > 0,
      `Receipt ${receipt.messageId} has no lines`);
    const lines = receipt.lines.map((line, lineIndex) => {
      const sku = normalizeSku(line.sku);
      assert(sku, `Receipt ${receipt.messageId} line ${lineIndex} has no SKU`);
      assert(Number.isInteger(line.unitPriceCents) && line.unitPriceCents >= 0,
        `Receipt ${receipt.messageId} line ${lineIndex} has invalid unitPriceCents`);
      const quantity = line.quantity ?? 1;
      assert(Number.isInteger(quantity) && quantity > 0,
        `Receipt ${receipt.messageId} line ${lineIndex} has invalid quantity`);
      return { ...line, sku, quantity };
    });
    return { ...receipt, lines, sourceFamily: receipt.sourceFamily ?? sourceFamily(receipt.brand) };
  });
  return { rawHash: sha256(raw), data, receipts };
}

async function loadLiveState(db) {
  const base = `accounts/${ACCOUNT_ID}`;
  const [itemsSnapshot, transactionsSnapshot, lineageSnapshot] = await Promise.all([
    db.collection(`${base}/items`).get(),
    db.collection(`${base}/transactions`).get(),
    db.collection(`${base}/lineageEdges`).get(),
  ]);
  return {
    base,
    itemDocs: itemsSnapshot.docs,
    transactionDocs: transactionsSnapshot.docs,
    lineageDocs: lineageSnapshot.docs,
    items: new Map(itemsSnapshot.docs.map((doc) => [doc.id, { id: doc.id, ...doc.data() }])),
    transactions: new Map(
      transactionsSnapshot.docs.map((doc) => [doc.id, { id: doc.id, ...doc.data() }])
    ),
    lineage: lineageSnapshot.docs.map((doc) => ({ id: doc.id, ...doc.data() })),
  };
}

function receiptTransactionMatches(receipt, transactions) {
  return [...transactions.values()].filter((transaction) =>
    eligibleSourcePurchase(transaction)
    && sourceFamily(transaction.source) === receipt.sourceFamily
    && dayString(transaction.transactionDate ?? transaction.date) === receipt.date
    && transaction.amountCents === receipt.totalCents
  );
}

function lineGroups(receipt) {
  const groups = new Map();
  for (const line of receipt.lines) {
    const key = `${line.sku}|${line.unitPriceCents}`;
    const existing = groups.get(key) ?? {
      sku: line.sku,
      unitPriceCents: line.unitPriceCents,
      quantity: 0,
      departments: new Set(),
    };
    existing.quantity += line.quantity;
    if (line.department) existing.departments.add(line.department);
    groups.set(key, existing);
  }
  return [...groups.values()].map((group) => ({ ...group, departments: [...group.departments].sort() }));
}

function sourceConsumption(sourceTransaction, line, state) {
  const ids = new Set();
  for (const itemId of sourceTransaction.itemIds ?? []) {
    const item = state.items.get(itemId);
    if (normalizeSku(item?.sku) === line.sku && priceCents(item) === line.unitPriceCents) ids.add(itemId);
  }
  for (const edge of state.lineage) {
    if (edge.fromTransactionId !== sourceTransaction.id) continue;
    const consumes = ['sold', 'returned', 'soldToInventory'].includes(edge.movementKind)
      || (edge.source === REPAIR_SOURCE && edge.repairKind === 'historicalSourcePredecessor');
    if (!consumes) continue;
    const item = state.items.get(edge.itemId);
    if (normalizeSku(item?.sku) === line.sku && priceCents(item) === line.unitPriceCents) ids.add(edge.itemId);
  }
  return [...ids].sort();
}

function classifyLineage(itemId, saleTransactionId, lineage) {
  const itemEdges = lineage.filter((edge) => edge.itemId === itemId);
  const saleEdges = itemEdges.filter((edge) =>
    edge.movementKind === 'sold'
    && edge.toTransactionId === saleTransactionId
    && edge.toProjectId === LEDGER_PROJECT_ID
    && (edge.fromProjectId == null || edge.fromProjectId === '')
  );
  const sourceBackedEdges = itemEdges.filter((edge) =>
    edge.toTransactionId === saleTransactionId
    && edge.toProjectId === LEDGER_PROJECT_ID
    && edge.fromTransactionId
    && (edge.movementKind === 'sold'
      || (edge.movementKind === 'correction'
        && edge.source === REPAIR_SOURCE
        && edge.repairKind === 'historicalSourcePredecessor'))
  );
  return { itemEdges, saleEdges, sourceBackedEdges };
}

function baseReportRow(item, saleTransaction, lineageClass) {
  return {
    itemId: item.id,
    itemName: item.name ?? null,
    itemSource: item.source ?? null,
    sku: normalizeSku(item.sku),
    purchasePriceCents: priceCents(item),
    existingSaleTransactionId: saleTransaction?.id ?? item.transactionId ?? null,
    existingSaleMovementEdgeId: lineageClass?.saleEdges?.map((edge) => edge.id).sort().join('|') || null,
  };
}

function buildPlan(state, evidence) {
  const cohort = [...state.items.values()]
    .filter((item) => item.projectId === LEDGER_PROJECT_ID
      && item.budgetCategoryId === FURNISHINGS_CATEGORY_ID
      && IN_PERSON_SOURCES.has(item.source)
      && isActive(item))
    .sort((a, b) => a.id.localeCompare(b.id));
  assert(cohort.length === 301, `Expected the audited 301-item cohort; found ${cohort.length}`);

  const exactReceipts = [];
  const unmatchedReceipts = [];
  for (const receipt of evidence.receipts) {
    const matches = receiptTransactionMatches(receipt, state.transactions);
    if (matches.length === 1) exactReceipts.push({ receipt, transaction: matches[0] });
    else unmatchedReceipts.push({
      messageId: receipt.messageId,
      date: receipt.date,
      totalCents: receipt.totalCents,
      reason: matches.length === 0 ? 'no_existing_source_purchase_matching_date_total_and_store'
        : 'ambiguous_existing_source_purchase_matching_date_total_and_store',
      candidateTransactionIds: matches.map((match) => match.id).sort(),
    });
  }

  const complete = [];
  const sourceMissing = [];
  const missing = [];
  const invalidSale = [];
  for (const item of cohort) {
    const saleTransaction = state.transactions.get(item.transactionId);
    const lineageClass = classifyLineage(item.id, item.transactionId, state.lineage);
    const base = baseReportRow(item, saleTransaction, lineageClass);
    if (!validInventorySale(saleTransaction, item.id)) {
      invalidSale.push({ ...base, reason: 'invalid_or_missing_current_inventory_sale_membership' });
    } else if (lineageClass.sourceBackedEdges.length > 0) {
      complete.push({
        ...base,
        sourcePurchaseTransactionIds: lineageClass.sourceBackedEdges
          .map((edge) => edge.fromTransactionId).sort(),
      });
    } else {
      const entry = { item, saleTransaction, lineageClass, base };
      sourceMissing.push(entry);
      if (lineageClass.saleEdges.length > 0) missing.push(entry);
      else invalidSale.push({ ...base, reason: 'sale_transaction_membership_without_sale_movement' });
    }
  }

  const optionsByItemId = new Map(sourceMissing.map(({ item }) => [item.id, []]));
  const receiptLineAvailability = [];
  for (const { receipt, transaction } of exactReceipts) {
    for (const line of lineGroups(receipt)) {
      const consumedItemIds = sourceConsumption(transaction, line, state);
      const availableQuantity = line.quantity - consumedItemIds.length;
      const candidateItemIds = sourceMissing
        .filter(({ item }) =>
          sourceFamily(item.source) === receipt.sourceFamily
          && normalizeSku(item.sku) === line.sku
          && priceCents(item) === line.unitPriceCents)
        .map(({ item }) => item.id)
        .sort();
      const availability = {
        receiptMessageId: receipt.messageId,
        sourcePurchaseTransactionId: transaction.id,
        sku: line.sku,
        unitPriceCents: line.unitPriceCents,
        receiptQuantity: line.quantity,
        consumedItemIds,
        consumedQuantity: consumedItemIds.length,
        availableQuantity,
        candidateItemIds,
      };
      receiptLineAvailability.push(availability);
      if (availableQuantity > 0) {
        for (const itemId of candidateItemIds) {
          optionsByItemId.get(itemId)?.push({ receipt, transaction, line, availability });
        }
      }
    }
  }

  const proposed = [];
  const skipped = [];
  const candidateGroups = new Map();
  for (const entry of sourceMissing) {
    const options = optionsByItemId.get(entry.item.id) ?? [];
    if (options.length !== 1) {
      skipped.push({
        ...entry.base,
        status: 'skipped',
        reason: options.length === 0 ? 'no_exact_unconsumed_receipt_sku_price_match'
          : 'ambiguous_multiple_source_purchase_matches',
        candidateSourcePurchaseTransactionIds: [...new Set(options.map((option) => option.transaction.id))].sort(),
        candidateReceiptMessageIds: [...new Set(options.map((option) => option.receipt.messageId))].sort(),
      });
      continue;
    }
    const option = options[0];
    const groupKey = [
      option.receipt.messageId,
      option.transaction.id,
      option.line.sku,
      option.line.unitPriceCents,
    ].join('|');
    const group = candidateGroups.get(groupKey) ?? { option, entries: [] };
    group.entries.push(entry);
    candidateGroups.set(groupKey, group);
  }

  for (const group of candidateGroups.values()) {
    const { option, entries } = group;
    if (entries.length > option.availability.availableQuantity) {
      for (const entry of entries) {
        skipped.push({
          ...entry.base,
          status: 'skipped',
          sourcePurchaseTransactionId: option.transaction.id,
          receiptMessageId: option.receipt.messageId,
          receiptQuantity: option.line.quantity,
          consumedQuantityBefore: option.availability.consumedQuantity,
          unconsumedQuantityBefore: option.availability.availableQuantity,
          reason: 'oversubscribed_receipt_sku_price_quantity',
        });
      }
      continue;
    }

    for (const entry of entries.sort((a, b) => a.item.id.localeCompare(b.item.id))) {
      const edgeId = deterministicEdgeId(
        'source_predecessor', entry.item.id, option.transaction.id, entry.saleTransaction.id
      );
      const idempotencyKey = `${REPAIR_VERSION}:source:${entry.item.id}:${option.transaction.id}:${entry.saleTransaction.id}`;
      proposed.push({
        ...entry.base,
        status: 'proposed',
        proposedEdgeId: edgeId,
        proposedMovementKind: 'correction',
        sourcePurchaseTransactionId: option.transaction.id,
        receiptMessageId: option.receipt.messageId,
        receiptDate: option.receipt.date,
        receiptTotalCents: option.receipt.totalCents,
        receiptSubtotalCents: option.receipt.subtotalCents ?? null,
        receiptStoreNumber: option.receipt.storeNumber ?? null,
        receiptTransactionNumber: option.receipt.transactionNumber ?? null,
        receiptCardLast4: option.receipt.cardLast4 ?? null,
        receiptSku: option.line.sku,
        receiptUnitPriceCents: option.line.unitPriceCents,
        receiptQuantity: option.line.quantity,
        receiptDepartments: option.line.departments,
        consumedItemIdsBefore: option.availability.consumedItemIds,
        consumedQuantityBefore: option.availability.consumedQuantity,
        unconsumedQuantityBefore: option.availability.availableQuantity,
        exactEvidence: {
          itemSkuEqualsReceiptSku: true,
          itemPurchasePriceCentsEqualsReceiptUnitPriceCents: true,
          sourcePurchaseDateEqualsReceiptDate: true,
          sourcePurchaseAmountCentsEqualsReceiptTotalCents: true,
          sourceFamilyMatches: true,
          receiptQuantityUnconsumed: true,
        },
        idempotencyKey,
        edgeData: {
          accountId: ACCOUNT_ID,
          itemId: entry.item.id,
          fromTransactionId: option.transaction.id,
          toTransactionId: entry.saleTransaction.id,
          fromProjectId: null,
          toProjectId: LEDGER_PROJECT_ID,
          movementKind: 'correction',
          source: REPAIR_SOURCE,
          repairKind: 'historicalSourcePredecessor',
          idempotencyKey,
          existingSaleMovementEdgeIds: entry.lineageClass.saleEdges.map((edge) => edge.id).sort(),
          evidence: {
            receiptMessageId: option.receipt.messageId,
            receiptDate: option.receipt.date,
            receiptTotalCents: option.receipt.totalCents,
            receiptSubtotalCents: option.receipt.subtotalCents ?? null,
            receiptStoreNumber: option.receipt.storeNumber ?? null,
            receiptTransactionNumber: option.receipt.transactionNumber ?? null,
            receiptCardLast4: option.receipt.cardLast4 ?? null,
            sku: option.line.sku,
            unitPriceCents: option.line.unitPriceCents,
            receiptQuantity: option.line.quantity,
            consumedQuantityBefore: option.availability.consumedQuantity,
          },
          note: 'Historical source-purchase predecessor for an existing inventory-sale movement; no item or transaction association changed.',
          deletedAt: null,
          createdBy: REPAIR_SOURCE,
        },
      });
    }
  }

  const specialItem = state.items.get(SPECIAL_ITEM_ID);
  const specialSale = state.transactions.get(SPECIAL_SALE_TRANSACTION_ID);
  assert(specialItem, `Missing special item ${SPECIAL_ITEM_ID}`);
  assert(specialSale, `Missing special sale ${SPECIAL_SALE_TRANSACTION_ID}`);
  const specialLineage = classifyLineage(SPECIAL_ITEM_ID, SPECIAL_SALE_TRANSACTION_ID, state.lineage);
  const specialMembership = {
    itemTransactionIdMatches: specialItem.transactionId === SPECIAL_SALE_TRANSACTION_ID,
    transactionItemIdsIncludesItem: Array.isArray(specialSale.itemIds)
      && specialSale.itemIds.includes(SPECIAL_ITEM_ID),
    transactionIsValidInventorySale: validInventorySale(specialSale, SPECIAL_ITEM_ID),
  };
  assert(Object.values(specialMembership).every(Boolean),
    `Special item ${SPECIAL_ITEM_ID} membership in ${SPECIAL_SALE_TRANSACTION_ID} is not fully verified`);

  let specialMovement;
  if (specialLineage.saleEdges.length > 0) {
    specialMovement = {
      ...baseReportRow(specialItem, specialSale, specialLineage),
      status: 'already_present',
      reason: 'sale_movement_already_exists',
      membershipEvidence: specialMembership,
    };
  } else {
    const edgeId = deterministicEdgeId('sale_movement', SPECIAL_ITEM_ID, null, SPECIAL_SALE_TRANSACTION_ID);
    const idempotencyKey = `${REPAIR_VERSION}:sale:${SPECIAL_ITEM_ID}:${SPECIAL_SALE_TRANSACTION_ID}`;
    specialMovement = {
      ...baseReportRow(specialItem, specialSale, specialLineage),
      status: 'proposed',
      proposedEdgeId: edgeId,
      proposedMovementKind: 'sold',
      membershipEvidence: specialMembership,
      exactEvidence: {
        itemTransactionIdMatchesSale: true,
        saleTransactionMembershipContainsItem: true,
        saleTransactionIsActiveInventoryPurchaseForTargetProject: true,
      },
      idempotencyKey,
      edgeData: {
        accountId: ACCOUNT_ID,
        itemId: SPECIAL_ITEM_ID,
        fromTransactionId: null,
        toTransactionId: SPECIAL_SALE_TRANSACTION_ID,
        fromProjectId: null,
        toProjectId: LEDGER_PROJECT_ID,
        movementKind: 'sold',
        source: REPAIR_SOURCE,
        repairKind: 'historicalSaleMovement',
        idempotencyKey,
        evidence: specialMembership,
        note: 'Historical repair of a missing sale movement after exact transaction membership verification; no source purchase inferred.',
        deletedAt: null,
        createdBy: REPAIR_SOURCE,
      },
    };
  }

  const planRows = [...proposed, ...(specialMovement.status === 'proposed' ? [specialMovement] : [])]
    .sort((a, b) => a.proposedEdgeId.localeCompare(b.proposedEdgeId));
  const planHash = sha256(stableStringify(planRows.map((row) => ({
    proposedEdgeId: row.proposedEdgeId,
    edgeData: row.edgeData,
  }))));

  return {
    cohort,
    exactReceipts,
    unmatchedReceipts,
    receiptLineAvailability,
    complete,
    sourceMissing,
    missing,
    invalidSale,
    proposed: proposed.sort((a, b) => a.itemId.localeCompare(b.itemId)),
    skipped: skipped.sort((a, b) => a.itemId.localeCompare(b.itemId)),
    specialMovement,
    planRows,
    planHash,
  };
}

function compareDocumentCollections(beforeRecords, afterRecords) {
  const before = new Map(beforeRecords.map((record) => [record.id, record]));
  const after = new Map(afterRecords.map((record) => [record.id, record]));
  const ids = [...new Set([...before.keys(), ...after.keys()])].sort();
  const differences = [];
  for (const id of ids) {
    const left = before.get(id);
    const right = after.get(id);
    if (!left || !right) {
      differences.push({ id, reason: left ? 'deleted' : 'created' });
    } else if (left.dataHash !== right.dataHash || left.updateTime !== right.updateTime) {
      differences.push({
        id,
        reason: 'data_or_update_time_changed',
        beforeDataHash: left.dataHash,
        afterDataHash: right.dataHash,
        beforeUpdateTime: left.updateTime,
        afterUpdateTime: right.updateTime,
      });
    }
  }
  return differences;
}

async function applyPlan(db, state, planRows) {
  if (planRows.length === 0) return { createdEdgeIds: [], alreadyPresentEdgeIds: [] };
  return db.runTransaction(async (transaction) => {
    const refs = planRows.map((row) => db.doc(`${state.base}/lineageEdges/${row.proposedEdgeId}`));
    const docs = await transaction.getAll(...refs);
    const createdEdgeIds = [];
    const alreadyPresentEdgeIds = [];
    const now = admin.firestore.FieldValue.serverTimestamp();
    for (let index = 0; index < docs.length; index += 1) {
      const existing = docs[index];
      const row = planRows[index];
      if (existing.exists) {
        const expected = edgeSemantic(row.edgeData);
        const actual = edgeSemantic(existing.data());
        assert(stableStringify(expected) === stableStringify(actual),
          `Deterministic edge ID collision at ${existing.ref.path}`);
        alreadyPresentEdgeIds.push(row.proposedEdgeId);
      } else {
        transaction.create(existing.ref, { ...row.edgeData, createdAt: now, updatedAt: now });
        createdEdgeIds.push(row.proposedEdgeId);
      }
    }
    return { createdEdgeIds, alreadyPresentEdgeIds };
  });
}

async function waitForStableDocuments(db, beforeSnapshot, timeoutMs = 30_000) {
  const deadline = Date.now() + timeoutMs;
  let lastResult = null;
  while (Date.now() < deadline) {
    await new Promise((resolve) => setTimeout(resolve, 2_000));
    const live = await loadLiveState(db);
    const itemRecords = live.itemDocs.map(documentRecord).sort((a, b) => a.id.localeCompare(b.id));
    const transactionRecords = live.transactionDocs.map(documentRecord).sort((a, b) => a.id.localeCompare(b.id));
    const itemDifferences = compareDocumentCollections(beforeSnapshot.items, itemRecords);
    const transactionDifferences = compareDocumentCollections(beforeSnapshot.transactions, transactionRecords);
    lastResult = { live, itemRecords, transactionRecords, itemDifferences, transactionDifferences };
    if (itemDifferences.length === 0 && transactionDifferences.length === 0) return lastResult;
  }
  return lastResult;
}

function publicPlanRow(row) {
  const { edgeData, ...publicFields } = row;
  return publicFields;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  assert(!process.env.FIRESTORE_EMULATOR_HOST, 'FIRESTORE_EMULATOR_HOST must be unset');
  assert(!['1', 'true', 'yes'].includes(String(process.env.USE_FIREBASE_EMULATORS ?? '').toLowerCase()),
    'USE_FIREBASE_EMULATORS must not enable emulators');
  assert(fs.existsSync(args.evidencePath), `Evidence file does not exist: ${args.evidencePath}`);
  fs.mkdirSync(args.outputDir, { recursive: true });

  const credentialPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  assert(credentialPath && fs.existsSync(credentialPath),
    'GOOGLE_APPLICATION_CREDENTIALS must point at the production service account JSON');
  const serviceAccount = JSON.parse(fs.readFileSync(credentialPath, 'utf8'));
  assert(serviceAccount.project_id === FIREBASE_PROJECT_ID,
    `Credential project must be ${FIREBASE_PROJECT_ID}; found ${serviceAccount.project_id}`);
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    projectId: FIREBASE_PROJECT_ID,
  });
  const db = admin.firestore();

  const evidence = parseEvidence(args.evidencePath);
  const runStartedAt = new Date().toISOString();
  const runId = runStartedAt.replace(/[-:.]/g, '').replace('Z', 'Z');
  const mode = args.apply ? 'apply' : 'dryrun';
  const prefix = path.join(args.outputDir, `witzenman-inperson-lineage-${mode}_${runId}`);

  const beforeState = await loadLiveState(db);
  const beforeSnapshot = snapshotPayload(
    'before', new Date().toISOString(),
    beforeState.itemDocs, beforeState.transactionDocs, beforeState.lineageDocs
  );
  fs.writeFileSync(`${prefix}_before.json`, `${JSON.stringify(beforeSnapshot, null, 2)}\n`);

  const plan = buildPlan(beforeState, evidence);
  if (args.apply) {
    assert(args.planHash === plan.planHash,
      `Plan hash changed. Expected ${args.planHash}; live plan is ${plan.planHash}. Run and review a new dry-run.`);
  }

  let execution = { createdEdgeIds: [], alreadyPresentEdgeIds: [] };
  let afterState = beforeState;
  let afterSnapshot = null;
  let invariantVerification = {
    itemsByteEquivalent: true,
    transactionsByteEquivalent: true,
    itemDifferences: [],
    transactionDifferences: [],
  };

  if (args.apply) {
    execution = await applyPlan(db, beforeState, plan.planRows);
    const stable = await waitForStableDocuments(db, beforeSnapshot);
    afterState = stable.live;
    afterSnapshot = snapshotPayload(
      'after', new Date().toISOString(),
      afterState.itemDocs, afterState.transactionDocs, afterState.lineageDocs
    );
    fs.writeFileSync(`${prefix}_after.json`, `${JSON.stringify(afterSnapshot, null, 2)}\n`);
    invariantVerification = {
      itemsByteEquivalent: stable.itemDifferences.length === 0,
      transactionsByteEquivalent: stable.transactionDifferences.length === 0,
      itemDifferences: stable.itemDifferences,
      transactionDifferences: stable.transactionDifferences,
    };
    assert(invariantVerification.itemsByteEquivalent,
      `Item documents changed after lineage-only apply: ${stable.itemDifferences.length} differences`);
    assert(invariantVerification.transactionsByteEquivalent,
      `Transaction documents changed after lineage-only apply: ${stable.transactionDifferences.length} differences`);
  }

  const afterPlan = buildPlan(afterState, evidence);
  const resultByEdgeId = new Map(execution.createdEdgeIds.map((id) => [id, 'repaired']));
  for (const id of execution.alreadyPresentEdgeIds) resultByEdgeId.set(id, 'already_present');
  const repairedItems = args.apply
    ? plan.planRows.map((row) => ({ ...publicPlanRow(row), status: resultByEdgeId.get(row.proposedEdgeId) }))
    : [];
  const dryRunProposals = args.apply ? [] : plan.planRows.map(publicPlanRow);
  const skippedItems = plan.skipped;
  if (plan.specialMovement.status !== 'proposed') skippedItems.push(plan.specialMovement);

  const beforeCounts = {
    activeCohortItems: plan.cohort.length,
    sourceBackedLineage: plan.complete.length,
      saleMovementMissingSourcePredecessor: plan.missing.length,
      sourcePredecessorGapsAcrossCohort: plan.sourceMissing.length,
    inventorySaleMembershipWithoutSaleMovement: plan.invalidSale.filter(
      (row) => row.reason === 'sale_transaction_membership_without_sale_movement'
    ).length,
    lineageEdgesAccountTotal: beforeSnapshot.counts.lineageEdges,
  };
  const afterCounts = {
    activeCohortItems: afterPlan.cohort.length,
    sourceBackedLineage: afterPlan.complete.length,
      saleMovementMissingSourcePredecessor: afterPlan.missing.length,
      sourcePredecessorGapsAcrossCohort: afterPlan.sourceMissing.length,
    inventorySaleMembershipWithoutSaleMovement: afterPlan.invalidSale.filter(
      (row) => row.reason === 'sale_transaction_membership_without_sale_movement'
    ).length,
    lineageEdgesAccountTotal: afterSnapshot?.counts.lineageEdges ?? beforeSnapshot.counts.lineageEdges,
  };

  const report = {
    schemaVersion: 1,
    repairVersion: REPAIR_VERSION,
    mode,
    runStartedAt,
    runCompletedAt: new Date().toISOString(),
    firebaseProjectId: FIREBASE_PROJECT_ID,
    productionBackendVerified: true,
    emulatorEnvironmentVerifiedDisabled: true,
    accountId: ACCOUNT_ID,
    ledgerProjectId: LEDGER_PROJECT_ID,
    furnishingsCategoryId: FURNISHINGS_CATEGORY_ID,
    evidence: {
      path: path.resolve(args.evidencePath),
      sha256: evidence.rawHash,
      receiptCount: evidence.receipts.length,
      exactDateTotalStoreTransactionMatches: plan.exactReceipts.length,
      unmatchedReceipts: plan.unmatchedReceipts,
    },
    planHash: plan.planHash,
    dryRunProposals,
    repairedItems,
    skippedItems,
    remainingGaps: afterPlan.skipped,
    specialSaleMovement: publicPlanRow(plan.specialMovement),
    receiptLineAvailability: plan.receiptLineAvailability,
    counts: {
      before: beforeCounts,
      after: afterCounts,
      proposedEdges: plan.planRows.length,
      createdEdges: execution.createdEdgeIds.length,
      alreadyPresentDeterministicEdges: execution.alreadyPresentEdgeIds.length,
      skippedItems: skippedItems.length,
      remainingSourcePredecessorGaps: afterPlan.sourceMissing.length,
      remainingSaleMovementGaps: afterCounts.inventorySaleMembershipWithoutSaleMovement,
    },
    execution,
    invariantVerification,
    snapshots: {
      before: `${prefix}_before.json`,
      after: afterSnapshot ? `${prefix}_after.json` : null,
      beforeDigests: beforeSnapshot.digests,
      afterDigests: afterSnapshot?.digests ?? null,
    },
    writeScope: [`accounts/${ACCOUNT_ID}/lineageEdges/{deterministicEdgeId}`],
    explicitlyUnchangedCollections: [
      `accounts/${ACCOUNT_ID}/items`,
      `accounts/${ACCOUNT_ID}/transactions`,
    ],
  };

  const reportPath = `${prefix}_report.json`;
  const csvPath = `${prefix}_report.csv`;
  fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`);
  const csvRows = args.apply
    ? [...repairedItems, ...skippedItems]
    : [...dryRunProposals.map((row) => ({ ...row, status: 'proposed' })), ...skippedItems];
  writeCsv(csvPath, csvRows);

  console.log(JSON.stringify({
    mode,
    planHash: plan.planHash,
    counts: report.counts,
    reportPath,
    csvPath,
    beforeSnapshotPath: report.snapshots.before,
    afterSnapshotPath: report.snapshots.after,
    invariantVerification,
  }, null, 2));
}

main().catch((error) => {
  console.error(error?.stack ?? error);
  process.exitCode = 1;
});
