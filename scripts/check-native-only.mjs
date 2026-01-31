import fs from 'node:fs/promises';
import path from 'node:path';

const ROOT = process.cwd();
const TARGET_DIRS = ['src', 'app'];
const ALLOWED_EXTENSIONS = new Set(['.ts', '.tsx', '.js', '.jsx', '.mjs', '.cjs']);

const FORBIDDEN_PATTERNS = [
  /from\s+['"]firebase\//g, // import ... from 'firebase/firestore'
  /require\(\s*['"]firebase\//g, // require('firebase/firestore')
];

async function listFilesRecursive(dirAbs) {
  const entries = await fs.readdir(dirAbs, { withFileTypes: true });
  const out = [];
  for (const entry of entries) {
    const abs = path.join(dirAbs, entry.name);
    if (entry.isDirectory()) {
      out.push(...(await listFilesRecursive(abs)));
      continue;
    }
    if (entry.isFile()) out.push(abs);
  }
  return out;
}

function isAllowedSourceFile(fileAbs) {
  return ALLOWED_EXTENSIONS.has(path.extname(fileAbs));
}

function toRelative(fileAbs) {
  return path.relative(ROOT, fileAbs);
}

async function main() {
  const offenders = [];

  for (const relDir of TARGET_DIRS) {
    const dirAbs = path.join(ROOT, relDir);
    let files = [];
    try {
      files = await listFilesRecursive(dirAbs);
    } catch {
      // If a target directory doesn't exist, skip.
      continue;
    }

    for (const fileAbs of files) {
      if (!isAllowedSourceFile(fileAbs)) continue;

      const content = await fs.readFile(fileAbs, 'utf8');
      const matches = FORBIDDEN_PATTERNS.some((re) => re.test(content));
      // Reset regex state for global regexes across files.
      FORBIDDEN_PATTERNS.forEach((re) => (re.lastIndex = 0));

      if (matches) offenders.push(toRelative(fileAbs));
    }
  }

  if (offenders.length > 0) {
    console.error('[native-only] Firebase Web SDK imports detected in app/src code:');
    for (const file of offenders) console.error(`- ${file}`);
    console.error(
      "\nRemove any `import ... from 'firebase/*'` usage. Use `@react-native-firebase/*` instead."
    );
    process.exit(1);
  }

  console.log('[native-only] OK: no Firebase Web SDK imports in app/src.');
}

await main();

