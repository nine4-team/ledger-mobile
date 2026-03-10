import admin from "firebase-admin";
import type { Firestore } from "firebase-admin/firestore";

export function initFirebase(): Firestore {
  const firestoreEmulatorHost = process.env.FIRESTORE_EMULATOR_HOST;
  const projectId = process.env.FIREBASE_PROJECT_ID || "ledger-nine4";

  if (firestoreEmulatorHost) {
    console.error(
      `[ledger-mcp] Connecting to Firestore emulator at ${firestoreEmulatorHost}`
    );
  } else {
    console.error("[ledger-mcp] Connecting to production Firestore");
  }

  if (!admin.apps.length) {
    if (firestoreEmulatorHost) {
      // Emulator mode — no real credentials needed
      process.env.FIRESTORE_EMULATOR_HOST = firestoreEmulatorHost;
      admin.initializeApp({ projectId });
    } else {
      // Production mode — use ADC or service account
      admin.initializeApp({
        credential: admin.credential.applicationDefault(),
        projectId,
      });
    }
  }

  return admin.firestore();
}
