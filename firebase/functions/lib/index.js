"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.acceptInvite = exports.createProject = exports.createAccount = exports.onAccountMembershipCreated = exports.onInventoryRequestCreated = exports.onProjectRequestCreated = exports.onItemTransactionIdChanged = exports.onAccountRequestCreated = exports.createWithQuota = void 0;
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
async function setRequestApplied(requestRef, extra = {}) {
    await requestRef.update({
        status: 'applied',
        appliedAt: firestore_1.FieldValue.serverTimestamp(),
        errorCode: firestore_1.FieldValue.delete(),
        errorMessage: firestore_1.FieldValue.delete(),
        ...extra
    });
}
async function setRequestFailed(requestRef, errorCode, errorMessage) {
    await requestRef.update({
        status: 'failed',
        errorCode,
        errorMessage,
        appliedAt: firestore_1.FieldValue.delete()
    });
}
const requestHandlers = {};
function canonicalPurchaseId(projectId) {
    return `INV_PURCHASE_${projectId}`;
}
function canonicalSaleId(projectId) {
    return `INV_SALE_${projectId}`;
}
function getItemValueCents(item) {
    if (typeof item.projectPriceCents === 'number')
        return item.projectPriceCents;
    if (typeof item.purchasePriceCents === 'number')
        return item.purchasePriceCents;
    return 0;
}
async function ensureCanonicalTransaction(params) {
    const { tx, accountId, transactionId, projectId, kind, amountDelta, itemId } = params;
    const txRef = (0, firestore_1.getFirestore)().doc(`accounts/${accountId}/transactions/${transactionId}`);
    const snap = await tx.get(txRef);
    const now = firestore_1.FieldValue.serverTimestamp();
    if (!snap.exists) {
        tx.set(txRef, {
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
        }, { merge: true });
        return;
    }
    const data = snap.data() ?? {};
    const existingAmount = typeof data.amountCents === 'number' ? data.amountCents : 0;
    const existingItemIds = Array.isArray(data.itemIds) ? data.itemIds : [];
    const nextAmount = existingAmount + amountDelta;
    const nextItemIds = existingItemIds.includes(itemId) ? existingItemIds : [...existingItemIds, itemId];
    tx.set(txRef, {
        projectId,
        isCanonicalInventory: true,
        canonicalKind: kind,
        amountCents: nextAmount,
        itemIds: nextItemIds,
        updatedAt: now,
    }, { merge: true });
}
async function removeFromCanonicalTransaction(params) {
    const { tx, accountId, transactionId, amountDelta, itemId } = params;
    const txRef = (0, firestore_1.getFirestore)().doc(`accounts/${accountId}/transactions/${transactionId}`);
    const snap = await tx.get(txRef);
    if (!snap.exists)
        return;
    const data = snap.data() ?? {};
    const existingAmount = typeof data.amountCents === 'number' ? data.amountCents : 0;
    const existingItemIds = Array.isArray(data.itemIds) ? data.itemIds : [];
    const nextItemIds = existingItemIds.filter((id) => id !== itemId);
    const nextAmount = Math.max(0, existingAmount - amountDelta);
    tx.set(txRef, {
        amountCents: nextAmount,
        itemIds: nextItemIds,
        updatedAt: firestore_1.FieldValue.serverTimestamp(),
    }, { merge: true });
}
async function appendLineageEdge(params) {
    const { tx, accountId, requestId, itemId, fromTransactionId, toTransactionId, createdBy, movementKind, source, note, fromProjectId, toProjectId, } = params;
    const edgeId = `edge_${requestId}_${itemId}_${movementKind}`;
    const edgeRef = (0, firestore_1.getFirestore)().doc(`accounts/${accountId}/lineageEdges/${edgeId}`);
    tx.set(edgeRef, {
        id: edgeId,
        accountId,
        itemId,
        fromTransactionId: fromTransactionId ?? null,
        toTransactionId: toTransactionId ?? null,
        createdAt: firestore_1.FieldValue.serverTimestamp(),
        updatedAt: firestore_1.FieldValue.serverTimestamp(),
        deletedAt: null,
        createdBy: createdBy ?? null,
        movementKind,
        source,
        note: note ?? null,
        fromProjectId: fromProjectId ?? null,
        toProjectId: toProjectId ?? null,
    }, { merge: true });
}
function getExpected(payload) {
    const expected = payload?.expected ?? {};
    return {
        itemProjectId: expected.itemProjectId ?? null,
        itemTransactionId: expected.itemTransactionId ?? null,
    };
}
async function handleProjectToBusiness(context) {
    const payload = context.requestData.payload ?? {};
    const itemId = payload.itemId;
    const sourceProjectId = payload.sourceProjectId;
    const note = payload.note;
    if (!itemId || !sourceProjectId) {
        await setRequestFailed(context.requestRef, 'invalid', 'Missing itemId or sourceProjectId.');
        return;
    }
    const db = (0, firestore_1.getFirestore)();
    const itemRef = db.doc(`accounts/${context.accountId}/items/${itemId}`);
    const { itemProjectId, itemTransactionId } = getExpected(payload);
    await db.runTransaction(async (tx) => {
        const itemSnap = await tx.get(itemRef);
        if (!itemSnap.exists) {
            throw new https_1.HttpsError('not-found', 'Item not found.');
        }
        const item = itemSnap.data() ?? {};
        if (itemProjectId !== item.projectId) {
            throw new https_1.HttpsError('failed-precondition', 'Item scope changed.');
        }
        if (itemTransactionId != null && itemTransactionId !== (item.transactionId ?? null)) {
            throw new https_1.HttpsError('failed-precondition', 'Item transaction changed.');
        }
        if (!item.inheritedBudgetCategoryId) {
            throw new https_1.HttpsError('failed-precondition', 'Missing inheritedBudgetCategoryId.');
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
            tx.set(itemRef, {
                projectId: null,
                transactionId: null,
                spaceId: null,
                updatedAt: firestore_1.FieldValue.serverTimestamp(),
                updatedBy: context.requestData.createdBy ?? null,
                latestTransactionId: null,
            }, { merge: true });
            await appendLineageEdge({
                tx,
                accountId: context.accountId,
                requestId: context.requestId,
                itemId,
                fromTransactionId: purchaseId,
                toTransactionId: null,
                createdBy: context.requestData.createdBy,
                movementKind: 'sold',
                source: 'server',
                note: note ?? null,
                fromProjectId: sourceProjectId,
                toProjectId: null,
            });
        }
        else {
            await ensureCanonicalTransaction({
                tx,
                accountId: context.accountId,
                transactionId: saleId,
                projectId: sourceProjectId,
                kind: 'INV_SALE',
                amountDelta,
                itemId,
            });
            tx.set(itemRef, {
                projectId: null,
                transactionId: saleId,
                spaceId: null,
                updatedAt: firestore_1.FieldValue.serverTimestamp(),
                updatedBy: context.requestData.createdBy ?? null,
                latestTransactionId: saleId,
            }, { merge: true });
            await appendLineageEdge({
                tx,
                accountId: context.accountId,
                requestId: context.requestId,
                itemId,
                fromTransactionId: previousTxId,
                toTransactionId: saleId,
                createdBy: context.requestData.createdBy,
                movementKind: 'sold',
                source: 'server',
                note: note ?? null,
                fromProjectId: sourceProjectId,
                toProjectId: null,
            });
        }
    });
    await setRequestApplied(context.requestRef);
}
async function handleBusinessToProject(context) {
    const payload = context.requestData.payload ?? {};
    const itemId = payload.itemId;
    const targetProjectId = payload.targetProjectId;
    const inheritedBudgetCategoryId = payload.inheritedBudgetCategoryId ?? null;
    const note = payload.note;
    if (!itemId || !targetProjectId) {
        await setRequestFailed(context.requestRef, 'invalid', 'Missing itemId or targetProjectId.');
        return;
    }
    const db = (0, firestore_1.getFirestore)();
    const itemRef = db.doc(`accounts/${context.accountId}/items/${itemId}`);
    const { itemProjectId, itemTransactionId } = getExpected(payload);
    await db.runTransaction(async (tx) => {
        const itemSnap = await tx.get(itemRef);
        if (!itemSnap.exists) {
            throw new https_1.HttpsError('not-found', 'Item not found.');
        }
        const item = itemSnap.data() ?? {};
        if (itemProjectId !== item.projectId) {
            throw new https_1.HttpsError('failed-precondition', 'Item scope changed.');
        }
        if (itemTransactionId != null && itemTransactionId !== (item.transactionId ?? null)) {
            throw new https_1.HttpsError('failed-precondition', 'Item transaction changed.');
        }
        if (!inheritedBudgetCategoryId) {
            throw new https_1.HttpsError('failed-precondition', 'Missing inheritedBudgetCategoryId.');
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
        tx.set(itemRef, {
            projectId: targetProjectId,
            transactionId: purchaseId,
            status: item.status ?? 'purchased',
            spaceId: null,
            inheritedBudgetCategoryId,
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
            updatedBy: context.requestData.createdBy ?? null,
            latestTransactionId: purchaseId,
        }, { merge: true });
        await appendLineageEdge({
            tx,
            accountId: context.accountId,
            requestId: context.requestId,
            itemId,
            fromTransactionId: previousTxId,
            toTransactionId: purchaseId,
            createdBy: context.requestData.createdBy,
            movementKind: 'sold',
            source: 'server',
            note: note ?? null,
            fromProjectId: null,
            toProjectId: targetProjectId,
        });
    });
    await setRequestApplied(context.requestRef);
}
async function handleProjectToProject(context) {
    const payload = context.requestData.payload ?? {};
    const itemId = payload.itemId;
    const sourceProjectId = payload.sourceProjectId;
    const targetProjectId = payload.targetProjectId;
    const inheritedBudgetCategoryId = payload.inheritedBudgetCategoryId ?? null;
    const note = payload.note;
    if (!itemId || !sourceProjectId || !targetProjectId) {
        await setRequestFailed(context.requestRef, 'invalid', 'Missing itemId or project ids.');
        return;
    }
    const db = (0, firestore_1.getFirestore)();
    const itemRef = db.doc(`accounts/${context.accountId}/items/${itemId}`);
    const { itemProjectId, itemTransactionId } = getExpected(payload);
    await db.runTransaction(async (tx) => {
        const itemSnap = await tx.get(itemRef);
        if (!itemSnap.exists) {
            throw new https_1.HttpsError('not-found', 'Item not found.');
        }
        const item = itemSnap.data() ?? {};
        if (itemProjectId !== item.projectId) {
            throw new https_1.HttpsError('failed-precondition', 'Item scope changed.');
        }
        if (itemTransactionId != null && itemTransactionId !== (item.transactionId ?? null)) {
            throw new https_1.HttpsError('failed-precondition', 'Item transaction changed.');
        }
        if (!inheritedBudgetCategoryId) {
            throw new https_1.HttpsError('failed-precondition', 'Missing inheritedBudgetCategoryId.');
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
        tx.set(itemRef, {
            projectId: targetProjectId,
            transactionId: purchaseId,
            spaceId: null,
            inheritedBudgetCategoryId,
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
            updatedBy: context.requestData.createdBy ?? null,
            latestTransactionId: purchaseId,
        }, { merge: true });
        await appendLineageEdge({
            tx,
            accountId: context.accountId,
            requestId: context.requestId,
            itemId,
            fromTransactionId: previousTxId,
            toTransactionId: purchaseId,
            createdBy: context.requestData.createdBy,
            movementKind: 'sold',
            source: 'server',
            note: note ?? null,
            fromProjectId: sourceProjectId,
            toProjectId: targetProjectId,
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
async function processRequestDoc(context) {
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
    }
    catch (error) {
        const message = error instanceof Error ? error.message : 'Unknown error.';
        await setRequestFailed(requestRef, 'handler_error', message);
    }
}
exports.onAccountRequestCreated = (0, firestore_2.onDocumentCreated)('accounts/{accountId}/requests/{requestId}', async (event) => {
    const requestRef = event.data?.ref;
    const requestData = event.data?.data();
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
});
/**
 * Append an association lineage edge whenever an item's transactionId changes.
 * This captures client-direct linking/unlinking and also complements request-doc operations.
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
            id: associationEdgeId,
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
                    id: returnedEdgeId,
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
exports.onProjectRequestCreated = (0, firestore_2.onDocumentCreated)('accounts/{accountId}/projects/{projectId}/requests/{requestId}', async (event) => {
    const requestRef = event.data?.ref;
    const requestData = event.data?.data();
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
});
exports.onInventoryRequestCreated = (0, firestore_2.onDocumentCreated)('accounts/{accountId}/inventory/requests/{requestId}', async (event) => {
    const requestRef = event.data?.ref;
    const requestData = event.data?.data();
    if (!requestRef) {
        return;
    }
    await processRequestDoc({
        requestRef,
        requestData: requestData ?? { status: 'failed', type: 'unknown' },
        accountId: event.params.accountId,
        requestId: event.params.requestId
    });
});
const BUDGET_CATEGORY_PRESET_SEED = [
    {
        id: 'seed_furnishings',
        name: 'Furnishings',
        slug: 'furnishings',
        order: 0,
        metadata: { categoryType: 'itemized', excludeFromOverallBudget: false },
    },
    {
        id: 'seed_design_fee',
        name: 'Design Fee',
        slug: 'design-fee',
        order: 1,
        metadata: { categoryType: 'fee', excludeFromOverallBudget: false },
    },
];
async function ensureBudgetCategoryPresetsSeeded(params) {
    const { accountId, createdBy } = params;
    const db = (0, firestore_1.getFirestore)();
    const now = firestore_1.FieldValue.serverTimestamp();
    const collectionRef = db.collection(`accounts/${accountId}/presets/default/budgetCategories`);
    await db.runTransaction(async (tx) => {
        // Fast path: if Furnishings exists, ensure it's usable (not archived) and exit.
        const existingFurnishings = await tx.get(collectionRef.where('name', '==', 'Furnishings').limit(1));
        if (!existingFurnishings.empty) {
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
        // Seed minimal required set (currently just Furnishings) in an idempotent way.
        for (const seed of BUDGET_CATEGORY_PRESET_SEED) {
            const seedRef = collectionRef.doc(seed.id);
            const seedSnap = await tx.get(seedRef);
            if (seedSnap.exists)
                continue;
            tx.set(seedRef, {
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
exports.createAccount = (0, https_1.onCall)(async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
        throw new https_1.HttpsError('unauthenticated', 'Must be signed in.');
    }
    const rawName = request.data?.name;
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
            joinedAt: now
        }, { merge: false });
    });
    // Bootstrap required presets before returning, to avoid downstream UI/code relying on missing seeds.
    await ensureBudgetCategoryPresetsSeeded({ accountId, createdBy: uid });
    return { accountId, role: 'owner', name };
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
exports.acceptInvite = (0, https_1.onCall)(async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
        throw new https_1.HttpsError('unauthenticated', 'Must be signed in to accept an invitation.');
    }
    const { token } = request.data ?? {};
    if (!token || typeof token !== 'string' || !token.trim()) {
        throw new https_1.HttpsError('invalid-argument', 'Invitation token is required.');
    }
    const db = (0, firestore_1.getFirestore)();
    const now = firestore_1.FieldValue.serverTimestamp();
    // Find the invite by token
    // Note: In a real implementation, you might hash the token or use a different lookup strategy.
    // For now, we'll search invites collections. This assumes tokens are stored as invite IDs or in a token field.
    // A production implementation should optimize this lookup (e.g., token -> inviteId mapping doc).
    let inviteRef = null;
    let accountId = null;
    let inviteData = null;
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
            throw new https_1.HttpsError('not-found', 'Invalid or expired invitation link.');
        }
    }
    else {
        const inviteDoc = accountsSnapshot.docs[0];
        inviteRef = inviteDoc.ref;
        inviteData = inviteDoc.data();
        // Extract accountId from path: accounts/{accountId}/invites/{inviteId}
        const pathParts = inviteDoc.ref.path.split('/');
        accountId = pathParts[1];
    }
    if (!accountId || !inviteRef || !inviteData) {
        throw new https_1.HttpsError('not-found', 'Invalid or expired invitation link.');
    }
    // Validate invite status and expiration
    const status = inviteData.status;
    const expiresAt = inviteData.expiresAt;
    const acceptedAt = inviteData.acceptedAt;
    const acceptedByUid = inviteData.acceptedByUid;
    if (status === 'accepted' || acceptedAt) {
        // Idempotent: if already accepted by this user, return success
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
    const role = inviteData.role || 'user';
    // Check entitlements (e.g., free tier user limits)
    // For MVP, we'll skip entitlement checks, but this is where you'd add them
    // Example: check account user count against plan limits
    // Create/update account user membership in a transaction
    const userRef = db.doc(`accounts/${accountId}/users/${uid}`);
    const result = await db.runTransaction(async (tx) => {
        // Re-check invite status in transaction
        const inviteSnap = await tx.get(inviteRef);
        if (!inviteSnap.exists) {
            throw new https_1.HttpsError('not-found', 'Invitation no longer exists.');
        }
        const currentInviteData = inviteSnap.data();
        if (currentInviteData?.acceptedAt) {
            // Idempotent: already accepted
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
        // Check if user already exists (idempotent)
        const userSnap = await tx.get(userRef);
        const userExists = userSnap.exists;
        // Create or update account user doc
        tx.set(userRef, {
            uid,
            role,
            joinedAt: userExists ? userSnap.data()?.joinedAt : now,
            joinedBy: userExists ? userSnap.data()?.joinedBy : inviteData.createdBy || null,
            updatedAt: now,
        }, { merge: true });
        // Mark invite as accepted
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
    // Ensure required presets exist for newly joined members (idempotent).
    await ensureBudgetCategoryPresetsSeeded({ accountId, createdBy: uid });
    return result;
});
//# sourceMappingURL=index.js.map