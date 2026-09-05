// READY scaffold only — executable tests begin only after the synchronized
// READY checkpoint and immutable CI pass.
//
// The frozen suite will count exactly one lifecycle owner, structured-database
// factory, attachment-database factory, query, store, and vault construction and
// prove no raw database/query/store/vault/key/path handle escapes it. It will derive
// contained opaque structured-database, attachment-database, and media-vault
// locations plus distinct SQLCipher/media-key identities from the exact
// validated environment, Principal, and Account scope. Factory capture must
// prove both SQLite databases receive identical SQLCipher key bytes, the media
// key bytes differ, equal injected key values refuse before storage opens, and
// each independently wrong key fails closed.
//
// It will use real encrypted stores to accept structured operations and captured
// attachment bytes, obtain exact clean and all-four-class pending summaries,
// preserve byte-identical summary evidence across ordinary close/reopen, and
// advance summary revision when equal-count evidence changes. Cross-Account,
// cross-Principal, wrong-key, missing/corrupt/orphaned-media, partial-open,
// observation, and close failures must remain explicit and never become a false
// clean result. All Client/Project creates, watches, capture, summary, diagnostic
// reads, and close share one lease gate: close cancels/drains watches, drains
// finite work, attempts both database closes in order, and stores one terminal
// result. Every operation after close refuses. The public surface must contain no
// destructive cleanup, provider signout, synchronization, upload verification,
// remote-success, or AccountSessionEnding operation.
