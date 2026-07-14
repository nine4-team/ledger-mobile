"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.backfillIsComplete = exports.backfillBudgetSummaries = exports.onAccountBudgetCategoryWritten = exports.onProjectBudgetCategoryWritten = exports.onTransactionWritten = exports.acceptInviteHttp = exports.acceptInvite = exports.previewInviteHttp = exports.createProject = exports.createAccountHttp = exports.createAccount = exports.onAccountMembershipCreated = exports.onSpaceArchived = exports.onItemPriceChanged = exports.onLineageEdgeCreated = exports.onItemTransactionIdChanged = exports.createWithQuota = void 0;
const admin = require("firebase-admin");
const firestore_1 = require("firebase-admin/firestore");
const https_1 = require("firebase-functions/v2/https");
const firestore_2 = require("firebase-functions/v2/firestore");
admin.initializeApp();
exports.createWithQuota = (0, https_1.onCall)(async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
        throw new https_1.HttpsError('unauthenticated', 'Must be signed in.');
    }
    const { objectKey, collectionPath, data } = request.data ?? {};
    if (!objectKey || !collectionPath || !data) {
        throw new https_1.HttpsError('invalid-argument', 'Missing objectKey, collectionPath, or data.');
    }
    // NOTE: This is intentionally a template/starter.
    // Real apps will likely:
    // - check “isPro” (from custom claims or a user doc updated by a billing webhook)
    // - load the quota limit from config
    // - enforce per-objectKey rules
    const db = (0, firestore_1.getFirestore)();
    const quotaRef = db.doc(`users/${uid}/quota/${objectKey}`);
    const newDocRef = db.collection(collectionPath.replace('{uid}', uid)).doc();
    const now = firestore_1.FieldValue.serverTimestamp();
    const result = await db.runTransaction(async (tx) => {
        const quotaSnap = await tx.get(quotaRef);
        const current = (quotaSnap.exists ? quotaSnap.data()?.count : 0) ?? 0;
        // Template default: free limit = 10. Apps should parameterize this.
        const freeLimit = 10;
        if (current >= freeLimit) {
            // Client should interpret this as “show paywall”.
            throw new https_1.HttpsError('resource-exhausted', `Quota exceeded for ${objectKey}.`);
        }
        tx.set(newDocRef, {
            ...data,
            uid,
            createdAt: now,
            updatedAt: now
        }, { merge: false });
        tx.set(quotaRef, {
            count: current + 1,
            updatedAt: now
        }, { merge: true });
        return { id: newDocRef.id };
    });
    return result;
});
/**
 * Append an association lineage edge whenever an item's transactionId changes.
 * This captures client-direct linking/unlinking. Optional `returned` intent edge
 * is appended when the destination transaction is a Return transaction.
 */
exports.onItemTransactionIdChanged = (0, firestore_2.onDocumentUpdated)('accounts/{accountId}/items/{itemId}', async (event) => {
    const before = event.data?.before.data() ?? null;
    const after = event.data?.after.data() ?? null;
    if (!before || !after)
        return;
    const beforeTxId = before.transactionId ?? null;
    const afterTxId = after.transactionId ?? null;
    if (beforeTxId === afterTxId)
        return;
    const accountId = event.params.accountId;
    const itemId = event.params.itemId;
    const db = (0, firestore_1.getFirestore)();
    // Always append an association audit edge for transactionId changes.
    const associationEdgeId = `assoc_${event.id}_${itemId}`;
    const associationRef = db.doc(`accounts/${accountId}/lineageEdges/${associationEdgeId}`);
    await db.runTransaction(async (tx) => {
        const existing = await tx.get(associationRef);
        if (existing.exists)
            return;
        const now = firestore_1.FieldValue.serverTimestamp();
        tx.set(associationRef, {
            accountId,
            itemId,
            fromTransactionId: beforeTxId,
            toTransactionId: afterTxId,
            createdAt: now,
            updatedAt: now,
            deletedAt: null,
            createdBy: after.updatedBy ?? null,
            movementKind: 'association',
            source: 'server',
            note: null,
            fromProjectId: before.projectId ?? null,
            toProjectId: after.projectId ?? null,
        }, { merge: false });
    });
    // Optional but deterministic: if the destination transaction is a Return transaction,
    // also append a `returned` intent edge (in addition to the association audit edge).
    if (afterTxId != null) {
        const toTxRef = db.doc(`accounts/${accountId}/transactions/${afterTxId}`);
        const toTxSnap = await toTxRef.get();
        const toTx = toTxSnap.exists ? toTxSnap.data() : null;
        const rawType = (toTx?.transactionType ?? toTx?.type ?? toTx?.transaction_type ?? null);
        const isReturn = typeof rawType === 'string' && rawType.trim().toLowerCase() === 'return';
        if (isReturn) {
            const returnedEdgeId = `returned_${event.id}_${itemId}`;
            const returnedRef = db.doc(`accounts/${accountId}/lineageEdges/${returnedEdgeId}`);
            await db.runTransaction(async (tx) => {
                const existing = await tx.get(returnedRef);
                if (existing.exists)
                    return;
                const now = firestore_1.FieldValue.serverTimestamp();
                tx.set(returnedRef, {
                    accountId,
                    itemId,
                    fromTransactionId: beforeTxId,
                    toTransactionId: afterTxId,
                    createdAt: now,
                    updatedAt: now,
                    deletedAt: null,
                    createdBy: after.updatedBy ?? null,
                    movementKind: 'returned',
                    source: 'server',
                    note: null,
                    fromProjectId: before.projectId ?? null,
                    toProjectId: after.projectId ?? null,
                }, { merge: false });
            });
        }
    }
});
/**
 * Recompute isComplete on the source transaction when a returned/sold lineage edge is created.
 * Safety net for non-atomic flows where the edge lands after the transaction's itemIds was updated.
 * For atomic batch writes (e.g., InventoryOperationsService), the onTransactionWritten trigger
 * already handles this — this trigger fires redundantly but is idempotent.
 */
exports.onLineageEdgeCreated = (0, firestore_2.onDocumentCreated)('accounts/{accountId}/lineageEdges/{edgeId}', async (event) => {
    const data = event.data?.data() ?? null;
    if (!data)
        return;
    const movementKind = data.movementKind;
    if (movementKind !== 'returned' && movementKind !== 'sold' && movementKind !== 'soldToInventory')
        return;
    const fromTransactionId = data.fromTransactionId;
    if (!fromTransactionId)
        return;
    const accountId = event.params.accountId;
    const db = (0, firestore_1.getFirestore)();
    try {
        const txRef = db.doc(`accounts/${accountId}/transactions/${fromTransactionId}`);
        const txSnap = await txRef.get();
        if (!txSnap.exists)
            return;
        const txData = txSnap.data() ?? {};
        const result = await computeIsComplete(db, accountId, fromTransactionId, txData);
        const currentIsComplete = txData.isComplete ?? null;
        const currentAudit = txData.audit ?? null;
        if (currentIsComplete !== result.isComplete ||
            JSON.stringify(currentAudit) !== JSON.stringify(result.audit)) {
            await txRef.set({
                isComplete: result.isComplete,
                audit: result.audit,
                updatedAt: firestore_1.FieldValue.serverTimestamp(),
            }, { merge: true });
        }
    }
    catch (err) {
        console.error(`[onLineageEdgeCreated] isComplete recompute failed for tx ${fromTransactionId}:`, err);
    }
});
/**
 * Recompute isComplete for any parent transactions that reference this item
 * when the item's price changes. Inventory movement transactions are
 * intentionally NOT touched: their `amountCents` is a frozen snapshot at
 * creation time and must never be rewritten here. Legacy canonical sales are
 * also frozen historical records. Both are skipped below.
 */
