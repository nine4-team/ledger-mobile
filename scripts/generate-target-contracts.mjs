#!/usr/bin/env node

import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const SOURCE_PATH = path.join(ROOT, "LedgerTargetContracts/catalog.json");
const OUTPUTS = {
  swift: path.join(ROOT, "LedgeriOS/LedgerTargetCore/GeneratedContractCatalog.swift"),
  typeScript: path.join(ROOT, "LedgerTargetMCP/generated/contracts.ts"),
  resource: path.join(ROOT, "LedgerTargetMCP/resources/contract-catalog.json"),
};
const MODE = process.argv[2] ?? "check";

function fail(message) {
  throw new Error(`target-contracts: ${message}`);
}

function stableValue(value) {
  if (Array.isArray(value)) return value.map(stableValue);
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.keys(value)
        .sort()
        .map((key) => [key, stableValue(value[key])]),
    );
  }
  return value;
}

function canonicalJSON(value) {
  return `${JSON.stringify(stableValue(value))}\n`;
}

function requireObject(value, label) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    fail(`${label} must be an object`);
  }
}

function requireArray(value, label) {
  if (!Array.isArray(value)) fail(`${label} must be an array`);
}

function requireExactKeys(value, keys, label) {
  requireObject(value, label);
  const actual = Object.keys(value).sort();
  const expected = [...keys].sort();
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    fail(`${label} keys must be exactly ${expected.join(", ")}`);
  }
}

function requireStableCode(value, label) {
  if (typeof value !== "string" || !/^[a-z][a-z0-9_]{2,79}$/.test(value)) {
    fail(`${label} must be a lower snake-case stable code`);
  }
}

function requireVersion(value, label) {
  if (typeof value !== "string" || !/^[1-9][0-9]{0,5}$/.test(value)) {
    fail(`${label} must be a positive decimal contract version`);
  }
}

function requireText(value, label, maximum = 240) {
  if (
    typeof value !== "string" ||
    value.trim() !== value ||
    value.length === 0 ||
    value.length > maximum
  ) {
    fail(`${label} must be nonempty, trimmed, and at most ${maximum} characters`);
  }
}

function unique(values, label) {
  const seen = new Set();
  for (const value of values) {
    if (seen.has(value)) fail(`${label} contains duplicate ${value}`);
    seen.add(value);
  }
  return seen;
}

function requireTestOwner(value, label) {
  requireText(value, label, 180);
  if (
    path.isAbsolute(value) ||
    value.includes("..") ||
    !/^(LedgeriOS|LedgerTargetMCP|scripts)\/[A-Za-z0-9_./-]+$/.test(value)
  ) {
    fail(`${label} must be a bounded repository test/script path`);
  }
  if (!fs.existsSync(path.join(ROOT, value))) {
    fail(`${label} does not exist: ${value}`);
  }
}

