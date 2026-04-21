/** Firestore document types — mirrors the data model spec. */

export interface Project {
  id: string;
  accountId?: string;
  name: string;
  clientName: string;
  description?: string;
  mainImageUrl?: string;
  isArchived: boolean;
  notes?: string;
  budgetSummary?: ProjectBudgetSummary;
  createdAt?: FirebaseFirestore.Timestamp;
  updatedAt?: FirebaseFirestore.Timestamp;
}

export interface ProjectBudgetSummary {
  totalBudgetCents?: number;
  spentCents?: number;
  categories?: Record<string, BudgetSummaryCategory>;
}

export interface BudgetSummaryCategory {
  budgetCents?: number;
  spentCents?: number;
  name?: string;
  /** @deprecated Phase 4 stops writing this; use `supportedTypes` instead. */
  categoryType?: string;
  supportedTypes?: string[];
  isArchived: boolean;
  excludeFromOverallBudget?: boolean;
}

export interface Transaction {
  id: string;
  projectId?: string;
  budgetCategoryId?: string;
  amountCents?: number;
  subtotalCents?: number;
  taxRatePct?: number;
  type?: string;
  status?: string;
  source?: string;
  transactionDate?: string;
  itemIds?: string[];
  notes?: string;
  /**
   * @deprecated Legacy canonical-sale aggregator marker. New per-batch Sale
   * transactions never set this field. Readers must use the dual-read path in
   * util/budget.ts — see docs/specs/canonical-sales.md for historical context.
   */
  isCanonicalInventorySale?: boolean;
  /**
   * @deprecated Legacy canonical-sale direction. Only present on historical
   * docs with isCanonicalInventorySale == true. New per-batch sales always go
   * business → project and never set this field.
   */
  inventorySaleDirection?: string;
  isCanonicalInventory?: boolean;
  canonicalKind?: string;
  isComplete?: boolean;
  audit?: {
    resolvedSubtotalCents: number;
    itemsSumCents: number;
    varianceCents: number;
    variancePercent: number;
    linkedItemsSumCents?: number;
    returnedItemsSumCents?: number;
    returnedItemsCount?: number;
    soldItemsSumCents?: number;
    soldItemsCount?: number;
    itemsMissingTaxRateCount?: number;
    itemsMissingTaxRate?: string[];
    totalItemCount?: number;
  } | null;
  purchasedBy?: string;
  reimbursementType?: string;
  receiptEmailed?: boolean;
  paymentMethod?: string;
  receiptImages?: AttachmentRef[];
  otherImages?: AttachmentRef[];
  transactionImages?: AttachmentRef[];
  ingestionSource?: string;
  ingestionStatus?: string;
  ingestionMeta?: {
    emailId?: string;
    subject?: string;
    inbox?: string;
    matchConfidence?: number;
    matchReason?: string;
    orderNumber?: string;
    linkedIngestionIds?: string[];
  };
  createdAt?: FirebaseFirestore.Timestamp;
  updatedAt?: FirebaseFirestore.Timestamp;
}

export interface Item {
  id: string;
  accountId?: string;
  projectId?: string;
  spaceId?: string;
  name?: string;
  description?: string;
  notes?: string;
  status?: string;
  source?: string;
  /** Denormalized immediate source. Set to the inventory label when the item lands in inventory; preserves the original vendor until then. `currentSource != source` means the item has passed through inventory — used for origin-aware routing in project→inventory moves. */
  currentSource?: string;
  sku?: string;
  transactionId?: string;
  purchasePriceCents?: number;
  projectPriceCents?: number;
  marketValueCents?: number;
  purchasedBy?: string;
  bookmark?: boolean;
  budgetCategoryId?: string;
  quantity?: number;
  taxRatePct?: number;
  images?: AttachmentRef[];
  createdBy?: string;
  updatedBy?: string;
  createdAt?: FirebaseFirestore.Timestamp;
  updatedAt?: FirebaseFirestore.Timestamp;
}

export interface Space {
  id: string;
  accountId?: string;
  projectId?: string;
  name: string;
  notes?: string;
  images?: AttachmentRef[];
  checklists?: Checklist[];
  isArchived: boolean;
  createdAt?: FirebaseFirestore.Timestamp;
  updatedAt?: FirebaseFirestore.Timestamp;
}

export interface Checklist {
  id: string;
  name: string;
  items: ChecklistItem[];
}

export interface ChecklistItem {
  id: string;
  text: string;
  isChecked: boolean;
}

export interface BudgetCategory {
  id: string;
  accountId?: string;
  name: string;
  slug?: string;
  isArchived: boolean;
  order?: number;
  metadata?: BudgetCategoryMetadata;
  /**
   * New-model field: transaction kinds this category accepts (e.g. ["fee"],
   * ["expense"], ["purchase","return"]). Absent on legacy docs — derive from
   * metadata.categoryType in that case. See docs/specs/transaction-type.md.
   */
  supportedTypes?: string[];
  createdAt?: FirebaseFirestore.Timestamp;
  updatedAt?: FirebaseFirestore.Timestamp;
}

export interface BudgetCategoryMetadata {
  categoryType?: string;
  excludeFromOverallBudget?: boolean;
}

export interface ProjectBudgetCategory {
  id: string;
  budgetCents?: number;
  createdBy?: string;
  updatedBy?: string;
  createdAt?: FirebaseFirestore.Timestamp;
  updatedAt?: FirebaseFirestore.Timestamp;
}

export interface LineageEdge {
  id: string;
  accountId?: string;
  itemId?: string;
  movementKind?: string;
  fromTransactionId?: string;
  toTransactionId?: string;
  fromProjectId?: string;
  toProjectId?: string;
  source?: string;
  note?: string;
  createdBy?: string;
  createdAt?: FirebaseFirestore.Timestamp;
}

export interface ProjectNote {
  id: string;
  projectId?: string;
  text: string;
  createdBy: string;
  createdByName: string;
  source: string;
  createdAt?: FirebaseFirestore.Timestamp;
}

export interface AttachmentRef {
  url: string;
  thumbnailUrlSm?: string;
  thumbnailUrlMd?: string;
  kind?: string;
  fileName?: string;
  contentType?: string;
  isPrimary?: boolean;
  isUploading?: boolean;
}
