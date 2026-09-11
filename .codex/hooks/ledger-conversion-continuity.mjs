#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { execFileSync, spawnSync } from "node:child_process";

async function readStdin() {
  let value = "";
  for await (const chunk of process.stdin) value += chunk;
  return value.trim() ? JSON.parse(value) : {};
}

function section(markdown, heading) {
  const marker = `## ${heading}`;
  const start = markdown.indexOf(marker);
  if (start < 0) return "missing";
  const bodyStart = start + marker.length;
  const next = markdown.indexOf("\n## ", bodyStart);
  return markdown
    .slice(bodyStart, next < 0 ? markdown.length : next)
    .trim()
    .slice(0, 2400);
}

function oneLine(markdown, label) {
  const match = markdown.match(new RegExp(`^${label}:\\s*(.+)$`, "m"));
  return match?.[1]?.trim() ?? "missing";
}

const event = await readStdin();
if (event.hook_event_name !== "SessionStart" || event.source !== "compact") {
  process.exit(0);
}

let root;
try {
  root = execFileSync("git", ["rev-parse", "--show-toplevel"], {
    cwd: event.cwd || process.cwd(),
    encoding: "utf8",
  }).trim();
} catch {
  process.exit(0);
}

const statePath = path.join(
  root,
  "docs/plans/ledger-accounting-redesign/conversion/execution-state.md",
);
const checkerPath = path.join(root, "scripts/supabase-conversion-ledger.mjs");
if (!fs.existsSync(statePath) || !fs.existsSync(checkerPath)) process.exit(0);

const state = fs.readFileSync(statePath, "utf8");
const check = spawnSync(process.execPath, [checkerPath, "check"], {
  cwd: root,
  encoding: "utf8",
  timeout: 25_000,
  maxBuffer: 2 * 1024 * 1024,
});
const checkOutput = `${check.stdout ?? ""}\n${check.stderr ?? ""}`
  .trim()
  .split("\n")
  .filter(Boolean)
  .at(-1) ?? "no checker output";
const checkStatus = check.status === 0 ? "PASS" : `FAIL (exit ${check.status ?? "unknown"})`;

const additionalContext = [
  "Ledger Supabase/PowerSync compact-resume guard is active.",
  "Conversation summaries are advisory. Before conversion work continues, read AGENTS.md, the conversion README, this persisted execution state, and—when implementation is active—the complete vertical-slice method and active slice dossier. Inspect the working-tree diff and preserve unrelated work.",
  `Persisted state version: ${oneLine(state, "State version")}`,
  `Persisted checkpoint: ${oneLine(state, "- Checkpoint")}`,
  `Conversion integrity check at compaction: ${checkStatus}; ${checkOutput}`,
  "Persisted Next Action:",
  section(state, "Next Action"),
  "If the check failed during a partial checkpoint, diagnose and restore consistency before advancing status or handing off. Never infer completion from the compacted summary, switch slices silently, implement redesigned behavior in the source backend, or cross a decision/credential/spend/production/migration/cutover gate without the required authority.",
].join("\n\n");

process.stdout.write(
  JSON.stringify({
    hookSpecificOutput: {
      hookEventName: "SessionStart",
      additionalContext,
    },
  }),
);