function validateCatalog(catalog) {
  requireExactKeys(
    catalog,
    [
      "schemaVersion",
      "versions",
      "enums",
      "authorizationPolicies",
      "telemetryClasses",
      "errors",
      "capabilities",
      "contracts",
      "deprecations",
    ],
    "catalog",
  );
  if (catalog.schemaVersion !== 1) fail("schemaVersion must be 1");

  requireExactKeys(
    catalog.versions,
    ["catalog", "schema", "query", "operation", "sync"],
    "versions",
  );
  for (const [name, version] of Object.entries(catalog.versions)) {
    requireVersion(version, `versions.${name}`);
  }

  requireArray(catalog.enums, "enums");
  const enumNames = unique(catalog.enums.map((entry) => entry.name), "enums");
  const enumValues = new Map();
  for (const entry of catalog.enums) {
    requireExactKeys(entry, ["name", "values"], `enum ${entry.name}`);
    requireText(entry.name, "enum.name", 80);
    if (!/^[A-Z][A-Za-z0-9]{2,79}$/.test(entry.name)) {
      fail(`enum name is invalid: ${entry.name}`);
    }
    requireArray(entry.values, `enum ${entry.name}.values`);
    if (entry.values.length === 0) fail(`enum ${entry.name} has no values`);
    for (const value of entry.values) {
      requireText(value, `enum ${entry.name} value`, 80);
      if (!/^[A-Za-z][A-Za-z0-9_]{0,79}$/.test(value)) {
        fail(`enum ${entry.name} has invalid value ${value}`);
      }
    }
    enumValues.set(entry.name, unique(entry.values, `enum ${entry.name}`));
  }

  const requiredEnums = [
    "LedgerEnvironmentKind",
    "OperationPhase",
    "ApplicationErrorCategory",
    "RetryDisposition",
    "ConnectivityState",
    "AuthenticationRefreshState",
    "SubscriptionReadinessState",
    "SyncWriteBlock",
  ];
  for (const name of requiredEnums) {
    if (!enumNames.has(name)) fail(`missing runtime enum ${name}`);
  }

  requireArray(catalog.authorizationPolicies, "authorizationPolicies");
  const authorizationPolicyIDs = unique(
    catalog.authorizationPolicies.map((entry) => entry.id),
    "authorizationPolicies",
  );
  for (const entry of catalog.authorizationPolicies) {
    requireExactKeys(entry, ["id", "description"], `authorization policy ${entry.id}`);
    requireStableCode(entry.id, "authorization policy id");
    requireText(entry.description, `authorization policy ${entry.id} description`);
  }

  requireArray(catalog.telemetryClasses, "telemetryClasses");
  const telemetryClassIDs = unique(
    catalog.telemetryClasses.map((entry) => entry.id),
    "telemetryClasses",
  );
  for (const entry of catalog.telemetryClasses) {
    requireExactKeys(entry, ["id", "description"], `telemetry class ${entry.id}`);
    requireStableCode(entry.id, "telemetry class id");
    requireText(entry.description, `telemetry class ${entry.id} description`);
  }

  requireArray(catalog.errors, "errors");
  const errorCodes = unique(catalog.errors.map((entry) => entry.code), "errors");
  const categories = enumValues.get("ApplicationErrorCategory");
  const retryDispositions = enumValues.get("RetryDisposition");
  for (const entry of catalog.errors) {
    requireExactKeys(
      entry,
      ["code", "category", "retryDisposition"],
      `error ${entry.code}`,
    );
    requireStableCode(entry.code, "error code");
    if (!categories.has(entry.category)) {
      fail(`error ${entry.code} has unknown category ${entry.category}`);
    }
    if (!retryDispositions.has(entry.retryDisposition)) {
      fail(`error ${entry.code} has unknown retry disposition ${entry.retryDisposition}`);
    }
  }

  requireArray(catalog.capabilities, "capabilities");
  const capabilityIDs = unique(
    catalog.capabilities.map((entry) => entry.id),
    "capabilities",
  );
  for (const entry of catalog.capabilities) {
    requireExactKeys(
      entry,
      [
        "id",
        "version",
        "availability",
        "authorizationPolicy",
        "telemetryClass",
        "testOwner",
      ],
      `capability ${entry.id}`,
    );
    requireStableCode(entry.id, "capability id");
    requireVersion(entry.version, `capability ${entry.id} version`);
    if (!["available", "gated", "deprecated"].includes(entry.availability)) {
      fail(`capability ${entry.id} has invalid availability ${entry.availability}`);
    }
    if (!authorizationPolicyIDs.has(entry.authorizationPolicy)) {
      fail(`capability ${entry.id} has unknown authorization policy`);
    }
    if (!telemetryClassIDs.has(entry.telemetryClass)) {
      fail(`capability ${entry.id} has unknown telemetry class`);
    }
    requireTestOwner(entry.testOwner, `capability ${entry.id} testOwner`);
  }

  requireArray(catalog.contracts, "contracts");
  const contractIDs = unique(catalog.contracts.map((entry) => entry.id), "contracts");
  for (const entry of catalog.contracts) {
    requireExactKeys(
      entry,
      [
        "id",
        "kind",
        "version",
        "capability",
        "authorizationPolicy",
        "resultContract",
        "errorCodes",
        "telemetryClass",
        "testOwner",
        "deprecation",
      ],
      `contract ${entry.id}`,
    );
    requireStableCode(entry.id, "contract id");
    if (!["operation", "query", "resource"].includes(entry.kind)) {
      fail(`contract ${entry.id} has invalid kind ${entry.kind}`);
    }
    requireVersion(entry.version, `contract ${entry.id} version`);
    if (!capabilityIDs.has(entry.capability)) {
      fail(`contract ${entry.id} has unknown capability ${entry.capability}`);
    }
    if (!authorizationPolicyIDs.has(entry.authorizationPolicy)) {
      fail(`contract ${entry.id} has unknown authorization policy`);
    }
    requireText(entry.resultContract, `contract ${entry.id} resultContract`, 100);
    if (!/^[A-Z][A-Za-z0-9]{2,99}$/.test(entry.resultContract)) {
      fail(`contract ${entry.id} resultContract is not a type name`);
    }
    requireArray(entry.errorCodes, `contract ${entry.id}.errorCodes`);
    if (entry.errorCodes.length === 0) fail(`contract ${entry.id} has no error contract`);
    unique(entry.errorCodes, `contract ${entry.id}.errorCodes`);
    for (const errorCode of entry.errorCodes) {
      if (!errorCodes.has(errorCode)) {
        fail(`contract ${entry.id} has unknown error ${errorCode}`);
      }
    }
    if (!telemetryClassIDs.has(entry.telemetryClass)) {
      fail(`contract ${entry.id} has unknown telemetry class`);
    }
    requireTestOwner(entry.testOwner, `contract ${entry.id} testOwner`);
    if (entry.deprecation !== null) {
      requireExactKeys(
        entry.deprecation,
        ["replacement", "minimumClientVersion"],
        `contract ${entry.id} deprecation`,
      );
      if (entry.deprecation.replacement !== null) {
        requireStableCode(entry.deprecation.replacement, "deprecation replacement");
      }
      requireVersion(
        entry.deprecation.minimumClientVersion,
        `contract ${entry.id} minimumClientVersion`,
      );
    }
  }

  requireArray(catalog.deprecations, "deprecations");
  unique(catalog.deprecations.map((entry) => entry.contract), "deprecations");
  const deprecationsByContract = new Map();
  for (const entry of catalog.deprecations) {
    requireExactKeys(
      entry,
      ["contract", "replacement", "minimumClientVersion"],
      `deprecation ${entry.contract}`,
    );
    if (!contractIDs.has(entry.contract)) fail(`deprecation has unknown contract`);
    if (entry.replacement !== null && !contractIDs.has(entry.replacement)) {
      fail(`deprecation ${entry.contract} has unknown replacement`);
    }
    if (entry.contract === entry.replacement) {
      fail(`deprecation ${entry.contract} replaces itself`);
    }
    requireVersion(entry.minimumClientVersion, "deprecation minimumClientVersion");
    deprecationsByContract.set(entry.contract, entry);
  }

  for (const contract of catalog.contracts) {
    const listed = deprecationsByContract.get(contract.id);
    if ((contract.deprecation === null) !== (listed === undefined)) {
      fail(`contract ${contract.id} deprecation projections disagree`);
    }
    if (
      contract.deprecation !== null &&
      (contract.deprecation.replacement !== listed.replacement ||
        contract.deprecation.minimumClientVersion !== listed.minimumClientVersion)
    ) {
      fail(`contract ${contract.id} deprecation projections disagree`);
    }
  }

  const sourceText = canonicalJSON(catalog);
  if (Buffer.byteLength(sourceText) > 64 * 1024) fail("catalog exceeds 64 KiB");
  const forbidden =
    /\b(firebase|firestore|supabase|powersync|postgres(?:ql)?|database|sql|table|service[_ -]?role|api[_ -]?key|password|access[_ -]?token|refresh[_ -]?token|private[_ -]?payload)\b/i;
  const match = sourceText.match(forbidden);
  if (match) fail(`catalog contains forbidden provider/credential term ${match[1]}`);
}

