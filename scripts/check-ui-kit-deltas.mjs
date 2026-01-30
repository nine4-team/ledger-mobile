import fs from 'node:fs';
import path from 'node:path';

const ROOT = process.cwd();
const SRC_DIR = path.join(ROOT, 'src');
const UI_DIR = path.join(SRC_DIR, 'ui');
const MARKER = 'TODO(ui-kit):';

/** @returns {string[]} */
function listFilesRecursive(dir) {
  /** @type {string[]} */
  const out = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      out.push(...listFilesRecursive(full));
    } else {
      out.push(full);
    }
  }
  return out;
}

function isCodeFile(filePath) {
  return (
    filePath.endsWith('.ts') ||
    filePath.endsWith('.tsx') ||
    filePath.endsWith('.js') ||
    filePath.endsWith('.jsx') ||
    filePath.endsWith('.md')
  );
}

function rel(p) {
  return path.relative(ROOT, p);
}

const allFiles = fs.existsSync(SRC_DIR) ? listFilesRecursive(SRC_DIR).filter(isCodeFile) : [];
const markerHits = [];

for (const file of allFiles) {
  const text = fs.readFileSync(file, 'utf8');
  const idx = text.indexOf(MARKER);
  if (idx !== -1) markerHits.push(file);
}

const hitsOutsideUi = markerHits.filter((f) => !f.startsWith(UI_DIR + path.sep));

if (hitsOutsideUi.length > 0) {
  console.error(`Found \`${MARKER}\` outside \`src/ui\`. Move these deltas into the ui stash:\n`);
  for (const f of hitsOutsideUi) console.error(`- ${rel(f)}`);
  console.error(`\nRule: app-only tokens/styles/components intended for UI-kit graduation must live in \`src/ui/**\`.`);
  process.exit(1);
}

console.log(`UI-kit deltas are centralized. Files in \`src/ui\` containing \`${MARKER}\`:\n`);
if (markerHits.length === 0) {
  console.log('- (none)');
} else {
  for (const f of markerHits) console.log(`- ${rel(f)}`);
}

