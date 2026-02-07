# Shared Media Gallery Component Implementation Plan

## Context

Currently, both the Item Detail and Transaction Detail screens duplicate the same gallery management logic: state tracking (visible/index), handlers (add/remove/set primary), thumbnail grid rendering, image picker button, modal gallery, and empty states. This creates maintenance overhead and inconsistency.

Additionally, the Transaction Detail screen needs to support PDF receipts, not just images. The current "Receipt Images" label should change to "Receipts" to reflect this broader scope. While the codebase has a `TransactionAttachmentPreview` component that already handles images + PDFs, it's not currently being used.

This implementation will create a shared `MediaGallerySection` component that:
- Eliminates code duplication across screens
- Encapsulates all gallery state and logic
- Supports both image-only galleries and mixed image+PDF galleries
- Provides consistent UX across all media galleries in the app
- Updates terminology from "Receipt Images" to "Receipts"

## User Requirements Summary

Based on user clarifications:
- **Max receipts**: 10 attachments (higher than regular images)
- **Max other images**: 5 attachments (unchanged)
- **PDF display**: Icon-based (no thumbnail generation needed)
- **File types**: Images and PDFs only (not Word, Excel, etc.)
- **Primary flag**: Available for both images and PDFs

## Implementation Approach

### Component Architecture

Create a single flexible `MediaGallerySection` component that handles everything:

**Component:** `MediaGallerySection.tsx`

**Props:**
```typescript
export type MediaGallerySectionProps = {
  // Content
  title: string;
  attachments: AttachmentRef[];
  maxAttachments?: number;

  // Edit mode
  isEditing: boolean;

  // File type support
  allowedKinds?: AttachmentKind[]; // Default: ['image']. For receipts: ['image', 'pdf']

  // Handlers (all use AttachmentRef, not just URL strings)
  onAddAttachment?: (localUri: string, kind: AttachmentKind) => Promise<void>;
  onRemoveAttachment?: (attachment: AttachmentRef) => Promise<void>;
  onSetPrimary?: (attachment: AttachmentRef) => Promise<void>;

  // Display customization
  size?: 'sm' | 'md' | 'lg';
  tileScale?: number;
  emptyStateMessage?: string;
  pickerLabel?: string; // "Add image" vs "Add receipt"

  // Style overrides
  style?: ViewStyle;
};
```

**Internal Structure:**
- Wraps content in `TitledCard` with customizable title
- Manages gallery modal state internally (no parent state needed)
- Separates images from PDFs for appropriate rendering
- Uses `ThumbnailGrid` for images
- Uses custom file tiles for PDFs (icon + label)
- Shows `ImagePickerButton` when editing and under max
- Handles empty state with customizable message
- Uses `ImageGallery` modal for full-screen image viewing
- PDFs open via `Linking.openURL()` when tapped

### File Type Support

**Extend ImagePickerButton** to support document picking:

1. Add `allowedKinds` prop to determine picker options
2. Add `expo-document-picker` for PDF selection
3. Update callback signature: `onFilePicked: (uri: string, kind: AttachmentKind) => void`
4. Show appropriate menu items:
   - Images only: Camera, Photo Library
   - Images + PDFs: Camera, Photo Library, Files (documents)
5. Update labels to be generic: "Add image" vs "Add receipt"

**Note:** `expo-document-picker` is already available in the project's dependencies, so no new packages needed.

### Migration Strategy

**Phase 1:** Create new components
- Build `MediaGallerySection.tsx` (new)
- Extend `ImagePickerButton.tsx` (modify)
- No breaking changes to existing code

**Phase 2:** Update Transaction Detail
- Replace "Receipt Images" section with MediaGallerySection
- Replace "Other Images" section with MediaGallerySection
- Remove manual state management (galleryVisible, galleryIndex for both sections)
- Update handlers to accept `AttachmentKind` parameter
- Update `handlePickReceiptImage` to `handlePickReceiptAttachment` with kind support

