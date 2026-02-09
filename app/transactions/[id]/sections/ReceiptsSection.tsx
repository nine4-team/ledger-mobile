import { MediaGallerySection } from '../../../../src/components/MediaGallerySection';
import type { Transaction } from '../../../../src/data/transactionsService';
import type { MediaHandlers } from './types';

type ReceiptsSectionProps = {
  transaction: Transaction;
  handlers: MediaHandlers;
};

export function ReceiptsSection({ transaction, handlers }: ReceiptsSectionProps) {
  return (
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
  );
}