exports.onItemPriceChanged = (0, firestore_2.onDocumentUpdated)('accounts/{accountId}/items/{itemId}', async (event) => {
    const before = event.data?.before.data() ?? null;
    const after = event.data?.after.data() ?? null;
    if (!before || !after)
        return;
    const beforePurchase = before.purchasePriceCents ?? null;
    const afterPurchase = after.purchasePriceCents ?? null;
    const beforeProject = before.projectPriceCents ?? null;
    const afterProject = after.projectPriceCents ?? null;
    if (beforePurchase === afterPurchase && beforeProject === afterProject)
        return;
    const accountId = event.params.accountId;
    const itemId = event.params.itemId;
    const db = (0, firestore_1.getFirestore)();
    const isFrozenInventoryMovement = (txData) => {
        const rawType = (txData.type ?? txData.transactionType ?? null);
        const type = typeof rawType === 'string' ? rawType.trim().toLowerCase() : '';
        const source = typeof txData.source === 'string' ? txData.source.trim() : '';
        return type === 'sale' || type === 'return' || (type === 'purchase' && source.endsWith(' Inventory'));
    };
    // Recompute isComplete for parent transactions — only if purchasePriceCents
    // changed (that's what audit uses). Never touches frozen movement docs.
    if (beforePurchase !== afterPurchase) {
        try {
            const parentTxSnapshot = await db
                .collection(`accounts/${accountId}/transactions`)
                .where('itemIds', 'array-contains', itemId)
                .get();
            for (const txDoc of parentTxSnapshot.docs) {
                const txData = txDoc.data() ?? {};
                // Skip frozen inventory movement transactions.
                if (isFrozenInventoryMovement(txData)) {
                    console.log(`[onItemPriceChanged] skipping frozen inventory movement transaction ${txDoc.id}`);
                    continue;
                }
                const result = await computeIsComplete(db, accountId, txDoc.id, txData);
                const currentIsComplete = txData.isComplete ?? null;
                const currentAudit = txData.audit ?? null;
                if (currentIsComplete !== result.isComplete ||
                    JSON.stringify(currentAudit) !== JSON.stringify(result.audit)) {
                    await txDoc.ref.set({
                        isComplete: result.isComplete,
                        audit: result.audit,
                        updatedAt: firestore_1.FieldValue.serverTimestamp(),
                    }, { merge: true });
                }
            }
        }
        catch (err) {
            console.error(`[onItemPriceChanged] isComplete recompute failed for item ${itemId}:`, err);
        }
        // Also recompute source transactions where this item left via lineage edges
        // (item no longer in their itemIds, but still contributes to their audit)
        try {
            const edgesSnapshot = await db
                .collection(`accounts/${accountId}/lineageEdges`)
                .where('itemId', '==', itemId)
                .get();
            const sourceTransactionIds = new Set();
            for (const edgeDoc of edgesSnapshot.docs) {
                const edge = edgeDoc.data() ?? {};
                const kind = edge.movementKind;
                if (kind !== 'returned' && kind !== 'sold' && kind !== 'soldToInventory')
                    continue;
                const fromTxId = edge.fromTransactionId;
                if (fromTxId)
                    sourceTransactionIds.add(fromTxId);
            }
            for (const srcTxId of sourceTransactionIds) {
                const txRef = db.doc(`accounts/${accountId}/transactions/${srcTxId}`);
                const txSnap = await txRef.get();
                if (!txSnap.exists)
                    continue;
                const txData = txSnap.data() ?? {};
                // Skip if this item is still in the transaction's itemIds (already handled above)
                const txItemIds = Array.isArray(txData.itemIds) ? txData.itemIds : [];
                if (txItemIds.includes(itemId))
                    continue;
                // Skip frozen inventory movement transactions.
                if (isFrozenInventoryMovement(txData))
                    continue;
                const result = await computeIsComplete(db, accountId, srcTxId, txData);
                const currentIsComplete = txData.isComplete ?? null;
                const currentAudit = txData.audit ?? null;
                if (currentIsComplete !== result.isComplete ||
                    JSON.stringify(currentAudit) !== JSON.stringify(result.audit)) {
                    await txRef.set({
                        isComplete: result.isComplete,
                        audit: result.audit,
                        updatedAt: firestore_1.FieldValue.serverTimestamp(),
                    }, { merge: true });
                }
            }
        }
        catch (err) {
            console.error(`[onItemPriceChanged] lineage-based isComplete recompute failed for item ${itemId}:`, err);
        }
    }
});
/**
 * Phase 6: Space Deletion Cleanup Cloud Function
 *
 * When a space is soft-deleted (isArchived changes from false to true),
 * this function clears the spaceId field from all items that belong to that space.
 *
 * Key features:
 * - Triggers on space update (Firestore trigger)
 * - Detects isArchived change from false to true
 * - Batch updates items to clear spaceId field
 * - Handles large batches (Firestore batch limit = 500)
 * - Scoped to correct workspace (respects projectId)
 * - Logs success/failure
 */
