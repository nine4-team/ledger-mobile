#!/usr/bin/env node
/**
 * Read-only audit for item documents that may actually represent non-item
 * receipt lines on active projects.
 *
 * Required:
 *   LEDGER_ACCOUNT_ID=... GOOGLE_APPLICATION_CREDENTIALS=... \
 *     node scripts/audit-non-item-receipt-lines.mjs
 *
 * Optional:
 *   FIREBASE_PROJECT_ID=ledger-nine4
 *   AUDIT_OUTPUT_DIR=docs/plans/non-item-receipt-line-audit-runs
 */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import admin from 'firebase-admin';

const FIREBASE_PROJECT_ID = process.env.FIREBASE_PROJECT_ID || 'ledger-nine4';
const ACCOUNT_ID = process.env.LEDGER_ACCOUNT_ID;
const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.dirname(SCRIPT_DIR);
const OUTPUT_DIR = process.env.AUDIT_OUTPUT_DIR
  || path.join(REPO_ROOT, 'docs', 'plans', 'non-item-receipt-line-audit-runs');

if (!ACCOUNT_ID) {
  throw new Error('LEDGER_ACCOUNT_ID is required.');
}

admin.initializeApp({
  credential: admin.credential.applicationDefault(),
  projectId: FIREBASE_PROJECT_ID,
});
const db = admin.firestore();

const CREDIT_WORDS = [
  'discount',
  'coupon',
  'credit',
  'promotion',
  'promotional',
  'promo',
  'reward',
  'savings',
];

const HIGH_CONFIDENCE_PATTERNS = [
  { key: 'shipping', pattern: /\bshipping\b/i },
  { key: 'handling', pattern: /\bhandling\b/i },
  { key: 'delivery', pattern: /^(?:.*\s)?delivery$|\bdelivery\s+(?:charge|fee|service)\b/i },
  { key: 'freight', pattern: /\bfreight\b/i },
  { key: 'return-protection', pattern: /\breturn\s+protection\b/i },
  { key: 'protection', pattern: /\bprotection(?:\s+plan)?\b/i },
  { key: 'warranty', pattern: /\bwarrant(?:y|ies)\b/i },
  { key: 'insurance', pattern: /\binsurance\b/i },
  { key: 'discount', pattern: /\bdiscount\b/i },
  { key: 'coupon', pattern: /\bcoupon\b/i },
  { key: 'credit', pattern: /\bcredit\b/i },
  { key: 'promotion', pattern: /\bpromo(?:tion(?:al)?)?\b/i },
  { key: 'reward', pattern: /\brewards?\b/i },
  { key: 'savings', pattern: /\bsavings?\b/i },
  { key: 'fee', pattern: /\b(?:service|processing|restocking|environmental|shipping|delivery)\s+fee\b/i },
  { key: 'tax', pattern: /\b(?:sales|use)\s+tax\b/i },
];

const REVIEW_PATTERNS = [
  { key: 'installation', pattern: /\binstallation\b|\binstall\s+(?:fee|service|labor)\b/i },
  { key: 'assembly', pattern: /\bassembly\s+(?:fee|service|labor)\b|^assembly$/i },
  { key: 'labor', pattern: /\blabor\b/i },
  { key: 'haul-away', pattern: /\bha(?:ul|uling)[ -]?away\b/i },
  { key: 'setup', pattern: /\bsetup\s+(?:fee|service|labor)\b/i },
  { key: 'membership', pattern: /\bmembership\b/i },
  { key: 'gift-card', pattern: /\bgift\s+card\b/i },
];

const EXPLICIT_NON_ITEM_NOTE_PATTERN = /\bnon[- ]physical\b|\bnot\s+(?:a\s+)?physical\b|\bneeded to reconcile\b|\bcreated\s+to\s+reconcile\b/i;

function isoDate(value) {
  return value?.toDate?.()?.toISOString?.() ?? value ?? null;
}

function cents(value) {
  return typeof value === 'number' && Number.isFinite(value)
    ? Math.round(value)
    : null;
}

function normalized(value) {
  return String(value ?? '').trim().toLowerCase();
}