function cloneCatalog(catalog) {
  return JSON.parse(JSON.stringify(catalog));
}

function expectValidationFailure(catalog, label, mutate, expectedMessage) {
  const invalid = cloneCatalog(catalog);
  mutate(invalid);
  try {
    validateCatalog(invalid);
  } catch (error) {
    if (!(error instanceof Error) || !error.message.includes(expectedMessage)) {
      fail(`${label} failed for an unexpected reason`);
    }
    return;
  }
  fail(`${label} did not fail closed`);
}

function runNegativeValidationControls(catalog) {
  const missingContractField = (field) => (invalid) => {
    delete invalid.contracts[0][field];
  };

  const controls = [
    ["duplicate registry IDs", (invalid) => {
      invalid.capabilities[1].id = invalid.capabilities[0].id;
    }, "contains duplicate"],
    ["duplicate enum values", (invalid) => {
      invalid.enums[0].values.push(invalid.enums[0].values[0]);
    }, "contains duplicate"],
    ["missing authorization metadata", missingContractField("authorizationPolicy"), "keys must be exactly"],
    ["missing error metadata", missingContractField("errorCodes"), "keys must be exactly"],
    ["missing result metadata", missingContractField("resultContract"), "keys must be exactly"],
    ["missing telemetry metadata", missingContractField("telemetryClass"), "keys must be exactly"],
    ["missing test ownership", missingContractField("testOwner"), "keys must be exactly"],
    ["missing version metadata", missingContractField("version"), "keys must be exactly"],
    ["unsupported authorization reference", (invalid) => {
      invalid.contracts[0].authorizationPolicy = "unknown_policy";
    }, "unknown authorization policy"],
    ["unsupported error reference", (invalid) => {
      invalid.contracts[0].errorCodes = ["unknown_error"];
    }, "unknown error"],
    ["unsupported telemetry reference", (invalid) => {
      invalid.contracts[0].telemetryClass = "unknown_telemetry";
    }, "unknown telemetry class"],
    ["unsupported capability reference", (invalid) => {
      invalid.contracts[0].capability = "unknown_capability";
    }, "unknown capability"],
    ["unsupported contract version", (invalid) => {
      invalid.contracts[0].version = "0";
    }, "positive decimal contract version"],
    ["invalid deprecation replacement", (invalid) => {
      invalid.contracts[0].deprecation = {
        replacement: invalid.contracts[0].id,
        minimumClientVersion: "1",
      };
      invalid.deprecations = [{
        contract: invalid.contracts[0].id,
        replacement: invalid.contracts[0].id,
        minimumClientVersion: "1",
      }];
    }, "replaces itself"],
    ["deprecation projection drift", (invalid) => {
      invalid.contracts[0].deprecation = {
        replacement: invalid.contracts[1].id,
        minimumClientVersion: "2",
      };
    }, "deprecation projections disagree"],
    ["provider leakage", (invalid) => {
      invalid.authorizationPolicies[0].description = "Delegate this check to Supabase.";
    }, "forbidden provider/credential term"],
    ["persistence leakage", (invalid) => {
      invalid.authorizationPolicies[0].description = "Read the private database table.";
    }, "forbidden provider/credential term"],
    ["credential leakage", (invalid) => {
      invalid.authorizationPolicies[0].description = "Attach an api_key to this request.";
    }, "forbidden provider/credential term"],
    ["private payload leakage", (invalid) => {
      invalid.authorizationPolicies[0].description = "Return the private payload.";
    }, "forbidden provider/credential term"],
  ];

  for (const [label, mutate, expectedMessage] of controls) {
    expectValidationFailure(catalog, label, mutate, expectedMessage);
  }
}

