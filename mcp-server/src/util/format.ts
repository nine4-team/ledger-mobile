/** Format cents as dollars: 1234 → "$12.34" */
export function formatCents(cents: number | undefined | null): string {
  if (cents == null) return "$0.00";
  const sign = cents < 0 ? "-" : "";
  const abs = Math.abs(cents);
  return `${sign}$${(abs / 100).toFixed(2)}`;
}

/** Format a Firestore Timestamp or date string for display. */
export function formatDate(
  value: FirebaseFirestore.Timestamp | string | undefined | null
): string {
  if (!value) return "";
  if (typeof value === "string") return value;
  if (typeof value === "object" && "toDate" in value) {
    return value.toDate().toLocaleDateString("en-US", {
      year: "numeric",
      month: "short",
      day: "numeric",
    });
  }
  return String(value);
}
