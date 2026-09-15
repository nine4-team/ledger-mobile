import { z } from "zod";
import { TargetMCPFailure, validateIdentifier, type TargetMCPRequestContext } from "./contractSupport.js";

const identifier = z.string().refine(v => {
  try { validateIdentifier(v, "invalid"); return true; } catch { return false; }
});
const position = z.number().int().min(0).max(2147483647);
const revision = z.string().max(19).refine(v => v.length <= 19 && /^[1-9][0-9]*$/.test(v)
  && String(BigInt(v)) === v && BigInt(v) <= 9223372036854775807n);
export const transactionAttachmentInputSchema = z.object({
  transactionId: identifier, section: z.enum(["receipts", "other"]),
  startPosition: position.default(0), limit: z.number().int().min(1).max(100).default(50),
  revision: revision.optional(),
}).strict().refine(v => v.startPosition === 0 || v.revision !== undefined);
export type TransactionAttachmentInput = z.input<typeof transactionAttachmentInputSchema>;
const pageSchema = z.object({
  accountId: identifier, principalId: identifier, transactionId: identifier,
  scopeKind: z.enum(["project", "business_inventory"]), projectId: identifier.nullable(), clientId: identifier.nullable(),
  section: z.enum(["receipts", "other"]), revision: revision.nullable(), expectedCount: position.nullable(),
  startPosition: position, isComplete: z.boolean(), nextPosition: position.nullable(),
  attachments: z.array(z.object({ id: identifier, position, isPrimary: z.boolean(),
    kind: z.enum(["image", "pdf"]), fileName: z.string().nullable() }).strict()).max(100),
}).strict();
export type TransactionAttachmentPage = z.infer<typeof pageSchema>;

/** Public reference metadata only; never accept provider paths or byte credentials. */
export function transactionAttachmentPage(value: unknown, input: TransactionAttachmentInput,
    context: TargetMCPRequestContext): TransactionAttachmentPage {
  try {
    const request = transactionAttachmentInputSchema.parse(input), page = pageSchema.parse(value);
    if (page.accountId !== context.accountId || page.principalId !== context.principalId
      || page.transactionId !== request.transactionId || page.section !== request.section
      || page.startPosition !== request.startPosition || page.attachments.length > request.limit
      || (page.scopeKind === "project" ? page.projectId === null || page.clientId === null
        : page.projectId !== null || page.clientId !== null)
      || (request.revision !== undefined && request.revision !== page.revision)) throw new Error("scope/revision");
    if (page.revision === null) {
      if (page.expectedCount !== null || page.startPosition !== 0 || page.isComplete
        || page.nextPosition !== null || page.attachments.length) throw new Error("unknown is not empty");
      return page;
    }
    if (page.expectedCount === null || page.startPosition > page.expectedCount
      || page.attachments.length !== Math.min(request.limit, page.expectedCount - page.startPosition)
      || page.attachments.some((v, i) => v.position !== page.startPosition + i)
      || new Set(page.attachments.map(v => v.id)).size !== page.attachments.length
      || page.attachments.filter(v => v.isPrimary).length > 1) throw new Error("page coverage");
    const end = page.startPosition + page.attachments.length;
    if (page.nextPosition !== (end < page.expectedCount ? end : null)
      || page.isComplete !== (page.startPosition === 0 && end === page.expectedCount)) throw new Error("completeness");
    return page;
  } catch { throw new TargetMCPFailure("transaction_attachment_server_result_mismatch"); }
}

/** Bound decoded response bytes too, not just row count. No body/error logging. */
export async function attachmentResponseJSON(response: Response): Promise<unknown> {
  const reader = response.body?.getReader();
  if (!reader) throw new TargetMCPFailure("transaction_attachment_server_result_mismatch");
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    while (true) {
      const chunk = await reader.read();
      if (chunk.done) break;
      size += chunk.value.byteLength;
      if (size > 2 * 1024 * 1024) {
        await reader.cancel();
        throw new TargetMCPFailure("transaction_attachment_response_too_large");
      }
      chunks.push(chunk.value);
    }
    return JSON.parse(Buffer.concat(chunks).toString("utf8"));
  } finally { reader.releaseLock(); }
}
