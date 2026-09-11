import assert from "node:assert/strict";
import { readFileSync, mkdtempSync, mkdirSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync, execFileSync } from "node:child_process";
import test from "node:test";
import { needsUI, selectUI } from "../select-ci-ui-tests.mjs";

test("backend-only changes omit UI but presentation, integration and unknown paths keep it", () => {
  const backend = ["supabase/migrations/read.sql", "powersync/sync-streams.yaml",
    "LedgeriOS/LedgerTargetCore/DownloadedItemPlacements.swift",
    "LedgeriOS/LedgerTargetPowerSync/CurrentItemPlacementLocalReader.swift",
    "scripts/test-local-property-report-mcp.mjs", "docs/plan.md"];
  assert.equal(needsUI(backend), false);
  assert.equal(needsUI(backend, { full: true }), true);
  assert.equal(needsUI(backend, { uiLayer: true }), true);
  for (const path of ["LedgeriOS/LedgerTargetStaging/ItemView.swift",
    "LedgeriOS/LedgerTargetApp/ItemModel.swift", "LedgeriOS/Package.swift",
    "LedgeriOS/LedgerTargetStagingUITests/WorkspaceChecklistUITests.swift",
    "package.json", "scripts/build-target.mjs", "unknown-file"]) {
    assert.equal(needsUI([...backend, path]), true, path);
  }
  // A later backend push does not erase outstanding UI changes from the range.
  assert.equal(needsUI(["LedgeriOS/LedgerTargetStaging/OldUnverifiedView.swift", ...backend]), true);
  assert.equal(selectUI({ root: repositoryRoot, event: "workflow_dispatch" }).required, true);
});

test("only UI execution may be conditional; its selector cannot be replaced by a constant", () => {
  for (const condition of ["false", "true", "needs.conversion-control.outputs.ui-required != 'true'"]) {
    expectFailure(value => { value.workflow = value.workflow.replace(
      "if: needs.conversion-control.outputs.ui-required == 'true'", `if: ${condition}`); }, /conditionally skip|execution overrides/);
  }
  expectFailure(value => { value.workflow = value.workflow.replace(
    "run: node scripts/select-ci-ui-tests.mjs", "run: echo required=false"); }, /UI selection/);
  expectFailure(value => { value.workflow = value.workflow.replace(
    "ui-required: ${{ steps.ui-scope.outputs.required }}", "ui-required: false"); }, /UI selection/);
});

