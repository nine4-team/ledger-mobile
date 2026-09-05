// READY scaffold only — no network request or executable RPC adapter exists.
//
// The implementation may send one exact project-archive-v1 command through an
// injected scoped-user access token, validated target URL and publishable key.
// Expected UInt64 revision evidence must remain canonical decimal/JSON bytes
// without floating-point coercion. The adapter must validate exact Operation,
// Account, fingerprint, Project subject and known terminal result before success;
// empty/malformed credentials, response mismatch and unknown terminal codes fail
// closed. It cannot accept a service-role key, embed an endpoint, log command
// bytes/identities/credentials, or expose restore/delete/rename/reassignment.
