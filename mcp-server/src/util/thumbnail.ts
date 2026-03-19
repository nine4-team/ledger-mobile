import sharp from "sharp";

export interface ThumbnailResult {
  sm?: Buffer;
  md?: Buffer;
}

/**
 * Generate sm (300px) and md (800px) JPEG thumbnails from image data.
 * Skips non-image content types (PDFs, files).
 *
 * Mirrors: iOS `ImageThumbnailGenerator.generateThumbnailData(from:size:)`
 * - Same max dimensions: sm=300, md=800
 * - Same quality: 1.0 (100%)
 * - Same behavior: skips if source is smaller than target (withoutEnlargement)
 */
export async function generateThumbnails(
  data: Buffer,
  contentType: string
): Promise<ThumbnailResult> {
  if (!contentType.startsWith("image/")) return {};

  const [sm, md] = await Promise.all([
    sharp(data)
      .resize(300, 300, { fit: "inside", withoutEnlargement: true })
      .jpeg({ quality: 100 })
      .toBuffer()
      .catch(() => undefined),
    sharp(data)
      .resize(800, 800, { fit: "inside", withoutEnlargement: true })
      .jpeg({ quality: 100 })
      .toBuffer()
      .catch(() => undefined),
  ]);

  return { sm, md };
}

/**
 * Derive thumbnail storage path from original path.
 * "accounts/x/transactions/y/image.jpg" → "accounts/x/transactions/y/image_sm.jpg"
 *
 * Mirrors: iOS `ImageThumbnailGenerator.thumbnailPath(for:size:)`
 */
export function thumbnailPath(
  originalPath: string,
  size: "sm" | "md"
): string {
  const dotIdx = originalPath.lastIndexOf(".");
  const base = dotIdx > 0 ? originalPath.slice(0, dotIdx) : originalPath;
  return `${base}_${size}.jpg`;
}
