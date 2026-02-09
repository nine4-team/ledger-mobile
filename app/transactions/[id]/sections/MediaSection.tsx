import { MediaGallerySection } from '../../../../src/components/MediaGallerySection';
import type { Transaction } from '../../../../src/data/transactionsService';
import type { MediaHandlers } from './types';

type MediaSectionProps = {
  transaction: Transaction;
  handlers: MediaHandlers;
};

export function MediaSection({ transaction, handlers }: MediaSectionProps) {
  return (
    <>
      <MediaGallerySection
        title="Receipts"
        hideTitle={true}
        attachments={transaction.receiptImages ?? []}
        maxAttachments={10}
        allowedKinds={['image', 'pdf']}
        onAddAttachment={handlers.handlePickReceiptAttachment}
        onRemoveAttachment={handlers.handleRemoveReceiptAttachment}
        onSetPrimary={handlers.handleSetPrimaryReceiptAttachment}
        emptyStateMessage="No receipts yet."
        pickerLabel="Add receipt"
        size="md"
        tileScale={1.5}
      />
      <MediaGallerySection
        title="Other Images"
        attachments={transaction.otherImages ?? []}
        maxAttachments={5}
        allowedKinds={['image']}
        onAddAttachment={handlers.handlePickOtherImage}
        onRemoveAttachment={handlers.handleRemoveOtherImage}
        onSetPrimary={handlers.handleSetPrimaryOtherImage}
        emptyStateMessage="No other images yet."
        pickerLabel="Add image"
        size="md"
        tileScale={1.5}
      />
    </>
  );
}