function swiftProjection(canonical, hash) {
  const base64 = Buffer.from(canonical).toString("base64");
  return `// Generated by scripts/generate-target-contracts.mjs. Do not edit.\nimport Foundation\n\npublic enum GeneratedTargetContractCatalog {\n    public static let sha256 = "${hash}"\n    private static let canonicalJSONBase64 = "${base64}"\n\n    public static func load() throws -> VersionedContractCatalog {\n        guard let data = Data(base64Encoded: canonicalJSONBase64) else {\n            throw ContractCatalogFailure.catalogHashMismatch\n        }\n        let catalog = try OperationContractCodec.decode(\n            VersionedContractCatalog.self,\n            from: data\n        )\n        try ContractCatalogValidator.validate(\n            catalog,\n            canonicalData: data,\n            expectedSHA256: sha256\n        )\n        return catalog\n    }\n}\n`;
}

function typeScriptProjection(catalog, hash) {
  return `// Generated by scripts/generate-target-contracts.mjs. Do not edit.\nexport const targetContractCatalogSha256 = ${JSON.stringify(hash)} as const;\nexport const targetContractCatalog = ${JSON.stringify(stableValue(catalog), null, 2)} as const;\nexport type TargetContractCatalog = typeof targetContractCatalog;\n`;
}

function resourceProjection(catalog, hash) {
  return `${JSON.stringify(
    stableValue({ catalogSha256: hash, catalog }),
    null,
    2,
  )}\n`;
}

function expectedOutputs(catalog) {
  const canonical = canonicalJSON(catalog);
  const hash = crypto.createHash("sha256").update(canonical).digest("hex");
  return {
    hash,
    outputs: {
      [OUTPUTS.swift]: swiftProjection(canonical, hash),
      [OUTPUTS.typeScript]: typeScriptProjection(catalog, hash),
      [OUTPUTS.resource]: resourceProjection(catalog, hash),
    },
  };
}

function generate(outputs) {
  for (const [filePath, content] of Object.entries(outputs)) {
    fs.mkdirSync(path.dirname(filePath), { recursive: true });
    fs.writeFileSync(filePath, content);
  }
}

function check(outputs) {
  const stale = [];
  for (const [filePath, content] of Object.entries(outputs)) {
    if (!fs.existsSync(filePath) || fs.readFileSync(filePath, "utf8") !== content) {
      stale.push(path.relative(ROOT, filePath));
    }
  }
  if (stale.length > 0) {
    fail(`stale generated projection(s): ${stale.join(", ")}`);
  }
}

if (!fs.existsSync(SOURCE_PATH)) fail("missing LedgerTargetContracts/catalog.json");
const catalog = JSON.parse(fs.readFileSync(SOURCE_PATH, "utf8"));
validateCatalog(catalog);
const { hash, outputs } = expectedOutputs(catalog);

if (MODE === "generate") {
  generate(outputs);
  process.stdout.write(`target-contracts: generated ${Object.keys(outputs).length} projections at ${hash}\n`);
} else if (MODE === "check") {
  runNegativeValidationControls(catalog);
  check(outputs);
  process.stdout.write(`target-contracts: catalog, ${Object.keys(outputs).length} projections, and negative registration controls valid at ${hash}\n`);
} else {
  fail(`unsupported mode ${MODE}; use generate or check`);
}
