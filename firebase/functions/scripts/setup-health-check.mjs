#!/usr/bin/env node

/**
 * Setup script to create the health/ping document in Firestore.
 *
 * This document is used by the mobile app's health check to verify
 * Firebase connectivity (per OFFLINE_CAPABILITY_SPEC.md).
 *
 * Usage:
 *   node setup-health-check.mjs [--emulator]
 *
 * Options:
 *   --emulator  Use Firebase emulator (default: production)
 */

import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { readFileSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Parse command line arguments
const useEmulator = process.argv.includes('--emulator');

console.log(`Setting up health/ping document (${useEmulator ? 'emulator' : 'production'})...`);

// Initialize Firebase Admin
let app;
if (useEmulator) {
  // Emulator mode
  process.env.FIRESTORE_EMULATOR_HOST = 'localhost:8081';
  app = initializeApp({ projectId: 'demo-project' });
  console.log('Connected to Firestore emulator at localhost:8081');
} else {
  // Production mode
  const serviceAccountPath = join(__dirname, '..', 'service-account-key.json');
  try {
    const serviceAccount = JSON.parse(readFileSync(serviceAccountPath, 'utf8'));
    app = initializeApp({
      credential: cert(serviceAccount),
    });
    console.log('Connected to production Firestore');
  } catch (error) {
    console.error('Error: service-account-key.json not found.');
    console.error('For production, place your service account key at:');
    console.error(`  ${serviceAccountPath}`);
    process.exit(1);
  }
}

const db = getFirestore(app);

// Create health/ping document
async function setupHealthCheck() {
  try {
    const healthDoc = db.doc('health/ping');

    await healthDoc.set({
      status: 'ok',
      message: 'Health check endpoint',
      lastUpdated: new Date().toISOString(),
      version: '1.0',
    });

    console.log('✓ Successfully created health/ping document');
    console.log('  Path: health/ping');
    console.log('  Status: ok');

    // Verify by reading it back
    const snapshot = await healthDoc.get();
    if (snapshot.exists) {
      console.log('✓ Verified: Document is readable');
      console.log('  Data:', snapshot.data());
    } else {
      console.error('✗ Error: Document was not created');
      process.exit(1);
    }
  } catch (error) {
    console.error('✗ Error setting up health check:', error.message);
    process.exit(1);
  }
}

// Run setup
setupHealthCheck()
  .then(() => {
    console.log('\nHealth check setup complete!');
    console.log('\nNext steps:');
    console.log('  1. Deploy Firestore rules: firebase deploy --only firestore:rules');
    console.log('  2. Test health check from mobile app');
    process.exit(0);
  })
  .catch((error) => {
    console.error('Unexpected error:', error);
    process.exit(1);
  });
