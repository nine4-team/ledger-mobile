// READY scaffold only: executable implementation begins only after independent
// review and an immutable ready-gate check.
//
// The bounded implementation will adapt the existing Account- and Principal-
// scoped local Project directory to the verified Transfer destination query.
// Caller fields provide only stable Account/Project request identity. On every
// update it must re-resolve that ProjectID and use the current directory row—
// never caller-stale Client/name/lifecycle—to build the canonical selection.
// Absent incomplete evidence emits zero candidates as incomplete; complete-
// ready absence fails boundedly. It preserves upstream evidence and owns no
// Transfer write.
