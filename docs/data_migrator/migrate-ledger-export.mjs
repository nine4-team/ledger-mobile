#!/usr/bin/env node
/**
 * Migrate legacy Supabase export -> Firestore import bundle (JSON).
 *
 * Usage:
 *   node docs/data_migrator/migrate-ledger-export.mjs <export.json> \
 *     [--out <out_dir>] \
 *     [--storage <storage_export_dir>] \
 *     [--check-storage] \
 *     [--version <migration_version>]
 */

import fs from 'node:fs/promises';
import path from 'node:path';
import { createHash } from 'node:crypto';

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
    outDir: flags.get('out') || null,
    storageDir: flags.get('storage') || null,
    checkStorage: Boolean(flags.get('check-storage')),
    migrationVersion: flags.get('version') || 'v1',
  };
}

function getTable(exportJson, name) {
  const tables = exportJson?.tables;
  const arr = tables?.[name];
  return Array.isArray(arr) ? arr : [];
}

function isNonEmptyString(v) {
  return typeof v === 'string' && v.trim().length > 0;
}

function normalizeOptionalString(v) {
  if (v === null || v === undefined) return null;
  if (typeof v !== 'string') return v;
  const trimmed = v.trim();
  return trimmed.length === 0 ? null : trimmed;
}

function normalizeOptionalId(v) {
  if (!isNonEmptyString(v)) return null;
  return v.trim();
}

function parseDecimalToCents(input) {
  if (input === null || input === undefined) return { cents: null, ok: true };
  const raw = typeof input === 'number' ? String(input) : String(input);
  const trimmed = raw.trim();
  if (trimmed.length === 0) return { cents: null, ok: true };
  if (!/^-?\d+(\.\d+)?$/.test(trimmed)) {
    return { cents: null, ok: false };
  }
  const sign = trimmed.startsWith('-') ? -1n : 1n;
  const unsigned = trimmed.replace(/^-/, '');
  const [wholePart, fracPartRaw = ''] = unsigned.split('.');
  const frac = `${fracPartRaw}000`.slice(0, 3);
  const firstTwo = frac.slice(0, 2);
  const third = frac.slice(2, 3);
  const whole = BigInt(wholePart || '0');
  let cents = whole * 100n + BigInt(firstTwo || '0');
  if (third && Number(third) >= 5) {
    cents += 1n;
  }
  cents *= sign;
  const asNumber = Number(cents);
  if (!Number.isSafeInteger(asNumber)) {
    return { cents: null, ok: false };
  }
  return { cents: asNumber, ok: true };
}

function parseNumber(input) {
  if (input === null || input === undefined) return null;
  if (typeof input === 'number' && Number.isFinite(input)) return input;
  if (typeof input === 'string' && input.trim().length > 0) {
    const num = Number(input);
    return Number.isFinite(num) ? num : null;
  }
  return null;
}

function stableStringify(value, space = 2) {
  const seen = new WeakSet();
  const normalize = (val) => {
    if (val === null || typeof val !== 'object') return val;
    if (seen.has(val)) return val;
    seen.add(val);
    if (Array.isArray(val)) return val.map(normalize);
    const out = {};
    for (const key of Object.keys(val).sort()) {
      out[key] = normalize(val[key]);
    }
    return out;
  };
  return JSON.stringify(normalize(value), null, space);
}

function extractBucketAndKeyFromUrl(url) {
  if (!isNonEmptyString(url)) return null;
  const marker = '/storage/v1/object/public/';
  const idx = url.indexOf(marker);
  if (idx === -1) return null;
  const rest = url.slice(idx + marker.length);
  const [bucket, ...keyParts] = rest.split('/');
  if (!bucket || keyParts.length === 0) return null;
  return { bucket, key: keyParts.join('/') };
}

function guessMimeTypeFromUrl(url) {
  if (!isNonEmptyString(url)) return null;
  const lower = url.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.gif')) return 'image/gif';
  if (lower.endsWith('.pdf')) return 'application/pdf';
  return null;
}

