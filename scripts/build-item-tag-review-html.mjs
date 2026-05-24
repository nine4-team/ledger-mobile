#!/usr/bin/env node
import { readFileSync, writeFileSync } from 'node:fs';
import { relative, resolve } from 'node:path';

const ROOT = resolve(new URL('..', import.meta.url).pathname);
const CSV_PATH = resolve(ROOT, 'tmp/item-tag-fixtures/review-needed/review-needed.csv');
const OUT_PATH = resolve(ROOT, 'tmp/item-tag-fixtures/review-needed/review.html');

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

function escapeHTML(value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
}

function fileURL(path) {
  return relative(resolve(CSV_PATH, '..'), path).split('/').map(encodeURIComponent).join('/');
}

function pill(text, tone = '') {
  if (!text) return '';
  return `<span class="pill ${tone}">${escapeHTML(text)}</span>`;
}

function splitValues(value) {
  return String(value ?? '')
    .split('|')
    .map((part) => part.trim())
    .filter(Boolean);
}

function rowCard(row, index) {
  const chips = splitValues(row.detectedCandidates).map((value) => pill(value)).join('');
  const barcodes = splitValues(row.detectedBarcodes).map((value) => pill(value, 'barcode')).join('');
  const ocrLines = splitValues(row.detectedTextLines)
    .map((value) => `<li>${escapeHTML(value)}</li>`)
    .join('');
  const selectedTone = row.selectedMatchesExpected === 'true' ? 'good' : row.selectedSku ? 'bad' : 'muted';
  return `
    <article class="card">
      <a href="${fileURL(row.absoluteImagePath)}"><img src="${fileURL(row.absoluteImagePath)}" loading="lazy" /></a>
      <section>
        <div class="eyebrow">${escapeHTML(String(index + 1).padStart(3, '0'))} · ${escapeHTML(row.vendor)} · ${escapeHTML(row.bucket)}</div>
        <h2>${escapeHTML(row.itemName)}</h2>
        <div class="facts">
          <div><strong>Expected item.sku</strong><code>${escapeHTML(row.expectedSku || 'none')}</code></div>
          <div><strong>Selected / prefilled</strong><code class="${selectedTone}">${escapeHTML(row.selectedSku || 'none')}</code></div>
          <div><strong>Correct SKU in chips?</strong><code>${escapeHTML(row.candidateContainsExpected)}</code></div>
          <div><strong>Barcode contains expected?</strong><code>${escapeHTML(row.barcodeContainsExpected)}</code></div>
        </div>
        <div class="values">
          <strong>Candidate chips</strong>
          <div class="pillrow">${chips || '<span class="empty">none</span>'}</div>
        </div>
        <div class="values">
          <strong>Barcode payloads</strong>
          <div class="pillrow">${barcodes || '<span class="empty">none</span>'}</div>
        </div>
        <details>
          <summary>OCR text lines</summary>
          <ol>${ocrLines || '<li class="empty">none</li>'}</ol>
        </details>
        <p class="question">${escapeHTML(row.reviewQuestion)}</p>
      </section>
    </article>
  `;
}

const rows = parseCSV(readFileSync(CSV_PATH, 'utf8'));
const groups = rows.reduce((map, row) => {
  if (!map.has(row.reviewFolder)) map.set(row.reviewFolder, []);
  map.get(row.reviewFolder).push(row);
  return map;
}, new Map());
const body = [...groups.entries()].map(([folder, groupRows]) => `
  <h1>${escapeHTML(folder)} <span>${groupRows.length}</span></h1>
  <p class="group-question">${escapeHTML(groupRows[0]?.reviewQuestion ?? '')}</p>
  ${groupRows.map(rowCard).join('\n')}
`).join('\n');

writeFileSync(OUT_PATH, `<!doctype html>
<html>
<head>
  <meta charset="utf-8" />
  <title>Item Tag Review</title>
  <style>
    body { margin: 0; padding: 28px; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; background: #f6f5f2; color: #1e1f22; }
    h1 { margin: 34px 0 4px; font-size: 28px; }
    h1 span { color: #666; font-weight: 500; }
    h2 { margin: 3px 0 12px; font-size: 18px; line-height: 1.2; }
    .group-question { margin: 0 0 18px; color: #555; }
    .card { display: grid; grid-template-columns: minmax(260px, 420px) 1fr; gap: 18px; align-items: start; margin: 0 0 18px; padding: 14px; border: 1px solid #ddd8cf; border-radius: 8px; background: white; }
    img { display: block; width: 100%; max-height: 520px; object-fit: contain; background: #eee; border-radius: 4px; }
    .eyebrow { color: #777; font-size: 12px; text-transform: uppercase; letter-spacing: .04em; }
    .facts { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 10px; margin-bottom: 12px; }
    .facts strong, .values strong { display: block; color: #60636a; font-size: 12px; margin-bottom: 4px; }
    code { display: inline-block; padding: 3px 6px; border-radius: 5px; background: #f1f1f1; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 13px; }
    code.good { background: #e8f5ec; color: #176b35; }
    code.bad { background: #ffefef; color: #a32121; }
    code.muted { color: #777; }
    .values { margin: 10px 0; }
    .pillrow { display: flex; flex-wrap: wrap; gap: 6px; }
    .pill { padding: 4px 7px; border-radius: 999px; background: #eef0f4; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 12px; }
    .pill.barcode { background: #fff2d8; }
    .empty { color: #888; font-style: italic; }
    details { margin-top: 10px; }
    summary { cursor: pointer; color: #3f4650; font-size: 13px; font-weight: 650; }
    ol { margin: 8px 0 0; padding-left: 22px; color: #30343a; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 12px; line-height: 1.45; }
    .question { margin: 12px 0 0; color: #555; font-size: 14px; }
    @media (max-width: 760px) { body { padding: 12px; } .card { grid-template-columns: 1fr; } .facts { grid-template-columns: 1fr; } }
  </style>
</head>
<body>
  ${body}
</body>
</html>
`);

console.log(OUT_PATH);
