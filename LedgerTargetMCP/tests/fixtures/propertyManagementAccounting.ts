import type { ProjectItemAccountingRow, PropertyManagementReportItem } from "../../src/propertyManagementReport.js";

// Matches the typed relationship evidence used by the Swift golden generator.
export function accounted(item: PropertyManagementReportItem): ProjectItemAccountingRow {
  return {
    evidence: { accountId: item.accountId, projectId: item.projectId, clientId: "client", itemId: item.itemId,
      ...(item.spaceId === null ? {} : { spaceId: item.spaceId }), clientPaidPurchases: [],
      billableOccurrences: [{ id: `charge-${item.itemId}`, accountId: item.accountId, projectId: item.projectId,
        itemId: item.itemId, polarity: "charge", phase: { kind: "availableToInvoice" } }] },
    relationshipAbsenceIsAuthoritative: true, resolution: "accountedFor",
  };
}
