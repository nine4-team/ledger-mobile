import type { Transaction } from '../../../../src/data/transactionsService';
import type { AttachmentRef, AttachmentKind } from '../../../../src/offline/media';

export type MediaHandlers = {
  handlePickReceiptAttachment: (localUri: string, kind: AttachmentKind) => Promise<void>;
  handleRemoveReceiptAttachment: (attachment: AttachmentRef) => Promise<void>;
  handleSetPrimaryReceiptAttachment: (attachment: AttachmentRef) => void;
  handlePickOtherImage: (localUri: string, kind: AttachmentKind) => Promise<void>;
  handleRemoveOtherImage: (attachment: AttachmentRef) => Promise<void>;
  handleSetPrimaryOtherImage: (attachment: AttachmentRef) => void;
};

export type BudgetCategories = Record<string, { name: string; metadata?: any }>;
