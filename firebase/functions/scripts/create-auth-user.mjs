#!/usr/bin/env node
/**
 * Create a user in Firebase Auth Emulator.
 *
 * Usage:
 *   node firebase/functions/scripts/create-auth-user.mjs <email> <password> <uid>
 */

import admin from 'firebase-admin';

const args = process.argv.slice(2);
if (args.length < 3) {
  console.error('Usage: node create-auth-user.mjs <email> <password> <uid>');
  process.exit(1);
}

const [email, password, uid] = args;
const projectId = process.env.FIREBASE_PROJECT_ID || 'demo-ledger';
const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST || 'localhost:9099';

process.env.FIREBASE_AUTH_EMULATOR_HOST = authHost;

admin.initializeApp({ projectId });

async function main() {
  try {
    try {
      await admin.auth().deleteUser(uid);
      console.log(`Deleted existing user ${uid}`);
    } catch (e) {
      // ignore
    }

    const user = await admin.auth().createUser({
      uid,
      email,
      password,
      emailVerified: true,
    });
    console.log(`Created user: ${user.email} (${user.uid})`);
  } catch (error) {
    console.error('Error creating user:', error);
    process.exit(1);
  }
}

main();
