#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(scriptDirectory, "..");
const packageRoot = path.join(repositoryRoot, "LedgeriOS");
const coreRoot = path.join(packageRoot, "LedgerTargetCore");
const testRoot = path.join(packageRoot, "LedgerTargetCoreTests");
const migrationCoreRoot = path.join(packageRoot, "LedgerTargetMigrationCore");
const migrationTestRoot = path.join(
  packageRoot,
  "LedgerTargetMigrationCoreTests",
);
const testSupportRoot = path.join(packageRoot, "LedgerTargetTestSupport");
const testSupportTestRoot = path.join(
  packageRoot,
  "LedgerTargetTestSupportTests",
);
const compositionRoot = path.join(packageRoot, "LedgerTargetComposition");
const compositionTestRoot = path.join(
  packageRoot,
  "LedgerTargetCompositionTests",
);
const powerSyncRoot = path.join(packageRoot, "LedgerTargetPowerSync");
const powerSyncTestRoot = path.join(packageRoot, "LedgerTargetPowerSyncTests");
const targetAppRoot = path.join(packageRoot, "LedgerTargetApp");
const targetProject = path.join(
  packageRoot,
  "LedgerTarget.xcodeproj",
  "project.pbxproj",
);
const targetScheme = path.join(
  packageRoot,
  "LedgerTarget.xcodeproj",
  "xcshareddata",
  "xcschemes",
  "LedgerTargetStaging.xcscheme",
);
const targetProjectSpec = path.join(packageRoot, "LedgerTargetProject.yml");
const sourceProject = path.join(
  packageRoot,
  "LedgeriOS.xcodeproj",
  "project.pbxproj",
);

const failures = [];

function fail(code, detail) {
  failures.push({ code, detail });
}

function swiftFiles(directory) {
  if (!fs.existsSync(directory)) return [];
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const absolute = path.join(directory, entry.name);
    if (entry.isDirectory()) return swiftFiles(absolute);
    return entry.isFile() && entry.name.endsWith(".swift") ? [absolute] : [];
  });
}

function relative(filePath) {
  return path.relative(repositoryRoot, filePath).split(path.sep).join("/");
}

const packageManifest = path.join(packageRoot, "Package.swift");
if (!fs.existsSync(packageManifest)) {
  fail("target_package_missing", "LedgeriOS/Package.swift");
}

let description;
if (failures.length === 0) {
  try {
    description = JSON.parse(
      execFileSync(
        "swift",
        ["package", "--package-path", packageRoot, "describe", "--type", "json"],
        { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] },
      ),
    );
  } catch {
    fail("target_package_invalid", "swift package describe failed");
  }
}