**Phase 3:** Update Item Detail
- Replace manual gallery implementation with MediaGallerySection
- Remove inline TextInput fields (URL/local URI inputs)
- Simplify handlers to work with MediaGallerySection API
- Remove manual state management

## Critical Files

### New Files
- `/Users/benjaminmackenzie/Dev/ledger_mobile/src/components/MediaGallerySection.tsx` - Main shared component

### Modified Files
- `/Users/benjaminmackenzie/Dev/ledger_mobile/src/components/ImagePickerButton.tsx` - Add PDF/document picking support
- `/Users/benjaminmackenzie/Dev/ledger_mobile/app/transactions/[id].tsx` - Use MediaGallerySection, update handlers
- `/Users/benjaminmackenzie/Dev/ledger_mobile/app/items/[id].tsx` - Use MediaGallerySection, simplify implementation

### Reference Files (unchanged, used internally)
- `/Users/benjaminmackenzie/Dev/ledger_mobile/src/components/ThumbnailGrid.tsx` - Used for image rendering
- `/Users/benjaminmackenzie/Dev/ledger_mobile/src/components/ImageGallery.tsx` - Used for full-screen image viewing
- `/Users/benjaminmackenzie/Dev/ledger_mobile/src/components/TitledCard.tsx` - Used for container wrapper
- `/Users/benjaminmackenzie/Dev/ledger_mobile/src/components/TransactionAttachmentPreview.tsx` - Reference for PDF tile rendering pattern

## Implementation Details

### MediaGallerySection Internal Logic

```typescript
// Separate images from PDFs
const imageAttachments = attachments.filter(a => a.kind === 'image');
const pdfAttachments = attachments.filter(a => a.kind === 'pdf');

// Internal state (not exposed to parent)
const [galleryVisible, setGalleryVisible] = useState(false);
const [galleryIndex, setGalleryIndex] = useState(0);

// Render structure
<TitledCard title={title}>
  {attachments.length > 0 ? (
    <>
      {/* Image thumbnails */}
      {imageAttachments.length > 0 && (
        <ThumbnailGrid
          images={imageAttachments}
          onImagePress={(img, idx) => { setGalleryIndex(idx); setGalleryVisible(true); }}
          onSetPrimary={onSetPrimary}
          onDelete={onRemoveAttachment}
        />
      )}

      {/* PDF file tiles */}
      {pdfAttachments.length > 0 && (
        <View style={styles.fileGrid}>
          {/* PDF icon tiles with menu */}
        </View>
      )}

      {/* Add button if under max */}
      {isEditing && attachments.length < maxAttachments && (
        <ImagePickerButton
          allowedKinds={allowedKinds}
          onFilePicked={onAddAttachment}
          label={pickerLabel}
        />
      )}
    </>
  ) : (
    <EmptyState message={emptyStateMessage} />
  )}
</TitledCard>

{/* Image gallery modal (images only) */}
<ImageGallery
  images={imageAttachments}
  visible={galleryVisible}
  initialIndex={galleryIndex}
  onRequestClose={() => setGalleryVisible(false)}
/>
```

### Transaction Detail Handler Updates

