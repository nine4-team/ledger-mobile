export function normalizePrimaryAttachments<T extends { isPrimary?: boolean }>(
  attachments: readonly T[]
): T[] {
  if (attachments.length === 0) return [];

  const markedIndex = attachments.findIndex((attachment) => attachment.isPrimary === true);
  const primaryIndex = markedIndex >= 0 ? markedIndex : 0;

  return attachments.map((attachment, index) => ({
    ...attachment,
    isPrimary: index === primaryIndex,
  }));
}
