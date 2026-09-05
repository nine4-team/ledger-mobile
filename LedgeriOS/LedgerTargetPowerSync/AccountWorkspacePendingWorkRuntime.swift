// READY scaffold only — executable runtime composition begins only after the
// synchronized READY checkpoint and immutable CI pass.
//
// This runtime-wide lifecycle owner will construct exactly one
// PendingWorkPowerSyncQuery, AttachmentCapturePowerSyncStore, and
// AttachmentLocalByteVault over the structured database and a separate local
// attachment queue in the same validated environment, Principal, and Account
// namespace. Both SQLite factories receive the same workspace SQLCipher key.
// The AES-GCM media key has a distinct Keychain identity and value; equality is
// rejected before any database or vault opens.
//
// One open/closing/closed lifecycle gate will cover every finite runtime call
// and every Client/Project watch, not only capture and summary. Close rejects new
// leases, cancels and drains watches, drains accepted finite work, attempts the
// attachment-database close and then the structured-database close even if the
// first fails, releases query/store/vault ownership, and stores one terminal
// success or bounded combined failure returned by every repeated close. Every
// post-close operation refuses.
//
// Bootstrap becomes async. It validates scope/locations/key separation before
// storage opens and, after any later failure, attempts to close every opened
// database in attachment-then-structured order, releases vault ownership, and
// reports the primary stage plus bounded cleanup outcomes without deleting
// either database, protected bytes, or either Keychain key.
//
// This is not AccountSessionEnding and will expose no endSession, synchronization,
// result resolution, provider signout, workspace switch, queue/media/database/
// key deletion, cache cleanup, destructive confirmation, Auth lease, hosted
// endpoint, migration, Firebase compatibility, production, or cutover behavior.
