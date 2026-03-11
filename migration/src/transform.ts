import { createHash } from 'node:crypto';
import type {
  SupabaseExport,
  SupabaseBudgetCategoryPreset,
  SupabaseImage,
  FirestoreDoc,
  MediaRef,
  TransformResult,
  TransformWarning,
  TransformError,
} from './types.js';

// ---------------------------------------------------------------------------
// Utility functions (ported from migrate-ledger-export.mjs)
// ---------------------------------------------------------------------------

function isNonEmptyString(v: unknown): v is string {
  return typeof v === 'string' && v.trim().length > 0;
}

function normalizeOptionalString(v: unknown): string | null {
  if (v === null || v === undefined) return null;
  if (typeof v !== 'string') return String(v);
  const trimmed = v.trim();
  return trimmed.length === 0 ? null : trimmed;
}

function normalizeOptionalId(v: unknown): string | null {
  if (!isNonEmptyString(v)) return null;
  return (v as string).trim();
}

function parseDecimalToCents(input: unknown): { cents: number | null; ok: boolean } {
  if (input === null || input === undefined) return { cents: null, ok: true };
  const raw = typeof input === 'number' ? String(input) : String(input);
  const trimmed = raw.trim();
  if (trimmed.length === 0) return { cents: null, ok: true };
  if (!/^-?\d+(\.\d+)?$/.test(trimmed)) return { cents: null, ok: false };
  const sign = trimmed.startsWith('-') ? -1n : 1n;
  const unsigned = trimmed.replace(/^-/, '');
  const [wholePart, fracPartRaw = ''] = unsigned.split('.');
  const frac = `${fracPartRaw}000`.slice(0, 3);
  const firstTwo = frac.slice(0, 2);
  const third = frac.slice(2, 3);
  const whole = BigInt(wholePart || '0');
  let cents = whole * 100n + BigInt(firstTwo || '0');
  if (third && Number(third) >= 5) cents += 1n;
  cents *= sign;
  const asNumber = Number(cents);
  if (!Number.isSafeInteger(asNumber)) return { cents: null, ok: false };
  return { cents: asNumber, ok: true };
}

function parseNumber(input: unknown): number | null {
  if (input === null || input === undefined) return null;
  if (typeof input === 'number' && Number.isFinite(input)) return input;
  if (typeof input === 'string' && input.trim().length > 0) {
    const num = Number(input);
    return Number.isFinite(num) ? num : null;
  }
  return null;
}

function guessPurchasedBy(paymentMethod: unknown): string | null {
  if (!isNonEmptyString(paymentMethod)) return null;
  const lower = paymentMethod.toLowerCase();
  if (lower.includes('client')) return 'Client';
  if (lower.includes('design') || lower.includes('business')) return 'Design Business';
  return null;
}

function mapItemStatus(disposition: unknown): string | null {
  if (!isNonEmptyString(disposition)) return null;
  const normalized = disposition.trim().toLowerCase();
  if (['to purchase', 'purchased', 'to return', 'returned'].includes(normalized)) return normalized;
  return null;
}

function mapTransactionStatus(status: unknown): string | null {
  if (!isNonEmptyString(status)) return null;
  const normalized = status.trim().toLowerCase();
  if (['pending', 'completed', 'canceled'].includes(normalized)) return normalized;
  return null;
}

function mapCategoryType(category: SupabaseBudgetCategoryPreset): string {
  const slug = normalizeOptionalString(category.slug);
  const name = normalizeOptionalString(category.name);
  const metadata = category.metadata;
  if (slug === 'design-fee' || name === 'Design Fee') return 'fee';
  if (slug === 'furnishings' || name === 'Furnishings') return 'itemized';
  if (metadata && typeof metadata === 'object') {
    const ct = (metadata as Record<string, unknown>).categoryType;
    if (typeof ct === 'string' && ['standard', 'itemized', 'fee'].includes(ct)) return ct;
    if ((metadata as Record<string, unknown>).itemizationEnabled === true) return 'itemized';
  }
  return 'standard';
}

