// READY scaffold only — no executable operation-identity primitive exists here.
//
// The implementation will own one generic account-bound operation identity
// builder/validator used by both Project archive and Client archive. It accepts a
// fixed command-family prefix, exact AccountID and canonical UUID, and emits only
// `<prefix>-<sha256(account UTF-8)>-<lowercase canonical UUID>`. Prefixes are
// compile-time/internal trusted inputs, not caller-controlled arbitrary text.
// Validation must recompute the Account digest and canonical UUID byte-for-byte.
// ProjectArchiveOperationIdentity will delegate to this primitive with no public
// API or accepted-byte change; Client archive uses prefix `client-archive`.