exports.onSpaceArchived = (0, firestore_2.onDocumentUpdated)('accounts/{accountId}/spaces/{spaceId}', async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) {
        console.warn('[onSpaceArchived] Missing before/after data');
        return;
    }
    const accountId = event.params.accountId;
    const spaceId = event.params.spaceId;
    // Only process when isArchived changes from false to true
    const wasArchived = before.isArchived === true;
    const nowArchived = after.isArchived === true;
    if (wasArchived || !nowArchived) {
        // Not a soft delete operation, skip
        return;
    }
    console.log(`[onSpaceArchived] Space ${spaceId} archived, clearing items...`);
    const db = (0, firestore_1.getFirestore)();
    const projectId = after.projectId ?? null;
    try {
        // Query all items that belong to this space
        let itemsQuery = db
            .collection(`accounts/${accountId}/items`)
            .where('spaceId', '==', spaceId);
        // Scope to the correct workspace (project or business inventory)
        if (projectId !== null) {
            itemsQuery = itemsQuery.where('projectId', '==', projectId);
        }
        else {
            // Business inventory context (projectId is null)
            itemsQuery = itemsQuery.where('projectId', '==', null);
        }
        const snapshot = await itemsQuery.get();
        const itemCount = snapshot.docs.length;
        if (itemCount === 0) {
            console.log(`[onSpaceArchived] No items found for space ${spaceId}`);
            return;
        }
        console.log(`[onSpaceArchived] Found ${itemCount} items to update for space ${spaceId}`);
        // Firestore batch limit is 500 operations
        const BATCH_SIZE = 500;
        const batches = [];
        let currentBatch = db.batch();
        let operationCount = 0;
        snapshot.docs.forEach((doc) => {
            currentBatch.update(doc.ref, {
                spaceId: null,
                updatedAt: firestore_1.FieldValue.serverTimestamp(),
            });
            operationCount++;
            // Create a new batch if we hit the limit
            if (operationCount === BATCH_SIZE) {
                batches.push(currentBatch);
                currentBatch = db.batch();
                operationCount = 0;
            }
        });
        // Add the last batch if it has any operations
        if (operationCount > 0) {
            batches.push(currentBatch);
        }
        // Commit all batches
        console.log(`[onSpaceArchived] Committing ${batches.length} batch(es) for space ${spaceId}`);
        await Promise.all(batches.map((batch) => batch.commit()));
        console.log(`[onSpaceArchived] Successfully cleared spaceId from ${itemCount} items for space ${spaceId}`);
    }
    catch (error) {
        const message = error instanceof Error ? error.message : 'Unknown error';
        console.error(`[onSpaceArchived] Failed to clear items for space ${spaceId}: ${message}`, error);
        // Don't throw - we want the space deletion to succeed even if cleanup fails
        // Items will still be accessible, just with an invalid spaceId reference
    }
});
function defaultCompanyFinancialAccess(role) {
    return role === 'owner' || role === 'admin' ? 'full' : 'none';
}
function normalizedCompanyFinancialAccess(value, role) {
    return value === 'full' || value === 'limited' || value === 'none'
        ? value
        : defaultCompanyFinancialAccess(role);
}
function normalizedAllowedFeeCategoryIds(value, access) {
    if (access !== 'limited' || !Array.isArray(value))
        return [];
    return Array.from(new Set(value.filter((id) => typeof id === 'string' && id.trim().length > 0)));
}
async function requireBearerUid(request) {
    const authorization = request.headers.authorization ?? '';
    const match = authorization.match(/^Bearer (.+)$/);
    if (!match) {
        throw new https_1.HttpsError('unauthenticated', 'Must be signed in.');
    }
    const decoded = await admin.auth().verifyIdToken(match[1]);
    return decoded.uid;
}
function httpsStatusForError(error) {
    if (error instanceof https_1.HttpsError) {
        switch (error.code) {
            case 'invalid-argument': return 400;
            case 'unauthenticated': return 401;
            case 'permission-denied': return 403;
            case 'not-found': return 404;
            case 'already-exists': return 409;
            case 'deadline-exceeded': return 410;
            default: return 500;
        }
    }
    return 500;
}
function errorBody(error) {
    return {
        error: {
            status: error instanceof https_1.HttpsError ? error.code : 'internal',
            message: error instanceof Error ? error.message : 'Internal error.',
        }
    };
}
async function findInviteByToken(token) {
    if (!token || typeof token !== 'string' || !token.trim()) {
        throw new https_1.HttpsError('invalid-argument', 'Invitation token is required.');
    }
    const db = (0, firestore_1.getFirestore)();
    const accountsSnapshot = await db.collectionGroup('invites').where('token', '==', token).limit(1).get();
    if (!accountsSnapshot.empty) {
        const inviteDoc = accountsSnapshot.docs[0];
        const pathParts = inviteDoc.ref.path.split('/');
        const accountId = pathParts[1];
        const inviteData = inviteDoc.data();
        if (!accountId || !inviteData) {
            throw new https_1.HttpsError('not-found', 'Invalid or expired invitation link.');
        }
        return { inviteRef: inviteDoc.ref, accountId, inviteData };
    }
    const inviteId = token;
    const allAccountsSnapshot = await db.collection('accounts').limit(100).get();
    for (const accountDoc of allAccountsSnapshot.docs) {
        const testInviteRef = db.doc(`accounts/${accountDoc.id}/invites/${inviteId}`);
        const testInviteSnap = await testInviteRef.get();
        if (testInviteSnap.exists) {
            const inviteData = testInviteSnap.data();
            if (!inviteData)
                break;
            return { inviteRef: testInviteRef, accountId: accountDoc.id, inviteData };
        }
    }
    throw new https_1.HttpsError('not-found', 'Invalid or expired invitation link.');
}
function assertInviteCanBeAccepted(inviteData) {
    const status = inviteData.status;
    const expiresAt = inviteData.expiresAt;
    const acceptedAt = inviteData.acceptedAt;
    if (status === 'accepted' || acceptedAt) {
        throw new https_1.HttpsError('already-exists', 'This invitation has already been accepted.');
    }
    if (status === 'revoked' || status === 'cancelled' || inviteData.revokedAt) {
        throw new https_1.HttpsError('permission-denied', 'This invitation has been cancelled.');
    }
    if (expiresAt && expiresAt.toMillis() < Date.now()) {
        throw new https_1.HttpsError('deadline-exceeded', 'This invitation has expired.');
    }
}
const BUDGET_CATEGORY_PRESET_SEED = [
    {
        id: 'seed_furnishings',
        name: 'Furnishings',
        slug: 'furnishings',
        order: 0,
        metadata: { categoryType: 'itemized', excludeFromOverallBudget: false },
    },
    {
        id: 'seed_install',
        name: 'Install',
        slug: 'install',
        order: 1,
        metadata: { categoryType: 'general', excludeFromOverallBudget: false },
    },
    {
        id: 'seed_design_fee',
        name: 'Design Fee',
        slug: 'design-fee',
        order: 2,
        metadata: { categoryType: 'fee', excludeFromOverallBudget: true },
    },
    {
        id: 'seed_storage_receiving',
        name: 'Storage & Receiving',
        slug: 'storage-receiving',
        order: 3,
        metadata: { categoryType: 'general', excludeFromOverallBudget: false },
    },
];
async function ensureBudgetCategoryPresetsSeeded(params) {
    const { accountId, createdBy } = params;
    const db = (0, firestore_1.getFirestore)();
    const now = firestore_1.FieldValue.serverTimestamp();
    const collectionRef = db.collection(`accounts/${accountId}/presets/default/budgetCategories`);
    const accountPresetsRef = db.doc(`accounts/${accountId}/presets/default`);
    await db.runTransaction(async (tx) => {
        // PHASE 1: ALL READS — Firestore requires all reads before any writes.
        const existingFurnishings = await tx.get(collectionRef.where('name', '==', 'Furnishings').limit(1));
        // Pre-read seed refs and account presets (needed for the slow path).
        const seedRefs = BUDGET_CATEGORY_PRESET_SEED.map((seed) => collectionRef.doc(seed.id));
        const [accountPresetsSnap, ...seedSnaps] = await Promise.all([
            tx.get(accountPresetsRef),
            ...seedRefs.map((ref) => tx.get(ref)),
        ]);
        // PHASE 2: ALL WRITES
        if (!existingFurnishings.empty) {
            // Fast path: presets already exist. Ensure Furnishings isn't archived.
            const docSnap = existingFurnishings.docs[0];
            const data = docSnap.data();
            if (data?.isArchived === true) {
                tx.set(docSnap.ref, {
                    isArchived: false,
                    updatedAt: now,
                    updatedBy: createdBy ?? null,
                }, { merge: true });
            }
            return;
        }
        // Seed all default budget categories in an idempotent way.
        for (let i = 0; i < BUDGET_CATEGORY_PRESET_SEED.length; i++) {
            const seed = BUDGET_CATEGORY_PRESET_SEED[i];
            if (seedSnaps[i].exists)
                continue;
            tx.set(seedRefs[i], {
                id: seed.id,
                accountId,
                projectId: null,
                name: seed.name,
                slug: seed.slug,
                isArchived: false,
                order: seed.order,
                metadata: seed.metadata ?? null,
                createdAt: now,
                updatedAt: now,
                deletedAt: null,
                createdBy: createdBy ?? null,
                updatedBy: createdBy ?? null,
            }, { merge: false });
        }
        // Set Furnishings as the default category in AccountPresets.
        if (!accountPresetsSnap.exists || !accountPresetsSnap.data()?.defaultBudgetCategoryId) {
            tx.set(accountPresetsRef, {
                id: 'default',
                accountId,
                defaultBudgetCategoryId: 'seed_furnishings',
                updatedAt: now,
            }, { merge: true });
        }
    });
}
/**
 * Bootstrap presets on first membership creation (covers client-side account creation too).
 */