function normalizeBudgetCategorySlug(category: SupabaseBudgetCategoryPreset): string | null {
  const slug = normalizeOptionalString(category.slug);
  const name = normalizeOptionalString(category.name);
  const base = slug || (name ? name.toLowerCase().replace(/\s+/g, '-') : null);
  if (!base) return null;
  return base
    .trim()
    .toLowerCase()
    .replace(/\s+/g, '-')
    .replace(/[^a-z0-9-]/g, '')
    .replace(/-+/g, '-')
    .replace(/^-+|-+$/g, '');
}

function makeStableShortHash(value: string): string {
  return createHash('sha256').update(value).digest('hex').slice(0, 8);
}

function guessMimeTypeFromUrl(url: string): string | null {
  const lower = url.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.gif')) return 'image/gif';
  if (lower.endsWith('.pdf')) return 'application/pdf';
  return null;
}

function extractBucketAndKey(url: string): { bucket: string; key: string } | null {
  const marker = '/storage/v1/object/public/';
  const idx = url.indexOf(marker);
  if (idx === -1) return null;
  const rest = url.slice(idx + marker.length);
  const [bucket, ...keyParts] = rest.split('/');
  if (!bucket || keyParts.length === 0) return null;
  return { bucket, key: keyParts.join('/') };
}

// ---------------------------------------------------------------------------
// Main transform function
// ---------------------------------------------------------------------------

