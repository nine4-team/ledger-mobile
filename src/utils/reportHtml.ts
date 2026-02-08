import type {
  InvoiceReportData,
  InvoiceLine,
  ClientSummaryData,
  ClientSummaryItem,
  PropertyManagementData,
  PropertyManagementItem,
} from '../data/reportDataService';
import { formatCents } from '../data/reportDataService';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export type ReportHeaderParams = {
  businessName: string;
  logoUrl: string | null;
  projectName: string;
  clientName: string;
};

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

function escapeHtml(text: string): string {
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}

function getReportStyles(): string {
  return `
    * {
      box-sizing: border-box;
      margin: 0;
      padding: 0;
    }
    body {
      font-family: -apple-system, 'Helvetica Neue', Helvetica, Arial, sans-serif;
      font-size: 13px;
      line-height: 1.5;
      color: #1a1a1a;
      padding: 40px;
      max-width: 800px;
      margin: 0 auto;
    }
    @media print {
      body {
        padding: 20px;
      }
    }
    .report-header {
      display: flex;
      align-items: flex-start;
      gap: 16px;
      margin-bottom: 32px;
      padding-bottom: 20px;
      border-bottom: 2px solid #987e55;
    }
    .report-logo {
      width: 80px;
      height: 80px;
      object-fit: contain;
      border-radius: 8px;
    }
    .report-header-info {
      flex: 1;
    }
    .report-header-info h1 {
      font-size: 22px;
      font-weight: 700;
      color: #987e55;
      margin-bottom: 4px;
    }
    .report-header-info .report-title {
      font-size: 16px;
      font-weight: 600;
      color: #333;
      margin-bottom: 8px;
    }
    .report-header-info .meta {
      font-size: 12px;
      color: #666;
      line-height: 1.6;
    }
    h2 {
      font-size: 16px;
      font-weight: 600;
      color: #987e55;
      margin-top: 28px;
      margin-bottom: 12px;
      padding-bottom: 6px;
      border-bottom: 1px solid #e0d5c5;
    }
    h3 {
      font-size: 14px;
      font-weight: 600;
      color: #333;
      margin-top: 16px;
      margin-bottom: 8px;
    }
    table {
      width: 100%;
      border-collapse: collapse;
      margin-bottom: 16px;
      page-break-inside: auto;
    }
    thead {
      background-color: #f7f3ee;
    }
    th {
      font-size: 11px;
      font-weight: 600;
      text-transform: uppercase;
      color: #666;
      text-align: left;
      padding: 8px 10px;
      border-bottom: 1px solid #e0d5c5;
    }
    th.right, td.right {
      text-align: right;
    }
    td {
      padding: 8px 10px;
      border-bottom: 1px solid #f0ebe4;
      vertical-align: top;
    }
    tr:nth-child(even) td {
      background-color: #faf8f5;
    }
    tr {
      page-break-inside: avoid;
    }
    .totals-table {
      width: auto;
      margin-left: auto;
      margin-top: 12px;
      margin-bottom: 24px;
    }
    .totals-table td {
      padding: 6px 12px;
      border-bottom: none;
      background-color: transparent !important;
    }
    .totals-table .total-label {
      font-weight: 600;
      color: #333;
      text-align: right;
    }
    .totals-table .total-value {
      font-weight: 600;
      text-align: right;
      min-width: 100px;
    }
    .totals-table .net-row td {
      border-top: 2px solid #987e55;
      font-size: 15px;
      font-weight: 700;
      color: #987e55;
      padding-top: 10px;
    }
    .missing-price {
      font-style: italic;
      color: #c0392b;
      font-size: 11px;
    }
    .empty-state {
      padding: 24px;
      text-align: center;
      color: #999;
      font-style: italic;
    }
    .card {
      background: #faf8f5;
      border: 1px solid #e0d5c5;
      border-radius: 8px;
      padding: 16px;
      margin-bottom: 12px;
    }
    .card-label {
      font-size: 11px;
      font-weight: 600;
      text-transform: uppercase;
      color: #666;
      margin-bottom: 4px;
    }
    .card-value {
      font-size: 20px;
      font-weight: 700;
      color: #1a1a1a;
    }
    .overview-grid {
      display: flex;
      gap: 12px;
      margin-bottom: 20px;
    }
    .overview-grid .card {
      flex: 1;
    }
    .receipt-badge {
      display: inline-block;
      font-size: 10px;
      font-weight: 600;
      color: #987e55;
      background: #f7f3ee;
      border-radius: 4px;
      padding: 2px 6px;
      margin-left: 6px;
    }
    .item-sub {
      font-size: 11px;
      color: #888;
      padding-left: 20px;
    }
    .footer {
      margin-top: 40px;
      padding-top: 16px;
      border-top: 1px solid #e0d5c5;
      font-size: 11px;
      color: #999;
      text-align: center;
    }
  `;
}

