// READY scaffold only — no executable behavior.
//
// This leaf will derive one exact PendingLocalWorkSummary from the active,
// validated target environment/Principal/Account workspace. It must inspect
// every structured local-operation row and every still-present attachment
// durability row, including missing/corrupt byte evidence, and it must inspect
// the vault orphan inventory so queue-free orphaned bytes cannot appear clean.
// An orphan is unidentifiable as an exact Attachment and therefore refuses the
// summary rather than being guessed into a count. ps_crud, connectivity, or an
// assumed zero is never pending-work authority.
//
// A local-only observation journal will preserve the identical revision,
// observed-at time, and summary fingerprint while the underlying identity-
// bearing evidence is unchanged, and will advance monotonically when evidence
// changes even if counts do not. One actor-owned observation authority will
// serialize callers, commit the journal transactionally, and revalidate both
// stores after the journal commit; any change during either collection or
// journal commit causes bounded retry or refusal. Malformed, cross-scope,
// orphaned, overflow, database, attachment, or journal evidence must never
// become an authoritative all-zero summary.
//
// This provider will not synchronize, upload, delete, sign out, switch an
// Account, choose Auth/offline-lease policy, touch hosted services, or perform
// physical AccountSessionEnding behavior.
