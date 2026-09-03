// READY CONTRACT — PROJECT RENAME USE CASE TESTS
//
// This leaf is intentionally comment-only until its exact READY commit passes
// the complete conversion gate. Implementation may replace only this comment.
//
// The implementation suite must prove all of the following without changing
// any production or test path other than the paired use-case leaf:
//
// 1. An ordinary consumer imports LedgerTargetCore without @testable and uses
//    the exact public four-argument ProjectRenameIntent initializer. The intent
//    is Equatable and Sendable, runtime non-Codable, and stores exactly Account,
//    Project, expected revision and already-validated ProjectDisplayName.
// 2. The typed ProjectDisplayName reaches the actual command byte-exactly,
//    including accepted outer/interior whitespace and more than 8 KiB Unicode;
//    this use case accepts no raw String and performs no second normalization.
// 3. Revisions zero and UInt64.max remain exact. Every LocalOperationState
//    returns in the exact validated receipt after exactly one rename call.
// 4. A reciprocal flattened encoded-leaf matrix independently varies Account,
//    Project, revision, display name, Operation, actor, contract and time. Each
//    caller value reaches only its literal expected owning command fields. The
//    baseline and all eight changed-leaf sets are literal; recording/canned
//    fakes and expectation helpers must not reconstruct expected values with
//    ProjectRenameDraft, RenameProjectCommand or production validation logic.
// 5. Positive infinity and NaN capture times fail during construction with
//    zero calls. A receipt OperationID mismatch fails after exactly one call.
// 6. All 12 ProjectRenameFailure values deliberately thrown by the port remain
//    exact, CancellationError stays structured cancellation, and only an
//    unknown port error maps to localAcceptanceFailed.
// 7. All 12 stable diagnostics remain an exact privacy-safe enumeration.
// 8. Exact nested command topology exposes only the existing rename fields and
//    same-Project revision precondition, with every broader edit/UI/service/
//    provider/production field excluded.
// 9. READY and implementation diffs obey their exact two-leaf allowlists and
//    preserve the statuses/content of EditProjectModal, ProjectDetailView,
//    ProjectDetailContainer, ProjectService and its protocol, Project model,
//    ProjectFormValidation/tests and update_project.
// 10. Separate exact READY and implementation commits must pass immutable CI,
//     complete target tests with warnings as errors, conversion/isolation and
//     generated-contract controls, repeatable generation, both staging builds,
//     JSON validation and clean tracked artifacts before promotion.
