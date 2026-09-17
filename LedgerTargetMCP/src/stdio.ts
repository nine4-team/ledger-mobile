import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { SupabasePropertyManagementReportReader } from "./propertyManagementReportRead.js";
import { createTargetServer } from "./server.js";
import { SupabaseClientSummaryPhysicalReportReader } from "./clientSummaryPhysicalReportRead.js";
import { SupabaseCategoryManagementApplier } from "./categoryManagement.js";
import { SupabaseTransactionReceiptReader } from "./transactionReceiptRead.js";
import { SupabaseTransactionDetailReader } from "./transactionDetailRead.js";
import { SupabaseInventorySaleService } from "./inventorySale.js";
import { SupabaseUninvoicedReturnService } from "./uninvoicedReturn.js";
import { SupabaseExpenseCreationService } from "./expenseCreation.js";
import { SupabaseCollectedInvoiceReader } from "./collectedInvoiceRead.js";
import { SupabaseLiveInvoiceReader } from "./liveInvoiceRead.js";
import { SupabaseInvoiceCreationService, SupabaseInvoiceRevisionService } from "./invoiceCreation.js";
import { SupabaseFeeCreationService } from "./feeCreation.js";
import { SupabaseFeeReader } from "./feeRead.js";

// One local process per user/account. Credentials are supplied by the launching
// host, never tool arguments. No token persistence or service-role fallback.
try {
  const reader = new SupabasePropertyManagementReportReader(
    new URL(process.env.LEDGER_TARGET_SUPABASE_URL ?? ""), process.env.LEDGER_TARGET_PUBLISHABLE_KEY ?? "");
  const context = await reader.resolveContext(process.env.LEDGER_TARGET_ACCOUNT_ID ?? "",
    process.env.LEDGER_TARGET_ACCESS_TOKEN ?? "");
  const clientSummaryReader = new SupabaseClientSummaryPhysicalReportReader(
    new URL(process.env.LEDGER_TARGET_SUPABASE_URL ?? ""), process.env.LEDGER_TARGET_PUBLISHABLE_KEY ?? "");
  const categoryManagement = new SupabaseCategoryManagementApplier(
    new URL(process.env.LEDGER_TARGET_SUPABASE_URL ?? ""), process.env.LEDGER_TARGET_PUBLISHABLE_KEY ?? "");
  const transactionReceipts = new SupabaseTransactionReceiptReader(
    new URL(process.env.LEDGER_TARGET_SUPABASE_URL ?? ""), process.env.LEDGER_TARGET_PUBLISHABLE_KEY ?? "");
  const transactionDetails = new SupabaseTransactionDetailReader(
    new URL(process.env.LEDGER_TARGET_SUPABASE_URL ?? ""), process.env.LEDGER_TARGET_PUBLISHABLE_KEY ?? "");
  const inventorySale = new SupabaseInventorySaleService(
    new URL(process.env.LEDGER_TARGET_SUPABASE_URL ?? ""), process.env.LEDGER_TARGET_PUBLISHABLE_KEY ?? "");
  const expenseCreation = new SupabaseExpenseCreationService(
    new URL(process.env.LEDGER_TARGET_SUPABASE_URL ?? ""), process.env.LEDGER_TARGET_PUBLISHABLE_KEY ?? "");
  const collectedInvoices = new SupabaseCollectedInvoiceReader(
    new URL(process.env.LEDGER_TARGET_SUPABASE_URL ?? ""), process.env.LEDGER_TARGET_PUBLISHABLE_KEY ?? "");
  const liveInvoices = new SupabaseLiveInvoiceReader(
    new URL(process.env.LEDGER_TARGET_SUPABASE_URL ?? ""), process.env.LEDGER_TARGET_PUBLISHABLE_KEY ?? "");
  const invoiceCreation = new SupabaseInvoiceCreationService(
    new URL(process.env.LEDGER_TARGET_SUPABASE_URL ?? ""), process.env.LEDGER_TARGET_PUBLISHABLE_KEY ?? "");
  const invoiceRevision = new SupabaseInvoiceRevisionService(
    new URL(process.env.LEDGER_TARGET_SUPABASE_URL ?? ""), process.env.LEDGER_TARGET_PUBLISHABLE_KEY ?? "");
  const feeCreation = new SupabaseFeeCreationService(
    new URL(process.env.LEDGER_TARGET_SUPABASE_URL ?? ""), process.env.LEDGER_TARGET_PUBLISHABLE_KEY ?? "");
  const fees = new SupabaseFeeReader(
    new URL(process.env.LEDGER_TARGET_SUPABASE_URL ?? ""), process.env.LEDGER_TARGET_PUBLISHABLE_KEY ?? "");
  const uninvoicedReturn = new SupabaseUninvoicedReturnService(
    new URL(process.env.LEDGER_TARGET_SUPABASE_URL ?? ""), process.env.LEDGER_TARGET_PUBLISHABLE_KEY ?? "");
  const server = createTargetServer(reader, context, clientSummaryReader, categoryManagement, transactionReceipts, transactionDetails, inventorySale, expenseCreation, expenseCreation, collectedInvoices, liveInvoices, invoiceCreation, feeCreation, fees, invoiceRevision, uninvoicedReturn, inventorySale, inventorySale);
  await server.connect(new StdioServerTransport());
} catch {
  process.stderr.write("Ledger target MCP could not start: check target configuration and user session.\n");
  process.exitCode = 1;
}
