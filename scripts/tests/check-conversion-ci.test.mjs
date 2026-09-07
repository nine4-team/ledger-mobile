import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import test from "node:test";

import {
  repositoryRoot,
  validateConversionCI,
  workflowRelativePath,
} from "../check-conversion-ci.mjs";

function inputs() {
  return {
    packageJson: JSON.parse(readFileSync(join(repositoryRoot, "package.json"), "utf8")),
    workflow: readFileSync(join(repositoryRoot, workflowRelativePath), "utf8"),
  };
}

function expectFailure(mutate, pattern) {
  const value = inputs();
  const originalPackageJson = JSON.stringify(value.packageJson);
  const originalWorkflow = value.workflow;
  mutate(value);
  assert.ok(
    JSON.stringify(value.packageJson) !== originalPackageJson || value.workflow !== originalWorkflow,
    "adversarial fixture must mutate package.json or the workflow",
  );
  assert.throws(() => validateConversionCI(value.packageJson, value.workflow), pattern);
}

test("repository conversion CI retains the required product and implementation gates", () => {
  const { packageJson, workflow } = inputs();
  assert.deepEqual(validateConversionCI(packageJson, workflow), {
    conversionCommands: 7,
    packageGates: 13,
    legacyScripts: 15,
    jobs: 3,
  });
});

test("conversion control rejects missing, reordered, retired, and lifecycle-bypassed checks", () => {
  expectFailure(
    (value) => {
      value.workflow = value.workflow.replace(
        "          node scripts/ledger-product-checklist.mjs --self-test\n",
        "",
      );
    },
    /commands or order changed/,
  );
  expectFailure(
    (value) => {
      value.workflow = value.workflow.replace(
        "          npm run conversion:capabilities:check\n          npm run conversion:queries:check",
        "          npm run conversion:queries:check\n          npm run conversion:capabilities:check",
      );
    },
    /commands or order changed/,
  );
  expectFailure(
    (value) => {
      value.workflow = value.workflow.replace(
        "          npm run conversion:check",
        "          npm run target:query-authority:check\n          npm run conversion:check",
      );
    },
    /commands or order changed|historical/,
  );
  expectFailure(
    (value) => {
      value.packageJson.scripts["preconversion:check"] = "node scripts/bypass.mjs";
    },
    /must not define preconversion:check/,
  );
  expectFailure(
    (value) => {
      value.packageJson.scripts["target:query-ports:check"] =
        value.packageJson.scripts["legacy:target:query-ports:check"];
    },
    /must remain namespaced as legacy:target:query-ports:check/,
  );
  const unrelated = inputs();
  unrelated.packageJson.scripts["local:help"] = "node --version";
  unrelated.workflow += "\n# Documentation-only comment.\n";
  assert.doesNotThrow(() => validateConversionCI(unrelated.packageJson, unrelated.workflow));
});

test("workflow rejects conditional skips, execution overrides, and weakened history or diff guards", () => {
  expectFailure(
    (value) => {
      value.workflow = value.workflow.replace(
        "    runs-on: ubuntu-latest",
        "    if: ${{ false }}\n    runs-on: ubuntu-latest",
      );
    },
    /must not conditionally skip/,
  );
  expectFailure(
    (value) => {
      value.workflow = value.workflow.replace(
        "    runs-on: ubuntu-latest",
        "    env:\n      NODE_OPTIONS: --require ./bypass.cjs\n    runs-on: ubuntu-latest",
      );
    },
    /execution overrides require security review/,
  );
  expectFailure(
    (value) => {
      value.workflow = value.workflow.replace("          fetch-depth: 0", "          fetch-depth: 1");
    },
    /full-history checkout/,
  );
  expectFailure(
    (value) => {
      value.workflow = value.workflow.replace(
        "      - name: Confirm checks did not rewrite tracked artifacts\n        run: git diff --exit-code",
        "      - name: Confirm checks did not rewrite tracked artifacts\n        run: git status --short",
      );
    },
    /read-only diff guard/,
  );
  expectFailure(
    (value) => {
      value.workflow = value.workflow.replace(
        "      - name: Stop isolated local Supabase\n        if: always()",
        "      - name: Stop isolated local Supabase\n        if: success()",
      );
    },
    /must not conditionally skip/,
  );
});

test("target job cannot bypass native, MCP, build, or dependency gates", () => {
  expectFailure(
    (value) => {
      value.workflow = value.workflow.replace("    needs: conversion-control\n", "", 1);
    },
    /target dependency/,
  );
  expectFailure(
    (value) => {
      value.workflow = value.workflow.replace("          npm run target:mcp:test\n", "");
    },
    /target gate npm run target:mcp:test/,
  );
  expectFailure(
    (value) => {
      value.workflow = value.workflow.replace(
        "          swift test --package-path LedgeriOS --no-parallel",
        "          swift test --package-path LedgeriOS",
      );
    },
    /three split nonparallel Swift test gates/,
  );
  expectFailure(
    (value) => {
      value.workflow = value.workflow.replace(
        "        run: npm run target:staging:build:ios\n",
        "",
      );
    },
    /target gate npm run target:staging:build:ios/,
  );
});

test("local Supabase job cannot bypass lint, database tests, cleanup, or its diff guard", () => {
  expectFailure(
    (value) => {
      value.workflow = value.workflow.replace("          npm run target:supabase:test:db\n", "");
    },
    /local database gate npm run target:supabase:test:db/,
  );
  expectFailure(
    (value) => {
      value.workflow = value.workflow.replace(
        "          npx --yes supabase@2.116.0 db lint --local --schema public,ledger_private --level warning --fail-on warning",
        "          npx --yes supabase@2.116.0 db lint --local --schema public",
      );
    },
    /local database gate npx --yes supabase@2.116.0 db lint/,
  );
  expectFailure(
    (value) => {
      value.workflow = value.workflow.replace(
        "        run: npx --yes supabase@2.116.0 stop --no-backup",
        "        run: true",
      );
    },
    /must not conditionally skip|local database gate npx --yes supabase@2.116.0 stop/,
  );
  expectFailure(
    (value) => {
      value.workflow = value.workflow.replace(
        "      - name: Confirm target checks did not rewrite tracked artifacts\n        run: git diff --exit-code",
        "      - name: Confirm target checks did not rewrite tracked artifacts\n        run: true",
      );
    },
    /read-only diff guard/,
  );
});
