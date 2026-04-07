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
 * Enforce that a mutation call carries a dated audit note.
 * Returns a ToolErrorResponse if invalid; null if valid.
 *
 * Accepted format: anything starting with a digit (month) — e.g. "4/6 — moved 3 fixtures…".
 * Minimum length 8 chars so we reject "x" or empty strings.
 */
export function requireAuditNote(notes: string | undefined, toolName: string): ToolErrorResponse | null {
  if (!notes || notes.trim().length < 8) {
    return validation(
      "`notes` is required and must be a short dated audit note.",
      `Include a dated note like "4/6 — short description of what changed and why". This preserves the audit trail on every mutation.`,
      { tool: toolName }
    );
  }
  if (!/^\s*\d/.test(notes)) {
    return validation(
      "`notes` must begin with a date.",
      `Prefix the note with today's date, e.g. "4/6 — moved 3 fixtures to Witzenman".`,
      { tool: toolName, received: notes.slice(0, 40) }
    );
  }
  return null;
}
