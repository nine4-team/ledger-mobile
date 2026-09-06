import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import admin from "firebase-admin";

export const READ_ONLY_PROFILE_VERSION = 1;
export const EXPECTED_PROJECT = "ledger-nine4";
export const EXPECTED_ACCOUNT = "1dd4fd75-8eea-4f7a-98e7-bf45b987ae94";
export const EXPECTED_BUCKET = "ledger-nine4.firebasestorage.app";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const ALLOWED_OUTPUT_DIR = path.join(ROOT, "migration/out/source-profiles");

function fail(message) {
  throw new Error(`Refusing to run: ${message}`);
}

export function parseArgs(argv, { requireBucket = false } = {}) {
  const values = {};
  let executeReadOnly = false;
  let help = false;
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (token === "--execute-read-only") {
      executeReadOnly = true;
      continue;
    }
    if (token === "--help" || token === "-h") {
      help = true;
      continue;
    }
    if (!token.startsWith("--")) fail(`unexpected positional argument ${token}`);
    const name = token.slice(2);
    if (!["project", "account", "bucket", "credential-file", "output-dir", "confirm"].includes(name)) {
      fail(`unknown option ${token}`);
    }
    const value = argv[index + 1];
    if (!value || value.startsWith("--")) fail(`${token} requires a value`);
    values[name] = value;
    index += 1;
  }
  if (help) return { help: true };
  for (const required of ["project", "account", "credential-file", "output-dir"]) {
    if (!values[required]) fail(`--${required} is required even for preflight`);
  }
  if (requireBucket && !values.bucket) fail("--bucket is required");
  if (values.project !== EXPECTED_PROJECT) {
    fail(`project must be exactly ${EXPECTED_PROJECT}`);
  }
  if (values.account !== EXPECTED_ACCOUNT) {
    fail(`account must be exactly the reviewed 1584 Design account ${EXPECTED_ACCOUNT}`);
  }
  if (requireBucket && values.bucket !== EXPECTED_BUCKET) {
    fail(`bucket must be exactly ${EXPECTED_BUCKET}`);
  }
  for (const emulatorVariable of [
    "FIRESTORE_EMULATOR_HOST",
    "FIREBASE_AUTH_EMULATOR_HOST",
    "FIREBASE_STORAGE_EMULATOR_HOST",
  ]) {
    if (process.env[emulatorVariable]) fail(`${emulatorVariable} is set`);
  }
  const outputDir = path.resolve(values["output-dir"]);
  if (outputDir !== ALLOWED_OUTPUT_DIR) {
    fail(`--output-dir must resolve exactly to ${ALLOWED_OUTPUT_DIR}`);
  }
  const credentialFile = path.resolve(values["credential-file"]);
  if (!fs.existsSync(credentialFile) || !fs.statSync(credentialFile).isFile()) {
    fail("--credential-file must identify an existing regular file");
  }
  const relativeCredentialPath = path.relative(ROOT, credentialFile);
  if (!relativeCredentialPath.startsWith("..") && !path.isAbsolute(relativeCredentialPath)) {
    fail("credential file must not be stored inside the repository");
  }
  const credentialMode = fs.statSync(credentialFile).mode & 0o777;
  if ((credentialMode & 0o077) !== 0) {
    fail("credential file must not be readable or writable by group/other (use chmod 600)");
  }
  let credentialJson;
  try {
    credentialJson = JSON.parse(fs.readFileSync(credentialFile, "utf8"));
  } catch {
    fail("credential file is not valid JSON");
  }
  if (
    credentialJson.type !== "service_account" ||
    credentialJson.project_id !== EXPECTED_PROJECT ||
    typeof credentialJson.client_email !== "string" ||
    typeof credentialJson.private_key !== "string"
  ) {
    fail("credential must be a service-account key for the exact reviewed project");
  }
  const expectedConfirmation = `READ_ONLY:${EXPECTED_PROJECT}:${EXPECTED_ACCOUNT}`;
  if (executeReadOnly && values.confirm !== expectedConfirmation) {
    fail(`execution requires --confirm ${expectedConfirmation}`);
  }
  return {
    help: false,
    executeReadOnly,
    project: values.project,
    account: values.account,
    bucket: values.bucket,
    credentialFile,
    credentialJson,
    credentialIdentitySha256: crypto
      .createHash("sha256")
      .update(`${credentialJson.project_id}:${credentialJson.client_email}`)
      .digest("hex"),
    outputDir,
    expectedConfirmation,
  };
}

