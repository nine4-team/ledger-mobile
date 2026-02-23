import { forwardRef } from 'react';
import { MediaGallerySection, type MediaGallerySectionRef } from '../../../../src/components/MediaGallerySection';
import type { Transaction } from '../../../../src/data/transactionsService';
import type { MediaHandlers } from './types';

type OtherImagesSectionProps = {
  transaction: Transaction;
  handlers: MediaHandlers;
};

export const OtherImagesSection = forwardRef<MediaGallerySectionRef, OtherImagesSectionProps>(
  function OtherImagesSection({ transaction, handlers }, ref) {
    return (
      <MediaGallerySection
        ref={ref}
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
);