exports.onAccountMembershipCreated = (0, firestore_2.onDocumentCreated)('accounts/{accountId}/users/{uid}', async (event) => {
    const accountId = event.params.accountId;
    const uid = event.params.uid ?? null;
    if (!accountId)
        return;
    await ensureBudgetCategoryPresetsSeeded({ accountId, createdBy: uid });
});
/**
 * Create a new account and the caller's membership (server-owned).
 */
async function createAccountForUid(uid, data) {
    const rawName = data?.name;
    const name = typeof rawName === 'string' && rawName.trim() ? rawName.trim().slice(0, 80) : 'My account';
    const db = (0, firestore_1.getFirestore)();
    const now = firestore_1.FieldValue.serverTimestamp();
    const accountRef = db.collection('accounts').doc();
    const accountId = accountRef.id;
    const membershipRef = db.doc(`accounts/${accountId}/users/${uid}`);
    await db.runTransaction(async (tx) => {
        tx.set(accountRef, {
            name,
            createdAt: now,
            createdBy: uid
        }, { merge: false });
        tx.set(membershipRef, {
            uid,
            role: 'owner',
            companyFinancialAccess: 'full',
            allowedFeeCategoryIds: [],
            joinedAt: now
        }, { merge: false });
    });
    // Bootstrap required presets before returning, to avoid downstream UI/code relying on missing seeds.
    await ensureBudgetCategoryPresetsSeeded({ accountId, createdBy: uid });
    return { accountId, role: 'owner', name };
}
exports.createAccount = (0, https_1.onCall)(async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
        throw new https_1.HttpsError('unauthenticated', 'Must be signed in.');
    }
    return createAccountForUid(uid, request.data);
});
exports.createAccountHttp = (0, https_1.onRequest)({ invoker: 'public' }, async (request, response) => {
    try {
        if (request.method !== 'POST') {
            throw new https_1.HttpsError('invalid-argument', 'POST is required.');
        }
        const uid = await requireBearerUid(request);
        const data = request.body?.data;
        const result = await createAccountForUid(uid, data);
        response.status(200).json({ result });
    }
    catch (error) {
        response.status(httpsStatusForError(error)).json(errorBody(error));
    }
});
/**
 * Create a new project (server-owned, entitlements-safe).
 */
exports.createProject = (0, https_1.onCall)(async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
        throw new https_1.HttpsError('unauthenticated', 'Must be signed in.');
    }
    const rawAccountId = request.data?.accountId;
    const rawName = request.data?.name;
    const rawClientName = request.data?.clientName;
    const accountId = typeof rawAccountId === 'string' ? rawAccountId.trim() : '';
    const name = typeof rawName === 'string' ? rawName.trim() : '';
    const clientName = typeof rawClientName === 'string' ? rawClientName.trim() : '';
    if (!accountId || !name || !clientName) {
        throw new https_1.HttpsError('invalid-argument', 'accountId, name, and clientName are required.');
    }
    const db = (0, firestore_1.getFirestore)();
    const now = firestore_1.FieldValue.serverTimestamp();
    const projectRef = db.collection(`accounts/${accountId}/projects`).doc();
    const projectId = projectRef.id;
    // Ensure required budget presets exist before we try to pin Furnishings.
    await ensureBudgetCategoryPresetsSeeded({ accountId, createdBy: uid });
    const presetBudgetCategories = db
        .collection(`accounts/${accountId}/presets/default/budgetCategories`)
        .where('name', '==', 'Furnishings')
        .limit(1);
    const presetSnapshot = await presetBudgetCategories.get();
    const furnishingsId = presetSnapshot.empty ? null : presetSnapshot.docs[0].id;
    const projectPreferencesRef = db.doc(`accounts/${accountId}/users/${uid}/projectPreferences/${projectId}`);
    await db.runTransaction(async (tx) => {
        tx.set(projectRef, {
            accountId,
            name,
            clientName,
            createdAt: now,
            updatedAt: now,
            createdBy: uid,
            isArchived: false,
        }, { merge: false });
        tx.set(projectPreferencesRef, {
            id: projectId,
            accountId,
            userId: uid,
            projectId,
            pinnedBudgetCategoryIds: furnishingsId ? [furnishingsId] : [],
            createdAt: now,
            updatedAt: now,
        }, { merge: true });
    });
    return { projectId };
});
/**
 * Accept an invitation token and create/update account membership.
 * This function is idempotent - if the user is already a member, it returns success.
 */