```typescript
// Updated handler signature (accepts kind parameter)
const handlePickReceiptAttachment = async (localUri: string, kind: AttachmentKind) => {
  if (!accountId || !id || !transaction) return;

  const mimeType = kind === 'pdf' ? 'application/pdf' : 'image/jpeg';
  const result = await saveLocalMedia({
    localUri,
    mimeType,
    ownerScope: `transaction:${id}`,
    persistCopy: true,
  });

  const currentAttachments = transaction.receiptImages ?? [];
  const hasPrimary = currentAttachments.some(att => att.isPrimary);

  const newAttachment: AttachmentRef = {
    url: result.attachmentRef.url,
    kind,
    isPrimary: !hasPrimary && kind === 'image', // Only images can be primary initially
  };

  const nextAttachments = [...currentAttachments, newAttachment].slice(0, 10);
  await updateTransaction(accountId, id, {
    receiptImages: nextAttachments,
    transactionImages: nextAttachments
  });

  await enqueueUpload({ mediaId: result.mediaId });
};

// Simplified usage (no manual state management)
<MediaGallerySection
  title="Receipts"
  attachments={transaction.receiptImages ?? []}
  maxAttachments={10}
  allowedKinds={['image', 'pdf']}
  isEditing={isEditing}
  onAddAttachment={handlePickReceiptAttachment}
  onRemoveAttachment={handleRemoveReceiptAttachment}
  onSetPrimary={handleSetPrimaryReceiptAttachment}
  emptyStateMessage="No receipts yet."
  pickerLabel="Add receipt"
/>
```

### ImagePickerButton Extensions

```typescript
// Add expo-document-picker import
import * as DocumentPicker from 'expo-document-picker';

// Updated props
export type ImagePickerButtonProps = {
  onFilePicked: (uri: string, kind: AttachmentKind) => void; // Changed from onImagePicked
  allowedKinds?: AttachmentKind[]; // Default: ['image']
  maxFiles?: number; // Renamed from maxImages
  currentFileCount?: number; // Renamed from currentImageCount
  label?: string; // Customizable label
  style?: any;
};

// Document picker handler
const handlePickDocument = useCallback(async () => {
  setMenuVisible(false);
  const result = await DocumentPicker.getDocumentAsync({
    type: 'application/pdf',
    copyToCacheDirectory: true,
  });
  if (result.type === 'success') {
    onFilePicked(result.uri, 'pdf');
  }
}, [onFilePicked]);

// Menu items based on allowedKinds
const menuItems: AnchoredMenuItem[] = [
  {
    label: 'Camera',
    onPress: handleTakePhoto,
    icon: 'camera-alt',
  },
  {
    label: 'Photo Library',
    onPress: handlePickFromLibrary,
    icon: 'photo-library',
  },
];

if (allowedKinds?.includes('pdf')) {
  menuItems.push({
    label: 'Files',
    onPress: handlePickDocument,
    icon: 'insert-drive-file',
  });
}
```

### PDF Tile Rendering (within MediaGallerySection)

```typescript
// PDF tile component (following TransactionAttachmentPreview pattern)
{pdfAttachments.map((attachment, index) => (
  <Pressable
    key={attachment.url}
    onPress={() => {
      const resolvedUri = resolveAttachmentUri(attachment);
      if (resolvedUri) {
        Linking.openURL(resolvedUri);
      }
    }}
    style={[styles.fileTile, { width: tileSize, height: tileSize }]}
  >
    <MaterialIcons
      name="picture-as-pdf"
      size={32}
      color={uiKitTheme.text.secondary}
    />
    <AppText variant="caption" numberOfLines={1}>
      {attachment.fileName || 'PDF'}
    </AppText>

    {/* Primary badge if applicable */}
    {attachment.isPrimary && (
      <View style={styles.primaryBadge}>
        <MaterialIcons name="star" size={12} color="#FFFFFF" />
      </View>
    )}

    {/* Options menu */}
    <Pressable
      onPress={(e) => handleOptionsPress(attachment, index, e)}
      style={styles.optionsButton}
    >
      <MaterialIcons name="more-vert" size={14} />
    </Pressable>
  </Pressable>
))}
```

## Data Model Considerations

**No schema changes needed.** The `AttachmentRef` type already supports:
```typescript
type AttachmentRef = {
  url: string;
  kind: 'image' | 'pdf' | 'file';
  fileName?: string;
  contentType?: string;
  isPrimary?: boolean;
};
```

**Transaction model:** The `receiptImages` field semantically expands to include PDFs (no schema change, just broader interpretation).

