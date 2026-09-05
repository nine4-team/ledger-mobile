// READY scaffold only — the executable provider test suite is absent.
//
// Required deterministic coverage: exact command field/version/fingerprint and
// UInt64 revision boundaries; atomic encrypted acceptance/replay/restart; pending
// Project creation then archive FIFO; immediate directory Active-to-Archived and
// detail archived/partial projection; no false empty/ready authority; transient
// upload retention; applying/applied/rejected operation observation; exact result
// linkage; rejected-overlay rollback to refreshed active evidence; retry with a
// new OperationID and refreshed revision; applied waits for archived authoritative
// readback; stale readback retention; newer authority cleanup; no resurrection;
// malformed CRUD/overlay/result and unknown code refusal; unrelated queue progress;
// Account/Principal mismatch; cancellation, stream termination and runtime close
// drainage; and byte-for-byte preservation of every represented Project, Client,
// category/allocation and child/history field outside the allowed mutation set.
// Tests use only disposable encrypted databases and synthetic identities.