async function acceptInviteForUid(uid, data) {
    const { token } = data ?? {};
    if (!token || typeof token !== 'string' || !token.trim()) {
        throw new https_1.HttpsError('invalid-argument', 'Invitation token is required.');
    }
    const db = (0, firestore_1.getFirestore)();
    const now = firestore_1.FieldValue.serverTimestamp();
    const { inviteRef, accountId, inviteData } = await findInviteByToken(token);
    const status = inviteData.status;
    const expiresAt = inviteData.expiresAt;
    const acceptedAt = inviteData.acceptedAt;
    const acceptedByUid = inviteData.acceptedByUid;
    if (status === 'accepted' || acceptedAt) {
        if (acceptedByUid === uid) {
            const userRef = db.doc(`accounts/${accountId}/users/${uid}`);
            const userSnap = await userRef.get();
            if (userSnap.exists) {
                const userData = userSnap.data();
                return {
                    accountId,
                    role: userData?.role || 'user',
                };
            }
        }
        throw new https_1.HttpsError('already-exists', 'This invitation has already been accepted.');
    }
    if (status === 'revoked' || status === 'cancelled') {
        throw new https_1.HttpsError('permission-denied', 'This invitation has been cancelled.');
    }
    if (expiresAt && expiresAt.toMillis() < Date.now()) {
        throw new https_1.HttpsError('deadline-exceeded', 'This invitation has expired.');
    }
    const inviteEmail = typeof inviteData.email === 'string' ? inviteData.email.trim().toLowerCase() : '';
    const authUser = await admin.auth().getUser(uid);
    const authEmail = authUser.email?.trim().toLowerCase() ?? '';
    if (!inviteEmail || !authEmail || inviteEmail !== authEmail) {
        throw new https_1.HttpsError('permission-denied', 'This invitation must be accepted by the invited email address.');
    }
    const createdAt = authUser.metadata.creationTime ? Date.parse(authUser.metadata.creationTime) : Number.NaN;
    const fifteenMinutesMs = 15 * 60 * 1000;
    if (!Number.isFinite(createdAt) || Date.now() - createdAt > fifteenMinutesMs) {
        throw new https_1.HttpsError('already-exists', 'An account already exists for this email.');
    }
    const role = inviteData.role || 'user';
    const companyFinancialAccess = normalizedCompanyFinancialAccess(inviteData.companyFinancialAccess, role);
    const allowedFeeCategoryIds = normalizedAllowedFeeCategoryIds(inviteData.allowedFeeCategoryIds, companyFinancialAccess);
    const userRef = db.doc(`accounts/${accountId}/users/${uid}`);
    const result = await db.runTransaction(async (tx) => {
        const inviteSnap = await tx.get(inviteRef);
        if (!inviteSnap.exists) {
            throw new https_1.HttpsError('not-found', 'Invitation no longer exists.');
        }
        const currentInviteData = inviteSnap.data();
        if (currentInviteData?.acceptedAt) {
            if (currentInviteData.acceptedByUid === uid) {
                const userSnap = await tx.get(userRef);
                if (userSnap.exists) {
                    const userData = userSnap.data();
                    return {
                        accountId: accountId,
                        role: userData?.role || 'user',
                    };
                }
            }
            throw new https_1.HttpsError('already-exists', 'This invitation has already been accepted.');
        }
        const userSnap = await tx.get(userRef);
        const userExists = userSnap.exists;
        tx.set(userRef, {
            uid,
            role,
            companyFinancialAccess,
            allowedFeeCategoryIds,
            joinedAt: userExists ? userSnap.data()?.joinedAt : now,
            joinedBy: userExists ? userSnap.data()?.joinedBy : inviteData.createdByUid || inviteData.createdBy || null,
            updatedAt: now,
        }, { merge: true });
        tx.update(inviteRef, {
            status: 'accepted',
            acceptedAt: now,
            acceptedByUid: uid,
            updatedAt: now,
        });
        return {
            accountId: accountId,
            role,
        };
    });
    await ensureBudgetCategoryPresetsSeeded({ accountId, createdBy: uid });
    return result;
}
async function previewInvite(data) {
    const { token } = data ?? {};
    const { inviteData } = await findInviteByToken(token);
    assertInviteCanBeAccepted(inviteData);
    const email = typeof inviteData.email === 'string' ? inviteData.email.trim().toLowerCase() : '';
    if (!email) {
        throw new https_1.HttpsError('not-found', 'Invalid or expired invitation link.');
    }
    const role = inviteData.role || 'user';
    const companyFinancialAccess = normalizedCompanyFinancialAccess(inviteData.companyFinancialAccess, role);
    return { email, role, companyFinancialAccess };
}
exports.previewInviteHttp = (0, https_1.onRequest)({ invoker: 'public' }, async (request, response) => {
    try {
        if (request.method !== 'POST') {
            throw new https_1.HttpsError('invalid-argument', 'POST is required.');
        }
        const data = request.body?.data;
        const result = await previewInvite(data);
        response.status(200).json({ result });
    }
    catch (error) {
        response.status(httpsStatusForError(error)).json(errorBody(error));
    }
});
exports.acceptInvite = (0, https_1.onCall)(async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
        throw new https_1.HttpsError('unauthenticated', 'Must be signed in to accept an invitation.');
    }
    return acceptInviteForUid(uid, request.data);
});
exports.acceptInviteHttp = (0, https_1.onRequest)({ invoker: 'public' }, async (request, response) => {
    try {
        if (request.method !== 'POST') {
            throw new https_1.HttpsError('invalid-argument', 'POST is required.');
        }
        const uid = await requireBearerUid(request);
        const data = request.body?.data;
        const result = await acceptInviteForUid(uid, data);
        response.status(200).json({ result });
    }
    catch (error) {
        response.status(httpsStatusForError(error)).json(errorBody(error));
    }
});
// ---------------------------------------------------------------------------
// Budget Summary Denormalization
// ---------------------------------------------------------------------------
// Maintains a precomputed `budgetSummary` on each project document so the
// projects list can display budget progress without extra queries.
function normalizeCategoryType(value) {
    switch (value?.trim().toLowerCase()) {
        case 'fee': return 'fee';
        case 'itemized': return 'itemized';
        case 'general': return 'general';
        default: return null;
    }
}
function resolveCategoryTypeFromCategoryData(data) {
    const metadata = data?.metadata && typeof data.metadata === 'object'
        ? data.metadata
        : {};
    return normalizeCategoryType(typeof metadata.categoryType === 'string' ? metadata.categoryType : null) ?? 'general';
}
async function transactionUsesItemsCategory(db, accountId, txData) {
    const categoryId = typeof txData.budgetCategoryId === 'string'
        ? txData.budgetCategoryId.trim()
        : null;
    if (!categoryId)
        return false;
    const categorySnap = await db
        .doc(`accounts/${accountId}/presets/default/budgetCategories/${categoryId}`)
        .get();
    if (!categorySnap.exists)
        return false;
    return resolveCategoryTypeFromCategoryData(categorySnap.data()) === 'itemized';
}
/**
 * Full, idempotent recalculation of a project's budget summary.
 * Queries all source data and writes the computed summary to the project doc.
 */
