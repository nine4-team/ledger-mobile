#!/usr/bin/env node
/**
 * dev-native.mjs — One-command native dev workflow.
 *
 * Usage: npm run dev:native
 *
 * Full native dev workflow:
 * 1. Starts Firebase emulators with persistence
 * 2. Waits for Auth + Firestore to be ready
 * 3. Seeds Firestore, Storage, and creates the auth user
 * 4. Builds the SwiftUI app (LedgeriOS Emulator scheme)
 * 5. Boots the iPhone 16e simulator and launches the app
 */

import { spawn, spawnSync } from 'node:child_process';
import { setTimeout as sleep } from 'node:timers/promises';

const PROJECT_ID = 'ledger-nine4';
const AUTH_PORT = 9099;
const FIRESTORE_PORT = 8181;
const STORAGE_PORT = 9199;

const AUTH_USER_EMAIL = 'team@nine4.co';
const AUTH_USER_PASSWORD = 'password123';
const AUTH_USER_UID = '4ef35958-597c-4aea-b99e-1ef62352a72d';

const BUNDLE_PATH = 'docs/data_migrator/out/v1/bundle.json';
const MEDIA_MANIFEST_PATH = 'docs/data_migrator/out/v1/media-manifest.json';

// ─── Helpers ──────────────────────────────────────────────────────────────────

function log(msg) {
  console.log(`\x1b[36m[dev:native]\x1b[0m ${msg}`);
}

function logError(msg) {
  console.error(`\x1b[31m[dev:native]\x1b[0m ${msg}`);
}

async function waitForPort(name, port, maxMs = 45000) {
  const start = Date.now();
  while (Date.now() - start < maxMs) {
    try {
      await fetch(`http://localhost:${port}`, { signal: AbortSignal.timeout(1000) });
      log(`${name} ready on :${port}`);
      return;
    } catch {
      await sleep(500);
    }
  }
  throw new Error(`Timed out waiting for ${name} on :${port}`);
}

function run(cmd, args, extraEnv = {}) {
  const result = spawnSync(cmd, args, {
    stdio: 'inherit',
    env: { ...process.env, ...extraEnv },
  });
  if (result.status !== 0) {
    throw new Error(`Command failed: ${cmd} ${args.join(' ')} (exit ${result.status})`);
  }
}

// ─── Main ─────────────────────────────────────────────────────────────────────

