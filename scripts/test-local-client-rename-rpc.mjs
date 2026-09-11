// DRAFT scaffold only: no executable local Data API test exists here yet.
//
// The implementation checkpoint must use only the disposable local Supabase
// stack and synthetic scoped-user tokens. It must call the Client-rename RPC
// with canonical JSON text (never a JavaScript Number for UInt64 revision),
// verify exact apply/replay/readback and current Project display behavior, run
// parallel same-revision calls, and prove restricted callers retain authorized
// same-Account reads but cannot rename or directly mutate, while revoked,
// anonymous and cross-Account requests fail without row/result enumeration.
// O-042/O-043 must first settle lifecycle/no-change and display-name validity.
// Hosted endpoints, production credentials and service-role client calls are
// prohibited.