async function recalculateProjectBudgetSummary(accountId, projectId) {
    const db = (0, firestore_1.getFirestore)();
    // 1. Fetch account-level budget categories (names, metadata)
    const budgetCatsSnapshot = await db
        .collection(`accounts/${accountId}/presets/default/budgetCategories`)
        .get();
    const budgetCategories = {};
    for (const doc of budgetCatsSnapshot.docs) {
        const data = doc.data() ?? {};
        const metadata = data.metadata && typeof data.metadata === 'object'
            ? data.metadata
            : {};
        const categoryType = resolveCategoryTypeFromCategoryData(data);
        budgetCategories[doc.id] = {
            name: typeof data.name === 'string' ? data.name : '',
            categoryType,
            excludeFromOverallBudget: metadata.excludeFromOverallBudget === true,
            isArchived: data.isArchived === true,
        };
    }
    // 2. Fetch project budget categories (budgetCents per category)
    const projectBudgetCatsSnapshot = await db
        .collection(`accounts/${accountId}/projects/${projectId}/budgetCategories`)
        .get();
    const projectBudgetCents = {};
    for (const doc of projectBudgetCatsSnapshot.docs) {
        const data = doc.data() ?? {};
        projectBudgetCents[doc.id] =
            typeof data.budgetCents === 'number' ? data.budgetCents : 0;
    }
    // 3. Fetch all transactions for this project
    const txSnapshot = await db
        .collection(`accounts/${accountId}/transactions`)
        .where('projectId', '==', projectId)
        .get();
    // 4. Compute spend per category (mirrors normalizeSpendAmount in budgetProgressService.ts)
    const spentByCategory = {};
    for (const doc of txSnapshot.docs) {
        const tx = doc.data() ?? {};
        if (tx.status === 'canceled')
            continue;
        if (typeof tx.amountCents !== 'number')
            continue;
        const categoryId = typeof tx.budgetCategoryId === 'string'
            ? tx.budgetCategoryId.trim()
            : null;
        if (!categoryId)
            continue;
        let amount = tx.amountCents;
        const txType = typeof tx.type === 'string'
            ? tx.type.trim().toLowerCase()
            : null;
        if (txType === 'return') {
            amount = -Math.abs(amount);
        }
        else if (tx.isCanonicalInventorySale && tx.inventorySaleDirection) {
            amount =
                tx.inventorySaleDirection === 'project_to_business'
                    ? -Math.abs(amount)
                    : Math.abs(amount);
        }
        else if (txType === 'sale') {
            amount = -Math.abs(amount);
        }
        spentByCategory[categoryId] = (spentByCategory[categoryId] ?? 0) + amount;
    }
    // 5. Build the summary — only include categories with non-zero budget or spend
    const categories = {};
    let overallSpentCents = 0;
    let overallBudgetCents = 0;
    const allCategoryIds = new Set([
        ...Object.keys(budgetCategories),
        ...Object.keys(projectBudgetCents),
        ...Object.keys(spentByCategory),
    ]);
    for (const catId of allCategoryIds) {
        const catMeta = budgetCategories[catId];
        const budgetCents = projectBudgetCents[catId] ?? 0;
        const spentCents = spentByCategory[catId] ?? 0;
        if (budgetCents === 0 && spentCents === 0)
            continue;
        categories[catId] = {
            budgetCents,
            spentCents,
            name: catMeta?.name ?? '',
            categoryType: catMeta?.categoryType ?? 'general',
            excludeFromOverallBudget: catMeta?.excludeFromOverallBudget ?? false,
            isArchived: catMeta?.isArchived ?? false,
        };
        if (!(catMeta?.excludeFromOverallBudget)) {
            overallSpentCents += spentCents;
            overallBudgetCents += budgetCents;
        }
    }
    // 6. Write to project document. Use `set` with mergeFields so test/emulator
    // fixtures with synthetic project IDs are created if absent, while the entire
    // `budgetSummary` field is still replaced wholesale. Plain `set` merge:true
    // would deep-merge the `categories` map and leave stale category entries.
    const projectRef = db.doc(`accounts/${accountId}/projects/${projectId}`);
    await projectRef.set({
        budgetSummary: {
            spentCents: overallSpentCents,
            totalBudgetCents: overallBudgetCents,
            categories,
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
        },
    }, {
        mergeFields: ['budgetSummary'],
    });
}
// ---------------------------------------------------------------------------
// Transaction Completeness: isComplete + audit
// ---------------------------------------------------------------------------
/**
 * Compute isComplete and audit for a transaction.
 * Returns { isComplete, audit } where audit is null when not applicable.
 */
