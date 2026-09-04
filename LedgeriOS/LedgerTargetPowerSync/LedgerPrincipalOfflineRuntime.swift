// READY scaffold only. Executable implementation begins only after the exact
// synchronized READY checkpoint and its immutable CI workflow pass.
//
// Planned boundary:
// - own one encrypted principal/environment bootstrap database namespace;
// - expose only the backend-neutral AccountQuerying port and local diagnostics;
// - reject environment or Principal rebinding before any database query;
// - inject query-specific readiness/freshness separately from database rows and
//   never restore current-ready authority solely from historical sync metadata;
// - keep account discovery separate from LedgerOfflineClientRuntime and from
//   workspace activation, authorization refresh, stream switching and teardown;
// - use the existing PowerSync schema's principal, Account and membership rows;
// - never create a first-membership or remembered-Account default; and
// - close without deleting local evidence by default.
//
// No hosted connector, credential, provider signout, database/key deletion or
// destructive session behavior is authorized by this scaffold.
