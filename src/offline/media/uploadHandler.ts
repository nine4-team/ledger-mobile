import storage from '@react-native-firebase/storage';
import { isFirebaseConfigured } from '../../firebase/firebase';
import type { MediaRecord, UploadJob } from './types';

/**
 * Global upload handler for offline media.
 *
 * This handler:
 * 1. Resolves offline://<mediaId> to local file path from MediaRecord
 * 2. Uploads the local file to Firebase Storage
 * 3. Returns the remote storage URL
 * 4. Handles errors and integrates with mediaStore job tracking
 */
export async function uploadMediaToFirebaseStorage(
  record: MediaRecord,
  job: UploadJob
): Promise<{ remoteUrl: string }> {
  if (!isFirebaseConfigured) {
    throw new Error('Firebase is not configured. Cannot upload media.');
  }

  if (!record.localUri) {
    throw new Error(`Media record ${record.id} has no local URI.`);
  }

  // Determine destination path
  // If job has destinationPath, use it; otherwise generate a default path
  const destinationPath =
    job.destinationPath ||
    generateDefaultStoragePath(record);

  const storageRef = storage().ref(destinationPath);

  try {
    // Upload file to Firebase Storage
    const uploadTask = storageRef.putFile(
      record.localUri,
      record.mimeType ? { contentType: record.mimeType } : undefined
    );

    // Optional: Add upload progress tracking
    // uploadTask.on('state_changed', (snapshot) => {
    //   const progress = (snapshot.bytesTransferred / snapshot.totalBytes) * 100;
    //   console.log(`Upload is ${progress}% done`);
    // });

    // Wait for upload to complete
    await uploadTask;

    // Get the download URL
    const remoteUrl = await storageRef.getDownloadURL();

    return { remoteUrl };
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unknown upload error';
    throw new Error(`Failed to upload media ${record.id}: ${message}`);
  }
}

/**
 * Generates a default storage path for media files.
 * Pattern: attachments/{ownerScope}/{mediaId}/{filename}
 * Falls back to: attachments/unknown/{mediaId}/{filename}
 */
function generateDefaultStoragePath(record: MediaRecord): string {
  const scope = record.ownerScope || 'unknown';
  const extension = getFileExtension(record);
  const fileName = `${record.id}${extension}`;

  return `attachments/${scope}/${record.id}/${fileName}`;
}

/**
 * Extracts file extension from media record.
 */
function getFileExtension(record: MediaRecord): string {
  // Try to get extension from mimeType
  if (record.mimeType) {
    const mimeToExt: Record<string, string> = {
      'image/jpeg': '.jpg',
      'image/png': '.png',
      'image/gif': '.gif',
      'image/webp': '.webp',
      'application/pdf': '.pdf',
    };
    const ext = mimeToExt[record.mimeType];
    if (ext) return ext;
  }

  // Try to get extension from localUri
  if (record.localUri) {
    const match = record.localUri.match(/\.([a-zA-Z0-9]+)$/);
    if (match) return `.${match[1]}`;
  }

  // Default fallback
  if (record.mimeType?.startsWith('image/')) return '.jpg';
  if (record.mimeType?.includes('pdf')) return '.pdf';

  return '';
}
