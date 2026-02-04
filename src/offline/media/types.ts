export type AttachmentKind = 'image' | 'pdf' | 'file';

export type AttachmentRef = {
  url: string;
  kind: AttachmentKind;
  fileName?: string;
  contentType?: string;
  isPrimary?: boolean;
};

export type MediaStatus = 'local_only' | 'uploading' | 'uploaded' | 'failed';

export type MediaRecord = {
  id: string;
  localUri: string;
  createdAt: number;
  updatedAt: number;
  size?: number;
  mimeType?: string;
  ownerScope?: string;
  status: MediaStatus;
  remoteUrl?: string;
  lastError?: string;
};

export type UploadJobStatus = 'queued' | 'uploading' | 'failed' | 'completed';

export type UploadJob = {
  id: string;
  mediaId: string;
  idempotencyKey: string;
  status: UploadJobStatus;
  createdAt: number;
  updatedAt: number;
  attemptCount: number;
  lastError?: string;
  destinationPath?: string;
};