export function printPreflight(kind, args) {
  console.log(JSON.stringify({
    result: "preflight_passed_no_remote_calls",
    profileKind: kind,
    profileVersion: READ_ONLY_PROFILE_VERSION,
    target: {
      project: args.project,
      account: args.account,
      ...(args.bucket ? { bucket: args.bucket } : {}),
    },
    credentialIdentitySha256: args.credentialIdentitySha256,
    outputDir: args.outputDir,
    executeInstruction: `repeat with --execute-read-only --confirm ${args.expectedConfirmation}`,
  }, null, 2));
}

export function initializeReadOnlyFirebase(args) {
  const app = admin.initializeApp({
    credential: admin.credential.cert(args.credentialJson),
    projectId: args.project,
    ...(args.bucket ? { storageBucket: args.bucket } : {}),
  }, `readonly-profile-${process.pid}`);
  return {
    admin,
    db: app.firestore(),
    auth: app.auth(),
    bucket: args.bucket ? app.storage().bucket(args.bucket) : null,
  };
}

export function repositoryState() {
  let commit = "unknown";
  let dirty = true;
  try {
    commit = execFileSync("git", ["rev-parse", "HEAD"], {
      cwd: ROOT,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
    dirty = execFileSync("git", ["status", "--porcelain"], {
      cwd: ROOT,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim().length > 0;
  } catch {
    // Repository provenance is useful evidence, but inability to invoke git
    // must not change the read-only nature of the profiler.
  }
  return { commit, dirty };
}

export function sha256(value) {
  return crypto.createHash("sha256").update(value).digest("hex");
}

export function writeProfileArtifact(kind, args, result) {
  const generatedAt = new Date().toISOString();
  const payload = {
    schemaVersion: 1,
    profileVersion: READ_ONLY_PROFILE_VERSION,
    profileKind: kind,
    generatedAt,
    repository: repositoryState(),
    source: {
      project: args.project,
      account: args.account,
      ...(args.bucket ? { bucket: args.bucket } : {}),
      credentialIdentitySha256: args.credentialIdentitySha256,
    },
    redaction: {
      documentValues: "Only type shapes and allowlisted enum aggregates are emitted.",
      identifiers: "No document IDs, Auth UIDs, emails, object names, URLs, or hashes of object content are emitted.",
      media: "No object bytes are downloaded.",
    },
    result,
  };
  const payloadJson = `${JSON.stringify(payload, null, 2)}\n`;
  const payloadSha256 = sha256(payloadJson);
  const artifact = { ...payload, payloadSha256 };
  const artifactJson = `${JSON.stringify(artifact, null, 2)}\n`;
  const artifactSha256 = sha256(artifactJson);
  const stamp = generatedAt.replace(/[:.]/g, "-");
  const baseName = `${kind}-v${READ_ONLY_PROFILE_VERSION}-${stamp}-${artifactSha256.slice(0, 12)}`;
  fs.mkdirSync(args.outputDir, { recursive: true, mode: 0o700 });
  const artifactPath = path.join(args.outputDir, `${baseName}.json`);
  const checksumPath = `${artifactPath}.sha256`;
  fs.writeFileSync(artifactPath, artifactJson, { flag: "wx", mode: 0o600 });
  fs.writeFileSync(checksumPath, `${artifactSha256}  ${path.basename(artifactPath)}\n`, {
    flag: "wx",
    mode: 0o600,
  });
  return { artifactPath, checksumPath, artifactSha256, payloadSha256 };
}

export function typeSignature(value, adminNamespace) {
  if (value === null) return "null";
  if (value === undefined) return "undefined";
  if (value instanceof adminNamespace.firestore.Timestamp) return "timestamp";
  if (value instanceof adminNamespace.firestore.GeoPoint) return "geo_point";
  if (value instanceof adminNamespace.firestore.DocumentReference) return "document_reference";
  if (Buffer.isBuffer(value)) return "bytes";
  if (Array.isArray(value)) {
    const elementTypes = [...new Set(value.map((entry) => typeSignature(entry, adminNamespace)))].sort();
    return `array<${elementTypes.join("|") || "empty"}>`;
  }
  if (typeof value === "number") return Number.isInteger(value) ? "integer" : "number";
  if (typeof value === "object") return "map";
  return typeof value;
}

export function increment(object, key, amount = 1) {
  object[key] = (object[key] ?? 0) + amount;
}

export function sortedObject(object) {
  return Object.fromEntries(Object.entries(object).sort(([a], [b]) => a.localeCompare(b)));
}
