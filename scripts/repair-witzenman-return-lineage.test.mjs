import test from 'node:test';
import assert from 'node:assert/strict';
import { analyze } from './repair-witzenman-return-lineage.mjs';

test('repair analysis preserves all 22 sold items, including one newer edge', () => {
  const projectId = 'project-witzenman';
  const originalReturnId = 'original-return';
  const consolidatedReturnId = 'CONSOLIDATED_project-witzenman_outbound_return';
  const backup = {
    transactions: [{
      id: originalReturnId,
      path: `accounts/a/transactions/${originalReturnId}`,
      data: { type: 'Return', projectId, itemIds: Array.from({ length: 22 }, (_, i) => `item-${i + 1}`) },
    }],
    lineageEdges: Array.from({ length: 21 }, (_, i) => ({
      id: `edge-${i + 1}`,
      path: `accounts/a/lineageEdges/edge-${i + 1}`,
      data: {
        itemId: `item-${i + 1}`,
        fromTransactionId: originalReturnId,
        toTransactionId: `destination-${i + 1}`,
        toProjectId: 'other-project',
        movementKind: 'sold',
      },
    })),
  };
  const live = {
    transactions: [{
      id: consolidatedReturnId,
      path: `accounts/a/transactions/${consolidatedReturnId}`,
      data: { type: 'Return', projectId, itemIds: [], consolidationDirection: 'outbound' },
    }],
    lineageEdges: Array.from({ length: 22 }, (_, i) => ({
      id: `edge-${i + 1}`,
      path: `accounts/a/lineageEdges/edge-${i + 1}`,
      data: {
        itemId: `item-${i + 1}`,
        fromTransactionId: consolidatedReturnId,
        toTransactionId: `destination-${i + 1}`,
        toProjectId: 'other-project',
        movementKind: 'sold',
      },
    })),
  };

  const manifest = analyze({ backup, live, accountId: 'account', projectId });
  assert.equal(manifest.originalSaleCandidateCount, 21);
  assert.equal(manifest.currentInvalidSaleEdgeCount, 22);
  assert.equal(manifest.operations.length, 22);
  assert.equal(manifest.blockers.length, 0);
  assert.equal(manifest.operations.filter((op) => op.evidence === 'original-backup').length, 21);
  assert.equal(manifest.operations.filter((op) => op.evidence === 'live-post-consolidation').length, 1);
  assert.ok(manifest.operations.every((op) => op.after.fromTransactionId === null));
  assert.ok(manifest.operations.every((op) => op.after.toProjectId === 'other-project'));
});