if (description) {
  const expectedExternalDependencies = new Map([
    ["powersync-swift", ["1.16.1"]],
    ["csqlite", ["3.51.2"]],
  ]);
  const externalDependencies = description.dependencies ?? [];
  if (externalDependencies.length !== expectedExternalDependencies.size) {
    fail(
      "target_provider_dependency_set",
      "The target package must resolve only the reviewed PowerSync and encrypted CSQLite direct dependencies.",
    );
  }
  for (const dependency of externalDependencies) {
    const expectedVersion = expectedExternalDependencies.get(dependency.identity);
    if (
      !expectedVersion ||
      JSON.stringify(dependency.requirement?.exact) !== JSON.stringify(expectedVersion)
    ) {
      fail(
        "target_provider_dependency_version",
        `${dependency.identity}:${JSON.stringify(dependency.requirement)}`,
      );
    }
  }

  const targets = new Map(
    (description.targets ?? []).map((target) => [target.name, target]),
  );
  const core = targets.get("LedgerTargetCore");
  const tests = targets.get("LedgerTargetCoreTests");
  const migrationCore = targets.get("LedgerTargetMigrationCore");
  const migrationTests = targets.get("LedgerTargetMigrationCoreTests");
  const testSupport = targets.get("LedgerTargetTestSupport");
  const testSupportTests = targets.get("LedgerTargetTestSupportTests");
  const composition = targets.get("LedgerTargetComposition");
  const compositionTests = targets.get("LedgerTargetCompositionTests");
  const powerSync = targets.get("LedgerTargetPowerSync");
  const powerSyncTests = targets.get("LedgerTargetPowerSyncTests");
  if (!core) {
    fail("target_core_missing", "LedgerTargetCore");
  } else if ((core.target_dependencies ?? []).length !== 0) {
    fail(
      "target_core_dependency_boundary",
      "LedgerTargetCore must not depend on another target.",
    );
  }
  if (!tests) {
    fail("target_core_tests_missing", "LedgerTargetCoreTests");
  } else {
    const dependencies = new Set(tests.target_dependencies ?? []);
    if (dependencies.size !== 1 || !dependencies.has("LedgerTargetCore")) {
      fail(
        "target_core_test_dependency_boundary",
        "LedgerTargetCoreTests may depend only on LedgerTargetCore.",
      );
    }
  }
  if (!migrationCore) {
    fail("target_migration_core_missing", "LedgerTargetMigrationCore");
  } else {
    const dependencies = new Set(migrationCore.target_dependencies ?? []);
    if (dependencies.size !== 1 || !dependencies.has("LedgerTargetCore")) {
      fail(
        "target_migration_core_dependency_boundary",
        "LedgerTargetMigrationCore may depend only on LedgerTargetCore.",
      );
    }
  }
  if (!migrationTests) {
    fail(
      "target_migration_core_tests_missing",
      "LedgerTargetMigrationCoreTests",
    );
  } else {
    const dependencies = new Set(migrationTests.target_dependencies ?? []);
    if (
      dependencies.size !== 2 ||
      !dependencies.has("LedgerTargetCore") ||
      !dependencies.has("LedgerTargetMigrationCore")
    ) {
      fail(
        "target_migration_core_test_dependency_boundary",
        "LedgerTargetMigrationCoreTests may depend only on LedgerTargetCore and LedgerTargetMigrationCore.",
      );
    }
  }
  if (!testSupport) {
    fail("target_test_support_missing", "LedgerTargetTestSupport");
  } else {
    const dependencies = new Set(testSupport.target_dependencies ?? []);
    if (dependencies.size !== 1 || !dependencies.has("LedgerTargetCore")) {
      fail(
        "target_test_support_dependency_boundary",
        "LedgerTargetTestSupport may depend only on LedgerTargetCore.",
      );
    }
  }
  if (!testSupportTests) {
    fail("target_test_support_tests_missing", "LedgerTargetTestSupportTests");
  } else {
    const dependencies = new Set(testSupportTests.target_dependencies ?? []);
    if (
      dependencies.size !== 2 ||
      !dependencies.has("LedgerTargetCore") ||
      !dependencies.has("LedgerTargetTestSupport")
    ) {
      fail(
        "target_test_support_test_dependency_boundary",
        "LedgerTargetTestSupportTests may depend only on LedgerTargetCore and LedgerTargetTestSupport.",
      );
    }
  }
  if (!composition) {
    fail("target_composition_missing", "LedgerTargetComposition");
  } else {
    const dependencies = new Set(composition.target_dependencies ?? []);
    if (dependencies.size !== 1 || !dependencies.has("LedgerTargetCore")) {
      fail(
        "target_composition_dependency_boundary",
        "LedgerTargetComposition may depend only on LedgerTargetCore.",
      );
    }
  }
  if (!compositionTests) {
    fail("target_composition_tests_missing", "LedgerTargetCompositionTests");
  } else {
    const dependencies = new Set(compositionTests.target_dependencies ?? []);
    if (
      dependencies.size !== 3 ||
      !dependencies.has("LedgerTargetCore") ||
      !dependencies.has("LedgerTargetComposition") ||
      !dependencies.has("LedgerTargetTestSupport")
    ) {
      fail(
        "target_composition_test_dependency_boundary",
        "LedgerTargetCompositionTests may depend only on LedgerTargetCore, LedgerTargetComposition, and LedgerTargetTestSupport.",
      );
    }
  }
  if (!powerSync) {
    fail("target_powersync_missing", "LedgerTargetPowerSync");
  } else {
    const dependencies = new Set(powerSync.target_dependencies ?? []);
    const products = new Set(powerSync.product_dependencies ?? []);
    if (
      dependencies.size !== 1 ||
      !dependencies.has("LedgerTargetCore") ||
      products.size !== 2 ||
      !products.has("PowerSync") ||
      !products.has("CSQLite")
    ) {
      fail(
        "target_powersync_dependency_boundary",
        "LedgerTargetPowerSync must depend only on LedgerTargetCore, PowerSync, and encrypted CSQLite.",
      );
    }
  }
  if (!powerSyncTests) {
    fail("target_powersync_tests_missing", "LedgerTargetPowerSyncTests");
  } else {
    const dependencies = new Set(powerSyncTests.target_dependencies ?? []);
    const products = new Set(powerSyncTests.product_dependencies ?? []);
    if (
      dependencies.size !== 2 ||
      !dependencies.has("LedgerTargetCore") ||
      !dependencies.has("LedgerTargetPowerSync") ||
      products.size !== 1 ||
      !products.has("PowerSync")
    ) {
      fail(
        "target_powersync_test_dependency_boundary",
        "LedgerTargetPowerSyncTests may depend only on LedgerTargetCore, LedgerTargetPowerSync, and PowerSync.",
      );
    }
  }
}