async function computeIsComplete(db, accountId, transactionId, txData) {
    // 1. Canonical transactions: complete only if all linked items have taxRatePct
    if (txData.isCanonicalInventorySale === true || txData.isCanonicalInventory === true) {
        const itemIds = Array.isArray(txData.itemIds) ? txData.itemIds : [];
        if (itemIds.length === 0) {
            return { isComplete: true, audit: null };
        }
        const itemDocs = await Promise.all(itemIds.map(id => db.doc(`accounts/${accountId}/items/${id}`).get()));
        const missingItemIds = itemDocs
            .filter(d => {
            const data = d.data();
            return !data || data.taxRatePct == null;
        })
            .map(d => d.id);
        if (missingItemIds.length === 0) {
            return { isComplete: true, audit: null };
        }
        return {
            isComplete: false,
            audit: {
                itemsMissingTaxRateCount: missingItemIds.length,
                itemsMissingTaxRate: missingItemIds,
                totalItemCount: itemIds.length,
            },
        };
    }
    // 2. Only item categories use transaction completeness audit. Purchases can
    //    be services, fuel, storage, or other project costs; those are complete
    //    at the transaction level and do not need item rows.
    const txType = typeof txData.type === 'string' ? txData.type.trim().toLowerCase() : null;
    if (txType !== 'purchase' && txType !== 'return') {
        return { isComplete: true, audit: null };
    }
    const usesItemsCategory = await transactionUsesItemsCategory(db, accountId, txData);
    if (!usesItemsCategory) {
        return { isComplete: true, audit: null };
    }
    // From here: tx is an item-category purchase or return — needs tax/subtotal audit
    // 3. Check tax data presence (strict null check — taxRatePct: 0 is valid)
    const hasSubtotal = txData.subtotalCents !== null && txData.subtotalCents !== undefined;
    const hasTaxRate = txData.taxRatePct !== null && txData.taxRatePct !== undefined;
    if (!hasSubtotal && !hasTaxRate) {
        return { isComplete: false, audit: null };
    }
    // 4. Check items (linked + lineage)
    const itemIds = Array.isArray(txData.itemIds) ? txData.itemIds : [];
    const itemIdSet = new Set(itemIds);
    // 4b. Query lineage edges from this transaction (returned + sold items)
    const edgesSnapshot = await db
        .collection(`accounts/${accountId}/lineageEdges`)
        .where('fromTransactionId', '==', transactionId)
        .get();
    // Filter to returned/sold, deduplicate by itemId (keep latest by createdAt)
    const lineageItemMap = new Map();
    for (const edgeDoc of edgesSnapshot.docs) {
        const edge = edgeDoc.data() ?? {};
        const kind = edge.movementKind;
        if (kind !== 'returned' && kind !== 'sold' && kind !== 'soldToInventory')
            continue;
        const edgeItemId = edge.itemId;
        if (!edgeItemId)
            continue;
        // Skip items still in itemIds (prevent double-counting)
        if (itemIdSet.has(edgeItemId))
            continue;
        const existing = lineageItemMap.get(edgeItemId);
        if (!existing) {
            lineageItemMap.set(edgeItemId, { movementKind: kind, createdAt: edge.createdAt });
        }
        else {
            // Keep latest by createdAt
            const existingTime = existing.createdAt instanceof Date ? existing.createdAt.getTime() : 0;
            const newTime = edge.createdAt instanceof Date ? edge.createdAt.getTime() : 0;
            if (newTime > existingTime) {
                lineageItemMap.set(edgeItemId, { movementKind: kind, createdAt: edge.createdAt });
            }
        }
    }
    // Bail if no items at all (neither linked nor lineage)
    if (itemIds.length === 0 && lineageItemMap.size === 0) {
        return { isComplete: false, audit: null };
    }
    // 5. Resolve subtotal
    let resolvedSubtotalCents = null;
    const subtotalCents = typeof txData.subtotalCents === 'number' ? txData.subtotalCents : null;
    const amountCents = typeof txData.amountCents === 'number' ? txData.amountCents : null;
    const taxRatePct = typeof txData.taxRatePct === 'number' ? txData.taxRatePct : null;
    if (subtotalCents !== null && subtotalCents > 0) {
        resolvedSubtotalCents = subtotalCents;
    }
    else if (amountCents !== null && amountCents > 0 && taxRatePct !== null && taxRatePct > 0) {
        resolvedSubtotalCents = Math.round(amountCents / (1 + taxRatePct / 100));
    }
    else if (amountCents !== null && amountCents > 0 && taxRatePct === 0) {
        // taxRatePct is explicitly 0 — no tax, amount is the subtotal
        resolvedSubtotalCents = amountCents;
    }
    if (resolvedSubtotalCents === null || resolvedSubtotalCents <= 0) {
        return { isComplete: false, audit: null };
    }
    // 6. Fetch linked items and sum purchasePriceCents
    // Firestore 'in' queries max 30 items per batch
    let linkedItemsSumCents = 0;
    const BATCH_SIZE = 30;
    for (let i = 0; i < itemIds.length; i += BATCH_SIZE) {
        const batch = itemIds.slice(i, i + BATCH_SIZE);
        const snapshot = await db
            .collection(`accounts/${accountId}/items`)
            .where('__name__', 'in', batch)
            .get();
        for (const doc of snapshot.docs) {
            const data = doc.data() ?? {};
            linkedItemsSumCents += typeof data.purchasePriceCents === 'number' ? data.purchasePriceCents : 0;
        }
    }
    // 6b. Fetch lineage items and sum by movementKind
    let returnedItemsSumCents = 0;
    let returnedItemsCount = 0;
    let soldItemsSumCents = 0;
    let soldItemsCount = 0;
    const lineageItemIds = Array.from(lineageItemMap.keys());
    if (lineageItemIds.length > 0) {
        for (let i = 0; i < lineageItemIds.length; i += BATCH_SIZE) {
            const batch = lineageItemIds.slice(i, i + BATCH_SIZE);
            const snapshot = await db
                .collection(`accounts/${accountId}/items`)
                .where('__name__', 'in', batch)
                .get();
            for (const doc of snapshot.docs) {
                const data = doc.data() ?? {};
                const priceCents = typeof data.purchasePriceCents === 'number' ? data.purchasePriceCents : 0;
                const edgeInfo = lineageItemMap.get(doc.id);
                if (edgeInfo?.movementKind === 'returned') {
                    returnedItemsSumCents += priceCents;
                    returnedItemsCount++;
                }
                else if (edgeInfo?.movementKind === 'sold' || edgeInfo?.movementKind === 'soldToInventory') {
                    soldItemsSumCents += priceCents;
                    soldItemsCount++;
                }
            }
        }
    }
    // 7. Compute totals and variance. Discounts live at the transaction level
    // because receipts often apply one promo across all lines rather than per item.
    const itemsSumCents = linkedItemsSumCents + returnedItemsSumCents + soldItemsSumCents;
    const discount = txData.discount && typeof txData.discount === 'object' ? txData.discount : null;
    const discountCents = typeof discount?.amountCents === 'number'
        ? Math.max(0, Math.round(discount.amountCents))
        : 0;
    const discountedItemsSumCents = Math.max(0, itemsSumCents - discountCents);
    const varianceCents = discountedItemsSumCents - resolvedSubtotalCents;
    const variancePercent = (varianceCents / resolvedSubtotalCents) * 100;
    const isComplete = Math.abs(variancePercent) <= 1;
    return {
        isComplete,
        audit: {
            resolvedSubtotalCents,
            itemsSumCents,
            discountCents,
            varianceCents,
            variancePercent: Math.round(variancePercent * 100) / 100, // 2 decimal places
            linkedItemsSumCents,
            returnedItemsSumCents,
            returnedItemsCount,
            soldItemsSumCents,
            soldItemsCount,
        },
    };
}
/** Fields that, when they are the ONLY changes, should not re-trigger isComplete computation. */
const IS_COMPLETE_LOOP_GUARD_FIELDS = new Set(['isComplete', 'audit', 'updatedAt']);
function onlyLoopGuardFieldsChanged(before, after) {
    if (!before || !after)
        return false;
    const allKeys = new Set([...Object.keys(before), ...Object.keys(after)]);
    for (const key of allKeys) {
        if (IS_COMPLETE_LOOP_GUARD_FIELDS.has(key))
            continue;
        if (JSON.stringify(before[key]) !== JSON.stringify(after[key]))
            return false;
    }
    return true;
}
/**
 * Recalculate budget summary when any transaction is created, updated, or deleted.
 * Also computes isComplete + audit for transaction completeness.
 * Handles transactions moving between projects by recalculating both.
 */
exports.onTransactionWritten = (0, firestore_2.onDocumentWritten)('accounts/{accountId}/transactions/{transactionId}', async (event) => {
    const accountId = event.params.accountId;
    const transactionId = event.params.transactionId;
    const beforeData = event.data?.before?.data();
    const afterData = event.data?.after?.data();
    // Loop guard: skip if only isComplete/audit/updatedAt changed
    if (beforeData && afterData && onlyLoopGuardFieldsChanged(beforeData, afterData)) {
        return;
    }
    // --- Budget summary recalculation (existing logic, project-scoped only) ---
    const beforeProjectId = typeof beforeData?.projectId === 'string' ? beforeData.projectId : null;
    const afterProjectId = typeof afterData?.projectId === 'string' ? afterData.projectId : null;
    const budgetPromise = (beforeProjectId || afterProjectId)
        ? Promise.all(Array.from(new Set([beforeProjectId, afterProjectId].filter(Boolean))).map((pid) => recalculateProjectBudgetSummary(accountId, pid).catch((err) => {
            console.error(`[onTransactionWritten] recalculate failed for project ${pid}:`, err);
        })))
        : Promise.resolve();
    // --- isComplete computation (runs for ALL transactions) ---
    let isCompletePromise = Promise.resolve();
    if (afterData) {
        // Transaction exists (create or update) — compute isComplete
        isCompletePromise = (async () => {
            try {
                const db = (0, firestore_1.getFirestore)();
                const result = await computeIsComplete(db, accountId, transactionId, afterData);
                // Only write if values actually differ
                const currentIsComplete = afterData.isComplete ?? null;
                const currentAudit = afterData.audit ?? null;
                const newAudit = result.audit;
                if (currentIsComplete !== result.isComplete ||
                    JSON.stringify(currentAudit) !== JSON.stringify(newAudit)) {
                    await db
                        .doc(`accounts/${accountId}/transactions/${transactionId}`)
                        .set({
                        isComplete: result.isComplete,
                        audit: newAudit,
                        updatedAt: firestore_1.FieldValue.serverTimestamp(),
                    }, { merge: true });
                }
            }
            catch (err) {
                console.error(`[onTransactionWritten] isComplete computation failed for ${transactionId}:`, err);
            }
        })();
    }
    await Promise.all([budgetPromise, isCompletePromise]);
});
/**
 * Recalculate budget summary when a project-level budget category is written.
 */
