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

type RequestStatus = 'pending' | 'applied' | 'failed' | 'denied';
type RequestDoc = {
  type: string;
  status: RequestStatus;
  opId?: string;
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

const requestHandlers: Record<string, (context: RequestHandlerContext) => Promise<void>> = {};

function canonicalPurchaseId(projectId: string) {
  return `INV_PURCHASE_${projectId}`;
}

function canonicalSaleId(projectId: string) {
  return `INV_SALE_${projectId}`;
}

function getItemValueCents(item: admin.firestore.DocumentData): number {
  if (typeof item.projectPriceCents === 'number') return item.projectPriceCents;
  if (typeof item.purchasePriceCents === 'number') return item.purchasePriceCents;
  return 0;
}

async function ensureCanonicalTransaction(params: {
  tx: admin.firestore.Transaction;
  accountId: string;
  transactionId: string;
  projectId: string;
  kind: 'INV_PURCHASE' | 'INV_SALE';
  amountDelta: number;
  itemId: string;
}) {
  const { tx, accountId, transactionId, projectId, kind, amountDelta, itemId } = params;
  const txRef = admin.firestore().doc(`accounts/${accountId}/transactions/${transactionId}`);
  const snap = await tx.get(txRef);
  const now = admin.firestore.FieldValue.serverTimestamp();
  if (!snap.exists) {
    tx.set(
      txRef,
      {
        id: transactionId,
        accountId,
        projectId,
        transactionDate: new Date().toISOString().slice(0, 10),
        amountCents: amountDelta,
        isCanonicalInventory: true,
        canonicalKind: kind,
        itemIds: [itemId],
        createdAt: now,
        updatedAt: now,
      },
      { merge: true }
    );
    return;
  }
  const data = snap.data() ?? {};
  const existingAmount = typeof data.amountCents === 'number' ? data.amountCents : 0;
  const existingItemIds = Array.isArray(data.itemIds) ? data.itemIds : [];
  const nextAmount = existingAmount + amountDelta;
  const nextItemIds = existingItemIds.includes(itemId) ? existingItemIds : [...existingItemIds, itemId];
  tx.set(
    txRef,
    {
      projectId,
      isCanonicalInventory: true,
      canonicalKind: kind,
      amountCents: nextAmount,
      itemIds: nextItemIds,
      updatedAt: now,
    },
    { merge: true }
  );
}

async function removeFromCanonicalTransaction(params: {
  tx: admin.firestore.Transaction;
  accountId: string;
  transactionId: string;
  amountDelta: number;
  itemId: string;
}) {
  const { tx, accountId, transactionId, amountDelta, itemId } = params;
  const txRef = admin.firestore().doc(`accounts/${accountId}/transactions/${transactionId}`);
  const snap = await tx.get(txRef);
  if (!snap.exists) return;
  const data = snap.data() ?? {};
  const existingAmount = typeof data.amountCents === 'number' ? data.amountCents : 0;
  const existingItemIds = Array.isArray(data.itemIds) ? data.itemIds : [];
  const nextItemIds = existingItemIds.filter((id: string) => id !== itemId);
  const nextAmount = Math.max(0, existingAmount - amountDelta);
  tx.set(
    txRef,
    {
      amountCents: nextAmount,
      itemIds: nextItemIds,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
}

async function appendLineageEdge(params: {
  tx: admin.firestore.Transaction;
  accountId: string;
  requestId: string;
  itemId: string;
  fromTransactionId: string | null;
  toTransactionId: string | null;
  createdBy: string | null | undefined;
}) {
  const { tx, accountId, requestId, itemId, fromTransactionId, toTransactionId, createdBy } = params;
  const edgeId = `edge_${requestId}_${itemId}`;
  const edgeRef = admin.firestore().doc(`accounts/${accountId}/lineageEdges/${edgeId}`);
  tx.set(
    edgeRef,
    {
      id: edgeId,
      accountId,
      itemId,
      fromTransactionId: fromTransactionId ?? null,
      toTransactionId: toTransactionId ?? null,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      deletedAt: null,
      createdBy: createdBy ?? null,
    },
    { merge: true }
  );
}

function getExpected(payload: any) {
  const expected = payload?.expected ?? {};
  return {
    itemProjectId: expected.itemProjectId ?? null,
    itemTransactionId: expected.itemTransactionId ?? null,
  };
}

async function handleProjectToBusiness(context: RequestHandlerContext) {
  const payload = context.requestData.payload ?? {};
  const itemId = payload.itemId as string;
  const sourceProjectId = payload.sourceProjectId as string;
  if (!itemId || !sourceProjectId) {
    await setRequestFailed(context.requestRef, 'invalid', 'Missing itemId or sourceProjectId.');
    return;
  }
  const db = admin.firestore();
  const itemRef = db.doc(`accounts/${context.accountId}/items/${itemId}`);
  const { itemProjectId, itemTransactionId } = getExpected(payload);
  await db.runTransaction(async (tx) => {
    const itemSnap = await tx.get(itemRef);
    if (!itemSnap.exists) {
      throw new HttpsError('not-found', 'Item not found.');
    }
    const item = itemSnap.data() ?? {};
    if (itemProjectId !== item.projectId) {
      throw new HttpsError('failed-precondition', 'Item scope changed.');
    }
    if (itemTransactionId != null && itemTransactionId !== (item.transactionId ?? null)) {
      throw new HttpsError('failed-precondition', 'Item transaction changed.');
    }
    if (!item.inheritedBudgetCategoryId) {
      throw new HttpsError('failed-precondition', 'Missing inheritedBudgetCategoryId.');
    }
    const previousTxId = item.transactionId ?? null;
    const amountDelta = getItemValueCents(item);
    const purchaseId = canonicalPurchaseId(sourceProjectId);
    const saleId = canonicalSaleId(sourceProjectId);
    if (previousTxId === purchaseId) {
      await removeFromCanonicalTransaction({
        tx,
        accountId: context.accountId,
        transactionId: purchaseId,
        amountDelta,
        itemId,
      });
      tx.set(
        itemRef,
        {
          projectId: null,
          transactionId: null,
          spaceId: null,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          latestTransactionId: null,
        },
        { merge: true }
      );
      await appendLineageEdge({
        tx,
        accountId: context.accountId,
        requestId: context.requestId,
        itemId,
        fromTransactionId: purchaseId,
        toTransactionId: null,
        createdBy: context.requestData.createdBy,
      });
    } else {
      await ensureCanonicalTransaction({
        tx,
        accountId: context.accountId,
        transactionId: saleId,
        projectId: sourceProjectId,
        kind: 'INV_SALE',
        amountDelta,
        itemId,
      });
      tx.set(
        itemRef,
        {
          projectId: null,
          transactionId: saleId,
          spaceId: null,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          latestTransactionId: saleId,
        },
        { merge: true }
      );
      await appendLineageEdge({
        tx,
        accountId: context.accountId,
        requestId: context.requestId,
        itemId,
        fromTransactionId: previousTxId,
        toTransactionId: saleId,
        createdBy: context.requestData.createdBy,
      });
    }
  });
  await setRequestApplied(context.requestRef);
}

async function handleBusinessToProject(context: RequestHandlerContext) {
  const payload = context.requestData.payload ?? {};
  const itemId = payload.itemId as string;
  const targetProjectId = payload.targetProjectId as string;
  const inheritedBudgetCategoryId = payload.inheritedBudgetCategoryId ?? null;
  if (!itemId || !targetProjectId) {
    await setRequestFailed(context.requestRef, 'invalid', 'Missing itemId or targetProjectId.');
    return;
  }
  const db = admin.firestore();
  const itemRef = db.doc(`accounts/${context.accountId}/items/${itemId}`);
  const { itemProjectId, itemTransactionId } = getExpected(payload);
  await db.runTransaction(async (tx) => {
    const itemSnap = await tx.get(itemRef);
    if (!itemSnap.exists) {
      throw new HttpsError('not-found', 'Item not found.');
    }
    const item = itemSnap.data() ?? {};
    if (itemProjectId !== item.projectId) {
      throw new HttpsError('failed-precondition', 'Item scope changed.');
    }
    if (itemTransactionId != null && itemTransactionId !== (item.transactionId ?? null)) {
      throw new HttpsError('failed-precondition', 'Item transaction changed.');
    }
    if (!inheritedBudgetCategoryId) {
      throw new HttpsError('failed-precondition', 'Missing inheritedBudgetCategoryId.');
    }
    const previousTxId = item.transactionId ?? null;
    const amountDelta = getItemValueCents(item);
    const purchaseId = canonicalPurchaseId(targetProjectId);
    await ensureCanonicalTransaction({
      tx,
      accountId: context.accountId,
      transactionId: purchaseId,
      projectId: targetProjectId,
      kind: 'INV_PURCHASE',
      amountDelta,
      itemId,
    });
    tx.set(
      itemRef,
      {
        projectId: targetProjectId,
        transactionId: purchaseId,
        status: item.status ?? 'purchased',
        spaceId: null,
        inheritedBudgetCategoryId,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        latestTransactionId: purchaseId,
      },
      { merge: true }
    );
    await appendLineageEdge({
      tx,
      accountId: context.accountId,
      requestId: context.requestId,
      itemId,
      fromTransactionId: previousTxId,
      toTransactionId: purchaseId,
      createdBy: context.requestData.createdBy,
    });
  });
  await setRequestApplied(context.requestRef);
}

async function handleProjectToProject(context: RequestHandlerContext) {
  const payload = context.requestData.payload ?? {};
  const itemId = payload.itemId as string;
  const sourceProjectId = payload.sourceProjectId as string;
  const targetProjectId = payload.targetProjectId as string;
  const inheritedBudgetCategoryId = payload.inheritedBudgetCategoryId ?? null;
  if (!itemId || !sourceProjectId || !targetProjectId) {
    await setRequestFailed(context.requestRef, 'invalid', 'Missing itemId or project ids.');
    return;
  }
  const db = admin.firestore();
  const itemRef = db.doc(`accounts/${context.accountId}/items/${itemId}`);
  const { itemProjectId, itemTransactionId } = getExpected(payload);
  await db.runTransaction(async (tx) => {
    const itemSnap = await tx.get(itemRef);
    if (!itemSnap.exists) {
      throw new HttpsError('not-found', 'Item not found.');
    }
    const item = itemSnap.data() ?? {};
    if (itemProjectId !== item.projectId) {
      throw new HttpsError('failed-precondition', 'Item scope changed.');
    }
    if (itemTransactionId != null && itemTransactionId !== (item.transactionId ?? null)) {
      throw new HttpsError('failed-precondition', 'Item transaction changed.');
    }
    if (!inheritedBudgetCategoryId) {
      throw new HttpsError('failed-precondition', 'Missing inheritedBudgetCategoryId.');
    }
    const previousTxId = item.transactionId ?? null;
    const amountDelta = getItemValueCents(item);
    const saleId = canonicalSaleId(sourceProjectId);
    const purchaseId = canonicalPurchaseId(targetProjectId);
    await ensureCanonicalTransaction({
      tx,
      accountId: context.accountId,
      transactionId: saleId,
      projectId: sourceProjectId,
      kind: 'INV_SALE',
      amountDelta,
      itemId,
    });
    await ensureCanonicalTransaction({
      tx,
      accountId: context.accountId,
      transactionId: purchaseId,
      projectId: targetProjectId,
      kind: 'INV_PURCHASE',
      amountDelta,
      itemId,
    });
    tx.set(
      itemRef,
      {
        projectId: targetProjectId,
        transactionId: purchaseId,
        spaceId: null,
        inheritedBudgetCategoryId,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        latestTransactionId: purchaseId,
      },
      { merge: true }
    );
    await appendLineageEdge({
      tx,
      accountId: context.accountId,
      requestId: context.requestId,
      itemId,
      fromTransactionId: previousTxId,
      toTransactionId: purchaseId,
      createdBy: context.requestData.createdBy,
    });
  });
  await setRequestApplied(context.requestRef);
}

requestHandlers.ITEM_SALE_PROJECT_TO_BUSINESS = handleProjectToBusiness;
requestHandlers.ITEM_SALE_BUSINESS_TO_PROJECT = handleBusinessToProject;
requestHandlers.ITEM_SALE_PROJECT_TO_PROJECT = handleProjectToProject;
requestHandlers.PING = async ({ requestRef }) => {
  await setRequestApplied(requestRef);
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

export const onAccountRequestCreated = onDocumentCreated(
  'accounts/{accountId}/requests/{requestId}',
  async (event) => {
    const requestRef = event.data?.ref;
    const requestData = event.data?.data() as RequestDoc | undefined;
    if (!requestRef) {
      return;
    }
    const opId = requestData?.opId;
    if (opId) {
      const existing = await requestRef.parent
        .where('opId', '==', opId)
        .where('type', '==', requestData?.type ?? '')
        .where('status', '==', 'applied')
        .limit(1)
        .get();
      if (!existing.empty && existing.docs[0].id !== requestRef.id) {
        await setRequestApplied(requestRef, { deduped: true });
        return;
      }
    }
    await processRequestDoc({
      requestRef,
      requestData: requestData ?? { status: 'failed', type: 'unknown' },
      accountId: event.params.accountId,
      requestId: event.params.requestId
    });
  }
);

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

type AcceptInviteRequest = {
  token: string;
  deviceInfo?: Record<string, unknown>;
  profileDefaults?: Record<string, unknown>;
};

type AcceptInviteResponse = {
  accountId: string;
  role: string;
};

type CreateAccountRequest = {
  name?: string;
};

type CreateAccountResponse = {
  accountId: string;
  role: 'owner';
  name: string;
};

type CreateProjectRequest = {
  accountId: string;
  name: string;
  clientName: string;
};

type CreateProjectResponse = {
  projectId: string;
};

/**
 * Create a new account and the caller's membership (server-owned).
 */
export const createAccount = onCall<CreateAccountRequest, CreateAccountResponse>(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Must be signed in.');
  }

  const rawName = request.data?.name;
  const name = typeof rawName === 'string' && rawName.trim() ? rawName.trim().slice(0, 80) : 'My account';

  const db = admin.firestore();
  const now = admin.firestore.FieldValue.serverTimestamp();
  const accountRef = db.collection('accounts').doc();
  const accountId = accountRef.id;
  const membershipRef = db.doc(`accounts/${accountId}/users/${uid}`);

  await db.runTransaction(async (tx) => {
    tx.set(
      accountRef,
      {
        name,
        createdAt: now,
        createdBy: uid
      },
      { merge: false }
    );

    tx.set(
      membershipRef,
      {
        uid,
        role: 'owner',
        joinedAt: now
      },
      { merge: false }
    );
  });

  return { accountId, role: 'owner', name };
});

/**
 * Create a new project (server-owned, entitlements-safe).
 */
export const createProject = onCall<CreateProjectRequest, CreateProjectResponse>(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Must be signed in.');
  }

  const rawAccountId = request.data?.accountId;
  const rawName = request.data?.name;
  const rawClientName = request.data?.clientName;
  const accountId = typeof rawAccountId === 'string' ? rawAccountId.trim() : '';
  const name = typeof rawName === 'string' ? rawName.trim() : '';
  const clientName = typeof rawClientName === 'string' ? rawClientName.trim() : '';

  if (!accountId || !name || !clientName) {
    throw new HttpsError('invalid-argument', 'accountId, name, and clientName are required.');
  }

  const db = admin.firestore();
  const now = admin.firestore.FieldValue.serverTimestamp();
  const projectRef = db.collection(`accounts/${accountId}/projects`).doc();
  const projectId = projectRef.id;

  const presetBudgetCategories = db
    .collection(`accounts/${accountId}/presets/default/budgetCategories`)
    .where('name', '==', 'Furnishings')
    .limit(1);
  const presetSnapshot = await presetBudgetCategories.get();
  const furnishingsId = presetSnapshot.empty ? null : presetSnapshot.docs[0].id;

  const projectPreferencesRef = db.doc(
    `accounts/${accountId}/users/${uid}/projectPreferences/${projectId}`
  );

  await db.runTransaction(async (tx) => {
    tx.set(
      projectRef,
      {
        accountId,
        name,
        clientName,
        createdAt: now,
        updatedAt: now,
        createdBy: uid,
        isArchived: false,
      },
      { merge: false }
    );

    tx.set(
      projectPreferencesRef,
      {
        id: projectId,
        accountId,
        userId: uid,
        projectId,
        pinnedBudgetCategoryIds: furnishingsId ? [furnishingsId] : [],
        createdAt: now,
        updatedAt: now,
      },
      { merge: true }
    );
  });

  return { projectId };
});

