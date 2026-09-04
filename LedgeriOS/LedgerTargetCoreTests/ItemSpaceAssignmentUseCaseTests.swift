// READY CONTRACT — ITEM SPACE ASSIGNMENT USE CASE TESTS
//
// This leaf is intentionally comment-only until its exact READY commit passes
// the complete conversion gate. Implementation may replace only this comment.
//
// The implementation suite must prove all of the following without changing
// any production or test path other than the paired use-case leaf:
//
// 1. An ordinary consumer imports LedgerTargetCore without @testable and uses
//    the exact public four-argument ItemSpaceAssignmentIntent initializer. The
//    intent is Equatable and Sendable, runtime non-Codable, and stores exactly
//    Account, placement scope, destination SpaceID, and typed Item/revision
//    candidates.
// 2. One exact represented active Space dispatches from ready, partial, and
//    stale validated directories. Its row revision alone becomes the expected
//    Space revision; zero and UInt64.max Space/Item revisions remain exact, and
//    differently ordered equivalent Item input reaches one canonical command.
// 3. Directory Account or scope mismatch, a missing destination row, empty or
//    duplicate Item selection, and every nonfinite capture time fail before any
//    assigner call. Missing-row failure says only not represented, including
//    for incomplete partial/stale evidence; it never asserts nonexistence.
// 4. Every LocalOperationState returns in the exact validated receipt after
//    exactly one call. Receipt OperationID mismatch fails after exactly one
//    call.
// 5. A reciprocal flattened encoded-leaf matrix independently varies Account,
//    Project-versus-Business-Inventory scope, destination SpaceID, directory-
//    supplied Space revision, every Item ID/revision, Operation, actor,
//    contract, and time. Each caller/evidence value reaches only its literal
//    owning command fields. Literal expectations must not be reconstructed by
//    ItemSpaceAssignmentDraft, AssignItemsToSpaceCommand, or production
//    validation logic.
// 6. All three ItemSpaceAssignmentUseCaseFailure values arise exactly before
//    the port. All 16 ItemSpaceAssignmentFailure values deliberately thrown by
//    the port remain exact, CancellationError stays structured cancellation,
//    and only an unknown port error maps to localAcceptanceFailed.
// 7. The three use-case and 16 operation diagnostic codes remain exact stable
//    privacy-safe enumerations.
// 8. Exact nested command topology contains only the verified assignment
//    draft/envelope/subject/fingerprint and Space/Item scope/revision
//    preconditions, with every clear, archive, media/marker, scope-movement,
//    accounting/provenance, UI, service, provider, and production field
//    excluded.
// 9. READY and implementation diffs obey their exact two-leaf allowlists and
//    preserve ItemSpaceAssignmentOperation/tests,
//    SpaceAssignmentDestinationData/tests, SpacePickerList,
//    InventoryItemsSubTab, TransactionDetailView, SpaceDetailView,
//    AddExistingItemsPicker, NewItemView, SharedItemsList, ItemsService, and
//    every source-app/MCP/provider surface.
// 10. Separate exact READY and implementation commits must pass immutable CI,
//     complete target tests with warnings as errors, conversion/isolation and
//     generated-contract controls, repeatable generation, both staging builds,
//     JSON validation, and clean tracked artifacts before promotion.
