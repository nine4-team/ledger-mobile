/**
 * Lightweight tool-call telemetry.
 *
 * Logs structured JSON lines to stderr for every wrapped tool handler.
 * This is intentionally simple — no Firestore writes, no external service —
 * so it can ship today without infra changes. Cloud Run captures stderr
 * into Cloud Logging automatically, and a future `get_tool_stats` tool
 * can read from there.
 *
 * Wrap a tool handler with `withTelemetry("tool_name", handler)` at
 * registration time. The wrapper preserves the handler's signature so
 * the MCP SDK type inference keeps working.
 */

export interface ToolCallLog {
  event: "mcp_tool_call";
  tool: string;
  ok: boolean;
  durationMs: number;
  responseBytes: number;
  errorCode?: string;
  timestamp: string;
}

type AnyHandler = (...args: any[]) => Promise<any>;

function estimateResponseBytes(result: unknown): number {
  try {
    const r = result as { content?: Array<{ text?: string }> } | undefined;
    if (!r?.content) return 0;
    let bytes = 0;
    for (const c of r.content) {
      if (typeof c?.text === "string") bytes += c.text.length;
    }
    return bytes;
  } catch {
    return 0;
  }
}

function extractErrorCode(result: unknown): string | undefined {
  try {
    const r = result as { isError?: boolean; content?: Array<{ text?: string }> };
    if (!r?.isError) return undefined;
    const text = r.content?.[0]?.text;
    if (!text) return "UNKNOWN";
    try {
      const parsed = JSON.parse(text);
      return parsed?.error?.code ?? "UNKNOWN";
    } catch {
      return "LEGACY_TEXT_ERROR";
    }
  } catch {
    return undefined;
  }
}

export function withTelemetry<H extends AnyHandler>(tool: string, handler: H): H {
  const wrapped = async (...args: Parameters<H>) => {
    const start = Date.now();
    let result: unknown;
    let thrown: unknown;
    try {
      result = await handler(...args);
    } catch (err) {
      thrown = err;
    }
    const durationMs = Date.now() - start;

    if (thrown) {
      const log: ToolCallLog = {
        event: "mcp_tool_call",
        tool,
        ok: false,
        durationMs,
        responseBytes: 0,
        errorCode: "THROWN",
        timestamp: new Date().toISOString(),
      };
      console.error(JSON.stringify(log));
      throw thrown;
    }

    const errorCode = extractErrorCode(result);
    const log: ToolCallLog = {
      event: "mcp_tool_call",
      tool,
      ok: !errorCode,
      durationMs,
      responseBytes: estimateResponseBytes(result),
      ...(errorCode ? { errorCode } : {}),
      timestamp: new Date().toISOString(),
    };
    console.error(JSON.stringify(log));
    return result;
  };
  return wrapped as H;
}