export function transform(
  data: SupabaseExport,
  options: { canonicalizeBudgetCategoryIds?: boolean } = {}
): TransformResult {
  const { account, users, projects, spaces, spaceTemplates, items, transactions, invitations,
    accountPresets, lineageEdges } = data;

  const accountId = account.id;
  const defaultUserId = normalizeOptionalId(account.created_by) ?? users[0]?.id ?? 'unknown-user';

  const warnings: TransformWarning[] = [];
  const errors: TransformError[] = [];
  const documents: FirestoreDoc[] = [];
  const mediaRefs: MediaRef[] = [];
  const counts: Record<string, number> = {};
  const mediaUrlToRef = new Map<string, MediaRef>();

  // ---------------------------------------------------------------------------
  // Lookup maps
  // ---------------------------------------------------------------------------

  const projectIdSet = new Set(projects.map((p) => p.id).filter(Boolean));
  const spaceIdSet = new Set(spaces.map((s) => s.id).filter(Boolean));

  // Item ID resolution: supabase UUID and legacy item_id both map to doc ID
  const itemIdToDocId = new Map<string, string>();
  for (const item of items) {
    const legacyId = normalizeOptionalId(item.item_id);
    const uuid = normalizeOptionalId(item.id);
    const docId = legacyId ?? uuid;
    if (!docId) continue;
    if (legacyId) itemIdToDocId.set(legacyId, docId);
    if (uuid) itemIdToDocId.set(uuid, docId);
  }

  // Transaction ID resolution
  const txIdToDocId = new Map<string, string>();
  for (const tx of transactions) {
    const rowId = normalizeOptionalId(tx.id);
    const domainId = normalizeOptionalId(tx.transaction_id);
    const docId = domainId ?? rowId;
    if (!docId) continue;
    if (rowId) txIdToDocId.set(rowId, docId);
    if (domainId) txIdToDocId.set(domainId, docId);
  }

  // Transaction → project map (for lineage edge fromProjectId/toProjectId derivation)
  const txDocIdToProjectId = new Map<string, string | null>();
  for (const tx of transactions) {
    const rowId = normalizeOptionalId(tx.id);
    const domainId = normalizeOptionalId(tx.transaction_id);
    const docId = domainId ?? rowId;
    if (!docId) continue;
    const projectId = normalizeOptionalId(tx.project_id);
    const resolvedProject = projectId && projectIdSet.has(projectId) ? projectId : null;
    txDocIdToProjectId.set(docId, resolvedProject);
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  function addDoc(path: string, docData: Record<string, unknown>) {
    documents.push({ path, data: docData });
    const collection = path.split('/').slice(0, -1).join('/');
    counts[collection] = (counts[collection] ?? 0) + 1;
  }

  function toAuditFields(
    row: { created_at?: string | null; updated_at?: string | null; last_updated?: string | null;
      created_by?: string | null; updated_by?: string | null } | null | undefined,
    overrides: Partial<{ createdAt: string | null; updatedAt: string | null;
      createdBy: string | null; updatedBy: string | null }> = {}
  ) {
    const createdAt = normalizeOptionalString(row?.created_at) ?? null;
    const updatedAt =
      normalizeOptionalString(row?.updated_at) ??
      normalizeOptionalString(row?.last_updated) ??
      createdAt ??
      null;
    return {
      createdAt: overrides.createdAt !== undefined ? overrides.createdAt : createdAt,
      updatedAt: overrides.updatedAt !== undefined ? overrides.updatedAt : updatedAt,
      createdBy: overrides.createdBy !== undefined
        ? overrides.createdBy
        : (normalizeOptionalId(row?.created_by) ?? defaultUserId),
      updatedBy: overrides.updatedBy !== undefined
        ? overrides.updatedBy
        : (normalizeOptionalId(row?.updated_by) ?? normalizeOptionalId(row?.created_by) ?? null),
    };
  }

  function registerMedia(
    img: SupabaseImage | null | undefined,
    ownerPath: string,
    field: string,
    allowPdf = false
  ): { url: string; kind: string; contentType?: string; isPrimary?: true } | null {
    if (!img) return null;
    const url = normalizeOptionalString(img.url);
    if (!url) return null;
    const parsed = extractBucketAndKey(url);
    const mediaKey = parsed ? `${parsed.bucket}/${parsed.key}` : url;
    const mediaId = createHash('sha256').update(mediaKey).digest('hex');
    const contentType = normalizeOptionalString(img.mimeType) ?? guessMimeTypeFromUrl(url);
    const isPdf = contentType?.toLowerCase().includes('pdf') ?? false;
    const kind: 'image' | 'pdf' | 'file' = isPdf ? 'pdf' : 'image';

    if (!allowPdf && isPdf) {
      warnings.push({ code: 'unsupported_media_kind',
        message: 'Skipping PDF for image-only field.',
        details: { url, field, ownerPath } });
      return null;
    }
    if (!allowPdf && contentType && !contentType.toLowerCase().startsWith('image/')) {
      warnings.push({ code: 'unsupported_media_kind',
        message: 'Skipping non-image media for image-only field.',
        details: { url, contentType, field, ownerPath } });
      return null;
    }

    if (!mediaUrlToRef.has(mediaId) && parsed) {
      const ref: MediaRef = {
        mediaId,
        supabaseUrl: url,
        bucket: parsed.bucket,
        objectPath: parsed.key,
        contentType,
        kind,
        owner: { path: ownerPath, field },
      };
      mediaUrlToRef.set(mediaId, ref);
      mediaRefs.push(ref);
    }

    return {
      url: `offline://${mediaId}`,
      kind,
      ...(contentType ? { contentType } : {}),
      ...(img.isPrimary === true ? { isPrimary: true as const } : {}),
    };
  }

  function resolveTransactionId(value: unknown, context: Record<string, unknown>): string | null {
    const ref = normalizeOptionalId(value);
    if (!ref) return null;
    const resolved = txIdToDocId.get(ref) ?? null;
    if (!resolved) warnings.push({ code: 'missing_transaction_ref',
      message: 'Transaction reference could not be resolved; set to null.',
      details: { ref, ...context } });
    return resolved;
  }

  function resolveItemId(value: unknown, context: Record<string, unknown>): string | null {
    const ref = normalizeOptionalId(value);
    if (!ref) return null;
    const resolved = itemIdToDocId.get(ref) ?? null;
    if (!resolved) warnings.push({ code: 'missing_item_ref',
      message: 'Item reference could not be resolved; omitted.',
      details: { ref, ...context } });
    return resolved;
  }

  // ---------------------------------------------------------------------------
  // Budget categories from account_presets
  // ---------------------------------------------------------------------------

  const presets = accountPresets?.presets ?? {};
  const presetCategories: SupabaseBudgetCategoryPreset[] =
    Array.isArray(presets.budget_categories) ? presets.budget_categories : [];
  const legacyPresetCategoryIds = new Set(
    presetCategories.map((c) => normalizeOptionalId(c.id)).filter((x): x is string => x !== null)
  );

  const budgetCategoryIdByLegacyId = new Map<string, string>();
  const usedEmittedBudgetCategoryIds = new Set<string>();

  for (const category of presetCategories) {
    const legacyId = normalizeOptionalId(category.id);
    if (!legacyId) continue;
    if (!options.canonicalizeBudgetCategoryIds) {
      budgetCategoryIdByLegacyId.set(legacyId, legacyId);
      usedEmittedBudgetCategoryIds.add(legacyId);
      continue;
    }
    const slug = normalizeBudgetCategorySlug(category);
    const baseId = slug ?? legacyId;
    let emittedId = baseId;
    if (usedEmittedBudgetCategoryIds.has(emittedId) && !budgetCategoryIdByLegacyId.has(legacyId)) {
      emittedId = `${baseId}-${makeStableShortHash(legacyId)}`;
      warnings.push({ code: 'duplicate_budget_category_slug',
        message: 'Duplicate budget category slug; disambiguated with hash suffix.',
        details: { legacyId, baseId, emittedId } });
    }
    usedEmittedBudgetCategoryIds.add(emittedId);
    budgetCategoryIdByLegacyId.set(legacyId, emittedId);
  }

  function resolveBudgetCategoryId(value: unknown, context: Record<string, unknown>): string | null {
    const legacyId = normalizeOptionalId(value);
    if (!legacyId) return null;
    const resolved = budgetCategoryIdByLegacyId.get(legacyId) ?? null;
    if (!resolved) warnings.push({ code: 'missing_budget_category',
      message: 'Budget category reference missing in presets; set to null.',
      details: { legacyId, ...context } });
    return resolved;
  }

  const furnishingsCategory = presetCategories.find((c) => {
    const slug = normalizeBudgetCategorySlug(c);
    const name = normalizeOptionalString(c.name);
    return slug === 'furnishings' || name === 'Furnishings';
  });
  const furnishingsCategoryId = furnishingsCategory
    ? resolveBudgetCategoryId(furnishingsCategory.id, { field: 'pinnedBudgetCategoryIds' })
    : null;

  // ---------------------------------------------------------------------------
  // Account document (NEW — was missing from old migrator)
  // ---------------------------------------------------------------------------

  addDoc(`accounts/${accountId}`, {
    id: accountId,
    name: account.name ?? '',
    ownerUid: normalizeOptionalId(account.created_by) ?? null,
    createdAt: normalizeOptionalString(account.created_at) ?? null,
    updatedAt: normalizeOptionalString(account.updated_at) ?? null,
  });

  // ---------------------------------------------------------------------------
  // Business profile (FIXED: businessName → name, logo AttachmentRef → logoUrl string)
  // ---------------------------------------------------------------------------

  addDoc(`accounts/${accountId}/profile/default`, {
    id: 'default',
    accountId,
    name: account.name ?? '',
    logoUrl: normalizeOptionalString(account.business_logo_url) ?? null,
    updatedAt: normalizeOptionalString(account.business_profile_updated_at) ?? null,
    updatedBy: normalizeOptionalId(account.business_profile_updated_by) ?? null,
  });

  // ---------------------------------------------------------------------------
  // Budget categories
  // ---------------------------------------------------------------------------

  for (const category of presetCategories) {
    const legacyCategoryId = normalizeOptionalId(category.id);
    if (!legacyCategoryId) continue;
    const categoryId = resolveBudgetCategoryId(legacyCategoryId, { field: 'budgetCategories' });
    if (!categoryId) continue;
    const legacyMetadata =
      category.metadata && typeof category.metadata === 'object' ? category.metadata : null;
    const categoryType = mapCategoryType(category);
    const mappedMetadata = {
      ...(categoryType !== 'standard' ? { categoryType } : {}),
      ...(legacyMetadata?.excludeFromOverallBudget === true ? { excludeFromOverallBudget: true } : {}),
      legacy: { ...(legacyMetadata ?? {}), sourceCategoryId: legacyCategoryId },
    };
    addDoc(`accounts/${accountId}/presets/default/budgetCategories/${categoryId}`, {
      id: categoryId,
      accountId,
      projectId: null,
      name: category.name ?? '',
      slug: normalizeBudgetCategorySlug(category) ?? '',
      isArchived: Boolean(category.is_archived),
      order: category.order ?? null,
      metadata: mappedMetadata,
      ...toAuditFields(category),
    });
  }

  // Vendor defaults
  const vendorDefaults: string[] = Array.isArray(presets.vendor_defaults)
    ? presets.vendor_defaults
    : [];
  if (vendorDefaults.length > 0) {
    addDoc(`accounts/${accountId}/presets/default/vendors/default`, {
      vendors: vendorDefaults,
      ...toAuditFields(accountPresets),
    });
  }

  // ---------------------------------------------------------------------------
  // Projects + per-project budget categories
  // ---------------------------------------------------------------------------

  for (const project of projects) {
    const projectId = normalizeOptionalId(project.id);
    if (!projectId) continue;

    addDoc(`accounts/${accountId}/projects/${projectId}`, {
      id: projectId,
      accountId,
      name: project.name ?? '',
      clientName: project.client_name ?? '',
      description: normalizeOptionalString(project.description) ?? null,
      mainImageUrl: normalizeOptionalString(project.main_image_url) ?? null,
      isArchived: project.is_archived === true ? true : null,
      ...toAuditFields(project, {
        createdBy: normalizeOptionalId(project.created_by) ?? defaultUserId,
      }),
    });

    // Per-project budget category allocations
    const budgetEntries = project.budget_categories && typeof project.budget_categories === 'object'
      ? Object.entries(project.budget_categories)
      : [];
    for (const [legacyCategoryId, legacyBudget] of budgetEntries) {
      if (!legacyPresetCategoryIds.has(legacyCategoryId)) continue;
      const categoryId = resolveBudgetCategoryId(legacyCategoryId,
        { projectId, field: 'project.budget_categories' });
      if (!categoryId) continue;
      const { cents, ok } = parseDecimalToCents(legacyBudget);
      if (!ok) warnings.push({ code: 'invalid_budget_amount',
        message: 'Project budget amount could not be parsed; set to null.',
        details: { projectId, categoryId, legacyBudget, legacyCategoryId } });
      addDoc(`accounts/${accountId}/projects/${projectId}/budgetCategories/${categoryId}`, {
        id: categoryId,
        budgetCents: ok ? cents : null,
        ...toAuditFields(project),
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Spaces
  // ---------------------------------------------------------------------------

  for (const space of spaces) {
    const spaceId = normalizeOptionalId(space.id);
    if (!spaceId) continue;
    const projectId = normalizeOptionalId(space.project_id);
    const resolvedProjectId = projectId && projectIdSet.has(projectId) ? projectId : null;
    if (projectId && !resolvedProjectId) warnings.push({ code: 'missing_project_ref',
      message: 'Space project_id not found; set to null.',
      details: { spaceId, projectId } });

    const images: ReturnType<typeof registerMedia>[] = [];
    for (const img of (space.images ?? [])) {
      const att = registerMedia(img, `accounts/${accountId}/spaces/${spaceId}`, 'images', false);
      if (att) images.push(att);
    }

    addDoc(`accounts/${accountId}/spaces/${spaceId}`, {
      id: spaceId,
      accountId,
      projectId: resolvedProjectId,
      name: space.name ?? '',
      notes: normalizeOptionalString(space.notes) ?? null,
      images: images.length > 0 ? images : null,
      checklists: Array.isArray(space.checklists) && space.checklists.length > 0
        ? space.checklists
        : null,
      isArchived: space.is_archived === true ? true : null,
      ...toAuditFields(space),
    });
  }

  // ---------------------------------------------------------------------------
  // Space templates
  // ---------------------------------------------------------------------------

  for (const template of spaceTemplates) {
    const templateId = normalizeOptionalId(template.id);
    if (!templateId) continue;
    const checklists = Array.isArray(template.checklists)
      ? template.checklists.map((list: unknown) => {
          const l = list as Record<string, unknown>;
          return {
            ...l,
            items: Array.isArray(l.items)
              ? (l.items as unknown[]).map((item) => ({
                  ...(item as Record<string, unknown>),
                  isChecked: false,
                }))
              : [],
          };
        })
      : null;
    addDoc(`accounts/${accountId}/presets/default/spaceTemplates/${templateId}`, {
      id: templateId,
      accountId,
      name: template.name ?? '',
      isArchived: Boolean(template.is_archived),
      notes: normalizeOptionalString(template.notes) ?? null,
      checklists,
      ...toAuditFields(template),
    });
  }

  // ---------------------------------------------------------------------------
  // Items
  // ---------------------------------------------------------------------------

  // Build inherited budget category from linked transaction (for items without one set directly)
  const txCategoryById = new Map<string, string>();
  for (const tx of transactions) {
    const rowId = normalizeOptionalId(tx.id);
    const domainId = normalizeOptionalId(tx.transaction_id);
    const docId = domainId ?? rowId;
    const categoryId = normalizeOptionalId(tx.category_id);
    if (docId && categoryId) {
      const mapped = resolveBudgetCategoryId(categoryId,
        { transactionId: docId, field: 'transactions.category_id' });
      if (mapped) txCategoryById.set(docId, mapped);
    }
  }

  for (const item of items) {
    const docId = normalizeOptionalId(item.item_id) ?? normalizeOptionalId(item.id);
    if (!docId) continue;

    const projectId = normalizeOptionalId(item.project_id);
    const resolvedProjectId = projectId && projectIdSet.has(projectId) ? projectId : null;
    if (projectId && !resolvedProjectId) warnings.push({ code: 'missing_project_ref',
      message: 'Item project_id not found; set to null.',
      details: { itemId: docId, projectId } });

    const spaceId = normalizeOptionalId(item.space_id);
    const resolvedSpaceId = spaceId && spaceIdSet.has(spaceId) ? spaceId : null;

    // Resolve transaction link
    const rawTxId = normalizeOptionalId(item.transaction_id);
    const transactionId = rawTxId ? (txIdToDocId.get(rawTxId) ?? null) : null;

    // Budget category: item's own, or inherited from its transaction
    const directCategoryId = resolveBudgetCategoryId(item.category_id,
      { itemId: docId, field: 'items.category_id' });
    const inheritedCategoryId = transactionId ? (txCategoryById.get(transactionId) ?? null) : null;
    const budgetCategoryId = directCategoryId ?? inheritedCategoryId;

    const { cents: purchasePriceCents, ok: purchasePriceOk } =
      parseDecimalToCents(item.purchase_price);
    const { cents: projectPriceCents, ok: projectPriceOk } =
      parseDecimalToCents(item.project_price);
    const { cents: marketValueCents, ok: marketValueOk } =
      parseDecimalToCents(item.market_value);
    const { cents: taxAmountPurchasePriceCents, ok: taxAmountPurchaseOk } =
      parseDecimalToCents(item.tax_amount_purchase_price);
    const { cents: taxAmountProjectPriceCents, ok: taxAmountProjectOk } =
      parseDecimalToCents(item.tax_amount_project_price);

    if (!purchasePriceOk || !projectPriceOk || !marketValueOk
        || !taxAmountPurchaseOk || !taxAmountProjectOk) {
      warnings.push({ code: 'invalid_money_value',
        message: 'Item contains invalid money values; affected fields set to null.',
        details: { itemId: docId } });
    }

    const images: ReturnType<typeof registerMedia>[] = [];
    for (const img of (item.images ?? [])) {
      const att = registerMedia(img, `accounts/${accountId}/items/${docId}`, 'images', false);
      if (att) images.push(att);
    }

    addDoc(`accounts/${accountId}/items/${docId}`, {
      id: docId,
      accountId,
      projectId: resolvedProjectId,
      spaceId: resolvedSpaceId,
      transactionId: transactionId ?? null,
      budgetCategoryId,           // FIXED: was inheritedBudgetCategoryId
      name: normalizeOptionalString(item.name) ?? normalizeOptionalString(item.description) ?? '',
      source: normalizeOptionalString(item.source) ?? null,
      sku: normalizeOptionalString(item.sku) ?? null,
      notes: normalizeOptionalString(item.notes) ?? null,
      bookmark: item.bookmark ?? null,
      purchasedBy: guessPurchasedBy(item.payment_method),
      status: mapItemStatus(item.disposition),
      quantity: null,             // Not tracked in Supabase
      purchasePriceCents: purchasePriceOk ? purchasePriceCents : null,
      projectPriceCents: projectPriceOk ? projectPriceCents : null,
      marketValueCents: marketValueOk ? marketValueCents : null,
      taxRatePct: parseNumber(item.tax_rate_pct),
      taxAmountPurchasePriceCents: taxAmountPurchaseOk ? taxAmountPurchasePriceCents : null,
      taxAmountProjectPriceCents: taxAmountProjectOk ? taxAmountProjectPriceCents : null,
      images: images.length > 0 ? images : null,
      ...toAuditFields(item, {
        createdBy: normalizeOptionalId(item.created_by) ?? defaultUserId,
        updatedBy: normalizeOptionalId(item.updated_by)
          ?? normalizeOptionalId(item.created_by)
          ?? null,
      }),
    });
  }

  // ---------------------------------------------------------------------------
  // Transactions
  // ---------------------------------------------------------------------------

  for (const tx of transactions) {
    const txId = normalizeOptionalId(tx.transaction_id) ?? normalizeOptionalId(tx.id);
    if (!txId) continue;

    const projectId = normalizeOptionalId(tx.project_id);
    const resolvedProjectId = projectId && projectIdSet.has(projectId) ? projectId : null;
    if (projectId && !resolvedProjectId) warnings.push({ code: 'missing_project_ref',
      message: 'Transaction project_id not found; set to null.',
      details: { transactionId: txId, projectId } });

    const { cents: amountCents, ok: amountOk } = parseDecimalToCents(tx.amount);
    const { cents: subtotalCents, ok: subtotalOk } = parseDecimalToCents(tx.subtotal);

    const needsReview = Boolean(tx.needs_review) || !amountOk || !subtotalOk;
    if (!amountOk) warnings.push({ code: 'invalid_transaction_amount',
      message: 'Transaction amount could not be parsed; set to 0 and flagged for review.',
      details: { transactionId: txId, amount: tx.amount } });

    const txOwnerPath = `accounts/${accountId}/transactions/${txId}`;

    const receiptImages: ReturnType<typeof registerMedia>[] = [];
    for (const img of (tx.receipt_images ?? [])) {
      const att = registerMedia(img, txOwnerPath, 'receiptImages', true);
      if (att) receiptImages.push(att);
    }
    const otherImages: ReturnType<typeof registerMedia>[] = [];
    for (const img of (tx.other_images ?? [])) {
      const att = registerMedia(img, txOwnerPath, 'otherImages', false);
      if (att) otherImages.push(att);
    }
    const transactionImages: ReturnType<typeof registerMedia>[] = [];
    for (const img of (tx.transaction_images ?? [])) {
      const att = registerMedia(img, txOwnerPath, 'transactionImages', true);
      if (att) transactionImages.push(att);
    }

    const itemIds: string[] = [];
    for (const itemId of (tx.item_ids ?? [])) {
      const resolved = resolveItemId(itemId, { transactionId: txId, field: 'item_ids' });
      if (resolved) itemIds.push(resolved);
    }

    const budgetCategoryId = resolveBudgetCategoryId(tx.category_id,
      { transactionId: txId, field: 'transactions.category_id' });

    const status = mapTransactionStatus(tx.status);

    addDoc(txOwnerPath, {
      id: txId,
      accountId,
      projectId: resolvedProjectId,
      transactionDate: normalizeOptionalString(tx.transaction_date) ?? '',
      amountCents: amountOk ? amountCents : 0,
      source: normalizeOptionalString(tx.source) ?? null,
      type: normalizeOptionalString(tx.transaction_type) ?? null,   // Firestore field is "type"
      paymentMethod: normalizeOptionalString(tx.payment_method) ?? null,  // ADDED
      purchasedBy: guessPurchasedBy(tx.payment_method),
      notes: normalizeOptionalString(tx.notes) ?? null,
      status,
      isCanceled: status === 'canceled' ? true : null,              // ADDED: derived
      reimbursementType: normalizeOptionalString(tx.reimbursement_type) ?? null,
      triggerEvent: normalizeOptionalString(tx.trigger_event) ?? null,
      receiptEmailed: tx.receipt_emailed == null ? null : Boolean(tx.receipt_emailed),
      receiptImages: receiptImages.length > 0 ? receiptImages : null,
      otherImages: otherImages.length > 0 ? otherImages : null,
      transactionImages: transactionImages.length > 0 ? transactionImages : null,
      budgetCategoryId,
      needsReview,
      taxRatePct: parseNumber(tx.tax_rate_pct),
      subtotalCents: subtotalOk ? subtotalCents : null,
      itemIds: itemIds.length > 0 ? itemIds : null,
      ...toAuditFields(tx, {
        createdBy: normalizeOptionalId(tx.created_by) ?? defaultUserId,
      }),
    });
  }

  // ---------------------------------------------------------------------------
  // Lineage edges (FIXED: add fromProjectId/toProjectId derived from tx→project map)
  // ---------------------------------------------------------------------------

  for (const edge of lineageEdges) {
    const edgeId = normalizeOptionalId(edge.id);
    if (!edgeId) continue;

    const itemId = resolveItemId(edge.item_id, { edgeId, field: 'item_id' });
    if (!itemId) {
      warnings.push({ code: 'missing_item_ref',
        message: 'Lineage edge references missing item; edge skipped.',
        details: { edgeId, itemId: edge.item_id } });
      continue;
    }

    const fromTransactionId = resolveTransactionId(edge.from_transaction_id,
      { edgeId, field: 'from_transaction_id' });
    const toTransactionId = resolveTransactionId(edge.to_transaction_id,
      { edgeId, field: 'to_transaction_id' });

    // Derive project IDs from the transaction→project lookup map
    const fromProjectId = fromTransactionId
      ? (txDocIdToProjectId.get(fromTransactionId) ?? null)
      : null;
    const toProjectId = toTransactionId
      ? (txDocIdToProjectId.get(toTransactionId) ?? null)
      : null;

    const source = normalizeOptionalString(edge.source);
    const mappedSource = source === 'db_trigger' ? 'server'
      : (source === 'app' || source === 'server' || source === 'migration') ? source
      : null;

    addDoc(`accounts/${accountId}/lineageEdges/${edgeId}`, {
      id: edgeId,
      accountId,
      itemId,
      fromTransactionId,
      toTransactionId,
      fromProjectId,
      toProjectId,
      movementKind: normalizeOptionalString(edge.movement_kind) ?? null,
      source: mappedSource,
      note: normalizeOptionalString(edge.note) ?? null,
      createdBy: normalizeOptionalId(edge.created_by) ?? defaultUserId,
      createdAt: normalizeOptionalString(edge.created_at) ?? null,
    });
  }

  // ---------------------------------------------------------------------------
  // Users (AccountMembers) — mobile reads from accounts/{id}/users/{uid}
  // ---------------------------------------------------------------------------

  for (const user of users) {
    const userId = normalizeOptionalId(user.id);
    if (!userId) continue;
    const role = normalizeOptionalString(user.role);
    const mappedRole = (role === 'owner' || role === 'admin' || role === 'user')
      ? role
      : userId === normalizeOptionalId(account.created_by) ? 'owner' : 'user';

    addDoc(`accounts/${accountId}/users/${userId}`, {
      id: userId,
      accountId,
      uid: userId,
      role: mappedRole,
      email: normalizeOptionalString(user.email) ?? null,
      name: normalizeOptionalString(user.display_name) ?? null,
      isDisabled: false,
      ...toAuditFields(user),
    });

    // Per-user project preferences
    for (const project of projects) {
      const projectId = normalizeOptionalId(project.id);
      if (!projectId) continue;
      addDoc(`accounts/${accountId}/users/${userId}/projectPreferences/${projectId}`, {
        id: projectId,
        accountId,
        userId,
        projectId,
        pinnedBudgetCategoryIds: furnishingsCategoryId ? [furnishingsCategoryId] : [],
        createdAt: normalizeOptionalString(user.created_at) ?? null,
        updatedAt: normalizeOptionalString(user.created_at) ?? null,
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Invitations
  // ---------------------------------------------------------------------------

  for (const invite of invitations) {
    const inviteId = normalizeOptionalId(invite.id);
    if (!inviteId) continue;
    addDoc(`accounts/${accountId}/invites/${inviteId}`, {
      id: inviteId,
      accountId,
      email: invite.email ?? '',
      role: normalizeOptionalString(invite.role) ?? 'user',
      token: invite.token ?? '',
      createdAt: normalizeOptionalString(invite.created_at) ?? null,
      createdByUid: normalizeOptionalId(invite.created_by) ?? null,
      expiresAt: normalizeOptionalString(invite.expires_at) ?? null,
      acceptedAt: normalizeOptionalString(invite.accepted_at) ?? null,
      acceptedByUid: normalizeOptionalId(invite.accepted_by) ?? null,
      revokedAt: normalizeOptionalString(invite.revoked_at) ?? null,
    });
  }

  // Sort documents for deterministic output
  documents.sort((a, b) => a.path.localeCompare(b.path));

  return { documents, mediaRefs, counts, warnings, errors };
}
