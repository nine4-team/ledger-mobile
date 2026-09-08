#!/usr/bin/env node

import { readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
export const repositoryRoot = resolve(scriptDirectory, "..");
export const workflowRelativePath = ".github/workflows/supabase-conversion-control.yml";

const conversionCommands = Object.freeze([
  "node scripts/check-conversion-current-state.mjs --self-test",
  "node scripts/ledger-product-checklist.mjs --self-test",
  "node scripts/supabase-conversion-ledger.mjs source-self-test",
  "npm run conversion:ci:test",
  "npm run conversion:check",
  "npm run conversion:capabilities:check",
  "npm run conversion:queries:check",
]);

const retiredConversionCommands = Object.freeze([
  "npm run target:query-ports:test",
  "npm run target:query-ports:check",
  "npm run target:query-authority:test",
  "npm run target:query-authority:check",
  "npm run source:query-reconciliation:test",
  "npm run source:query-reconciliation:check",
]);

const nativeUIClipboardStep = [
  "      - name: Exercise target workspace checklist UI",
  "        env:",
  '          TEST_RUNNER_LEDGER_ISOLATED_CI_CLIPBOARD: "true"',
  "        run: npm run target:staging:ui:test:macos",
].join("\n");

const requiredScripts = Object.freeze({
  "conversion:ci:test": "node --test scripts/tests/check-conversion-ci.test.mjs scripts/tests/select-ci-supabase-db-port.test.mjs",
  "conversion:check":
    "node scripts/check-conversion-current-state.mjs && node scripts/supabase-conversion-ledger.mjs source-check",
  "conversion:capabilities:check":
    "node scripts/extract-current-capability-surfaces.mjs check",
  "conversion:queries:check": "node scripts/extract-firestore-query-contract.mjs check",
  "target:environment:check": "node scripts/check-target-environment.mjs",
  "target:contracts:check":
    "node scripts/generate-target-contracts.mjs check && npm --prefix LedgerTargetMCP run check",
  "target:mcp:test": "npm --prefix LedgerTargetMCP test",
  "target:supabase:test:db": "npx --yes supabase@2.116.0 test db --local",
  "target:supabase:test:space-assignment-destination-read":
    "node scripts/test-local-space-assignment-destination-read.mjs",
  "target:supabase:test:project-note-read":
    "node scripts/test-local-project-note-read.mjs",
  "target:supabase:test:payment-import":
    "node scripts/test-local-imported-payment-concurrency.mjs",
  "target:supabase:test:rpc":
    "node scripts/test-local-client-creation-rpc.mjs && node scripts/test-local-project-creation-rpc.mjs",
  "target:staging:build:macos":
    "xcodebuild -project LedgeriOS/LedgerTarget.xcodeproj -scheme LedgerTargetStaging -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build",
  "target:staging:ui:test:macos":
    "xcodebuild -project LedgeriOS/LedgerTarget.xcodeproj -scheme LedgerTargetStaging -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- -only-testing:LedgerTargetStagingUITests/WorkspaceChecklistUITests test",
  "target:staging:build:ios":
    "xcodebuild -project LedgeriOS/LedgerTarget.xcodeproj -scheme LedgerTargetStaging -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build",
});

const legacyScripts = Object.freeze({
  "conversion:sync": "node scripts/supabase-conversion-ledger.mjs sync",
  "conversion:residuals:generate": "node scripts/generate-m2-residual-register.mjs generate",
  "conversion:residuals:check": "node scripts/generate-m2-residual-register.mjs check",
  "target:query-ports:generate": "node scripts/generate-target-query-port-inventory.mjs generate",
  "target:query-ports:check": "node scripts/generate-target-query-port-inventory.mjs check",
  "target:query-ports:test": "node --test scripts/tests/generate-target-query-port-inventory.test.mjs",
  "target:query-authority:generate":
    "node scripts/generate-target-query-logical-authority-crosswalk.mjs generate",
  "target:query-authority:check":
    "node scripts/generate-target-query-logical-authority-crosswalk.mjs check",
  "target:query-authority:test":
    "node --test scripts/tests/generate-target-query-logical-authority-crosswalk.test.mjs",
  "source:query-reconciliation:generate":
    "node scripts/generate-source-query-reconciliation.mjs generate",
  "source:query-reconciliation:check":
    "node scripts/generate-source-query-reconciliation.mjs check",
  "source:query-reconciliation:test":
    "node --test scripts/tests/generate-source-query-reconciliation.test.mjs",
  "conversion:gate:m0": "node scripts/supabase-conversion-ledger.mjs gate M0",
  "conversion:gate:m1": "node scripts/supabase-conversion-ledger.mjs gate M1",
  "conversion:gate:m2": "node scripts/supabase-conversion-ledger.mjs gate M2",
});

function fail(message) {
  throw new Error(`conversion-ci: ${message}`);
}

function requireCondition(condition, message) {
  if (!condition) fail(message);
}

function normalizedLines(text) {
  requireCondition(typeof text === "string", "workflow must be text");
  return text.replace(/\r\n?/g, "\n").split("\n");
}

function uniqueLineIndex(lines, pattern, label) {
  const matches = lines.flatMap((line, index) => (pattern.test(line) ? [index] : []));
  requireCondition(matches.length === 1, `${label} must occur exactly once`);
  return matches[0];
}

function jobLines(lines, jobName) {
  const start = uniqueLineIndex(lines, new RegExp(`^  ${jobName}:\\s*$`), `${jobName} job`);
  const relativeEnd = lines
    .slice(start + 1)
    .findIndex((line) => /^  [A-Za-z0-9_-]+:\s*$/.test(line));
  const end = relativeEnd < 0 ? lines.length : start + 1 + relativeEnd;
  return lines.slice(start, end);
}

function requireExactLine(lines, expected, label) {
  requireCondition(
    lines.filter((line) => line === expected).length === 1,
    `${label} must occur exactly once`,
  );
}

function commandsForNamedStep(lines, stepName) {
  const start = uniqueLineIndex(
    lines,
    new RegExp(`^      - name: ${stepName.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\s*$`),
    `${stepName} step`,
  );
  const relativeEnd = lines.slice(start + 1).findIndex((line) => /^      - name:/.test(line));
  const end = relativeEnd < 0 ? lines.length : start + 1 + relativeEnd;
  const block = lines.slice(start + 1, end);
  requireCondition(block[0] === "        run: |", `${stepName} must use a literal run block`);
  return block
    .slice(1)
    .filter((line) => line.trim() !== "" && !line.trim().startsWith("#"))
    .map((line) => {
      requireCondition(line.startsWith("          "), `${stepName} has an invalid command indent`);
      return line.slice(10);
    });
}

function validatePackageScripts(packageJson) {
  requireCondition(packageJson && typeof packageJson === "object", "package.json must be an object");
  requireCondition(
    packageJson.scripts && typeof packageJson.scripts === "object" && !Array.isArray(packageJson.scripts),
    "package.json scripts must be an object",
  );
  for (const [name, command] of Object.entries(requiredScripts)) {
    requireCondition(
      packageJson.scripts[name] === command,
      `package.json script ${name} must execute the required gate`,
    );
    for (const prefix of ["pre", "post"]) {
      requireCondition(
        !Object.hasOwn(packageJson.scripts, `${prefix}${name}`),
        `package.json must not define ${prefix}${name}`,
      );
    }
  }
  for (const [oldName, command] of Object.entries(legacyScripts)) {
    requireCondition(
      !Object.hasOwn(packageJson.scripts, oldName),
      `historical script ${oldName} must remain namespaced as legacy:${oldName}`,
    );
    requireCondition(
      packageJson.scripts[`legacy:${oldName}`] === command,
      `historical script legacy:${oldName} must remain explicitly reproducible`,
    );
  }
}

function validateWorkflowSafety(lines) {
  const triggerStart = uniqueLineIndex(lines, /^on:\s*$/, "workflow trigger root");
  const permissionsStart = uniqueLineIndex(lines, /^permissions:\s*$/, "workflow permissions root");
  requireCondition(triggerStart < permissionsStart, "workflow triggers must precede permissions");
  const triggerLines = lines
    .slice(triggerStart, permissionsStart)
    .filter((line) => line.trim() !== "");
  requireCondition(
    JSON.stringify(triggerLines) === JSON.stringify(["on:", "  pull_request:"]),
    "workflow must run unconditionally for pull requests only",
  );
  requireExactLine(lines, "  contents: read", "read-only workflow permission");

  const executionOverride = /^\s*(?:env|defaults|shell|working-directory|container)\s*:/;
  requireCondition(
    !lines.some((line, index) => executionOverride.test(line)
      && lines.slice(index - 1, index + 3).join("\n") !== nativeUIClipboardStep),
    "environment or execution overrides require security review",
  );

  const conditional = /^\s+(?:["']?if["']?|["']?continue-on-error["']?)\s*:/;
  for (const [index, line] of lines.entries()) {
    if (!conditional.test(line)) continue;
    const allowedCleanup =
      line === "        if: always()" &&
      lines[index - 1] === "      - name: Stop isolated local Supabase" &&
      lines[index + 1] === "        run: npx --yes supabase@2.116.0 stop --no-backup";
    const allowedDiagnostics =
      line === "        if: always()" &&
      lines[index - 1] === "      - name: Preserve native test stall diagnostics" &&
      lines[index + 1] === "        uses: actions/upload-artifact@v4";
    requireCondition(allowedCleanup || allowedDiagnostics,
      "jobs must not conditionally skip or tolerate failures");
  }
}

function validateConversionJob(lines) {
  const conversion = jobLines(lines, "conversion-control");
  requireExactLine(conversion, "    runs-on: ubuntu-latest", "conversion Linux runner");
  const actualCommands = commandsForNamedStep(conversion, "Validate conversion control plane");
  requireCondition(
    JSON.stringify(actualCommands) === JSON.stringify(conversionCommands),
    "conversion validation commands or order changed",
  );
  for (const retired of retiredConversionCommands) {
    requireCondition(!lines.some((line) => line.trim() === retired), `${retired} is historical and must not run in normal CI`);
  }
  requireExactLine(
    conversion,
    "      - name: Confirm checks did not rewrite tracked artifacts",
    "conversion read-only diff step",
  );
  const guard = uniqueLineIndex(
    conversion,
    /^      - name: Confirm checks did not rewrite tracked artifacts\s*$/,
    "conversion read-only diff step",
  );
  requireCondition(
    conversion[guard + 1] === "        run: git diff --exit-code",
    "conversion job must retain its exact read-only diff guard",
  );
}

function validateTargetJob(lines) {
  const target = jobLines(lines, "target-environment");
  requireExactLine(target, "    needs: [conversion-control, local-supabase-provider-slices]", "target same-commit database dependency");
  requireCondition(target.join("\n").includes([
    "      - name: Load same-commit report parity fixture",
    "        uses: actions/download-artifact@v4",
    "        with:",
    "          name: report-parity-${{ github.sha }}",
    "          path: ${{ runner.temp }}",
  ].join("\n")), "target requires the exact same-commit report fixture");
  requireExactLine(target, "    runs-on: macos-26", "target macOS runner");
  requireCondition(target.join("\n").includes(nativeUIClipboardStep),
    "native UI Copy verification requires its exact isolated test-runner flag");
  for (const command of [
    "          node --check scripts/check-target-environment.mjs",
    "          npm run target:environment:check",
    "          npm --prefix LedgerTargetMCP ci --ignore-scripts",
    "          npm run target:contracts:check",
    "          npm run target:mcp:test",
    "        run: npm run target:staging:build:macos",
    "        run: npm run target:staging:ui:test:macos",
    "        run: npm run target:staging:build:ios",
  ]) {
    const label = command.trim().replace(/^run:\s+/, "");
    requireExactLine(target, command, `target gate ${label}`);
  }
  requireCondition(
    target.filter((line) => line === "          swift test --package-path LedgeriOS --no-parallel").length === 1,
    "target job must retain one complete nonparallel Swift test gate",
  );
  requireCondition(!target.some(line => /^\s+--(?:filter|skip)\b/.test(line)),
    "native test gate must not filter or skip suites");
  const guard = uniqueLineIndex(
    target,
    /^      - name: Confirm target checks did not rewrite tracked artifacts\s*$/,
    "target read-only diff step",
  );
  const diagnostics = [
    "      - name: Preserve native test stall diagnostics",
    "        if: always()",
    "        uses: actions/upload-artifact@v4",
    "        with:",
    "          name: native-test-stall-diagnostics",
    "          path: ${{ runner.temp }}/ledger-native-diagnostics",
    "          if-no-files-found: ignore",
  ];
  requireCondition(target.join("\n").includes(diagnostics.join("\n") + "\n\n"),
    "target diagnostics must retain the exact bounded artifact configuration");
  const wrapper = "          bash scripts/run-target-native-tests-with-diagnostics.sh";
  requireCondition(target.filter(line => line === wrapper).length === 1,
    "target diagnostics must wrap exactly one native test command");
  const nativeIndex = target.indexOf("          swift test --package-path LedgeriOS --no-parallel");
  requireCondition(target[nativeIndex - 1] === wrapper && target[nativeIndex + 1] === "",
    "target diagnostics must wrap the complete native test command");
  requireCondition(
    target[guard + 1] === "        run: git diff --exit-code",
    "target job must retain its exact read-only diff guard",
  );
}

function validateLocalSupabaseJob(lines) {
  const local = jobLines(lines, "local-supabase-provider-slices");
  requireCondition(local.join("\n").includes([
    "      - name: Preserve same-commit report parity fixture",
    "        uses: actions/upload-artifact@v4",
    "        with:",
    "          name: report-parity-${{ github.sha }}",
    "          path: ${{ runner.temp }}/ledger-property-report-parity.json",
    "          if-no-files-found: error",
    "          retention-days: 1",
  ].join("\n")), "local database gate must preserve the same-commit report fixture");
  requireExactLine(local, "    needs: conversion-control", "local Supabase dependency");
  requireExactLine(local, "    runs-on: ubuntu-latest", "local Supabase Linux runner");
  const portSelection = local.indexOf("        run: node scripts/select-ci-supabase-db-port.mjs");
  requireCondition(portSelection >= 0 && portSelection < local.indexOf("      - name: Start isolated local Supabase"),
    "local database port selection must precede startup");
  for (const command of [
    "          npx --yes supabase@2.116.0 start",
    "          -x studio,imgproxy,mailpit,edge-runtime,logflare,vector,supavisor",
    "          npx --yes supabase@2.116.0 db lint --local --schema public,ledger_private --level warning --fail-on warning",
    "          npm run target:supabase:test:db",
    "          npm run target:supabase:test:space-assignment-destination-read",
    "          npm run target:supabase:test:project-note-read",
    "          npm run target:supabase:test:rpc",
    "          npm run target:supabase:test:payment-import",
    "          node scripts/test-local-item-placement-concurrency.mjs",
    "          node scripts/test-local-physical-item-stream.mjs",
    "          node scripts/test-local-property-management-stream.mjs",
    "          node scripts/test-local-property-report-mcp.mjs",
    "          npm --prefix LedgerTargetMCP ci --ignore-scripts",
    "        run: npx --yes supabase@2.116.0 stop --no-backup",
  ]) {
    requireExactLine(local, command, `local database gate ${command.trim()}`);
  }
  const guard = uniqueLineIndex(
    local,
    /^      - name: Confirm target checks did not rewrite tracked artifacts\s*$/,
    "local Supabase read-only diff step",
  );
  requireCondition(
    local[guard + 1] === "        run: git diff --exit-code",
    "local Supabase job must retain its exact read-only diff guard",
  );
}

function validateFullHistory(lines) {
  const conversion = jobLines(lines, "conversion-control");
  const target = jobLines(lines, "target-environment");
  requireExactLine(conversion, "          fetch-depth: 0", "conversion full-history checkout");
  requireExactLine(target, "          fetch-depth: 0", "target full-history checkout");
  requireCondition(
    lines.filter((line) => line === "          fetch-depth: 0").length === 2,
    "workflow must retain the two full-history checkouts",
  );
}

export function validateConversionCI(packageJson, workflowText) {
  validatePackageScripts(packageJson);
  const lines = normalizedLines(workflowText);
  validateWorkflowSafety(lines);
  validateConversionJob(lines);
  validateTargetJob(lines);
  validateLocalSupabaseJob(lines);
  validateFullHistory(lines);
  return {
    conversionCommands: conversionCommands.length,
    packageGates: Object.keys(requiredScripts).length,
    legacyScripts: Object.keys(legacyScripts).length,
    jobs: 3,
  };
}

export function validateRepositoryConversionCI(root = repositoryRoot) {
  const packageJson = JSON.parse(readFileSync(join(root, "package.json"), "utf8"));
  const workflowText = readFileSync(join(root, workflowRelativePath), "utf8");
  return validateConversionCI(packageJson, workflowText);
}

function isMainModule() {
  return process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href;
}

if (isMainModule()) {
  const result = validateRepositoryConversionCI();
  console.log(`Conversion CI safety check passed: ${JSON.stringify(result)}`);
}
