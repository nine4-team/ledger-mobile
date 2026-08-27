#!/usr/bin/env node

import crypto from 'node:crypto';
import fs from 'node:fs';
import { execFileSync } from 'node:child_process';
import { decode } from 'html-entities';

const GWS_CONFIG_DIR = '/Users/benjaminmackenzie/.config/gws-receipts1584';
const MESSAGE_IDS = [
  '19d56009752ee478',
  '19d4f4b25cc58ff5',
  '19d370c04f822ecd',
  '19d2cb67afd66d6f',
  '19cbc76b0110950e',
  '19cbc5fe218e4f43',
  '19c2ec874e0e60d6',
  '19c00824b797aee9',
  '19d3712282732a75',
  '19d2d6d294ff4783',
  '19c16fdb96321755',
  '19c0785856a15ed3',
  '19bc3a3f44cf2275',
  '19d2cab15d9cdc3c',
  '19dcc4f30ec34760',
  '19cbb6752332cfc3',
];

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function sha256(value) {
  return crypto.createHash('sha256').update(value).digest('hex');
}

function cents(value) {
  return Math.round(Number(value.replaceAll(',', '')) * 100);
}

function base64UrlDecode(value) {
  const padded = value.replaceAll('-', '+').replaceAll('_', '/')
    .padEnd(Math.ceil(value.length / 4) * 4, '=');
  return Buffer.from(padded, 'base64').toString('utf8');
}

function parts(part) {
  return [part, ...(part.parts ?? []).flatMap(parts)];
}

function header(message, name) {
  return message.payload.headers.find((entry) => entry.name.toLowerCase() === name.toLowerCase())?.value ?? null;
}

function htmlToText(html) {
  return decode(html
    .replace(/<!--[\s\S]*?-->/g, ' ')
    .replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi, ' ')
    .replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, ' ')
    .replace(/<(br|\/p|\/div|\/tr|\/td|\/th|\/li)\b[^>]*>/gi, '\n')
    .replace(/<[^>]+>/g, ' '))
    .replace(/\r/g, '')
    .replace(/[ \t\f\v]+/g, ' ')
    .replace(/ *\n */g, '\n')
    .replace(/\n{2,}/g, '\n')
    .trim();
}

function firstMatch(text, regex, label, messageId) {
  const match = text.match(regex);
  assert(match, `Could not parse ${label} from Gmail message ${messageId}`);
  return match;
}

function parseReceipt(message) {
  const htmlPart = parts(message.payload).find((part) => part.mimeType === 'text/html' && part.body?.data);
  assert(htmlPart, `Gmail message ${message.id} has no HTML body`);
  const html = base64UrlDecode(htmlPart.body.data);
  const text = htmlToText(html);

  const dateMatch = firstMatch(text, /txn\s*date#:\s*(\d{4})-(\d{2})-(\d{2})/i, 'transaction date', message.id);
  const totalMatch = firstMatch(text, /(?:^|\s)Total\s+\$([0-9,]+\.\d{2})/i, 'total', message.id);
  const subtotalMatch = firstMatch(text, /Subtotal\s+\$([0-9,]+\.\d{2})/i, 'subtotal', message.id);
  const storeMatch = firstMatch(text, /store#:\s*(\d+)/i, 'store number', message.id);
  const transactionMatch = firstMatch(text, /txn#:\s*(\d+)/i, 'transaction number', message.id);
  const cardMatch = firstMatch(text, /\*{4,}(\d{4})/, 'payment card last four', message.id);
  const taxMatch = text.match(/(?:[A-Z]{2}\s+)?([0-9]+(?:\.[0-9]+)?)%\s+Sales Tax\s+\$([0-9,]+\.\d{2})/i);

  const lines = [];
  const lineRegex = /\b(\d{2})\s*-\s*([A-Z0-9/&' .-]+?)\s+([0-9]{6,12})\s+\$([0-9,]+\.\d{2})\s+[TN]\b/g;
  for (const match of text.matchAll(lineRegex)) {
    lines.push({
      departmentCode: match[1],
      department: match[2].trim().replace(/\s+/g, ' '),
      sku: match[3],
      unitPriceCents: cents(match[4]),
      quantity: 1,
    });
  }
  assert(lines.length > 0, `Could not parse receipt lines from Gmail message ${message.id}`);

  const subject = header(message, 'Subject');
  const from = header(message, 'From');
  const brand = subject?.includes('TJ Maxx') ? 'TJ Maxx & HomeGoods'
    : subject?.includes('Marshalls') ? 'Marshalls'
      : 'HomeGoods';

  return {
    messageId: message.id,
    threadId: message.threadId,
    internalDate: new Date(Number(message.internalDate)).toISOString(),
    subject,
    from,
    brand,
    sourceFamily: brand === 'Marshalls' ? 'marshalls' : 'tjx-homegoods',
    date: `${dateMatch[1]}-${dateMatch[2]}-${dateMatch[3]}`,
    subtotalCents: cents(subtotalMatch[1]),
    totalCents: cents(totalMatch[1]),
    taxRatePct: taxMatch ? Number(taxMatch[1]) : null,
    taxCents: taxMatch ? cents(taxMatch[2]) : null,
    storeNumber: storeMatch[1],
    transactionNumber: transactionMatch[1],
    cardLast4: cardMatch[1],
    lines,
    normalizedReceiptTextSha256: sha256(text),
    normalizedReceiptText: text,
  };
}

function getMessage(messageId) {
  const params = JSON.stringify({ userId: 'me', id: messageId, format: 'full' });
  const stdout = execFileSync('gws', ['gmail', 'users', 'messages', 'get', '--params', params], {
    encoding: 'utf8',
    maxBuffer: 20 * 1024 * 1024,
    env: { ...process.env, GOOGLE_WORKSPACE_CLI_CONFIG_DIR: GWS_CONFIG_DIR },
  });
  return JSON.parse(stdout);
}

const outputFlag = process.argv.indexOf('--output');
assert(outputFlag >= 0 && process.argv[outputFlag + 1], '--output /absolute/path.json is required');
const outputPath = process.argv[outputFlag + 1];

const receipts = MESSAGE_IDS.map((messageId) => parseReceipt(getMessage(messageId)))
  .sort((a, b) => a.date.localeCompare(b.date) || a.messageId.localeCompare(b.messageId));
const distinctSkuCount = new Set(receipts.flatMap((receipt) => receipt.lines.map((line) => line.sku))).size;
const payload = {
  schemaVersion: 1,
  generatedAt: new Date().toISOString(),
  mailbox: 'receipts@1584design.com',
  gmailScope: 'https://www.googleapis.com/auth/gmail.readonly',
  messageCount: receipts.length,
  distinctReceiptSkuCount: distinctSkuCount,
  receipts,
};
fs.writeFileSync(outputPath, `${JSON.stringify(payload, null, 2)}\n`);
console.log(JSON.stringify({ outputPath, messageCount: receipts.length, distinctReceiptSkuCount: distinctSkuCount }, null, 2));