async function main() {
  // Force emulator mode regardless of .env
  process.env.EXPO_PUBLIC_USE_FIREBASE_EMULATORS = 'true';

  // 1. Start emulators in background
  log('Starting Firebase emulators...');
  const emulatorProc = spawn(
    'firebase',
    ['emulators:start', '--import=./firebase-export', '--export-on-exit=./firebase-export'],
    { stdio: 'inherit', detached: false }
  );
  emulatorProc.on('error', (err) => {
    logError(`Emulator process error: ${err.message}`);
    process.exit(1);
  });

  // 2. Wait for Auth + Firestore
  log('Waiting for emulators to be ready...');
  try {
    await Promise.all([
      waitForPort('Auth', AUTH_PORT),
      waitForPort('Firestore', FIRESTORE_PORT),
    ]);
  } catch (err) {
    logError(err.message);
    emulatorProc.kill();
    process.exit(1);
  }

  // Give emulators a moment to finish internal init after ports open
  await sleep(3000);

  // 3. Seed Firestore
  log('Seeding Firestore...');
  try {
    run('node', [
      'firebase/functions/scripts/seed-firestore-emulator.mjs',
      BUNDLE_PATH,
      '--project', PROJECT_ID,
      '--firestore-host', 'localhost',
      '--firestore-port', String(FIRESTORE_PORT),
    ], {
      FIRESTORE_EMULATOR_HOST: `localhost:${FIRESTORE_PORT}`,
      FIREBASE_PROJECT_ID: PROJECT_ID,
    });
  } catch (err) {
    logError(`Firestore seed failed: ${err.message}`);
  }

  // 3b. Backfill budget summaries (seed uses bulkWriter which bypasses triggers)
  log('Backfilling budget summaries...');
  try {
    run('node', [
      'firebase/functions/scripts/backfill-budget-summaries.mjs',
    ], {
      FIRESTORE_EMULATOR_HOST: `localhost:${FIRESTORE_PORT}`,
      FIREBASE_PROJECT_ID: PROJECT_ID,
    });
  } catch (err) {
    logError(`Budget summary backfill failed: ${err.message}`);
  }

  // 4. Seed Storage
  log('Seeding Storage...');
  try {
    run('node', [
      'firebase/functions/scripts/seed-storage-emulator.mjs',
      MEDIA_MANIFEST_PATH,
      '--project', PROJECT_ID,
      '--storage-host', 'localhost',
      '--storage-port', String(STORAGE_PORT),
    ], {
      FIRESTORE_EMULATOR_HOST: `localhost:${FIRESTORE_PORT}`,
      FIREBASE_PROJECT_ID: PROJECT_ID,
      FIREBASE_STORAGE_EMULATOR_HOST: `localhost:${STORAGE_PORT}`,
    });
  } catch (err) {
    logError(`Storage seed failed: ${err.message}`);
  }

  // 5. Create auth user
  log(`Creating auth user ${AUTH_USER_EMAIL}...`);
  try {
    run('node', [
      'firebase/functions/scripts/create-auth-user.mjs',
      AUTH_USER_EMAIL,
      AUTH_USER_PASSWORD,
      AUTH_USER_UID,
    ], {
      FIREBASE_PROJECT_ID: PROJECT_ID,
      FIREBASE_AUTH_EMULATOR_HOST: `localhost:${AUTH_PORT}`,
    });
  } catch (err) {
    logError(`Auth user creation failed: ${err.message}`);
  }

  // 6. Build and launch SwiftUI app on simulator
  const SIMULATOR_NAME = 'iPhone 16e';
  const SCHEME = 'LedgeriOS (Emulator)';
  const BUNDLE_ID = 'apps.nine4.ledger';

  log(`Building ${SCHEME}...`);
  try {
    run('xcodebuild', [
      '-project', 'LedgeriOS/LedgeriOS.xcodeproj',
      '-scheme', SCHEME,
      '-destination', `platform=iOS Simulator,name=${SIMULATOR_NAME}`,
      '-derivedDataPath', 'LedgeriOS/DerivedData',
      'build',
    ]);
  } catch (err) {
    logError(`Build failed: ${err.message}`);
    emulatorProc.kill();
    process.exit(1);
  }

  // Boot simulator if needed
  log(`Booting ${SIMULATOR_NAME}...`);
  spawnSync('xcrun', ['simctl', 'boot', SIMULATOR_NAME], { stdio: 'ignore' }); // OK if already booted
  spawnSync('open', ['-a', 'Simulator']);

  // Install and launch
  const appPath = spawnSync('find', [
    'LedgeriOS/DerivedData/Build/Products/Debug-iphonesimulator',
    '-name', '*.app', '-maxdepth', '1',
  ], { encoding: 'utf8' }).stdout.trim();

  if (!appPath) {
    logError('Could not find built .app bundle');
    emulatorProc.kill();
    process.exit(1);
  }

  log('Installing app...');
  run('xcrun', ['simctl', 'install', 'booted', appPath]);

  log('Launching app...');
  run('xcrun', ['simctl', 'launch', 'booted', BUNDLE_ID], {
    SIMCTL_CHILD_USE_FIREBASE_EMULATORS: '1',
  });

  log('──────────────────────────────────────────');
  log('Sign in with: team@nine4.co / password123');
  log('──────────────────────────────────────────');
  log('App launched. Emulators running in foreground — Ctrl+C to stop.');

  // Keep process alive for emulators; forward Ctrl+C
  process.on('SIGINT', () => {
    emulatorProc.kill('SIGINT');
    process.exit(0);
  });
  process.on('SIGTERM', () => {
    emulatorProc.kill('SIGTERM');
    process.exit(0);
  });
}

main().catch((err) => {
  logError(err.message);
  process.exit(1);
});
