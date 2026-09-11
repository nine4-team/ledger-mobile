// DRAFT scaffold only: no executable Data API test exists at this checkpoint.
//
// The READY implementation may use only the disposable local Supabase stack and
// synthetic scoped-user tokens. It must call one scoped Space-create RPC with
// canonical command text, prove exact apply/replay/readback for both scopes,
// reject changed replay and unauthorized/cross-Account/missing-parent requests
// without enumeration, and prove direct writes remain denied. Hosted endpoints,
// service-role client shortcuts, production credentials, Firebase, migration,
// deployment, release, and cutover are prohibited.
