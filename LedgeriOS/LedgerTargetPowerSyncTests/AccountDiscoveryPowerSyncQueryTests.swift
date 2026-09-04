// READY scaffold only. Planned executable coverage:
// - zero/one/many/equal-name active memberships and deterministic ordering;
// - exact environment/Principal binding and cross-scope refusal;
// - inactive and other-Principal membership exclusion;
// - missing Principal sentinel never yields a complete snapshot;
// - membership-before-Account and malformed Account rows remain partial rather
//   than authoritative empty;
// - independently reactive typed query completeness/freshness, ready zero,
//   ready -> stale -> ready without row changes, restart initialized stale or
//   partial until fresh observation, and content-bound local-version transitions;
// - local read/readiness failure before cache emits a bounded failed update with
//   no snapshot; the same failure after a valid snapshot retains that exact
//   cached scope/content and never upgrades it or exposes a raw provider error;
// - explicit selection only from the exact current snapshot, with no automatic
//   first or remembered selection;
// - encrypted close/reopen with cached rows and readiness truth preserved;
// - poison/access-counting database proof that rejected Principal/environment
//   rebinding performs zero database access;
// - database/readiness cancellation and readiness-source termination; and
// - separation between local SQL scope proof and future hosted Sync/Auth proof.
