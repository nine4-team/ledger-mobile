/**
 * Health check tests
 *
 * Note: These are basic unit tests. Manual testing is required to verify
 * actual Firebase connectivity and emulator compatibility.
 */

import { checkFirebaseHealth, resetHealthCheckState } from '../healthCheck';

// Mock Firebase
jest.mock('../../firebase/firebase', () => ({
  db: {
    doc: jest.fn(() => ({
      get: jest.fn(),
    })),
  },
  isFirebaseConfigured: true,
}));

describe('healthCheck', () => {
  beforeEach(() => {
    resetHealthCheckState();
    jest.clearAllMocks();
  });

  it('should return true for successful health check', async () => {
    const { db } = require('../../firebase/firebase');
    db.doc().get.mockResolvedValue({});

    const result = await checkFirebaseHealth();
    expect(result).toBe(true);
  });

  it('should return false for network errors', async () => {
    const { db } = require('../../firebase/firebase');
    db.doc().get.mockRejectedValue(new Error('Network error'));

    const result = await checkFirebaseHealth();
    expect(result).toBe(false);
  });

  it('should return true for not-found errors (server responded)', async () => {
    const { db } = require('../../firebase/firebase');
    const error = new Error('Not found');
    (error as any).code = 'firestore/not-found';
    db.doc().get.mockRejectedValue(error);

    const result = await checkFirebaseHealth();
    expect(result).toBe(true);
  });

  it('should return true for permission-denied errors (server responded)', async () => {
    const { db } = require('../../firebase/firebase');
    const error = new Error('Permission denied');
    (error as any).code = 'firestore/permission-denied';
    db.doc().get.mockRejectedValue(error);

    const result = await checkFirebaseHealth();
    expect(result).toBe(true);
  });

  it('should cache results within rate limit period', async () => {
    const { db } = require('../../firebase/firebase');
    db.doc().get.mockResolvedValue({});

    // First call
    const result1 = await checkFirebaseHealth();
    expect(result1).toBe(true);
    expect(db.doc).toHaveBeenCalledTimes(1);

    // Second call within rate limit (should use cache)
    const result2 = await checkFirebaseHealth();
    expect(result2).toBe(true);
    expect(db.doc).toHaveBeenCalledTimes(1); // Not called again
  });

  it('should handle timeout', async () => {
    const { db } = require('../../firebase/firebase');
    // Simulate a slow request that will timeout
    db.doc().get.mockImplementation(
      () => new Promise((resolve) => setTimeout(resolve, 10000))
    );

    const result = await checkFirebaseHealth();
    expect(result).toBe(false);
  });
});
