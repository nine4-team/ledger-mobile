/** Firestore document types — mirrors the data model spec. */

export interface Project {
  id: string;
  accountId?: string;
  name: string;
  clientName: string;
  description?: string;
  mainImageUrl?: string;
  isArchived?: boolean;
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
  isArchived?: boolean;
  excludeFromOverallBudget?: boolean;
}

export interface Transaction {
  id: string;
  projectId?: string;
  budgetCategoryId?: string;
  amountCents?: number;
  subtotalCents?: number;
  taxRatePct?: number;
  /** Firestore field name is "type" — legacy data may also use "transactionType" */
  type?: string;
  transactionType?: string;
  status?: string;
  source?: string;
  transactionDate?: string;
  itemIds?: string[];
  notes?: string;
  isCanceled?: boolean;
  isCanonicalInventorySale?: boolean;
  inventorySaleDirection?: string;
  isCanonicalInventory?: boolean;
  canonicalKind?: string;
  needsReview?: boolean;
  purchasedBy?: string;
  reimbursementType?: string;
  receiptEmailed?: boolean;
  paymentMethod?: string;
  receiptImages?: AttachmentRef[];
  otherImages?: AttachmentRef[];
  transactionImages?: AttachmentRef[];
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
  isArchived?: boolean;
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
  isArchived?: boolean;
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
  kind?: string;
  fileName?: string;
  contentType?: string;
  isPrimary?: boolean;
  isUploading?: boolean;
}
