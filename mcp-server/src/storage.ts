import { getStorage } from "firebase-admin/storage";
import { randomUUID } from "node:crypto";

const BUCKET_NAME = "ledger-nine4.firebasestorage.app";

/**
 * Upload a buffer to Firebase Storage and return a permanent download URL.
 *
 * Uses the `firebaseStorageDownloadTokens` metadata convention to produce
 * the same permanent token-based URLs that the iOS client SDK's
 * `StorageReference.downloadURL()` returns. The admin SDK has no equivalent
 * to the client SDK's `getDownloadURL()` — this is the standard workaround.
 *
 * Mirrors: iOS `MediaService.uploadData()` → `FirebaseStorageUploader.putData()`
 * Path convention: `accounts/{accountId}/{entityType}/{entityId}/{filename}`
 */
export async function uploadToStorage(
  path: string,
  data: Buffer,
  contentType: string
): Promise<string> {
  const bucket = getStorage().bucket(BUCKET_NAME);
  const file = bucket.file(path);
  const token = randomUUID();

  await file.save(data, {
    metadata: {
      contentType,
      metadata: { firebaseStorageDownloadTokens: token },
    },
  });

  const encodedPath = encodeURIComponent(path);
  return `https://firebasestorage.googleapis.com/v0/b/${BUCKET_NAME}/o/${encodedPath}?alt=media&token=${token}`;
}

/**
 * Delete a file from Storage given its download URL.
 * Mirrors: iOS `MediaService.deleteImage(url:)`
 */
export async function deleteFromStorage(url: string): Promise<void> {
  const match = url.match(/\/o\/([^?]+)/);
  if (!match) throw new Error("Cannot parse storage path from URL");
  const path = decodeURIComponent(match[1]);
  await getStorage().bucket(BUCKET_NAME).file(path).delete();
}