test("selector uses the fixed batch ancestor and fails closed without usable evidence", t => {
  const root = mkdtempSync(join(tmpdir(), "ledger-ui-selection-"));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const git = (...args) => execFileSync("git", args, { cwd: root, stdio: "pipe" }).toString().trim();
  git("init", "-q");
  git("-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "--allow-empty", "-m", "baseline");
  const base = git("rev-parse", "HEAD");
  const directory = "docs/plans/ledger-accounting-redesign/conversion";
  mkdirSync(join(root, directory), { recursive: true });
  const state = { activeWorkflow: { id: "backend", recordPath: `${directory}/checklist.json`, baseCommit: base } };
  const save = () => writeFileSync(join(root, directory, "current-execution-state.json"), JSON.stringify(state));
  writeFileSync(join(root, directory, "checklist.json"), JSON.stringify({ executionRecords: [{ workflowId: "backend", layers: ["domain"] }] }));
  save();
  assert.equal(selectUI({ root, event: "pull_request" }).required, false);
  writeFileSync(join(root, directory, "checklist.json"), JSON.stringify({ executionRecords: [{ workflowId: "backend", layers: ["domain", "app_ui"] }] }));
  assert.equal(selectUI({ root, event: "pull_request" }).required, true);
  writeFileSync(join(root, directory, "checklist.json"), JSON.stringify({ executionRecords: [{ workflowId: "backend", layers: ["domain"] }] }));
  mkdirSync(join(root, "LedgeriOS/LedgerTargetApp"), { recursive: true });
  writeFileSync(join(root, "LedgeriOS/LedgerTargetApp/View.swift"), "// changed UI\n");
  git("add", ".");
  git("-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "-qm", "presentation");
  assert.equal(selectUI({ root, event: "pull_request" }).required, true);
  for (const invalid of [undefined, "invalid", "a".repeat(40)]) {
    state.activeWorkflow.baseCommit = invalid;
    save();
    assert.equal(selectUI({ root, event: "pull_request" }).required, true);
  }
});

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

test("small failure screenshots retain scoped extraction and never replace full evidence", () => {
  expectFailure(value => {
    value.workflow = value.workflow.replace('          done\n', '          done\n          echo extra-command\n');
  }, /failure screenshot extraction/);
  expectFailure(value => {
    value.workflow = value.workflow.replace('  conversion-control:\n', '  conversion-control:\n      - name: Export native UI failure screenshots\n        if: failure()\n        run: |\n          echo unexpected\n');
  }, /conditionally skip/);
  expectFailure(value => {
    value.workflow = value.workflow.replace("xcrun xcresulttool export attachments --only-failures", "echo skipped");
  }, /failure screenshot extraction/);
  expectFailure(value => {
    value.workflow = value.workflow.replace("ledger-ui-failure-images/**/*.png", "ledger-ui-failure-images/**/*");
  }, /failure screenshot artifacts/);
  expectFailure(value => {
    value.workflow = value.workflow.replace("native-ui-screenshots-ios-${{ github.sha }}", "native-ui-screenshots-ios-latest");
  }, /failure screenshot artifacts/);
});

test("iPhone UI cannot silently omit new Item or report interactions", () => {
  const selector = "-only-testing:LedgerTargetStagingUITests/WorkspaceChecklistUITests test";
  for (const replacement of [
    "-only-testing:LedgerTargetStagingUITests/WorkspaceChecklistUITests/testPropertyManagementIOSPDFCopyCompletion test",
    "-skip-testing:LedgerTargetStagingUITests/WorkspaceChecklistUITests/testDownloadedItemsRefreshAndRemoval " + selector,
  ]) {
    expectFailure(value => { value.workflow = value.workflow.replace(selector, replacement); },
      /iOS UI must run the whole/);
  }
  expectFailure(value => {
    value.workflow = value.workflow.replace("TEST_RUNNER_LEDGER_ISOLATED_CI_CLIPBOARD=true xcodebuild", "xcodebuild");
  }, /iOS UI Copy verification requires its isolated/);
});

test("stable aggregate rejects failed, cancelled, skipped, or missing dependencies", () => {
  for (const dependency of ["conversion-control", "local-supabase-provider-slices", "native-macos", "native-ios"]) {
    const assertion = `          test '\${{ needs.${dependency}.result }}' = 'success'`;
    for (const replacement of ["", assertion.replace("= 'success'", "!= 'failure'"), assertion + " || true"]) {
      expectFailure(value => { value.workflow = value.workflow.replace(assertion, replacement); }, /target aggregate/);
    }
  }
  for (const [original, replacement] of [
    ["    if: always()", "    if: success()"],
    ["    if: always()\n", ""],
    ["    name: Isolated target environment", "    name: Renamed gate"],
    ["local-supabase-provider-slices, native-macos, native-ios]", "local-supabase-provider-slices, native-macos]"],
  ]) expectFailure(value => { value.workflow = value.workflow.replace(original, replacement); }, /target aggregate|conditionally skip/);
  expectFailure(value => {
    value.workflow = value.workflow.replace("        run: npm run target:staging:ui:test:macos", "        continue-on-error: true\n        run: npm run target:staging:ui:test:macos");
  }, /conditionally skip|execution overrides/);
});

test("actual aggregate shell rejects each unsuccessful dependency result", () => {
  const block = inputs().workflow.split("      - name: Require every target verification job\n        run: |\n")[1]
    .split("\n\n")[0];
  const dependencies = ["conversion-control", "local-supabase-provider-slices", "native-macos", "native-ios"];
  function execute(results) {
    const script = block.replace(/\$\{\{ needs\.([\w-]+)\.result \}\}/g, (_, dependency) => results[dependency]);
    return spawnSync("bash", ["-e", "-c", script], { encoding: "utf8" });
  }
  const successful = Object.fromEntries(dependencies.map(dependency => [dependency, "success"]));
  assert.equal(execute(successful).status, 0);
  for (const dependency of dependencies) {
    for (const result of ["failure", "cancelled", "skipped", ""]) {
      const actual = execute({ ...successful, [dependency]: result });
      assert.ifError(actual.error);
      assert.equal(actual.status, 1, `${dependency}: ${result || "missing"} must fail`);
    }
  }
});

test("native workers remain independent, same-commit and retain separate failure evidence", () => {
  for (const platform of ["macos", "ios"]) {
    expectFailure(value => {
      value.workflow = value.workflow.replace(`name: native-ui-failure-${platform}-`, "name: native-ui-failure-");
    }, /platform-separated/);
    expectFailure(value => {
      const start = value.workflow.indexOf(`  native-${platform}:`);
      value.workflow = value.workflow.slice(0, start) + value.workflow.slice(start).replace(
        "    needs: [conversion-control, local-supabase-provider-slices]",
        "    needs: [conversion-control, local-supabase-provider-slices, native-other]");
    }, /same-commit database dependency/);
    expectFailure(value => {
      const start = value.workflow.indexOf(`  native-${platform}:`);
      value.workflow = value.workflow.slice(0, start) + value.workflow.slice(start).replace(
        "          fetch-depth: 0", "          ref: main\n          fetch-depth: 0");
    }, /this PR commit/);
    expectFailure(value => {
      const start = value.workflow.indexOf(`  native-${platform}:`);
      value.workflow = value.workflow.slice(0, start) + value.workflow.slice(start).replace(
        "        run: git diff --exit-code", "        run: true");
    }, /read-only diff guard/);
  }
  for (const original of ["-parallel-testing-enabled NO", "-default-test-execution-time-allowance 300", "          bash scripts/test-local-vendor-pdf-parser.sh"]) {
    expectFailure(value => { value.workflow = value.workflow.replace(original, ""); }, /iOS UI must preserve|target gate/);
  }
});

test("report parity cannot silently lose its same-commit fixture", () => {
  expectFailure(value => {
    value.workflow = value.workflow.replace("          name: report-parity-${{ github.sha }}", "          name: report-parity-unbound");
  }, /same-commit report fixture/);
  expectFailure(value => {
    value.workflow = value.workflow.replace("          if-no-files-found: error", "          if-no-files-found: ignore");
  }, /same-commit report fixture/);
});

test("repository conversion CI retains the required product and implementation gates", () => {
  const { packageJson, workflow } = inputs();
  assert.deepEqual(validateConversionCI(packageJson, workflow), {
    conversionCommands: 7,
    packageGates: 15,
    legacyScripts: 15,
    jobs: 5,
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
  expectFailure(value => {
    value.workflow = value.workflow.replace(
      '        env:\n          TEST_RUNNER_LEDGER_ISOLATED_CI_CLIPBOARD: "true"\n', "");
  }, /isolated test-runner flag|conditionally skip/);
  expectFailure(value => {
    value.workflow = value.workflow.replace('TEST_RUNNER_LEDGER_ISOLATED_CI_CLIPBOARD: "true"',
      'TEST_RUNNER_LEDGER_ISOLATED_CI_CLIPBOARD: "false"');
  }, /environment or execution overrides/);
  for (const [original, replacement] of [
    ["          bash scripts/run-target-native-tests-with-diagnostics.sh\n", ""],
    ["          path: ${{ runner.temp }}/ledger-native-diagnostics", "          path: /Users"],
    ["          name: native-test-stall-diagnostics", "          name: arbitrary-files"],
  ]) {
    expectFailure(value => {
      value.workflow = value.workflow.replace(original, replacement);
    }, /target diagnostics/);
  }
  expectFailure(
    (value) => {
      value.workflow = value.workflow.replace(
        "      - name: Preserve native test stall diagnostics\n        if: always()\n        uses: actions/upload-artifact@v4",
        "      - name: Preserve native test stall diagnostics\n        if: always()\n        run: swift test",
      );
    },
    /must not conditionally skip/,
  );
  expectFailure(
    (value) => {
      value.workflow = value.workflow.replace("        run: npm run target:staging:ui:test:macos\n", "");
    },
    /environment or execution overrides|target gate npm run target:staging:ui:test:macos/,
  );
  expectFailure(
    (value) => {
      value.workflow = value.workflow.replace("    needs: [conversion-control, local-supabase-provider-slices]\n", "");
    },
    /target same-commit database dependency/,
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
    /one complete nonparallel Swift test gate/,
  );
  for (const selection of ["--filter OneSuite", "--skip OneSuite"]) {
    expectFailure(value => {
      value.workflow = value.workflow.replace(
        "          swift test --package-path LedgeriOS --no-parallel\n",
        `          swift test --package-path LedgeriOS --no-parallel\n          ${selection}\n`,
      );
    }, /must not filter or skip suites/);
  }
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

test("failed native UI evidence allowance cannot conditionally run arbitrary commands", () => {
  expectFailure(value => {
    value.workflow = value.workflow.replace(
      "      - name: Preserve failed native UI test evidence\n        if: failure()\n        uses: actions/upload-artifact@v4",
      "      - name: Preserve failed native UI test evidence\n        if: failure()\n        run: echo skipped",
    );
  }, /jobs must not conditionally skip or tolerate failures/);
});

test("local Supabase job cannot bypass lint, database tests, cleanup, or its diff guard", () => {
  expectFailure(value => {
    value.workflow = value.workflow.replace("          node scripts/test-local-physical-item-stream.mjs\n", "");
  }, /local database gate node scripts\/test-local-physical-item-stream/);
  expectFailure(value => {
    value.workflow = value.workflow.replace("          node scripts/test-local-item-placement-concurrency.mjs\n", "");
  }, /local database gate node scripts\/test-local-item-placement-concurrency/);
  expectFailure(value => {
    value.workflow = value.workflow.replace("        run: node scripts/select-ci-supabase-db-port.mjs\n", "");
  }, /port selection must precede startup/);
  expectFailure(
    (value) => {
      value.workflow = value.workflow.replace("          npm run target:supabase:test:payment-import\n", "");
    },
    /local database gate npm run target:supabase:test:payment-import/,
  );
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
