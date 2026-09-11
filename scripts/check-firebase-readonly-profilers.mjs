#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const PROFILE_SOURCES = [
  "scripts/lib/firebase-readonly-profile.mjs",
  "scripts/profile-firebase-firestore-auth-readonly.mjs",
  "scripts/profile-firebase-storage-readonly.mjs",
];
const FORBIDDEN = [
  [/\b(?:db|doc|document|documentRef|collection|collectionRef|ref|batch|transaction|auth|bucket|file)\.(?:set|add|update|delete|create|commit)\s*\(/, "Firebase write method"],
  [/\b(?:runTransaction|bulkWriter|createUser|updateUser|deleteUser|revokeRefreshTokens)\s*\(/, "Firestore/Auth write API"],
  [/\.(?:save|upload|copy|move|setMetadata|makePublic|makePrivate)\s*\(/, "Storage write API"],
  [/\b(?:WriteBatch|BulkWriter)\b/, "write-only Firebase type"],
];

const errors = [];
for (const sourcePath of PROFILE_SOURCES) {
  const absolutePath = path.join(ROOT, sourcePath);
  if (!fs.existsSync(absolutePath)) {
    errors.push(`${sourcePath}: missing`);
    continue;
  }
  const source = fs.readFileSync(absolutePath, "utf8");
  for (const [pattern, label] of FORBIDDEN) {
    if (pattern.test(source)) errors.push(`${sourcePath}: contains forbidden ${label}`);
  }
  if (sourcePath.startsWith("scripts/profile-") && !source.includes("--execute-read-only")) {
    errors.push(`${sourcePath}: lacks explicit execution gate`);
  }
  if (
    sourcePath.startsWith("scripts/profile-") &&
    (!source.includes("READ_ONLY:ledger-nine4:") || !source.includes("parseArgs"))
  ) {
    errors.push(`${sourcePath}: lacks exact confirmation token wiring`);
  }
}

if (errors.length > 0) {
  console.error(errors.join("\n"));
  process.exitCode = 1;
} else {
  console.log("Firebase source profilers contain no recognized mutation APIs and retain execution gates.");
}