exports.onProjectBudgetCategoryWritten = (0, firestore_2.onDocumentWritten)('accounts/{accountId}/projects/{projectId}/budgetCategories/{categoryId}', async (event) => {
    const { accountId, projectId } = event.params;
    await recalculateProjectBudgetSummary(accountId, projectId).catch((err) => {
        console.error(`[onProjectBudgetCategoryWritten] recalculate failed for project ${projectId}:`, err);
    });
});
async function recomputeCompletenessForBudgetCategory(db, accountId, categoryId) {
    const txSnapshot = await db
        .collection(`accounts/${accountId}/transactions`)
        .where('budgetCategoryId', '==', categoryId)
        .get();
    const BATCH_SIZE = 500;
    for (let i = 0; i < txSnapshot.docs.length; i += BATCH_SIZE) {
        const slice = txSnapshot.docs.slice(i, i + BATCH_SIZE);
        const batch = db.batch();
        let batchHasWrites = false;
        for (const txDoc of slice) {
            const txData = txDoc.data() ?? {};
            const result = await computeIsComplete(db, accountId, txDoc.id, txData);
            const currentIsComplete = txData.isComplete ?? null;
            const currentAudit = txData.audit ?? null;
            if (currentIsComplete !== result.isComplete ||
                JSON.stringify(currentAudit) !== JSON.stringify(result.audit)) {
                batch.set(txDoc.ref, {
                    isComplete: result.isComplete,
                    audit: result.audit,
                    updatedAt: firestore_1.FieldValue.serverTimestamp(),
                }, { merge: true });
                batchHasWrites = true;
            }
        }
        if (batchHasWrites) {
            await batch.commit();
        }
    }
}
/**
 * Recalculate budget summaries for ALL projects when an account-level budget
 * category changes (name, categoryType, excludeFromOverallBudget, isArchived).
 * Short-circuits when only irrelevant fields changed (order, slug, timestamps).
 */
exports.onAccountBudgetCategoryWritten = (0, firestore_2.onDocumentWritten)('accounts/{accountId}/presets/default/budgetCategories/{categoryId}', async (event) => {
    const accountId = event.params.accountId;
    const categoryId = event.params.categoryId;
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    // On update, skip if only irrelevant fields changed
    if (before && after) {
        const beforeMeta = before.metadata && typeof before.metadata === 'object'
            ? before.metadata
            : {};
        const afterMeta = after.metadata && typeof after.metadata === 'object'
            ? after.metadata
            : {};
        const relevantFieldsChanged = before.name !== after.name ||
            before.isArchived !== after.isArchived ||
            beforeMeta.categoryType !== afterMeta.categoryType ||
            beforeMeta.excludeFromOverallBudget !== afterMeta.excludeFromOverallBudget;
        if (!relevantFieldsChanged)
            return;
    }
    const db = (0, firestore_1.getFirestore)();
    const completenessPromise = recomputeCompletenessForBudgetCategory(db, accountId, categoryId).catch((err) => {
        console.error(`[onAccountBudgetCategoryWritten] isComplete recompute failed for category ${categoryId}:`, err);
    });
    // --- Existing: recalculate budget summaries for all projects ---
    const projectsSnapshot = await db
        .collection(`accounts/${accountId}/projects`)
        .select()
        .get();
    if (!projectsSnapshot.empty) {
        console.log(`[onAccountBudgetCategoryWritten] Recalculating ${projectsSnapshot.size} projects for account ${accountId}`);
        const projectIds = projectsSnapshot.docs.map((d) => d.id);
        const BATCH_SIZE = 5;
        for (let i = 0; i < projectIds.length; i += BATCH_SIZE) {
            const batch = projectIds.slice(i, i + BATCH_SIZE);
            await Promise.all(batch.map((pid) => recalculateProjectBudgetSummary(accountId, pid).catch((err) => {
                console.error(`[onAccountBudgetCategoryWritten] recalculate failed for project ${pid}:`, err);
            })));
        }
    }
    await completenessPromise;
});
exports.backfillBudgetSummaries = (0, https_1.onCall)(async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
        throw new https_1.HttpsError('unauthenticated', 'Must be signed in.');
    }
    const { accountId } = request.data ?? {};
    if (!accountId) {
        throw new https_1.HttpsError('invalid-argument', 'Missing accountId.');
    }
    const db = (0, firestore_1.getFirestore)();
    const projectsSnapshot = await db
        .collection(`accounts/${accountId}/projects`)
        .select()
        .get();
    let processed = 0;
    const projectIds = projectsSnapshot.docs.map((d) => d.id);
    const BATCH_SIZE = 5;
    for (let i = 0; i < projectIds.length; i += BATCH_SIZE) {
        const batch = projectIds.slice(i, i + BATCH_SIZE);
        await Promise.all(batch.map((pid) => recalculateProjectBudgetSummary(accountId, pid).catch((err) => {
            console.error(`[backfillBudgetSummaries] failed for project ${pid}:`, err);
        })));
        processed += batch.length;
    }
    return { processed, total: projectIds.length };
});
exports.backfillIsComplete = (0, https_1.onCall)(async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
        throw new https_1.HttpsError('unauthenticated', 'Must be signed in.');
    }
    const { accountId } = request.data ?? {};
    if (!accountId) {
        throw new https_1.HttpsError('invalid-argument', 'Missing accountId.');
    }
    const db = (0, firestore_1.getFirestore)();
    const txSnapshot = await db
        .collection(`accounts/${accountId}/transactions`)
        .get();
    let processed = 0;
    let updated = 0;
    const BATCH_SIZE = 500;
    const docs = txSnapshot.docs;
    for (let i = 0; i < docs.length; i += BATCH_SIZE) {
        const slice = docs.slice(i, i + BATCH_SIZE);
        const batch = db.batch();
        let batchHasWrites = false;
        for (const txDoc of slice) {
            const txData = txDoc.data() ?? {};
            const result = await computeIsComplete(db, accountId, txDoc.id, txData);
            const currentIsComplete = txData.isComplete ?? null;
            const currentAudit = txData.audit ?? null;
            if (currentIsComplete !== result.isComplete ||
                JSON.stringify(currentAudit) !== JSON.stringify(result.audit)) {
                batch.set(txDoc.ref, {
                    isComplete: result.isComplete,
                    audit: result.audit,
                    updatedAt: firestore_1.FieldValue.serverTimestamp(),
                }, { merge: true });
                batchHasWrites = true;
                updated++;
            }
            processed++;
        }
        if (batchHasWrites) {
            await batch.commit();
        }
    }
    return { processed, updated, total: docs.length };
});
//# sourceMappingURL=index.js.map