const forbiddenImport =
  /^\s*(?:@preconcurrency\s+)?import\s+(Firebase\w*|Supabase\w*|PowerSync\w*|GoogleSignIn)\b/m;
for (const filePath of [
  ...swiftFiles(coreRoot),
  ...swiftFiles(testRoot),
  ...swiftFiles(migrationCoreRoot),
  ...swiftFiles(migrationTestRoot),
  ...swiftFiles(testSupportRoot),
  ...swiftFiles(testSupportTestRoot),
  ...swiftFiles(compositionRoot),
  ...swiftFiles(compositionTestRoot),
  ...swiftFiles(targetAppRoot),
]) {
  const match = fs.readFileSync(filePath, "utf8").match(forbiddenImport);
  if (match) {
    fail(
      "target_core_provider_import",
      `${relative(filePath)} imports ${match[1]}`,
    );
  }
}

const forbiddenSourceProviderImport =
  /^\s*(?:@preconcurrency\s+)?import\s+(Firebase\w*|GoogleSignIn)\b/m;
for (const filePath of [
  ...swiftFiles(powerSyncRoot),
  ...swiftFiles(powerSyncTestRoot),
]) {
  const match = fs.readFileSync(filePath, "utf8").match(forbiddenSourceProviderImport);
  if (match) {
    fail(
      "target_powersync_source_provider_import",
      `${relative(filePath)} imports ${match[1]}`,
    );
  }
}

for (const [code, requiredPath] of [
  ["target_project_spec_missing", targetProjectSpec],
  ["target_project_missing", targetProject],
  ["target_scheme_missing", targetScheme],
]) {
  if (!fs.existsSync(requiredPath)) {
    fail(code, relative(requiredPath));
  }
}

