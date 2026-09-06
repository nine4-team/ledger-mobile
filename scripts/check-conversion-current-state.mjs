import { execFileSync } from "node:child_process";
import { readFileSync, statSync } from "node:fs";
import { dirname, isAbsolute, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const repositoryRoot = resolve(scriptDirectory, "..");
const stateRelativePath =
  "docs/plans/ledger-accounting-redesign/conversion/current-execution-state.json";
const statePath = join(repositoryRoot, stateRelativePath);
const maximumBytes = 12_000;
const errors = [];

function requireCondition(condition, message) {
  if (!condition) errors.push(message);
}

function requireNonEmptyString(value, field) {
  requireCondition(
    typeof value === "string" && value.trim().length > 0,
    `${field} must be a non-empty string.`,
  );
}

function requireRepositoryPath(value, field) {
  requireNonEmptyString(value, field);
  if (typeof value !== "string" || value.length === 0) return;
  requireCondition(!isAbsolute(value), `${field} must be repository-relative.`);
  const resolved = resolve(repositoryRoot, value);
  requireCondition(
    relative(repositoryRoot, resolved) !== "" &&
      !relative(repositoryRoot, resolved).startsWith(".."),
    `${field} must remain inside the repository.`,
  );
  try {
    statSync(resolved);
  } catch {
    errors.push(`${field} does not exist: ${value}`);
  }
}

let state;
try {
  const bytes = statSync(statePath).size;
  requireCondition(
    bytes <= maximumBytes,
    `${stateRelativePath} is ${bytes} bytes; compact resume state must remain at or below ${maximumBytes} bytes.`,
  );
  state = JSON.parse(readFileSync(statePath, "utf8"));
} catch (error) {
  errors.push(`Unable to read valid ${stateRelativePath}: ${error.message}`);
}

if (state) {
  requireCondition(state.schemaVersion === 1, "schemaVersion must equal 1.");
  requireCondition(
    Number.isInteger(state.stateVersion) && state.stateVersion > 0,
    "stateVersion must be a positive integer.",
  );
  requireCondition(
    /^\d{4}-\d{2}-\d{2}$/.test(state.updatedAt ?? ""),
    "updatedAt must be an ISO calendar date.",
  );
  requireCondition(
    state.branch === "codex/supabase-powersync-implementation",
    "branch must remain the dedicated Supabase integration branch.",
  );
  requireCondition(
    state.worktree === "/Users/benjaminmackenzie/Dev/ledger_mobile_supabase",
    "worktree must remain the dedicated Supabase worktree.",
  );
  requireRepositoryPath(state.historyFile, "historyFile");
  requireRepositoryPath(state.method?.path, "method.path");
  requireCondition(
    Number.isInteger(state.method?.version) && state.method.version > 0,
    "method.version must be a positive integer.",
  );

  const checkpoint = state.verifiedCheckpoint ?? {};
  requireNonEmptyString(checkpoint.name, "verifiedCheckpoint.name");
  requireCondition(
    /^[0-9a-f]{40}$/.test(checkpoint.commit ?? ""),
    "verifiedCheckpoint.commit must be a full Git commit ID.",
  );
  requireCondition(
    Number.isInteger(checkpoint.ciRun) && checkpoint.ciRun > 0,
    "verifiedCheckpoint.ciRun must be a positive immutable CI run ID.",
  );
  requireCondition(
    checkpoint.ciStatus === "passed",
    "verifiedCheckpoint.ciStatus must describe a passed checkpoint.",
  );
  if (/^[0-9a-f]{40}$/.test(checkpoint.commit ?? "")) {
    try {
      execFileSync("git", ["cat-file", "-e", `${checkpoint.commit}^{commit}`], {
        cwd: repositoryRoot,
        stdio: "ignore",
      });
      execFileSync("git", ["merge-base", "--is-ancestor", checkpoint.commit, "HEAD"], {
        cwd: repositoryRoot,
        stdio: "ignore",
      });
    } catch {
      errors.push(
        "verifiedCheckpoint.commit must exist and be an ancestor of the current HEAD.",
      );
    }
  }

  const activeBatch = state.activeBatch ?? {};
  requireNonEmptyString(activeBatch.id, "activeBatch.id");
  requireCondition(
    [
      "ready",
      "implementation",
      "implementation_review",
      "local_verification",
      "ci_verification",
      "rehearsal",
      "blocked",
    ].includes(activeBatch.status),
    "activeBatch.status is not an allowed active state.",
  );
  requireNonEmptyString(activeBatch.outcome, "activeBatch.outcome");
  requireCondition(
    Array.isArray(activeBatch.dossiers) && activeBatch.dossiers.length > 0,
    "activeBatch.dossiers must identify at least one dossier.",
  );
  for (const [index, path] of (activeBatch.dossiers ?? []).entries()) {
    requireRepositoryPath(path, `activeBatch.dossiers[${index}]`);
  }
  requireCondition(
    Array.isArray(activeBatch.allowedPaths) && activeBatch.allowedPaths.length > 0,
    "activeBatch.allowedPaths must define the exact implementation boundary.",
  );
  for (const [index, path] of (activeBatch.allowedPaths ?? []).entries()) {
    requireRepositoryPath(path, `activeBatch.allowedPaths[${index}]`);
  }
  requireCondition(
    new Set(activeBatch.allowedPaths ?? []).size ===
      (activeBatch.allowedPaths ?? []).length,
    "activeBatch.allowedPaths must not contain duplicates.",
  );
  requireCondition(
    Array.isArray(activeBatch.nextActions) &&
      activeBatch.nextActions.length >= 1 &&
      activeBatch.nextActions.length <= 5,
    "activeBatch.nextActions must contain one to five concrete actions.",
  );

  const progress = state.progress ?? {};
  const progressIntegers = [
    "targetRelevantSurfaces",
    "mappedOrLaterSurfaces",
    "implementedOrLaterSurfaces",
    "locallyWorkingProviderWorkflows",
    "hostedAuthenticatedRehearsals",
    "cutoverReadyWorkflows",
  ];
  for (const field of progressIntegers) {
    requireCondition(
      Number.isInteger(progress[field]) && progress[field] >= 0,
      `progress.${field} must be a non-negative integer.`,
    );
  }
  requireCondition(
    progress.implementedOrLaterSurfaces <= progress.mappedOrLaterSurfaces &&
      progress.mappedOrLaterSurfaces <= progress.targetRelevantSurfaces,
    "Progress surface counts must satisfy implemented <= mapped <= target relevant.",
  );
  const estimate = progress.practicalCompletionEstimatePercent ?? {};
  requireCondition(
    estimate.low <= estimate.center &&
      estimate.center <= estimate.high &&
      estimate.low >= 0 &&
      estimate.high <= 100,
    "Practical completion estimate must satisfy 0 <= low <= center <= high <= 100.",
  );

  const efficiency = state.efficiency ?? {};
  requireCondition(
    efficiency.measurementUnit === "verified end-to-end workflow",
    "Efficiency must be measured per verified end-to-end workflow.",
  );
  requireCondition(
    efficiency.normalBatchSliceMinimum === 2 &&
      efficiency.normalBatchSliceMaximum === 4,
    "Normal batches must target two to four related slices.",
  );
  requireCondition(
    efficiency.normalBatchFullLocalGates === 1 &&
      efficiency.normalBatchImmutableCiRuns === 1,
    "A normal batch must target one complete local gate and one immutable CI run.",
  );
  requireCondition(
    efficiency.maximumConcurrentWriters >= 1 &&
      efficiency.maximumConcurrentWriters <= 2,
    "maximumConcurrentWriters must remain between one and two.",
  );

  requireCondition(
    Array.isArray(state.guardrails) &&
      state.guardrails.some((value) =>
        value.includes("/Users/benjaminmackenzie/Dev/ledger_mobile"),
      ) &&
      state.guardrails.some((value) => value.includes("Firebase")) &&
      state.guardrails.some((value) => value.includes("production")),
    "guardrails must preserve the Firebase-worktree and production boundaries.",
  );
  requireCondition(
    Array.isArray(state.resume?.requiredReads) &&
      state.resume.requiredReads[0] === stateRelativePath &&
      state.resume.requiredReads.length <= 4,
    "resume.requiredReads must begin with compact current state and contain at most four files.",
  );
  requireCondition(
    Array.isArray(state.resume?.requiredCommands) &&
      state.resume.requiredCommands.includes("npm run conversion:state:check"),
    "resume.requiredCommands must include the compact-state checker.",
  );
}

const agents = readFileSync(join(repositoryRoot, "AGENTS.md"), "utf8");
requireCondition(
  agents.includes(stateRelativePath) &&
    agents.includes("npm run conversion:state:check"),
  "AGENTS.md must require the compact state and its checker on resume.",
);

if (errors.length > 0) {
  console.error("Conversion current-state check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(
  `Conversion current state is valid: ${state.activeBatch.id} at ${state.verifiedCheckpoint.commit.slice(0, 8)}.`,
);
