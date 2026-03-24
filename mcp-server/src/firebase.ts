import admin from "firebase-admin";
import type { Firestore } from "firebase-admin/firestore";

export function initFirebase(credentialsPath?: string): Firestore {
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
      // Production mode
      const credPath = credentialsPath || process.env.GOOGLE_APPLICATION_CREDENTIALS;
      if (credPath) {
        // Explicit cert() bypasses ADC chain — immune to RAPT re-auth
        const fs = require("fs");
        const serviceAccount = JSON.parse(fs.readFileSync(credPath, "utf8"));
        console.error(`[ledger-mcp] Using service account: ${serviceAccount.client_email}`);
        admin.initializeApp({
          credential: admin.credential.cert(serviceAccount),
          projectId,
        });
      } else {
        // Fallback to ADC for Cloud Run (uses instance identity)
        admin.initializeApp({
          credential: admin.credential.applicationDefault(),
          projectId,
        });
      }
    }
  }

  return admin.firestore();
}