if (
  fs.existsSync(targetProjectSpec) &&
  fs.existsSync(targetProject) &&
  fs.existsSync(targetScheme)
) {
  const spec = fs.readFileSync(targetProjectSpec, "utf8");
  const project = fs.readFileSync(targetProject, "utf8");
  const scheme = fs.readFileSync(targetScheme, "utf8");
  const targetAppSource = swiftFiles(targetAppRoot)
    .map((filePath) => fs.readFileSync(filePath, "utf8"))
    .join("\n");
  const requiredProjectionText = [
    "supportedDestinations:",
    "- iOS",
    "- macOS",
    "PRODUCT_BUNDLE_IDENTIFIER: apps.nine4.ledger.staging",
    "INFOPLIST_KEY_CFBundleDisplayName: Ledger STAGING",
  ];
  for (const required of requiredProjectionText) {
    if (!spec.includes(required)) {
      fail("target_staging_projection_incomplete", required);
    }
  }
  for (const required of [
    "apps.nine4.ledger.staging",
    "Ledger STAGING",
    "LedgerTargetCore",
    "LedgerTargetPowerSync",
  ]) {
    if (!project.includes(required)) {
      fail("target_generated_project_incomplete", required);
    }
  }
  if (!scheme.includes('BlueprintName = "LedgerTargetStaging"')) {
    fail("target_staging_scheme_invalid", relative(targetScheme));
  }
  if (!targetAppSource.includes("LOCAL SPIKE • NO HOSTED SERVICES")) {
    fail("target_staging_banner_missing", relative(targetAppRoot));
  }
  if (!targetAppSource.includes("unprovisioned-powersync-staging")) {
    fail("target_staging_unprovisioned_marker_missing", relative(targetAppRoot));
  }
  for (const forbiddenProductionIdentifier of [
    '"ledger-nine4"',
    '"ledger-nine4.firebasestorage.app"',
    '"apps.nine4.ledger"',
    '"supabase-production"',
    '"powersync-production"',
    '"storage-production"',
    '"mcp-production"',
  ]) {
    if (targetAppSource.includes(forbiddenProductionIdentifier)) {
      fail(
        "target_staging_production_identifier",
        forbiddenProductionIdentifier,
      );
    }
  }
  if (
    /ProcessInfo\.processInfo\.environment|UserDefaults\.standard/.test(
      targetAppSource,
    )
  ) {
    fail(
      "target_runtime_environment_toggle",
      "The staging projection must be fixed at compilation.",
    );
  }
  if (/Firebase|GoogleSignIn|XCRemoteSwiftPackageReference/.test(project)) {
    fail(
      "target_project_provider_contamination",
      "The target staging project contains a source-provider dependency.",
    );
  }
  if (/LedgerTargetMigrationCore/.test(project)) {
    fail(
      "target_app_migration_tooling_contamination",
      "The target staging application must not link migration-control tooling.",
    );
  }
  if (/LedgerTargetTestSupport/.test(project)) {
    fail(
      "target_app_test_support_contamination",
      "The target staging application must not link test-support tooling.",
    );
  }
  if (/LedgerTargetComposition/.test(project)) {
    fail(
      "target_app_composition_contamination",
      "The target staging application must not link composition before its application-wiring slice.",
    );
  }
}

if (!fs.existsSync(sourceProject)) {
  fail("source_project_missing", "LedgeriOS/LedgeriOS.xcodeproj/project.pbxproj");
} else {
  const project = fs.readFileSync(sourceProject, "utf8");
  for (const targetOnlyPath of [
    "LedgerTargetCore/TargetEnvironment.swift",
    "LedgerTargetCoreTests/TargetEnvironmentManifestTests.swift",
    "LedgerTargetMigrationCore",
    "LedgerTargetMigrationCoreTests",
    "LedgerTargetTestSupport",
    "LedgerTargetTestSupportTests",
    "LedgerTargetComposition",
    "LedgerTargetCompositionTests",
    "LedgerTargetPowerSync",
    "LedgerTargetPowerSyncTests",
  ]) {
    if (project.includes(targetOnlyPath)) {
      fail(
        "source_target_contamination",
        `The Firebase application project references ${targetOnlyPath}.`,
      );
    }
  }
}

if (failures.length > 0) {
  for (const failure of failures) {
    process.stderr.write(`${failure.code}: ${failure.detail}\n`);
  }
  process.exit(1);
}

process.stdout.write(
  "target-environment: isolated LedgerTargetCore, reviewed PowerSync/encrypted-SQLite provider lane, separate migration-control/test-support/composition tooling, and local-spike app graph validated; fixed staging identity and no runtime toggle, tooling app link, premature composition link, source-provider import, or Firebase-project contamination detected\n",
);