function isInventorySource(value) {
  return normalized(value).endsWith(' inventory');
}

function itemPriceForTransaction(item, transaction) {
  const type = normalized(transaction.type ?? transaction.transactionType);
  const usesProjectPrice = (type === 'purchase' || type === 'return')
    && typeof transaction.projectId === 'string'
    && isInventorySource(transaction.source);
  const purchasePrice = cents(item.purchasePriceCents) ?? 0;
  if (!usesProjectPrice) return purchasePrice;
  return Math.max(purchasePrice, cents(item.projectPriceCents) ?? 0);
}

function detectedKinds(name, patterns) {
  return patterns
    .filter(({ pattern }) => pattern.test(name))
    .map(({ key }) => key);
}

function proposedDirection(name) {
  const text = normalized(name);
  return CREDIT_WORDS.some((word) => text.includes(word)) ? 'credit' : 'charge';
}

function categoryType(category) {
  return normalized(category?.metadata?.categoryType) || 'general';
}

function compactTransaction(doc, data, project, category) {
  return {
    id: doc.id,
    path: doc.ref.path,
    projectId: data.projectId ?? null,
    projectName: project?.name ?? null,
    categoryId: data.budgetCategoryId ?? null,
    categoryName: category?.name ?? null,
    categoryType: categoryType(category),
    type: data.type ?? data.transactionType ?? null,
    source: data.source ?? null,
    transactionDate: data.transactionDate ?? null,
    amountCents: cents(data.amountCents),
    subtotalCents: cents(data.subtotalCents),
    taxRatePct: typeof data.taxRatePct === 'number' ? data.taxRatePct : null,
    isComplete: data.isComplete ?? null,
    itemIds: Array.isArray(data.itemIds) ? data.itemIds : [],
    discount: data.discount && typeof data.discount === 'object'
      ? { amountCents: cents(data.discount.amountCents) }
      : null,
    receiptAttachmentCount: [
      ...(Array.isArray(data.receiptImages) ? data.receiptImages : []),
      ...(Array.isArray(data.transactionImages) ? data.transactionImages : []),
    ].length,
    audit: data.audit && typeof data.audit === 'object'
      ? {
          resolvedSubtotalCents: cents(data.audit.resolvedSubtotalCents),
          itemsSumCents: cents(data.audit.itemsSumCents),
          discountCents: cents(data.audit.discountCents),
          varianceCents: cents(data.audit.varianceCents),
          variancePercent: data.audit.variancePercent ?? null,
        }
      : null,
    createdAt: isoDate(data.createdAt),
    updatedAt: isoDate(data.updatedAt),
  };
}

function attachmentCheckmarkReferences(documentPath, data, attachmentFields) {
  const references = [];
  for (const field of attachmentFields) {
    const attachments = Array.isArray(data[field]) ? data[field] : [];
    attachments.forEach((attachment, attachmentIndex) => {
      const checkmarks = Array.isArray(attachment?.checkmarks) ? attachment.checkmarks : [];
      checkmarks.forEach((checkmark, checkmarkIndex) => {
        const ids = [
          checkmark?.itemId,
          ...(Array.isArray(checkmark?.itemIds) ? checkmark.itemIds : []),
        ].filter(Boolean);
        for (const itemId of new Set(ids)) {
          references.push({
            itemId,
            documentPath,
            field,
            attachmentIndex,
            checkmarkIndex,
            checkmarkId: checkmark?.id ?? null,
          });
        }
      });
    });
  }
  return references;
}

