#!/usr/bin/env node
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';

const ROOT = resolve(dirname(new URL(import.meta.url).pathname), '..');
const REPORTS = [
  resolve(ROOT, 'tmp/item-tag-fixtures/triage/triage-report.csv'),
  resolve(ROOT, 'tmp/item-tag-fixtures-ross/triage/triage-report.csv'),
];
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
      } else if (char === '"') quoted = false;
      else cell += char;
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
    } else if (char !== '\r') cell += char;
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

function isTrue(value) {
  return String(value).toLowerCase() === 'true';
}

function hasValue(value) {
  return String(value ?? '').trim().length > 0;
}

function normalizeSku(value) {
  return String(value ?? '').replace(/[^a-zA-Z0-9]/g, '').toLowerCase();
}

function splitValues(value) {
  return String(value ?? '')
    .split('|')
    .map((part) => part.trim())
    .filter(Boolean);
}

function pct(numerator, denominator) {
  if (!denominator) return '0.0%';
  return `${((numerator / denominator) * 100).toFixed(1)}%`;
}

function loadRows() {
  return REPORTS.flatMap((reportPath) => parseCSV(readFileSync(reportPath, 'utf8')));
}

function reviewedPositive(row) {
  return ['01-barcode-detected', '02-expected-sku-found'].includes(row.bucket) && hasValue(row.expectedSku);
}

function detectedTextContainsExpected(row) {
  const expected = normalizeSku(row.expectedSku);
  if (!expected) return false;
  return splitValues(row.detectedTextLines).some((line) => normalizeSku(line).includes(expected));
}

function failureReason(row) {
  if (isTrue(row.candidateContainsExpected) && isTrue(row.selectedMatchesExpected)) return 'correct_prefill';
  if (isTrue(row.candidateContainsExpected) && !hasValue(row.selectedSku)) return 'correct_chip_no_prefill';
  if (isTrue(row.candidateContainsExpected) && hasValue(row.selectedSku)) return 'ranking_chose_wrong';
  if (detectedTextContainsExpected(row)) return 'parser_dropped_expected_text';
  if (isTrue(row.barcodeContainsExpected)) return 'barcode_contains_expected_but_ocr_missed';
  return 'ocr_missed_expected';
}

function countBy(rows, keyFn) {
  const counts = new Map();
  for (const row of rows) {
    const key = keyFn(row);
    counts.set(key, (counts.get(key) ?? 0) + 1);
  }
  return [...counts.entries()].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]));
}

const rows = loadRows();
const positives = rows.filter(reviewedPositive);
const correctChipRows = positives.filter((row) => isTrue(row.candidateContainsExpected));
const correctPrefillRows = positives.filter((row) => isTrue(row.selectedMatchesExpected));
const wrongPrefillRows = positives.filter((row) => hasValue(row.selectedSku) && !isTrue(row.selectedMatchesExpected));
const noPrefillRows = positives.filter((row) => !hasValue(row.selectedSku));
const missRows = positives.filter((row) => !isTrue(row.candidateContainsExpected));

const lines = [
  '# Item Tag SKU Extraction Diagnostics',
  '',
  'Denominator: reviewed-positive images, meaning images in `01-barcode-detected` or `02-expected-sku-found` that have an existing `item.sku`.',
  '',
  '| Metric | Count | Percent | Denominator |',
  '| --- | ---: | ---: | ---: |',
  `| Correct SKU appears in chips | ${correctChipRows.length} | ${pct(correctChipRows.length, positives.length)} | ${positives.length} |`,
  `| Correct SKU is prefilled | ${correctPrefillRows.length} | ${pct(correctPrefillRows.length, positives.length)} | ${positives.length} |`,
  `| Wrong SKU is prefilled | ${wrongPrefillRows.length} | ${pct(wrongPrefillRows.length, positives.length)} | ${positives.length} |`,
  `| No SKU is prefilled | ${noPrefillRows.length} | ${pct(noPrefillRows.length, positives.length)} | ${positives.length} |`,
  `| Correct chip becomes correct prefill | ${correctPrefillRows.length} | ${pct(correctPrefillRows.length, correctChipRows.length)} | ${correctChipRows.length} |`,
  `| Prefill precision | ${correctPrefillRows.length} | ${pct(correctPrefillRows.length, correctPrefillRows.length + wrongPrefillRows.length)} | ${correctPrefillRows.length + wrongPrefillRows.length} |`,
  '',
  '## Failure Reasons',
  '',
  '| Reason | Count | Percent of reviewed-positive |',
  '| --- | ---: | ---: |',
  ...countBy(positives, failureReason).map(([reason, count]) => `| ${reason} | ${count} | ${pct(count, positives.length)} |`),
  '',
  '## Correct Chip Coverage by Vendor',
  '',
  '| Vendor | Correct chips | Denominator | Percent |',
  '| --- | ---: | ---: | ---: |',
  ...countBy(positives, (row) => row.vendor).map(([vendor]) => {
    const vendorRows = positives.filter((row) => row.vendor === vendor);
    const vendorCorrect = vendorRows.filter((row) => isTrue(row.candidateContainsExpected));
    return `| ${vendor} | ${vendorCorrect.length} | ${vendorRows.length} | ${pct(vendorCorrect.length, vendorRows.length)} |`;
  }),
  '',
  '## Prefill Accuracy by Vendor',
  '',
  '| Vendor | Correct prefill | Wrong prefill | No prefill | Denominator |',
  '| --- | ---: | ---: | ---: | ---: |',
  ...countBy(positives, (row) => row.vendor).map(([vendor]) => {
    const vendorRows = positives.filter((row) => row.vendor === vendor);
    const correct = vendorRows.filter((row) => isTrue(row.selectedMatchesExpected)).length;
    const wrong = vendorRows.filter((row) => hasValue(row.selectedSku) && !isTrue(row.selectedMatchesExpected)).length;
    const none = vendorRows.filter((row) => !hasValue(row.selectedSku)).length;
    return `| ${vendor} | ${correct} | ${wrong} | ${none} | ${vendorRows.length} |`;
  }),
  '',
  '## Miss CSV',
  '',
  'See `failure-diagnostics.csv` for one row per reviewed-positive miss.',
  '',
];

const csvHeaders = [
  'failureReason',
  'vendor',
  'expectedSku',
  'selectedSku',
  'bucket',
  'detectedCandidates',
  'detectedBarcodes',
  'detectedTextLines',
  'localPath',
  'itemName',
  'projectName',
];
const csvLines = [csvHeaders.join(',')];
for (const row of missRows.concat(wrongPrefillRows.filter((row) => isTrue(row.candidateContainsExpected)))) {
  csvLines.push([
    failureReason(row),
    row.vendor,
    row.expectedSku,
    row.selectedSku,
    row.bucket,
    row.detectedCandidates,
    row.detectedBarcodes,
    row.detectedTextLines,
    row.localPath,
    row.itemName,
    row.projectName,
  ].map(csvValue).join(','));
}

mkdirSync(OUT_DIR, { recursive: true });
writeFileSync(join(OUT_DIR, 'failure-diagnostics.md'), `${lines.join('\n')}\n`);
writeFileSync(join(OUT_DIR, 'failure-diagnostics.csv'), `${csvLines.join('\n')}\n`);
console.log(join(OUT_DIR, 'failure-diagnostics.md'));
console.log(join(OUT_DIR, 'failure-diagnostics.csv'));
