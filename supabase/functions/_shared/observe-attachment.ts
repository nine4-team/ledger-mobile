// Both Transaction and Expense publication verify the same immutable Storage bytes.
export const maximumAttachmentBytes = 64 * 1024 * 1024

export type StoredAttachment = { storage_path: string }
export type ObservedObject = { sha256: string; byteCount: number; mediaType: string }

async function readBounded(body: ReadableStream<Uint8Array> | null, maximum: number): Promise<Uint8Array> {
  if (!body) throw new Error("stored_object_body_missing")
  const reader = body.getReader()
  const chunks: Uint8Array[] = []
  let count = 0
  try {
    while (true) {
      const { done, value } = await reader.read()
      if (done) break
      count += value.byteLength
      if (count > maximum) {
        await reader.cancel()
        throw new Error("stored_object_too_large")
      }
      chunks.push(value)
    }
  } finally { reader.releaseLock() }
  const result = new Uint8Array(count)
  let offset = 0
  for (const chunk of chunks) { result.set(chunk, offset); offset += chunk.byteLength }
  return result
}

// Callers authorize and validate the reservation before using this privileged read.
export async function observeStoredAttachment(baseURL: string, reservation: StoredAttachment,
  headers: HeadersInit, transport: typeof fetch = fetch): Promise<ObservedObject | null> {
  const segments = reservation.storage_path.split("/").map(encodeURIComponent).join("/")
  const response = await transport(`${baseURL}/storage/v1/object/authenticated/ledger-attachments/${segments}`, {
    headers, redirect: "error",
  })
  if (response.status === 404) return null
  if (response.status === 400) {
    // Storage wraps NoSuchKey in HTTP 400 with a 404 payload.
    const failure = await response.json().catch(() => null)
    if (failure?.code === "NoSuchKey" && String(failure.statusCode) === "404") return null
  }
  if (response.status !== 200) throw new Error(`storage_read_${response.status}`)
  const declaredLength = response.headers.get("content-length")
  if (declaredLength && (!/^\d+$/.test(declaredLength) || Number(declaredLength) > maximumAttachmentBytes)) {
    await response.body?.cancel()
    return { sha256: "0".repeat(64), byteCount: Number(declaredLength) || 0,
      mediaType: response.headers.get("content-type")?.split(";")[0].trim().toLowerCase() ?? "" }
  }
  const bytes = await readBounded(response.body, maximumAttachmentBytes)
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))
  return {
    sha256: [...digest].map((byte) => byte.toString(16).padStart(2, "0")).join(""),
    byteCount: bytes.byteLength,
    mediaType: response.headers.get("content-type")?.split(";")[0].trim().toLowerCase() ?? "",
  }
}
