// READY scaffold only: no executable provider tests exist here yet.
//
// Implementation tests must prove exact same-Account/same-Client filtering over
// the real encrypted Project directory, active-only destinations, source and
// Business Inventory exclusion, duplicate-name identity safety, honest partial/
// stale/authoritative-empty states, and restart behavior where retained rows
// first emit incomplete/non-authoritative evidence and cannot become ready or
// authoritative-empty until new current-process completeness. Also required:
// malformed-evidence refusal, initial/disappearing/reappearing source absence, same-ID Client
// change resolved from the current row, current archived-source read evidence,
// complete-ready source absence, observer cancellation, and workspace close.
