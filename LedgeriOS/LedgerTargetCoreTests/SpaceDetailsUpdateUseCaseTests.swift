// Frozen executable obligations for space-details-update-use-case-contracts.
//
// Tests must independently prove exact raw empty/nil/whitespace/padded/interior-
// whitespace/long input; canonical conversion and newline-only name rejection;
// immutable replacement; duplicate-name validity without a query; reciprocal
// forwarding of every caller field including revision zero/UInt64.max; one
// complete name/notes payload and same-Space revision precondition; validation-
// before-call; exactly one port call; every receipt local state; mismatch,
// normalized/raw failure and Swift cancellation behavior; and permanent scope
// exclusions.
//
// Do not treat transient form input, reflection/encoding, an in-memory port, or
// a queued receipt as initial population, dirty/no-op policy, form restart,
// physical persistence, authorization, provider Sync, UI, migration, or
// production proof. The current EditSpaceDetailsModal remains only partially
// mapped source evidence and may not be promoted by this target-only slice.