## Terminology Updates

| Location | Old | New |
|----------|-----|-----|
| Transaction Detail | "Receipt Images" | "Receipts" |
| Transaction Detail empty state | "No receipt images yet." | "No receipts yet." |
| ImagePickerButton (receipts mode) | "Add image" | "Add receipt" |
| Menu title (when PDFs present) | "Image options" | "Attachment options" |

## Edge Cases & Considerations

1. **Primary flag on PDFs**: User is ok with primary flag on any attachment type. However, initially only images will be marked primary by default (first image added). PDFs can be manually marked primary via the menu.

2. **Mixed galleries**: ImageGallery modal only shows images (PDFs excluded). PDFs open via Linking.openURL() when tapped.

3. **Max limits**:
   - Receipts: 10 max
   - Other images (transactions): 5 max
   - Item images: 5 max

4. **Offline support**: Both images and PDFs use the same offline media system with upload queue.

5. **Theme support**: All colors use `useUIKitTheme()` for dark mode compatibility.

6. **Empty state**: When no attachments exist, show customizable message + add button (if editing).

7. **File extension**: PDFs saved with appropriate MIME type (`application/pdf`) for proper upload handling.

## Verification & Testing

### Manual Testing Checklist

**Transaction Detail - Receipts Section:**
1. ✓ Section title shows "Receipts" (not "Receipt Images")
2. ✓ Can add image via camera
3. ✓ Can add image via photo library
4. ✓ Can add PDF via files picker
5. ✓ Images display as thumbnails in grid
6. ✓ PDFs display as icon tiles with label
7. ✓ Tap image opens full-screen gallery
8. ✓ Tap PDF opens file viewer
9. ✓ Can set primary on images
10. ✓ Can set primary on PDFs
11. ✓ Can delete images
12. ✓ Can delete PDFs
13. ✓ Empty state shows "No receipts yet."
14. ✓ Can add up to 10 attachments total (mixed images + PDFs)
15. ✓ Add button disappears at 10 attachments
16. ✓ Primary badge shows on marked attachment
17. ✓ Theme colors correct in dark mode

**Transaction Detail - Other Images Section:**
1. ✓ Section title shows "Other Images"
2. ✓ Can add images (camera/library)
3. ✓ Cannot add PDFs (no Files option)
4. ✓ Max 5 images
5. ✓ Gallery, primary, delete all work

**Item Detail - Images Section:**
1. ✓ Section title shows "Images"
2. ✓ Inline URL/local URI inputs removed
3. ✓ Uses MediaGallerySection component
4. ✓ Can add images via ImagePickerButton
5. ✓ Gallery, primary, delete all work
6. ✓ Max 5 images

**Cross-cutting:**
1. ✓ Offline mode: attachments saved locally and queued for upload
2. ✓ Upload queue processes images and PDFs correctly
3. ✓ Dark mode: all components properly themed
4. ✓ Tablet layout: responsive grid sizing
5. ✓ No memory leaks (modal cleanup)
6. ✓ Gesture conflicts resolved (if any)

### Code Testing
- Unit test: MediaGallerySection renders with images only
- Unit test: MediaGallerySection renders with mixed images + PDFs
- Unit test: MediaGallerySection shows empty state correctly
- Unit test: ImagePickerButton shows correct menu based on allowedKinds
- Integration test: Transaction can add/remove/view receipts (images + PDFs)
- Integration test: Item can add/remove/view images

## Summary

This plan creates a single, flexible `MediaGallerySection` component that:
- Eliminates repetitive gallery logic across screens
- Supports both image-only and image+PDF modes via props
- Updates terminology: "Receipt Images" → "Receipts"
- Extends ImagePickerButton to support PDF picking
- Maintains backward compatibility with existing data
- Provides consistent, theme-aware UX
- Reduces parent component complexity (no manual state management)

The implementation is non-breaking and can be done incrementally, screen by screen.
