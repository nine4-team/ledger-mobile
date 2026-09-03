// READY CONTRACT — PROJECT DETAILS UPDATE USE CASE TESTS
//
// This leaf is intentionally comment-only until its exact READY commit passes
// the complete conversion gate. Implementation may replace only this comment.
//
// The implementation suite must prove all of the following without changing
// any production or test path other than the paired use-case leaf:
//
// 1. This test leaf imports LedgerTargetCore without @testable and constructs
//    ProjectDetailsUpdateFormInput through its exact public four-argument
//    initializer. The input is Equatable and Sendable, is not Codable, has
//    exactly accountId, projectId, expectedRevision and rawDescription, and
//    preserves the caller's raw String bytes until canonical construction.
// 2. nil, empty and whitespace-only raw descriptions all dispatch the same
//    canonical clear replacement; padded descriptions trim only outer
//    whitespace/newlines; accepted interior text and more than 8 KiB of UTF-8
//    text survive through the actual command exactly, with no invented cap.
// 3. Expected revisions zero and UInt64.max remain exact.
// 4. A reciprocal flattened encoded-leaf matrix independently varies Account,
//    Project, revision, description, Operation, actor, contract and time. Each
//    caller value reaches only its existing owning command fields. Distinct raw
//    descriptions that normalize to the same replacement yield the identical
//    command and fingerprint.
// 5. Every LocalOperationState returns in the exact validated receipt after
//    exactly one ProjectDetailsUpdating.updateDetails call.
// 6. Both nonfinite captured-at forms fail during construction with zero port
//    calls. A receipt OperationID mismatch fails after exactly one call.
// 7. Every ProjectDetailsUpdateFailure deliberately returned by the port is
//    preserved, CancellationError remains structured cancellation, and only an
//    unknown port error maps to localAcceptanceFailed. Construction failures
//    are never caught and rewritten as port failures.
// 8. All 13 stable ProjectDetailsUpdateFailure diagnostics and the exact nested
//    encoded-command topology are exhaustive and reveal no raw error or
//    excluded rename, Client, category, allocation, budget, media, lifecycle,
//    child, accounting, history, UI, service-detail or production field.
// 9. The READY and implementation diffs obey their exact two-leaf allowlists;
//    the existing operation dependency remains verified and every source
//    EditProject/service/model/MCP surface retains its prior status.
// 10. Separate exact READY and implementation commits must pass immutable CI,
//     complete target tests with warnings as errors, conversion/isolation and
//     generated-contract controls, repeatable project generation, both staging
//     builds, JSON validation and clean tracked artifacts before promotion.
