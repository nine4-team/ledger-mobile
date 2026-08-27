import { getStorage } from "firebase-admin/storage";
import { randomUUID } from "node:crypto";

export const BUCKET_NAME = "ledger-nine4.firebasestorage.app";

export function storagePathFromUrl(url: string): string | null {
  try {
    const parsed = new URL(url);
    if (parsed.hostname !== "firebasestorage.googleapis.com") return null;
    const prefix = `/v0/b/${BUCKET_NAME}/o/`;
    if (!parsed.pathname.startsWith(prefix)) return null;
    return decodeURIComponent(parsed.pathname.slice(prefix.length));
  } catch {
    return null;
  }
}

export function storageDownloadUrl(path: string, token: string): string {
  return `https://firebasestorage.googleapis.com/v0/b/${BUCKET_NAME}/o/${encodeURIComponent(path)}?alt=media&token=${token}`;
}

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

  return storageDownloadUrl(path, token);
}

export async function uploadVerifiedToStorage(
  path: string,
  data: Buffer,
  contentType: string
): Promise<string> {
  const url = await uploadToStorage(path, data, contentType);
  const file = getStorage().bucket(BUCKET_NAME).file(path);
  const [exists] = await file.exists();
  if (!exists) throw new Error(`Uploaded Storage object could not be verified: ${path}`);
  const [metadata] = await file.getMetadata();
  if (Number(metadata.size) !== data.length) {
    throw new Error(`Uploaded Storage object size mismatch: ${path}`);
  }
  return url;
}

/** Copy a Firebase Storage object to a new path and verify the persisted byte size. */
export async function copyStorageObject(
  sourceUrl: string,
  destinationPath: string
): Promise<{ url: string; path: string; data: Buffer; contentType: string }> {
  const sourcePath = storagePathFromUrl(sourceUrl);
  if (!sourcePath) throw new Error("Cannot copy a non-Firebase Storage URL.");
  const bucket = getStorage().bucket(BUCKET_NAME);
  const source = bucket.file(sourcePath);
  const [sourceExists] = await source.exists();
  if (!sourceExists) throw new Error(`Source Storage object does not exist: ${sourcePath}`);
  const [[metadata], [data]] = await Promise.all([source.getMetadata(), source.download()]);
  const contentType = metadata.contentType ?? "application/octet-stream";
  const url = await uploadVerifiedToStorage(destinationPath, data, contentType);
  const destination = bucket.file(destinationPath);
  const [destinationExists] = await destination.exists();
  if (!destinationExists) throw new Error(`Copied Storage object could not be verified: ${destinationPath}`);
  const [destinationMetadata] = await destination.getMetadata();
  if (Number(destinationMetadata.size) !== data.length) {
    throw new Error(`Copied Storage object size mismatch: ${destinationPath}`);
  }
  return { url, path: destinationPath, data, contentType };
}

/**
 * Delete a file from Storage given its download URL.
 * Mirrors: iOS `MediaService.deleteImage(url:)`
 */
export async function deleteFromStorage(url: string): Promise<void> {
  const path = storagePathFromUrl(url);
  if (!path) throw new Error("Cannot parse storage path from URL");
  await getStorage().bucket(BUCKET_NAME).file(path).delete();
}
