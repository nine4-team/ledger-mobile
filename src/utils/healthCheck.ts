/**
 * App-specific health check for Firebase connectivity.
 *
 * Per OFFLINE_CAPABILITY_SPEC.md lines 111-127:
 * - Cheap: single lightweight Firestore read
 * - Rate-limited: max once per 30 seconds
 * - Non-blocking: async, never delays UI render
 * - Environment-aware: works with emulators when enabled
 *
 * Implementation: Firestore Ping (Option A)
 * - Reads a known lightweight doc from Firestore (health/ping)
 * - Uses server-preferring read to test actual backend connectivity
 * - Falls back gracefully if doc doesn't exist (still tests connectivity)
 */

import { db, isFirebaseConfigured } from '../firebase/firebase';

/**
 * Configuration
 */
const HEALTH_CHECK_TIMEOUT_MS = 5_000; // 5 seconds max
const RATE_LIMIT_MS = 30_000; // 30 seconds between checks
const HEALTH_DOC_PATH = 'health/ping'; // Public readable doc

/**
 * Rate limiting state
 */
let lastHealthCheckTime = 0;
let lastHealthCheckResult: boolean | null = null;

/**
 * Performs an app-specific health check to verify Firebase connectivity.
 *
 * Returns:
 * - true: Firebase is reachable and healthy
 * - false: Firebase is unreachable or unhealthy
 *
 * Rate limiting:
 * - If called within RATE_LIMIT_MS of last check, returns cached result
 * - This prevents spamming Firebase with health check requests
 *
 * Error handling:
 * - All errors are caught and return false (unhealthy)
 * - Never throws exceptions
 * - Includes timeout protection
 */
export async function checkFirebaseHealth(): Promise<boolean> {
  // If Firebase is not configured (e.g., bypassed auth), assume healthy
  // This prevents false negatives during development
  if (!isFirebaseConfigured || !db) {
    return true;
  }

  // Rate limiting: return cached result if within rate limit period
  const now = Date.now();
  if (now - lastHealthCheckTime < RATE_LIMIT_MS && lastHealthCheckResult !== null) {
    return lastHealthCheckResult;
  }

  try {
    // Perform health check with timeout
    const result = await Promise.race([
      performHealthCheck(),
      createTimeout(HEALTH_CHECK_TIMEOUT_MS),
    ]);

    // Update rate limiting state
    lastHealthCheckTime = now;
    lastHealthCheckResult = result;

    return result;
  } catch (error) {
    // All errors are treated as unhealthy
    // This includes timeouts, network errors, permission errors, etc.
    console.warn('[healthCheck] Health check failed:', error);

    lastHealthCheckTime = now;
    lastHealthCheckResult = false;

    return false;
  }
}

/**
 * Performs the actual health check by reading a known doc from Firestore.
 *
 * Strategy:
 * - Attempts to read health/ping doc from server (not cache)
 * - Uses getOptions: { source: 'server' } to force server fetch
 * - Doc existence doesn't matter - we're testing connectivity
 * - Success = Firebase is reachable
 * - Failure = Firebase is unreachable
 */
async function performHealthCheck(): Promise<boolean> {
  if (!db) {
    return false;
  }

  try {
    // Attempt to read health doc from server
    // Note: Using native SDK syntax (@react-native-firebase/firestore)
    const docRef = db.doc(HEALTH_DOC_PATH);

    // Force server fetch (not cache)
    // This tests actual backend connectivity
    await docRef.get({
      source: 'server', // Explicitly fetch from server, not cache
    });

    // Success: We reached Firestore
    // Document existence doesn't matter - connectivity test succeeded
    return true;
  } catch (error) {
    // Differentiate between expected "not found" (healthy) vs connectivity issues (unhealthy)
    // If we got a response from server (even 404), that's healthy
    // Only network/timeout errors indicate unhealthy state

    // @react-native-firebase/firestore error codes
    const code = (error as { code?: string })?.code;

    if (code === 'firestore/not-found' || code === 'firestore/permission-denied') {
      // We got a server response (even if negative) - connectivity is OK
      return true;
    }

    // Network error, timeout, or other connectivity issue
    return false;
  }
}

/**
 * Creates a promise that rejects after the specified timeout.
 * Used for timeout protection on health checks.
 */
function createTimeout(ms: number): Promise<boolean> {
  return new Promise((_, reject) => {
    setTimeout(() => {
      reject(new Error('Health check timeout'));
    }, ms);
  });
}

/**
 * Resets the health check rate limiting state.
 * Useful for testing or forcing an immediate health check.
 *
 * NOT recommended for production use - respect rate limits!
 */
export function resetHealthCheckState(): void {
  lastHealthCheckTime = 0;
  lastHealthCheckResult = null;
}
