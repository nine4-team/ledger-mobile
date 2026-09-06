#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
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

function maskSwiftLexical(source, { strings }) {
  const output = [...source];
  let index = 0;
  let blockDepth = 0;
  let lineComment = false;
  let stringTerminator = null;
  let rawHashes = 0;

  const mask = (position) => {
    if (output[position] !== "\n" && output[position] !== "\r") {
      output[position] = " ";
    }
  };

  while (index < source.length) {
    if (lineComment) {
      if (source[index] === "\n" || source[index] === "\r") {
        lineComment = false;
      } else {
        mask(index);
      }
      index += 1;
      continue;
    }

    if (blockDepth > 0) {
      if (source.startsWith("/*", index)) {
        mask(index);
        mask(index + 1);
        blockDepth += 1;
        index += 2;
      } else if (source.startsWith("*/", index)) {
        mask(index);
        mask(index + 1);
        blockDepth -= 1;
        index += 2;
      } else {
        mask(index);
        index += 1;
      }
      continue;
    }

    if (stringTerminator) {
      if (source.startsWith(stringTerminator, index)) {
        if (strings) {
          for (let offset = 0; offset < stringTerminator.length; offset += 1) {
            mask(index + offset);
          }
        }
        index += stringTerminator.length;
        stringTerminator = null;
        rawHashes = 0;
      } else if (rawHashes === 0 && source[index] === "\\") {
        if (strings) mask(index);
        index += 1;
        if (index < source.length) {
          if (strings) mask(index);
          index += 1;
        }
      } else {
        if (strings) mask(index);
        index += 1;
      }
      continue;
    }

    if (source.startsWith("//", index)) {
      mask(index);
      mask(index + 1);
      lineComment = true;
      index += 2;
      continue;
    }
    if (source.startsWith("/*", index)) {
      mask(index);
      mask(index + 1);
      blockDepth = 1;
      index += 2;
      continue;
    }

    const stringStart = source.slice(index).match(/^(#*)("""|")/);
    if (stringStart) {
      const opener = stringStart[0];
      rawHashes = stringStart[1].length;
      stringTerminator = `${stringStart[2]}${"#".repeat(rawHashes)}`;
      if (strings) {
        for (let offset = 0; offset < opener.length; offset += 1) {
          mask(index + offset);
        }
      }
      index += opener.length;
      continue;
    }

    index += 1;
  }

  if (blockDepth !== 0 || stringTerminator) return null;
  return output.join("");
}

function swiftWithoutComments(source) {
  return maskSwiftLexical(source, { strings: false });
}

function swiftCodeOnly(source) {
  return maskSwiftLexical(source, { strings: true });
}

function swiftFunctionBody(source, signature) {
  const code = swiftCodeOnly(source);
  if (code === null) return null;
  const signatureIndex = code.indexOf(signature);
  if (signatureIndex < 0 || code.indexOf(signature, signatureIndex + 1) >= 0) {
    return null;
  }
  const open = code.indexOf("{", signatureIndex + signature.length);
  if (open < 0) return null;
  let depth = 1;
  for (let index = open + 1; index < code.length; index += 1) {
    if (code[index] === "{") depth += 1;
    if (code[index] === "}") depth -= 1;
    if (depth === 0) return code.slice(open + 1, index);
  }
  return null;
}

function compactSwiftCode(source) {
  const code = swiftCodeOnly(source);
  return code === null ? null : code.replace(/\s+/g, "");
}

function countOccurrences(source, value) {
  return source.split(value).length - 1;
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
    "assignItemsToSpace",
    "captureAttachment",
    "clearItemSpaceAssignments",
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
    "watchItemSpaceAssignmentOperation",
    "watchItemSpaceClearingOperation",
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

  const itemSpaceAssignmentSignatures = [
    ...runtimeSource.matchAll(
      /public\s+func\s+assignItemsToSpace\s*\(\s*_\s+command:\s*AssignItemsToSpaceCommand\s*\)\s*async\s+throws\s*->\s*OperationReceipt\s*\{/g,
    ),
  ];
  if (itemSpaceAssignmentSignatures.length !== 1) {
    fail(
      "target_item_space_assignment_submit_signature",
      "The public runtime must expose exactly one typed Item-to-Space assignment submission.",
    );
  }
  const itemSpaceAssignmentWatchSignatures = [
    ...runtimeSource.matchAll(
      /public\s+func\s+watchItemSpaceAssignmentOperation\s*\(\s*_\s+operationId:\s*OperationID\s*\)\s*->\s*AsyncThrowingStream\s*<\s*OperationSnapshot\s*,\s*Error\s*>\s*\{/g,
    ),
  ];
  if (itemSpaceAssignmentWatchSignatures.length !== 1) {
    fail(
      "target_item_space_assignment_watch_signature",
      "The public runtime must expose exactly one typed assignment-operation watch.",
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
    "ItemSpaceAssignmentPowerSyncStore",
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
  const pendingWorkFiles = {
    model: path.join(
      appModelRoot,
      "AccountPendingWorkStagingExercise.swift",
    ),
    modelTests: path.join(
      appModelTestRoot,
      "AccountPendingWorkStagingExerciseTests.swift",
    ),
    adapter: path.join(
      targetAppRoot,
      "AccountPendingWorkStagingRuntimeAdapter.swift",
    ),
    view: path.join(
      targetAppRoot,
      "AccountPendingWorkStagingExerciseView.swift",
    ),
  };
  for (const filePath of Object.values(pendingWorkFiles)) {
    if (!fs.existsSync(filePath)) {
      fail("target_pending_work_staging_leaf_missing", relative(filePath));
    }
  }
  if (Object.values(pendingWorkFiles).every(fs.existsSync)) {
    const model = fs.readFileSync(pendingWorkFiles.model, "utf8");
    const adapter = fs.readFileSync(pendingWorkFiles.adapter, "utf8");
    const view = fs.readFileSync(pendingWorkFiles.view, "utf8");
    const modelCode = swiftCodeOnly(model);
    const modelWithoutComments = swiftWithoutComments(model);
    const adapterCode = compactSwiftCode(adapter);
    const viewCode = swiftCodeOnly(view);
    const viewWithoutComments = swiftWithoutComments(view);
    const stagingCode = swiftCodeOnly(stagingAppSource);

    if (
      modelCode === null ||
      modelWithoutComments === null ||
      adapterCode === null ||
      viewCode === null ||
      viewWithoutComments === null ||
      stagingCode === null
    ) {
      fail(
        "target_pending_work_lexical_structure_invalid",
        "Pending-work Swift sources must have closed comments and string literals.",
      );
    }

    if (
      /PowerSync|Supabase|Firebase|Firestore|PowerSyncDatabaseProtocol|\bSQL\b|credential|URLSession/.test(
        modelCode ?? "",
      )
    ) {
      fail(
        "target_pending_work_model_boundary_escape",
        relative(pendingWorkFiles.model),
      );
    }
    const pendingRefreshBody = swiftFunctionBody(model, "public func refresh() async");
    const pendingStopBody = swiftFunctionBody(model, "public func stop() async");
    const pendingReadBody = swiftFunctionBody(model, "private func readSummary(");
    const pendingMethodRequirements = [
      [
        "refresh",
        pendingRefreshBody,
        [
          "generationToken = activeGeneration",
          "admittedTasks",
          "retiredTasks.forEach { $0.cancel() }",
          "await retiredTask.value",
          "await task.value",
        ],
      ],
      [
        "stop",
        pendingStopBody,
        [
          "isStopped = true",
          "generationToken = UUID()",
          "runtime = nil",
          "tasks.forEach { $0.cancel() }",
          "await task.value",
          "admittedTasks.removeAll()",
        ],
      ],
      [
        "readSummary",
        pendingReadBody,
        [
          "summary.environment == expectedEnvironment",
          "summary.principalId == expectedPrincipalId",
          "summary.accountId == expectedAccountId",
          "summary.hasBlockingWork",
          "generationToken == generation",
        ],
      ],
    ];
    for (const [method, body, requirements] of pendingMethodRequirements) {
      if (body === null) {
        fail("target_pending_work_model_method_boundary", method);
        continue;
      }
      for (const required of requirements) {
        if (!body.includes(required)) {
          fail("target_pending_work_model_incomplete", `${method}: ${required}`);
        }
      }
    }
    if (
      !/public\s+func\s+pendingWorkSummary\s*\(\s*\)\s*async\s+throws\s*->\s*PendingLocalWorkSummary/.test(
        modelCode ?? "",
      )
    ) {
      fail(
        "target_pending_work_port_not_argument_free",
        relative(pendingWorkFiles.model),
      );
    }
    const exactAdapter = [
      "importLedgerTargetAppModel",
      "importLedgerTargetPowerSync",
      "enumAccountPendingWorkStagingRuntimeAdapter{",
      "staticfuncadapt(_runtime:LedgerOfflineClientRuntime)",
      "->AccountPendingWorkStagingRuntime{",
      "AccountPendingWorkStagingRuntime(",
      "pendingWorkSummary:{tryawaitruntime.pendingWorkSummary()}",
      ")}}",
    ].join("");
    if (adapterCode !== exactAdapter) {
      fail(
        "target_pending_work_adapter_incomplete",
        "The staging adapter must be the exact one-call pendingWorkSummary forwarding boundary.",
      );
    }
    if (
      /import LedgerTargetCore|PowerSyncDatabaseProtocol|\bSQL\b|Supabase|Firebase|Firestore|credential|URLSession/.test(
        adapterCode ?? "",
      )
    ) {
      fail(
        "target_pending_work_adapter_scope_escape",
        relative(pendingWorkFiles.adapter),
      );
    }
    for (const required of [
      'Section("Pending Local Work")',
      'Button("Refresh")',
      '"Queued operations"',
      '"Applying operations"',
      '"Unresolved rejected operations"',
      '"Unverified attachments"',
      'target-pending-work-status',
      'target-pending-work-refresh',
      'target-pending-work-queued-count',
      'target-pending-work-applying-count',
      'target-pending-work-rejected-count',
      'target-pending-work-attachment-count',
      'target-pending-work-diagnostic',
    ]) {
      if (!(viewWithoutComments ?? "").includes(required)) {
        fail("target_pending_work_view_incomplete", required);
      }
    }
    if (
      /LedgerTargetPowerSync|PowerSync|Supabase|Firebase|Firestore|\bSQL\b/i.test(
        viewCode ?? "",
      )
    ) {
      fail(
        "target_pending_work_view_scope_escape",
        relative(pendingWorkFiles.view),
      );
    }
    if (
      /PowerSync|Supabase|Firebase|Firestore|\bSQL\b|credential|\bsynced\b|\buploaded\b|remote(?:ly)? durable|safe to log out/i.test(
        `${modelWithoutComments ?? ""}\n${viewWithoutComments ?? ""}`,
      )
    ) {
      fail(
        "target_pending_work_copy_overclaim",
        "Pending-work presentation copy must not claim sync, upload, remote durability, or logout safety.",
      );
    }
    for (const fileName of [
      "AccountPendingWorkStagingRuntimeAdapter.swift",
      "AccountPendingWorkStagingExerciseView.swift",
    ]) {
      if (!project.includes(fileName)) {
        fail("target_pending_work_project_membership_missing", fileName);
      }
    }
    for (const required of [
      "AccountPendingWorkStagingExerciseView(model: pendingWork)",
    ]) {
      if (!(stagingCode ?? "").includes(required)) {
        fail("target_pending_work_staging_wiring_incomplete", required);
      }
    }
    const pendingWorkStartBody = swiftFunctionBody(
      stagingAppSource,
      "func start(validatedEnvironment:",
    );
    const compactPendingWorkStartBody =
      pendingWorkStartBody === null
        ? null
        : pendingWorkStartBody.replace(/\s+/g, "");
    if (
      compactPendingWorkStartBody === null ||
      countOccurrences(
        compactPendingWorkStartBody,
        [
          "pendingWork=AccountPendingWorkStagingExercise(",
          "expectedEnvironment:validatedEnvironment.manifest.environment,",
          "expectedPrincipalId:principalId,",
          "expectedAccountId:accountId,",
          "runtime:AccountPendingWorkStagingRuntimeAdapter.adapt(runtime)",
          ")",
        ].join(""),
      ) !== 1
    ) {
      fail(
        "target_pending_work_staging_construction_boundary",
        "Every runtime opening must construct exactly one fresh pending-work child inside start.",
      );
    }
    for (const source of [modelCode ?? "", adapterCode ?? "", viewCode ?? ""]) {
      if (
        /SessionEndDisposition|removeFromDevice|signOut\s*\(|logout\s*\(|delete\w*\s*\(|upload\w*\s*\(|synchroni[sz]e\w*\s*\(|\.close\s*\(/i.test(
          source,
        )
      ) {
        fail(
          "target_pending_work_forbidden_action",
          "Pending-work staging leaves may only read and present local status.",
        );
      }
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
    const pendingWorkStopBeforeClose = (signature, compactCloseCall) => {
      const body = swiftFunctionBody(stagingAppSource, signature);
      if (body === null) return false;
      const compactBody = body.replace(/\s+/g, "");
      const captureCall = "letpendingWork=self.pendingWork";
      const removeCall = "self.pendingWork=nil";
      const stopCall = "awaitpendingWork?.stop()";
      if (
        countOccurrences(compactBody, captureCall) !== 1 ||
        countOccurrences(compactBody, removeCall) !== 1 ||
        countOccurrences(compactBody, stopCall) !== 1 ||
        countOccurrences(compactBody, compactCloseCall) !== 1
      ) {
        return false;
      }
      const capture = compactBody.indexOf(captureCall);
      const remove = compactBody.indexOf(removeCall);
      const stop = compactBody.indexOf(stopCall);
      const close = compactBody.indexOf(compactCloseCall);
      return capture >= 0 && remove > capture && stop > remove && close > stop;
    };
    if (
      !pendingWorkStopBeforeClose(
        "func start(validatedEnvironment:",
        "tryawaitruntime.close()",
      )
    ) {
      fail(
        "target_pending_work_normal_cleanup_order",
        "The per-runtime pending-work child must leave UI and drain before normal runtime close.",
      );
    }
    if (
      !pendingWorkStopBeforeClose(
        "private func closeAfterFailedStart(",
        "try?awaitopenedRuntime.close()",
      )
    ) {
      fail(
        "target_pending_work_failed_cleanup_order",
        "The per-runtime pending-work child must leave UI and drain before failed-start runtime close.",
      );
    }
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

const localOperationGuardPath = path.join(
  powerSyncRoot,
  "LocalOperationIdentityGuard.swift",
);
const localOperationGuardTestsPath = path.join(
  powerSyncTestRoot,
  "LocalOperationIdentityGuardTests.swift",
);
const localOperationAcceptingStores = [
  ["ClientCreationPowerSyncStore", "ClientCreationPowerSyncStore.swift", "createClient"],
  ["ProjectSetupPowerSyncStore", "ProjectSetupPowerSyncStore.swift", "createProject"],
  ["ProjectArchivePowerSyncStore", "ProjectArchivePowerSyncStore.swift", "archiveProject"],
  ["ClientArchivePowerSyncStore", "ClientArchivePowerSyncStore.swift", "archiveClient"],
  ["ItemSpaceAssignmentPowerSyncStore", "ItemSpaceAssignmentPowerSyncStore.swift", "assignItemsToSpace"],
  ["ItemSpaceClearingPowerSyncStore", "ItemSpaceClearingPowerSyncStore.swift", "clearItemSpaceAssignments"],
];
if (!fs.existsSync(localOperationGuardPath) || !fs.existsSync(localOperationGuardTestsPath)) {
  fail("target_local_operation_identity_guard_missing", "guard or executable test leaf");
} else {
  const guardSource = fs.readFileSync(localOperationGuardPath, "utf8");
  const guardCode = swiftWithoutComments(guardSource);
  const guardCompact = (guardCode ?? "").replace(/\s+/g, "");
  const guardTests = fs.readFileSync(localOperationGuardTestsPath, "utf8");
  const familyCases = [
    'casecreateClient="create_client"',
    'casecreateProject="create_project"',
    'casearchiveProject="archive_project"',
    'casearchiveClient="archive_client"',
    'caseassignItemsToSpace="assign_items_to_space"',
    'caseclearItemSpaceAssignments="clear_item_space_assignments"',
  ];
  for (const familyCase of familyCases) {
    if (!guardCompact.includes(familyCase)) {
      fail("target_local_operation_identity_family_inventory", familyCase);
    }
  }
  const relationBlock = guardCompact.match(
    /staticletoperationBearingRelations=\[([^\]]*)\]/,
  )?.[1] ?? "";
  const expectedRelations = [
    "localOperations", "operationResults", "pendingClients", "pendingProjects",
    "pendingProjectCategoryAllocations", "projectArchiveOverlays",
    "clientArchiveOverlays", "itemSpaceAssignmentCommands",
    "itemSpaceClearingCommands",
  ];
  const registeredRelations = [
    ...relationBlock.matchAll(/LedgerPowerSyncTable\.([A-Za-z]+)/g),
  ].map((match) => match[1]);
  if (JSON.stringify(registeredRelations) !== JSON.stringify(expectedRelations)) {
    fail("target_local_operation_identity_relation_inventory", registeredRelations.join(","));
  }
  const expectedInsertOnly = [
    "clientCommands", "projectCommands", "projectArchiveCommands", "clientArchiveCommands",
  ];
  const insertOnlyBlock = guardCompact.match(
    /staticletinsertOnlyCommandTables=\[([^\]]*)\]/,
  )?.[1] ?? "";
  const registeredInsertOnly = [
    ...insertOnlyBlock.matchAll(/LedgerPowerSyncTable\.([A-Za-z]+)/g),
  ].map((match) => match[1]);
  if (JSON.stringify(registeredInsertOnly) !== JSON.stringify(expectedInsertOnly)) {
    fail("target_local_operation_identity_ps_crud_inventory", registeredInsertOnly.join(","));
  }
  if (
    !guardCompact.includes(
      "staticletforbiddenMutationTables=[LedgerPowerSyncTable.operationResults]",
    ) ||
    !guardCompact.includes("FROMps_crud") ||
    !guardCompact.includes("LedgerPowerSyncTable.operationResults")
  ) {
    fail("target_local_operation_identity_result_mutation_guard", relative(localOperationGuardPath));
  }
  const providerBlock = guardCompact.match(
    /staticletacceptingProviders=\[([^\]]*)\]/,
  )?.[1] ?? "";
  const registeredProviders = [...providerBlock.matchAll(/"([A-Za-z]+)"/g)]
    .map((match) => match[1]);
  const expectedProviders = localOperationAcceptingStores.map(([name]) => name);
  if (JSON.stringify(registeredProviders) !== JSON.stringify(expectedProviders)) {
    fail("target_local_operation_identity_provider_inventory", registeredProviders.join(","));
  }
  for (const [provider, file, family] of localOperationAcceptingStores) {
    const storePath = path.join(powerSyncRoot, file);
    const source = fs.readFileSync(storePath, "utf8");
    const code = (swiftWithoutComments(source) ?? "").replace(/\s+/g, "");
    const guardIndex = code.indexOf("LocalOperationIdentityGuard.inspect(");
    const firstWriteIndex = code.indexOf("INSERTINTO");
    if (
      guardIndex < 0 || firstWriteIndex < 0 || guardIndex >= firstWriteIndex ||
      !code.includes(`expectedFamily:.${family}`) ||
      !code.includes("writeTransaction{transactionin")
    ) {
      fail("target_local_operation_identity_guard_before_write", provider);
    }
  }
  for (const [file, family] of [
    ["ClientCreationPowerSyncStore.swift", "create_client"],
    ["ProjectSetupPowerSyncStore.swift", "create_project"],
  ]) {
    const code = (swiftWithoutComments(
      fs.readFileSync(path.join(powerSyncRoot, file), "utf8"),
    ) ?? "").replace(/\s+/g, "");
    if (
      !code.includes(`'${family}'`) ||
      !code.includes("command_envelope_json") ||
      !code.includes("envelopeJSON")
    ) {
      fail("target_local_operation_identity_creation_owner_evidence", file);
    }
  }
  if (/spike_local_operation_(?:owner|ownership|registry)/i.test(guardCode ?? "")) {
    fail("target_local_operation_identity_second_registry", relative(localOperationGuardPath));
  }
  for (const id of Array.from({ length: 12 }, (_, index) =>
    `LOCALOPID-TEST-${String(index + 1).padStart(3, "0")}`)) {
    if (!guardTests.includes(id)) {
      fail("target_local_operation_identity_test_id_missing", id);
    }
  }
  for (const testFunction of [
    "exactInventoryAndInsertOnlyRepresentation", "orderedFamilyMatrix",
    "orphanInventoryMatrix", "terminalAndLegacyClassification",
    "concurrentClaims", "checkpointAtomicityAndCancellation",
    "encryptedRestartStability", "privacyAndNoMutation",
    "ownerAndAuxiliaryTamperMatrix",
  ]) {
    if (swiftFunctionBody(guardTests, `func ${testFunction}(`) === null) {
      fail("target_local_operation_identity_executable_test_missing", testFunction);
    }
  }
  const orphanBody = swiftFunctionBody(guardTests, "func orphanInventoryMatrix(") ?? "";
  for (const proof of [
    "for destination in LocalOperationCommandFamily.allCases",
    "insertSynchronizedResult(",
  ]) {
    if (!orphanBody.includes(proof)) {
      fail("target_local_operation_identity_orphan_matrix_incomplete", proof);
    }
  }
  for (const proof of [
    '["operation", "synchronized_result"]', "result_mutation_queue",
    "orphan-invalid-json",
  ]) {
    if (!guardTests.includes(proof)) {
      fail("target_local_operation_identity_orphan_matrix_incomplete", proof);
    }
  }
  const concurrencyBody = swiftFunctionBody(guardTests, "func concurrentClaims(") ?? "";
  for (const proof of [
    "submitRaceOutcome(",
    "ProjectArchivePowerSyncFailure.invalidOperationIdentity",
    "ClientArchivePowerSyncFailure.invalidOperationIdentity",
    "expectOneCompleteGraph(",
  ]) {
    if (!concurrencyBody.includes(proof)) {
      fail("target_local_operation_identity_concurrency_matrix_incomplete", proof);
    }
  }
  if (!guardTests.includes('outcomes.filter { $0 == "payloadMismatch" }.count == 1')) {
    fail("target_local_operation_identity_concurrency_matrix_incomplete", "payloadMismatch");
  }
  const changedSubmissionBody = swiftFunctionBody(
    guardTests, "func submitChanged(",
  ) ?? "";
  for (const family of [
    "ClientCreationPowerSyncStore", "ProjectSetupPowerSyncStore",
    "ProjectArchivePowerSyncStore", "ClientArchivePowerSyncStore",
    "ItemSpaceAssignmentPowerSyncStore",
    "ItemSpaceClearingPowerSyncStore",
  ]) {
    if (!changedSubmissionBody.includes(family)) {
      fail("target_local_operation_identity_changed_race_incomplete", family);
    }
  }
  const terminalHelper = swiftFunctionBody(
    guardTests, "func verifyCreationTerminalReconciliation(",
  ) ?? "";
  if (
    countOccurrences(
      terminalHelper, "PowerSyncOverlayReconciler.reconcileClient(",
    ) < 2 ||
    countOccurrences(
      terminalHelper, "PowerSyncOverlayReconciler.reconcileProjectCore(",
    ) < 2
  ) {
    fail(
      "target_local_operation_identity_terminal_matrix_incomplete",
      "applied and rejected authoritative reconciliation",
    );
  }
  for (const proof of [
    "PowerSyncOverlayReconciler.reconcileClient(",
    "PowerSyncOverlayReconciler.reconcileProjectCore(",
    "insertCreationResult(",
    ".localState == .rejected", ".localState == .applied",
  ]) {
    if (!terminalHelper.includes(proof)) {
      fail("target_local_operation_identity_terminal_matrix_incomplete", proof);
    }
  }
  for (const proof of [
    "client_created", "project_created", "unknown_rejection",
    "$.request_sha256", "$.client_created_at_ms",
  ]) {
    if (!guardTests.includes(proof)) {
      fail("target_local_operation_identity_result_tamper_matrix_incomplete", proof);
    }
  }
  for (const proof of [
    "requestSHA256 == nil",
    "clientCreatedAt == operation.clientCreatedAtMilliseconds",
    "clientCreationRejectionCodes", "projectCreationRejectionCodes",
  ]) {
    if (!guardCode.includes(proof)) {
      fail("target_local_operation_identity_creation_result_validation", proof);
    }
  }
  const checkpointBody = swiftFunctionBody(
    guardTests, "func checkpointAtomicityAndCancellation(",
  ) ?? "";
  const rawFailureBody = swiftFunctionBody(
    guardTests, "func verifyBoundedRawErrorMapping(",
  ) ?? "";
  if (
    !checkpointBody.includes("verifyBoundedRawErrorMapping()") ||
    !rawFailureBody.includes("LocalOperationGuardInjectedFailure()") ||
    !rawFailureBody.includes("ClientCreationFailure.localAcceptanceFailed") ||
    !rawFailureBody.includes("ProjectSetupFailure.localAcceptanceFailed") ||
    !rawFailureBody.includes("ProjectArchiveFailure.localAcceptanceFailed") ||
    !rawFailureBody.includes("ClientArchiveFailure.localAcceptanceFailed") ||
    !rawFailureBody.includes("ItemSpaceAssignmentFailure.localAcceptanceFailed")
    || !rawFailureBody.includes("ItemSpaceClearingFailure.localAcceptanceFailed")
  ) {
    fail("target_local_operation_identity_failure_mapping_incomplete", "six providers");
  }
  const malformedFailureBody = swiftFunctionBody(
    guardTests, "func verifyMalformedGuardErrorMapping(",
  ) ?? "";
  for (const proof of [
    "ClientCreationFailure.localAcceptanceFailed",
    "ProjectSetupFailure.localAcceptanceFailed",
    "ProjectArchivePowerSyncFailure.malformedLocalEvidence",
    "ClientArchivePowerSyncFailure.malformedLocalEvidence",
    "ItemSpaceAssignmentPowerSyncStoreFailure.malformedLocalEvidence",
    "ItemSpaceClearingPowerSyncStoreFailure.malformedLocalEvidence",
  ]) {
    if (!malformedFailureBody.includes(proof)) {
      fail("target_local_operation_identity_guard_mapping_incomplete", proof);
    }
  }
  const restartBody = swiftFunctionBody(
    guardTests, "func encryptedRestartStability(",
  ) ?? "";
  for (const proof of [
    "insertSynchronizedResult(",
    "reservationCounts(database) == baselineCounts",
  ]) {
    if (!restartBody.includes(proof)) {
      fail("target_local_operation_identity_restart_matrix_incomplete", proof);
    }
  }
  for (const proof of [
    '["pending_client", "pending_project", "pending_allocation",',
    '"project_overlay", "client_overlay", "result_mutation",',
    '"result_mutation_queue"]',
    "restart-invalid-json", "restart-multiple-family", "unknown-type",
    "malformed-envelope", "foreign-scope",
  ]) {
    if (!guardTests.includes(proof)) {
      fail("target_local_operation_identity_restart_matrix_incomplete", proof);
    }
  }
  if (!restartBody.includes("for family in LocalOperationCommandFamily.allCases")) {
    fail("target_local_operation_identity_restart_matrix_incomplete", "all command families");
  }
  const resolved = JSON.parse(
    fs.readFileSync(path.join(packageRoot, "Package.resolved"), "utf8"),
  );
  const corePin = resolved.pins?.find(
    (pin) => pin.identity === "powersync-sqlite-core-swift",
  );
  if (
    corePin?.state?.version !== "0.5.3" ||
    corePin?.state?.revision !== "0302873677f07039d5e2fc4d1aefdf093e8e6292"
  ) {
    fail("target_local_operation_identity_powersync_core_pin", JSON.stringify(corePin?.state));
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

const itemSpaceAssignmentStorePath = path.join(
  powerSyncRoot,
  "ItemSpaceAssignmentPowerSyncStore.swift",
);
const itemSpaceAssignmentTestsPath = path.join(
  powerSyncTestRoot,
  "ItemSpaceAssignmentPowerSyncStoreTests.swift",
);
for (const requiredPath of [
  itemSpaceAssignmentStorePath,
  itemSpaceAssignmentTestsPath,
]) {
  if (!fs.existsSync(requiredPath)) {
    fail("target_item_space_assignment_local_leaf_missing", relative(requiredPath));
  }
}
if (
  fs.existsSync(itemSpaceAssignmentStorePath) &&
  fs.existsSync(itemSpaceAssignmentTestsPath) &&
  fs.existsSync(powerSyncSchemaPath)
) {
  const store = fs.readFileSync(itemSpaceAssignmentStorePath, "utf8");
  const tests = fs.readFileSync(itemSpaceAssignmentTestsPath, "utf8");
  const schema = fs.readFileSync(powerSyncSchemaPath, "utf8");
  const itemSpaceAssignmentRuntime = fs.readFileSync(
    accountWorkspaceRuntimePath,
    "utf8",
  );
  const itemSpaceAssignmentCoordinator = fs.readFileSync(
    accountWorkspaceCoordinatorPath,
    "utf8",
  );
  const storeWithoutComments = swiftWithoutComments(store);
  const schemaWithoutComments = swiftWithoutComments(schema);
  const testsWithoutComments = swiftWithoutComments(tests);
  const coordinatorCode = compactSwiftCode(itemSpaceAssignmentCoordinator);
  const runtimeCode = compactSwiftCode(itemSpaceAssignmentRuntime);
  if (
    storeWithoutComments === null ||
    schemaWithoutComments === null ||
    testsWithoutComments === null ||
    coordinatorCode === null ||
    runtimeCode === null
  ) {
    fail(
      "target_item_space_assignment_lexical_structure_invalid",
      "Assignment store and runtime sources must have closed comments and string literals.",
    );
  }
  if (
    !(schemaWithoutComments ?? "").includes(
      'public static let itemSpaceAssignmentCommands = "spike_item_space_assignment_commands"',
    )
  ) {
    fail(
      "target_item_space_assignment_local_table_name",
      "The local command table name must remain exact.",
    );
  }
  const tableStart = (schemaWithoutComments ?? "").indexOf(
    "Table(\n            name: LedgerPowerSyncTable.itemSpaceAssignmentCommands,",
  );
  const tableEnd = tableStart < 0
    ? -1
    : (schemaWithoutComments ?? "").indexOf("\n        Table(", tableStart + 1);
  const tableSection = tableStart < 0 || tableEnd < 0
    ? ""
    : (schemaWithoutComments ?? "").slice(tableStart, tableEnd);
  const actualColumns = [
    ...tableSection.matchAll(/\.(text|integer)\("([^"]+)"\)/g),
  ].map((match) => `${match[1]}:${match[2]}`);
  const expectedColumns = [
    "text:account_id",
    "text:actor_principal_id",
    "text:contract_version",
    "text:destination_space_id",
    "text:scope_kind",
    "text:project_id",
    "text:expected_space_revision",
    "text:items_json",
    "text:fingerprint",
    "text:command_json",
    "integer:accepted_at_ms",
  ];
  if (JSON.stringify(actualColumns) !== JSON.stringify(expectedColumns)) {
    fail(
      "target_item_space_assignment_local_table_columns",
      actualColumns.join(","),
    );
  }
  for (const required of [
    'name: "item_space_assignment_command_account"',
    'columns: ["account_id"]',
    "localOnly: true",
  ]) {
    if (!tableSection.includes(required)) {
      fail("target_item_space_assignment_local_table_contract", required);
    }
  }
  for (const required of [
    "actor ItemSpaceAssignmentPowerSyncStore: ItemSpaceAssigning",
    "ItemSpaceAssignmentPowerSyncStoreFailure",
    "item_space_assignment_acceptance_time_invalid",
    "item_space_assignment_local_evidence_malformed",
    "item_space_assignment_operation_not_found",
    "item_space_assignment_items_v1",
    '"project"',
    '"business_inventory"',
    '"assign_items_to_space"',
    "OperationContractFailure.payloadMismatch",
    "ItemSpaceAssignmentFailure.localAcceptanceFailed",
    "CancellationError()",
    "case beforeTransaction",
    "case beforeCommit",
    "exactDate(milliseconds:",
    "cancelAndDrainWatches()",
    "operation.id = ?",
    "operation.account_id = ?",
    "operation.actor_principal_id = ?",
  ]) {
    if (!(storeWithoutComments ?? "").includes(required)) {
      fail("target_item_space_assignment_local_store_incomplete", required);
    }
  }
  const frozenDependencies = [
    [
      path.join(coreRoot, "ItemSpaceClearingOperation.swift"),
      "de8eb6c7a67fb5cc77e2c9fa2c279514908a35c76dd977d3288d42dbdc6d06ec",
    ],
    [
      path.join(coreRoot, "ItemSpaceClearingUseCase.swift"),
      "bec36d9ddbf5be470aa224a108138b71e88f8007632b90a0d039bd2f0e1f7709",
    ],
    [
      path.join(powerSyncRoot, "PendingWorkPowerSyncQuery.swift"),
      "036ea69b475795f04ce5820f4884969cd02461948a9ac40e9ac13f86d3d11bf1",
    ],
    [
      path.join(powerSyncRoot, "LedgerPowerSyncUploadConnector.swift"),
      "e3032c3950a524908a0cd89535c3a9556f783b70833910af1bc35adaa495b940",
    ],
    [
      path.join(powerSyncRoot, "ItemSpaceAssignmentPowerSyncStore.swift"),
      "124b257ced5fc89e4999c49228b804885b5b091bec0ee79f49d284e3b4c4f36e",
    ],
    [
      path.join(scriptDirectory, "supabase-conversion-ledger.mjs"),
      "94d3c6198cedac57213f00ac5bc171371b9796f6dfdb1fbd9b305516bdb8d624",
    ],
  ];
  for (const [frozenPath, expectedHash] of frozenDependencies) {
    const actualHash = createHash("sha256")
      .update(fs.readFileSync(frozenPath))
      .digest("hex");
    if (actualHash !== expectedHash) {
      fail("target_item_space_clearing_frozen_dependency_changed", relative(frozenPath));
    }
  }
  const referencedTables = new Set(
    [...(storeWithoutComments ?? "").matchAll(/LedgerPowerSyncTable\.(\w+)/g)]
      .map((match) => match[1]),
  );
  const allowedTables = new Set([
    "itemSpaceAssignmentCommands",
    "localOperations",
    "operationResults",
  ]);
  if (
    [...referencedTables].some((tableName) => !allowedTables.has(tableName)) ||
    referencedTables.size !== allowedTables.size
  ) {
    fail(
      "target_item_space_assignment_local_projection_escape",
      [...referencedTables].sort().join(","),
    );
  }
  if (
    /\bps_crud\b|insertOnly|Supabase|Postgrest|URLSession|Firebase|Firestore/.test(
      storeWithoutComments ?? "",
    ) ||
    /DELETE\s+FROM|UPDATE\s+[^\n]*(?:itemSpaceAssignmentCommands|spike_item_space_assignment_commands)/i.test(
      storeWithoutComments ?? "",
    ) ||
    /\bfunc\s+(?:delete|remove|repair|reset)\w*\s*\(/i.test(
      storeWithoutComments ?? "",
    )
  ) {
    fail(
      "target_item_space_assignment_local_scope_escape",
      relative(itemSpaceAssignmentStorePath),
    );
  }
  if (
    !(runtimeCode ?? "").includes(
      "publicfinalclassLedgerOfflineClientRuntime:ItemSpaceAssigning,ItemSpaceAssignmentClearing,Sendable",
    )
  ) {
    fail(
      "target_item_space_assignment_runtime_conformance",
      "The public runtime must nominally satisfy the verified ItemSpaceAssigning port.",
    );
  }
  const assignmentSubmitBody = swiftFunctionBody(
    itemSpaceAssignmentCoordinator,
    "func assignItemsToSpace(",
  );
  const assignmentWatchBody = swiftFunctionBody(
    itemSpaceAssignmentCoordinator,
    "func startItemSpaceAssignmentOperationWatch(",
  );
  const closeBody = swiftFunctionBody(
    itemSpaceAssignmentCoordinator,
    "private func performClose() async",
  );
  const facadeSubmitBody = swiftFunctionBody(
    itemSpaceAssignmentRuntime,
    "public func assignItemsToSpace(",
  );
  const facadeWatchBody = swiftFunctionBody(
    itemSpaceAssignmentRuntime,
    "public func watchItemSpaceAssignmentOperation(",
  );
  const structuralRequirements = [
    [
      "live factory",
      "makeItemSpaceAssignmentStore:{database,accountId,principalId,nowinItemSpaceAssignmentPowerSyncStore(database:database,accountId:accountId,principalId:principalId,now:now)}",
      coordinatorCode ?? "",
    ],
    [
      "bootstrap binding",
      "dependencies.makeItemSpaceAssignmentStore(openedStructured.database,accountId,principalId,dependencies.now)",
      coordinatorCode ?? "",
    ],
    [
      "resource binding",
      "itemSpaceAssignmentStore:madeItemSpaceAssignmentStore",
      coordinatorCode ?? "",
    ],
    [
      "finite lease",
      "withFiniteLease(.assignItemsToSpace)",
      compactSwiftCode(assignmentSubmitBody ?? "") ?? "",
    ],
    [
      "finite delegation",
      "resources.itemSpaceAssignmentStore.assignItemsToSpace(command)",
      compactSwiftCode(assignmentSubmitBody ?? "") ?? "",
    ],
    [
      "watch route",
      "resources.itemSpaceAssignmentStore.watchOperation(operationId)",
      compactSwiftCode(assignmentWatchBody ?? "") ?? "",
    ],
    [
      "facade submit route",
      "lifecycleOwner.assignItemsToSpace(command)",
      compactSwiftCode(facadeSubmitBody ?? "") ?? "",
    ],
    [
      "facade watch route",
      "lifecycleOwner.startItemSpaceAssignmentOperationWatch(",
      compactSwiftCode(facadeWatchBody ?? "") ?? "",
    ],
  ];
  for (const [label, required, source] of structuralRequirements) {
    if (!source.includes(required)) {
      fail("target_item_space_assignment_runtime_wiring", label);
    }
  }
  const compactCloseBody = compactSwiftCode(closeBody ?? "") ?? "";
  const assignmentDrainIndex = compactCloseBody.indexOf(
    "awaitresources.itemSpaceAssignmentStore.cancelAndDrainWatches()",
  );
  const structuredCloseIndex = compactCloseBody.indexOf(
    "tryawaitresources.closeStructuredDatabase()",
  );
  if (
    assignmentDrainIndex < 0 ||
    structuredCloseIndex < 0 ||
    assignmentDrainIndex >= structuredCloseIndex
  ) {
    fail(
      "target_item_space_assignment_runtime_close_order",
      "Assignment provider drainage must precede structured database close.",
    );
  }
  for (const testFunction of [
    "exactProjectAndInventoryRows",
    "numericAndClientTimeBoundaries",
    "providerTimeBoundaryAndPreDatabaseSentinel",
    "providerTimeExactRoundTripBoundary",
    "scopeRefusalBeforeDatabaseAccess",
    "encryptedRestartRetention",
    "malformedRestartNeverUpgrades",
    "exactAndChangedReplay",
    "commandTamperAndOrphans",
    "operationTamperAndTerminalEvidence",
    "concurrentAdmission",
    "writeFailureMappingAndRollback",
    "cancellationBoundaries",
    "queuedOnlyWatchAndDrainage",
    "watchFailureMappingAndCancellation",
    "watchRefusalMatrix",
    "pendingSummaryAndNoUploadWork",
    "runtimeCloseDrainageAndTerminalRefusal",
    "runtimeItemSpaceAssignmentUseCaseIntegration",
    "liveRuntimeItemSpaceAssignmentBinding",
    "boundedDiagnostics",
  ]) {
    const escapedTestFunction = testFunction.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    const annotatedTest = new RegExp(
      `@Test\\s*\\([^\\n]*\\)\\s*func\\s+${escapedTestFunction}\\s*\\(`,
      "g",
    );
    const annotatedMatches = [
      ...(testsWithoutComments ?? "").matchAll(annotatedTest),
    ];
    if (
      annotatedMatches.length !== 1 ||
      swiftFunctionBody(tests, `func ${testFunction}(`) === null
    ) {
      fail("target_item_space_assignment_executable_test_missing", testFunction);
    }
  }
  for (const requiredTestId of [
    "ITEMSPACELOCAL-TEST-001",
    "ITEMSPACELOCAL-TEST-002",
    "ITEMSPACELOCAL-TEST-003",
    "ITEMSPACELOCAL-TEST-004",
    "ITEMSPACELOCAL-TEST-005",
    "ITEMSPACELOCAL-TEST-006",
    "ITEMSPACELOCAL-TEST-007",
    "ITEMSPACELOCAL-TEST-008",
    "ITEMSPACELOCAL-TEST-009",
    "ITEMSPACELOCAL-TEST-010",
    "ITEMSPACELOCAL-TEST-011",
    "ITEMSPACELOCAL-TEST-012",
    "ITEMSPACELOCAL-TEST-013",
  ]) {
    if (!tests.includes(requiredTestId)) {
      fail("target_item_space_assignment_local_test_missing", requiredTestId);
    }
  }
}

const itemSpaceClearingStorePath = path.join(
  powerSyncRoot,
  "ItemSpaceClearingPowerSyncStore.swift",
);
const itemSpaceClearingTestsPath = path.join(
  powerSyncTestRoot,
  "ItemSpaceClearingPowerSyncStoreTests.swift",
);
for (const requiredPath of [
  itemSpaceClearingStorePath,
  itemSpaceClearingTestsPath,
]) {
  if (!fs.existsSync(requiredPath)) {
    fail("target_item_space_clearing_local_leaf_missing", relative(requiredPath));
  }
}
if (
  fs.existsSync(itemSpaceClearingStorePath) &&
  fs.existsSync(itemSpaceClearingTestsPath) &&
  fs.existsSync(powerSyncSchemaPath)
) {
  const store = fs.readFileSync(itemSpaceClearingStorePath, "utf8");
  const tests = fs.readFileSync(itemSpaceClearingTestsPath, "utf8");
  const schema = fs.readFileSync(powerSyncSchemaPath, "utf8");
  const itemSpaceClearingRuntime = fs.readFileSync(
    accountWorkspaceRuntimePath,
    "utf8",
  );
  const itemSpaceClearingCoordinator = fs.readFileSync(
    accountWorkspaceCoordinatorPath,
    "utf8",
  );
  const storeWithoutComments = swiftWithoutComments(store);
  const schemaWithoutComments = swiftWithoutComments(schema);
  const testsWithoutComments = swiftWithoutComments(tests);
  const coordinatorCode = compactSwiftCode(itemSpaceClearingCoordinator);
  const runtimeCode = compactSwiftCode(itemSpaceClearingRuntime);
  if (
    storeWithoutComments === null ||
    schemaWithoutComments === null ||
    testsWithoutComments === null ||
    coordinatorCode === null ||
    runtimeCode === null
  ) {
    fail(
      "target_item_space_clearing_lexical_structure_invalid",
      "Clearing store and runtime sources must have closed comments and string literals.",
    );
  }
  if (
    !(schemaWithoutComments ?? "").includes(
      'public static let itemSpaceClearingCommands = "spike_item_space_clearing_commands"',
    )
  ) {
    fail(
      "target_item_space_clearing_local_table_name",
      "The local command table name must remain exact.",
    );
  }
  const tableStart = (schemaWithoutComments ?? "").indexOf(
    "Table(\n            name: LedgerPowerSyncTable.itemSpaceClearingCommands,",
  );
  const tableEnd = tableStart < 0
    ? -1
    : (schemaWithoutComments ?? "").indexOf("\n        Table(", tableStart + 1);
  const tableSection = tableStart < 0 || tableEnd < 0
    ? ""
    : (schemaWithoutComments ?? "").slice(tableStart, tableEnd);
  const actualColumns = [
    ...tableSection.matchAll(/\.(text|integer)\("([^"]+)"\)/g),
  ].map((match) => `${match[1]}:${match[2]}`);
  const expectedColumns = [
    "text:account_id",
    "text:actor_principal_id",
    "text:contract_version",
    "text:scope_kind",
    "text:project_id",
    "text:items_json",
    "text:fingerprint",
    "text:command_json",
    "integer:accepted_at_ms",
  ];
  if (JSON.stringify(actualColumns) !== JSON.stringify(expectedColumns)) {
    fail(
      "target_item_space_clearing_local_table_columns",
      actualColumns.join(","),
    );
  }
  for (const required of [
    'name: "item_space_clearing_command_account"',
    'columns: ["account_id"]',
    "localOnly: true",
  ]) {
    if (!tableSection.includes(required)) {
      fail("target_item_space_clearing_local_table_contract", required);
    }
  }
  for (const required of [
    "actor ItemSpaceClearingPowerSyncStore: ItemSpaceAssignmentClearing",
    "ItemSpaceClearingPowerSyncStoreFailure",
    "item_space_clearing_acceptance_time_invalid",
    "item_space_clearing_local_evidence_malformed",
    "item_space_clearing_operation_not_found",
    "item_space_clearing_items_v1",
    "currentSpaceId",
    '"project"',
    '"business_inventory"',
    '"clear_item_space_assignments"',
    "OperationContractFailure.payloadMismatch",
    "ItemSpaceClearingFailure.localAcceptanceFailed",
    "CancellationError()",
    "case beforeCommit",
    "case inventoryConstruction",
    "case inventoryRead",
    "case afterOwnershipInspection",
    "exactDate(milliseconds:",
    "cancelAndDrainWatches()",
    "operation.id = ?",
    "operation.account_id = ?",
    "operation.actor_principal_id = ?",
  ]) {
    if (!(storeWithoutComments ?? "").includes(required)) {
      fail("target_item_space_clearing_local_store_incomplete", required);
    }
  }
  const referencedTables = new Set(
    [...(storeWithoutComments ?? "").matchAll(/LedgerPowerSyncTable\.(\w+)/g)]
      .map((match) => match[1]),
  );
  const allowedTables = new Set([
    "itemSpaceClearingCommands",
    "localOperations",
    "operationResults",
  ]);
  if (
    [...referencedTables].some((tableName) => !allowedTables.has(tableName)) ||
    referencedTables.size !== allowedTables.size
  ) {
    fail(
      "target_item_space_clearing_local_projection_escape",
      [...referencedTables].sort().join(","),
    );
  }
  if (
    /\bps_crud\b|insertOnly|Supabase|Postgrest|URLSession|Firebase|Firestore/.test(
      storeWithoutComments ?? "",
    ) ||
    /DELETE\s+FROM|UPDATE\s+[^\n]*(?:itemSpaceClearingCommands|spike_item_space_clearing_commands)/i.test(
      storeWithoutComments ?? "",
    ) ||
    /\bfunc\s+(?:delete|remove|repair|reset)\w*\s*\(/i.test(
      storeWithoutComments ?? "",
    )
  ) {
    fail(
      "target_item_space_clearing_local_scope_escape",
      relative(itemSpaceClearingStorePath),
    );
  }
  if (
    !(runtimeCode ?? "").includes(
      "publicfinalclassLedgerOfflineClientRuntime:ItemSpaceAssigning,ItemSpaceAssignmentClearing,Sendable",
    )
  ) {
    fail(
      "target_item_space_clearing_runtime_conformance",
      "The public runtime must nominally satisfy the verified ItemSpaceAssignmentClearing port.",
    );
  }
  const clearingSubmitBody = swiftFunctionBody(
    itemSpaceClearingCoordinator,
    "func clearItemSpaceAssignments(",
  );
  const clearingWatchBody = swiftFunctionBody(
    itemSpaceClearingCoordinator,
    "func startItemSpaceClearingOperationWatch(",
  );
  const closeBody = swiftFunctionBody(
    itemSpaceClearingCoordinator,
    "private func performClose() async",
  );
  const facadeSubmitBody = swiftFunctionBody(
    itemSpaceClearingRuntime,
    "public func clearItemSpaceAssignments(",
  );
  const facadeWatchBody = swiftFunctionBody(
    itemSpaceClearingRuntime,
    "public func watchItemSpaceClearingOperation(",
  );
  const structuralRequirements = [
    [
      "live factory",
      "makeItemSpaceClearingStore:{database,accountId,principalId,nowinItemSpaceClearingPowerSyncStore(database:database,accountId:accountId,principalId:principalId,now:now)}",
      coordinatorCode ?? "",
    ],
    [
      "bootstrap binding",
      "dependencies.makeItemSpaceClearingStore(openedStructured.database,accountId,principalId,dependencies.now)",
      coordinatorCode ?? "",
    ],
    [
      "resource binding",
      "itemSpaceClearingStore:madeItemSpaceClearingStore",
      coordinatorCode ?? "",
    ],
    [
      "finite lease",
      "withFiniteLease(.clearItemSpaceAssignments)",
      compactSwiftCode(clearingSubmitBody ?? "") ?? "",
    ],
    [
      "finite delegation",
      "resources.itemSpaceClearingStore.clearItemSpaceAssignments(command)",
      compactSwiftCode(clearingSubmitBody ?? "") ?? "",
    ],
    [
      "watch route",
      "resources.itemSpaceClearingStore.watchOperation(operationId)",
      compactSwiftCode(clearingWatchBody ?? "") ?? "",
    ],
    [
      "facade submit route",
      "lifecycleOwner.clearItemSpaceAssignments(command)",
      compactSwiftCode(facadeSubmitBody ?? "") ?? "",
    ],
    [
      "facade watch route",
      "lifecycleOwner.startItemSpaceClearingOperationWatch(",
      compactSwiftCode(facadeWatchBody ?? "") ?? "",
    ],
  ];
  for (const [label, required, source] of structuralRequirements) {
    if (!source.includes(required)) {
      fail("target_item_space_clearing_runtime_wiring", label);
    }
  }
  const compactCloseBody = compactSwiftCode(closeBody ?? "") ?? "";
  const clearingDrainIndex = compactCloseBody.indexOf(
    "awaitresources.itemSpaceClearingStore.cancelAndDrainWatches()",
  );
  const structuredCloseIndex = compactCloseBody.indexOf(
    "tryawaitresources.closeStructuredDatabase()",
  );
  if (
    clearingDrainIndex < 0 ||
    structuredCloseIndex < 0 ||
    clearingDrainIndex >= structuredCloseIndex
  ) {
    fail(
      "target_item_space_clearing_runtime_close_order",
      "Clearing provider drainage must precede structured database close.",
    );
  }
  for (const testFunction of [
    "exactProjectAndInventoryRows",
    "numericAndClientTimeBoundaries",
    "providerTimeBoundaryAndPreDatabaseSentinel",
    "providerTimeExactRoundTripBoundary",
    "scopeRefusalBeforeDatabaseAccess",
    "encryptedRestartRetention",
    "malformedRestartNeverUpgrades",
    "exactAndChangedReplay",
    "commandTamperAndOrphans",
    "operationTamperAndTerminalEvidence",
    "concurrentAdmission",
    "writeFailureMappingAndRollback",
    "cancellationBoundaries",
    "queuedOnlyWatchAndDrainage",
    "watchFailureMappingAndCancellation",
    "watchRefusalMatrix",
    "pendingSummaryAndNoUploadWork",
    "runtimeCloseDrainageAndTerminalRefusal",
    "runtimeItemSpaceClearingUseCaseIntegration",
    "liveRuntimeItemSpaceClearingBinding",
    "boundedDiagnostics",
  ]) {
    const escapedTestFunction = testFunction.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    const annotatedTest = new RegExp(
      `@Test\\s*\\([^\\n]*\\)\\s*func\\s+${escapedTestFunction}\\s*\\(`,
      "g",
    );
    const annotatedMatches = [
      ...(testsWithoutComments ?? "").matchAll(annotatedTest),
    ];
    if (
      annotatedMatches.length !== 1 ||
      swiftFunctionBody(tests, `func ${testFunction}(`) === null
    ) {
      fail("target_item_space_clearing_executable_test_missing", testFunction);
    }
  }
  for (const requiredTestId of [
    "ITEMSPACECLEARLOCAL-TEST-001",
    "ITEMSPACECLEARLOCAL-TEST-002",
    "ITEMSPACECLEARLOCAL-TEST-003",
    "ITEMSPACECLEARLOCAL-TEST-004",
    "ITEMSPACECLEARLOCAL-TEST-005",
    "ITEMSPACECLEARLOCAL-TEST-006",
    "ITEMSPACECLEARLOCAL-TEST-007",
    "ITEMSPACECLEARLOCAL-TEST-008",
    "ITEMSPACECLEARLOCAL-TEST-009",
    "ITEMSPACECLEARLOCAL-TEST-010",
    "ITEMSPACECLEARLOCAL-TEST-011",
    "ITEMSPACECLEARLOCAL-TEST-012",
    "ITEMSPACECLEARLOCAL-TEST-013",
  ]) {
    if (!tests.includes(requiredTestId)) {
      fail("target_item_space_clearing_local_test_missing", requiredTestId);
    }
  }
}

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
