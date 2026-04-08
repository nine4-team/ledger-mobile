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
  categoryType?: string;
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
  isCanonicalInventorySale?: boolean;
  inventorySaleDirection?: string;
  isCanonicalInventory?: boolean;
  canonicalKind?: string;
  needsReview?: boolean;
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
