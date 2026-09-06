const IDENTIFIER = /^[\p{L}\p{N}_.:-]+$/u;

export type TargetMCPRequestContext = Readonly<{
  accountId: string;
  principalId: string;
  accessToken: string;
}>;

export class TargetMCPFailure extends Error {
  readonly code: string;
  readonly statusCode: number | undefined;

  constructor(code: string, statusCode?: number) {
    super(code);
    this.name = "TargetMCPFailure";
    this.code = code;
    this.statusCode = statusCode;
  }
}

export function validateIdentifier(value: string, code: string): string {
  const bytes = new TextEncoder().encode(value);
  if (
    value.trim() !== value
    || bytes.length === 0
    || bytes.length > 128
    || !IDENTIFIER.test(value)
  ) {
    throw new TargetMCPFailure(code);
  }
  return value;
}

export function canonicalJSON(value: unknown, encodingFailureCode: string): string {
  if (value === null || typeof value === "boolean" || typeof value === "number") {
    return JSON.stringify(value);
  }
  if (typeof value === "string") {
    return JSON.stringify(value).replaceAll("/", "\\/");
  }
  if (Array.isArray(value)) {
    return `[${value.map((item) => canonicalJSON(item, encodingFailureCode)).join(",")}]`;
  }
  if (typeof value === "object") {
    const record = value as Record<string, unknown>;
    return `{${Object.keys(record)
      .sort()
      .map((key) => `${canonicalJSON(key, encodingFailureCode)}:${canonicalJSON(record[key], encodingFailureCode)}`)
      .join(",")}}`;
  }
  throw new TargetMCPFailure(encodingFailureCode);
}

export function validateTerminalResult(
  phase: unknown,
  resultCode: unknown,
  errorCode: unknown,
  mismatchCode: string,
): asserts phase is "applied" | "rejected" {
  if (
    (phase !== "applied" && phase !== "rejected")
    || (phase === "applied" && (typeof resultCode !== "string" || errorCode !== null))
    || (phase === "rejected" && (resultCode !== null || typeof errorCode !== "string"))
  ) {
    throw new TargetMCPFailure(mismatchCode);
  }
}
