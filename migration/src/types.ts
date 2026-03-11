/** Raw rows from Supabase tables, keyed by table name. */
export interface SupabaseExport {
  account: SupabaseAccount;
  users: SupabaseUser[];
  projects: SupabaseProject[];
  spaces: SupabaseSpace[];
  spaceTemplates: SupabaseSpaceTemplate[];
  items: SupabaseItem[];
  transactions: SupabaseTransaction[];
  invitations: SupabaseInvitation[];
  accountPresets: SupabaseAccountPresets | null;
  lineageEdges: SupabaseLineageEdge[];
}

export interface SupabaseAccount {
  id: string;
  name: string;
  created_by: string | null;
  created_at: string | null;
  updated_at: string | null;
  business_logo_url: string | null;
  business_profile_updated_at: string | null;
  business_profile_updated_by: string | null;
}

export interface SupabaseUser {
  id: string;
  account_id: string;
  email: string | null;
  display_name: string | null;
  role: string | null;
  created_at: string | null;
  last_login: string | null;
}

export interface SupabaseProject {
  id: string;
  account_id: string;
  name: string;
  client_name: string | null;
  description: string | null;
  budget: string | null;
  design_fee: string | null;
  budget_categories: Record<string, string> | null;
  main_image_url: string | null;
  is_archived: boolean | null;
  created_at: string | null;
  updated_at: string | null;
  created_by: string | null;
}

export interface SupabaseSpace {
  id: string;
  account_id: string;
  project_id: string | null;
  name: string;
  notes: string | null;
  images: SupabaseImage[] | null;
  checklists: unknown[] | null;
  is_archived: boolean | null;
  created_at: string | null;
  updated_at: string | null;
}

export interface SupabaseSpaceTemplate {
  id: string;
  account_id: string;
  name: string;
  notes: string | null;
  checklists: unknown[] | null;
  is_archived: boolean | null;
  sort_order: number | null;
  created_at: string | null;
  updated_at: string | null;
}

export interface SupabaseItem {
  id: string;
  item_id: string | null;
  account_id: string;
  project_id: string | null;
  transaction_id: string | null;
  name: string | null;
  description: string | null;
  source: string | null;
  sku: string | null;
  purchase_price: string | null;
  project_price: string | null;
  market_value: string | null;
  payment_method: string | null;
  disposition: string | null;
  notes: string | null;
  space: string | null;
  space_id: string | null;
  qr_key: string | null;
  bookmark: boolean | null;
  images: SupabaseImage[] | null;
  tax_rate_pct: number | null;
  tax_amount_purchase_price: string | null;
  tax_amount_project_price: string | null;
  category_id: string | null;
  created_by: string | null;
  updated_by: string | null;
  created_at: string | null;
  updated_at: string | null;
}

export interface SupabaseTransaction {
  id: string;
  transaction_id: string | null;
  account_id: string;
  project_id: string | null;
  transaction_date: string | null;
  source: string | null;
  transaction_type: string | null;
  payment_method: string | null;
  amount: string | null;
  category_id: string | null;
  notes: string | null;
  receipt_images: SupabaseImage[] | null;
  other_images: SupabaseImage[] | null;
  transaction_images: SupabaseImage[] | null;
  receipt_emailed: boolean | null;
  status: string | null;
  reimbursement_type: string | null;
  trigger_event: string | null;
  item_ids: string[] | null;
  tax_rate_pct: number | null;
  subtotal: string | null;
  needs_review: boolean | null;
  sum_item_purchase_prices: string | null;
  created_by: string | null;
  created_at: string | null;
  updated_at: string | null;
}

export interface SupabaseInvitation {
  id: string;
  account_id: string;
  email: string | null;
  role: string | null;
  token: string | null;
  status: string | null;
  created_by: string | null;
  created_at: string | null;
  expires_at: string | null;
  accepted_at: string | null;
  accepted_by: string | null;
  revoked_at: string | null;
}

export interface SupabaseAccountPresets {
  account_id: string;
  default_budget_category_id: string | null;
  budget_category_order: string[] | null;
  /** JSONB column containing nested budget_categories and vendor_defaults arrays. */
  presets: {
    budget_categories?: SupabaseBudgetCategoryPreset[];
    vendor_defaults?: string[];
    [key: string]: unknown;
  } | null;
  created_at: string | null;
  updated_at: string | null;
}

export interface SupabaseBudgetCategoryPreset {
  id: string;
  name: string;
  slug: string | null;
  is_archived: boolean | null;
  order: number | null;
  metadata: {
    categoryType?: string;
    excludeFromOverallBudget?: boolean;
    itemizationEnabled?: boolean;
    [key: string]: unknown;
  } | null;
  created_at: string | null;
  updated_at: string | null;
}

export interface SupabaseLineageEdge {
  id: string;
  account_id: string;
  item_id: string | null;
  from_transaction_id: string | null;
  to_transaction_id: string | null;
  movement_kind: string | null;
  source: string | null;
  note: string | null;
  created_by: string | null;
  created_at: string | null;
}

export interface SupabaseImage {
  url: string;
  alt?: string | null;
  isPrimary?: boolean | null;
  uploadedAt?: string | null;
  fileName?: string | null;
  size?: number | null;
  mimeType?: string | null;
}

/** A single Firestore document to write. */
export interface FirestoreDoc {
  path: string;
  data: Record<string, unknown>;
}

/** An image/file attachment to migrate from Supabase Storage to Firebase Storage. */
export interface MediaRef {
  mediaId: string;
  supabaseUrl: string;
  bucket: string;
  objectPath: string;
  contentType: string | null;
  kind: 'image' | 'pdf' | 'file';
  owner: { path: string; field: string };
}

export interface TransformResult {
  documents: FirestoreDoc[];
  mediaRefs: MediaRef[];
  counts: Record<string, number>;
  warnings: TransformWarning[];
  errors: TransformError[];
}

export interface TransformWarning {
  code: string;
  message: string;
  details?: Record<string, unknown>;
}

export interface TransformError {
  code: string;
  message: string;
  details?: Record<string, unknown>;
}
