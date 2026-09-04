// READY CONTRACT — ITEM SPACE CLEARING USE CASE TESTS
//
// This leaf is intentionally comment-only until its exact READY commit passes
// the complete conversion gate. Implementation may replace only this comment.
//
// The implementation suite must prove all of the following without changing
// any production or test path other than the paired use-case leaf:
//
// 1. An ordinary consumer imports LedgerTargetCore without @testable and uses
//    the exact public three-argument ItemSpaceClearingIntent initializer. The
//    intent is Equatable and Sendable, runtime non-Codable, and stores exactly
//    Account, placement scope, and typed Item/revision/current-Space candidates.
// 2. Project and Business Inventory input, one Item, mixed-current-Space bulk
//    input, differently ordered equivalent input, and zero/UInt64.max Item
//    revisions reach one exact canonical ClearItemSpaceAssignmentsCommand after
//    exactly one call. Account and scope reach only their literal owning fields.
// 3. Empty or duplicate Item selection and positive infinity, negative
//    infinity, or NaN capture time fail during draft/command construction before
//    any clearer call. Nil/no-current-Space intent is structurally
//    unrepresentable and creates no synthetic no-op receipt. Stale assigned-
//    looking evidence may dispatch and later conflict at authoritative apply.
// 4. Every LocalOperationState returns in the exact validated receipt after
//    exactly one call. Receipt OperationID mismatch fails after exactly one call.
// 5. A reciprocal flattened encoded-leaf matrix independently varies Account,
//    Project-versus-Business-Inventory scope, every Item ID/revision/current
//    Space, Operation, actor, contract, and time. Each caller value reaches only
//    its literal owning command fields. Literal expectations must not be rebuilt
//    by ItemSpaceClearingDraft, ClearItemSpaceAssignmentsCommand, or production
//    validation logic.
// 6. All 15 ItemSpaceClearingFailure values deliberately thrown by the port
//    remain exact, CancellationError stays structured cancellation, and only an
//    unknown port error maps to localAcceptanceFailed. Construction failures
//    remain outside that catch boundary and receipt validation remains after it.
// 7. All 15 operation diagnostic codes remain exact stable privacy-safe
//    enumerations.
// 8. Exact intent and nested command topology contains only the verified clear
//    draft/envelope/subject/fingerprint and scope/Item revision/current-Space
//    preconditions, with every destination assignment, archive, attachment,
//    marker mutation, scope movement, accounting/provenance, UI, service,
//    provider, credential, and production field excluded.
// 9. READY changes only these two comment scaffolds plus the named conversion
//    dossier/evidence/control artifacts. The later executable implementation
//    commit may replace only these exact two target leaves. Both preserve the
//    verified clearing operation/tests and assignment operation/use-case/
//    destination siblings unchanged, plus every enumerated source-app/test/MCP
//    clear-space surface and every provider surface at its frozen status.
//    Verified IDs: SWIFT-4C7158974133, TEST-0AB198EB6935,
//    SWIFT-4B007A00C393, TEST-51D893DD949E, SWIFT-0540BE125F5A,
//    TEST-DA67EAC9C2EF, SWIFT-164554FA1456, TEST-A3D73145E3EC.
//    Characterized IDs: SWIFT-0B434663295C, SWIFT-4C8A8E236450,
//    SWIFT-BDF8928A5FC7, SWIFT-DDFAC91775DA, SWIFT-AB578AEF4330,
//    SWIFT-F3BDD0968C6D, SWIFT-236679C7D427, SWIFT-C593225376EB,
//    TEST-8B555E151D8D, MCPMOD-82DC4C25B1B8.
//    Target-mapped IDs: SWIFT-4D0D546A02D8, SWIFT-C0ABD9666AE7,
//    SWIFT-47AEDE21C63C, TEST-6297E07C65AA, TEST-C1A3D3DA5E75,
//    MCPMOD-155A4AB80AC9.
// 10. Separate exact READY and implementation commits must pass immutable CI,
//     complete target tests with warnings as errors, conversion/isolation and
//     generated-contract controls, repeatable generation, both staging builds,
//     JSON validation, and clean tracked artifacts before promotion.
