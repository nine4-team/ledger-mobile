import { withSupabase } from "@supabase/server"
import { maximumAttachmentBytes, observeStoredAttachment } from "../_shared/observe-attachment.ts"
import { environment, serviceHeaders } from "../_shared/service-credentials.ts"

const identifier = /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$/
const json = (status: number, body: unknown) => Response.json(body, {
  status, headers: { "cache-control": "no-store" },
})

export default {
  fetch: withSupabase({ auth: "user" }, async (request, context) => {
    if (request.method !== "POST") return json(405, { error: "method_not_allowed" })
    let attachmentId: string
    try {
      const length = Number(request.headers.get("content-length") ?? "0")
      if (!Number.isFinite(length) || length > 1024) return json(413, { error: "request_too_large" })
      const text = await request.text()
      if (text.length > 1024) return json(413, { error: "request_too_large" })
      const payload = JSON.parse(text)
      if (typeof payload?.attachmentId !== "string" || !identifier.test(payload.attachmentId)) {
        return json(400, { error: "invalid_attachment_id" })
      }
      attachmentId = payload.attachmentId
    } catch { return json(400, { error: "invalid_request" }) }
    try {
      const userID = context.userClaims?.id
      if (typeof userID !== "string") return json(401, { error: "authentication_required" })
      const { data: reservation, error } = await context.supabase.rpc("spike_read_expense_attachment_upload", {
        p_upload_id: attachmentId,
      })
      if (error || !reservation || reservation.id !== attachmentId ||
          !identifier.test(reservation.account_id) || !identifier.test(reservation.project_id) ||
          !identifier.test(reservation.expense_id) || !/^[0-9a-f]{64}$/.test(reservation.content_sha256) ||
          !Number.isSafeInteger(Number(reservation.byte_count)) || Number(reservation.byte_count) < 1 ||
          Number(reservation.byte_count) > maximumAttachmentBytes ||
          !(/^image\/[a-z0-9][a-z0-9.+-]{0,126}$/.test(reservation.media_type) || reservation.media_type === "application/pdf") ||
          reservation.storage_path !== `accounts/${reservation.account_id}/attachments/${attachmentId}/${reservation.content_sha256}`) {
        return json(404, { error: "expense_upload_unavailable" })
      }
      const observed = await observeStoredAttachment(environment("SUPABASE_URL").replace(/\/$/, ""), reservation, serviceHeaders())
      if (!observed) return json(409, { error: "attachment_upload_incomplete" })
      const { data, error: publicationError } = await context.supabaseAdmin.rpc("spike_publish_verified_expense_attachment", {
        p_auth_user_id: userID, p_upload_id: attachmentId, p_observed_sha256: observed.sha256,
        p_observed_byte_count: observed.byteCount, p_observed_media_type: observed.mediaType,
      })
      if (publicationError) {
        if (publicationError.code === "42501") return json(403, { error: "expense_upload_unavailable" })
        if (publicationError.code === "PT409" && ["stored_bytes_mismatch", "attachment_upload_incomplete", "attachment_identity_conflict"].includes(publicationError.message)) {
          return json(409, { error: publicationError.message })
        }
        return json(502, { error: "publication_failed" })
      }
      return json(200, data)
    } catch { return json(502, { error: "verification_unavailable" }) }
  }),
}
