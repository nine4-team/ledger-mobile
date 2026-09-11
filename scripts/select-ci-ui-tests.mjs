import { readFileSync, appendFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { pathToFileURL } from "node:url";

// CI verifies the active batch, not release readiness. Its fixed base includes
// earlier edits in this batch, unlike the previous push. Older workflow failures
// remain in their existing records; a new batch cannot declare them resolved.
export function needsUI(paths, { full = false, uiLayer = false } = {}) {
  if (full || uiLayer) return true;
  return paths.some(path => !(
    /^(docs\/|supabase\/|powersync\/|LedgerTargetMCP\/)/.test(path) ||
    /^LedgeriOS\/LedgerTarget(Core|CoreTests|PowerSync|PowerSyncTests)\//.test(path) ||
    /^scripts\/test-local-.*\.mjs$/.test(path) ||
    ["AGENTS.md", ".github/workflows/supabase-conversion-control.yml",
      "scripts/select-ci-ui-tests.mjs", "scripts/check-conversion-ci.mjs",
      "scripts/tests/check-conversion-ci.test.mjs", "scripts/tests/sync-output-tables.test.mjs"
    ].includes(path)
  ));
}

export function selectUI({ root = process.cwd(), event = process.env.GITHUB_EVENT_NAME } = {}) {
  const state = JSON.parse(readFileSync(`${root}/docs/plans/ledger-accounting-redesign/conversion/current-execution-state.json`));
  const checklist = JSON.parse(readFileSync(`${root}/${state.activeWorkflow.recordPath}`));
  const record = checklist.executionRecords.find(record => record.workflowId === state.activeWorkflow.id);
  if (!record) throw new Error("Active workflow not found; cannot select verification");
  const base = state.activeWorkflow.baseCommit;
  // Missing/invalid/stale evidence fails closed to full UI, never a silent skip.
  let required = true;
  let reason = "full UI requested or no usable batch baseline";
  if (event === "pull_request" && /^[0-9a-f]{40}$/.test(base ?? "")) {
    try {
      execFileSync("git", ["merge-base", "--is-ancestor", base, "HEAD"], { cwd: root, stdio: "pipe" });
      const paths = execFileSync("git", ["diff", "--no-renames", "--name-only", "-z", base, "HEAD"], { cwd: root })
        .toString().split("\0").filter(Boolean);
      required = needsUI(paths, { uiLayer: record.layers.includes("app_ui") });
      reason = required ? "UI layer, presentation/build/shared integration, or unclassified change"
        : "backend-only batch; native, build, database and security checks remain required; not release-wide UI proof";
    } catch {
      reason = "unusable batch baseline; run UI conservatively";
    }
  }
  return { required, reason, base };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const result = selectUI();
  if (process.env.GITHUB_OUTPUT) appendFileSync(process.env.GITHUB_OUTPUT, `required=${result.required}\n`);
  console.log(JSON.stringify(result));
}
