// READY scaffold only — no network request or executable RPC adapter exists.
//
// The implementation may send one exact client-archive-v1 command through an
// injected scoped-user access token, validated target URL and publishable key.
// Expected UInt64 revision evidence stays canonical decimal/JSON bytes without
// floating-point coercion. The adapter validates exact Operation, Account,
// fingerprint, Client subject and known terminal result before success; empty or
// malformed credentials, response mismatch and unknown terminal codes fail
// closed. It cannot accept a service-role key, embed an endpoint, log command
// bytes/identity/credentials, or expose restore/delete/rename/merge/reassignment.
