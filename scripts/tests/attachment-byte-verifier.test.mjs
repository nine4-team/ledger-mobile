import test from 'node:test'
import assert from 'node:assert/strict'
import { createHash } from 'node:crypto'
import { maximumAttachmentBytes, observeStoredAttachment } from '../../supabase/functions/_shared/observe-attachment.ts'

const path = { storage_path: 'accounts/a/attachments/receipt:1/hash' }
const observe = (response) => observeStoredAttachment('https://example.test', path, {}, async () => response)

test('hashes actual bytes and normalizes MIME using authenticated Storage path', async () => {
  const bytes = new TextEncoder().encode('receipt bytes')
  const result = await observeStoredAttachment('https://example.test', path, { apikey: 'test' }, async (url, init) => {
    assert.equal(url, 'https://example.test/storage/v1/object/authenticated/ledger-attachments/accounts/a/attachments/receipt%3A1/hash')
    assert.equal(init.redirect, 'error')
    assert.equal(init.headers.apikey, 'test')
    return new Response(bytes, { headers: { 'content-type': 'Application/PDF; charset=binary' } })
  })
  assert.deepEqual(result, { sha256: createHash('sha256').update(bytes).digest('hex'), byteCount: bytes.length, mediaType: 'application/pdf' })
})

test('only actual missing-object responses are retryable absence', async () => {
  assert.equal(await observe(new Response(null, { status: 404 })), null)
  assert.equal(await observe(Response.json({ code: 'NoSuchKey', statusCode: '404' }, { status: 400 })), null)
  await assert.rejects(observe(Response.json({ code: 'AccessDenied', statusCode: '404' }, { status: 400 })), /storage_read_400/)
  await assert.rejects(observe(new Response(null, { status: 403 })), /storage_read_403/)
})

test('oversize declared body is cancelled without downloading it', async () => {
  let cancelled = false
  const stream = new ReadableStream({ cancel() { cancelled = true } })
  const result = await observe(new Response(stream, { headers: { 'content-length': String(maximumAttachmentBytes + 1) } }))
  assert.equal(cancelled, true)
  assert.equal(result.byteCount, maximumAttachmentBytes + 1)
  assert.equal(result.sha256, '0'.repeat(64))
})

test('streaming limit applies even when declared size lies', async () => {
  let cancelled = false
  const stream = new ReadableStream({
    start(controller) { controller.enqueue(new Uint8Array(maximumAttachmentBytes + 1)) },
    cancel() { cancelled = true },
  })
  await assert.rejects(observe(new Response(stream, { headers: { 'content-length': '1' } })), /stored_object_too_large/)
  assert.equal(cancelled, true)
})

test('missing response body cannot become verified empty receipt', async () => {
  await assert.rejects(observe(new Response(null)), /stored_object_body_missing/)
})
