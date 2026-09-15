import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const root = fileURLToPath(new URL('../../', import.meta.url));
test('original CSV calculations work without Firebase and retain exact values', {
  skip: process.platform !== 'darwin' ? 'Native Swift Foundation check runs on macOS' : false,
}, () => {
  const scratch = mkdtempSync(path.join(tmpdir(), 'ledger-csv-check-'));
  try {
    const executable = path.join(scratch, 'check');
    execFileSync('swiftc', ['LedgeriOS/LedgeriOS/Logic/TransactionExportCalculations.swift',
      'LedgeriOS/LedgeriOS/Logic/ExportFieldConfig.swift',
      'scripts/tests/transaction-export-calculations.swift', '-o', executable], {
      cwd: root, timeout: 30_000, stdio: 'pipe',
    });
    assert.match(execFileSync(executable, { encoding: 'utf8', timeout: 5_000 }), /^PASS: shared CSV/);
  } finally {
    rmSync(scratch, { recursive: true, force: true });
  }
});