function generateHeaderHtml(params: ReportHeaderParams, reportTitle: string): string {
  const { businessName, logoUrl, projectName, clientName } = params;
  const now = new Date();
  const dateStr = now.toLocaleDateString('en-US', {
    year: 'numeric',
    month: 'long',
    day: 'numeric',
  });

  const logoHtml =
    logoUrl && logoUrl.startsWith('http')
      ? `<img class="report-logo" src="${escapeHtml(logoUrl)}" alt="Logo" />`
      : '';

  return `
    <div class="report-header">
      ${logoHtml}
      <div class="report-header-info">
        <h1>${escapeHtml(businessName)}</h1>
        <div class="report-title">${escapeHtml(reportTitle)}</div>
        <div class="meta">
          <strong>Project:</strong> ${escapeHtml(projectName)}<br/>
          <strong>Client:</strong> ${escapeHtml(clientName)}<br/>
          <strong>Date:</strong> ${escapeHtml(dateStr)}
        </div>
      </div>
    </div>
  `;
}

function wrapHtml(title: string, body: string): string {
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>${escapeHtml(title)}</title>
  <style>${getReportStyles()}</style>
</head>
<body>
  ${body}
</body>
</html>`;
}

// ---------------------------------------------------------------------------
// Invoice Report
// ---------------------------------------------------------------------------

function renderInvoiceLinesTable(lines: InvoiceLine[], label: string): string {
  if (lines.length === 0) {
    return `<h2>${escapeHtml(label)}</h2><p class="empty-state">No invoiceable transactions found.</p>`;
  }

  const rows = lines.map((line) => {
    const dateStr = line.date ?? '';
    const categoryStr = line.budgetCategoryName ?? '';
    const amountStr = formatCents(line.amountCents);

    let itemsSub = '';
    if (line.items.length > 0) {
      const itemRows = line.items
        .map((item) => {
          const priceStr = item.isMissingPrice
            ? `<span class="missing-price">${formatCents(item.projectPriceCents)} (missing price)</span>`
            : formatCents(item.projectPriceCents);
          return `<div class="item-sub">${escapeHtml(item.name)} &mdash; ${priceStr}</div>`;
        })
        .join('');
      itemsSub = itemRows;
    }

    const missingFlag = line.hasMissingPrices
      ? ' <span class="missing-price">(contains missing prices)</span>'
      : '';

    return `
      <tr>
        <td>${escapeHtml(dateStr)}</td>
        <td>${escapeHtml(line.title)}${missingFlag}${itemsSub}</td>
        <td>${escapeHtml(categoryStr)}</td>
        <td class="right">${amountStr}</td>
      </tr>
    `;
  }).join('');

  return `
    <h2>${escapeHtml(label)}</h2>
    <table>
      <thead>
        <tr>
          <th style="width:100px">Date</th>
          <th>Description</th>
          <th style="width:140px">Category</th>
          <th class="right" style="width:110px">Amount</th>
        </tr>
      </thead>
      <tbody>
        ${rows}
      </tbody>
    </table>
  `;
}

export function generateInvoiceHtml(data: InvoiceReportData, header: ReportHeaderParams): string {
  const headerHtml = generateHeaderHtml(header, 'Invoice Report');

  if (!data.hasData) {
    return wrapHtml('Invoice Report', `
      ${headerHtml}
      <p class="empty-state">No invoiceable transactions found.</p>
    `);
  }

  const chargesHtml = renderInvoiceLinesTable(data.chargeLines, 'Charges');
  const creditsHtml = renderInvoiceLinesTable(data.creditLines, 'Credits');

  const totalsHtml = `
    <table class="totals-table">
      <tbody>
        <tr>
          <td class="total-label">Charges Total</td>
          <td class="total-value">${formatCents(data.chargesTotalCents)}</td>
        </tr>
        <tr>
          <td class="total-label">Credits Total</td>
          <td class="total-value">(${formatCents(data.creditsTotalCents)})</td>
        </tr>
        <tr class="net-row">
          <td class="total-label">Net Amount Due</td>
          <td class="total-value">${formatCents(data.netAmountDueCents)}</td>
        </tr>
      </tbody>
    </table>
  `;

  return wrapHtml('Invoice Report', `
    ${headerHtml}
    ${chargesHtml}
    ${creditsHtml}
    ${totalsHtml}
    <div class="footer">Generated on ${new Date().toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric' })}</div>
  `);
}

// ---------------------------------------------------------------------------
// Client Summary Report
// ---------------------------------------------------------------------------

function renderClientSummaryItemRow(item: ClientSummaryItem): string {
  let receiptBadge = '';
  if (item.receiptLink) {
    if (item.receiptLink.type === 'invoice') {
      receiptBadge = '<span class="receipt-badge">Invoice</span>';
    } else if (item.receiptLink.type === 'receipt-url') {
      receiptBadge = '<span class="receipt-badge">Receipt</span>';
    } else if (item.receiptLink.type === 'pending-upload') {
      receiptBadge = '<span class="receipt-badge" style="opacity:0.6">Pending Upload</span>';
    }
  }

  return `
    <tr>
      <td>${escapeHtml(item.name)}${receiptBadge}</td>
      <td>${escapeHtml(item.source ?? '')}</td>
      <td>${escapeHtml(item.spaceName ?? '')}</td>
      <td class="right">${formatCents(item.projectPriceCents)}</td>
    </tr>
  `;
}

export function generateClientSummaryHtml(data: ClientSummaryData, header: ReportHeaderParams): string {
  const headerHtml = generateHeaderHtml(header, 'Client Summary Report');

  if (!data.hasData) {
    return wrapHtml('Client Summary Report', `
      ${headerHtml}
      <p class="empty-state">No items found.</p>
    `);
  }

  const overviewHtml = `
    <div class="overview-grid">
      <div class="card">
        <div class="card-label">Total Spent</div>
        <div class="card-value">${formatCents(data.totalSpentCents)}</div>
      </div>
      <div class="card">
        <div class="card-label">Market Value</div>
        <div class="card-value">${formatCents(data.totalMarketValueCents)}</div>
      </div>
      <div class="card">
        <div class="card-label">Total Saved</div>
        <div class="card-value">${formatCents(data.totalSavedCents)}</div>
      </div>
    </div>
  `;

  let categoryHtml = '';
  if (data.categoryBreakdown.length > 0) {
    const categoryRows = data.categoryBreakdown
      .map(
        (entry) => `
        <tr>
          <td>${escapeHtml(entry.categoryName)}</td>
          <td class="right">${formatCents(entry.totalCents)}</td>
        </tr>
      `
      )
      .join('');

    categoryHtml = `
      <h2>Category Breakdown</h2>
      <table>
        <thead>
          <tr>
            <th>Category</th>
            <th class="right" style="width:120px">Total</th>
          </tr>
        </thead>
        <tbody>
          ${categoryRows}
        </tbody>
      </table>
    `;
  }

  const itemRows = data.items.map(renderClientSummaryItemRow).join('');

  const itemsHtml = `
    <h2>Items</h2>
    <table>
      <thead>
        <tr>
          <th>Item</th>
          <th style="width:120px">Source</th>
          <th style="width:120px">Space</th>
          <th class="right" style="width:110px">Project Price</th>
        </tr>
      </thead>
      <tbody>
        ${itemRows}
      </tbody>
    </table>
  `;

  return wrapHtml('Client Summary Report', `
    ${headerHtml}
    ${overviewHtml}
    ${categoryHtml}
    ${itemsHtml}
    <div class="footer">Generated on ${new Date().toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric' })}</div>
  `);
}

// ---------------------------------------------------------------------------
// Property Management Summary Report
// ---------------------------------------------------------------------------

function renderPropertyManagementItemRow(item: PropertyManagementItem): string {
  const valueStr = item.hasNoMarketValue
    ? '<span class="missing-price">No market value</span>'
    : formatCents(item.marketValueCents);

  return `
    <tr>
      <td>${escapeHtml(item.name)}</td>
      <td>${escapeHtml(item.source ?? '')}</td>
      <td>${escapeHtml(item.sku ?? '')}</td>
      <td>${escapeHtml(item.spaceName ?? '')}</td>
      <td class="right">${valueStr}</td>
    </tr>
  `;
}

export function generatePropertyManagementHtml(
  data: PropertyManagementData,
  header: ReportHeaderParams,
): string {
  const headerHtml = generateHeaderHtml(header, 'Property Management Summary');

  if (!data.hasData) {
    return wrapHtml('Property Management Summary', `
      ${headerHtml}
      <p class="empty-state">No items found.</p>
    `);
  }

  const summaryHtml = `
    <div class="overview-grid">
      <div class="card">
        <div class="card-label">Total Items</div>
        <div class="card-value">${data.totalItems}</div>
      </div>
      <div class="card">
        <div class="card-label">Total Market Value</div>
        <div class="card-value">${formatCents(data.totalMarketValueCents)}</div>
      </div>
    </div>
  `;

  const itemRows = data.items.map(renderPropertyManagementItemRow).join('');

  const itemsHtml = `
    <h2>Items</h2>
    <table>
      <thead>
        <tr>
          <th>Item</th>
          <th style="width:110px">Source</th>
          <th style="width:100px">SKU</th>
          <th style="width:110px">Space</th>
          <th class="right" style="width:110px">Market Value</th>
        </tr>
      </thead>
      <tbody>
        ${itemRows}
      </tbody>
    </table>
  `;

  return wrapHtml('Property Management Summary', `
    ${headerHtml}
    ${summaryHtml}
    ${itemsHtml}
    <div class="footer">Generated on ${new Date().toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric' })}</div>
  `);
}
