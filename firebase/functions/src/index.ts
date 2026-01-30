import * as admin from 'firebase-admin';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { onDocumentCreated } from 'firebase-functions/v2/firestore';

admin.initializeApp();

type CreateWithQuotaRequest = {
  // Identifies which quota bucket to enforce (e.g. "memory", "entry", "project").
  objectKey: string;

  // Document path under the user's namespace where the new doc should be created.
  // Example: "users/{uid}/objects"
  collectionPath: string;

  // The doc payload to write. Server will add timestamps.
  data: Record<string, unknown>;
};

export const createWithQuota = onCall<CreateWithQuotaRequest>(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Must be signed in.');
  }

  const { objectKey, collectionPath, data } = request.data ?? ({} as CreateWithQuotaRequest);
  if (!objectKey || !collectionPath || !data) {
    throw new HttpsError('invalid-argument', 'Missing objectKey, collectionPath, or data.');
  }

  // NOTE: This is intentionally a template/starter.
  // Real apps will likely:
  // - check “isPro” (from custom claims or a user doc updated by a billing webhook)
  // - load the quota limit from config
  // - enforce per-objectKey rules
  const db = admin.firestore();

  const quotaRef = db.doc(`users/${uid}/quota/${objectKey}`);
  const newDocRef = db.collection(collectionPath.replace('{uid}', uid)).doc();
  const now = admin.firestore.FieldValue.serverTimestamp();

  const result = await db.runTransaction(async (tx) => {
    const quotaSnap = await tx.get(quotaRef);
    const current = (quotaSnap.exists ? (quotaSnap.data()?.count as number | undefined) : 0) ?? 0;

    // Template default: free limit = 10. Apps should parameterize this.
    const freeLimit = 10;

    if (current >= freeLimit) {
      // Client should interpret this as “show paywall”.
      throw new HttpsError('resource-exhausted', `Quota exceeded for ${objectKey}.`);
    }

    tx.set(
      newDocRef,
      {
        ...data,
        uid,
        createdAt: now,
        updatedAt: now
      },
      { merge: false }
    );

    tx.set(
      quotaRef,
      {
        count: current + 1,
        updatedAt: now
      },
      { merge: true }
    );

    return { id: newDocRef.id };
  });

  return result;
});

type RequestStatus = 'pending' | 'applied' | 'failed';
type RequestDoc = {
  type: string;
  status: RequestStatus;
  createdAt?: admin.firestore.Timestamp;
  createdBy?: string;
  appliedAt?: admin.firestore.Timestamp;
  errorCode?: string;
  errorMessage?: string;
  payload?: Record<string, unknown>;
};

async function setRequestApplied(
  requestRef: admin.firestore.DocumentReference,
  extra: Record<string, unknown> = {}
) {
  await requestRef.update({
    status: 'applied',
    appliedAt: admin.firestore.FieldValue.serverTimestamp(),
    errorCode: admin.firestore.FieldValue.delete(),
    errorMessage: admin.firestore.FieldValue.delete(),
    ...extra
  });
}

async function setRequestFailed(
  requestRef: admin.firestore.DocumentReference,
  errorCode: string,
  errorMessage: string
) {
  await requestRef.update({
    status: 'failed',
    errorCode,
    errorMessage,
    appliedAt: admin.firestore.FieldValue.delete()
  });
}

type RequestHandlerContext = {
  requestRef: admin.firestore.DocumentReference;
  requestData: RequestDoc;
  accountId: string;
  projectId?: string;
  requestId: string;
};

const requestHandlers: Record<string, (context: RequestHandlerContext) => Promise<void>> = {
  // Example "no-op" handler to prove the pipeline works end-to-end.
  // Replace or extend with real handlers that perform transactions.
  PING: async ({ requestRef }) => {
    await setRequestApplied(requestRef);
  }
};

async function processRequestDoc(context: RequestHandlerContext) {
  const { requestRef, requestData } = context;
  if (!requestData) {
    await setRequestFailed(requestRef, 'invalid', 'Request data missing.');
    return;
  }

  if (requestData.status !== 'pending') {
    // Ignore replays or client-mutations; server owns status transitions.
    return;
  }

  const handler = requestHandlers[requestData.type];
  if (!handler) {
    await setRequestFailed(requestRef, 'unimplemented', `No handler for ${requestData.type}.`);
    return;
  }

  try {
    await handler(context);
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unknown error.';
    await setRequestFailed(requestRef, 'handler_error', message);
  }
}

export const onProjectRequestCreated = onDocumentCreated(
  'accounts/{accountId}/projects/{projectId}/requests/{requestId}',
  async (event) => {
    const requestRef = event.data?.ref;
    const requestData = event.data?.data() as RequestDoc | undefined;
    if (!requestRef) {
      return;
    }
    await processRequestDoc({
      requestRef,
      requestData: requestData ?? { status: 'failed', type: 'unknown' },
      accountId: event.params.accountId,
      projectId: event.params.projectId,
      requestId: event.params.requestId
    });
  }
);

export const onInventoryRequestCreated = onDocumentCreated(
  'accounts/{accountId}/inventory/requests/{requestId}',
  async (event) => {
    const requestRef = event.data?.ref;
    const requestData = event.data?.data() as RequestDoc | undefined;
    if (!requestRef) {
      return;
    }
    await processRequestDoc({
      requestRef,
      requestData: requestData ?? { status: 'failed', type: 'unknown' },
      accountId: event.params.accountId,
      requestId: event.params.requestId
    });
  }
);

