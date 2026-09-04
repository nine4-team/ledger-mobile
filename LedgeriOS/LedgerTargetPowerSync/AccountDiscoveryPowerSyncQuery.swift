// READY scaffold only. Executable implementation begins only after the exact
// synchronized READY checkpoint and its immutable CI workflow pass.
//
// Planned boundary:
// - implement AccountQuerying over the principal bootstrap PowerSync rows;
// - bind every observation to one compiled environment and PrincipalID;
// - require the exact local Principal row as the bootstrap sentinel before any
//   snapshot can be complete;
// - derive visible Accounts only from active same-Principal membership joined
//   to visibility-safe Account metadata;
// - count membership rows before the Account join so delayed/malformed rows
//   cannot become an authoritative empty list;
// - combine local row changes with an injected, typed query-specific readiness
//   observation carrying both relationship completeness and freshness;
// - emit ready -> stale -> ready when freshness changes without any row change;
// - initialize a reopened cached database as partial or stale until the current
//   process receives fresh query-specific readiness; historical connection-wide
//   has-synced/last-synced state is never sufficient;
// - emit content-bound LocalDataVersion and honest partial/stale/ready quality;
// - preserve cached authorized rows for offline use without claiming fresh
//   server authorization;
// - convert local-database/readiness-source failure before cache into a bounded
//   failed update with no cached snapshot, and failure after cache into the same
//   bounded failure with the exact last snapshot retained; never expose raw
//   provider errors or convert either failure into authoritative empty; and
// - cancel both database and readiness observations with the consumer.
//
// This file must not create membership, choose an Account, activate a workspace,
// open protected Account data, or implement Auth/offline-lease policy.
