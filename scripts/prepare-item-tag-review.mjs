#!/usr/bin/env node
import { existsSync, mkdirSync, readFileSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { basename, dirname, extname, join, resolve } from 'node:path';

const ROOT = resolve(dirname(new URL(import.meta.url).pathname), '..');
const REPORTS = [
  resolve(ROOT, 'tmp/item-tag-fixtures/triage/triage-report.csv'),
  resolve(ROOT, 'tmp/item-tag-fixtures-ross/triage/triage-report.csv'),
];
const MANIFEST_DIRS = {
  'tmp/item-tag-fixtures/triage/triage-report.csv': resolve(ROOT, 'tmp/item-tag-fixtures'),
  'tmp/item-tag-fixtures-ross/triage/triage-report.csv': resolve(ROOT, 'tmp/item-tag-fixtures-ross'),
};
const OUT_DIR = resolve(ROOT, 'tmp/item-tag-fixtures/review-needed');

function parseCSV(text) {
  const rows = [];
  let row = [];
  let cell = '';
  let quoted = false;
  for (let index = 0; index < text.length; index += 1) {
    const char = text[index];
    const next = text[index + 1];
    if (quoted) {
      if (char === '"' && next === '"') {
        cell += '"';
        index += 1;
      } else if (char === '"') {
        quoted = false;
      } else {
        cell += char;
      }
      continue;
    }

    if (char === '"') quoted = true;
    else if (char === ',') {
      row.push(cell);
      cell = '';
    } else if (char === '\n') {
      row.push(cell);
      rows.push(row);
      row = [];
      cell = '';
    } else if (char !== '\r') {
      cell += char;
    }
  }
  if (cell.length || row.length) {
    row.push(cell);
    rows.push(row);
  }

  const header = rows.shift();
  return rows
    .filter((values) => values.length === header.length)
    .map((values) => Object.fromEntries(header.map((key, index) => [key, values[index]])));
}

function csvValue(value) {
  const text = value == null ? '' : String(value);
  return `"${text.replaceAll('"', '""')}"`;
}

function safeName(value) {
  return String(value ?? '')
    .replace(/[^a-zA-Z0-9._-]+/g, '-')
    .replace(/^-|-$/g, '')
    .slice(0, 150) || 'untitled';
}

function hasValue(value) {
  return String(value ?? '').trim().length > 0;
}

function isTrue(value) {
  return String(value).toLowerCase() === 'true';
}

function loadRows() {
  return REPORTS.flatMap((reportPath) => {
    const reportKey = reportPath.replace(`${ROOT}/`, '');
    const imageRoot = MANIFEST_DIRS[reportKey];
    return parseCSV(readFileSync(reportPath, 'utf8')).map((row) => ({
      ...row,
      imageRoot,
      sourceReport: reportKey,
      absoluteImagePath: resolve(imageRoot, row.localPath),
    }));
  });
}

function reviewGroups(rows) {
  const reviewedPositive = (row) => ['01-barcode-detected', '02-expected-sku-found'].includes(row.bucket);
  const correctChipMissing = (row) => reviewedPositive(row) && !isTrue(row.candidateContainsExpected);
  const wrongPrefill = (row) => hasValue(row.selectedSku) && !isTrue(row.selectedMatchesExpected);
  const barcodeContainsExpectedNoPrefill = (row) =>
    reviewedPositive(row) &&
    isTrue(row.barcodeContainsExpected) &&
    !hasValue(row.selectedSku);

  return [
    {
      dir: '01-at-home-reviewed-positive',
      question: 'Is the existing item.sku printed anywhere on these At Home tag/barcode images?',
      rows: rows.filter((row) => row.vendor === 'At Home' && reviewedPositive(row)),
    },
    {
      dir: '02-wrong-prefills',
      question: 'Why did this image prefill a SKU that does not match existing item.sku?',
      rows: rows.filter(wrongPrefill),
    },
    {
      dir: '03-hobby-lobby-chip-missing',
      question: 'Is the expected SKU visible, and if so why did it fail to appear in chips?',
      rows: rows.filter((row) => row.vendor === 'Hobby Lobby' && correctChipMissing(row)),
    },
    {
      dir: '04-barcode-contained-expected-no-prefill',
      question: 'Can barcode safely recover the expected SKU when OCR did not prefill?',
      rows: rows.filter(barcodeContainsExpectedNoPrefill),
    },
  ];
}

function linkName(row, index) {
  const selected = hasValue(row.selectedSku) ? row.selectedSku : 'none';
  const chip = isTrue(row.candidateContainsExpected) ? 'chip-hit' : 'chip-missing';
  const item = safeName(row.itemName);
  const ext = extname(row.absoluteImagePath) || '.jpg';
  return safeName(`${String(index + 1).padStart(3, '0')}__${row.vendor}__expected-${row.expectedSku || 'none'}__selected-${selected}__${chip}__${item}`) + ext;
}

function writeGroup(group) {
  const dir = join(OUT_DIR, group.dir);
  mkdirSync(dir, { recursive: true });
  group.rows.forEach((row, index) => {
    if (!existsSync(row.absoluteImagePath)) return;
    const destination = join(dir, linkName(row, index));
    try {
      rmSync(destination, { force: true });
      symlinkSync(row.absoluteImagePath, destination);
    } catch (error) {
      console.warn(`Failed to link ${row.absoluteImagePath}: ${error.message}`);
    }
  });
}

function writeReviewCSV(groups) {
  const headers = [
    'reviewFolder',
    'reviewQuestion',
    'vendor',
    'expectedSku',
    'selectedSku',
    'selectedMatchesExpected',
    'candidateContainsExpected',
    'barcodeContainsExpected',
    'detectedBarcodes',
    'detectedCandidates',
    'bucket',
    'itemName',
    'projectName',
    'absoluteImagePath',
  ];
  const lines = [headers.join(',')];
  for (const group of groups) {
    for (const row of group.rows) {
      lines.push([
        group.dir,
        group.question,
        row.vendor,
        row.expectedSku,
        row.selectedSku,
        row.selectedMatchesExpected,
        row.candidateContainsExpected,
        row.barcodeContainsExpected,
        row.detectedBarcodes,
        row.detectedCandidates,
        row.bucket,
        row.itemName,
        row.projectName,
        row.absoluteImagePath,
      ].map(csvValue).join(','));
    }
  }
  writeFileSync(join(OUT_DIR, 'review-needed.csv'), `${lines.join('\n')}\n`);
}

const rows = loadRows();
rmSync(OUT_DIR, { recursive: true, force: true });
mkdirSync(OUT_DIR, { recursive: true });
const groups = reviewGroups(rows);
groups.forEach(writeGroup);
writeReviewCSV(groups);

console.log(`Review set written to ${OUT_DIR}`);
for (const group of groups) {
  console.log(`${group.dir}: ${group.rows.length}`);
}
console.log(`CSV: ${join(OUT_DIR, 'review-needed.csv')}`);
