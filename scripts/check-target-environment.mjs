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
const appModelRoot = path.join(packageRoot, "LedgerTargetAppModel");
const appModelTestRoot = path.join(packageRoot, "LedgerTargetAppModelTests");
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

function filesWithExtension(directory, extension) {
  if (!fs.existsSync(directory)) return [];
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const absolute = path.join(directory, entry.name);
    if (entry.isDirectory()) return filesWithExtension(absolute, extension);
    return entry.isFile() && entry.name.endsWith(extension) ? [absolute] : [];
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
  const appModel = targets.get("LedgerTargetAppModel");
  const appModelTests = targets.get("LedgerTargetAppModelTests");
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
  if (!appModel) {
    fail("target_app_model_missing", "LedgerTargetAppModel");
  } else {
    const dependencies = new Set(appModel.target_dependencies ?? []);
    if (dependencies.size !== 1 || !dependencies.has("LedgerTargetCore")) {
      fail(
        "target_app_model_dependency_boundary",
        "LedgerTargetAppModel may depend only on LedgerTargetCore.",
      );
    }
  }
  if (!appModelTests) {
    fail("target_app_model_tests_missing", "LedgerTargetAppModelTests");
  } else {
    const dependencies = new Set(appModelTests.target_dependencies ?? []);
    if (
      dependencies.size !== 2 ||
      !dependencies.has("LedgerTargetCore") ||
      !dependencies.has("LedgerTargetAppModel")
    ) {
      fail(
        "target_app_model_test_dependency_boundary",
        "LedgerTargetAppModelTests may depend only on LedgerTargetCore and LedgerTargetAppModel.",
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
  ...swiftFiles(appModelRoot),
  ...swiftFiles(appModelTestRoot),
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

const accountWorkspaceRuntimePath = path.join(
  powerSyncRoot,
  "LedgerOfflineClientRuntime.swift",
);
const accountWorkspaceCoordinatorPath = path.join(
  powerSyncRoot,
  "AccountWorkspacePendingWorkRuntime.swift",
);
const accountWorkspaceIsolationPath = path.join(
  powerSyncRoot,
  "LedgerWorkspaceRuntimeIsolation.swift",
);
for (const requiredPath of [
  accountWorkspaceRuntimePath,
  accountWorkspaceCoordinatorPath,
  accountWorkspaceIsolationPath,
]) {
  if (!fs.existsSync(requiredPath)) {
    fail("target_account_workspace_runtime_missing", relative(requiredPath));
  }
}
if (
  fs.existsSync(accountWorkspaceRuntimePath) &&
  fs.existsSync(accountWorkspaceCoordinatorPath) &&
  fs.existsSync(accountWorkspaceIsolationPath)
) {
  const runtimeSource = fs.readFileSync(accountWorkspaceRuntimePath, "utf8");
  const coordinatorSource = fs.readFileSync(
    accountWorkspaceCoordinatorPath,
    "utf8",
  );
  const isolationSource = fs.readFileSync(accountWorkspaceIsolationPath, "utf8");
  const powerSyncSources = swiftFiles(powerSyncRoot)
    .map((filePath) => fs.readFileSync(filePath, "utf8"))
    .join("\n");
  const publicRuntimeFunctions = [
    ...runtimeSource.matchAll(/public\s+func\s+(\w+)/g),
  ].map((match) => match[1]);
  const expectedPublicRuntimeFunctions = [
    "archive",
    "archive",
    "captureAttachment",
    "close",
    "createClient",
    "createProject",
    "encryptionCipher",
    "pendingUploadCount",
    "pendingWorkSummary",
    "resolveLocalAttachmentBytes",
    "watchBudgetCategories",
    "watchClient",
    "watchClientArchiveOperation",
    "watchClients",
    "watchOperation",
    "watchProject",
    "watchProjectNotes",
    "watchProjects",
    "watchSpaceAssignmentDestinations",
    "watchSpaceCoreDetails",
    "watchTransferDestinations",
  ];
  if (
    JSON.stringify([...publicRuntimeFunctions].sort()) !==
    JSON.stringify(expectedPublicRuntimeFunctions)
  ) {
    fail(
      "target_account_workspace_public_surface",
      publicRuntimeFunctions.join(","),
    );
  }

  const budgetCategoryWatchSignatures = [
    ...runtimeSource.matchAll(
      /public\s+func\s+watchBudgetCategories\s*\(\s*\)\s*->\s*AsyncThrowingStream\s*<\s*BudgetCategoryReferenceSnapshot\s*,\s*Error\s*>\s*\{/g,
    ),
  ];
  if (budgetCategoryWatchSignatures.length !== 1) {
    fail(
      "target_budget_category_watch_signature",
      "The public runtime must expose exactly one zero-argument, Account-bound budget-category watch.",
    );
  }

  const attachmentResolutionSignatures = [
    ...runtimeSource.matchAll(
      /public\s+func\s+resolveLocalAttachmentBytes\s*\(\s*for\s+receipt:\s*AttachmentLocalDurabilityReceipt\s*\)\s*async\s+throws\s*->\s*Data\s*\{/g,
    ),
  ];
  if (attachmentResolutionSignatures.length !== 1) {
    fail(
      "target_attachment_local_byte_resolution_signature",
      "The public runtime must expose exactly one full-receipt local byte resolver.",
    );
  }
  if (
    /resolveLocalAttachmentBytes\s*\([^)]*AttachmentID/.test(runtimeSource) ||
    /resolveLocalAttachmentBytes\s*\([^)]*(?:URL|String)\b/.test(runtimeSource)
  ) {
    fail(
      "target_attachment_local_byte_resolution_shortcut",
      "Attachment local-byte resolution must not accept an ID, path, URL, or string shortcut.",
    );
  }

  const spaceDestinationWatchSignatures = [
    ...runtimeSource.matchAll(
      /public\s+func\s+watchSpaceAssignmentDestinations\s*\(\s*scope:\s*ItemPlacementScope\s*\)\s*->\s*AsyncThrowingStream\s*<\s*SpaceAssignmentDestinationDirectorySnapshot\s*,\s*Error\s*>\s*\{/g,
    ),
  ];
  if (spaceDestinationWatchSignatures.length !== 1) {
    fail(
      "target_space_destination_watch_signature",
      "The public runtime must expose exactly one Account-bound typed placement-scope destination watch.",
    );
  }

  const transferDestinationWatchSignatures = [
    ...runtimeSource.matchAll(
      /public\s+func\s+watchTransferDestinations\s*\(\s*source:\s*ProjectSummary\s*\)\s*->\s*AsyncThrowingStream\s*<\s*TransferDestinationSelectionSnapshot\s*,\s*Error\s*>\s*\{/g,
    ),
  ];
  if (transferDestinationWatchSignatures.length !== 1) {
    fail(
      "target_transfer_destination_watch_signature",
      "The public runtime must expose exactly one Account-bound typed source-Project destination watch.",
    );
  }

  const projectNoteWatchSignatures = [
    ...runtimeSource.matchAll(
      /public\s+func\s+watchProjectNotes\s*\(\s*_\s+request:\s*ProjectNotePageRequest\s*\)\s*->\s*AsyncThrowingStream\s*<\s*ProjectNotePage\s*,\s*Error\s*>\s*\{/g,
    ),
  ];
  if (projectNoteWatchSignatures.length !== 1) {
    fail(
      "target_project_note_watch_signature",
      "The public runtime must expose exactly one Account-bound typed Project-note page watch.",
    );
  }

  const publicRuntimeSignatures = [
    ...runtimeSource.matchAll(/public\s+func\s+\w+[\s\S]*?\{/g),
    ...coordinatorSource.matchAll(/public\s+static\s+func\s+\w+[\s\S]*?\{/g),
  ]
    .map((match) => match[0])
    .join("\n");
  for (const forbiddenType of [
    "PowerSyncDatabaseProtocol",
    "PendingWorkPowerSyncQuery",
    "BudgetCategoryReferencePowerSyncQuery",
    "CompletenessObservation",
    "AttachmentCapturePowerSyncStore",
    "AttachmentLocalByteVault",
    "LedgerPowerSyncEncryptionKey",
    "LedgerWorkspaceRuntimeLocation",
    "URL",
  ]) {
    if (publicRuntimeSignatures.includes(forbiddenType)) {
      fail(
        "target_account_workspace_resource_escape",
        forbiddenType,
      );
    }
  }

  if (/public\s+init\s*\(/.test(runtimeSource)) {
    fail(
      "target_account_workspace_constructor_escape",
      "LedgerOfflineClientRuntime must be constructed only by its scoped bootstrap.",
    );
  }
  if (
    /public\s+(?:struct|enum)\s+LedgerWorkspaceRuntimeLocation\b/.test(
      isolationSource,
    ) ||
    /public\s+enum\s+LedgerWorkspaceRuntimeIsolation\b/.test(isolationSource)
  ) {
    fail(
      "target_account_workspace_path_escape",
      "Resolved database, vault, and Keychain locations must remain provider-internal.",
    );
  }

  const lifecycleOwnedTypes = [
    "AccountWorkspacePendingWorkRuntime",
    "AttachmentCapturePowerSyncDatabaseFactory",
    "AttachmentCapturePowerSyncStore",
    "AttachmentDurabilityNamespaceScope",
    "AttachmentLocalByteVault",
    "AttachmentMediaEncryptionKey",
    "ClientCoreDetailsPowerSyncQuery",
    "ClientCreationPowerSyncStore",
    "ClientProjectDirectoryPowerSyncQuery",
    "BudgetCategoryReferencePowerSyncQuery",
    "LedgerPowerSyncDatabaseFactory",
    "LedgerPowerSyncEncryptionKey",
    "LedgerPowerSyncKeychain",
    "LedgerPowerSyncUploadConnector",
    "PendingWorkPowerSyncQuery",
    "ProjectCoreDetailsPowerSyncQuery",
    "ProjectNotePowerSyncQuery",
    "ProjectArchivePowerSyncStore",
    "ProjectSetupPowerSyncStore",
    "TransferDestinationSelectionPowerSyncQuery",
  ];
  for (const typeName of lifecycleOwnedTypes) {
    const publicDeclaration = new RegExp(
      `\\bpublic\\s+(?:final\\s+)?(?:actor|class|enum|struct)\\s+${typeName}\\b`,
    );
    if (publicDeclaration.test(powerSyncSources)) {
      fail(
        "target_account_workspace_lifecycle_bypass",
        `${typeName} must remain compiler-internal to the scoped lifecycle owner.`,
      );
    }
  }

  const accountWorkspaceSources = `${runtimeSource}\n${coordinatorSource}`;
  for (const forbiddenBehavior of [
    ["target_account_workspace_destructive_close", /deleteDatabase:\s*true/],
    ["target_account_workspace_clear_escape", /disconnectAndClear/],
    ["target_account_workspace_session_policy_escape", /AccountSessionEnding/],
    ["target_account_workspace_provider_signout", /\bsignOut\b|\bsignout\b/i],
  ]) {
    if (forbiddenBehavior[1].test(accountWorkspaceSources)) {
      fail(forbiddenBehavior[0], relative(accountWorkspaceCoordinatorPath));
    }
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
  const stagingAppPath = path.join(
    targetAppRoot,
    "LedgerTargetStagingApp.swift",
  );
  const stagingAppSource = fs.existsSync(stagingAppPath)
    ? fs.readFileSync(stagingAppPath, "utf8")
    : "";
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
    "LedgerTargetAppModel",
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
  const appModelSource = swiftFiles(appModelRoot)
    .map((filePath) => fs.readFileSync(filePath, "utf8"))
    .join("\n");
  if (
    /Firebase|Firestore|Supabase|PowerSync|\bSQL\b|credential|service[_ ]?role|bearer|https?:\/\//i.test(
      appModelSource,
    )
  ) {
    fail(
      "target_app_model_provider_contamination",
      "LedgerTargetAppModel contains a provider, SQL, credential, or endpoint token.",
    );
  }

  const spaceDestinationFiles = {
    provider: path.join(powerSyncRoot, "SpaceAssignmentDestinationPowerSyncQuery.swift"),
    providerTests: path.join(powerSyncTestRoot, "SpaceAssignmentDestinationPowerSyncQueryTests.swift"),
    model: path.join(appModelRoot, "SpaceAssignmentDestinationStagingExercise.swift"),
    modelTests: path.join(appModelTestRoot, "SpaceAssignmentDestinationStagingExerciseTests.swift"),
    adapter: path.join(targetAppRoot, "SpaceAssignmentDestinationStagingRuntimeAdapter.swift"),
    view: path.join(targetAppRoot, "SpaceAssignmentDestinationStagingExerciseView.swift"),
  };
  for (const filePath of Object.values(spaceDestinationFiles)) {
    if (!fs.existsSync(filePath)) {
      fail("target_space_destination_leaf_missing", relative(filePath));
    }
  }
  if (Object.values(spaceDestinationFiles).every(fs.existsSync)) {
    const provider = fs.readFileSync(spaceDestinationFiles.provider, "utf8");
    const providerTests = fs.readFileSync(spaceDestinationFiles.providerTests, "utf8");
    const model = fs.readFileSync(spaceDestinationFiles.model, "utf8");
    const adapter = fs.readFileSync(spaceDestinationFiles.adapter, "utf8");
    const view = fs.readFileSync(spaceDestinationFiles.view, "utf8");
    for (const required of [
      '"space_assignment_project_destinations"',
      '"project_id": .string(projectId.rawValue)',
      '"space_assignment_business_inventory_destinations"',
      '"account_id": .string(accountId.rawValue)',
      ".subscribe()",
      "currentStatus.asFlow()",
      "status.syncStreams != nil",
      "status.forStream(stream: identity)",
      "Self.map(status, stream: base)",
      "status.forStream(stream: stream)",
      "status.connected",
      "baselineLastSyncedAt",
      "SELECT local_params, last_synced_at",
      "FROM ps_stream_subscriptions",
      "JsonValue.self",
      "TimeInterval(epoch) / 1_000_000",
      "let baseline = [publicBaseline, retainedBaseline]",
      "if subscription.baselineLastSyncedAt == nil",
      "subscription.waitForFirstSync()",
      "subscription.currentStatus()",
      "subscription.observeStatus",
      "epoch > $0",
      "localReader.readRows(",
      ".unsubscribe()",
    ]) {
      if (!provider.includes(required)) {
        fail("target_space_destination_subscription_incomplete", required);
      }
    }
    if (provider.includes("31_536_000") || provider.includes("Task { await owner.unsubscribe()")) {
      fail(
        "target_space_destination_persisted_sync_authority",
        "Picker completeness must use current-process evidence and structurally drained subscription ownership.",
      );
    }
    for (const required of [
      "Retained internal exact-stream epoch cannot complete when public baseline is absent",
      "INSERT INTO ps_stream_subscriptions",
      "database.currentStatus.forStream(stream: identity) == nil",
      "retained.baselineLastSyncedAt == 41",
      "controlled.waitForFirstSyncCallCount == 0",
    ]) {
      if (!providerTests.includes(required)) {
        fail("target_space_destination_retained_epoch_regression_missing", required);
      }
    }
    if (/public\s+(?:final\s+)?class\s+SpaceAssignmentDestinationPowerSyncQuery/.test(provider)) {
      fail("target_space_destination_provider_public", relative(spaceDestinationFiles.provider));
    }
    for (const state of ["waiting", "partial", "stale", "ready", "authoritativeEmpty", "failure"]) {
      if (!model.includes(`case ${state}`)) {
        fail("target_space_destination_presenter_state_missing", state);
      }
    }
    for (const required of [
      "runtime.watchSpaceAssignmentDestinations(scope: scope)",
      "model.select(spaceId: row.id)",
      "ForEach(model.rows, id: \\.id)",
    ]) {
      if (!`${adapter}\n${view}`.includes(required)) {
        fail("target_space_destination_thin_ui_incomplete", required);
      }
    }
    if (/\b(?:assign|clear|create|update|archive)(?:Space|Item)?\s*\(/i.test(`${model}\n${adapter}\n${view}`)) {
      fail("target_space_destination_mutation_escape", "Picker leaves contain a mutation-like call.");
    }
    if (/MCP|Firebase|Firestore|Supabase|https?:\/\//i.test(`${model}\n${adapter}\n${view}`)) {
      fail("target_space_destination_boundary_escape", "Picker presentation leaves cross a forbidden provider boundary.");
    }
    if (!stagingAppSource.includes("SpaceAssignmentDestinationStagingExerciseView") ||
        !stagingAppSource.includes('ProjectID(validating: "project-primary")')) {
      fail("target_space_destination_staging_missing", relative(stagingAppPath));
    }
  }
  const transferDestinationFiles = {
    provider: path.join(
      powerSyncRoot,
      "TransferDestinationSelectionPowerSyncQuery.swift",
    ),
    providerTests: path.join(
      powerSyncTestRoot,
      "TransferDestinationSelectionPowerSyncQueryTests.swift",
    ),
    model: path.join(
      appModelRoot,
      "TransferDestinationSelectionStagingExercise.swift",
    ),
    modelTests: path.join(
      appModelTestRoot,
      "TransferDestinationSelectionStagingExerciseTests.swift",
    ),
    adapter: path.join(
      targetAppRoot,
      "TransferDestinationSelectionStagingRuntimeAdapter.swift",
    ),
    view: path.join(
      targetAppRoot,
      "TransferDestinationSelectionStagingExerciseView.swift",
    ),
  };
  for (const filePath of Object.values(transferDestinationFiles)) {
    if (!fs.existsSync(filePath)) {
      fail("target_transfer_destination_leaf_missing", relative(filePath));
    }
  }
  if (Object.values(transferDestinationFiles).every(fs.existsSync)) {
    const provider = fs.readFileSync(transferDestinationFiles.provider, "utf8");
    const providerTests = fs.readFileSync(
      transferDestinationFiles.providerTests,
      "utf8",
    );
    const model = fs.readFileSync(transferDestinationFiles.model, "utf8");
    const modelTests = fs.readFileSync(
      transferDestinationFiles.modelTests,
      "utf8",
    );
    const adapter = fs.readFileSync(transferDestinationFiles.adapter, "utf8");
    const view = fs.readFileSync(transferDestinationFiles.view, "utf8");

    for (const required of [
      "directoryQuery.watchProjects(accountId: boundAccountId)",
      "$0.id == sourceRequest.id",
      "source: currentSource",
      "rows: []",
      "isCompleteForQuery: false",
      "sourceUnavailable",
      "cancelAndDrainWatches()",
    ]) {
      if (!provider.includes(required)) {
        fail("target_transfer_destination_projection_incomplete", required);
      }
    }
    if (
      /import\s+PowerSync|PowerSyncDatabaseProtocol|\bdatabase\s*\.|\bsyncStream\s*\(|\bSELECT\b|\bINSERT\b|\bUPDATE\b|\bDELETE\b/.test(
        provider,
      )
    ) {
      fail(
        "target_transfer_destination_second_data_source",
        "The derived picker provider must use only the existing Project-directory port.",
      );
    }
    if (
      /public\s+(?:final\s+)?class\s+TransferDestinationSelectionPowerSyncQuery/.test(
        provider,
      )
    ) {
      fail(
        "target_transfer_destination_provider_public",
        relative(transferDestinationFiles.provider),
      );
    }
    for (const required of [
      "Encrypted local Project directory drives the derived query without a second read",
      "Current directory source controls filtering",
      "Incomplete absence never filters by stale caller",
      "complete absence, upstream failure, cancellation, and close fail boundedly",
    ]) {
      if (!providerTests.includes(required)) {
        fail("target_transfer_destination_provider_test_missing", required);
      }
    }
    for (const state of [
      "waiting",
      "partial",
      "stale",
      "ready",
      "partialEmpty",
      "staleEmpty",
      "authoritativeEmpty",
      "failure",
    ]) {
      if (!model.includes(`case ${state}`)) {
        fail("target_transfer_destination_presenter_state_missing", state);
      }
    }
    for (const required of [
      "previous != snapshot.source.clientId",
      "!snapshot.candidates.contains(where:",
      "old?.cancel()",
      "await old?.value",
      "runtime.watchTransferDestinations(source: source)",
      "model.select(projectId: candidate.destination.id)",
      "ForEach(model.rows, id: \\.destination.id)",
    ]) {
      if (!`${model}\n${adapter}\n${view}`.includes(required)) {
        fail("target_transfer_destination_thin_ui_incomplete", required);
      }
    }
    for (const required of [
      "All presentation states stay distinct",
      "Source replacement drains the old watch and ignores late evidence",
      "stream completion, scope mismatch, and failures are bounded",
    ]) {
      if (!modelTests.includes(required)) {
        fail("target_transfer_destination_presenter_test_missing", required);
      }
    }
    if (
      /MCP|Firebase|Firestore|Supabase|URLSession|https?:\/\//i.test(
        `${model}\n${adapter}\n${view}`,
      )
    ) {
      fail(
        "target_transfer_destination_boundary_escape",
        "Transfer picker presentation leaves cross a forbidden provider boundary.",
      );
    }
    for (const required of [
      "TransferDestinationSelectionStagingExerciseView",
      "syntheticTransferSource",
      "TransferDestinationSelectionStagingRuntimeAdapter.adapt(runtime)",
    ]) {
      if (!stagingAppSource.includes(required)) {
        fail("target_transfer_destination_staging_missing", required);
      }
    }
    for (const required of [
      "SpaceCreationStagingExerciseView.swift",
      "SpaceCreationStagingRuntimeAdapter.swift",
      "TransferDestinationSelectionStagingExerciseView.swift",
      "TransferDestinationSelectionStagingRuntimeAdapter.swift",
    ]) {
      if (!project.includes(required)) {
        fail("target_transfer_destination_project_membership_missing", required);
      }
    }
  }

  const projectNoteFiles = {
    provider: path.join(powerSyncRoot, "ProjectNotePowerSyncQuery.swift"),
    providerTests: path.join(powerSyncTestRoot, "ProjectNotePowerSyncQueryTests.swift"),
    model: path.join(appModelRoot, "ProjectNoteHistoryStagingExercise.swift"),
    modelTests: path.join(appModelTestRoot, "ProjectNoteHistoryStagingExerciseTests.swift"),
    view: path.join(targetAppRoot, "ProjectNoteHistoryStagingExerciseView.swift"),
    mcp: path.join(repositoryRoot, "LedgerTargetMCP/src/projectArchivalReview.ts"),
    mcpTests: path.join(repositoryRoot, "LedgerTargetMCP/tests/projectArchivalReview.test.ts"),
  };
  for (const filePath of Object.values(projectNoteFiles)) {
    if (!fs.existsSync(filePath)) {
      fail("target_project_note_leaf_missing", relative(filePath));
    }
  }
  if (Object.values(projectNoteFiles).every(fs.existsSync)) {
    const provider = fs.readFileSync(projectNoteFiles.provider, "utf8");
    const model = fs.readFileSync(projectNoteFiles.model, "utf8");
    const view = fs.readFileSync(projectNoteFiles.view, "utf8");
    const mcp = fs.readFileSync(projectNoteFiles.mcp, "utf8");
    const mcpSourceRoot = path.join(repositoryRoot, "LedgerTargetMCP/src");
    for (const candidate of filesWithExtension(mcpSourceRoot, ".ts")) {
      if (candidate === projectNoteFiles.mcp) continue;
      const source = fs.readFileSync(candidate, "utf8");
      if (
        /projectArchivalReview(?:\.js)?/.test(source)
        || /\b(?:listProjectNotesTool|archiveProjectTool)(?:Definition)?\b/.test(source)
      ) {
        fail(
          "target_project_archival_review_mcp_registered_while_gated",
          relative(candidate),
        );
      }
    }
    const syncPath = path.join(repositoryRoot, "powersync/sync-streams.yaml");
    const sync = fs.existsSync(syncPath) ? fs.readFileSync(syncPath, "utf8") : "";
    const syncSection = sync.match(
      /^  project_note_history:\n([\s\S]*?)(?=^  [a-z][a-z0-9_]*:\n|(?![\s\S]))/m,
    )?.[0] ?? "";
    for (const required of [
      "spike_project_notes",
      "ORDER BY note.created_at_ms DESC, note.keyset_id DESC",
      "Int(request.pageSize) + 1",
      "cancelAndDrainWatches()",
      '"project_note_history"',
    ]) {
      if (!provider.includes(required)) {
        fail("target_project_note_provider_incomplete", required);
      }
    }
    if (!syncSection.includes("note.id AS keyset_id")) {
      fail("target_project_note_sync_keyset_missing", relative(syncPath));
    }
    if (/public\s+(?:final\s+)?class\s+ProjectNotePowerSyncQuery/.test(provider)) {
      fail("target_project_note_provider_public", relative(projectNoteFiles.provider));
    }
    for (const required of [
      "ProjectNotePageRequest.maximumPageSize",
      "oldTask?.cancel()",
      "await oldTask?.value",
      "page.request == request",
    ]) {
      if (!model.includes(required)) {
        fail("target_project_note_presenter_incomplete", required);
      }
    }
    if (view.includes("PrincipalID") || view.includes("deletedByPrincipalId")) {
      fail(
        "target_project_note_private_audit_escape",
        "The staging view must not render Principal identifiers or deletion audit identity.",
      );
    }
    if (!project.includes("ProjectNoteHistoryStagingExerciseView.swift")) {
      fail(
        "target_project_note_project_membership_missing",
        "ProjectNoteHistoryStagingExerciseView.swift",
      );
    }
    for (const forbidden of [
      "add_project_note",
      "edit_project_note",
      "delete_project_note",
      "search_project_notes",
    ]) {
      if (`${provider}\n${model}\n${view}\n${mcp}`.includes(forbidden)) {
        fail("target_project_note_mutation_escape", forbidden);
      }
    }
    if (/Firebase|Firestore/.test(`${provider}\n${model}\n${view}\n${mcp}`)) {
      fail("target_project_note_source_backend_escape", "Project-note target leaves reference Firebase.");
    }
    for (const required of [
      "project_note_history:",
      "subscription.parameter('account_id')",
      "subscription.parameter('project_id')",
      "principal.auth_user_id = auth.user_id()",
      "membership.state = 'active'",
      "FROM spike_project_notes AS note",
    ]) {
      if (!syncSection.includes(required)) {
        fail("target_project_note_sync_scope_incomplete", required);
      }
    }
    if (/\b(?:ORDER\s+BY|LIMIT)\b/i.test(syncSection)) {
      fail(
        "target_project_note_sync_query_unbounded_directive",
        "The exact Project-note stream must sync full scope; paging belongs to local reads.",
      );
    }
  }

  const spaceCoreDetailsFiles = {
    provider: path.join(powerSyncRoot, "SpaceCoreDetailsPowerSyncQuery.swift"),
    providerTests: path.join(powerSyncTestRoot, "SpaceCoreDetailsPowerSyncQueryTests.swift"),
    model: path.join(appModelRoot, "SpaceCoreDetailsStagingExercise.swift"),
    modelTests: path.join(appModelTestRoot, "SpaceCoreDetailsStagingExerciseTests.swift"),
    adapter: path.join(targetAppRoot, "SpaceCoreDetailsStagingRuntimeAdapter.swift"),
    view: path.join(targetAppRoot, "SpaceCoreDetailsStagingExerciseView.swift"),
  };
  for (const filePath of Object.values(spaceCoreDetailsFiles)) {
    if (!fs.existsSync(filePath)) {
      fail("target_space_core_details_leaf_missing", relative(filePath));
    }
  }
  if (Object.values(spaceCoreDetailsFiles).every(fs.existsSync)) {
    const provider = fs.readFileSync(spaceCoreDetailsFiles.provider, "utf8");
    const model = fs.readFileSync(spaceCoreDetailsFiles.model, "utf8");
    const adapter = fs.readFileSync(spaceCoreDetailsFiles.adapter, "utf8");
    const view = fs.readFileSync(spaceCoreDetailsFiles.view, "utf8");
    const runtimePath = path.join(powerSyncRoot, "LedgerOfflineClientRuntime.swift");
    const runtime = fs.readFileSync(runtimePath, "utf8");
    const syncPath = path.join(repositoryRoot, "powersync/sync-streams.yaml");
    const sync = fs.existsSync(syncPath) ? fs.readFileSync(syncPath, "utf8") : "";
    const syncSection = sync.match(
      /^  space_core_details:\n([\s\S]*?)(?=^  [a-z][a-z0-9_]*:\n|(?![\s\S]))/m,
    )?.[0] ?? "";
    for (const required of [
      "SpaceCoreDetailsQuerying",
      "SpaceCoreDetailsLocalReading",
      "space_core_details",
      "LedgerPowerSyncTable.spaceCoreDetails",
      "LedgerPowerSyncTable.spaceChecklists",
      "LedgerPowerSyncTable.spaceChecklistItems",
      "cancelAndDrainWatches()",
    ]) {
      if (!provider.includes(required)) {
        fail("target_space_core_details_provider_incomplete", required);
      }
    }
    if (/public\s+(?:final\s+)?class\s+SpaceCoreDetailsPowerSyncQuery/.test(provider)) {
      fail("target_space_core_details_provider_public", relative(spaceCoreDetailsFiles.provider));
    }
    if (!/public\s+func\s+watchSpaceCoreDetails\s*\(\s*spaceId:\s*SpaceID/.test(runtime)) {
      fail("target_space_core_details_runtime_facade_missing", relative(runtimePath));
    }
    for (const required of [
      "generation",
      "oldTask?.cancel()",
      "await oldTask?.value",
      "update.validating(request: request)",
      "progressCountsAreAuthoritative",
    ]) {
      if (!model.includes(required)) {
        fail("target_space_core_details_presenter_incomplete", required);
      }
    }
    if (!adapter.includes("runtime.watchSpaceCoreDetails(spaceId: spaceId)")) {
      fail("target_space_core_details_adapter_incomplete", relative(spaceCoreDetailsFiles.adapter));
    }
    if (/PowerSync|SQL|Supabase|Firebase|Firestore|credential|authorization/i.test(model)) {
      fail("target_space_core_details_model_boundary_escape", relative(spaceCoreDetailsFiles.model));
    }
    if (/PowerSyncDatabaseProtocol|\bSQL\b|Supabase|Firebase|Firestore|credential|authorization/i.test(adapter)) {
      fail("target_space_core_details_adapter_boundary_escape", relative(spaceCoreDetailsFiles.adapter));
    }
    if (/\bButton\s*\(|SpaceDetailView|MCP|Firebase|Firestore|Supabase|PowerSyncDatabaseProtocol|\bSQL\b/.test(view)) {
      fail("target_space_core_details_view_scope_escape", relative(spaceCoreDetailsFiles.view));
    }
    if (
      !view.includes("if model.progressCountsAreAuthoritative") ||
      !view.includes("target-space-core-details-progress-incomplete")
    ) {
      fail(
        "target_space_core_details_incomplete_progress_exposed",
        "Checklist counts must be withheld when local hierarchy completeness is unknown",
      );
    }
    for (const required of [
      "space_core_details:",
      "subscription.parameter('account_id')",
      "subscription.parameter('space_id')",
      "principal.auth_user_id = auth.user_id()",
      "membership.state = 'active'",
      "FROM spike_spaces AS space",
      "FROM spike_space_core_details AS detail",
      "FROM spike_space_checklists AS checklist",
      "FROM spike_space_checklist_items AS item",
    ]) {
      if (!syncSection.includes(required)) {
        fail("target_space_core_details_sync_scope_incomplete", required);
      }
    }
    if ((syncSection.match(/^      - \|$/gm) ?? []).length !== 4) {
      fail("target_space_core_details_sync_query_count", "expected four relation queries");
    }
    if (/space\.lifecycle\s*=|project\.lifecycle\s*=/.test(syncSection)) {
      fail("target_space_core_details_lifecycle_filter", "exact detail cannot exclude archived Space or Project evidence");
    }
    for (const required of [
      "SpaceCoreDetailsStagingExerciseView(model: model.spaceDetails)",
      "SpaceCoreDetailsStagingRuntimeAdapter(runtime)",
      "syntheticSpaceId",
    ]) {
      if (!stagingAppSource.includes(required)) {
        fail("target_space_core_details_staging_missing", required);
      }
    }
    for (const fileName of [
      "SpaceCoreDetailsStagingRuntimeAdapter.swift",
      "SpaceCoreDetailsStagingExerciseView.swift",
    ]) {
      if (!project.includes(fileName)) {
        fail("target_space_core_details_project_membership_missing", fileName);
      }
    }
    const mcpSource = filesWithExtension(
      path.join(repositoryRoot, "LedgerTargetMCP", "src"),
      ".ts",
    ).map((filePath) => fs.readFileSync(filePath, "utf8")).join("\n");
    if (/spaceCoreDetails|space_core_details|SpaceCoreDetails/.test(mcpSource)) {
      fail("target_space_core_details_mcp_escape", "Space details remain outside MCP in this slice");
    }
  }

  const runtimeAdapterPath = path.join(
    targetAppRoot,
    "ProjectSetupStagingRuntimeAdapter.swift",
  );
  if (!fs.existsSync(runtimeAdapterPath)) {
    fail("target_project_setup_adapter_missing", relative(runtimeAdapterPath));
  } else {
    const adapter = fs.readFileSync(runtimeAdapterPath, "utf8");
    for (const required of [
      "import LedgerTargetAppModel",
      "import LedgerTargetPowerSync",
      "runtime.watchClients()",
      "runtime.watchBudgetCategories()",
      "runtime.createProject(command)",
    ]) {
      if (!adapter.includes(required)) {
        fail("target_project_setup_adapter_incomplete", required);
      }
    }
  }
  const projectBrowsingAdapterPath = path.join(
    targetAppRoot,
    "ProjectBrowsingStagingRuntimeAdapter.swift",
  );
  if (!fs.existsSync(projectBrowsingAdapterPath)) {
    fail(
      "target_project_browsing_adapter_missing",
      relative(projectBrowsingAdapterPath),
    );
  } else {
    const adapter = fs.readFileSync(projectBrowsingAdapterPath, "utf8");
    for (const required of [
      "import LedgerTargetAppModel",
      "import LedgerTargetPowerSync",
      "runtime.watchProjects()",
      "runtime.watchProject(request)",
      "runtime.watchProjectNotes(request)",
    ]) {
      if (!adapter.includes(required)) {
        fail("target_project_browsing_adapter_incomplete", required);
      }
    }
  }
  const projectArchiveAdapterPath = path.join(
    targetAppRoot,
    "ProjectArchiveBrowserStagingRuntimeAdapter.swift",
  );
  if (!fs.existsSync(projectArchiveAdapterPath)) {
    fail(
      "target_project_archive_adapter_missing",
      relative(projectArchiveAdapterPath),
    );
  } else {
    const adapter = fs.readFileSync(projectArchiveAdapterPath, "utf8");
    for (const required of [
      "import LedgerTargetAppModel",
      "import LedgerTargetPowerSync",
      "runtime.archive($0)",
      "runtime.watchOperation($0)",
    ]) {
      if (!adapter.includes(required)) {
        fail("target_project_archive_adapter_incomplete", required);
      }
    }
    if (
      /import LedgerTargetCore|PowerSyncDatabaseProtocol|\bSQL\b|Supabase|URLSession/.test(
        adapter,
      )
    ) {
      fail(
        "target_project_archive_adapter_scope_escape",
        relative(projectArchiveAdapterPath),
      );
    }
  }
  const clientBrowsingAdapterPath = path.join(
    targetAppRoot,
    "ClientBrowsingStagingRuntimeAdapter.swift",
  );
  if (!fs.existsSync(clientBrowsingAdapterPath)) {
    fail(
      "target_client_browsing_adapter_missing",
      relative(clientBrowsingAdapterPath),
    );
  } else {
    const adapter = fs.readFileSync(clientBrowsingAdapterPath, "utf8");
    for (const required of [
      "import LedgerTargetAppModel",
      "import LedgerTargetPowerSync",
      "runtime.watchClients()",
      "runtime.watchClient(request)",
    ]) {
      if (!adapter.includes(required)) {
        fail("target_client_browsing_adapter_incomplete", required);
      }
    }
  }
  const clientArchiveAdapterPath = path.join(
    targetAppRoot,
    "ClientArchiveBrowserStagingRuntimeAdapter.swift",
  );
  if (!fs.existsSync(clientArchiveAdapterPath)) {
    fail(
      "target_client_archive_adapter_missing",
      relative(clientArchiveAdapterPath),
    );
  } else {
    const adapter = fs.readFileSync(clientArchiveAdapterPath, "utf8");
    for (const required of [
      "import LedgerTargetAppModel",
      "import LedgerTargetPowerSync",
      "runtime.archive($0)",
      "runtime.watchClientArchiveOperation($0)",
    ]) {
      if (!adapter.includes(required)) {
        fail("target_client_archive_adapter_incomplete", required);
      }
    }
    if (
      /import LedgerTargetCore|PowerSyncDatabaseProtocol|\bSQL\b|Supabase|URLSession/.test(
        adapter,
      )
    ) {
      fail(
        "target_client_archive_adapter_scope_escape",
        relative(clientArchiveAdapterPath),
      );
    }
  }
  const clientArchiveStorePath = path.join(
    powerSyncRoot,
    "ClientArchivePowerSyncStore.swift",
  );
  if (!fs.existsSync(clientArchiveStorePath)) {
    fail("target_client_archive_store_missing", relative(clientArchiveStorePath));
  } else if (
    /\b(?:print|debugPrint|dump|NSLog)\s*\(/.test(
      fs.readFileSync(clientArchiveStorePath, "utf8"),
    )
  ) {
    fail(
      "target_client_archive_sensitive_debug_logging",
      relative(clientArchiveStorePath),
    );
  }
  const clientBrowsingViewPath = path.join(
    targetAppRoot,
    "ClientBrowsingStagingExerciseView.swift",
  );
  if (!fs.existsSync(clientBrowsingViewPath)) {
    fail(
      "target_client_browsing_view_missing",
      relative(clientBrowsingViewPath),
    );
  } else if (
    fs
      .readFileSync(clientBrowsingViewPath, "utf8")
      .includes("import LedgerTargetPowerSync")
  ) {
    fail(
      "target_client_browsing_view_provider_contamination",
      relative(clientBrowsingViewPath),
    );
  }
  for (const forbiddenInlineClientBrowsing of [
    "ClientDirectoryPresentationProjector.project(",
    "ClientDetailPresentationProjector.project(",
    "activeClientDirectory",
    "archivedClientDirectory",
    "clientDetailsTask",
  ]) {
    if (stagingAppSource.includes(forbiddenInlineClientBrowsing)) {
      fail(
        "target_client_browsing_inline_ownership",
        forbiddenInlineClientBrowsing,
      );
    }
  }
  for (const requiredClientBrowsingWiring of [
    "ClientBrowsingStagingExerciseView(",
    "model: model.clientBrowser",
    "archive: model.clientArchive",
    "ClientBrowsingStagingRuntimeAdapter.adapt(runtime)",
    "await clientBrowser.start(",
    "ClientArchiveBrowserStagingRuntimeAdapter.adapt(runtime)",
    "await clientArchive.start(",
  ]) {
    if (!stagingAppSource.includes(requiredClientBrowsingWiring)) {
      fail(
        "target_client_browsing_staging_wiring_incomplete",
        requiredClientBrowsingWiring,
      );
    }
  }
  const projectBrowsingViewPath = path.join(
    targetAppRoot,
    "ProjectBrowsingStagingExerciseView.swift",
  );
  if (!fs.existsSync(projectBrowsingViewPath)) {
    fail(
      "target_project_browsing_view_missing",
      relative(projectBrowsingViewPath),
    );
  } else if (
    fs
      .readFileSync(projectBrowsingViewPath, "utf8")
      .includes("import LedgerTargetPowerSync")
  ) {
    fail(
      "target_project_browsing_view_provider_contamination",
      relative(projectBrowsingViewPath),
    );
  }
  for (const forbiddenInlineProjectBrowsing of [
    "ProjectDirectoryPresentationProjector.project(",
    "ProjectDetailHeaderPresentationProjector.project(",
    "runtime.watchProjects()",
    "runtime.watchProject(request)",
    "activeProjectDirectory",
    "archivedProjectDirectory",
    "projectDetailsTask",
  ]) {
    if (stagingAppSource.includes(forbiddenInlineProjectBrowsing)) {
      fail(
        "target_project_browsing_inline_ownership",
        forbiddenInlineProjectBrowsing,
      );
    }
  }
  for (const requiredProjectBrowsingWiring of [
    "ProjectBrowsingStagingExerciseView(",
    "model: model.projectBrowser",
    "archive: model.projectArchive",
    "ProjectBrowsingStagingRuntimeAdapter.adapt(runtime)",
    "await projectBrowser.start(",
    "ProjectArchiveBrowserStagingRuntimeAdapter.adapt(runtime)",
    "await projectArchive.start(",
  ]) {
    if (!stagingAppSource.includes(requiredProjectBrowsingWiring)) {
      fail(
        "target_project_browsing_staging_wiring_incomplete",
        requiredProjectBrowsingWiring,
      );
    }
  }
  const startBoundary = stagingAppSource.indexOf(
    "func start(validatedEnvironment:",
  );
  const failedCleanupBoundary = stagingAppSource.indexOf(
    "private func closeAfterFailedStart(",
  );
  const createClientBoundary = stagingAppSource.indexOf("func createClient()");
  if (
    startBoundary < 0 ||
    failedCleanupBoundary <= startBoundary ||
    createClientBoundary <= failedCleanupBoundary
  ) {
    fail(
      "target_project_browsing_cleanup_boundary_missing",
      relative(stagingAppPath),
    );
  } else {
    const startBody = stagingAppSource.slice(
      startBoundary,
      failedCleanupBoundary,
    );
    const failedCleanupBody = stagingAppSource.slice(
      failedCleanupBoundary,
      createClientBoundary,
    );
    const stopBeforeClose = (source, closeCall) => {
      const stop = source.indexOf("await projectBrowser.stop()");
      const close = source.indexOf(closeCall);
      return stop >= 0 && close > stop;
    };
    const clientStopBeforeClose = (source, closeCall) => {
      const stop = source.indexOf("await clientBrowser.stop()");
      const close = source.indexOf(closeCall);
      return stop >= 0 && close > stop;
    };
    const archiveStopBeforeClose = (source, closeCall) => {
      const stop = source.indexOf("await projectArchive.stop()");
      const close = source.indexOf(closeCall);
      return stop >= 0 && close > stop;
    };
    const clientArchiveStopBeforeClose = (source, closeCall) => {
      const stop = source.indexOf("await clientArchive.stop()");
      const close = source.indexOf(closeCall);
      return stop >= 0 && close > stop;
    };
    if (!clientStopBeforeClose(startBody, "try await runtime.close()")) {
      fail(
        "target_client_browsing_normal_cleanup_order",
        "Client browsing observations must drain before normal runtime close.",
      );
    }
    if (
      !clientStopBeforeClose(
        failedCleanupBody,
        "try? await openedRuntime.close()",
      )
    ) {
      fail(
        "target_client_browsing_failed_cleanup_order",
        "Client browsing observations must drain before failed-start runtime close.",
      );
    }
    if (!archiveStopBeforeClose(startBody, "try await runtime.close()")) {
      fail(
        "target_project_archive_normal_cleanup_order",
        "Project archive observation must drain before normal runtime close.",
      );
    }
    if (!clientArchiveStopBeforeClose(startBody, "try await runtime.close()")) {
      fail(
        "target_client_archive_normal_cleanup_order",
        "Client archive observation must drain before normal runtime close.",
      );
    }
    if (
      !clientArchiveStopBeforeClose(
        failedCleanupBody,
        "try? await openedRuntime.close()",
      )
    ) {
      fail(
        "target_client_archive_failed_cleanup_order",
        "Client archive observation must drain before failed-start runtime close.",
      );
    }
    if (
      !archiveStopBeforeClose(
        failedCleanupBody,
        "try? await openedRuntime.close()",
      )
    ) {
      fail(
        "target_project_archive_failed_cleanup_order",
        "Project archive observation must drain before failed-start runtime close.",
      );
    }
    if (!stopBeforeClose(startBody, "try await runtime.close()")) {
      fail(
        "target_project_browsing_normal_cleanup_order",
        "Project browsing observations must drain before normal runtime close.",
      );
    }
    if (
      !stopBeforeClose(
        failedCleanupBody,
        "try? await openedRuntime.close()",
      )
    ) {
      fail(
        "target_project_browsing_failed_cleanup_order",
        "Project browsing observations must drain before failed-start runtime close.",
      );
    }
  }
  if (targetAppSource.includes("CreateProjectCommand(")) {
    fail(
      "target_project_setup_direct_command",
      "The target app must submit through ProjectSetupUseCase, not construct CreateProjectCommand.",
    );
  }
  if (targetAppSource.includes("ArchiveProjectCommand(")) {
    fail(
      "target_project_archive_direct_command",
      "The target app must submit through ProjectArchiveUseCase, not construct ArchiveProjectCommand.",
    );
  }
  if (targetAppSource.includes("ArchiveClientCommand(")) {
    fail(
      "target_client_archive_direct_command",
      "The target app must submit through ClientArchiveUseCase, not construct ArchiveClientCommand.",
    );
  }
  for (const forbiddenProjectSetupUI of [
    "Create a new Client",
    "Enable Furnishings budget",
    "category-furnishings",
  ]) {
    if (targetAppSource.includes(forbiddenProjectSetupUI)) {
      fail("target_project_setup_provisional_ui", forbiddenProjectSetupUI);
    }
  }
  for (const requiredProjectSetupUI of [
    '"target-project-name"',
    '"target-project-existing-client"',
    '"target-project-category-\\(category.id.rawValue)"',
    '"target-create-project"',
    '"target-project-client-readiness"',
    '"target-project-category-readiness"',
    '"target-project-diagnostic"',
    '"target-project-receipt"',
  ]) {
    if (!targetAppSource.includes(requiredProjectSetupUI)) {
      fail("target_project_setup_accessibility_incomplete", requiredProjectSetupUI);
    }
  }
  for (const requiredProjectBrowsingUI of [
    '"target-project-directory-status"',
    '"target-project-active-count"',
    '"target-project-archived-count"',
    '"target-project-row-\\(segment.rawValue)-\\(row.projectId.rawValue)"',
    '"target-selected-project-name"',
    '"target-selected-client-name"',
    '"target-project-detail-state"',
    '"target-project-detail-readiness"',
    '"target-project-directory-diagnostic"',
    '"target-project-detail-diagnostic"',
    '"target-project-archive-action"',
    '"target-project-archive-confirm"',
    '"target-project-archive-cancel"',
    '"target-project-archive-state"',
    '"target-project-archive-diagnostic"',
    '"target-project-archive-retry"',
    ".onChange(of: model.selectedProjectArchiveEvidence)",
    "await archive.selectionDidSettle()",
  ]) {
    if (!targetAppSource.includes(requiredProjectBrowsingUI)) {
      fail(
        "target_project_browsing_accessibility_incomplete",
        requiredProjectBrowsingUI,
      );
    }
  }
  for (const requiredClientBrowsingUI of [
    '"target-client-directory-status"',
    '"target-client-active-count"',
    '"target-client-archived-count"',
    '"target-client-row-\\(segment.rawValue)-\\(row.clientId.rawValue)"',
    '"target-client-browser-selected-name"',
    '"target-client-detail-state"',
    '"target-client-detail-readiness"',
    '"target-client-directory-diagnostic"',
    '"target-client-detail-diagnostic"',
    '"target-client-archive-action"',
    '"target-client-archive-confirm"',
    '"target-client-archive-cancel"',
    '"target-client-archive-state"',
    '"target-client-archive-diagnostic"',
    '"target-client-archive-retry"',
    ".onChange(of: model.selectedClientArchiveEvidence)",
    "await archive.selectionDidSettle()",
  ]) {
    if (!targetAppSource.includes(requiredClientBrowsingUI)) {
      fail(
        "target_client_browsing_accessibility_incomplete",
        requiredClientBrowsingUI,
      );
    }
  }
  const createClientSource = createClientBoundary >= 0
    ? stagingAppSource.slice(createClientBoundary)
    : "";
  for (const requiredPostCreateConfirmation of [
    "let request = try ClientCoreDetailsRequest(",
    "for try await update in runtime.watchClient(request)",
    "lastCreatedName =",
  ]) {
    if (!createClientSource.includes(requiredPostCreateConfirmation)) {
      fail(
        "target_client_creation_confirmation_missing",
        requiredPostCreateConfirmation,
      );
    }
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

const categoryRevisionMigrationPath = path.join(
  repositoryRoot,
  "supabase/migrations/20260906014441_project_category_configuration_revision.sql",
);
const powerSyncSchemaPath = path.join(
  powerSyncRoot,
  "LedgerPowerSyncSchema.swift",
);
const projectSetupStorePath = path.join(
  powerSyncRoot,
  "ProjectSetupPowerSyncStore.swift",
);
const syncStreamsPath = path.join(repositoryRoot, "powersync/sync-streams.yaml");
for (const requiredPath of [
  categoryRevisionMigrationPath,
  powerSyncSchemaPath,
  projectSetupStorePath,
  syncStreamsPath,
]) {
  if (!fs.existsSync(requiredPath)) {
    fail("target_project_category_revision_foundation_missing", relative(requiredPath));
  }
}
if (
  [
    categoryRevisionMigrationPath,
    powerSyncSchemaPath,
    projectSetupStorePath,
    syncStreamsPath,
  ].every(fs.existsSync)
) {
  const migration = fs.readFileSync(categoryRevisionMigrationPath, "utf8");
  const schema = fs.readFileSync(powerSyncSchemaPath, "utf8");
  const store = fs.readFileSync(projectSetupStorePath, "utf8");
  const sync = fs.readFileSync(syncStreamsPath, "utf8");
  const projectCategoryDomainPath = path.join(
    coreRoot,
    "ProjectCategoryConfigurationData.swift",
  );
  const projectCategoryDomain = fs.readFileSync(
    projectCategoryDomainPath,
    "utf8",
  );
  for (const required of [
    "add column category_configuration_revision numeric not null default 1",
    "scale(category_configuration_revision) = 0",
    "category_configuration_revision >= 1::numeric",
    "category_configuration_revision <= 18446744073709551615::numeric",
  ]) {
    if (!migration.includes(required)) {
      fail("target_project_category_revision_database_incomplete", required);
    }
  }
  if (
    (schema.match(/\.text\("category_configuration_revision"\)/g) ?? [])
      .length !== 2
  ) {
    fail(
      "target_project_category_revision_local_type",
      "Authoritative and pending Project tables must each store the revision as text.",
    );
  }
  for (const required of [
    "lifecycle, revision, category_configuration_revision,",
    'command.draft.description,\n                        "1",',
  ]) {
    if (!store.includes(required)) {
      fail("target_project_category_revision_pending_incomplete", required);
    }
  }
  if (!projectCategoryDomain.includes("public let configurationRevision: UInt64")) {
    fail(
      "target_project_category_revision_domain_type",
      "Project category-configuration snapshots must expose an exact UInt64 revision.",
    );
  }
  const categoryRevisionProductionFiles = [
    ...swiftFiles(coreRoot),
    ...swiftFiles(powerSyncRoot),
    ...swiftFiles(appModelRoot),
    ...swiftFiles(targetAppRoot),
  ].filter((filePath) =>
    /category_configuration_revision/.test(
      fs.readFileSync(filePath, "utf8"),
    ),
  );
  const allowedCategoryRevisionFiles = new Set([
    powerSyncSchemaPath,
    projectSetupStorePath,
  ]);
  const unexpectedCategoryRevisionFiles = categoryRevisionProductionFiles.filter(
    (filePath) => !allowedCategoryRevisionFiles.has(filePath),
  );
  if (
    categoryRevisionProductionFiles.length !== allowedCategoryRevisionFiles.size ||
    unexpectedCategoryRevisionFiles.length > 0
  ) {
    fail(
      "target_project_category_revision_unreviewed_mapping",
      `Only the frozen Core type, local schema, and literal pending-Project initialization may map the revision in production Swift before the provider boundary: ${unexpectedCategoryRevisionFiles.map(relative).join(", ")}`,
    );
  }

  const streamNames = [
    ...sync.matchAll(/^  ([a-z][a-z0-9_]*):$/gm),
  ].map((match) => match[1]);
  const expectedStreamNames = [
    "spike_account_bootstrap",
    "spike_clients",
    "spike_projects",
    "spike_operation_results",
    "space_assignment_project_destinations",
    "space_assignment_business_inventory_destinations",
    "project_note_history",
    "space_core_details",
  ];
  if (JSON.stringify(streamNames) !== JSON.stringify(expectedStreamNames)) {
    fail(
      "target_project_category_revision_sync_stream_set",
      "The revision foundation must not add, remove, or rename a Sync Stream.",
    );
  }
  const streamSection = (name) =>
    sync.match(
      new RegExp(
        `^  ${name}:\\n[\\s\\S]*?(?=^  [a-z][a-z0-9_]*:\\n|(?![\\s\\S]))`,
        "m",
      ),
    )?.[0] ?? "";
  const broadProjectSection = streamSection("spike_projects");
  const projectNoteSection = streamSection("project_note_history");
  const normalizedQueries = (section) =>
    [...section.matchAll(
      /^      - \|\n([\s\S]*?)(?=^      - \|\n|(?![\s\S]))/gm,
    )].map((match) => match[1].replace(/\s+/g, " ").trim());
  const expectedBroadProjectQueries = [
    "SELECT project.id, project.account_id, project.client_id, project.display_name, project.description, project.lifecycle, project.revision, project.category_configuration_revision::text AS category_configuration_revision, project.created_at_ms, project.updated_at_ms, project.created_by_principal_id FROM spike_projects AS project WHERE project.account_id IN ( SELECT membership.account_id FROM spike_account_memberships AS membership JOIN spike_principals AS principal ON principal.id = membership.principal_id WHERE principal.auth_user_id = auth.user_id() AND membership.state = 'active' )",
    "SELECT category.* FROM spike_budget_categories AS category JOIN spike_account_memberships AS membership ON membership.account_id = category.account_id JOIN spike_principals AS principal ON principal.id = membership.principal_id WHERE principal.auth_user_id = auth.user_id() AND membership.state = 'active' AND ( category.visibility_class = 'ordinary' OR membership.financial_access = 'full' )",
    "SELECT allocation.* FROM spike_project_category_allocations AS allocation JOIN spike_budget_categories AS category ON category.account_id = allocation.account_id AND category.id = allocation.category_id JOIN spike_account_memberships AS membership ON membership.account_id = allocation.account_id JOIN spike_principals AS principal ON principal.id = membership.principal_id WHERE principal.auth_user_id = auth.user_id() AND membership.state = 'active' AND ( category.visibility_class = 'ordinary' OR membership.financial_access = 'full' )",
  ];
  const expectedProjectNoteQueries = [
    "SELECT project.id, project.account_id, project.client_id, project.display_name, project.description, project.lifecycle, project.revision, project.category_configuration_revision::text AS category_configuration_revision, project.created_at_ms, project.updated_at_ms, project.created_by_principal_id FROM spike_projects AS project JOIN spike_account_memberships AS membership ON membership.account_id = project.account_id JOIN spike_principals AS principal ON principal.id = membership.principal_id WHERE project.account_id = subscription.parameter('account_id') AND project.id = subscription.parameter('project_id') AND principal.auth_user_id = auth.user_id() AND membership.state = 'active'",
    "SELECT note.id, note.account_id, note.project_id, note.id AS keyset_id, note.content_kind, note.note_text, note.source, note.created_by_principal_id, note.creator_display_name, note.created_at_ms, note.revision::text AS revision, note.last_edited_by_principal_id, note.last_edited_at_ms, note.deleted_by_principal_id, note.deleted_at_ms FROM spike_project_notes AS note JOIN spike_projects AS project ON project.account_id = note.account_id AND project.id = note.project_id JOIN spike_account_memberships AS membership ON membership.account_id = note.account_id JOIN spike_principals AS principal ON principal.id = membership.principal_id WHERE note.account_id = subscription.parameter('account_id') AND note.project_id = subscription.parameter('project_id') AND principal.auth_user_id = auth.user_id() AND membership.state = 'active'",
  ];
  if (
    JSON.stringify(normalizedQueries(broadProjectSection)) !==
    JSON.stringify(expectedBroadProjectQueries)
  ) {
    fail(
      "target_project_category_revision_sync_broad_exact",
      "The complete three-query Project stream must remain byte-semantically equal after whitespace normalization.",
    );
  }
  if (
    JSON.stringify(normalizedQueries(projectNoteSection)) !==
    JSON.stringify(expectedProjectNoteQueries)
  ) {
    fail(
      "target_project_category_revision_sync_note_exact",
      "The complete two-query Project-note stream must remain byte-semantically equal after whitespace normalization.",
    );
  }
  if (
    (sync.match(
      /project\.category_configuration_revision::text\s+AS category_configuration_revision/g,
    ) ?? []).length !== 2 ||
    /SELECT\s+project\.\*/i.test(sync)
  ) {
    fail(
      "target_project_category_revision_sync_incomplete",
      "Both unchanged-authority Project projections must cast the exact numeric revision to text and neither may use project.*.",
    );
  }
  if (!store.includes('command.draft.description,\n                        "1",')) {
    fail(
      "target_project_category_revision_derived",
      "The only local initialization must remain the reviewed literal generation 1 inside Project acceptance.",
    );
  }
}

const blockedCategoryProviderLeaves = [
  path.join(powerSyncRoot, "ProjectCategoryConfigurationPowerSyncQuery.swift"),
  path.join(powerSyncTestRoot, "ProjectCategoryConfigurationPowerSyncQueryTests.swift"),
  path.join(appModelRoot, "ProjectCategoryConfigurationStagingExercise.swift"),
  path.join(appModelTestRoot, "ProjectCategoryConfigurationStagingExerciseTests.swift"),
  path.join(targetAppRoot, "ProjectCategoryConfigurationStagingRuntimeAdapter.swift"),
  path.join(targetAppRoot, "ProjectCategoryConfigurationStagingExerciseView.swift"),
];
for (const filePath of blockedCategoryProviderLeaves) {
  if (!fs.existsSync(filePath)) {
    fail("target_project_category_blocked_leaf_missing", relative(filePath));
    continue;
  }
  const substantiveLines = fs
    .readFileSync(filePath, "utf8")
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line.length > 0 && !line.startsWith("//"));
  if (substantiveLines.length !== 0) {
    fail(
      "target_project_category_blocked_leaf_executable",
      `${relative(filePath)} must remain comment-only until O-026 and a separate READY boundary are resolved.`,
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
    "LedgerTargetAppModel",
    "LedgerTargetAppModelTests",
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
