// DRAFT scaffold only — no MCP tool or Supabase call exists at this checkpoint.
//
// The implementation will define the gated rename_client target boundary. Its
// input carries OperationID, ClientID, validated replacement display text,
// captured milliseconds and expected revision as a canonical unsigned decimal
// string. Account and Principal come only from authenticated request context.
// A precision-safe canonical writer must emit the revision as the exact unquoted
// JSON integer token required by Swift without converting it to Number, then
// send the complete canonical command as RPC text and validate the immutable
// terminal result. App and MCP must share one contract and stable error set.
// O-042/O-043 must first settle lifecycle/no-change and display-name validity.
