import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, mkdirSync, writeFileSync, renameSync, unlinkSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import test from "node:test";
import { checkSourceBaseline, discoverSourceBaseline, loadSourceInventory } from "../supabase-conversion-ledger.mjs";

const inventoryPath = "docs/plans/ledger-accounting-redesign/conversion/conversion-manifest.json";
const sourcePath = "LedgeriOS/LedgeriOS/Components/Gallery.swift";

function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), "ledger-source-baseline-"));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const git = (...args) => execFileSync("git", args, { cwd: root, encoding: "utf8", stdio: ["pipe", "pipe", "pipe"] }).trim();
  const write = (path, value) => { mkdirSync(dirname(join(root, path)), { recursive: true }); writeFileSync(join(root, path), value); };
  git("init", "--quiet");
  git("config", "user.name", "Baseline test");
  git("config", "user.email", "baseline-test@example.invalid");
  git("config", "core.hooksPath", join(root, "no-hooks"));
  const commit = () => { git("add", "."); git("-c", "commit.gpgsign=false", "commit", "--quiet", "-m", "Synthetic baseline fixture"); return git("rev-parse", "HEAD"); };
  write(sourcePath, "// café: original gallery\nstruct Gallery {}\n");
  write("firebase/firestore.rules", "match /items/{item} { allow read: if false; }\n");
  write("mcp-server/src/items.ts", 'server.tool("items", {});\n');
  const base = commit();
  const inventory = { schemaVersion: 1, sourceBaseline: { commit: base }, surfaces: discoverSourceBaseline(base, root) };
  const save = () => { write(inventoryPath, JSON.stringify(inventory)); return { sourceBaseline: { commit: base, inventoryCommit: commit() } }; };
  const recorded = save();
  return { root, git, write, commit, inventory, save, recorded };
}

test("target edits, extraction, deletion and commits do not resynchronize the saved inventory", (t) => {
  const f = fixture(t);
  assert.deepEqual(checkSourceBaseline(f.recorded, f.root).errors, []);
  renameSync(join(f.root, sourcePath), join(f.root, "LedgeriOS/LedgeriOS/Components/SharedGallery.swift"));
  f.write("LedgeriOS/LedgeriOS/Components/SharedGallery.swift", "struct SharedGallery {}\n");
  f.write("LedgeriOS/LedgerTargetApp/NewView.swift", "struct NewView {}\n");
  f.commit();
  f.write(inventoryPath, "not used by the frozen inventory reader");
  assert.deepEqual(checkSourceBaseline(f.recorded, f.root).errors, []);
  assert.equal(loadSourceInventory(f.recorded, f.root).surfaces.length, f.inventory.surfaces.length);
});

test("an omitted original source in a saved inventory still fails", (t) => {
  const f = fixture(t);
  f.inventory.surfaces = f.inventory.surfaces.filter((s) => s.name !== sourcePath);
  assert.match(checkSourceBaseline(f.save(), f.root).errors.join("\n"), /new unrecorded source/);
});

test("an incorrect saved source hash still fails", (t) => {
  const f = fixture(t);
  f.inventory.surfaces.find((s) => s.name === sourcePath).observedSourceHash = "wrong";
  assert.match(checkSourceBaseline(f.save(), f.root).errors.join("\n"), /source hash changed/);
});

test("a source added or removed in a newly selected snapshot needs review", (t) => {
  const f = fixture(t);
  f.write("LedgeriOS/LedgeriOS/Components/Unreviewed.swift", "struct Unreviewed {}\n");
  unlinkSync(join(f.root, sourcePath));
  const result = checkSourceBaseline(f.save(), f.root);
  assert.match(result.errors.join("\n"), /new unrecorded source/);
  assert.match(result.errors.join("\n"), /disappeared without retirement/);
});

test("missing, symbolic and inconsistent baseline pointers fail without a live-file fallback", (t) => {
  const f = fixture(t);
  assert.throws(() => checkSourceBaseline({ sourceBaseline: { ...f.recorded.sourceBaseline, inventoryCommit: "HEAD" } }, f.root), /exact local Git commit/);
  assert.throws(() => checkSourceBaseline({ sourceBaseline: { ...f.recorded.sourceBaseline, inventoryCommit: "0".repeat(40) } }, f.root));
  assert.throws(() => checkSourceBaseline({ sourceBaseline: { ...f.recorded.sourceBaseline, commit: f.recorded.sourceBaseline.inventoryCommit } }, f.root), /different baseline/);
  assert.throws(() => checkSourceBaseline({ sourceBaseline: { commit: f.recorded.sourceBaseline.commit } }, f.root), /exact local Git commit/);
});