function guessPurchasedBy(paymentMethod) {
  if (!isNonEmptyString(paymentMethod)) return null;
  const lower = paymentMethod.toLowerCase();
  if (lower.includes('client')) return 'Client';
  if (lower.includes('design') || lower.includes('business')) return 'Design Business';
  return null;
}

function mapStatus(disposition) {
  if (!isNonEmptyString(disposition)) return null;
  const normalized = disposition.trim().toLowerCase();
  if (['to purchase', 'purchased', 'to return', 'returned'].includes(normalized)) {
    return normalized;
  }
  return null;
}

function mapTransactionStatus(status) {
  if (!isNonEmptyString(status)) return null;
  const normalized = status.trim().toLowerCase();
  if (['pending', 'completed', 'canceled'].includes(normalized)) {
    return normalized;
  }
  return null;
}

function mapCategoryType(category) {
  const slug = normalizeOptionalString(category?.slug);
  const name = normalizeOptionalString(category?.name);
  const metadata = category?.metadata;
  if (slug === 'design-fee' || name === 'Design Fee') return 'fee';
  if (slug === 'furnishings' || name === 'Furnishings') return 'itemized';
  if (metadata && typeof metadata === 'object') {
    if (metadata.categoryType && ['standard', 'itemized', 'fee'].includes(metadata.categoryType)) {
      return metadata.categoryType;
    }
    if (metadata.itemizationEnabled === true) return 'itemized';
  }
  return 'standard';
}

async function fileExists(p) {
  try {
    await fs.access(p);
    return true;
  } catch {
    return false;
  }
}

