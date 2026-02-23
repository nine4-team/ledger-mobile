// Mock Firebase dependencies so importing requestDocs doesn't fail
jest.mock('../../firebase/firebase', () => ({
  db: null,
  auth: null,
  isFirebaseConfigured: false,
}));
jest.mock('@react-native-firebase/firestore', () => ({
  collection: jest.fn(),
  doc: jest.fn(),
  onSnapshot: jest.fn(),
  serverTimestamp: jest.fn(),
  setDoc: jest.fn(),
}));
jest.mock('../../sync/pendingWrites', () => ({
  trackPendingWrite: jest.fn(),
}));
jest.mock('../../sync/requestDocTracker', () => ({
  trackRequestDocPath: jest.fn(),
}));

import {
  getRequestCollectionPath,
  getRequestDocPath,
  parseRequestDocPath,
  generateRequestOpId,
} from '../requestDocs';

// ---------------------------------------------------------------------------
// getRequestCollectionPath
// ---------------------------------------------------------------------------

describe('getRequestCollectionPath', () => {
  it('returns account-scoped path', () => {
    expect(getRequestCollectionPath({ accountId: 'acc-1', scope: 'account' }))
      .toBe('accounts/acc-1/requests');
  });

  it('returns inventory-scoped path', () => {
    expect(getRequestCollectionPath({ accountId: 'acc-1', scope: 'inventory' }))
      .toBe('accounts/acc-1/inventory/requests');
  });

  it('returns project-scoped path', () => {
    expect(getRequestCollectionPath({ accountId: 'acc-1', projectId: 'proj-1' }))
      .toBe('accounts/acc-1/projects/proj-1/requests');
  });
});

// ---------------------------------------------------------------------------
// getRequestDocPath
// ---------------------------------------------------------------------------

describe('getRequestDocPath', () => {
  it('appends request ID to account-scoped collection', () => {
    expect(getRequestDocPath({ accountId: 'acc-1', scope: 'account' }, 'req-123'))
      .toBe('accounts/acc-1/requests/req-123');
  });

  it('appends request ID to project-scoped collection', () => {
    expect(getRequestDocPath({ accountId: 'acc-1', projectId: 'proj-1' }, 'req-456'))
      .toBe('accounts/acc-1/projects/proj-1/requests/req-456');
  });

  it('appends request ID to inventory-scoped collection', () => {
    expect(getRequestDocPath({ accountId: 'acc-1', scope: 'inventory' }, 'req-789'))
      .toBe('accounts/acc-1/inventory/requests/req-789');
  });
});

// ---------------------------------------------------------------------------
// parseRequestDocPath
// ---------------------------------------------------------------------------

describe('parseRequestDocPath', () => {
  it('parses account-scoped path', () => {
    expect(parseRequestDocPath('accounts/acc-1/requests/req-123'))
      .toEqual({ accountId: 'acc-1', scope: 'account' });
  });

  it('parses project-scoped path', () => {
    expect(parseRequestDocPath('accounts/acc-1/projects/proj-1/requests/req-456'))
      .toEqual({ accountId: 'acc-1', projectId: 'proj-1' });
  });

  it('parses inventory-scoped path', () => {
    expect(parseRequestDocPath('accounts/acc-1/inventory/requests/req-789'))
      .toEqual({ accountId: 'acc-1', scope: 'inventory' });
  });

  it('returns null for unrecognized path formats', () => {
    expect(parseRequestDocPath('some/random/path')).toBeNull();
    expect(parseRequestDocPath('')).toBeNull();
    expect(parseRequestDocPath('accounts')).toBeNull();
  });

  it('handles leading/trailing whitespace', () => {
    expect(parseRequestDocPath('  accounts/acc-1/requests/req-123  '))
      .toEqual({ accountId: 'acc-1', scope: 'account' });
  });

  it('does not match paths with extra segments', () => {
    expect(parseRequestDocPath('accounts/acc-1/requests/req-123/extra')).toBeNull();
  });

  it('roundtrips with getRequestDocPath for all scope types', () => {
    const scopes = [
      { accountId: 'acc-1', scope: 'account' as const },
      { accountId: 'acc-1', scope: 'inventory' as const },
      { accountId: 'acc-1', projectId: 'proj-1' },
    ];

    for (const scope of scopes) {
      const path = getRequestDocPath(scope, 'req-roundtrip');
      const parsed = parseRequestDocPath(path);
      expect(parsed).toEqual(scope);
    }
  });
});

// ---------------------------------------------------------------------------
// generateRequestOpId
// ---------------------------------------------------------------------------

describe('generateRequestOpId', () => {
  it('returns a non-empty string', () => {
    const id = generateRequestOpId();
    expect(typeof id).toBe('string');
    expect(id.length).toBeGreaterThan(0);
  });

  it('returns unique values on successive calls', () => {
    const ids = new Set(Array.from({ length: 100 }, () => generateRequestOpId()));
    expect(ids.size).toBe(100);
  });
});
