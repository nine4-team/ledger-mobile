/**
 * Structured error responses for MCP tools.
 *
 * Every failed tool call should return a machine-readable payload so the AI
 * can branch on `code` and act on `hint` without human intervention.
 */

export type ErrorCode =
  | "NOT_FOUND"
  | "VALIDATION"
  | "PERMISSION"
  | "CONFLICT"
  | "LIMIT_EXCEEDED"
  | "UNAVAILABLE";

export interface ToolErrorInput {
  code: ErrorCode;
  message: string;
  hint?: string;
  retryable?: boolean;
  suggestedTool?: string;
  details?: Record<string, unknown>;
}

export interface ToolErrorResponse {
  [key: string]: unknown;
  content: Array<{ type: "text"; text: string }>;
  isError: true;
}

export function toolError(input: ToolErrorInput): ToolErrorResponse {
  const payload = {
    error: {
      code: input.code,
      message: input.message,
      ...(input.hint !== undefined ? { hint: input.hint } : {}),
      ...(input.retryable !== undefined ? { retryable: input.retryable } : {}),
      ...(input.suggestedTool !== undefined ? { suggestedTool: input.suggestedTool } : {}),
      ...(input.details !== undefined ? { details: input.details } : {}),
    },
  };
  return {
    content: [{ type: "text", text: JSON.stringify(payload, null, 2) }],
    isError: true,
  };
}

/** Common helper: not-found error for a named entity. */
export function notFound(entity: string, id: string, suggestedTool?: string): ToolErrorResponse {
  return toolError({
    code: "NOT_FOUND",
    message: `${entity} ${id} not found.`,
    hint: `Verify the ID is correct and belongs to the current account. Use a list_/search_ tool to discover valid IDs.`,
    retryable: false,
    suggestedTool,
  });
}

/** Validation error with an optional hint and field details. */
export function validation(
  message: string,
  hint?: string,
  details?: Record<string, unknown>
): ToolErrorResponse {
  return toolError({ code: "VALIDATION", message, hint, retryable: true, details });
}

/**
 * Require a non-empty `notes` string on tools that create a brand-new audit
 * record whose notes field IS the primary description (sell_items_from_*,
 * return_items, create_*_with_items, add_project_note).
 *
 * Returns a ToolErrorResponse if invalid; null if valid.
 *
 * History: an earlier version of this helper required notes to begin with a
 * date literal (e.g. "4/6 — …"). That regex was removed in 2026-04 — it
 * fought the actual convention, which is: user-authored prose at the top of
 * the notes field, AI-authored audit lines (if any) BELOW the prose with a
 * blank-line separator. Forcing a date to the top pushed user prose below and
 * produced unreadable records. The createdAt/updatedAt timestamps on the
 * document already capture "when"; the notes field should capture "what" in
 * the reader's natural order.
 */
export function requireNonEmptyNote(notes: string | undefined, toolName: string): ToolErrorResponse | null {
  if (!notes || notes.trim().length < 3) {
    return validation(
      "`notes` is required and cannot be empty.",
      `Provide a short description of what this record represents — a sentence or two is fine. The createdAt timestamp records the date; the notes field should describe what, not when.`,
      { tool: toolName }
    );
  }
  return null;
}
