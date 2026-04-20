/**
 * Helpers for maintaining the `notes` field on transactions and items.
 *
 * ## Convention
 *
 * `notes` is a single string field shared between user-authored prose and
 * AI-authored audit lines. The convention:
 *
 *   1. User-authored prose goes at the TOP of the field. It describes what the
 *      record represents ("Living room sofas — green loveseat & sofa…") and is
 *      the primary content a human reads first.
 *
 *   2. AI-authored audit lines go at the BOTTOM of the field, separated from
 *      user prose by a blank line. Each line is tagged so the authorship is
 *      unambiguous:
 *
 *        [AI 2026-04-20] Reconciled shipping $399 into subtotalCents.
 *
 *   3. When an AI makes multiple edits the same day, the latest edit REPLACES
 *      the previous same-day AI line rather than stacking stale entries.
 *      `appendOrReviseAiAuditLine` handles this automatically.
 *
 *   4. When an AI wants to rewrite the whole notes field (e.g. consolidating
 *      its own prior messes), it passes `notes` as a full replacement via the
 *      regular field — not through the audit-append channel.
 */

/** Today as an MM/DD/YYYY string, local time. */
export function todayString(date: Date = new Date()): string {
  const m = date.getMonth() + 1;
  const d = date.getDate();
  const y = date.getFullYear();
  return `${m}/${d}/${y}`;
}

const AI_PREFIX_RE = /^\[AI (\d{1,2}\/\d{1,2}\/\d{4})\] /;

/** True if `line` is already an AI audit line with an ISO-date prefix. */
function isAiAuditLine(line: string): boolean {
  return AI_PREFIX_RE.test(line);
}

/** Extract the M/D/YYYY date out of an AI audit line, or null. */
function aiAuditLineDate(line: string): string | null {
  const match = line.match(AI_PREFIX_RE);
  return match ? match[1] : null;
}

/**
 * Append an AI audit line to `existingNotes` and return the merged string.
 *
 * If the last paragraph of `existingNotes` is already an AI audit line from
 * today, that line is REPLACED with the new one (prevents stacking of stale
 * same-day entries). Otherwise the new line is appended below existing
 * content, separated by a blank line.
 *
 * Input `auditLine` should be a short, single-line message. The `[AI M/D/YYYY]`
 * prefix is added automatically — do not include one yourself.
 */
export function appendOrReviseAiAuditLine(
  existingNotes: string | undefined,
  auditLine: string,
  date: string = todayString()
): string {
  const tagged = `[AI ${date}] ${auditLine.trim()}`;
  const prev = (existingNotes ?? "").trimEnd();
  if (!prev) return tagged;

  // Find the last non-empty line. If it's an AI line from today, replace it.
  const lines = prev.split("\n");
  for (let i = lines.length - 1; i >= 0; i--) {
    const line = lines[i].trim();
    if (!line) continue;
    if (isAiAuditLine(line) && aiAuditLineDate(line) === date) {
      lines[i] = tagged;
      return lines.join("\n");
    }
    break;
  }

  // Append with a blank-line separator.
  return `${prev}\n\n${tagged}`;
}

/**
 * Tag a fresh notes value as AI-authored. Used by tools that create entirely
 * AI-written records (sell_items, return_items, move_items_between_projects)
 * so the human reader can tell the line came from the MCP side, not an app
 * user. If `notes` is already tagged, returns it unchanged.
 */
export function tagNotesAsAi(
  notes: string,
  date: string = todayString()
): string {
  const trimmed = notes.trim();
  if (!trimmed) return trimmed;
  const firstLine = trimmed.split("\n", 1)[0];
  if (isAiAuditLine(firstLine)) return trimmed;
  return `[AI ${date}] ${trimmed}`;
}
