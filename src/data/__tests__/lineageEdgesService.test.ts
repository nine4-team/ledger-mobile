// Mock Firebase dependencies so importing lineageEdgesService doesn't fail
jest.mock('../../firebase/firebase', () => ({
  db: null,
  auth: null,
  isFirebaseConfigured: false,
}));
jest.mock('@react-native-firebase/firestore', () => ({
  collection: jest.fn(),
  doc: jest.fn(),
  getDocsFromCache: jest.fn(),
  onSnapshot: jest.fn(),
  query: jest.fn(),
  setDoc: jest.fn(),
  where: jest.fn(),
  serverTimestamp: jest.fn(),
  orderBy: jest.fn(),
}));
jest.mock('../../sync/pendingWrites', () => ({
  trackPendingWrite: jest.fn(),
}));

import { normalizeEdgeFromFirestore } from '../lineageEdgesService';

// ---------------------------------------------------------------------------
// normalizeEdgeFromFirestore
// ---------------------------------------------------------------------------

describe('normalizeEdgeFromFirestore', () => {
  it('handles undefined raw data - returns defaults with id', () => {
    const result = normalizeEdgeFromFirestore(undefined, 'edge-1');
    expect(result.id).toBe('edge-1');
    expect(result.fromTransactionId).toBeNull();
    expect(result.toTransactionId).toBeNull();
    expect(result.movementKind).toBe('association');
    expect(result.source).toBe('server');
  });

  it('handles null raw data - returns defaults with id', () => {
    const result = normalizeEdgeFromFirestore(null, 'edge-2');
    expect(result.id).toBe('edge-2');
    expect(result.fromTransactionId).toBeNull();
    expect(result.toTransactionId).toBeNull();
    expect(result.movementKind).toBe('association');
    expect(result.source).toBe('server');
  });

  it('handles missing movementKind - defaults to association', () => {
    const raw = {
      accountId: 'acc-1',
      itemId: 'item-1',
      fromTransactionId: 'txn-1',
      toTransactionId: 'txn-2',
      source: 'app',
    };
    const result = normalizeEdgeFromFirestore(raw, 'edge-3');
    expect(result.movementKind).toBe('association');
  });

  it('handles missing source - defaults to server', () => {
    const raw = {
      accountId: 'acc-1',
      itemId: 'item-1',
      fromTransactionId: 'txn-1',
      toTransactionId: 'txn-2',
      movementKind: 'sold',
    };
    const result = normalizeEdgeFromFirestore(raw, 'edge-4');
    expect(result.source).toBe('server');
  });

  it('preserves all fields when present', () => {
    const raw = {
      accountId: 'acc-1',
      itemId: 'item-1',
      fromTransactionId: 'txn-from',
      toTransactionId: 'txn-to',
      movementKind: 'sold',
      source: 'app',
      createdAt: { seconds: 1000, nanoseconds: 0 },
      createdBy: 'user-1',
      note: 'test note',
      fromProjectId: 'proj-1',
      toProjectId: 'proj-2',
    };
    const result = normalizeEdgeFromFirestore(raw, 'edge-5');
    expect(result).toEqual({
      accountId: 'acc-1',
      itemId: 'item-1',
      fromTransactionId: 'txn-from',
      toTransactionId: 'txn-to',
      movementKind: 'sold',
      source: 'app',
      createdAt: { seconds: 1000, nanoseconds: 0 },
      createdBy: 'user-1',
      note: 'test note',
      fromProjectId: 'proj-1',
      toProjectId: 'proj-2',
      id: 'edge-5',
    });
  });

  it('sets fromTransactionId to null when missing', () => {
    const raw = {
      accountId: 'acc-1',
      itemId: 'item-1',
      toTransactionId: 'txn-to',
      movementKind: 'returned',
      source: 'migration',
    };
    const result = normalizeEdgeFromFirestore(raw, 'edge-6');
    expect(result.fromTransactionId).toBeNull();
  });

  it('sets toTransactionId to null when missing', () => {
    const raw = {
      accountId: 'acc-1',
      itemId: 'item-1',
      fromTransactionId: 'txn-from',
      movementKind: 'correction',
      source: 'app',
    };
    const result = normalizeEdgeFromFirestore(raw, 'edge-7');
    expect(result.toTransactionId).toBeNull();
  });

  it('handles empty object raw data', () => {
    const result = normalizeEdgeFromFirestore({}, 'edge-8');
    expect(result.id).toBe('edge-8');
    expect(result.fromTransactionId).toBeNull();
    expect(result.toTransactionId).toBeNull();
    expect(result.movementKind).toBe('association');
    expect(result.source).toBe('server');
  });
});
