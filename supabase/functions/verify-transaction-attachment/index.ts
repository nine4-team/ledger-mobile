import { withSupabase } from "@supabase/server"
import { maximumAttachmentBytes, observeStoredAttachment } from "../_shared/observe-attachment.ts"
import { environment, serviceHeaders } from "../_shared/service-credentials.ts"

const maximumBytes = maximumAttachmentBytes
const identifier = /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$/
const sha256 = /^[0-9a-f]{64}$/

type Reservation = {
  id: string
  account_id: string
  principal_id: string
  transaction_id: string
  section: "receipts" | "other"
  content_sha256: string
  byte_count: number | string
  media_type: string
  storage_path: string
}

function json(status: number, body: unknown): Response {
  return Response.json(body, { status, headers: { "cache-control": "no-store" } })
}

function validatedReservation(value: Reservation | null): Reservation | null {
  if (!value || !identifier.test(value.id) || !identifier.test(value.account_id) ||
      !identifier.test(value.transaction_id) || !sha256.test(value.content_sha256) ||
      !["receipts", "other"].includes(value.section)) return null
  const bytes = Number(value.byte_count)
  const image = /^image\/[a-z0-9][a-z0-9.+-]{0,126}$/.test(value.media_type)
  if (!Number.isSafeInteger(bytes) || bytes < 1 || bytes > maximumBytes ||
      (!image && !(value.section === "receipts" && value.media_type === "application/pdf"))) return null
  const expectedPath = `accounts/${value.account_id}/attachments/${value.id}/${value.content_sha256}`
  return value.storage_path === expectedPath ? value : null
}

export default {
  fetch: withSupabase({ auth: "user" }, async (request, context) => {
    if (request.method !== "POST") return json(405, { error: "method_not_allowed" })
    const length = Number(request.headers.get("content-length") ?? "0")
    if (!Number.isFinite(length) || length > 1024) return json(413, { error: "request_too_large" })
    let payload: { attachmentId?: unknown } | null
    try {
      const text = await request.text()
      if (text.length > 1024) return json(413, { error: "request_too_large" })
      payload = JSON.parse(text)
    } catch { return json(400, { error: "invalid_request" }) }
    if (typeof payload?.attachmentId !== "string" || !identifier.test(payload.attachmentId)) {
      return json(400, { error: "invalid_attachment_id" })
    }

    try {
      const baseURL = environment("SUPABASE_URL").replace(/\/$/, "")
      const userID = context.userClaims?.id
      if (typeof userID !== "string") return json(401, { error: "authentication_required" })
      const columns = "id,account_id,principal_id,transaction_id,section,content_sha256,byte_count,media_type,storage_path"
      const { data, error } = await context.supabase.from("transaction_attachment_uploads")
        .select(columns).eq("id", payload.attachmentId).maybeSingle()
      if (error) return json(404, { error: "attachment_upload_unavailable" })
      const reservation = validatedReservation(data as Reservation | null)
      if (!reservation) return json(404, { error: "attachment_upload_unavailable" })
      const observed = await observeStoredAttachment(baseURL, reservation, serviceHeaders())
      if (!observed) return json(409, { error: "attachment_upload_incomplete" })
      const { data: result, error: publicationError } = await context.supabaseAdmin.rpc(
        "spike_publish_verified_transaction_attachment", {
          p_auth_user_id: userID,
          p_upload_id: reservation.id,
          p_observed_sha256: observed.sha256,
          p_observed_byte_count: observed.byteCount,
          p_observed_media_type: observed.mediaType,
        },
      )
      if (publicationError) {
        console.error("attachment publication failed", publicationError.code, publicationError.message)
        return json(502, { error: "publication_failed" })
      }
      return json(200, result)
    } catch {
      return json(502, { error: "verification_unavailable" })
    }
  }),
}