async function main() {
  const { exportPath, outDir, storageDir, checkStorage, migrationVersion } = parseArgs(process.argv);

  if (!exportPath) {
    console.error('Missing export path.\n');
    console.error(
      'Usage: node docs/data_migrator/migrate-ledger-export.mjs <export.json> [--out out_dir] [--storage dir]'
    );
    process.exitCode = 2;
    return;
  }

  const raw = await fs.readFile(exportPath, 'utf8');
  const exportJson = JSON.parse(raw);
  const exportFilename = path.basename(exportPath);

  const accounts = getTable(exportJson, 'public.accounts');
  const users = getTable(exportJson, 'public.users');
  const projects = getTable(exportJson, 'public.projects');
  const spaces = getTable(exportJson, 'public.spaces');
  const templates = getTable(exportJson, 'public.space_templates');
  const items = getTable(exportJson, 'public.items');
  const transactions = getTable(exportJson, 'public.transactions');
  const edges = getTable(exportJson, 'public.item_lineage_edges');
  const invitations = getTable(exportJson, 'public.invitations');
  const accountPresets = getTable(exportJson, 'public.account_presets');

  const account = accounts[0] || {};
  const accountId = exportJson?.scope?.accountId || account?.id;
  if (!accountId) {
    throw new Error('Missing accountId in export.');
  }

  const defaultUserId =
    normalizeOptionalId(account?.created_by) || normalizeOptionalId(users?.[0]?.id) || 'unknown-user';

  const projectIdSet = new Set(projects.map((p) => p.id).filter(Boolean));
  const spaceIdSet = new Set(spaces.map((s) => s.id).filter(Boolean));

  const itemIdToDocId = new Map();
  const itemUuidToDocId = new Map();
  for (const item of items) {
    const itemId = normalizeOptionalId(item?.item_id);
    const itemUuid = normalizeOptionalId(item?.id);
    const docId = itemId || itemUuid;
    if (!docId) continue;
    if (itemId) itemIdToDocId.set(itemId, docId);
    if (itemUuid) itemUuidToDocId.set(itemUuid, docId);
  }

  const txIdToDocId = new Map();
  for (const tx of transactions) {
    const rowId = normalizeOptionalId(tx?.id);
    const domainId = normalizeOptionalId(tx?.transaction_id);
    const docId = domainId || rowId;
    if (!docId) continue;
    if (rowId) txIdToDocId.set(rowId, docId);
    if (domainId) txIdToDocId.set(domainId, docId);
  }

  const warnings = [];
  const errors = [];

  const mediaManifest = new Map();

  const registerMedia = async (media, options) => {
    if (!media || typeof media !== 'object') return null;
    const url = normalizeOptionalString(media.url);
    if (!url) return null;

    const parsed = extractBucketAndKeyFromUrl(url);
    const mediaKey = parsed ? `${parsed.bucket}/${parsed.key}` : url;
    const mediaId = createHash('sha256').update(mediaKey).digest('hex');
    const contentType = normalizeOptionalString(media.mimeType);
    const inferredContentType = contentType || guessMimeTypeFromUrl(url);

    let kind = 'image';
    if (options?.allowPdf && inferredContentType && inferredContentType.toLowerCase().includes('pdf')) {
      kind = 'pdf';
    }
    if (!options?.allowPdf && inferredContentType && !inferredContentType.toLowerCase().startsWith('image/')) {
      warnings.push({
        code: 'unsupported_media_kind',
        message: 'Skipping non-image media for image-only field.',
        details: { url, contentType: inferredContentType, field: options?.field, ownerPath: options?.ownerPath },
      });
      return null;
    }

    let localPath = null;
    let exists = null;
    if (storageDir && parsed) {
      localPath = path.join(storageDir, parsed.bucket, parsed.key);
      if (checkStorage) {
        exists = await fileExists(localPath);
        if (!exists) {
          warnings.push({
            code: 'missing_storage_object',
            message: 'Media file not found in storage export directory.',
            details: { bucket: parsed.bucket, key: parsed.key, localPath },
          });
        }
      }
    }

    const manifestEntry = {
      mediaId,
      kind,
      contentType: inferredContentType || null,
      sourceUrl: url,
      storage: parsed
        ? {
            bucket: parsed.bucket,
            key: parsed.key,
            localPath,
            exists,
          }
        : null,
      owner: {
        path: options?.ownerPath || null,
        field: options?.field || null,
      },
    };

    if (!mediaManifest.has(mediaId)) {
      mediaManifest.set(mediaId, manifestEntry);
    }

    return {
      url: `offline://${mediaId}`,
      kind,
      contentType: inferredContentType || undefined,
      isPrimary: media.isPrimary === true ? true : undefined,
    };
  };

  const resolveTransactionId = (value, context) => {
    const ref = normalizeOptionalId(value);
    if (!ref) return null;
    const resolved = txIdToDocId.get(ref) || null;
    if (!resolved) {
      warnings.push({
        code: 'missing_transaction_ref',
        message: 'Transaction reference could not be resolved; set to null.',
        details: { ref, ...context },
      });
    }
    return resolved;
  };

  const resolveItemId = (value, context) => {
    const ref = normalizeOptionalId(value);
    if (!ref) return null;
    const resolved = itemIdToDocId.get(ref) || null;
    if (!resolved) {
      warnings.push({
        code: 'missing_item_ref',
        message: 'Item reference could not be resolved; omitted.',
        details: { ref, ...context },
      });
    }
    return resolved;
  };

  const addDoc = (documents, pathValue, data, counts) => {
    documents.push({ path: pathValue, data });
    const collection = pathValue.split('/').slice(0, -1).join('/');
    counts[collection] = (counts[collection] ?? 0) + 1;
  };

  const documents = [];
  const counts = {};

  const toAuditFields = (row, overrides = {}) => {
    const createdAt = normalizeOptionalString(row?.created_at) || null;
    const updatedAt =
      normalizeOptionalString(row?.updated_at) ||
      normalizeOptionalString(row?.last_updated) ||
      createdAt ||
      null;
    return {
      createdAt,
      updatedAt,
      deletedAt: null,
      createdBy: normalizeOptionalId(row?.created_by) || defaultUserId,
      updatedBy: normalizeOptionalId(row?.updated_by) || normalizeOptionalId(row?.created_by) || null,
      ...overrides,
    };
  };

  const presets = accountPresets?.[0]?.presets || {};
  const presetCategories = Array.isArray(presets.budget_categories) ? presets.budget_categories : [];
  const presetCategoryIds = new Set(presetCategories.map((c) => c.id).filter(Boolean));
  const furnishingsCategory = presetCategories.find(
    (c) => normalizeOptionalString(c?.slug) === 'furnishings' || normalizeOptionalString(c?.name) === 'Furnishings'
  );
  const furnishingsCategoryId = normalizeOptionalId(furnishingsCategory?.id) || null;

  for (const category of presetCategories) {
    const categoryId = normalizeOptionalId(category?.id);
    if (!categoryId) continue;
    const legacyMetadata =
      category?.metadata && typeof category.metadata === 'object' ? category.metadata : null;
    const categoryType = mapCategoryType(category);
    const mappedMetadata =
      categoryType !== 'standard' || legacyMetadata
        ? {
            categoryType,
            ...(legacyMetadata?.excludeFromOverallBudget === true
              ? { excludeFromOverallBudget: true }
              : {}),
            ...(legacyMetadata ? { legacy: legacyMetadata } : {}),
          }
        : null;
    addDoc(
      documents,
      `accounts/${accountId}/presets/default/budgetCategories/${categoryId}`,
      {
        id: categoryId,
        accountId,
        projectId: null,
        name: category?.name || '',
        slug: category?.slug || '',
        isArchived: Boolean(category?.is_archived),
        metadata: mappedMetadata,
        ...toAuditFields(category),
      },
      counts
    );
  }

  const vendorDefaults = Array.isArray(presets.vendor_defaults) ? presets.vendor_defaults : [];
  if (vendorDefaults.length > 0) {
    addDoc(
      documents,
      `accounts/${accountId}/presets/default/vendors/default`,
      {
        vendors: vendorDefaults,
        ...toAuditFields(accountPresets?.[0] || {}),
      },
      counts
    );
  }

  for (const project of projects) {
    const projectId = normalizeOptionalId(project?.id);
    if (!projectId) continue;
    addDoc(
      documents,
      `accounts/${accountId}/projects/${projectId}`,
      {
        id: projectId,
        accountId,
        name: project?.name || '',
        clientName: project?.client_name || '',
        description: normalizeOptionalString(project?.description),
        mainImageUrl: normalizeOptionalString(project?.main_image_url),
        metadata: project?.metadata || null,
        ...toAuditFields(project, { createdBy: normalizeOptionalId(project?.created_by) || defaultUserId }),
      },
      counts
    );

    const budgetEntries = project?.budget_categories && typeof project.budget_categories === 'object'
      ? Object.entries(project.budget_categories)
      : [];
    for (const [categoryId, legacyBudget] of budgetEntries) {
      if (!presetCategoryIds.has(categoryId)) {
        warnings.push({
          code: 'missing_budget_category',
          message: 'Project budget references missing preset category.',
          details: { projectId, categoryId },
        });
        continue;
      }
      const { cents, ok } = parseDecimalToCents(legacyBudget);
      if (!ok) {
        warnings.push({
          code: 'invalid_budget_amount',
          message: 'Project budget amount could not be parsed; set to null.',
          details: { projectId, categoryId, legacyBudget },
        });
      }
      addDoc(
        documents,
        `accounts/${accountId}/projects/${projectId}/budgetCategories/${categoryId}`,
        {
          id: categoryId,
          budgetCents: ok ? cents : null,
          ...toAuditFields(project),
        },
        counts
      );
    }
  }

  for (const space of spaces) {
    const spaceId = normalizeOptionalId(space?.id);
    if (!spaceId) continue;
    const projectId = normalizeOptionalId(space?.project_id);
    const resolvedProjectId = projectIdSet.has(projectId) ? projectId : null;
    if (projectId && !resolvedProjectId) {
      warnings.push({
        code: 'missing_project_ref',
        message: 'Space project_id missing in export; set to null.',
        details: { spaceId, projectId },
      });
    }

    const images = [];
    if (Array.isArray(space?.images)) {
      for (const img of space.images) {
        // eslint-disable-next-line no-await-in-loop
        const attachment = await registerMedia(img, {
          allowPdf: false,
          ownerPath: `accounts/${accountId}/spaces/${spaceId}`,
          field: 'images',
        });
        if (attachment) images.push(attachment);
      }
    }

    addDoc(
      documents,
      `accounts/${accountId}/spaces/${spaceId}`,
      {
        id: spaceId,
        accountId,
        projectId: resolvedProjectId,
        name: space?.name || '',
        notes: normalizeOptionalString(space?.notes),
        images: images.length > 0 ? images : null,
        checklists: Array.isArray(space?.checklists) && space.checklists.length > 0 ? space.checklists : null,
        ...toAuditFields(space),
      },
      counts
    );
  }

  for (const template of templates) {
    const templateId = normalizeOptionalId(template?.id);
    if (!templateId) continue;
    const checklists = Array.isArray(template?.checklists)
      ? template.checklists.map((list) => ({
          ...list,
          items: Array.isArray(list?.items)
            ? list.items.map((item) => ({ ...item, isChecked: false }))
            : [],
        }))
      : null;
    addDoc(
      documents,
      `accounts/${accountId}/presets/default/spaceTemplates/${templateId}`,
      {
        id: templateId,
        accountId,
        name: template?.name || '',
        isArchived: Boolean(template?.is_archived),
        notes: normalizeOptionalString(template?.notes),
        checklists,
        ...toAuditFields(template),
      },
      counts
    );
  }

  const txCategoryById = new Map();
  for (const tx of transactions) {
    const txId = normalizeOptionalId(tx?.transaction_id) || normalizeOptionalId(tx?.id);
    const categoryId = normalizeOptionalId(tx?.category_id);
    if (txId && categoryId) {
      txCategoryById.set(txId, categoryId);
    }
  }

  for (const item of items) {
    const docId = normalizeOptionalId(item?.item_id) || normalizeOptionalId(item?.id);
    if (!docId) continue;
    const projectId = normalizeOptionalId(item?.project_id);
    const resolvedProjectId = projectIdSet.has(projectId) ? projectId : null;
    if (projectId && !resolvedProjectId) {
      warnings.push({
        code: 'missing_project_ref',
        message: 'Item project_id missing in export; set to null.',
        details: { itemId: docId, projectId },
      });
    }

    const spaceId = normalizeOptionalId(item?.space_id);
    const resolvedSpaceId = spaceIdSet.has(spaceId) ? spaceId : null;
    if (spaceId && !resolvedSpaceId) {
      warnings.push({
        code: 'missing_space_ref',
        message: 'Item space_id missing in export; set to null.',
        details: { itemId: docId, spaceId },
      });
    }

    const transactionId = resolveTransactionId(item?.transaction_id, { itemId: docId, field: 'transaction_id' });
    const latestTransactionId = resolveTransactionId(item?.latest_transaction_id, {
      itemId: docId,
      field: 'latest_transaction_id',
    });
    const originTransactionId = resolveTransactionId(item?.origin_transaction_id, {
      itemId: docId,
      field: 'origin_transaction_id',
    });

    const inheritedBudgetCategoryId = transactionId
      ? normalizeOptionalId(txCategoryById.get(transactionId)) || null
      : null;

    const { cents: purchasePriceCents, ok: purchasePriceOk } = parseDecimalToCents(item?.purchase_price);
    const { cents: projectPriceCents, ok: projectPriceOk } = parseDecimalToCents(item?.project_price);
    const { cents: marketValueCents, ok: marketValueOk } = parseDecimalToCents(item?.market_value);
    const { cents: taxAmountPurchasePriceCents, ok: taxAmountPurchaseOk } = parseDecimalToCents(
      item?.tax_amount_purchase_price
    );
    const { cents: taxAmountProjectPriceCents, ok: taxAmountProjectOk } = parseDecimalToCents(
      item?.tax_amount_project_price
    );

    if (!purchasePriceOk || !projectPriceOk || !marketValueOk || !taxAmountPurchaseOk || !taxAmountProjectOk) {
      warnings.push({
        code: 'invalid_money_value',
        message: 'Item contains invalid money values; set to null.',
        details: { itemId: docId },
      });
    }

    const images = [];
    if (Array.isArray(item?.images)) {
      for (const img of item.images) {
        // eslint-disable-next-line no-await-in-loop
        const attachment = await registerMedia(img, {
          allowPdf: false,
          ownerPath: `accounts/${accountId}/items/${docId}`,
          field: 'images',
        });
        if (attachment) images.push(attachment);
      }
    }

    addDoc(
      documents,
      `accounts/${accountId}/items/${docId}`,
      {
        id: docId,
        accountId,
        projectId: resolvedProjectId,
        createdBy: normalizeOptionalId(item?.created_by) || defaultUserId,
        description: normalizeOptionalString(item?.description) || '',
        name: normalizeOptionalString(item?.name),
        source: normalizeOptionalString(item?.source),
        sku: normalizeOptionalString(item?.sku),
        notes: normalizeOptionalString(item?.notes),
        bookmark: item?.bookmark ?? null,
        purchasedBy: guessPurchasedBy(item?.payment_method),
        status: mapStatus(item?.disposition),
        images: images.length > 0 ? images : null,
        transactionId: transactionId ?? null,
        spaceId: resolvedSpaceId,
        inheritedBudgetCategoryId,
        purchasePriceCents: purchasePriceOk ? purchasePriceCents : null,
        projectPriceCents: projectPriceOk ? projectPriceCents : null,
        marketValueCents: marketValueOk ? marketValueCents : null,
        taxRatePct: parseNumber(item?.tax_rate_pct),
        taxAmountPurchasePriceCents: taxAmountPurchaseOk ? taxAmountPurchasePriceCents : null,
        taxAmountProjectPriceCents: taxAmountProjectOk ? taxAmountProjectPriceCents : null,
        originTransactionId: originTransactionId ?? null,
        latestTransactionId: latestTransactionId ?? null,
        ...toAuditFields(item),
      },
      counts
    );
  }

  for (const tx of transactions) {
    const txId = normalizeOptionalId(tx?.transaction_id) || normalizeOptionalId(tx?.id);
    if (!txId) continue;
    const projectId = normalizeOptionalId(tx?.project_id);
    const resolvedProjectId = projectIdSet.has(projectId) ? projectId : null;
    if (projectId && !resolvedProjectId) {
      warnings.push({
        code: 'missing_project_ref',
        message: 'Transaction project_id missing in export; set to null.',
        details: { transactionId: txId, projectId },
      });
    }

    const { cents: amountCents, ok: amountOk } = parseDecimalToCents(tx?.amount);
    const { cents: subtotalCents, ok: subtotalOk } = parseDecimalToCents(tx?.subtotal);
    const { cents: sumItemPurchasePricesCents, ok: sumItemOk } = parseDecimalToCents(tx?.sum_item_purchase_prices);

    const needsReview = Boolean(tx?.needs_review) || !amountOk || !subtotalOk || !sumItemOk;
    if (!amountOk) {
      warnings.push({
        code: 'invalid_transaction_amount',
        message: 'Transaction amount could not be parsed; set to 0 and flagged for review.',
        details: { transactionId: txId, amount: tx?.amount },
      });
    }

    const receiptImages = [];
    if (Array.isArray(tx?.receipt_images)) {
      for (const media of tx.receipt_images) {
        // eslint-disable-next-line no-await-in-loop
        const attachment = await registerMedia(media, {
          allowPdf: true,
          ownerPath: `accounts/${accountId}/transactions/${txId}`,
          field: 'receiptImages',
        });
        if (attachment) receiptImages.push(attachment);
      }
    }
    const otherImages = [];
    if (Array.isArray(tx?.other_images)) {
      for (const media of tx.other_images) {
        // eslint-disable-next-line no-await-in-loop
        const attachment = await registerMedia(media, {
          allowPdf: false,
          ownerPath: `accounts/${accountId}/transactions/${txId}`,
          field: 'otherImages',
        });
        if (attachment) otherImages.push(attachment);
      }
    }
    const transactionImages = [];
    if (Array.isArray(tx?.transaction_images)) {
      for (const media of tx.transaction_images) {
        // eslint-disable-next-line no-await-in-loop
        const attachment = await registerMedia(media, {
          allowPdf: true,
          ownerPath: `accounts/${accountId}/transactions/${txId}`,
          field: 'transactionImages',
        });
        if (attachment) transactionImages.push(attachment);
      }
    }

    const itemIds = [];
    if (Array.isArray(tx?.item_ids)) {
      for (const itemId of tx.item_ids) {
        const resolved = resolveItemId(itemId, { transactionId: txId, field: 'item_ids' });
        if (resolved) itemIds.push(resolved);
      }
    }

    const budgetCategoryId = normalizeOptionalId(tx?.category_id);
    if (budgetCategoryId && !presetCategoryIds.has(budgetCategoryId)) {
      warnings.push({
        code: 'missing_budget_category',
        message: 'Transaction category_id missing in presets; set to null.',
        details: { transactionId: txId, categoryId: budgetCategoryId },
      });
    }

    addDoc(
      documents,
      `accounts/${accountId}/transactions/${txId}`,
      {
        id: txId,
        accountId,
        projectId: resolvedProjectId,
        transactionDate: normalizeOptionalString(tx?.transaction_date) || '',
        amountCents: amountOk ? amountCents : 0,
        source: normalizeOptionalString(tx?.source),
        type: normalizeOptionalString(tx?.transaction_type),
        purchasedBy: guessPurchasedBy(tx?.payment_method),
        notes: normalizeOptionalString(tx?.notes),
        status: mapTransactionStatus(tx?.status),
        reimbursementType: normalizeOptionalString(tx?.reimbursement_type),
        triggerEvent: normalizeOptionalString(tx?.trigger_event),
        receiptEmailed:
          tx?.receipt_emailed === null || tx?.receipt_emailed === undefined
            ? null
            : Boolean(tx?.receipt_emailed),
        receiptImages: receiptImages.length > 0 ? receiptImages : null,
        otherImages: otherImages.length > 0 ? otherImages : null,
        transactionImages: transactionImages.length > 0 ? transactionImages : null,
        budgetCategoryId: presetCategoryIds.has(budgetCategoryId) ? budgetCategoryId : null,
        needsReview,
        taxRatePct: parseNumber(tx?.tax_rate_pct),
        subtotalCents: subtotalOk ? subtotalCents : null,
        sumItemPurchasePricesCents: sumItemOk ? sumItemPurchasePricesCents : null,
        itemIds: itemIds.length > 0 ? itemIds : null,
        ...toAuditFields(tx, { createdBy: normalizeOptionalId(tx?.created_by) || defaultUserId }),
      },
      counts
    );
  }

  for (const edge of edges) {
    const edgeId = normalizeOptionalId(edge?.id);
    if (!edgeId) continue;
    const itemId = resolveItemId(edge?.item_id, { edgeId, field: 'item_id' });
    if (!itemId) {
      warnings.push({
        code: 'missing_item_ref',
        message: 'Lineage edge references missing item; edge skipped.',
        details: { edgeId, itemId: edge?.item_id },
      });
      continue;
    }

    const fromTransactionId = resolveTransactionId(edge?.from_transaction_id, {
      edgeId,
      field: 'from_transaction_id',
    });
    const toTransactionId = resolveTransactionId(edge?.to_transaction_id, {
      edgeId,
      field: 'to_transaction_id',
    });

    const source = normalizeOptionalString(edge?.source);
    const mappedSource =
      source === 'db_trigger' ? 'server' : source === 'app' || source === 'server' || source === 'migration'
        ? source
        : null;

    addDoc(
      documents,
      `accounts/${accountId}/lineageEdges/${edgeId}`,
      {
        id: edgeId,
        accountId,
        itemId,
        fromTransactionId,
        toTransactionId,
        movementKind: normalizeOptionalString(edge?.movement_kind),
        source: mappedSource,
        note: normalizeOptionalString(edge?.note),
        ...toAuditFields(edge, { createdBy: normalizeOptionalId(edge?.created_by) || defaultUserId }),
      },
      counts
    );
  }

  for (const user of users) {
    const userId = normalizeOptionalId(user?.id);
    if (!userId) continue;
    const role = normalizeOptionalString(user?.role);
    const mappedRole =
      role === 'owner' || role === 'admin' || role === 'user'
        ? role
        : userId === normalizeOptionalId(account?.created_by)
          ? 'owner'
          : 'user';
    addDoc(
      documents,
      `accounts/${accountId}/users/${userId}`,
      {
        id: userId,
        accountId,
        uid: userId,
        role: mappedRole,
        isDisabled: false,
        ...toAuditFields(user),
      },
      counts
    );

    for (const project of projects) {
      const projectId = normalizeOptionalId(project?.id);
      if (!projectId) continue;
      addDoc(
        documents,
        `accounts/${accountId}/users/${userId}/projectPreferences/${projectId}`,
        {
          id: projectId,
          accountId,
          userId,
          projectId,
          pinnedBudgetCategoryIds: furnishingsCategoryId ? [furnishingsCategoryId] : [],
          createdAt: normalizeOptionalString(user?.created_at) || null,
          updatedAt: normalizeOptionalString(user?.created_at) || null,
        },
        counts
      );
    }
  }

  if (invitations.length > 0) {
    for (const invite of invitations) {
      const inviteId = normalizeOptionalId(invite?.id);
      if (!inviteId) continue;
      addDoc(
        documents,
        `accounts/${accountId}/invites/${inviteId}`,
        {
          id: inviteId,
          accountId,
          email: invite?.email || '',
          role: normalizeOptionalString(invite?.role) || 'user',
          token: invite?.token || '',
          createdAt: normalizeOptionalString(invite?.created_at) || null,
          createdByUid: normalizeOptionalId(invite?.created_by) || null,
          expiresAt: normalizeOptionalString(invite?.expires_at) || null,
          acceptedAt: normalizeOptionalString(invite?.accepted_at) || null,
          acceptedByUid: normalizeOptionalId(invite?.accepted_by) || null,
          revokedAt: normalizeOptionalString(invite?.revoked_at) || null,
        },
        counts
      );
    }
  }

  const logoAttachment = account?.business_logo_url
    ? await registerMedia(
        {
          url: account?.business_logo_url,
        },
        {
          allowPdf: false,
          ownerPath: `accounts/${accountId}/profile/default`,
          field: 'logo',
        }
      )
    : null;

  addDoc(
    documents,
    `accounts/${accountId}/profile/default`,
    {
      id: 'default',
      accountId,
      businessName: account?.name || '',
      logo: logoAttachment,
      createdAt: normalizeOptionalString(account?.created_at) || null,
      updatedAt: normalizeOptionalString(account?.business_profile_updated_at) || null,
      updatedBy: normalizeOptionalId(account?.business_profile_updated_by) || null,
    },
    counts
  );

  documents.sort((a, b) => a.path.localeCompare(b.path));

  const outBase = outDir || path.join('docs', 'data_migrator', 'out', migrationVersion);
  const absoluteOut = path.isAbsolute(outBase) ? outBase : path.join(process.cwd(), outBase);
  await fs.mkdir(absoluteOut, { recursive: true });

  const bundle = {
    meta: {
      migrationVersion,
      generatedAt: exportJson?.exportedAt || null,
      sourceExport: exportFilename,
      accountId,
    },
    documents,
    counts,
  };

  const report = {
    meta: bundle.meta,
    totals: {
      documents: documents.length,
      warnings: warnings.length,
      errors: errors.length,
    },
    counts,
    warnings: warnings.slice(0, 500),
    errors: errors.slice(0, 200),
    truncated: {
      warnings: warnings.length > 500,
      errors: errors.length > 200,
    },
  };

  const manifest = Array.from(mediaManifest.values()).sort((a, b) =>
    `${a.mediaId}:${a.owner?.path}:${a.owner?.field}`.localeCompare(
      `${b.mediaId}:${b.owner?.path}:${b.owner?.field}`
    )
  );

  await fs.writeFile(path.join(absoluteOut, 'bundle.json'), stableStringify(bundle), 'utf8');
  await fs.writeFile(path.join(absoluteOut, 'report.json'), stableStringify(report), 'utf8');
  await fs.writeFile(path.join(absoluteOut, 'media-manifest.json'), stableStringify({ meta: bundle.meta, media: manifest }), 'utf8');

  console.log(`Wrote bundle to ${path.join(absoluteOut, 'bundle.json')}`);
  console.log(`Wrote report to ${path.join(absoluteOut, 'report.json')}`);
  console.log(`Wrote media manifest to ${path.join(absoluteOut, 'media-manifest.json')}`);
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
