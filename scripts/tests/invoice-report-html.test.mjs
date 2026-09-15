import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const root = fileURLToPath(new URL('../../', import.meta.url));
test('shared Invoice HTML retains exact authorized display data without a backend', {
  skip: process.platform !== 'darwin' ? 'Foundation currency formatting check requires macOS' : false,
}, () => {
  const scratch = mkdtempSync(path.join(tmpdir(), 'ledger-invoice-render-check-'));
  try {
    const executable = path.join(scratch, 'check');
    execFileSync('swiftc', ['LedgeriOS/LedgeriOS/Logic/InvoiceReportData.swift',
      'LedgeriOS/LedgeriOS/Views/Reports/ReportHTMLBuilder.swift',
      'scripts/tests/invoice-report-html.swift', '-o', executable], {
      cwd: root, timeout: 30_000, stdio: 'pipe',
    });
    const output = execFileSync(executable, { encoding: 'utf8', timeout: 5_000 });
    assert.match(output, /^PASS: shared Invoice/);
    console.log(output.trim());
  } finally { rmSync(scratch, { recursive: true, force: true }); }
});
