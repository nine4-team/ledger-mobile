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
  /** Canonical budget category behavior: general, itemized, or fee. */
  categoryType?: string;
  isArchived: boolean;
  excludeFromOverallBudget?: boolean;
}

export interface Transaction {
  id: string;
  projectId?: string | null;
  budgetCategoryId?: string | null;
  amountCents?: number;
  subtotalCents?: number;
  taxRatePct?: number;
  discount?: Discount;
  type?: string;
  status?: string;
  source?: string;
  transactionDate?: string;
  itemIds?: string[];
  notes?: string;
  /**
   * @deprecated Legacy canonical-sale aggregator marker. New per-batch
   * inventory movement transactions never set this field. Readers must use the dual-read path in
   * util/budget.ts — see docs/specs/canonical-sales.md for historical context.
   */
  isCanonicalInventorySale?: boolean;
  /**
   * @deprecated Legacy canonical-sale direction. Only present on historical
   * docs with isCanonicalInventorySale == true. New per-batch inventory movements
   * derive direction from transaction shape and never set this field.
   */
  inventorySaleDirection?: string;
  isCanonicalInventory?: boolean;
  canonicalKind?: string;
  isComplete?: boolean;
  audit?: {
    resolvedSubtotalCents: number;
    itemsSumCents: number;
    discountCents?: number;
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
  purchaseHandling?: "inventory_resale" | "project_reimbursement";
  intendedProjectId?: string;
  intendedBudgetCategoryId?: string;
  inventoryIntentResolvedAt?: FirebaseFirestore.Timestamp;
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
  settlementInvoiceId?: string;
  settlementInvoiceLineIds?: string[];
  createdAt?: FirebaseFirestore.Timestamp;
  updatedAt?: FirebaseFirestore.Timestamp;
}

export interface Discount {
  /** Positive discount amount in cents, applied against the transaction subtotal. */
  amountCents: number;
}

export type InvoiceLineSourceType = "item" | "transaction" | "feeInstallment" | "manual";
export type InvoiceLineSign = 1 | -1;

export interface InvoiceLine {
  id?: string;
  sourceType: InvoiceLineSourceType;
  sourceId?: string;
  amountCents: number;
  sign: InvoiceLineSign;
  budgetCategoryId?: string;
  snapshotName?: string;
  settlementTransactionIds?: string[];
}

export interface FeeInstallment {
  id: string;
  accountId?: string;
  projectId?: string;
  budgetCategoryId: string;
  label: string;
  amountCents: number;
  sortOrder?: number;
  createdBy?: string;
  updatedBy?: string;
  createdAt?: FirebaseFirestore.Timestamp;
  updatedAt?: FirebaseFirestore.Timestamp;
}

export interface Invoice {
  id: string;
  accountId?: string;
  projectId?: string;
  status?: "created" | "sent" | "paid" | "canceled";
  itemIds?: string[];
  transactionIds?: string[];
  lines?: InvoiceLine[];
  totalCents?: number;
  notes?: string;
  invoiceNumber?: string;
  dateIssued?: FirebaseFirestore.Timestamp;
  dateSent?: FirebaseFirestore.Timestamp;
  datePaid?: FirebaseFirestore.Timestamp;
  dateVoided?: FirebaseFirestore.Timestamp;
  createdBy?: string;
  updatedBy?: string;
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
  /** Immutable accounting provenance captured when this item most recently entered business inventory from a project. */
  inventoryEntryTransactionId?: string;
  inventoryEntryProjectId?: string;
  inventoryEntryBudgetCategoryId?: string;
  inventoryEntryPriceCents?: number;
  inventoryEntryAmountCents?: number;
  images?: AttachmentRef[];
  createdBy?: string;
  updatedBy?: string;
  createdAt?: FirebaseFirestore.Timestamp;
  updatedAt?: FirebaseFirestore.Timestamp;
}

export type ProtoItemStatus = "open" | "in_review" | "converted";
export type ProtoItemCaptureContext = "project" | "inventory" | "transaction";

export interface ProtoItemExtraction {
  rawText?: string;
  barcodePayloads?: string[];
  skuCandidates?: string[];
  confidence?: number;
  extractedAt?: FirebaseFirestore.Timestamp;
}

/**
 * Photo-first capture object for "this will become an item later".
 *
 * Stored in accounts/{accountId}/protoItems. MCP tools expose these as
 * quick draft items to match the product language.
 */
export interface ProtoItem {
  id: string;
  accountId?: string;
  projectId?: string | null;
  intendedProjectId?: string | null;
  transactionId?: string;
  name?: string;
  captureContext?: ProtoItemCaptureContext;
  status?: ProtoItemStatus;
  /** User-selected routing marker for a project draft originating in business inventory. */
  isFromInventory?: boolean;
  /** @deprecated Read compatibility only. New tools never expose or write this field. */
  sourceHint?: string;
  photos?: AttachmentRef[];
  sku?: string;
  quantity?: number;
  notes?: string;
  extracted?: ProtoItemExtraction;
  /** @deprecated Legacy suggestion metadata. Never use as a confirmed association. */
  candidateTransactionId?: string;
  candidateItemId?: string;
  convertedItemId?: string;
  convertedAt?: FirebaseFirestore.Timestamp;
  createdBy?: string;
  updatedBy?: string;
  convertedBy?: string;
  createdAt?: FirebaseFirestore.Timestamp;
  updatedAt?: FirebaseFirestore.Timestamp;
}

export interface Space {
  id: string;
  accountId?: string;
  projectId?: string | null;
  name: string;
  notes?: string;
  images?: AttachmentRef[];
  checklists?: Checklist[];
  isComplete?: boolean;
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
  checkmarks?: ImageCheckmark[];
}

export interface ImageCheckmark {
  id: string;
  /** Horizontal position normalized to the image bounds (0...1). */
  x: number;
  /** Vertical position normalized to the image bounds (0...1). */
  y: number;
}