async function main() {
  const accountRef = db.doc(`accounts/${ACCOUNT_ID}`);
  const [
    accountSnap,
    projectsSnap,
    transactionsSnap,
    itemsSnap,
    categoriesSnap,
    edgesSnap,
    invoicesSnap,
    spacesSnap,
  ] = await Promise.all([
    accountRef.get(),
    accountRef.collection('projects').get(),
    accountRef.collection('transactions').get(),
    accountRef.collection('items').get(),
    accountRef.collection('presets').doc('default').collection('budgetCategories').get(),
    accountRef.collection('lineageEdges').get(),
    accountRef.collection('invoices').get(),
    accountRef.collection('spaces').get(),
  ]);

  if (!accountSnap.exists) {
    throw new Error(`Account ${ACCOUNT_ID} does not exist.`);
  }

  const account = accountSnap.data() ?? {};
  const projects = new Map(projectsSnap.docs
    .filter((doc) => doc.data()?.isArchived !== true)
    .map((doc) => [doc.id, { id: doc.id, ...doc.data() }]));
  const categories = new Map(categoriesSnap.docs
    .map((doc) => [doc.id, { id: doc.id, ...doc.data() }]));

  const transactions = new Map();
  for (const doc of transactionsSnap.docs) {
    const data = doc.data() ?? {};
    const project = projects.get(data.projectId);
    if (!project) continue;
    const category = categories.get(data.budgetCategoryId);
    transactions.set(doc.id, {
      raw: data,
      compact: compactTransaction(doc, data, project, category),
    });
  }

  const items = new Map(itemsSnap.docs.map((doc) => [doc.id, {
    id: doc.id,
    path: doc.ref.path,
    ...doc.data(),
  }]));

  const transactionMembershipsByItem = new Map();
  for (const doc of transactionsSnap.docs) {
    const data = doc.data() ?? {};
    for (const itemId of Array.isArray(data.itemIds) ? data.itemIds : []) {
      const memberships = transactionMembershipsByItem.get(itemId) ?? [];
      memberships.push({
        transactionId: doc.id,
        transactionPath: doc.ref.path,
        projectId: data.projectId ?? null,
        source: data.source ?? null,
        type: data.type ?? data.transactionType ?? null,
        status: data.status ?? null,
      });
      transactionMembershipsByItem.set(itemId, memberships);
    }
  }

  const invoiceDependenciesByItem = new Map();
  for (const doc of invoicesSnap.docs) {
    const data = doc.data() ?? {};
    const flatMembership = new Set(Array.isArray(data.itemIds) ? data.itemIds : []);
    const lineMembership = new Map();
    for (const line of Array.isArray(data.lines) ? data.lines : []) {
      if (normalized(line?.sourceType) !== 'item' || !line?.sourceId) continue;
      const lines = lineMembership.get(line.sourceId) ?? [];
      lines.push({
        lineId: line.id ?? null,
        amountCents: cents(line.amountCents),
        sign: line.sign ?? null,
        snapshotName: line.snapshotName ?? null,
        budgetCategoryId: line.budgetCategoryId ?? null,
      });
      lineMembership.set(line.sourceId, lines);
    }
    const itemIds = new Set([...flatMembership, ...lineMembership.keys()]);
    for (const itemId of itemIds) {
      const dependencies = invoiceDependenciesByItem.get(itemId) ?? [];
      dependencies.push({
        invoiceId: doc.id,
        invoicePath: doc.ref.path,
        projectId: data.projectId ?? null,
        status: data.status ?? null,
        inFlatItemIds: flatMembership.has(itemId),
        lines: lineMembership.get(itemId) ?? [],
      });
      invoiceDependenciesByItem.set(itemId, dependencies);
    }
  }

  const lineageDependenciesByItem = new Map();
  for (const doc of edgesSnap.docs) {
    const data = doc.data() ?? {};
    if (!data.itemId) continue;
    const dependencies = lineageDependenciesByItem.get(data.itemId) ?? [];
    dependencies.push({
      edgeId: doc.id,
      edgePath: doc.ref.path,
      movementKind: data.movementKind ?? null,
      fromTransactionId: data.fromTransactionId ?? null,
      toTransactionId: data.toTransactionId ?? null,
      fromProjectId: data.fromProjectId ?? null,
      toProjectId: data.toProjectId ?? null,
      createdAt: isoDate(data.createdAt),
    });
    lineageDependenciesByItem.set(data.itemId, dependencies);
  }

  const imageCheckmarkDependenciesByItem = new Map();
  const checkmarkReferences = [
    ...transactionsSnap.docs.flatMap((doc) => attachmentCheckmarkReferences(
      doc.ref.path,
      doc.data() ?? {},
      ['receiptImages', 'otherImages', 'transactionImages'],
    )),
    ...itemsSnap.docs.flatMap((doc) => attachmentCheckmarkReferences(
      doc.ref.path,
      doc.data() ?? {},
      ['images'],
    )),
    ...spacesSnap.docs.flatMap((doc) => attachmentCheckmarkReferences(
      doc.ref.path,
      doc.data() ?? {},
      ['images'],
    )),
  ];
  for (const reference of checkmarkReferences) {
    const dependencies = imageCheckmarkDependenciesByItem.get(reference.itemId) ?? [];
    dependencies.push(reference);
    imageCheckmarkDependenciesByItem.set(reference.itemId, dependencies);
  }

  const lineageBySourceTransaction = new Map();
  for (const doc of edgesSnap.docs) {
    const data = doc.data() ?? {};
    if (!['returned', 'sold', 'soldToInventory'].includes(data.movementKind)) continue;
    if (!transactions.has(data.fromTransactionId) || !data.itemId) continue;
    const rows = lineageBySourceTransaction.get(data.fromTransactionId) ?? [];
    rows.push({
      edgeId: doc.id,
      movementKind: data.movementKind,
      itemId: data.itemId,
      createdAt: isoDate(data.createdAt),
    });
    lineageBySourceTransaction.set(data.fromTransactionId, rows);
  }

  const candidates = [];
  const legacyDiscountTransactions = [];
  const transactionAnalyses = [];
  const inspectedItemIds = new Set();

  for (const [transactionId, entry] of transactions) {
    const transaction = entry.raw;
    const compact = entry.compact;
    if (compact.categoryType !== 'itemized') continue;

    if (compact.discount?.amountCents != null) {
      legacyDiscountTransactions.push(compact);
    }

    const membership = [];
    for (const itemId of compact.itemIds) {
      membership.push({ itemId, membership: 'linked', movementKind: null });
    }
    for (const edge of lineageBySourceTransaction.get(transactionId) ?? []) {
      if (membership.some((row) => row.itemId === edge.itemId)) continue;
      membership.push({
        itemId: edge.itemId,
        membership: 'lineage',
        movementKind: edge.movementKind,
      });
    }

    let calculatedItemTotalCents = 0;
    let detectedCandidateTotalCents = 0;
    const transactionCandidateIds = [];
    const itemSummaries = [];

    for (const membershipRow of membership) {
      const item = items.get(membershipRow.itemId);
      if (!item) continue;
      inspectedItemIds.add(item.id);
      const name = String(item.name ?? item.description ?? '').trim();
      const highConfidenceKinds = detectedKinds(name, HIGH_CONFIDENCE_PATTERNS);
      const reviewKinds = detectedKinds(name, REVIEW_PATTERNS);
      const notesExplicitlyNonItem = EXPLICIT_NON_ITEM_NOTE_PATTERN.test(String(item.notes ?? ''));
      const kinds = [...new Set([...highConfidenceKinds, ...reviewKinds])];
      const priceCents = itemPriceForTransaction(item, transaction);
      calculatedItemTotalCents += priceCents;
      itemSummaries.push({
        id: item.id,
        name,
        membership: membershipRow.membership,
        movementKind: membershipRow.movementKind,
        auditPriceCents: priceCents,
        purchasePriceCents: cents(item.purchasePriceCents),
        projectPriceCents: cents(item.projectPriceCents),
        sku: item.sku ?? null,
        notes: item.notes ?? null,
      });
      if (kinds.length === 0 && !notesExplicitlyNonItem) continue;

      detectedCandidateTotalCents += priceCents;
      transactionCandidateIds.push(item.id);
      const direction = proposedDirection(name);
      const confidence = notesExplicitlyNonItem || highConfidenceKinds.length > 0
        ? 'high'
        : 'review';
      candidates.push({
        confidence,
        reason: notesExplicitlyNonItem
          ? `Item notes explicitly describe a non-physical/reconciliation line; name signals: ${kinds.join(', ') || 'none'}`
          : `${confidence === 'high' ? 'Name matches' : 'Name may match'} non-item receipt-line language: ${kinds.join(', ')}`,
        detectedKinds: kinds,
        proposedDirection: direction,
        proposedSignedAmountCents: direction === 'credit' ? -Math.abs(priceCents) : priceCents,
        membership: membershipRow.membership,
        movementKind: membershipRow.movementKind,
        item: {
          id: item.id,
          path: item.path,
          name,
          description: item.description ?? null,
          projectId: item.projectId ?? null,
          transactionId: item.transactionId ?? null,
          budgetCategoryId: item.budgetCategoryId ?? null,
          status: item.status ?? null,
          source: item.source ?? null,
          purchasePriceCents: cents(item.purchasePriceCents),
          projectPriceCents: cents(item.projectPriceCents),
          auditPriceCents: priceCents,
          sku: item.sku ?? null,
          spaceId: item.spaceId ?? null,
          imageCount: Array.isArray(item.images) ? item.images.length : 0,
          notes: item.notes ?? null,
          createdBy: item.createdBy ?? null,
          createdAt: isoDate(item.createdAt),
        },
        transaction: compact,
      });
    }

    if (transactionCandidateIds.length > 0 || compact.discount?.amountCents != null) {
      const legacyDiscountCents = compact.discount?.amountCents ?? 0;
      const residualAfterLegacyDiscountCents = compact.subtotalCents == null
        ? null
        : compact.subtotalCents - (calculatedItemTotalCents - legacyDiscountCents);
      transactionAnalyses.push({
        transaction: compact,
        calculatedItemTotalCents,
        storedAuditItemTotalCents: compact.audit?.itemsSumCents ?? null,
        detectedCandidateItemIds: transactionCandidateIds,
        detectedCandidateTotalCents,
        remainingPhysicalItemTotalCents: calculatedItemTotalCents - detectedCandidateTotalCents,
        legacyDiscountCents,
        residualAfterLegacyDiscountCents,
        legacyDiscountMigrationAssessment: legacyDiscountCents === 0
          ? null
          : residualAfterLegacyDiscountCents === 0
            ? 'exact-credit-line-migration'
            : residualAfterLegacyDiscountCents === legacyDiscountCents
              ? 'discount-already-reflected-or-subtotal-needs-correction'
              : 'additional-receipt-line-or-subtotal-review-required',
        itemSummaries,
      });
    }
  }

  const currentItemsOnActiveProjects = [...items.values()]
    .filter((item) => projects.has(item.projectId));
  const currentItemsWithoutTransactionCoverage = currentItemsOnActiveProjects
    .filter((item) => !inspectedItemIds.has(item.id));

  for (const candidate of candidates) {
    const itemId = candidate.item.id;
    candidate.dependencies = {
      transactionMemberships: transactionMembershipsByItem.get(itemId) ?? [],
      invoices: invoiceDependenciesByItem.get(itemId) ?? [],
      lineageEdges: lineageDependenciesByItem.get(itemId) ?? [],
      imageCheckmarks: imageCheckmarkDependenciesByItem.get(itemId) ?? [],
    };
  }

  const report = {
    firestoreProjectId: FIREBASE_PROJECT_ID,
    account: {
      id: ACCOUNT_ID,
      name: account.name ?? account.businessName ?? null,
    },
    generatedAt: new Date().toISOString(),
    scope: 'Read-only audit of itemized transactions belonging to active projects.',
    summary: {
      activeProjectCount: projects.size,
      activeProjectTransactionCount: transactions.size,
      activeProjectItemizedTransactionCount: [...transactions.values()]
        .filter((entry) => entry.compact.categoryType === 'itemized').length,
      currentItemsOnActiveProjects: currentItemsOnActiveProjects.length,
      itemRecordsInspectedThroughItemizedTransactionMembership: inspectedItemIds.size,
      currentItemsWithoutItemizedTransactionCoverage: currentItemsWithoutTransactionCoverage.length,
      highConfidenceItemCandidates: candidates.filter((candidate) => candidate.confidence === 'high').length,
      reviewItemCandidates: candidates.filter((candidate) => candidate.confidence === 'review').length,
      affectedTransactions: new Set(candidates.map((candidate) => candidate.transaction.id)).size,
      legacyDiscountTransactions: legacyDiscountTransactions.length,
      candidateItemsOnInvoices: new Set(candidates
        .filter((candidate) => candidate.dependencies.invoices.length > 0)
        .map((candidate) => candidate.item.id)).size,
      candidateItemsWithMovementLineage: new Set(candidates
        .filter((candidate) => candidate.dependencies.lineageEdges.some((edge) =>
          ['returned', 'sold', 'soldToInventory'].includes(edge.movementKind)))
        .map((candidate) => candidate.item.id)).size,
      candidateItemsReferencedByImageCheckmarks: new Set(candidates
        .filter((candidate) => candidate.dependencies.imageCheckmarks.length > 0)
        .map((candidate) => candidate.item.id)).size,
    },
    activeProjects: [...projects.values()]
      .map((project) => ({
        id: project.id,
        name: project.name ?? null,
        clientName: project.clientName ?? null,
        isArchived: project.isArchived ?? null,
      }))
      .sort((a, b) => String(a.name).localeCompare(String(b.name))),
    itemCandidates: candidates.sort((a, b) =>
      a.confidence.localeCompare(b.confidence)
      || String(a.transaction.projectName).localeCompare(String(b.transaction.projectName))
      || String(a.transaction.transactionDate).localeCompare(String(b.transaction.transactionDate))
      || String(a.item.name).localeCompare(String(b.item.name))),
    highConfidenceItemCandidates: candidates.filter((candidate) => candidate.confidence === 'high').sort((a, b) =>
      String(a.transaction.projectName).localeCompare(String(b.transaction.projectName))
      || String(a.transaction.transactionDate).localeCompare(String(b.transaction.transactionDate))
      || String(a.item.name).localeCompare(String(b.item.name))),
    reviewItemCandidates: candidates.filter((candidate) => candidate.confidence === 'review').sort((a, b) =>
      String(a.transaction.projectName).localeCompare(String(b.transaction.projectName))
      || String(a.transaction.transactionDate).localeCompare(String(b.transaction.transactionDate))
      || String(a.item.name).localeCompare(String(b.item.name))),
    legacyDiscountTransactions: legacyDiscountTransactions.sort((a, b) =>
      String(a.projectName).localeCompare(String(b.projectName))
      || String(a.transactionDate).localeCompare(String(b.transactionDate))),
    affectedTransactionAnalysis: transactionAnalyses.sort((a, b) =>
      String(a.transaction.projectName).localeCompare(String(b.transaction.projectName))
      || String(a.transaction.transactionDate).localeCompare(String(b.transaction.transactionDate))),
    currentItemsWithoutItemizedTransactionCoverage: currentItemsWithoutTransactionCoverage.map((item) => ({
      id: item.id,
      path: item.path,
      name: item.name ?? item.description ?? null,
      projectId: item.projectId ?? null,
      projectName: projects.get(item.projectId)?.name ?? null,
      transactionId: item.transactionId ?? null,
      budgetCategoryId: item.budgetCategoryId ?? null,
      status: item.status ?? null,
      source: item.source ?? null,
      purchasePriceCents: cents(item.purchasePriceCents),
      projectPriceCents: cents(item.projectPriceCents),
      sku: item.sku ?? null,
      spaceId: item.spaceId ?? null,
      imageCount: Array.isArray(item.images) ? item.images.length : 0,
      notes: item.notes ?? null,
      createdAt: isoDate(item.createdAt),
    })),
    reviewLimitations: [
      'Name matching can identify obvious non-item concepts but cannot prove physicality.',
      'Receipt attachments are counted but their contents are not inspected by this script.',
      'Items outside itemized transaction membership are counted but not classified as migration candidates.',
      'A migration must preserve movement lineage and invoice dependencies before deleting or detaching any item.',
    ],
  };

  fs.mkdirSync(OUTPUT_DIR, { recursive: true });
  const timestamp = report.generatedAt.replace(/[:.]/g, '-');
  const outputPath = path.join(OUTPUT_DIR, `${timestamp}.json`);
  fs.writeFileSync(outputPath, JSON.stringify(report, null, 2));

  console.log(JSON.stringify({ outputPath, ...report.summary }, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
