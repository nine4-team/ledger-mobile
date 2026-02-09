import { MediaGallerySection } from '../../../../src/components/MediaGallerySection';
import type { Transaction } from '../../../../src/data/transactionsService';
import type { MediaHandlers } from './types';

type OtherImagesSectionProps = {
  transaction: Transaction;
  handlers: MediaHandlers;
};

export function OtherImagesSection({ transaction, handlers }: OtherImagesSectionProps) {
  return (
    <MediaGallerySection
      title="Other Images"
      hideTitle={true}
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
  );
}
