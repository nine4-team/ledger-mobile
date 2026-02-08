/**
 * Canonical reimbursement type values as stored in Firestore.
 *
 * These are the actual field values for `transaction.reimbursementType`.
 * Use these constants throughout the app instead of raw strings.
 */

/** Client owes the design business money */
export const OWED_TO_COMPANY = 'owed-to-company' as const;

/** Design business owes client money */
export const OWED_TO_CLIENT = 'owed-to-client' as const;

export type ReimbursementType = typeof OWED_TO_COMPANY | typeof OWED_TO_CLIENT;

/** All reimbursement types that indicate a transaction is invoiceable */
export const INVOICEABLE_REIMBURSEMENT_TYPES: readonly ReimbursementType[] = [
  OWED_TO_COMPANY,
  OWED_TO_CLIENT,
] as const;

/** Check if a transaction is invoiceable based on its reimbursement type */
export function isInvoiceable(reimbursementType: string | null | undefined): boolean {
  return reimbursementType === OWED_TO_COMPANY || reimbursementType === OWED_TO_CLIENT;
}