/**
 * Accept an invitation token and create/update account membership.
 * This function is idempotent - if the user is already a member, it returns success.
 */
export const acceptInvite = onCall<AcceptInviteRequest, AcceptInviteResponse>(
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError('unauthenticated', 'Must be signed in to accept an invitation.');
    }

    const { token } = request.data ?? ({} as AcceptInviteRequest);
    if (!token || typeof token !== 'string' || !token.trim()) {
      throw new HttpsError('invalid-argument', 'Invitation token is required.');
    }

    const db = admin.firestore();
    const now = admin.firestore.FieldValue.serverTimestamp();

    // Find the invite by token
    // Note: In a real implementation, you might hash the token or use a different lookup strategy.
    // For now, we'll search invites collections. This assumes tokens are stored as invite IDs or in a token field.
    // A production implementation should optimize this lookup (e.g., token -> inviteId mapping doc).
    let inviteRef: admin.firestore.DocumentReference | null = null;
    let accountId: string | null = null;
    let inviteData: any = null;

    // Search all accounts for an invite with this token
    // This is a simplified implementation - production should use a token lookup index
    const accountsSnapshot = await db.collectionGroup('invites').where('token', '==', token).limit(1).get();

    if (accountsSnapshot.empty) {
      // Try searching by invite ID (if token is the invite ID)
      const inviteId = token;
      // We need to search across accounts - this is expensive but works for MVP
      // Production should maintain a token -> accountId/inviteId mapping
      const allAccountsSnapshot = await db.collection('accounts').limit(100).get();
      
      for (const accountDoc of allAccountsSnapshot.docs) {
        const testInviteRef = db.doc(`accounts/${accountDoc.id}/invites/${inviteId}`);
        const testInviteSnap = await testInviteRef.get();
        if (testInviteSnap.exists) {
          inviteRef = testInviteRef;
          accountId = accountDoc.id;
          inviteData = testInviteSnap.data();
          break;
        }
      }

      if (!inviteRef || !accountId) {
        throw new HttpsError('not-found', 'Invalid or expired invitation link.');
      }
    } else {
      const inviteDoc = accountsSnapshot.docs[0];
      inviteRef = inviteDoc.ref;
      inviteData = inviteDoc.data();
      // Extract accountId from path: accounts/{accountId}/invites/{inviteId}
      const pathParts = inviteDoc.ref.path.split('/');
      accountId = pathParts[1];
    }

    if (!accountId || !inviteRef || !inviteData) {
      throw new HttpsError('not-found', 'Invalid or expired invitation link.');
    }

    // Validate invite status and expiration
    const status = inviteData.status;
    const expiresAt = inviteData.expiresAt as admin.firestore.Timestamp | undefined;
    const acceptedAt = inviteData.acceptedAt as admin.firestore.Timestamp | undefined;
    const acceptedByUid = inviteData.acceptedByUid as string | undefined;

    if (status === 'accepted' || acceptedAt) {
      // Idempotent: if already accepted by this user, return success
      if (acceptedByUid === uid) {
        const userRef = db.doc(`accounts/${accountId}/users/${uid}`);
        const userSnap = await userRef.get();
        if (userSnap.exists) {
          const userData = userSnap.data();
          return {
            accountId,
            role: (userData?.role as string) || 'user',
          };
        }
      }
      throw new HttpsError('already-exists', 'This invitation has already been accepted.');
    }

    if (status === 'revoked' || status === 'cancelled') {
      throw new HttpsError('permission-denied', 'This invitation has been cancelled.');
    }

    if (expiresAt && expiresAt.toMillis() < Date.now()) {
      throw new HttpsError('deadline-exceeded', 'This invitation has expired.');
    }

    const role = (inviteData.role as string) || 'user';

    // Check entitlements (e.g., free tier user limits)
    // For MVP, we'll skip entitlement checks, but this is where you'd add them
    // Example: check account user count against plan limits

    // Create/update account user membership in a transaction
    const userRef = db.doc(`accounts/${accountId}/users/${uid}`);

    const result = await db.runTransaction(async (tx) => {
      // Re-check invite status in transaction
      const inviteSnap = await tx.get(inviteRef!);
      if (!inviteSnap.exists) {
        throw new HttpsError('not-found', 'Invitation no longer exists.');
      }

      const currentInviteData = inviteSnap.data();
      if (currentInviteData?.acceptedAt) {
        // Idempotent: already accepted
        if (currentInviteData.acceptedByUid === uid) {
          const userSnap = await tx.get(userRef);
          if (userSnap.exists) {
            const userData = userSnap.data();
            return {
              accountId: accountId!,
              role: (userData?.role as string) || 'user',
            };
          }
        }
        throw new HttpsError('already-exists', 'This invitation has already been accepted.');
      }

      // Check if user already exists (idempotent)
      const userSnap = await tx.get(userRef);
      const userExists = userSnap.exists;

      // Create or update account user doc
      tx.set(
        userRef,
        {
          uid,
          role,
          joinedAt: userExists ? userSnap.data()?.joinedAt : now,
          joinedBy: userExists ? userSnap.data()?.joinedBy : inviteData.createdBy || null,
          updatedAt: now,
        },
        { merge: true }
      );

      // Mark invite as accepted
      tx.update(inviteRef, {
        status: 'accepted',
        acceptedAt: now,
        acceptedByUid: uid,
        updatedAt: now,
      });

      return {
        accountId: accountId!,
        role,
      };
    });

    return result;
  }
);

